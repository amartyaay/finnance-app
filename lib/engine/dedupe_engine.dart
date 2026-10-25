import '../domain/enums.dart';
import '../domain/transaction.dart';
import '../services/sms/sender_registry.dart';

/// Merges alerts about the *same* real-world event.
///
/// The common Indian case: one UPI payment produces an SMS from the bank **and**
/// a card/wallet alert, sometimes with slightly different wording. Counting both
/// doubles the month's spend, which is the single most common complaint about
/// SMS-based trackers.
///
/// The rule is conservative — same amount, inside a short window, and a shared
/// account tail / card / merchant — but it does allow the *same* sender: one
/// payment often produces several alerts from the same header (a benefit card
/// repeating its notification, a term deposit closing into the savings account).
/// When two alerts match, the richer (or, for a closure, the larger) one is kept
/// and the other is marked — never silently dropped.
class DedupeEngine {
  const DedupeEngine({
    this.windowSeconds = 180,
    this.registry = const SenderRegistry(),
  });

  final int windowSeconds;
  final SenderRegistry registry;

  /// A term-deposit closure prints its own wording on the credit leg and a
  /// plain "debit by transfer" on the TD account leg.
  static final RegExp _closureWording = RegExp(
    r'\b(?:closure\s+of\s+(?:td|term\s+deposit)|td\s+closure|'
    r'term\s+deposit\s+closure)\b|\bon\s+account\s+of\s+closure\b',
    caseSensitive: false,
  );

  static final RegExp _maskTail = RegExp(r'[xX*]{2,}[\s-]*(\d{3,6})');
  static final RegExp _outVerb = RegExp(
    r'\b(?:debit(?:ed)?|spent|paid|withdrawn|withdrew)\b',
    caseSensitive: false,
  );
  static final RegExp _inVerb = RegExp(
    r'\b(?:credited|deposited|received)\b',
    caseSensitive: false,
  );

  List<Txn> mark(List<Txn> transactions) {
    final sorted = [...transactions]
      ..sort((a, b) => a.occurredAtMs.compareTo(b.occurredAtMs));

    // Pairwise evidence first (same event / opposite legs / closure legs), then
    // union the pairs. A term-deposit closure can print *three* alerts (a
    // generic credit, the TD debit, a detailed "Closure of TD" credit), so a
    // chain of two-way matches must resolve to one event rather than leaving a
    // winner that is itself somebody's duplicate.
    final parent = <String, String>{for (final txn in sorted) txn.key: txn.key};
    String find(String key) {
      var root = key;
      while (parent[root] != root) {
        root = parent[root]!;
      }
      // Path compression keeps repeated lookups cheap on a long inbox.
      var cursor = key;
      while (parent[cursor] != root) {
        final next = parent[cursor]!;
        parent[cursor] = root;
        cursor = next;
      }
      return root;
    }

    void union(String a, String b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[rb] = ra;
    }

    final pairs = <({String a, String b, bool closure, bool opposite})>[];
    for (var i = 0; i < sorted.length; i++) {
      final a = sorted[i];
      for (var j = i + 1; j < sorted.length; j++) {
        final b = sorted[j];
        if (b.occurredAtMs - a.occurredAtMs > windowSeconds * 1000) break;
        final closure = _closureLegs(a, b);
        final opposite = !closure && _oppositeLeg(a, b);
        if (!closure && !opposite && !_sameEvent(a, b)) continue;
        pairs.add((a: a.key, b: b.key, closure: closure, opposite: opposite));
        union(a.key, b.key);
      }
    }
    if (pairs.isEmpty) return sorted;

    final transferGroups = <String>{};
    final closureGroups = <String>{};
    for (final pair in pairs) {
      final root = find(pair.a);
      if (pair.closure || pair.opposite) transferGroups.add(root);
      if (pair.closure) closureGroups.add(root);
    }

    final members = <String, List<Txn>>{};
    for (final txn in sorted) {
      members.putIfAbsent(find(txn.key), () => <Txn>[]).add(txn);
    }

    final duplicates = <String, String>{}; // loser key -> winner key
    final rewritten = <String, Txn>{}; // survivor key -> corrected row
    for (final entry in members.entries) {
      final group = entry.value;
      if (group.length < 2) continue;
      final closure = closureGroups.contains(entry.key);
      var winner = group.first;
      for (final txn in group.skip(1)) {
        winner = closure ? _closureWinner(winner, txn) : _richer(winner, txn);
      }
      for (final txn in group) {
        if (identical(txn, winner)) continue;
        duplicates[txn.key] = winner.key;
      }
      if (transferGroups.contains(entry.key)) {
        // A debit alert and a credit alert for the same amount are one movement
        // between two of the user's accounts, never a spend plus an income.
        rewritten[winner.key] = winner.copyWith(
          kind: TxnKind.transfer,
          transferReason: TransferReason.selfTransfer,
        );
      }
    }

    return [
      for (final txn in sorted)
        duplicates.containsKey(txn.key)
            ? txn.copyWith(isDuplicateOfKey: duplicates[txn.key])
            : (rewritten[txn.key] ?? txn),
    ];
  }

  /// Two alerts from the same sender that carry two *different* reference ids
  /// are evidence of two separate charges — the only case that keeps the old
  /// same-sender exemption.
  bool _refsDistinguish(Txn a, Txn b) {
    return a.referenceId != null &&
        b.referenceId != null &&
        a.referenceId != b.referenceId;
  }

  /// Same sender, same amount, opposite direction, inside 120 s: the two legs of
  /// one internal transfer (bank debit alert + bank credit alert).
  bool _oppositeLeg(Txn a, Txn b) {
    if (a.sender == null || a.sender != b.sender) return false;
    if (a.amountPaise != b.amountPaise) return false;
    if ((b.occurredAtMs - a.occurredAtMs).abs() > 120 * 1000) return false;
    if (_refsDistinguish(a, b)) return false;
    final aOut = a.kind == TxnKind.spend || a.kind == TxnKind.cash;
    final bOut = b.kind == TxnKind.spend || b.kind == TxnKind.cash;
    return (aOut && b.kind == TxnKind.income) || (bOut && a.kind == TxnKind.income);
  }

  /// A term deposit closing produces two alerts seconds apart: the TD account is
  /// debited and the savings account is credited. They are one event, even when
  /// the principal and the interest print different figures (the larger is the
  /// transfer; the other is its duplicate).
  bool _closureLegs(Txn a, Txn b) {
    final aBody = a.rawBody;
    final bBody = b.rawBody;
    if (aBody == null || bBody == null) return false;
    if (a.sender == null || a.sender != b.sender) return false;
    if ((b.occurredAtMs - a.occurredAtMs).abs() > windowSeconds * 1000) {
      return false;
    }
    final aLower = aBody.toLowerCase();
    final bLower = bBody.toLowerCase();
    final aClosure = _closureWording.hasMatch(aLower);
    final bClosure = _closureWording.hasMatch(bLower);
    if (!aClosure && !bClosure) return false;

    // One leg must be the debit and the other the credit; two credits are two
    // separate inflow notices (ignored anyway), not a closure pair.
    final aDebit = _outVerb.hasMatch(aLower) && !_inVerb.hasMatch(aLower);
    final bDebit = _outVerb.hasMatch(bLower) && !_inVerb.hasMatch(bLower);
    if (aDebit == bDebit) return false;

    // The TD account mask is printed on both legs (`… TD A/c 493687` on the
    // credit, `A/C 493687 has a debit` on the debit). Sharing it is proof.
    final aTails = _maskTails(aBody);
    final bTails = _maskTails(bBody);
    if (aTails.intersection(bTails).isNotEmpty) return true;
    // Some banks omit the mask on one leg; both naming the closure is enough.
    return aClosure && bClosure;
  }

  Set<String> _maskTails(String body) {
    return {
      for (final match in _maskTail.allMatches(body)) match.group(1)!,
    };
  }

  bool _sameEvent(Txn a, Txn b) {
    if (a.amountPaise != b.amountPaise) return false;

    final sameSender = a.sender != null && a.sender == b.sender;
    if (sameSender && _refsDistinguish(a, b)) return false;
    if (a.kind != b.kind) return false;

    final debitLike = a.kind == TxnKind.spend || a.kind == TxnKind.cash;

    if (sameSender && debitLike) {
      // A repeated debit alert from the same sender, for the same amount, with
      // the same account tail and no distinguishing reference, is a duplicate
      // notification of one payment (Pluxee ₹408 ×2, 173 s apart), not a real
      // double charge. Two different references keep both rows.
      if (a.last4 != null && a.last4 == b.last4) return true;
      // Benefit / wallet / merchant senders only send notifications; they are
      // not authoritative for a second debit.
      if (_notificationSender(a) || _notificationSender(b)) return true;
      // No account tail on either alert: a bank repeating the same debit is the
      // one case that might be a genuine double charge (HDFCBK test), so keep
      // the historical exemption rather than guess.
      if (a.last4 == null && b.last4 == null) return false;
      // Different tails (bank account vs card) can still be the two views of
      // one payment, so fall through to the merchant/card checks below.
    }

    final sameRail = a.instrument == b.instrument &&
        a.last4 != null &&
        a.last4 == b.last4;
    // Two *different* rail references on the same tail are two payments.
    if (sameRail && _refsDistinguish(a, b)) return false;

    final sameCard = a.cardKey != null && a.cardKey == b.cardKey;
    if (sameCard || sameRail) return true;
    if (_merchantSimilarity(a.merchant, b.merchant) >= 0.6) return true;
    if (_tokenOverlap(a.merchant, b.merchant)) return true;

    // A card-bill payment is reported twice — by the bank (account debited) and
    // by the issuer (limit restored). The same amount inside the window is one
    // payment, whichever tail each alert prints.
    if (a.transferReason == TransferReason.creditCardBill &&
        b.transferReason == TransferReason.creditCardBill) {
      return true;
    }

    // Bank view + card/wallet view of one payment: same amount, one side richer.
    final oneMissingMerchant =
        (a.merchant?.isNotEmpty != true) != (b.merchant?.isNotEmpty != true);
    return oneMissingMerchant && a.instrument != b.instrument;
  }

  /// Senders that report events but never raise a second independent charge:
  /// merchant receipts, benefit/flexi cards and wallets.
  bool _notificationSender(Txn txn) {
    final sender = txn.sender;
    if (sender == null) return false;
    final id = registry.resolve(sender);
    return registry.isMerchantReceiptSender(id) ||
        registry.isBenefitCardSender(id) ||
        id.entityKind == 'wallet';
  }

  /// A shared long token is enough for merchant strings that differ in shape:
  /// `SREE KRISHNA STORES` vs `Sreekrishna` (dup-wallet-upi-150).
  bool _tokenOverlap(String? left, String? right) {
    if (left == null || right == null) return false;
    final a = _normalise(left);
    final b = _normalise(right);
    if (a.length < 5 || b.length < 5) return false;
    for (final token in left.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
      if (token.length >= 5 && b.contains(token)) return true;
    }
    for (final token in right.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
      if (token.length >= 5 && a.contains(token)) return true;
    }
    return false;
  }

  Txn _richer(Txn a, Txn b) => _score(a) >= _score(b) ? a : b;

  /// For a closure with unequal principal/interest legs, the larger amount is
  /// the transfer and the smaller row is its duplicate.
  Txn _closureWinner(Txn a, Txn b) {
    if (a.amountPaise != b.amountPaise) {
      return a.amountPaise > b.amountPaise ? a : b;
    }
    return _richer(a, b);
  }

  int _score(Txn txn) {
    return (txn.merchant?.isNotEmpty == true ? 2 : 0) +
        (txn.cardKey != null ? 2 : 0) +
        (txn.referenceId != null ? 1 : 0) +
        (txn.availableLimitPaise != null ? 1 : 0) +
        (txn.instrument == Instrument.upi ? 1 : 0);
  }

  double _merchantSimilarity(String? left, String? right) {
    if (left == null || right == null) return 0;
    final a = _normalise(left);
    final b = _normalise(right);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    if (a.length >= 4 && b.length >= 4 && (a.contains(b) || b.contains(a))) {
      return 0.8;
    }
    return 0;
  }

  static String _normalise(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

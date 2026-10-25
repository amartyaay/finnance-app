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

  /// Card-bill payments are notified **twice**, by two different senders, and
  /// the two alerts are usually hours apart: the bank account debit ("paid
  /// Rs 3,772 to HDFC Card") and the issuer's "Payment of Rs 3,772 received on
  /// your HDFC Credit Card XX4821". The general [windowSeconds] is deliberately
  /// short, so this narrow rule pairs a bill payment by amount alone, up to two
  /// days apart, and never widens the window for any other kind of row.
  static const int billWindowSeconds = 48 * 60 * 60;

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

    // Second pass, card bills only: same amount, both issuer/or bank legs of a
    // bill payment, up to 48 hours apart, regardless of sender. This is a
    // separate, narrow rule — the general window above is unchanged.
    final billByAmount = <int, List<Txn>>{};
    for (final txn in sorted) {
      if (txn.transferReason == TransferReason.creditCardBill) {
        billByAmount.putIfAbsent(txn.amountPaise, () => <Txn>[]).add(txn);
      }
    }
    for (final group in billByAmount.values) {
      if (group.length < 2) continue;
      for (var i = 0; i < group.length; i++) {
        for (var j = i + 1; j < group.length; j++) {
          if (group[j].occurredAtMs - group[i].occurredAtMs >
              billWindowSeconds * 1000) {
            break;
          }
          // Two alerts that print two different reference ids are two genuine
          // payments of the same amount, not one event notified twice.
          if (_refsDistinguish(group[i], group[j])) continue;
          pairs.add(
            (a: group[i].key, b: group[j].key, closure: false, opposite: false),
          );
          union(group[i].key, group[j].key);
        }
      }
    }
    // The very same alert text (tracking link aside) from the same bank for the
    // same amount is one event re-sent, even when the copies are 12 minutes
    // apart (HDFC's refund alert from VD-HDFCBK and again from VM-HDFCBK).
    final bySignature = <String, Txn>{};
    for (final txn in sorted) {
      final body = txn.rawBody;
      if (body == null || txn.sender == null) continue;
      final signature = '${txn.sender}|${txn.amountPaise}|${_bodySignature(body)}';
      final earlier = bySignature[signature];
      if (earlier != null &&
          txn.occurredAtMs - earlier.occurredAtMs <= 60 * 60 * 1000) {
        pairs.add((a: earlier.key, b: txn.key, closure: false, opposite: false));
        union(earlier.key, txn.key);
      }
      bySignature[signature] = txn;
    }

    // Receipts: a biller's "Recharge of INR 361 successful" is folded into the
    // bank/card alert for the same payment — the same amount (to the rupee)
    // within a day, or from the same merchant within 3 days (3 % fee slack
    // only inside two hours). Only a receipt
    // that no alert covers survives, which is exactly when it is the only
    // record of the payment. Two receipts for one payment ("we have processed
    // Rs 2249" + "Recharge of INR 2,249 successful") are one as well.
    const receiptWindowMs = 3 * 24 * 60 * 60 * 1000;
    final receipts =
        sorted.where((t) => t.sourceType == TxnSourceType.receipt).toList();
    for (final receipt in receipts) {
      Txn? match;
      for (final other in sorted) {
        // A payment receipt pairs with a debit; a merchant's "refund
        // processed" pairs with the bank's refund credit.
        if (identical(other, receipt) || _isInflow(other) != _isInflow(receipt)) {
          continue;
        }
        final gapMs = (other.occurredAtMs - receipt.occurredAtMs).abs();
        if (gapMs > receiptWindowMs) continue;
        final diff = (other.amountPaise - receipt.amountPaise).abs();
        // The same merchant may differ by fees (3 %); anyone else must match
        // to the rupee and within a day, or a ₹417 Swiggy receipt is swallowed
        // by an unrelated ₹410 payment two days later.
        final sameMerchant =
            _merchantSimilarity(other.merchant, receipt.merchant) >= 0.6 ||
            _tokenOverlap(other.merchant, receipt.merchant);
        // Two Swiggy orders of ₹417 and ₹404 a day apart are two orders, so
        // fee slack applies only within two hours.
        final close = sameMerchant
            ? diff <= 100 ||
                  (diff <= (receipt.amountPaise * 0.03).round() &&
                      gapMs <= 2 * 60 * 60 * 1000)
            : diff <= 100 && gapMs <= 24 * 60 * 60 * 1000;
        if (!close) continue;
        if (other.sourceType == TxnSourceType.receipt) {
          // Pair receipt-with-receipt once (earlier first), only within an
          // hour, and never across two order ids: two ₹49 Airtel recharges
          // on two days are two recharges.
          if (other.occurredAtMs > receipt.occurredAtMs) continue;
          if (gapMs > 60 * 60 * 1000) continue;
          if (_refsDistinguish(other, receipt) &&
              _isInflow(receipt) == _isInflow(other) &&
              other.sender == receipt.sender) {
            continue;
          }
        }
        // Prefer a bank alert over another receipt, then the closest in time.
        if (match == null ||
            (match.sourceType == TxnSourceType.receipt &&
                other.sourceType != TxnSourceType.receipt) ||
            (match.sourceType == other.sourceType &&
                (other.occurredAtMs - receipt.occurredAtMs).abs() <
                    (match.occurredAtMs - receipt.occurredAtMs).abs())) {
          match = other;
        }
      }
      if (match != null) {
        pairs.add((a: match.key, b: receipt.key, closure: false, opposite: false));
        union(match.key, receipt.key);
      }
    }

    // One bank moving money between two of the user's own accounts can print
    // the legs minutes apart (SBI: "A/C …5650 has a debit by transfer of Rs
    // 1,02,794.00 … Avl Bal Rs 0.00" then "A/C …4642 Credited INR 1,02,794.00
    // … Deposit by transfer from Mr. <you>"). Same sender, same amount,
    // opposite directions, neither naming a merchant, within 30 minutes.
    for (var i = 0; i < sorted.length; i++) {
      final a = sorted[i];
      if (a.merchant != null || a.sender == null) continue;
      for (var j = i + 1; j < sorted.length; j++) {
        final b = sorted[j];
        if (b.occurredAtMs - a.occurredAtMs > 30 * 60 * 1000) break;
        if (b.merchant != null || b.sender != a.sender) continue;
        if (b.amountPaise != a.amountPaise) continue;
        if (_isInflow(a) == _isInflow(b)) continue;
        if (_refsDistinguish(a, b)) continue;
        pairs.add((a: a.key, b: b.key, closure: false, opposite: true));
        union(a.key, b.key);
      }
    }

    // Third pass: one UPI/IMPS reference printed by two banks — the debit leg
    // at one and the credit leg at the other (SBI "trf to Bank Account …
    // Refno 649507747508" + HDFC "credited … (UPI 649507747508)"). The same
    // long reference, the same amount and opposite directions within a day is
    // one movement between the user's own accounts.
    final byRef = <String, List<Txn>>{};
    for (final txn in sorted) {
      final ref = txn.referenceId;
      if (ref == null || ref.length < 10) continue;
      byRef.putIfAbsent(ref, () => <Txn>[]).add(txn);
    }
    for (final group in byRef.values) {
      for (var i = 0; i < group.length; i++) {
        for (var j = i + 1; j < group.length; j++) {
          final a = group[i];
          final b = group[j];
          if (a.amountPaise != b.amountPaise) continue;
          if (b.occurredAtMs - a.occurredAtMs > 24 * 60 * 60 * 1000) continue;
          if (_isInflow(a) == _isInflow(b)) continue;
          pairs.add((a: a.key, b: b.key, closure: false, opposite: true));
          union(a.key, b.key);
        }
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
      // Any group that contains an issuer's card-bill confirmation is a
      // bill-payment group, however it was paired (the 48-hour amount pass, or
      // the general window when the two alerts are seconds apart).
      final bill = group.any(
        (t) => t.transferReason == TransferReason.creditCardBill,
      );
      Txn winner;
      if (closure) {
        winner = group.first;
        for (final txn in group.skip(1)) {
          winner = _closureWinner(winner, txn);
        }
      } else if (bill) {
        // A card-bill group keeps the issuer leg: it carries the cardKey, and
        // that is the leg the card screens use to clear the outstanding bill.
        winner = _billWinner(group);
      } else {
        winner = group.first;
        for (final txn in group.skip(1)) {
          winner = _richer(winner, txn);
        }
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

  static bool _isInflow(Txn txn) =>
      txn.kind == TxnKind.income || txn.moneyInKind != MoneyInKind.none;

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
    // A transfer counts as the outgoing leg: a TD debit parses as `transfer`
    // while its credit leg parses as `income`, and they are one event.
    bool out(TxnKind kind) =>
        kind == TxnKind.spend || kind == TxnKind.cash || kind == TxnKind.transfer;
    final aOut = out(a.kind);
    final bOut = out(b.kind);
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
    // The very same alert text, from the same sender, for the same amount: one
    // event notified twice (a fund house re-sending its SIP confirmation two
    // minutes later). This is the only same-sender merge that needs no merchant.
    if (sameSender &&
        a.rawBody != null &&
        b.rawBody != null &&
        _bodySignature(a.rawBody!) == _bodySignature(b.rawBody!)) {
      return true;
    }
    if (a.kind != b.kind) return false;

    final bothCardBill =
        a.transferReason == TransferReason.creditCardBill &&
        b.transferReason == TransferReason.creditCardBill;
    final merchantSame = bothCardBill ||
        _merchantSimilarity(a.merchant, b.merchant) >= 0.6 ||
        _tokenOverlap(a.merchant, b.merchant);
    final oneMissingMerchant =
        (a.merchant?.isNotEmpty != true) != (b.merchant?.isNotEmpty != true);
    // Same amount is never enough on its own. Two genuine ₹500 buys at two
    // different shops seconds apart must both survive — silently deleting the
    // second is the double-charge failure this app exists to catch.
    final merchantOk = merchantSame || oneMissingMerchant;

    final debitLike = a.kind == TxnKind.spend || a.kind == TxnKind.cash;

    // Two *movements* (not purchases) from the same bank, for the same amount,
    // with no merchant and no reference either side, inside the window: one
    // event notified twice. A SIP confirmation re-sent two minutes later with a
    // fresh tracking link is the real case; a spend is never merged this way.
    if (sameSender &&
        !debitLike &&
        a.merchant == null &&
        b.merchant == null &&
        a.referenceId == null &&
        b.referenceId == null) {
      return true;
    }

    if (sameSender && debitLike) {
      if (!merchantOk) return false;
      // A repeated debit alert from the same sender, for the same amount, with
      // the same account tail and the same merchant is a duplicate notification
      // of one payment (Pluxee ₹408 ×2, 173 s apart), not a real double charge.
      if (a.last4 != null && a.last4 == b.last4) return true;
      // Benefit / wallet / merchant senders only send notifications; they are
      // not authoritative for a second debit — but only at the same merchant.
      if (_notificationSender(a) || _notificationSender(b)) return true;
      // No account tail on either alert: a bank repeating the same debit is the
      // one case that might be a genuine double charge, so keep both rows.
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
    if (sameCard || sameRail) return merchantOk;
    if (merchantSame) return true;

    // A card-bill payment is reported twice — by the bank (account debited) and
    // by the issuer (limit restored). The same amount inside the window is one
    // payment, whichever tail each alert prints.
    if (a.transferReason == TransferReason.creditCardBill &&
        b.transferReason == TransferReason.creditCardBill) {
      return true;
    }

    // Bank view + card/wallet view of one payment: same amount, one side richer.
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

  /// The leg of a card-bill group that must survive: the issuer confirmation,
  /// identified by a `cardKey`. Keeping the funding-account debit instead hides
  /// the payment from the card, and a paid bill keeps showing as due.
  Txn _billWinner(List<Txn> group) {
    Txn? best;
    for (final txn in group) {
      if (txn.transferReason != TransferReason.creditCardBill) continue;
      if (best == null || _billScore(txn) > _billScore(best)) best = txn;
    }
    if (best != null) return best;
    // No bill leg in the group (cannot happen for a bill seed): use the normal
    // richer-row rule rather than dropping the event.
    return group.reduce(_richer);
  }

  int _billScore(Txn txn) =>
      (txn.cardKey != null ? 4 : 0) +
      (txn.instrument == Instrument.creditCard ? 2 : 0) +
      (txn.issuer != null ? 1 : 0) +
      (txn.availableLimitPaise != null ? 1 : 0);

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
    // A bank/card alert always beats a biller's receipt for the same payment.
    if (txn.sourceType == TxnSourceType.receipt) return -10;
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

  /// The alert text without its tracking link: HDFC re-sends one refund from
  /// two headers with two different short links, and that is one refund.
  static String _bodySignature(String body) => body
      .toLowerCase()
      .replaceAll(RegExp(r'https?://\S+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

import '../domain/enums.dart';
import '../domain/statement.dart';
import '../domain/transaction.dart';

/// The days one imported account's statements cover, inclusive.
class StatementCoverage {
  const StatementCoverage({
    required this.accountKey,
    required this.bank,
    required this.accountMask,
    required this.from,
    required this.to,
  });

  final String accountKey;
  final String bank;
  final String? accountMask;

  /// Calendar days (time of day ignored).
  final DateTime from;
  final DateTime to;

  bool coversDay(DateTime at) {
    final day = DateTime(at.year, at.month, at.day);
    return !day.isBefore(DateTime(from.year, from.month, from.day)) &&
        !day.isAfter(DateTime(to.year, to.month, to.day));
  }
}

/// One ledger from two sources. An imported bank statement is the single
/// source of truth for the days it covers: **every** bank-account SMS on
/// those days (this bank's and any other bank's, UPI, debit card, receipts)
/// gives way to it. Credit cards and wallets are not in a bank statement, so
/// their SMS stay; the statement shows one big card-bill payment, and the
/// card's own alerts say what it paid for. Days the statement does not cover
/// (this month, after the file ends) are SMS as before.
///
/// The decisions the SMS ledger already made are kept:
/// - a replaced alert that was a duplicate of another sender's alert (the
///   bank leg of a card bill, whose issuer confirmation survives) hands that
///   status to its statement row;
/// - a category the user chose on the alert stays on the statement row.
/// When the bank's SMS never arrived, a card-bill row still pairs with the
/// issuer's "payment received", so the bill is counted once.
class StatementMerge {
  const StatementMerge();

  List<Txn> merge({
    required List<Txn> sms,
    required List<StatementCoverage> coverage,
    required Map<String, List<StatementRow>> rows,
  }) {
    if (coverage.isEmpty) return sms;

    // 1. Bank alerts on covered days step aside. The statement's own
    //    account's alerts are kept aside for matching (clock, category,
    //    duplicate status); other banks' are simply dropped.
    final replaced = <String, List<Txn>>{};
    final dropped = <String>{};
    final kept = <Txn>[];
    for (final txn in sms) {
      final covering = coverage.where((c) => c.coversDay(txn.occurredAt));
      if (covering.isEmpty || _isCardOrWallet(txn)) {
        kept.add(txn);
        continue;
      }
      final owner = covering.where((c) => _fromAccount(txn, c)).firstOrNull;
      if (owner == null) {
        // Another bank's account, fed from the statement account. Its
        // debits still say where that money went (see [_otherBank]); its
        // credits are the statement's own transfers arriving, and receipts
        // repeat what the statement already shows.
        final routed = _sameBank(txn, covering) ? null : _otherBank(txn);
        if (routed == null) {
          dropped.add(txn.key);
        } else {
          kept.add(routed);
        }
      } else {
        replaced.putIfAbsent(owner.accountKey, () => []).add(txn);
      }
    }
    final replacedKeys = {
      ...dropped,
      for (final list in replaced.values)
        for (final t in list) t.key,
    };

    // 2. Statement rows become ledger rows, each matched to the alert it
    //    replaces (same amount and direction, within two days).
    final fromStatement = <Txn>[];
    final remap = <String, String>{}; // replaced SMS key -> statement key
    for (final c in coverage) {
      final pool = [...?replaced[c.accountKey]];
      for (final row in rows[c.accountKey] ?? const <StatementRow>[]) {
        if (!c.coversDay(row.date)) continue;
        final amount = row.isDebit ? row.debitPaise : row.creditPaise;
        if (amount <= 0) continue;
        Txn? match;
        var best = 3 * 24 * 3600 * 1000;
        for (final t in pool) {
          if (t.amountPaise != amount || _isInflow(t) == row.isDebit) continue;
          final gap = (t.occurredAt.difference(_noon(row.date)).inMilliseconds)
              .abs();
          if (gap < best) {
            best = gap;
            match = t;
          }
        }
        if (match != null) pool.remove(match);
        final txn = _toTxn(row, c, match, replacedKeys);
        if (match != null) remap[match.key] = txn.key;
        fromStatement.add(txn);
      }
    }

    // 3. Alerts that pointed at a replaced alert now point at its statement
    //    row (they stay duplicates either way).
    //    A card alert that deferred to a bank alert with no statement row
    //    to inherit from would vanish with it; it counts again instead.
    final out = <Txn>[
      for (final t in kept)
        if (t.isDuplicateOfKey != null && remap.containsKey(t.isDuplicateOfKey))
          t.copyWith(isDuplicateOfKey: remap[t.isDuplicateOfKey])
        else if (t.isDuplicateOfKey != null &&
            replacedKeys.contains(t.isDuplicateOfKey))
          _undup(t)
        else
          t,
    ];

    // 4. Rows whose alert never arrived: a card bill pairs with the issuer's
    //    confirmation; a merchant receipt folds into the statement row.
    final claimed = {
      for (final t in fromStatement)
        if (t.isDuplicateOfKey != null) t.isDuplicateOfKey!,
    };
    for (var i = 0; i < fromStatement.length; i++) {
      final s = fromStatement[i];
      if (s.isDuplicateOfKey != null) continue;
      // A debit with the exact amount of a card's "payment received" is that
      // bill, whatever the narration says ("trf to PhonePe", "CRED").
      if (!_isInflow(s)) {
        final issuer = out
            .where(
              (t) =>
                  t.isDuplicateOfKey == null &&
                  !claimed.contains(t.key) &&
                  t.moneyInKind == MoneyInKind.cardPayment &&
                  t.amountPaise == s.amountPaise &&
                  t.occurredAt.difference(s.occurredAt).inDays.abs() <= 3,
            )
            .firstOrNull;
        if (issuer != null) {
          claimed.add(issuer.key);
          fromStatement[i] = s.copyWith(
            kind: TxnKind.transfer,
            transferReason: TransferReason.creditCardBill,
            isDuplicateOfKey: issuer.key,
          );
          continue;
        }
      }
      if (s.kind == TxnKind.spend) {
        for (var j = 0; j < out.length; j++) {
          final r = out[j];
          if (r.sourceType != TxnSourceType.receipt ||
              r.isDuplicateOfKey != null ||
              r.amountPaise != s.amountPaise ||
              r.occurredAt.difference(s.occurredAt).inHours.abs() > 36) {
            continue;
          }
          out[j] = r.copyWith(isDuplicateOfKey: s.key);
          break;
        }
      }
    }

    for (var j = 0; j < out.length; j++) {
      final t = out[j];
      if (t.sourceType != TxnSourceType.sms ||
          t.transferReason != TransferReason.creditCardBill ||
          _isInflow(t) ||
          t.cardKey != null ||
          !coverage.any((c) => c.coversDay(t.occurredAt))) {
        continue;
      }
      final bank = (t.issuer ?? '').toLowerCase();
      final cards = {
        for (final o in out)
          if (o.cardKey != null &&
              bank.isNotEmpty &&
              o.cardKey!.toLowerCase().startsWith(bank.split(' ').first))
            o.cardKey!,
      };
      var updated = cards.length == 1 ? t.copyWith(cardKey: cards.first) : t;
      if (updated.isDuplicateOfKey == null) {
        final issuer = out
            .where(
              (o) =>
                  o.isDuplicateOfKey == null &&
                  !claimed.contains(o.key) &&
                  o.moneyInKind == MoneyInKind.cardPayment &&
                  o.amountPaise == t.amountPaise &&
                  o.occurredAt.difference(t.occurredAt).inDays.abs() <= 3,
            )
            .firstOrNull;
        if (issuer != null) {
          claimed.add(issuer.key);
          updated = updated.copyWith(isDuplicateOfKey: issuer.key);
        }
      }
      out[j] = updated;
    }

    out.addAll(fromStatement);
    out.sort((a, b) => a.occurredAtMs.compareTo(b.occurredAtMs));
    return out;
  }

  /// The statement's own bank, another account (its FDs and RDs): the
  /// statement already shows every movement into and out of them.
  static bool _sameBank(Txn txn, Iterable<StatementCoverage> covering) {
    for (final c in covering) {
      final probe = StatementCoverage(
        accountKey: c.accountKey,
        bank: c.bank,
        accountMask: null,
        from: c.from,
        to: c.to,
      );
      if (_fromAccount(txn, probe)) return true;
    }
    return false;
  }

  static final RegExp _investmentWords = RegExp(
    r'mutual\s*fund|\bumrn\b|\bsip\b|\bnach\b|\bach\b|asset\s*manag|'
    r'debit\s*mandate|nippon|\bamc\b|'
    r'groww|zerodha|upstox|iccl|indian clearing|kfin|cams',
    caseSensitive: false,
  );

  /// A debit from another bank account the user tops up from the statement
  /// account (the owner's HDFC account): mandates to mutual funds are the
  /// investments it exists for; anything else leaving it is taken to be that
  /// bank's credit-card bill. Neither is spend: the purchases are on the card.
  /// Credits and receipts are dropped (null).
  static Txn? _otherBank(Txn txn) {
    if (txn.sourceType != TxnSourceType.sms) return null;
    if (_isInflow(txn)) return null;
    // Only a bank account alert names an account; a biller's message does not.
    if (txn.last4 == null || txn.issuer == null) return null;
    final body = txn.rawBody ?? '';
    final investment =
        txn.transferReason == TransferReason.investment ||
        _investmentWords.hasMatch(body) ||
        _investmentWords.hasMatch(txn.merchant ?? '');
    return txn.copyWith(
      kind: TxnKind.transfer,
      transferReason: investment
          ? TransferReason.investment
          : TransferReason.creditCardBill,
      categoryName: investment ? 'Investments' : 'Transfers',
      categoryKind: investment
          ? SpendCategoryKind.investments
          : SpendCategoryKind.transfers,
      merchant: investment ? null : '${txn.issuer ?? 'Card'} card bill',
      needsReview: false,
    );
  }

  /// Not in a bank statement: a credit card (not a debit card), a card
  /// issuer's own alert, or a wallet / meal card.
  static bool _isCardOrWallet(Txn txn) {
    if (txn.sourceType == TxnSourceType.statement) return false;
    // "Payment of INR … received towards your Axis Bank Credit Card": the
    // card's side of a bill payment, which the statement shows only as a debit.
    if (txn.moneyInKind == MoneyInKind.cardPayment) return true;
    if (txn.instrument == Instrument.creditCard ||
        txn.instrument == Instrument.wallet) {
      return true;
    }
    final debitCard =
        txn.instrument == Instrument.debitCard ||
        txn.instrument == Instrument.atm;
    if (txn.cardKey != null && !debitCard) return true;
    return (txn.issuer ?? '').toLowerCase().contains('card');
  }

  static Txn _undup(Txn t) => Txn(
    key: t.key,
    occurredAtMs: t.occurredAtMs,
    amountPaise: t.amountPaise,
    kind: t.kind,
    instrument: t.instrument,
    id: t.id,
    smsId: t.smsId,
    sender: t.sender,
    merchant: t.merchant,
    counterpartyVpa: t.counterpartyVpa,
    categoryId: t.categoryId,
    categoryName: t.categoryName,
    categorySource: t.categorySource,
    categoryKind: t.categoryKind,
    transferReason: t.transferReason,
    moneyInKind: t.moneyInKind,
    cardKey: t.cardKey,
    last4: t.last4,
    issuer: t.issuer,
    referenceId: t.referenceId,
    balanceAfterPaise: t.balanceAfterPaise,
    availableLimitPaise: t.availableLimitPaise,
    confidence: t.confidence,
    amountScore: t.amountScore,
    sourceType: t.sourceType,
    needsReview: t.needsReview,
    rawBody: t.rawBody,
  );

  /// An alert about this account: from the same bank, not a card, and naming
  /// this account's tail (or no account at all).
  static bool _fromAccount(Txn txn, StatementCoverage c) {
    if (txn.sourceType != TxnSourceType.sms) return false;
    // A debit card spends from this account (its number is the card's, not
    // the account's); a credit card is a different ledger altogether.
    final debitCard =
        txn.instrument == Instrument.debitCard ||
        txn.instrument == Instrument.atm;
    if (txn.instrument == Instrument.creditCard) return false;
    if (txn.cardKey != null && !debitCard) return false;
    if ((txn.issuer ?? '').toLowerCase().contains('card')) return false;
    final bank = c.bank.toLowerCase();
    final issuer = (txn.issuer ?? '').toLowerCase();
    final sender = (txn.sender ?? '').toLowerCase();
    final sameBank = bank == 'sbi'
        ? ((issuer.contains('sbi') || issuer.contains('state bank')) &&
                  !issuer.contains('card')) ||
              (issuer.isEmpty &&
                  sender.contains('sbi') &&
                  !sender.contains('crd'))
        : issuer.contains(bank) || (issuer.isEmpty && sender.contains(bank));
    if (!sameBank) return false;
    final mask = c.accountMask;
    final tail = txn.last4;
    if (mask == null || tail == null || debitCard) return true;
    return mask.endsWith(tail) || tail.endsWith(mask);
  }

  static bool _isInflow(Txn txn) => switch (txn.kind) {
    TxnKind.income => true,
    TxnKind.transfer => txn.moneyInKind.isInflow,
    _ => false,
  };

  static DateTime _noon(DateTime day) =>
      DateTime(day.year, day.month, day.day, 12);

  Txn _toTxn(
    StatementRow row,
    StatementCoverage c,
    Txn? alert,
    Set<String> replacedKeys,
  ) {
    final debit = row.isDebit;
    final amount = debit ? row.debitPaise : row.creditPaise;
    final (kind, reason, moneyIn) = switch (row.kind) {
      StatementKind.spend ||
      StatementKind.charges ||
      StatementKind.otherDebit => (
        TxnKind.spend,
        TransferReason.none,
        MoneyInKind.none,
      ),
      StatementKind.cash => (
        TxnKind.cash,
        TransferReason.none,
        MoneyInKind.none,
      ),
      StatementKind.toPerson => (
        TxnKind.transfer,
        TransferReason.personTransfer,
        MoneyInKind.none,
      ),
      StatementKind.fromPerson => (
        TxnKind.transfer,
        TransferReason.personTransfer,
        MoneyInKind.p2pReceive,
      ),
      StatementKind.cardBill => (
        TxnKind.transfer,
        TransferReason.creditCardBill,
        MoneyInKind.none,
      ),
      // A top-up of the holder's account at another bank is invested from
      // there; that bank's SMS carry each SIP, so here it is a transfer.
      StatementKind.investment => (
        TxnKind.transfer,
        (row.counterparty ?? '').startsWith('To your ')
            ? TransferReason.selfTransfer
            : TransferReason.investment,
        MoneyInKind.none,
      ),
      StatementKind.redemption => (
        TxnKind.transfer,
        TransferReason.redemption,
        MoneyInKind.redemption,
      ),
      StatementKind.salary => (
        TxnKind.income,
        TransferReason.none,
        MoneyInKind.salary,
      ),
      StatementKind.interest => (
        TxnKind.income,
        TransferReason.none,
        MoneyInKind.interest,
      ),
      StatementKind.refund => (
        TxnKind.transfer,
        TransferReason.refund,
        MoneyInKind.refund,
      ),
      StatementKind.cashback => (
        TxnKind.transfer,
        TransferReason.cashback,
        MoneyInKind.cashback,
      ),
      StatementKind.loan =>
        debit
            ? (TxnKind.transfer, TransferReason.loanRepayment, MoneyInKind.none)
            : (
                TxnKind.transfer,
                TransferReason.selfTransfer,
                MoneyInKind.selfTransfer,
              ),
      // An unnamed credit is the user's own money until something names a
      // payer, exactly as the SMS ledger treats "credited to your a/c".
      StatementKind.selfTransfer || StatementKind.otherCredit =>
        debit
            ? (TxnKind.transfer, TransferReason.selfTransfer, MoneyInKind.none)
            : (
                TxnKind.transfer,
                TransferReason.selfTransfer,
                MoneyInKind.selfTransfer,
              ),
    };

    // The alert's own clock when it is the same day; noon otherwise.
    final sameDay =
        alert != null &&
        alert.occurredAt.year == row.date.year &&
        alert.occurredAt.month == row.date.month &&
        alert.occurredAt.day == row.date.day;
    final at = sameDay
        ? alert.occurredAtMs
        : _noon(row.date).millisecondsSinceEpoch;

    // A category the user set on the alert (or a learned rule) survives.
    final userCategory =
        alert != null &&
        (alert.categorySource == CategorySource.user ||
            alert.categorySource == CategorySource.learned);
    // The duplicate status survives only when the alert it deferred to is
    // still in the ledger (another sender's leg, not this account's).
    final dupOf = alert?.isDuplicateOfKey;
    final inheritedDup = dupOf != null && !replacedKeys.contains(dupOf)
        ? dupOf
        : null;

    return Txn(
      key: row.key ?? row.identity(c.accountKey),
      occurredAtMs: at,
      amountPaise: amount,
      kind: kind,
      instrument: alert?.instrument ?? Instrument.bankAccount,
      sender: '${c.bank} statement',
      merchant: alert?.merchant ?? row.counterparty,
      counterpartyVpa: alert?.counterpartyVpa,
      categoryName: userCategory ? alert.categoryName : row.categoryName,
      categorySource: userCategory
          ? alert.categorySource
          : CategorySource.heuristic,
      categoryKind: userCategory ? alert.categoryKind : row.categoryKind,
      transferReason: reason,
      moneyInKind: moneyIn,
      last4: c.accountMask,
      issuer: c.bank,
      referenceId: row.reference ?? alert?.referenceId,
      balanceAfterPaise: row.balancePaise,
      confidence: row.balanceVerified ? 1.0 : 0.8,
      sourceType: TxnSourceType.statement,
      isDuplicateOfKey: inheritedDup,
      rawBody: row.description,
    );
  }
}

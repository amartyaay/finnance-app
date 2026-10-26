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

/// One ledger from two sources: an imported bank statement is the record for
/// the account and the days it covers; SMS fill in everything else (other
/// banks, cards, and the days after the statement ends, like this month).
///
/// The statement replaces that account's SMS rows outright, so nothing is
/// counted twice and an SMS the bank never sent cannot leave a hole. The
/// decisions the SMS ledger already made are kept, though:
/// - a replaced alert that was a duplicate of another sender's alert (the
///   bank leg of a card bill, whose issuer confirmation survives) hands that
///   status to its statement row;
/// - a category the user chose on the alert stays on the statement row.
/// When the account's SMS never arrived, the statement row still pairs with
/// the card issuer's "payment received", and a merchant receipt folds into
/// the statement row it confirms.
class StatementMerge {
  const StatementMerge();

  List<Txn> merge({
    required List<Txn> sms,
    required List<StatementCoverage> coverage,
    required Map<String, List<StatementRow>> rows,
  }) {
    if (coverage.isEmpty) return sms;

    // 1. The account's own alerts, on covered days, step aside.
    final replaced = <String, List<Txn>>{};
    final kept = <Txn>[];
    for (final txn in sms) {
      final owner = coverage
          .where((c) => c.coversDay(txn.occurredAt) && _fromAccount(txn, c))
          .firstOrNull;
      if (owner == null) {
        kept.add(txn);
      } else {
        replaced.putIfAbsent(owner.accountKey, () => []).add(txn);
      }
    }
    final replacedKeys = {
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
    final out = <Txn>[
      for (final t in kept)
        t.isDuplicateOfKey != null && remap.containsKey(t.isDuplicateOfKey)
            ? t.copyWith(isDuplicateOfKey: remap[t.isDuplicateOfKey])
            : t,
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
      if (s.transferReason == TransferReason.creditCardBill && !_isInflow(s)) {
        final issuer = out
            .where(
              (t) =>
                  t.isDuplicateOfKey == null &&
                  !claimed.contains(t.key) &&
                  t.cardKey != null &&
                  t.moneyInKind == MoneyInKind.cardPayment &&
                  t.amountPaise == s.amountPaise &&
                  t.occurredAt.difference(s.occurredAt).inDays.abs() <= 3,
            )
            .firstOrNull;
        if (issuer != null) {
          claimed.add(issuer.key);
          fromStatement[i] = s.copyWith(isDuplicateOfKey: issuer.key);
        }
      } else if (s.kind == TxnKind.spend) {
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

    out.addAll(fromStatement);
    out.sort((a, b) => a.occurredAtMs.compareTo(b.occurredAtMs));
    return out;
  }

  /// An alert about this account: from the same bank, not a card, and naming
  /// this account's tail (or no account at all).
  static bool _fromAccount(Txn txn, StatementCoverage c) {
    if (txn.sourceType != TxnSourceType.sms) return false;
    // A debit card spends from this account (its number is the card's, not
    // the account's); a credit card is a different ledger altogether.
    final debitCard =
        txn.instrument == Instrument.debitCard || txn.instrument == Instrument.atm;
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
      StatementKind.investment => (
        TxnKind.transfer,
        TransferReason.investment,
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

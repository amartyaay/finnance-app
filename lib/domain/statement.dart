/// A bank statement imported from a file (SBI first), and its rows.
///
/// Statements are a second, independent source of truth next to SMS: every row
/// carries the running balance the bank printed, so each one can be checked
/// arithmetically (`previous − debit + credit = balance`). A row that fails the
/// check is kept but flagged — nothing is silently dropped.
library;

import 'enums.dart';
import 'hashing.dart';

/// What a statement row is, financially. Mirrors the SMS ledger's vocabulary
/// (`TxnKind` + `TransferReason`), but statement narrations are richer, so the
/// kinds are spelled out instead of folded into `transfer`.
enum StatementKind {
  /// Paid a merchant: UPI to a shop, debit-card POS/online, bill payment.
  spend,

  /// Sent to another person (P2P UPI/IMPS/NEFT to a named individual).
  toPerson,

  /// Received from another person. Their money, not income.
  fromPerson,

  /// Between the account holder's own accounts.
  selfTransfer,

  /// Paying a credit-card bill. Never spend: the purchases were on the card.
  cardBill,

  /// SIP, mutual fund, stocks, FD/RD booking.
  investment,

  /// FD/RD/MF proceeds coming back.
  redemption,

  /// EMI / loan repayment (debit) or disbursal (credit).
  loan,

  /// ATM or branch cash withdrawal.
  cash,

  /// Salary credit (detected, or marked by the user).
  salary,

  /// Interest or dividend credited.
  interest,

  /// Refund, reversal or chargeback.
  refund,

  /// Cashback or reward credited.
  cashback,

  /// Bank fees and taxes on them: SMS charges, card fee, GST on charges.
  charges,

  /// A credit we cannot name. Never assumed to be income.
  otherCredit,

  /// A debit we cannot name. Counted as spend (money did leave), shown as Other.
  otherDebit;

  bool get isDebitKind => switch (this) {
    spend || toPerson || cardBill || investment || cash || charges || otherDebit => true,
    _ => false,
  };

  /// Counts toward "spent" in a salary cycle: consumption, not movement.
  bool get isSpend =>
      this == spend || this == charges || this == otherDebit || this == toPerson;

  String get label => switch (this) {
    spend => 'Spend',
    toPerson => 'Sent to a person',
    fromPerson => 'From a person',
    selfTransfer => 'Between your accounts',
    cardBill => 'Credit-card bill',
    investment => 'Investment',
    redemption => 'Redemption',
    loan => 'Loan / EMI',
    cash => 'Cash withdrawal',
    salary => 'Salary',
    interest => 'Interest',
    refund => 'Refund',
    cashback => 'Cashback',
    charges => 'Bank charges',
    otherCredit => 'Other money in',
    otherDebit => 'Other',
  };
}

/// One printed line of a statement, after table reconstruction.
class StatementRow {
  const StatementRow({
    required this.date,
    required this.description,
    required this.debitPaise,
    required this.creditPaise,
    required this.balancePaise,
    this.valueDate,
    this.reference,
    this.balanceVerified = false,
    this.kind = StatementKind.otherDebit,
    this.counterparty,
    this.categoryName = 'Other',
    this.categoryKind = SpendCategoryKind.other,
    this.isSalaryOverride,
    this.key,
  });

  /// The stored identity (see [identity]); null until the row is saved.
  final String? key;

  final DateTime date;
  final DateTime? valueDate;
  final String description;
  final String? reference;

  /// Exactly one of [debitPaise] / [creditPaise] is non-zero.
  final int debitPaise;
  final int creditPaise;

  /// Running balance after this row, as printed. Negative = overdrawn.
  final int? balancePaise;

  /// True when `previous − debit + credit == balance` held for this row.
  final bool balanceVerified;

  final StatementKind kind;

  /// The other party, cleaned from the narration (`SWIGGY`, `RAHUL KUMAR`).
  final String? counterparty;
  final String categoryName;
  final SpendCategoryKind categoryKind;

  /// The user's explicit "this is / is not my salary"; null when untouched.
  final bool? isSalaryOverride;

  bool get isDebit => debitPaise > 0;
  int get amountPaise => isDebit ? debitPaise : creditPaise;

  /// Identity across overlapping imports of the same account: the running
  /// balance makes two genuinely different rows with the same date and amount
  /// distinct, while re-importing the same period collapses to one row.
  String identity(String accountKey) => 'stmt:${fnv1a64(
    '$accountKey|${date.toIso8601String().substring(0, 10)}|$debitPaise|'
    '$creditPaise|${balancePaise ?? ''}|${reference ?? ''}',
  )}';

  StatementRow copyWith({
    bool? balanceVerified,
    StatementKind? kind,
    String? counterparty,
    String? categoryName,
    SpendCategoryKind? categoryKind,
    bool? isSalaryOverride,
    bool clearSalaryOverride = false,
    String? key,
  }) => StatementRow(
    key: key ?? this.key,
    date: date,
    valueDate: valueDate,
    description: description,
    reference: reference,
    debitPaise: debitPaise,
    creditPaise: creditPaise,
    balancePaise: balancePaise,
    balanceVerified: balanceVerified ?? this.balanceVerified,
    kind: kind ?? this.kind,
    counterparty: counterparty ?? this.counterparty,
    categoryName: categoryName ?? this.categoryName,
    categoryKind: categoryKind ?? this.categoryKind,
    isSalaryOverride: clearSalaryOverride
        ? null
        : (isSalaryOverride ?? this.isSalaryOverride),
  );
}

/// A parsed statement file.
class BankStatement {
  const BankStatement({
    required this.bank,
    required this.rows,
    this.accountMask,
    this.holderName,
    this.periodFrom,
    this.periodTo,
    this.openingBalancePaise,
    this.closingBalancePaise,
    this.warnings = const [],
  });

  final String bank;

  /// Last four digits of the account, when printed.
  final String? accountMask;
  final String? holderName;
  final DateTime? periodFrom;
  final DateTime? periodTo;
  final int? openingBalancePaise;
  final int? closingBalancePaise;
  final List<StatementRow> rows;

  /// Human-readable problems found while parsing (unbalanced rows, a page that
  /// produced no rows). Shown on the import result, never hidden.
  final List<String> warnings;

  String get accountKey => '$bank:${accountMask ?? 'unknown'}';

  int get verifiedRows => rows.where((r) => r.balanceVerified).length;

  /// Every row reconciles and the closing balance matches the last row.
  bool get fullyVerified =>
      rows.isNotEmpty &&
      verifiedRows == rows.length &&
      (closingBalancePaise == null || closingBalancePaise == rows.last.balancePaise);
}

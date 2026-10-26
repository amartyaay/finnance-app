import '../../app/money_format.dart';
import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../../domain/transaction.dart';

/// One labelled slice of the money that came in during a month.
///
/// The label is the *reason* the money arrived (salary, refund, transfer in),
/// so every screen can print "Refunds ₹X · Transfers in ₹Y" from the same model
/// instead of inventing its own categories.
class MoneyInGroup {
  const MoneyInGroup({required this.kind, required this.amountPaise});

  final MoneyInKind kind;
  final int amountPaise;

  Paise get amount => Paise(amountPaise);
}

/// Human label for an inflow reason. "Refunds" is plural because the line is a
/// total, and "Transfers in" says both the direction and the fact that it is
/// not income.
String moneyInKindLabel(MoneyInKind kind) => switch (kind) {
  MoneyInKind.salary => 'Salary',
  MoneyInKind.interest => 'Interest',
  MoneyInKind.other => 'Other income',
  MoneyInKind.refund => 'Refunds',
  MoneyInKind.cashback => 'Cashback',
  MoneyInKind.cardPayment => 'Card bill credits',
  MoneyInKind.selfTransfer => 'Transfers in',
  MoneyInKind.redemption => 'Redemptions',
  MoneyInKind.walletLoad => 'Wallet loads',
  MoneyInKind.p2pReceive => 'From people',
  MoneyInKind.none => '',
};

/// True when [txn] is income under the same rule the monthly summary uses:
/// salary/interest/other, plus a legacy credit that has no finer taxonomy.
bool countsAsTrueIncome(Txn txn) {
  if (txn.kind != TxnKind.income) return false;
  final kind = txn.moneyInKind;
  return kind.isTrueIncome || kind == MoneyInKind.none;
}

/// Every inflow in the month, grouped by reason and largest first.
///
/// Refunds, cashback and transfers are deliberately included: the point of the
/// line is to show *all* money that came in, not only the part that counts as
/// income. A credit with no finer taxonomy is grouped as "Other income".
List<MoneyInGroup> moneyInGroups(
  Iterable<Txn> transactions, {
  required DateTime monthStart,
  required DateTime monthEnd,
}) {
  final byKind = <MoneyInKind, int>{};
  for (final txn in transactions) {
    if (txn.isDuplicateOfKey != null) continue;
    var at = txn.occurredAt;
    // Same rule as the monthly summary: a month-end salary is next month's.
    final calendarMonth =
        monthStart.day == 1 &&
        monthEnd == DateTime(monthStart.year, monthStart.month + 1);
    if (calendarMonth &&
        txn.moneyInKind == MoneyInKind.salary &&
        at.day >= 25) {
      at = DateTime(at.year, at.month + 1);
    }
    if (at.isBefore(monthStart) || !at.isBefore(monthEnd)) continue;
    var kind = txn.moneyInKind;
    if (kind == MoneyInKind.none) {
      // An income credit whose source the parser could not name is still money
      // in; it must appear on the line rather than silently vanish.
      if (txn.kind != TxnKind.income) continue;
      kind = MoneyInKind.other;
    }
    byKind.update(
      kind,
      (value) => value + txn.amountPaise,
      ifAbsent: () => txn.amountPaise,
    );
  }
  final groups = [
    for (final entry in byKind.entries)
      if (entry.value > 0)
        MoneyInGroup(kind: entry.key, amountPaise: entry.value),
  ]..sort((a, b) => b.amountPaise.compareTo(a.amountPaise));
  return groups;
}

/// True when the grouped inflows contain a salary credit.
bool hasSalary(List<MoneyInGroup> groups) =>
    groups.any((group) => group.kind == MoneyInKind.salary);

/// `₹3,940` for a refund total, `₹1,05,590` for a transfer total — the one money
/// rule in `lib/app/money_format.dart`, not a third format invented here.
String moneyInAmount(Paise amount) => money(amount);

/// `Refunds ₹3,939.66 · Transfers in ₹1.2L` — the one string every screen uses.
String moneyInLine(List<MoneyInGroup> groups) => groups
    .map(
      (group) =>
          '${moneyInKindLabel(group.kind)} ${moneyInAmount(group.amount)}',
    )
    .join(' · ');

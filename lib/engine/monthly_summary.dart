import '../domain/enums.dart';
import '../domain/money.dart';
import '../domain/transaction.dart';

/// Everything the dashboard needs, computed once per data change.
class MonthlySummary {
  const MonthlySummary({
    required this.monthStart,
    required this.spendPaise,
    required this.incomePaise,
    required this.cashPaise,
    required this.transferPaise,
    required this.txnCount,
    required this.byCategory,
    required this.dailySpend,
    required this.projectedSpendPaise,
    required this.previousSpendPaise,
    required this.daysElapsed,
    required this.daysInMonth,
  });

  final DateTime monthStart;
  final int spendPaise;
  final int incomePaise;
  final int cashPaise;
  final int transferPaise;
  final int txnCount;
  final List<CategoryTotal> byCategory;

  /// One entry per day of the month so far (index 0 = day 1).
  final List<int> dailySpend;

  /// Linear projection to month-end, weighted by the days actually elapsed.
  final int projectedSpendPaise;

  final int previousSpendPaise;
  final int daysElapsed;
  final int daysInMonth;

  Paise get spend => Paise(spendPaise);
  Paise get income => Paise(incomePaise);
  Paise get projectedSpend => Paise(projectedSpendPaise);
  Paise get previousSpend => Paise(previousSpendPaise);
  Paise get cash => Paise(cashPaise);

  /// Net money left after real spending (transfers excluded — they are not
  /// consumption, and counting them would double-count card bills).
  Paise get net => Paise(incomePaise - spendPaise);

  double get savingsRate =>
      incomePaise <= 0 ? 0 : (incomePaise - spendPaise) / incomePaise;

  /// Month-over-month change, e.g. 0.18 for +18%.
  double get monthOverMonth {
    if (previousSpendPaise <= 0) return 0;
    return (spendPaise - previousSpendPaise) / previousSpendPaise;
  }

  Paise get dailyAverage =>
      Paise(daysElapsed == 0 ? 0 : (spendPaise / daysElapsed).round());

  CategoryTotal? categoryFor(SpendCategoryKind kind) {
    for (final entry in byCategory) {
      if (entry.kind == kind) return entry;
    }
    return null;
  }

  static MonthlySummary empty(DateTime now) => MonthlySummary(
    monthStart: DateTime(now.year, now.month),
    spendPaise: 0,
    incomePaise: 0,
    cashPaise: 0,
    transferPaise: 0,
    txnCount: 0,
    byCategory: const [],
    dailySpend: const [],
    projectedSpendPaise: 0,
    previousSpendPaise: 0,
    daysElapsed: 0,
    daysInMonth: 30,
  );
}

class CategoryTotal {
  const CategoryTotal({
    required this.name,
    required this.kind,
    required this.paise,
    required this.txnCount,
    required this.share,
    required this.previousPaise,
  });

  final String name;
  final SpendCategoryKind kind;
  final int paise;
  final int txnCount;
  final double share;
  final int previousPaise;

  Paise get amount => Paise(paise);
  Paise get previous => Paise(previousPaise);

  double get change {
    if (previousPaise <= 0) return 0;
    return (paise - previousPaise) / previousPaise;
  }
}

/// Computes a [MonthlySummary] for the calendar month containing [now].
///
/// Calendar month (not card statement cycle) is what users expect from a spend
/// app; card cycles are handled separately in `CardMetrics`.
class SummaryCalculator {
  const SummaryCalculator();

  MonthlySummary forMonth(
    List<Txn> transactions,
    DateTime now, {
    int monthOffset = 0,
  }) {
    final monthStart = DateTime(
      now.year,
      now.month + monthOffset,
    );
    final monthEnd = DateTime(now.year, now.month + monthOffset + 1);
    final prevStart = DateTime(monthStart.year, monthStart.month - 1);

    var spend = 0;
    var income = 0;
    var cash = 0;
    var transfer = 0;
    var count = 0;
    var prevSpend = 0;
    final byKind = <SpendCategoryKind, _Acc>{};
    final daily = <int>[];

    for (final txn in transactions) {
      if (txn.isDuplicateOfKey != null) continue;
      final at = txn.occurredAt;
      if (at.isBefore(monthStart) || !at.isBefore(monthEnd)) {
        if (at.isBefore(monthStart) &&
            !at.isBefore(prevStart) &&
            txn.kind == TxnKind.spend) {
          prevSpend += txn.amountPaise;
        }
        continue;
      }
      count++;
      switch (txn.kind) {
        case TxnKind.spend:
          spend += txn.amountPaise;
          final acc = byKind.putIfAbsent(
            txn.categoryKind,
            () => _Acc(txn.categoryName ?? 'Other'),
          );
          acc.paise += txn.amountPaise;
          acc.count++;
          final dayIdx = at.day - 1;
          while (daily.length <= dayIdx) {
            daily.add(0);
          }
          daily[dayIdx] += txn.amountPaise;
        case TxnKind.cash:
          cash += txn.amountPaise;
        case TxnKind.income:
          income += txn.amountPaise;
        case TxnKind.transfer:
          transfer += txn.amountPaise;
      }
    }

    final daysInMonth = monthEnd.difference(monthStart).inDays;
    final daysElapsed = now.isAfter(monthEnd)
        ? daysInMonth
        : (now.day).clamp(1, daysInMonth);
    final projected = daysElapsed == 0
        ? 0
        : (spend / daysElapsed * daysInMonth).round();

    // Previous month, per category, for month-over-month deltas.
    final prevByKind = <SpendCategoryKind, int>{};
    for (final txn in transactions) {
      if (txn.isDuplicateOfKey != null) continue;
      if (txn.kind != TxnKind.spend) continue;
      final at = txn.occurredAt;
      if (at.isBefore(prevStart) || !at.isBefore(monthStart)) continue;
      prevByKind.update(
        txn.categoryKind,
        (v) => v + txn.amountPaise,
        ifAbsent: () => txn.amountPaise,
      );
    }

    final categories = byKind.entries
        .map(
          (e) => CategoryTotal(
            name: e.value.label,
            kind: e.key,
            paise: e.value.paise,
            txnCount: e.value.count,
            share: spend == 0 ? 0 : e.value.paise / spend,
            previousPaise: prevByKind[e.key] ?? 0,
          ),
        )
        .toList()
      ..sort((a, b) => b.paise.compareTo(a.paise));

    return MonthlySummary(
      monthStart: monthStart,
      spendPaise: spend,
      incomePaise: income,
      cashPaise: cash,
      transferPaise: transfer,
      txnCount: count,
      byCategory: categories,
      dailySpend: daily,
      projectedSpendPaise: projected,
      previousSpendPaise: prevSpend,
      daysElapsed: daysElapsed,
      daysInMonth: daysInMonth,
    );
  }
}

class _Acc {
  _Acc(this.label);

  final String label;
  int paise = 0;
  int count = 0;
}

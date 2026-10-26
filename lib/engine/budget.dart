import 'dart:convert';
import 'dart:math' as math;

import '../domain/enums.dart';
import '../domain/money.dart';
import '../domain/transaction.dart';
import 'monthly_summary.dart';

/// What the user decided: one monthly spending limit, optional limits per
/// category, an optional monthly savings goal, and whether the 10 pm summary
/// is on. Amounts are integer paise; null means "not set".
class Budget {
  const Budget({
    this.monthlyPaise,
    this.categoryPaise = const {},
    this.savingsGoalPaise,
    this.dailyDigest = true,
  });

  final int? monthlyPaise;
  final Map<SpendCategoryKind, int> categoryPaise;
  final int? savingsGoalPaise;
  final bool dailyDigest;

  bool get isSet => monthlyPaise != null && monthlyPaise! > 0;

  Budget copyWith({
    int? monthlyPaise,
    bool clearMonthly = false,
    Map<SpendCategoryKind, int>? categoryPaise,
    int? savingsGoalPaise,
    bool clearSavingsGoal = false,
    bool? dailyDigest,
  }) => Budget(
    monthlyPaise: clearMonthly ? null : monthlyPaise ?? this.monthlyPaise,
    categoryPaise: categoryPaise ?? this.categoryPaise,
    savingsGoalPaise: clearSavingsGoal
        ? null
        : savingsGoalPaise ?? this.savingsGoalPaise,
    dailyDigest: dailyDigest ?? this.dailyDigest,
  );

  String toJson() => jsonEncode({
    'monthly': monthlyPaise,
    'categories': {for (final e in categoryPaise.entries) e.key.name: e.value},
    'savingsGoal': savingsGoalPaise,
    'dailyDigest': dailyDigest,
  });

  factory Budget.fromJson(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final cats = (map['categories'] as Map<String, dynamic>? ?? const {});
      return Budget(
        monthlyPaise: map['monthly'] as int?,
        categoryPaise: {
          for (final e in cats.entries)
            if (SpendCategoryKind.values.any((k) => k.name == e.key))
              SpendCategoryKind.values.byName(e.key): e.value as int,
        },
        savingsGoalPaise: map['savingsGoal'] as int?,
        dailyDigest: map['dailyDigest'] as bool? ?? true,
      );
    } on Object {
      return const Budget();
    }
  }
}

/// Where spending stands against the plan.
enum BudgetPace {
  /// Spent less than the share of the month gone by.
  under,

  /// Within 10 % of the expected spend by today.
  onTrack,

  /// Ahead of the even pace, but not over the limit yet.
  ahead,

  /// The monthly limit is already passed.
  over;

  String get label => switch (this) {
    under => 'Under pace',
    onTrack => 'On track',
    ahead => 'Spending fast',
    over => 'Over budget',
  };
}

class CategoryBudgetStatus {
  const CategoryBudgetStatus({
    required this.kind,
    required this.name,
    required this.limitPaise,
    required this.spentPaise,
  });

  final SpendCategoryKind kind;
  final String name;
  final int limitPaise;
  final int spentPaise;

  double get fraction => limitPaise <= 0 ? 0 : spentPaise / limitPaise;
  int get leftPaise => limitPaise - spentPaise;
}

/// The month measured against the [Budget]: the numbers the Budget tab and
/// the 10 pm summary both print, so they can never disagree.
class BudgetStatus {
  const BudgetStatus({
    required this.budget,
    required this.month,
    required this.spentPaise,
    required this.todayPaise,
    required this.daysElapsed,
    required this.daysInMonth,
    required this.categories,
    required this.incomePaise,
    required this.outPaise,
    required this.projectedSpendPaise,
  });

  final Budget budget;
  final DateTime month;
  final int spentPaise;
  final int todayPaise;
  final int daysElapsed;
  final int daysInMonth;
  final List<CategoryBudgetStatus> categories;

  /// True income this month and money out (spend + cash + card bills), the
  /// same definitions as Home's "Came in" and "Out".
  final int incomePaise;
  final int outPaise;
  final int projectedSpendPaise;

  int get limitPaise => budget.monthlyPaise ?? 0;
  int get leftPaise => limitPaise - spentPaise;

  /// Days still to come, today included: what is left is spread over them.
  int get daysLeft => math.max(1, daysInMonth - daysElapsed + 1);

  /// What can be spent per day from today to month-end and still land on the
  /// budget. Zero once the budget is used up.
  int get safePerDayPaise =>
      leftPaise <= 0 ? 0 : (leftPaise / daysLeft).floor();

  /// The even-pace spend by the end of today.
  int get expectedByTodayPaise =>
      (limitPaise * daysElapsed / daysInMonth).round();

  double get fraction => limitPaise <= 0 ? 0 : spentPaise / limitPaise;
  double get monthFraction => daysElapsed / daysInMonth;

  BudgetPace get pace {
    if (spentPaise > limitPaise) return BudgetPace.over;
    final expected = expectedByTodayPaise;
    if (expected <= 0) return BudgetPace.onTrack;
    final ratio = spentPaise / expected;
    if (ratio > 1.1) return BudgetPace.ahead;
    if (ratio < 0.9) return BudgetPace.under;
    return BudgetPace.onTrack;
  }

  /// Saved so far: true income minus everything that went out.
  int get savedPaise => incomePaise - outPaise;

  /// Saved by month-end if spending keeps its current pace.
  int get projectedSavedPaise =>
      incomePaise - (outPaise + math.max(0, projectedSpendPaise - spentPaise));

  static BudgetStatus of({
    required Budget budget,
    required MonthlySummary month,
    required List<Txn> ledger,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    var todayPaise = 0;
    for (final t in ledger) {
      if (t.kind != TxnKind.spend ||
          t.isDuplicateOfKey != null ||
          t.needsReview) {
        continue;
      }
      final at = t.occurredAt;
      if (!at.isBefore(today) && at.isBefore(tomorrow)) {
        todayPaise += t.amountPaise;
      }
    }
    final byKind = {for (final c in month.byCategory) c.kind: c};
    final categories = [
      for (final e in budget.categoryPaise.entries)
        CategoryBudgetStatus(
          kind: e.key,
          name: byKind[e.key]?.name ?? _label(e.key),
          limitPaise: e.value,
          spentPaise: byKind[e.key]?.paise ?? 0,
        ),
    ]..sort((a, b) => b.fraction.compareTo(a.fraction));
    return BudgetStatus(
      budget: budget,
      month: month.monthStart,
      spentPaise: month.spendPaise,
      todayPaise: todayPaise,
      daysElapsed: month.daysElapsed,
      daysInMonth: month.daysInMonth,
      categories: categories,
      incomePaise: month.incomePaise,
      outPaise: month.moneyOutPaise,
      projectedSpendPaise: month.projectedSpendPaise,
    );
  }

  /// A starting budget: the median of the last three full months' spend,
  /// rounded up to the next ₹1,000 (like a "suggested" budget from history).
  /// Null with less than one full month of data.
  static int? suggestMonthly(List<Txn> ledger, DateTime now) {
    const calc = SummaryCalculator();
    final months = [
      for (var o = -1; o >= -3; o--)
        calc.forMonth(ledger, now, monthOffset: o).spendPaise,
    ].where((p) => p > 0).toList()..sort();
    if (months.isEmpty) return null;
    final median = months[months.length ~/ 2];
    return ((median / 100000).ceil()) * 100000;
  }

  /// A starting limit for one category: its average over the last three full
  /// months, rounded up to the next ₹500.
  static int? suggestCategory(
    List<Txn> ledger,
    DateTime now,
    SpendCategoryKind kind,
  ) {
    const calc = SummaryCalculator();
    var total = 0;
    var months = 0;
    for (var o = -1; o >= -3; o--) {
      final m = calc.forMonth(ledger, now, monthOffset: o);
      if (m.spendPaise <= 0) continue;
      months++;
      total += m.categoryFor(kind)?.paise ?? 0;
    }
    if (months == 0 || total == 0) return null;
    return (((total / months) / 50000).ceil()) * 50000;
  }

  static String _label(SpendCategoryKind kind) {
    final n = kind.name;
    return n[0].toUpperCase() + n.substring(1);
  }
}

/// The 10 pm notification, from the same numbers as the Budget tab.
class DailyDigest {
  const DailyDigest({required this.title, required this.body});

  final String title;
  final String body;

  static DailyDigest compose(BudgetStatus status, {String? topToday}) {
    final today = inr(_whole(status.todayPaise));
    final title = status.todayPaise == 0
        ? 'No spending today'
        : 'You spent $today today${topToday == null ? '' : ' · mostly $topToday'}';
    final String body;
    if (!status.budget.isSet) {
      body =
          '${inr(_whole(status.spentPaise))} spent this month, on pace for '
          '${inr(_whole(status.projectedSpendPaise))}. Set a monthly budget to '
          'see how much is safe to spend each day.';
    } else if (status.pace == BudgetPace.over) {
      body =
          '${inr(_whole(status.spentPaise))} of ${inr(_whole(status.limitPaise))} '
          'this month: ${inr(_whole(-status.leftPaise))} over budget.';
    } else {
      final left = inr(_whole(status.leftPaise));
      // At 10 pm today is spent: what is left spreads over tomorrow onward.
      final days = status.daysLeft - 1;
      final perDay = inr(_whole(days <= 0 ? 0 : status.leftPaise ~/ days));
      final tail = days <= 0
          ? 'Last day of the month.'
          : '$perDay a day for the next $days ${days == 1 ? 'day' : 'days'}.';
      body =
          '$left left of ${inr(_whole(status.limitPaise))} '
          '(${status.pace.label.toLowerCase()}). $tail';
    }
    return DailyDigest(title: title, body: body);
  }

  static Paise _whole(int paise) => Paise(((paise / 100).round()) * 100);

  /// Today's biggest spending category ("mostly Food & dining"), or null.
  static String? topToday(List<Txn> ledger, DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    final byCategory = <String, int>{};
    for (final t in ledger) {
      if (t.kind != TxnKind.spend || t.isDuplicateOfKey != null) continue;
      if (t.occurredAt.isBefore(day)) continue;
      byCategory.update(
        t.categoryName ?? 'Other',
        (v) => v + t.amountPaise,
        ifAbsent: () => t.amountPaise,
      );
    }
    if (byCategory.isEmpty) return null;
    final sorted = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }
}

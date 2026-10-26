import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/money_format.dart';
import '../app/widgets/kit.dart';
import '../domain/enums.dart';
import '../domain/money.dart';
import '../engine/budget.dart';
import '../engine/monthly_summary.dart';
import '../state/app_state.dart';
import 'widgets/txn_common.dart';

/// The month's plan: one spending limit with a daily "safe to spend", optional
/// limits for the categories that matter, savings against a goal, and the
/// switch for the 10 pm summary.
///
/// What counts is the same "Spent" as Home: purchases (card purchases when they
/// happen), never card-bill payments, investments or transfers, so a budget
/// can't be blown by paying a card bill.
class BudgetScreen extends StatelessWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final status = state.budgetStatus;
    final budget = state.budget;
    final now = state.now;
    final ledger = state.data.transactions;

    return Scaffold(
      appBar: AppBar(title: const Text('Budget'), titleSpacing: T.s5),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, 112),
        children: [
          if (!budget.isSet)
            _SetupCard(
              suggestion: BudgetStatus.suggestMonthly(ledger, now),
              history: _lastMonths(ledger, now, 3),
            )
          else
            _BudgetHero(status: status),
          const SizedBox(height: T.s5),
          _CategoryLimits(status: status),
          const SizedBox(height: T.s5),
          _Savings(status: status),
          if (budget.isSet) ...[
            const SizedBox(height: T.s5),
            _History(
              months: _lastMonths(ledger, now, 6),
              limit: budget.monthlyPaise!,
            ),
          ],
          const SizedBox(height: T.s5),
          const _DigestCard(),
        ],
      ),
    );
  }

  static List<MonthlySummary> _lastMonths(List ledger, DateTime now, int n) {
    const calc = SummaryCalculator();
    return [
      for (var o = -1; o >= -n; o--)
        calc.forMonth(ledger.cast(), now, monthOffset: o),
    ];
  }
}

// ---- Setup ------------------------------------------------------------------

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.suggestion, required this.history});

  final int? suggestion;
  final List<MonthlySummary> history;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final state = context.read<AppState>();
    final past = history.where((m) => m.spendPaise > 0).toList();
    return HeroSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Set a monthly budget', style: T.title.copyWith(color: p.ink)),
          const SizedBox(height: T.s2),
          Text(
            'The most you want to spend in a month: rent, food, shopping, '
            'everything. Card bills, investments and money moved between your '
            'accounts never count, just like on Home.',
            style: T.body.copyWith(color: p.inkSecondary),
          ),
          if (past.isNotEmpty) ...[
            const SizedBox(height: T.s3),
            Text(
              'You spent ${past.map((m) => '${money(m.spend)} in ${DateFormat.MMM().format(m.monthStart)}').join(', ')}.',
              style: T.bodySmall.copyWith(color: p.inkMuted),
            ),
          ],
          const SizedBox(height: T.s4),
          Wrap(
            spacing: T.s2,
            runSpacing: T.s2,
            children: [
              if (suggestion != null)
                FilledButton(
                  onPressed: () => state.setBudget(
                    state.budget.copyWith(monthlyPaise: suggestion),
                  ),
                  child: Text('Use ${money(Paise(suggestion!))}'),
                ),
              OutlinedButton(
                onPressed: () async {
                  final amount = await showAmountSheet(
                    context,
                    title: 'Monthly budget',
                    hint: 'All spending in a month',
                    initial: suggestion,
                  );
                  if (amount != null && amount.paise != null) {
                    await state.setBudget(
                      state.budget.copyWith(monthlyPaise: amount.paise),
                    );
                  }
                },
                child: const Text('Choose an amount'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- Hero -----------------------------------------------------------------------

class _BudgetHero extends StatelessWidget {
  const _BudgetHero({required this.status});

  final BudgetStatus status;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final state = context.read<AppState>();
    final over = status.leftPaise < 0;
    final tone = switch (status.pace) {
      BudgetPace.over => PillTone.danger,
      BudgetPace.ahead => PillTone.caution,
      BudgetPace.onTrack => PillTone.info,
      BudgetPace.under => PillTone.positive,
    };
    final month = DateFormat.MMMM().format(status.month);
    final spoken =
        '$month budget ${moneySpoken(Paise(status.limitPaise))}. '
        '${over ? 'Over by ${moneySpoken(Paise(-status.leftPaise))}' : '${moneySpoken(Paise(status.leftPaise))} left'}. '
        '${status.pace.label}. Safe to spend ${moneySpoken(Paise(status.safePerDayPaise))} a day.';
    return Semantics(
      label: spoken,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HeroSurface(
            padding: const EdgeInsets.fromLTRB(T.s5, T.s3, T.s2, T.s5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        over ? 'Over budget' : 'Left this month',
                        style: T.body.copyWith(color: p.inkMuted, fontSize: 14),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit budget',
                      onPressed: () => _edit(context, state),
                      icon: Icon(
                        PhosphorIconsRegular.pencilSimple,
                        color: p.inkMuted,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: T.s3),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: GradientText(
                      child: Text(
                        money(Paise(status.leftPaise.abs())),
                        style: T.heroNumber.copyWith(
                          fontSize: 46,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: T.s1),
                Padding(
                  padding: const EdgeInsets.only(right: T.s3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${money(Paise(status.spentPaise))} of ${money(Paise(status.limitPaise))} · $month',
                          maxLines: 2,
                          style: T.body.copyWith(
                            color: p.inkSecondary,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: T.s2),
                      Pill(status.pace.label, tone: tone, dense: true),
                    ],
                  ),
                ),
                const SizedBox(height: T.s4),
                Padding(
                  padding: const EdgeInsets.only(right: T.s3),
                  child: _PaceBar(status: status),
                ),
              ],
            ),
          ),
          const SizedBox(height: T.s3),
          Row(
            children: [
              Expanded(
                child: _Tile(
                  value: money(Paise(status.safePerDayPaise)),
                  label: 'Safe per day',
                  dot: T.teal,
                ),
              ),
              const SizedBox(width: T.s2),
              Expanded(
                child: _Tile(
                  value: money(Paise(status.todayPaise)),
                  label: 'Spent today',
                  dot: T.blue,
                ),
              ),
              const SizedBox(width: T.s2),
              Expanded(
                child: _Tile(
                  value: '${status.daysLeft}',
                  label: status.daysLeft == 1 ? 'Day left' : 'Days left',
                  dot: T.violet,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, AppState state) async {
    final result = await showAmountSheet(
      context,
      title: 'Monthly budget',
      hint: 'All spending in a month',
      initial: state.budget.monthlyPaise,
      removable: true,
    );
    if (result == null) return;
    await state.setBudget(
      result.paise == null
          ? state.budget.copyWith(clearMonthly: true)
          : state.budget.copyWith(monthlyPaise: result.paise),
    );
  }
}

/// Spent so far against the limit, with a tick where an even pace would be
/// today: left of the tick is fine, right of it is spending fast.
class _PaceBar extends StatelessWidget {
  const _PaceBar({required this.status});

  final BudgetStatus status;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final fill = status.fraction.clamp(0.0, 1.0);
    final over = status.pace == BudgetPace.over;
    final fast = status.pace == BudgetPace.ahead;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final tick = c.maxWidth * status.monthFraction.clamp(0.0, 1.0);
            return SizedBox(
              height: 22,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 6,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 6,
                    width: c.maxWidth * fill,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        gradient: LinearGradient(
                          colors: over
                              ? [p.danger, p.danger]
                              : fast
                              ? [p.caution, T.rose]
                              : const [T.teal, T.blue],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (tick - 1).clamp(0.0, c.maxWidth - 2),
                    top: 0,
                    child: Container(width: 2, height: 22, color: p.ink),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '${(status.fraction * 100).round()}% used',
              style: T.bodySmall.copyWith(color: p.inkMuted, fontSize: 12),
            ),
            const Spacer(),
            Text(
              'Today · day ${status.daysElapsed} of ${status.daysInMonth}',
              style: T.bodySmall.copyWith(color: p.inkMuted, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label, required this.dot});

  final String value;
  final String label;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(T.s3, T.s3, T.s2, T.s3),
      decoration: T.glass(radius: T.r4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(height: T.s2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: T.money.copyWith(
                color: p.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.bodySmall.copyWith(color: p.inkMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ---- Category limits ---------------------------------------------------------------

class _CategoryLimits extends StatelessWidget {
  const _CategoryLimits({required this.status});

  final BudgetStatus status;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final state = context.read<AppState>();
    final month = const SummaryCalculator().forMonth(
      state.data.transactions,
      state.now,
    );
    final limited = status.categories;
    final unlimited = [
      for (final c in month.byCategory)
        if (!state.budget.categoryPaise.containsKey(c.kind) &&
            c.kind != SpendCategoryKind.other)
          c,
    ].take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Category limits',
          subtitle: 'For the few categories you want to watch',
          action: 'Add',
          onAction: () => _pickCategory(context, state),
          padding: const EdgeInsets.only(bottom: T.s2),
        ),
        if (limited.isEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unlimited.isEmpty
                      ? 'No spending yet this month.'
                      : 'Your biggest categories this month. Tap one to give it a limit.',
                  style: T.bodySmall.copyWith(color: p.inkMuted),
                ),
                for (final c in unlimited)
                  _SuggestRow(
                    kind: c.kind,
                    name: c.name,
                    spent: c.paise,
                    onTap: () => _editCategory(context, state, c.kind, c.name),
                  ),
              ],
            ),
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: T.s4,
              vertical: T.s2,
            ),
            child: Column(
              children: [
                for (final c in limited)
                  _LimitRow(
                    status: c,
                    monthFraction: status.monthFraction,
                    onTap: () => _editCategory(context, state, c.kind, c.name),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _pickCategory(BuildContext context, AppState state) async {
    final p = T.of(context);
    final kinds = [
      for (final k in SpendCategoryKind.values)
        if (k != SpendCategoryKind.other &&
            k != SpendCategoryKind.transfers &&
            k != SpendCategoryKind.income &&
            k != SpendCategoryKind.investments &&
            !state.budget.categoryPaise.containsKey(k))
          k,
    ];
    final kind = await showModalBottomSheet<SpendCategoryKind>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Limit a category', style: T.title.copyWith(color: p.ink)),
              const SizedBox(height: T.s3),
              for (final k in kinds)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    categoryIcon(k),
                    color: categoryColor(context, k),
                  ),
                  title: Text(
                    categoryKindLabel(k),
                    style: T.body.copyWith(color: p.ink),
                  ),
                  onTap: () => Navigator.pop(sheet, k),
                ),
            ],
          ),
        ),
      ),
    );
    if (kind == null || !context.mounted) return;
    await _editCategory(context, state, kind, categoryKindLabel(kind));
  }

  Future<void> _editCategory(
    BuildContext context,
    AppState state,
    SpendCategoryKind kind,
    String name,
  ) async {
    final current = state.budget.categoryPaise[kind];
    final result = await showAmountSheet(
      context,
      title: '$name limit',
      hint: 'Per month',
      initial:
          current ??
          BudgetStatus.suggestCategory(
            state.data.transactions,
            state.now,
            kind,
          ),
      removable: current != null,
    );
    if (result == null) return;
    final next = Map<SpendCategoryKind, int>.of(state.budget.categoryPaise);
    if (result.paise == null) {
      next.remove(kind);
    } else {
      next[kind] = result.paise!;
    }
    await state.setBudget(state.budget.copyWith(categoryPaise: next));
  }
}

class _SuggestRow extends StatelessWidget {
  const _SuggestRow({
    required this.kind,
    required this.name,
    required this.spent,
    required this.onTap,
  });

  final SpendCategoryKind kind;
  final String name;
  final int spent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(T.r3),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            Icon(
              categoryIcon(kind),
              size: 20,
              color: categoryColor(context, kind),
            ),
            const SizedBox(width: T.s3),
            // Name over amount: three pieces of text on one line do not
            // fit 360 dp at 1.3x.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.body.copyWith(color: p.ink),
                  ),
                  Text(
                    '${money(Paise(spent))} this month',
                    style: T.bodySmall.copyWith(color: p.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: T.s2),
            Text(
              'Set limit',
              style: T.bodySmall.copyWith(
                color: T.teal,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LimitRow extends StatelessWidget {
  const _LimitRow({
    required this.status,
    required this.monthFraction,
    required this.onTap,
  });

  final CategoryBudgetStatus status;
  final double monthFraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final over = status.spentPaise > status.limitPaise;
    final fast = !over && status.fraction > monthFraction * 1.1;
    final color = over
        ? p.danger
        : fast
        ? p.caution
        : categoryColor(context, status.kind);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(T.r3),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: T.s2 + 2),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: categoryColor(
                  context,
                  status.kind,
                ).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(T.r3),
              ),
              child: Icon(
                categoryIcon(status.kind),
                size: 19,
                color: categoryColor(context, status.kind),
              ),
            ),
            const SizedBox(width: T.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          status.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.body.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        over
                            ? '${money(Paise(-status.leftPaise))} over'
                            : '${money(Paise(status.leftPaise))} left',
                        style: T.bodySmall.copyWith(
                          color: over ? p.danger : p.inkSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Stack(
                      children: [
                        Container(
                          height: 6,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        FractionallySizedBox(
                          widthFactor: status.fraction.clamp(0.02, 1.0),
                          child: Container(height: 6, color: color),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${money(Paise(status.spentPaise))} of ${money(Paise(status.limitPaise))}',
                    style: T.bodySmall.copyWith(
                      color: p.inkMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Savings ---------------------------------------------------------------------------

class _Savings extends StatelessWidget {
  const _Savings({required this.status});

  final BudgetStatus status;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final state = context.read<AppState>();
    final goal = state.budget.savingsGoalPaise;
    final hasIncome = status.incomePaise > 0;
    final saved = status.savedPaise;
    final projected = status.projectedSavedPaise;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Savings',
          subtitle: 'What came in minus everything that went out',
          action: goal == null ? 'Set goal' : 'Edit goal',
          onAction: () => _editGoal(context, state),
          padding: const EdgeInsets.only(bottom: T.s2),
        ),
        AppCard(
          child: !hasIncome
              ? Text(
                  'No salary or interest found for this month yet, so there '
                  'is nothing to measure savings against. A salary that lands '
                  'from the 25th counts for the next month.',
                  style: T.bodySmall.copyWith(color: p.inkMuted),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Line(
                      'Came in',
                      money(Paise(status.incomePaise)),
                      p.positive,
                    ),
                    _Line('Went out', money(Paise(status.outPaise)), p.ink),
                    Divider(height: T.s4, color: p.outlineVariant),
                    _Line(
                      saved >= 0 ? 'Saved so far' : 'Short so far',
                      money(Paise(saved.abs())),
                      saved >= 0 ? p.ink : p.danger,
                      bold: true,
                    ),
                    const SizedBox(height: T.s1),
                    Text(
                      projected >= 0
                          ? 'At this pace you will save about ${money(Paise(projected))} by month-end.'
                          : 'At this pace you will be about ${money(Paise(-projected))} short by month-end.',
                      style: T.bodySmall.copyWith(color: p.inkMuted),
                    ),
                    if (goal != null) ...[
                      const SizedBox(height: T.s3),
                      _GoalBar(saved: math.max(0, projected), goal: goal),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _editGoal(BuildContext context, AppState state) async {
    final current = state.budget.savingsGoalPaise;
    final result = await showAmountSheet(
      context,
      title: 'Monthly savings goal',
      hint: 'What you want left at month-end',
      initial: current,
      removable: current != null,
    );
    if (result == null) return;
    await state.setBudget(
      result.paise == null
          ? state.budget.copyWith(clearSavingsGoal: true)
          : state.budget.copyWith(savingsGoalPaise: result.paise),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, this.color, {this.bold = false});

  final String label;
  final String value;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: T.body.copyWith(
                color: bold ? p.ink : p.inkSecondary,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            value,
            style: T.money.copyWith(
              color: color,
              fontSize: bold ? 17 : 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalBar extends StatelessWidget {
  const _GoalBar({required this.saved, required this.goal});

  final int saved;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final fraction = goal <= 0 ? 0.0 : (saved / goal).clamp(0.0, 1.0);
    final met = saved >= goal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Container(height: 8, color: Colors.white.withValues(alpha: 0.08)),
              FractionallySizedBox(
                widthFactor: math.max(0.02, fraction),
                child: Container(height: 8, color: met ? p.positive : T.violet),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          met
              ? 'On course for your ${money(Paise(goal))} goal.'
              : '${money(Paise(goal - saved))} short of your ${money(Paise(goal))} goal at this pace.',
          style: T.bodySmall.copyWith(color: p.inkMuted),
        ),
      ],
    );
  }
}

// ---- History -------------------------------------------------------------------------------

class _History extends StatelessWidget {
  const _History({required this.months, required this.limit});

  final List<MonthlySummary> months;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final shown = months.where((m) => m.spendPaise > 0).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final peak = shown.fold<int>(limit, (m, e) => math.max(m, e.spendPaise));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Against this budget',
          subtitle: 'Earlier months, measured with today\'s limit',
          padding: EdgeInsets.only(bottom: T.s2),
        ),
        AppCard(
          child: Column(
            children: [
              for (final m in shown)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: T.s1 + 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          DateFormat.MMM().format(m.monthStart),
                          style: T.bodySmall.copyWith(color: p.inkSecondary),
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, c) => Stack(
                            children: [
                              Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              Container(
                                height: 8,
                                width: c.maxWidth * (m.spendPaise / peak),
                                decoration: BoxDecoration(
                                  color: m.spendPaise > limit
                                      ? p.danger
                                      : T.teal,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              Positioned(
                                left: c.maxWidth * (limit / peak) - 1,
                                child: Container(
                                  width: 2,
                                  height: 8,
                                  color: p.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: T.s3),
                      SizedBox(
                        width: 78,
                        child: Text(
                          money(m.spend),
                          textAlign: TextAlign.right,
                          style: T.money.copyWith(
                            color: m.spendPaise > limit ? p.danger : p.ink,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- 10 pm summary ---------------------------------------------------------------------

class _DigestCard extends StatelessWidget {
  const _DigestCard();

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final state = context.watch<AppState>();
    final on = state.budget.dailyDigest;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsFill.bellRinging, color: T.teal, size: 20),
              const SizedBox(width: T.s3),
              Expanded(
                child: Text(
                  'Daily summary at 10 pm',
                  style: T.cardTitle.copyWith(color: p.ink),
                ),
              ),
              Switch(
                value: on,
                onChanged: (v) =>
                    state.setBudget(state.budget.copyWith(dailyDigest: v)),
              ),
            ],
          ),
          const SizedBox(height: T.s1),
          Text(
            'One notification a night: what you spent today and how the '
            "month's budget looks. Worked out on this phone from your SMS; "
            'nothing is sent anywhere.',
            style: T.bodySmall.copyWith(color: p.inkMuted),
          ),
          if (on)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await state.sendTestDigest();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Sent tonight's summary as a preview."),
                      ),
                    );
                  }
                },
                child: const Text('Preview it now'),
              ),
            ),
        ],
      ),
    );
  }
}

// ---- Amount sheet -------------------------------------------------------------------------

/// Asks for a rupee amount. Returns null on cancel, `(paise: null)` for
/// "Remove", and the amount otherwise.
Future<({int? paise})?> showAmountSheet(
  BuildContext context, {
  required String title,
  required String hint,
  int? initial,
  bool removable = false,
}) {
  final controller = TextEditingController(
    text: initial == null ? '' : '${(initial / 100).round()}',
  );
  final p = T.of(context);
  return showModalBottomSheet<({int? paise})>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) {
      void submit() {
        final rupees = int.tryParse(
          controller.text.replaceAll(RegExp(r'[^0-9]'), ''),
        );
        if (rupees == null || rupees <= 0) return;
        Navigator.pop(sheet, (paise: rupees * 100));
      }

      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            T.s5,
            0,
            T.s5,
            T.s5 + MediaQuery.viewInsetsOf(sheet).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: T.title.copyWith(color: p.ink)),
              const SizedBox(height: T.s1),
              Text(hint, style: T.bodySmall.copyWith(color: p.inkMuted)),
              const SizedBox(height: T.s4),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => submit(),
                style: T.money.copyWith(color: p.ink, fontSize: 22),
                decoration: const InputDecoration(
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: T.s4),
              Row(
                children: [
                  if (removable)
                    TextButton(
                      onPressed: () => Navigator.pop(sheet, (paise: null)),
                      child: Text(
                        'Remove',
                        style: TextStyle(
                          fontFamily: T.fontFamily,
                          color: p.danger,
                        ),
                      ),
                    ),
                  const Spacer(),
                  FilledButton(onPressed: submit, child: const Text('Save')),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

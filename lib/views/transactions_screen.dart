import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/widgets/kit.dart';
import '../domain/enums.dart';
import '../domain/money.dart';
import '../domain/transaction.dart';
import '../state/app_state.dart';
import 'widgets/charts.dart';
import 'widgets/txn_common.dart';
import 'widgets/txn_detail_sheet.dart';
import 'widgets/txn_row.dart';

/// Activity: the month's ledger, grouped by day, with search and one-tap
/// filtering. Amounts are never coloured red — spending is normal, not an error.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final TextEditingController _search = TextEditingController();
  int _monthOffset = 0;
  SpendCategoryKind? _kindFilter;
  bool _needsReviewOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = T.of(context);
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month + _monthOffset);
    final monthEnd = DateTime(now.year, now.month + _monthOffset + 1);
    final transactions = state.data.transactions;
    final monthTransactions = transactions
        .where((txn) {
          final at = txn.occurredAt;
          return !at.isBefore(monthStart) && at.isBefore(monthEnd);
        })
        .toList(growable: false);

    final Widget body;
    if (state.isLoading && transactions.isEmpty) {
      body = const _ActivitySkeleton();
    } else if (transactions.isEmpty) {
      body = _EmptyActivity(state: state);
    } else {
      final totals = _totals(monthTransactions);
      final categories = _categoriesInMonth(monthTransactions);
      final query = _search.text.trim().toLowerCase();
      final visible = monthTransactions.where((txn) {
        if (_kindFilter != null && txn.categoryKind != _kindFilter) return false;
        if (_needsReviewOnly && !txn.needsReview) return false;
        if (query.isEmpty) return true;
        final haystack =
            '${txn.title} ${txn.merchant ?? ''} ${txn.categoryName ?? ''}';
        return haystack.toLowerCase().contains(query);
      }).toList()..sort((a, b) => b.occurredAtMs.compareTo(a.occurredAtMs));

      final groups = <DateTime, List<Txn>>{};
      for (final txn in visible) {
        final at = txn.occurredAt;
        final day = DateTime(at.year, at.month, at.day);
        groups.putIfAbsent(day, () => []).add(txn);
      }

      final daysInMonth = monthEnd.difference(monthStart).inDays;
      final daily = _dailySpend(
        monthTransactions,
        daysInMonth,
        now,
        _monthOffset,
      );
      final isCurrentMonth = _monthOffset == 0;

      body = RefreshIndicator(
        onRefresh: state.scanInbox,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, 96),
          children: [
            AppCard(
              shadow: true,
              padding: const EdgeInsets.fromLTRB(T.s2, T.s2, T.s2, T.s4),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: () =>
                            setState(() => _monthOffset = _monthOffset - 1),
                        icon: const Icon(Icons.chevron_left_rounded),
                        color: p.inkSecondary,
                      ),
                      Expanded(
                        child: Text(
                          monthYearLabel(monthStart),
                          textAlign: TextAlign.center,
                          style: T.cardTitle.copyWith(
                            color: p.ink,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: _monthOffset >= 0
                            ? null
                            : () => setState(
                                () => _monthOffset = _monthOffset + 1,
                              ),
                        icon: const Icon(Icons.chevron_right_rounded),
                        color: p.inkSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: T.s1),
                  Text(
                    'Spent',
                    style: T.label.copyWith(
                      color: p.inkMuted,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: MoneyText(
                      totals.spent,
                      animate: true,
                      style: T.moneyLarge(p.ink).copyWith(fontSize: 30),
                    ),
                  ),
                  const SizedBox(height: T.s1),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '+${inr(totals.income)}',
                          style: T.money.copyWith(
                            color: p.primary,
                            fontSize: 13,
                          ),
                        ),
                        TextSpan(
                          text: ' in  ·  ',
                          style: T.bodySmall.copyWith(color: p.inkMuted),
                        ),
                        TextSpan(
                          text: '−${inr(totals.out)}',
                          style: T.money.copyWith(
                            color: p.inkSecondary,
                            fontSize: 13,
                          ),
                        ),
                        TextSpan(
                          text: ' out  ·  ',
                          style: T.bodySmall.copyWith(color: p.inkMuted),
                        ),
                        TextSpan(
                          text:
                              '${monthTransactions.length} '
                              '${monthTransactions.length == 1 ? 'entry' : 'entries'}',
                          style: T.bodySmall.copyWith(color: p.inkMuted),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: T.s3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: T.s3),
                    child: DailyBars(
                      values: daily,
                      month: monthStart,
                      todayIndex: isCurrentMonth
                          ? (now.day - 1).clamp(0, daily.length - 1)
                          : null,
                      height: 62,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: T.s4),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              autocorrect: false,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search merchant or category',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: p.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(T.r5),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(T.r5),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(T.r5),
                  borderSide: BorderSide(color: p.primary, width: 1.4),
                ),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () => setState(_search.clear),
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: T.s3),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _kindFilter == null && !_needsReviewOnly,
                    onTap: () => setState(() {
                      _kindFilter = null;
                      _needsReviewOnly = false;
                    }),
                  ),
                  for (final entry in categories.entries) ...[
                    const SizedBox(width: T.s2),
                    _FilterChip(
                      label: entry.value,
                      selected: _kindFilter == entry.key,
                      onTap: () => setState(() {
                        _kindFilter = _kindFilter == entry.key
                            ? null
                            : entry.key;
                        _needsReviewOnly = false;
                      }),
                    ),
                  ],
                  if (state.data.needsReview.isNotEmpty) ...[
                    const SizedBox(width: T.s2),
                    _FilterChip(
                      label: 'Needs review',
                      icon: Icons.flag_rounded,
                      selected: _needsReviewOnly,
                      onTap: () => setState(() {
                        _needsReviewOnly = !_needsReviewOnly;
                        _kindFilter = null;
                      }),
                    ),
                  ],
                  const SizedBox(width: T.s5),
                ],
              ),
            ),
            const SizedBox(height: T.s1),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: T.s7),
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 36,
                      color: p.inkMuted,
                    ),
                    const SizedBox(height: T.s2),
                    Text(
                      monthTransactions.isEmpty
                          ? 'No transactions in ${monthYearLabel(monthStart)}.'
                          : 'Nothing matches these filters.',
                      textAlign: TextAlign.center,
                      style: T.body.copyWith(color: p.inkSecondary),
                    ),
                  ],
                ),
              ),
            if (visible.isNotEmpty)
              for (final entry in groups.entries) ...[
                TxnDayHeader(
                  day: entry.key,
                  outflow: _totals(entry.value).out,
                  inflow: _totals(entry.value).income,
                ),
                AppCard(
                  padding: EdgeInsets.zero,
                  radius: T.r3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(T.r3),
                    child: Column(
                      children: [
                        for (var i = 0; i < entry.value.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: 64,
                              color: p.outlineVariant,
                            ),
                          TxnRow(
                            txn: entry.value[i],
                            onTap: () => showTransactionDetail(
                              context,
                              entry.value[i],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Activity'), titleSpacing: T.s5),
      body: SafeArea(top: false, bottom: false, child: body),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: T.fast,
            curve: T.curveOut,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: T.s3),
            decoration: BoxDecoration(
              color: selected ? p.ink : p.surface,
              borderRadius: BorderRadius.circular(T.r5),
              border: Border.all(
                color: selected ? p.ink : p.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 14,
                    color: selected ? p.bg : p.inkSecondary,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  maxLines: 1,
                  style: T.bodySmall.copyWith(
                    color: selected ? p.bg : p.inkSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: state.scanInbox,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(T.s5, T.s6, T.s5, 96),
        children: [
          EmptyState(
            icon: Icons.receipt_long_rounded,
            title: 'Nothing here yet',
            body:
                'Scan your bank and UPI messages and every spend, credit and '
                'transfer lands here, grouped by day.',
            actionLabel: 'Scan SMS',
            onAction: state.scanInbox,
            secondaryLabel: 'See a demo',
            onSecondary: state.startDemo,
          ),
        ],
      ),
    );
  }
}

class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, 96),
      children: const [
        SkeletonBox(height: 248, radius: T.r3),
        SizedBox(height: T.s4),
        SkeletonBox(height: 52, radius: T.r5),
        SizedBox(height: T.s3),
        SkeletonBox(height: 28, width: 240, radius: T.r5),
        SizedBox(height: T.s4),
        SkeletonBox(height: 180, radius: T.r3),
        SizedBox(height: T.s4),
        SkeletonBox(height: 180, radius: T.r3),
      ],
    );
  }
}

({Paise spent, Paise income, Paise out}) _totals(List<Txn> transactions) {
  var spent = 0;
  var income = 0;
  var out = 0;
  for (final txn in transactions) {
    switch (txn.kind) {
      case TxnKind.spend:
        spent += txn.amountPaise;
        out += txn.amountPaise;
      case TxnKind.cash:
        out += txn.amountPaise;
      case TxnKind.income:
        income += txn.amountPaise;
      case TxnKind.transfer:
        break;
    }
  }
  return (spent: Paise(spent), income: Paise(income), out: Paise(out));
}

Map<SpendCategoryKind, String> _categoriesInMonth(List<Txn> transactions) {
  final labels = <SpendCategoryKind, String>{};
  for (final txn in transactions) {
    final name = txn.categoryName?.trim();
    labels.putIfAbsent(
      txn.categoryKind,
      () => name == null || name.isEmpty
          ? categoryKindLabel(txn.categoryKind)
          : name,
    );
  }
  final sorted = labels.entries.toList()
    ..sort((a, b) => a.key.index.compareTo(b.key.index));
  return {for (final entry in sorted) entry.key: entry.value};
}

List<int> _dailySpend(
  List<Txn> transactions,
  int daysInMonth,
  DateTime now,
  int monthOffset,
) {
  final length = monthOffset == 0
      ? now.day.clamp(1, daysInMonth).toInt()
      : daysInMonth;
  final values = List<int>.filled(length, 0);
  for (final txn in transactions) {
    if (txn.kind != TxnKind.spend) continue;
    final index = txn.occurredAt.day - 1;
    if (index < 0 || index >= length) continue;
    values[index] += txn.amountPaise;
  }
  return values;
}

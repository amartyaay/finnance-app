import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/money_format.dart';
import '../app/widgets/kit.dart';
import '../domain/enums.dart';
import '../domain/money.dart';
import '../domain/transaction.dart';
import '../engine/monthly_summary.dart';
import '../state/app_state.dart';
import 'widgets/charts.dart';
import 'widgets/money_in_breakdown.dart';
import 'widgets/txn_common.dart';
import 'widgets/txn_detail_sheet.dart';
import 'widgets/txn_row.dart';

/// A request another screen sends to Activity: switch tab and land on a slice.
///
/// [serial] makes a repeated request distinguishable from the previous one (two
/// taps on the same insight must both apply), and every field is a filter the
/// ledger already understands.
class ActivityRequest {
  const ActivityRequest({
    this.serial = 0,
    this.category,
    this.query,
    this.transfersOnly = false,
    this.needsReviewOnly = false,
  });

  final int serial;
  final SpendCategoryKind? category;

  /// A merchant or category name to search for, so "duplicate charge at X" can
  /// land on the rows for X instead of the whole month.
  final String? query;

  final bool transfersOnly;
  final bool needsReviewOnly;

  ActivityRequest withSerial(int value) => ActivityRequest(
    serial: value,
    category: category,
    query: query,
    transfersOnly: transfersOnly,
    needsReviewOnly: needsReviewOnly,
  );
}

/// Activity: the month's ledger, grouped by day, with search and one-tap
/// filtering. Amounts are never coloured red — spending is normal, not an error.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    super.key,
    this.request = const ActivityRequest(),
  });

  /// Applied on arrival and again when [AppShell] sends a new one.
  final ActivityRequest request;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final TextEditingController _search = TextEditingController();
  int _monthOffset = 0;
  SpendCategoryKind? _kindFilter;

  /// Money moved, not spend: card bill payments, SIPs, self transfers. This is
  /// the filter behind the hero's "transfers not counted" line.
  bool _transfersOnly = false;
  bool _needsReviewOnly = false;

  @override
  void initState() {
    super.initState();
    _applyRequest(widget.request);
  }

  @override
  void didUpdateWidget(TransactionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.request.serial != oldWidget.request.serial) {
      setState(() => _applyRequest(widget.request));
    }
  }

  void _applyRequest(ActivityRequest request) {
    if (request.serial == 0) return;
    _monthOffset = 0;
    _kindFilter = request.category;
    _transfersOnly = request.transfersOnly;
    _needsReviewOnly = request.needsReviewOnly;
    _search.text = request.query ?? '';
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = T.of(context);
    final now = state.now;
    final monthStart = DateTime(now.year, now.month + _monthOffset);
    final monthEnd = DateTime(now.year, now.month + _monthOffset + 1);
    final transactions = state.data.transactions;
    // One summary for the displayed month, so the header's "out", "income" and
    // entry count are the *same* definitions Home prints.
    final summary = const SummaryCalculator().forMonth(
      transactions,
      now,
      monthOffset: _monthOffset,
    );
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
      final categories = _categoriesInMonth(monthTransactions);
      final hasTransfers = monthTransactions.any(
        (txn) => txn.kind == TxnKind.transfer,
      );
      final query = _search.text.trim().toLowerCase();
      final visible = monthTransactions.where((txn) {
        if (_kindFilter != null && txn.categoryKind != _kindFilter) return false;
        if (_transfersOnly && txn.kind != TxnKind.transfer) return false;
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
                      summary.spend,
                      animate: true,
                      style: T.moneyLarge(p.ink).copyWith(fontSize: 30),
                    ),
                  ),
                  const SizedBox(height: T.s3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: T.s2),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ActivityStat(
                            label: isCurrentMonth
                                ? 'Out this month'
                                : 'Out in ${_monthName(monthStart)}',
                            value: money(summary.moneyOut),
                          ),
                        ),
                        Expanded(
                          child: _ActivityStat(
                            label: 'Income',
                            value: money(summary.income),
                          ),
                        ),
                        Expanded(
                          child: _ActivityStat(
                            label: summary.txnCount == 1
                                ? 'Entry'
                                : 'Entries',
                            value: '${summary.txnCount}',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: T.s3),
                  _ActivityCaption(
                    periodLabel: isCurrentMonth
                        ? 'Out this month'
                        : 'Out in ${_monthName(monthStart)}',
                    summary: summary,
                    moneyIn: moneyInGroups(
                      transactions,
                      monthStart: monthStart,
                      monthEnd: monthEnd,
                    ),
                  ),
                  const SizedBox(height: T.s2),
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
            ChipStrip(
              children: [
                FilterChipView(
                  label: 'All',
                  selected:
                      _kindFilter == null &&
                      !_transfersOnly &&
                      !_needsReviewOnly,
                  onTap: () => setState(() {
                    _kindFilter = null;
                    _transfersOnly = false;
                    _needsReviewOnly = false;
                  }),
                ),
                if (hasTransfers)
                  FilterChipView(
                    label: 'Transfers',
                    icon: Icons.swap_horiz_rounded,
                    selected: _transfersOnly,
                    onTap: () => setState(() {
                      _transfersOnly = !_transfersOnly;
                      _kindFilter = null;
                      _needsReviewOnly = false;
                    }),
                  ),
                for (final entry in categories.entries)
                  if (!hasTransfers || entry.value != 'Transfers')
                    FilterChipView(
                      label: entry.value,
                      selected: _kindFilter == entry.key,
                      onTap: () => setState(() {
                        _kindFilter = _kindFilter == entry.key
                            ? null
                            : entry.key;
                        _transfersOnly = false;
                        _needsReviewOnly = false;
                      }),
                    ),
                if (state.data.needsReview.isNotEmpty)
                  FilterChipView(
                    label: 'Needs review',
                    icon: Icons.flag_rounded,
                    selected: _needsReviewOnly,
                    onTap: () => setState(() {
                      _needsReviewOnly = !_needsReviewOnly;
                      _kindFilter = null;
                      _transfersOnly = false;
                    }),
                  ),
              ],
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

    // Transparent: the shell paints the ambient glow behind every tab.
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Activity'), titleSpacing: T.s5),
      body: SafeArea(top: false, bottom: false, child: body),
    );
  }
}

/// One of the three month figures under Activity's headline. The labels are
/// deliberately the same words Home uses ("Out this month", "Income").
class _ActivityStat extends StatelessWidget {
  const _ActivityStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            softWrap: false,
            style: T.money.copyWith(
              color: p.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: T.label.copyWith(
            color: p.inkMuted,
            fontSize: 11.5,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

/// The two explanations under Activity's figures: what the "out" total includes,
/// and every rupee that came in, grouped by why it arrived. This is the line
/// that stops "no income" on Home and "+â‚¹3,939 in" here from contradicting.
class _ActivityCaption extends StatelessWidget {
  const _ActivityCaption({
    required this.periodLabel,
    required this.summary,
    required this.moneyIn,
  });

  final String periodLabel;
  final MonthlySummary summary;
  final List<MoneyInGroup> moneyIn;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final included = <String>[
      if (summary.cardBillPaymentPaise > 0)
        '${money(Paise(summary.cardBillPaymentPaise))} card bills',
      if (summary.cashPaise > 0) '${money(Paise(summary.cashPaise))} cash',
    ];
    final lines = <String?>[
      if (included.isNotEmpty)
        '$periodLabel includes ${included.join(' · ')}',
      moneyIn.isEmpty
          ? (summary.hasTrueIncome
                ? null
                : 'No salary, refund or transfer messages this month.')
          : 'Money in: ${moneyInLine(moneyIn)}'
                '${summary.hasTrueIncome ? '' : ' · Salary: none found'}',
      if (!summary.hasTrueIncome && moneyIn.isNotEmpty)
        'Only salary and interest count as income; refunds and transfers do not.',
    ].whereType<String>().toList(growable: false);
    if (lines.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(top: T.s1),
            child: Text(
              line,
              textAlign: TextAlign.center,
              style: T.bodySmall.copyWith(
                color: p.inkMuted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
      ],
    );
  }
}

String _monthName(DateTime date) => monthYearLabel(date).split(' ').first;

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

/// One day's own figures, using the same definitions as the month header:
/// "out" is spend + cash + card-bill payments, "income" is real income only.
({Paise spent, Paise income, Paise out}) _totals(List<Txn> transactions) {
  var spent = 0;
  var income = 0;
  var out = 0;
  for (final txn in transactions) {
    if (countsAsTrueIncome(txn)) income += txn.amountPaise;
    switch (txn.kind) {
      case TxnKind.spend:
        spent += txn.amountPaise;
        out += txn.amountPaise;
      case TxnKind.cash:
        out += txn.amountPaise;
      case TxnKind.income:
        break;
      case TxnKind.transfer:
        if (txn.transferReason == TransferReason.creditCardBill) {
          out += txn.amountPaise;
        }
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/widgets/kit.dart';
import '../domain/enums.dart';
import '../domain/money.dart';
import '../domain/transaction.dart';
import '../state/app_state.dart';
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
    final scheme = Theme.of(context).colorScheme;
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
                        color: scheme.onSurfaceVariant,
                      ),
                      Expanded(
                        child: Text(
                          monthYearLabel(monthStart),
                          textAlign: TextAlign.center,
                          style: T.title.copyWith(color: scheme.onSurface),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: _monthOffset >= 0
                            ? null
                            : () =>
                                  setState(() => _monthOffset = _monthOffset + 1),
                        icon: const Icon(Icons.chevron_right_rounded),
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  Text(
                    'Spent',
                    style: T.label.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    inr(totals.spent),
                    style: T.moneyLarge(scheme.onSurface),
                  ),
                  const SizedBox(height: T.s1),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: inr(totals.income),
                          style: T.money.copyWith(
                            color: T.primary,
                            fontSize: 13,
                          ),
                        ),
                        TextSpan(
                          text: ' in  ·  ',
                          style: T.bodySmall.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        TextSpan(
                          text: inr(totals.out),
                          style: T.money.copyWith(
                            color: scheme.onSurface,
                            fontSize: 13,
                          ),
                        ),
                        TextSpan(
                          text: ' out  ·  ',
                          style: T.bodySmall.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        TextSpan(
                          text:
                              '${monthTransactions.length} '
                              '${monthTransactions.length == 1 ? 'entry' : 'entries'}',
                          style: T.bodySmall.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
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
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    showCheckmark: false,
                    selected: _kindFilter == null && !_needsReviewOnly,
                    onSelected: (_) => setState(() {
                      _kindFilter = null;
                      _needsReviewOnly = false;
                    }),
                  ),
                  for (final entry in categories.entries) ...[
                    const SizedBox(width: T.s2),
                    ChoiceChip(
                      label: Text(entry.value),
                      showCheckmark: false,
                      selected: _kindFilter == entry.key,
                      onSelected: (_) => setState(() {
                        _kindFilter = _kindFilter == entry.key
                            ? null
                            : entry.key;
                        _needsReviewOnly = false;
                      }),
                    ),
                  ],
                  if (state.data.needsReview.isNotEmpty) ...[
                    const SizedBox(width: T.s2),
                    ChoiceChip(
                      avatar: const Icon(Icons.flag_outlined, size: 16),
                      label: const Text('Needs review'),
                      showCheckmark: false,
                      selected: _needsReviewOnly,
                      onSelected: (_) => setState(() {
                        _needsReviewOnly = !_needsReviewOnly;
                        _kindFilter = null;
                      }),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: T.s2),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: T.s7),
                child: Text(
                  monthTransactions.isEmpty
                      ? 'No transactions in ${monthYearLabel(monthStart)}.'
                      : 'Nothing matches these filters.',
                  textAlign: TextAlign.center,
                  style: T.body.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            if (visible.isNotEmpty)
              for (final entry in groups.entries) ...[
                TxnDayHeader(
                  day: entry.key,
                  outflow: _totals(entry.value).out,
                  inflow: _totals(entry.value).income,
                ),
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 56, endIndent: T.s1),
                  TxnRow(
                    txn: entry.value[i],
                    onTap: () =>
                        showTransactionDetail(context, entry.value[i]),
                  ),
                ],
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

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: state.scanInbox,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(T.s5, T.s8, T.s5, 96),
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
      children: [
        const SkeletonBox(height: 148, radius: T.r3),
        const SizedBox(height: T.s4),
        const SkeletonBox(height: 48, radius: T.r2),
        const SizedBox(height: T.s3),
        for (var i = 0; i < 6; i++) ...[
          const SizedBox(height: T.s2),
          const SkeletonBox(height: 56, radius: T.r2),
        ],
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

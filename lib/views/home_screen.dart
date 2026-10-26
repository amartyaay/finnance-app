import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/money_format.dart';
import '../app/widgets/kit.dart';
import '../data/finance_repository.dart';
import '../domain/money.dart';
import '../domain/sms_inbox.dart';
import '../domain/transaction.dart';
import '../engine/card_metrics.dart';
import '../engine/monthly_summary.dart';
import '../state/app_state.dart';
import 'sms_inbox_screen.dart';
import 'transactions_screen.dart';
import '../state/statements_controller.dart';
import 'statements_screen.dart';
import 'widgets/money_in_breakdown.dart';
import 'widgets/txn_common.dart';
import 'widgets/txn_detail_sheet.dart';
import 'widgets/txn_row.dart';

/// The dashboard. Answers three questions in one screen, in this order:
/// how much have I spent, is anything wrong, and where did it go.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    this.onNavigate,
    this.onOpenSettings,
    this.onOpenActivity,
  });

  /// Switches the shell tab (1 = activity, 2 = cards, 3 = insights).
  final ValueChanged<int>? onNavigate;

  /// Opens Activity with a filter already applied (transfers, category, queue).
  final ValueChanged<ActivityRequest>? onOpenActivity;

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    var data = state.data;

    if (state.isLoading && data.isEmpty) {
      return const _HomeSkeleton();
    }
    if (data.isEmpty) {
      return _EmptyHome(state: state);
    }

    // Home shows a day, a week or a month, back to the oldest transaction.
    // Only the two summaries change; alerts and bills always describe today.
    final period = state.period;
    final offset = state.periodOffset;
    final isCurrent = offset == 0;
    final now = state.now;
    if (!isCurrent || period != SpendPeriod.month) {
      const calc = SummaryCalculator();
      data = data.withSummaries(
        calc.forPeriod(data.transactions, now, period, offset: offset),
        calc.forPeriod(data.transactions, now, period, offset: offset - 1),
      );
    }
    final summary = data.summary;
    final hasAttention =
        isCurrent &&
        (data.phishingAlerts.isNotEmpty ||
            data.unpaidBillCount > 0 ||
            data.needsReviewCount > 0);

    return Column(
      children: [
        // Fixed, like the other tabs' titles: the list scrolls under it and
        // never under the status bar.
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, T.s3),
            child: Column(
              children: [
                _PeriodHeader(
                  period: period,
                  start: summary.monthStart,
                  offset: offset,
                  history: state.periodsOfHistory,
                  greeting: _greeting(now),
                  onChange: state.setPeriodOffset,
                  onPick: () => _showPeriods(context, state),
                  trailing: [
                    if (state.isDemo)
                      Padding(
                        padding: const EdgeInsets.only(right: T.s1),
                        child: ActionChip(
                          label: const Text('Demo'),
                          onPressed: state.exitDemo,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Settings',
                      style: _headerButton(context),
                      onPressed: onOpenSettings,
                      icon: const Icon(PhosphorIconsRegular.gearSix, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: T.s3),
                PeriodTabs(value: period, onChanged: state.setPeriod),
              ],
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: state.scanInbox,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, 104),
                  sliver: SliverList.list(
                    children: [
                      Entrance(
                        index: 0,
                        child: _HeroCard(
                          data: data,
                          isCurrent: isCurrent,
                          offset: offset,
                          onOpenActivity: onOpenActivity,
                        ),
                      ),
                      if (hasAttention) ...[
                        const SizedBox(height: T.s3),
                        Entrance(
                          index: 1,
                          child: _AttentionRow(
                            data: data,
                            onNavigate: onNavigate,
                          ),
                        ),
                      ],
                      if (summary.byCategory.isNotEmpty) ...[
                        const SizedBox(height: T.s5),
                        Entrance(
                          index: 2,
                          child: _CategoryCard(
                            summary: summary,
                            onSeeAll: () => onNavigate?.call(3),
                          ),
                        ),
                      ],
                      const SizedBox(height: T.s5),
                      Entrance(
                        index: 3,
                        child: _RecentList(
                          title: isCurrent && period == SpendPeriod.month
                              ? 'Recent'
                              : 'Latest, ${periodTitle(period, summary.monthStart, offset).toLowerCase()}',
                          transactions: [
                            for (final t in data.transactions)
                              if (!t.occurredAt.isBefore(state.periodStart) &&
                                  t.occurredAt.isBefore(state.periodEnd))
                                t,
                          ],
                          onSeeAll: () => onNavigate?.call(1),
                        ),
                      ),
                      const SizedBox(height: T.s5),
                      _PrivacyFooter(
                        smsRead: data.smsMessagesRead,
                        needsReview: data.needsReviewCount,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static ButtonStyle _headerButton(BuildContext context) {
    final p = T.of(context);
    return IconButton.styleFrom(
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      foregroundColor: p.ink,
      fixedSize: const Size(44, 44),
      side: const BorderSide(color: T.glassEdge),
    );
  }

  /// Every day / week / month back to the oldest transaction (at most a
  /// year of them), newest first, with what was spent: the "over time" view,
  /// and a way to jump to any one.
  static void _showPeriods(BuildContext context, AppState state) {
    final p = T.of(context);
    const calc = SummaryCalculator();
    final now = state.now;
    final period = state.period;
    final limit = switch (period) {
      SpendPeriod.day => 60,
      SpendPeriod.week => 53,
      SpendPeriod.month => 24,
    };
    final rows = [
      for (var o = 0; o >= -state.periodsOfHistory && -o < limit; o--)
        (
          offset: o,
          summary: calc.forPeriod(
            state.data.transactions,
            now,
            period,
            offset: o,
          ),
        ),
    ];
    final peak = rows.fold<int>(1, (m, e) => math.max(m, e.summary.spendPaise));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s6),
            children: [
              Text(switch (period) {
                SpendPeriod.day => 'Day by day',
                SpendPeriod.week => 'Week by week',
                SpendPeriod.month => 'Month by month',
              }, style: T.title.copyWith(color: p.ink)),
              const SizedBox(height: T.s1),
              Text(
                'What you spent. Tap one to see it.',
                style: T.bodySmall.copyWith(color: p.inkMuted),
              ),
              const SizedBox(height: T.s3),
              for (final r in rows)
                InkWell(
                  borderRadius: BorderRadius.circular(T.r3),
                  onTap: () {
                    Navigator.pop(sheet);
                    state.setPeriodOffset(r.offset);
                  },
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.symmetric(
                      horizontal: T.s3,
                      vertical: T.s2,
                    ),
                    decoration: r.offset == state.periodOffset
                        ? T.glass(radius: T.r3)
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                periodTitle(
                                  period,
                                  r.summary.monthStart,
                                  r.offset,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: T.body.copyWith(
                                  color: p.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              money(r.summary.spend),
                              style: T.money.copyWith(
                                color: p.ink,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
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
                                height: 5,
                                color: Colors.white.withValues(alpha: 0.07),
                              ),
                              FractionallySizedBox(
                                widthFactor: (r.summary.spendPaise / peak)
                                    .clamp(0.0, 1.0),
                                child: Container(
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [T.teal, T.blue],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _greeting(DateTime now) {
    final hour = now.hour;
    if (hour < 5) return 'Late night';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Truncate on a word boundary, so a warning never ends mid-URL.
  static String _clipWords(String text, int max) {
    final clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length <= max) return clean;
    final window = clean.substring(0, max);
    final space = window.lastIndexOf(' ');
    final cut = space > max ~/ 2 ? window.substring(0, space) : window;
    return '${cut.trimRight()}…';
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.data,
    required this.isCurrent,
    this.offset = 0,
    this.onOpenActivity,
  });

  final int offset;

  final HomeData data;

  /// False when Home is looking at a past month: no pace, no "still due".
  final bool isCurrent;
  final ValueChanged<ActivityRequest>? onOpenActivity;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final summary = data.summary;
    final period = summary.period;
    final monthName = DateFormat.MMMM().format(summary.monthStart);
    final when = periodPhrase(period, summary.monthStart, offset);
    final outLabel = period == SpendPeriod.month && !isCurrent
        ? 'Out in $monthName'
        : 'Out $when';

    // True income only. When no salary/interest credit exists there is no honest
    // "left over", so the row reports what left the accounts and what is still
    // owed instead of deriving a figure from ₹0.
    final hasIncome = data.hasTrueIncome;
    final left = data.left;
    final stats = <({String label, String value})>[
      if (hasIncome) ...[
        (label: 'Came in', value: money(summary.income)),
        // The same definition Activity and Cards use: spend + cash + card
        // bills, never category spend alone.
        (label: outLabel, value: money(data.moneyOut)),
        (
          label: left.value < 0 ? 'Over' : 'Left',
          // "Over" is a magnitude, so it never carries a minus sign.
          value: money(Paise(left.value.abs())),
        ),
      ] else ...[
        (label: outLabel, value: money(data.moneyOut)),
        if (isCurrent && data.unpaidBillCount > 0)
          (
            label: data.unpaidBillCount == 1
                ? 'Still due'
                : 'Still due (${data.unpaidBillCount})',
            value: money(data.stillDue),
          ),
        // The one per-day figure on this screen. The hero used to print
        // "₹812.52 a day" above a stat that said "₹813" — the same value in two
        // formats, three lines apart.
        period == SpendPeriod.day
            ? (
                label: summary.txnCount == 1 ? 'Entry' : 'Entries',
                value: '${summary.txnCount}',
              )
            : (label: 'Spend / day', value: money(summary.dailyAverage)),
      ],
    ];

    // Every part of the footnote is a model field, and each one says whether it
    // is inside the spend headline or deliberately outside it.
    final cardBills = summary.cardBillPaymentPaise;
    final cash = summary.cashPaise;
    final otherTransfers = summary.transferPaise - cardBills;
    // The salary an imported statement found, and the cycle it is in.
    final statementLine = _statementLine(context.watch<StatementsController>());
    final included = <String>[
      if (cardBills > 0) '${money(Paise(cardBills))} card bills',
      if (cash > 0) '${money(Paise(cash))} cash',
    ];
    final includedLine = included.isEmpty
        ? null
        : hasIncome
        ? 'Left is after ${included.join(' + ')}'
        : '$outLabel includes ${included.join(' + ')}';

    // All money-in, by why it arrived. Refunds and transfers are shown but
    // never re-badged as income: that was the "no income vs +₹3,939 in" clash.
    final moneyIn = moneyInGroups(
      data.transactions,
      monthStart: summary.monthStart,
      monthEnd: DateTime(summary.monthStart.year, summary.monthStart.month + 1),
    );
    final moneyInText = moneyIn.isEmpty
        ? (hasIncome
              ? 'Money in: none found this month.'
              : 'No salary, refund or transfer messages this month.')
        : 'Money in: ${moneyInLine(moneyIn)}'
              '${hasIncome ? '' : ' · Salary: none found'}';

    // Projection, not a like-for-like comparison with a full previous month.
    // Saying "on pace" here keeps this pill and Insights' projection identical.
    final showPace =
        isCurrent &&
        summary.daysElapsed < summary.daysInMonth &&
        summary.projectedSpendPaise > 0;
    final paceLabel = 'On pace for ${money(summary.projectedSpend)}';

    final monthEnd = DateTime(
      summary.monthStart.year,
      summary.monthStart.month + 1,
    );
    final fromStatement = data.transactions
        .where(
          (t) =>
              t.sourceType == TxnSourceType.statement &&
              !t.occurredAt.isBefore(summary.monthStart) &&
              t.occurredAt.isBefore(monthEnd),
        )
        .length;
    final provenance = <String>[
      if (fromStatement > 0)
        '$fromStatement from your bank statement (it replaces that '
            "account's SMS for the days it covers)",
      if (data.smsMessagesRead > 0) '${data.smsMessagesRead} messages read',
      data.needsReviewCount > 0
          ? '${data.needsReviewCount} to confirm'
          : 'all clear',
      if (data.lastScanAt != null) 'as of ${clockTime(data.lastScanAt!)}',
    ].join(' · ');

    final spoken = <String>[
      monthYearLabel(summary.monthStart),
      'Spent ${_spoken(summary.spend)}',
      if (showPace) 'On pace for ${_spoken(summary.projectedSpend)}',
      if (hasIncome)
        '${_spoken(summary.income)} came in; ${left.value < 0 ? '${_spoken(Paise(left.value.abs()))} over' : '${_spoken(Paise(left.value.abs()))} left'}'
      else
        'No salary or interest credit found, so there is no left over figure. ${_spoken(data.moneyOut)} went out of your accounts',
      if (!hasIncome && data.unpaidBillCount > 0)
        '${_spoken(data.stillDue)} still due across ${data.unpaidBillCount} ${data.unpaidBillCount == 1 ? 'card bill' : 'card bills'}',
      if (hasIncome) 'Out this month ${_spoken(data.moneyOut)}',
      if (moneyIn.isNotEmpty) 'Money in, not income: ${moneyInLine(moneyIn)}',
    ].join('. ');

    // Everything that used to crowd the hero, one tap away.
    void showDetails() {
      final lines = [
        ?includedLine,
        moneyInText,
        provenance,
      ].where((t) => t.trim().isNotEmpty).toList();
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheet) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How this is counted',
                  style: T.title.copyWith(color: p.ink),
                ),
                const SizedBox(height: T.s2),
                Text(
                  'Spent is what you paid merchants this month. Card-bill '
                  'payments, money moved between your own accounts, investments '
                  'and refunds are kept out of it.',
                  style: T.body.copyWith(color: p.inkSecondary),
                ),
                const SizedBox(height: T.s3),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: T.s2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7, right: T.s2),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: T.teal,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            line,
                            style: T.bodySmall.copyWith(color: p.inkSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: T.s2),
                if (otherTransfers > 0 && onOpenActivity != null)
                  _SheetLink(
                    icon: PhosphorIconsRegular.arrowsLeftRight,
                    text:
                        '${money(Paise(otherTransfers))} transfers not counted',
                    onTap: () {
                      Navigator.pop(sheet);
                      onOpenActivity!(
                        const ActivityRequest(transfersOnly: true),
                      );
                    },
                  ),
                if (!hasIncome)
                  _SheetLink(
                    icon: PhosphorIconsRegular.bank,
                    text:
                        statementLine ??
                        'No salary in your SMS. Import an SBI statement to see '
                            'each month salary to salary',
                    onTap: () {
                      Navigator.pop(sheet);
                      StatementsScreen.open(context);
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // The hero is read as one sentence (children excluded, so no number is
    // read twice); its links stay reachable as custom actions, which TalkBack
    // lists under "Actions".
    final actions = <CustomSemanticsAction, VoidCallback>{
      const CustomSemanticsAction(label: 'How this is counted'): showDetails,
      if (otherTransfers > 0 && onOpenActivity != null)
        const CustomSemanticsAction(
          label: 'Show the transfers not counted',
        ): () =>
            onOpenActivity!(const ActivityRequest(transfersOnly: true)),
      if (!hasIncome)
        CustomSemanticsAction(
          label: statementLine == null
              ? 'Import an SBI statement to find your salary'
              : 'Open salary to salary',
        ): () =>
            StatementsScreen.open(context),
    };

    return Semantics(
      container: true,
      label: spoken,
      excludeSemantics: true,
      customSemanticsActions: actions.isEmpty ? null : actions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HeroSurface(
            padding: const EdgeInsets.fromLTRB(T.s5, T.s3, T.s2, T.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        period == SpendPeriod.month && !isCurrent
                            ? 'Spent in $monthName'
                            : 'Spent $when',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.body.copyWith(
                          color: p.heroMuted,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'How this is counted',
                      onPressed: showDetails,
                      icon: Icon(
                        PhosphorIconsRegular.info,
                        color: p.heroMuted,
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
                      child: MoneyText(
                        summary.spend,
                        animate: true,
                        style: T.heroNumber.copyWith(
                          fontSize: 50,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: T.s2),
                Text(
                  period == SpendPeriod.day
                      ? '${summary.txnCount} ${summary.txnCount == 1 ? 'entry' : 'entries'} · ${DateFormat('EEEE, d MMMM').format(summary.monthStart)}'
                      : !isCurrent
                      ? '${summary.txnCount} entries · ${money(summary.dailyAverage)} a day'
                      : showPace
                      ? '$paceLabel · Day ${summary.daysElapsed} of ${summary.daysInMonth}'
                      : 'Day ${summary.daysElapsed} of ${summary.daysInMonth}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.body.copyWith(color: p.heroMuted, fontSize: 13.5),
                ),
                const SizedBox(height: T.s4),
                Padding(
                  padding: const EdgeInsets.only(right: T.s3),
                  child: _DailyBars(summary: summary),
                ),
              ],
            ),
          ),
          const SizedBox(height: T.s3),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              // Three tiles side by side at body size; two columns once the
              // text grows, so values are never elided into stubs.
              final twoColumns = constraints.maxWidth < 300 || scale >= 1.2;
              const dots = [T.teal, T.blue, T.violet];
              if (!twoColumns) {
                return Row(
                  children: [
                    for (var i = 0; i < stats.length; i++) ...[
                      if (i > 0) const SizedBox(width: T.s2),
                      Expanded(
                        child: _HeroStat(
                          label: stats[i].label,
                          value: stats[i].value,
                          dot: dots[i % dots.length],
                        ),
                      ),
                    ],
                  ],
                );
              }
              final cellWidth = (constraints.maxWidth - T.s2) / 2;
              return Wrap(
                spacing: T.s2,
                runSpacing: T.s2,
                children: [
                  for (var i = 0; i < stats.length; i++)
                    SizedBox(
                      width: cellWidth,
                      child: _HeroStat(
                        label: stats[i].label,
                        value: stats[i].value,
                        dot: dots[i % dots.length],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _spoken(Paise amount) => moneySpoken(amount);

  static String? _statementLine(StatementsController statements) {
    final analysis = statements.analysis;
    if (analysis == null || !analysis.salary.found || analysis.cycles.isEmpty) {
      return null;
    }
    final cycle = analysis.cycles.first;
    return 'Salary ${money(Paise(analysis.salary.typicalPaise))} (SBI statement) · '
        '${money(Paise(cycle.spentPaise))} spent from the account since '
        '${DateFormat('d MMM').format(cycle.start)}';
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.dot,
  });

  final String label;
  final String value;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(T.s3, T.s3, T.s2, T.s3),
      decoration: T.glass(radius: T.r4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
              softWrap: false,
              style: T.money.copyWith(
                color: p.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
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

/// A row in a sheet that leads somewhere: icon, text, chevron, 48 dp.
class _SheetLink extends StatelessWidget {
  const _SheetLink({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
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
            Icon(icon, color: T.teal, size: 20),
            const SizedBox(width: T.s3),
            Expanded(
              child: Text(text, style: T.body.copyWith(color: p.ink)),
            ),
            Icon(PhosphorIconsRegular.caretRight, color: p.inkMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

/// The month in bars: one gradient column per day so far (a hairline for a
/// day with no spend), faint stubs for the days still to come.
class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.summary});

  final MonthlySummary summary;

  @override
  Widget build(BuildContext context) {
    final daily = summary.dailySpend;
    final peak = daily.isEmpty ? 0 : daily.reduce(math.max);
    final top = peak <= 0 ? 1.0 : peak / 100.0;
    final floor = top * 0.025;
    return ExcludeSemantics(
      child: SizedBox(
        height: 64,
        child: BarChart(
          BarChartData(
            minY: 0,
            maxY: top,
            alignment: BarChartAlignment.spaceBetween,
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(enabled: false),
            barGroups: [
              for (
                var i = 0;
                i <
                    (summary.period == SpendPeriod.day
                        ? 24
                        : summary.daysInMonth);
                i++
              )
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: i < daily.length && daily[i] > 0
                          ? math.max(daily[i] / 100.0, floor * 2)
                          : floor,
                      width: 5,
                      borderRadius: BorderRadius.circular(3),
                      gradient: i < daily.length && daily[i] > 0
                          ? const LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [T.teal, T.blue],
                            )
                          : null,
                      color: i < daily.length && daily[i] > 0
                          ? null
                          : Colors.white.withValues(
                              alpha: i < daily.length ? 0.18 : 0.07,
                            ),
                    ),
                  ],
                ),
            ],
          ),
          duration: Duration.zero,
        ),
      ),
    );
  }
}

class _CompactNotice extends StatelessWidget {
  const _CompactNotice({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.onDismiss,
  });

  final PillTone tone;
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback? onAction;

  /// When set, a 48 dp close button appears; the caller hides the notice.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final fg = switch (tone) {
      PillTone.danger => p.danger,
      PillTone.caution => p.caution,
      PillTone.positive => p.positive,
      PillTone.brand => p.primary,
      _ => p.info,
    };
    // Same language as NoticeBanner: a calm card, a tinted icon disc, ink
    // text; the tone lives in the disc and the action pill.
    return Container(
      padding: const EdgeInsets.fromLTRB(T.s3, T.s3, T.s1, T.s3),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(T.r4),
        border: p.isDark ? Border.all(color: p.outlineVariant) : null,
        boxShadow: p.isDark ? null : p.shadowSoft,
      ),
      child: Row(
        children: [
          IconDisc(icon: icon, color: fg, size: 38),
          const SizedBox(width: T.s3),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.cardTitle.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.bodySmall.copyWith(
                    color: p.inkSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: T.s2),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: fg,
              backgroundColor: fg.withValues(alpha: p.isDark ? 0.16 : 0.09),
              minimumSize: const Size(48, 40),
              padding: const EdgeInsets.symmetric(horizontal: T.s3),
              shape: const StadiumBorder(),
              tapTargetSize: MaterialTapTargetSize.padded,
              textStyle: T.bodySmall.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            child: Text(actionLabel, maxLines: 1),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              tooltip: 'Dismiss',
              icon: Icon(Icons.close_rounded, size: 18, color: p.inkMuted),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

class _Attention extends StatefulWidget {
  const _Attention({required this.data, this.onNavigate});

  final HomeData data;
  final ValueChanged<int>? onNavigate;

  @override
  State<_Attention> createState() => _AttentionState();
}

class _AttentionState extends State<_Attention> {
  /// Dismissed for this visit only: nothing is stored, nothing blocks, and the
  /// same banner comes back on the next launch.
  bool _reviewHidden = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final onNavigate = widget.onNavigate;
    final widgets = <Widget>[];

    for (final alert in data.phishingAlerts.take(1)) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: T.s3),
          child: _CompactNotice(
            tone: PillTone.danger,
            icon: Icons.gpp_maybe_rounded,
            title: 'Possible fraud message',
            body:
                '${alert.sender} · ${HomeScreen._clipWords(alert.preview, 90)}',
            actionLabel: 'Check',
            onAction: () => _showPhishing(context, alert),
          ),
        ),
      );
    }

    // The headline "Bills due" figure is [HomeData.stillDue]; this banner quotes
    // the same sum, so the two can never disagree.
    final unpaid = data.unpaidBillCount;
    if (unpaid > 0) {
      CardMetrics? only;
      if (unpaid == 1) {
        for (final card in data.cards) {
          if (card.billDuePaise > 0) only = card;
        }
      }
      final days = only?.dueDate == null
          ? null
          : daysUntilDate(only!.dueDate!, now: viewNow(context));
      final dueText = days == null ? 'unpaid' : billDuePhrase(days);
      final minimum = only?.minimumDue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: T.s3),
          child: _CompactNotice(
            tone: days != null && days <= 7 ? PillTone.caution : PillTone.info,
            icon: Icons.event_available_rounded,
            title: unpaid == 1
                ? '${only?.card.displayName ?? 'Card'} bill $dueText'
                : '$unpaid card bills unpaid',
            body: unpaid == 1
                ? '${money(data.stillDue)} total due'
                      '${minimum != null ? ' · ${money(minimum)} minimum' : ''}. '
                      'Paying in full avoids interest.'
                : '${money(data.stillDue)} still due across $unpaid cards. '
                      'Paying in full avoids interest.',
            actionLabel: unpaid == 1 ? 'See card' : 'See cards',
            onAction: () => onNavigate?.call(2),
          ),
        ),
      );
    }

    if (data.needsReviewCount > 0 && !_reviewHidden) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: T.s3),
          child: _CompactNotice(
            tone: PillTone.info,
            icon: Icons.help_rounded,
            title: '${data.needsReviewCount} to confirm',
            body: 'We could not name the merchant with confidence.',
            actionLabel: 'Review',
            onAction: () => SmsInboxScreen.open(
              context,
              initialFilter: InboxFilter.unreviewed,
            ),
            onDismiss: () => setState(() => _reviewHidden = true),
          ),
        ),
      );
    }

    if (widgets.isEmpty) return const SizedBox.shrink();
    return Column(children: widgets);
  }

  void _showPhishing(BuildContext context, PhishingAlert alert) {
    final p = T.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Pill(
                    'Likely fraud',
                    tone: PillTone.danger,
                    icon: Icons.gpp_bad_rounded,
                  ),
                  const Spacer(),
                  Text(
                    clockTime(alert.receivedAt),
                    style: T.bodySmall.copyWith(color: p.inkMuted),
                  ),
                ],
              ),
              const SizedBox(height: T.s4),
              Text(
                'From ${alert.sender}',
                style: T.cardTitle.copyWith(color: p.ink),
              ),
              const SizedBox(height: T.s3),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(T.s3),
                decoration: BoxDecoration(
                  color: p.surfaceMuted,
                  borderRadius: BorderRadius.circular(T.r2),
                ),
                child: Text(
                  alert.preview,
                  style: T.body.copyWith(fontSize: 13.5, color: p.inkSecondary),
                ),
              ),
              const SizedBox(height: T.s4),
              Text(
                'Why this was flagged',
                style: T.cardTitle.copyWith(
                  fontWeight: FontWeight.w700,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: T.s2),
              Text(
                'This message uses the wording and links typical of KYC, refund or '
                'parcel scams. Your bank never asks you to confirm details or share an '
                'OTP through a link.',
                style: T.body.copyWith(color: p.inkSecondary),
              ),
              const SizedBox(height: T.s3),
              Text(
                'It was kept out of your spending totals, and no link was opened.',
                style: T.bodySmall.copyWith(color: p.inkMuted),
              ),
              const SizedBox(height: T.s5),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.summary, this.onSeeAll});

  final MonthlySummary summary;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final top = summary.byCategory.take(5).toList();
    final peak = top.isEmpty ? 1 : top.map((c) => c.paise).reduce(math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Where it went',
          action: 'Insights',
          onAction: onSeeAll,
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: T.s2),
        Container(
          padding: const EdgeInsets.fromLTRB(T.s4, T.s2, T.s4, T.s2),
          decoration: T.glass(),
          child: Column(
            children: [
              for (final c in top)
                Semantics(
                  label:
                      '${c.name}, ${moneySpoken(Paise(c.paise))}, '
                      '${(c.share * 100).round()} percent',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: T.s2),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: categoryColor(
                              context,
                              c.kind,
                            ).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(T.r3),
                          ),
                          child: Icon(
                            categoryIcon(c.kind),
                            size: 19,
                            color: categoryColor(context, c.kind),
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
                                      c.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: T.body.copyWith(
                                        color: p.ink,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: T.s2),
                                  Text(
                                    money(Paise(c.paise)),
                                    style: T.money.copyWith(
                                      color: p.ink,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: Stack(
                                  children: [
                                    Container(
                                      height: 5,
                                      color: Colors.white.withValues(
                                        alpha: 0.07,
                                      ),
                                    ),
                                    FractionallySizedBox(
                                      widthFactor: (c.paise / peak).clamp(
                                        0.02,
                                        1.0,
                                      ),
                                      child: Container(
                                        height: 5,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              categoryColor(context, c.kind),
                                              categoryColor(
                                                context,
                                                c.kind,
                                              ).withValues(alpha: 0.55),
                                            ],
                                          ),
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
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Everything that needs the owner, folded into one glass row. Tapping it
/// opens the full notices (fraud first, then bills, then the review queue).
class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.data, this.onNavigate});

  final HomeData data;
  final ValueChanged<int>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final parts = <String>[
      if (data.phishingAlerts.isNotEmpty)
        data.phishingAlerts.length == 1
            ? '1 possible fraud message'
            : '${data.phishingAlerts.length} possible fraud messages',
      if (data.unpaidBillCount > 0)
        data.unpaidBillCount == 1
            ? '1 card bill unpaid'
            : '${data.unpaidBillCount} card bills unpaid',
      if (data.needsReviewCount > 0) '${data.needsReviewCount} to confirm',
    ];
    final count =
        (data.phishingAlerts.isNotEmpty ? 1 : 0) +
        (data.unpaidBillCount > 0 ? 1 : 0) +
        (data.needsReviewCount > 0 ? 1 : 0);
    final fraud = data.phishingAlerts.isNotEmpty;
    final accent = fraud
        ? T.rose
        : data.unpaidBillCount > 0
        ? p.caution
        : T.teal;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(T.r4),
        onTap: () => showModalBottomSheet<void>(
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
                  Text('Needs you', style: T.title.copyWith(color: p.ink)),
                  const SizedBox(height: T.s4),
                  _Attention(
                    data: data,
                    onNavigate: (tab) {
                      Navigator.pop(sheet);
                      onNavigate?.call(tab);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(T.s4, T.s3, T.s3, T.s3),
          decoration: T.glass(),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(T.r3),
                ),
                child: Icon(
                  fraud
                      ? PhosphorIconsFill.shieldWarning
                      : PhosphorIconsFill.bellRinging,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: T.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 1
                          ? '1 thing needs you'
                          : '$count things need you',
                      style: T.body.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      parts.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: T.bodySmall.copyWith(color: p.inkMuted),
                    ),
                  ],
                ),
              ),
              Icon(
                PhosphorIconsRegular.caretRight,
                color: p.inkMuted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({
    required this.title,
    required this.transactions,
    this.onSeeAll,
  });

  final String title;

  final List<Txn> transactions;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    // The ledger arrives oldest-first (dedupe preserves its own ordering), so
    // sort for display: "Recent" is the newest five, not the first five.
    final recent = [...transactions]
      ..sort((a, b) => b.occurredAtMs.compareTo(a.occurredAtMs));
    final top = recent.take(5).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: title,
          action: 'See all',
          onAction: onSeeAll,
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: T.s2),
        if (top.isEmpty)
          AppCard(
            padding: const EdgeInsets.all(T.s4),
            child: Text(
              'Nothing recorded yet.',
              style: T.body.copyWith(color: p.inkMuted),
            ),
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: T.s1),
            child: Column(
              children: [
                for (var i = 0; i < top.length; i++) ...[
                  TxnRow(
                    txn: top[i],
                    onTap: () => showTransactionDetail(context, top[i]),
                  ),
                  if (i != top.length - 1)
                    Divider(
                      height: 1,
                      indent: txnRowTextInset,
                      endIndent: T.s4,
                      color: p.outlineVariant,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _PrivacyFooter extends StatelessWidget {
  const _PrivacyFooter({required this.smsRead, required this.needsReview});

  final int smsRead;
  final int needsReview;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final parts = <String>[
      if (smsRead > 0) '$smsRead messages read',
      if (needsReview > 0) '$needsReview to confirm',
      'nothing uploaded',
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_rounded, size: 14, color: p.inkMuted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            parts.join(' · '),
            textAlign: TextAlign.center,
            style: T.bodySmall.copyWith(color: p.inkMuted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: EmptyState(
              icon: Icons.qr_code_scanner_rounded,
              title: 'No transactions yet',
              body:
                  state.errorMessage ??
                  (state.hasSmsPermission
                      ? 'Your inbox has no bank alerts we could read. Tap scan after a payment, or explore the app with demo data.'
                      : 'Allow SMS access so Hisaab can read bank and UPI alerts, or look around with generated demo data first.'),
              actionLabel: state.hasSmsPermission
                  ? 'Scan inbox'
                  : 'Allow SMS access',
              onAction: state.hasSmsPermission
                  ? state.scanInbox
                  : state.requestPermission,
              secondaryLabel: 'Explore with demo data',
              onSecondary: state.startDemo,
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(T.s5),
        children: const [
          SkeletonBox(height: 30, width: 190),
          SizedBox(height: T.s5),
          SkeletonBox(height: 300, radius: T.r4),
          SizedBox(height: T.s4),
          SkeletonBox(height: 64, radius: T.r3),
          SizedBox(height: T.s3),
          SkeletonBox(height: 288, radius: T.r4),
          SizedBox(height: T.s4),
          SkeletonBox(height: 238, radius: T.r3),
        ],
      ),
    );
  }
}

/// The page title: the period on screen (tap for the list of periods), with
/// back / forward arrows, aligned to the content's edges.
class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({
    required this.period,
    required this.start,
    required this.offset,
    required this.history,
    required this.greeting,
    required this.onChange,
    required this.onPick,
    required this.trailing,
  });

  final SpendPeriod period;
  final DateTime start;
  final int offset;
  final int history;
  final String greeting;
  final ValueChanged<int> onChange;
  final VoidCallback onPick;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final over = offset == 0 && period == SpendPeriod.month
        ? greeting
        : periodSubtitle(period, start);
    final arrow = IconButton.styleFrom(
      minimumSize: const Size(40, 44),
      padding: EdgeInsets.zero,
      foregroundColor: p.ink,
      disabledForegroundColor: p.inkMuted.withValues(alpha: 0.35),
    );
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Choose ${period.label.toLowerCase()}',
            child: InkWell(
              borderRadius: BorderRadius.circular(T.r3),
              onTap: onPick,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    over,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.bodySmall.copyWith(
                      color: p.inkMuted,
                      fontSize: 12,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          periodTitle(period, start, offset),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.title.copyWith(color: p.ink),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        PhosphorIconsRegular.caretDown,
                        size: 16,
                        color: p.inkMuted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Previous ${period.label.toLowerCase()}',
          style: arrow,
          onPressed: offset > -history ? () => onChange(offset - 1) : null,
          icon: const Icon(PhosphorIconsRegular.caretLeft, size: 20),
        ),
        IconButton(
          tooltip: 'Next ${period.label.toLowerCase()}',
          style: arrow,
          onPressed: offset < 0 ? () => onChange(offset + 1) : null,
          icon: const Icon(PhosphorIconsRegular.caretRight, size: 20),
        ),
        const SizedBox(width: T.s2),
        ...trailing,
      ],
    );
  }
}

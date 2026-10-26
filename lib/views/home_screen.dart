import 'dart:math' as math;

import 'package:flutter/material.dart';
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
import '../engine/insights_engine.dart';
import '../engine/monthly_summary.dart';
import '../state/app_state.dart';
import 'insight_actions.dart';
import 'sms_inbox_screen.dart';
import 'transactions_screen.dart';
import '../state/statements_controller.dart';
import 'statements_screen.dart';
import 'widgets/card_face.dart';
import 'widgets/charts.dart';
import 'widgets/insight_tile.dart';
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
    final data = state.data;

    if (state.isLoading && data.isEmpty) {
      return const _HomeSkeleton();
    }
    if (data.isEmpty) {
      return _EmptyHome(state: state);
    }

    final summary = data.summary;
    final hasAttention =
        data.phishingAlerts.isNotEmpty ||
        data.unpaidBillCount > 0 ||
        data.needsReviewCount > 0;

    return RefreshIndicator(
      onRefresh: state.scanInbox,
      child: CustomScrollView(
        slivers: [
          // Scrolls away with the page (no floating bar over content), and is
          // transparent so the shell's ambient glow shows behind it.
          SliverAppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            titleSpacing: T.s5,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(context.read<AppState>().now),
                  style: T.bodySmall.copyWith(
                    color: T.of(context).inkMuted,
                    fontSize: 12,
                  ),
                ),
                Text(
                  monthYearLabel(summary.monthStart),
                  style: T.title.copyWith(color: T.of(context).ink),
                ),
              ],
            ),
            actions: [
              if (state.isDemo)
                Padding(
                  padding: const EdgeInsets.only(right: T.s1),
                  child: Center(
                    child: ActionChip(
                      label: const Text('Demo'),
                      onPressed: state.exitDemo,
                      avatar: const Icon(Icons.science_rounded, size: 15),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              // Round surface buttons: the header reads as part of the page
              // rather than as bare system icons.
              IconButton(
                tooltip: 'Scan SMS',
                style: _headerButton(context),
                onPressed: state.isScanning ? null : state.scanInbox,
                icon: state.isScanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: 20),
              ),
              const SizedBox(width: T.s2),
              IconButton(
                tooltip: 'Settings',
                style: _headerButton(context),
                onPressed: onOpenSettings,
                icon: const Icon(Icons.person_rounded, size: 20),
              ),
              const SizedBox(width: T.s4),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, 104),
            sliver: SliverList.list(
              children: [
                Entrance(
                  index: 0,
                  child: _HeroCard(data: data, onOpenActivity: onOpenActivity),
                ),
                if (hasAttention) ...[
                  const SizedBox(height: T.s3),
                  Entrance(
                    index: 1,
                    child: _Attention(data: data, onNavigate: onNavigate),
                  ),
                ],
                const SizedBox(height: T.s4),
                Entrance(index: 2, child: _PaceSection(summary: summary)),
                if (summary.byCategory.isNotEmpty) ...[
                  const SizedBox(height: T.s4),
                  Entrance(
                    index: 3,
                    child: _CategoryCard(
                      summary: summary,
                      onSeeAll: () => onNavigate?.call(3),
                    ),
                  ),
                ],
                if (data.cards.isNotEmpty) ...[
                  const SizedBox(height: T.s5),
                  Entrance(
                    index: 4,
                    child: _CardStrip(
                      cards: data.cards,
                      onOpen: () => onNavigate?.call(2),
                    ),
                  ),
                ],
                if (data.insights.isNotEmpty) ...[
                  const SizedBox(height: T.s5),
                  Entrance(
                    index: 5,
                    child: _InsightSection(
                      // One countdown for the whole app: the calendar-day
                      // rewrite and the "in 1 days" grammar fix live in
                      // `InsightTile`, together with the chip and the tone.
                      insights: withCalendarDueDates(data.insights, data.cards),
                      transactions: data.transactions,
                      onSeeAll: () => onNavigate?.call(3),
                      onTab: onNavigate,
                      onOpenActivity: onOpenActivity,
                    ),
                  ),
                ],
                const SizedBox(height: T.s5),
                Entrance(
                  index: 6,
                  child: _RecentList(
                    transactions: data.transactions,
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
    );
  }

  static ButtonStyle _headerButton(BuildContext context) {
    final p = T.of(context);
    return IconButton.styleFrom(
      backgroundColor: p.surface,
      foregroundColor: p.ink,
      fixedSize: const Size(44, 44),
      side: BorderSide(color: p.outlineVariant),
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
  const _HeroCard({required this.data, this.onOpenActivity});

  final HomeData data;
  final ValueChanged<ActivityRequest>? onOpenActivity;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final summary = data.summary;

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
        (label: 'Out this month', value: money(data.moneyOut)),
        (
          label: left.value < 0 ? 'Over' : 'Left',
          // "Over" is a magnitude, so it never carries a minus sign.
          value: money(Paise(left.value.abs())),
        ),
      ] else ...[
        (label: 'Out this month', value: money(data.moneyOut)),
        if (data.unpaidBillCount > 0)
          (
            label: data.unpaidBillCount == 1
                ? 'Still due'
                : 'Still due (${data.unpaidBillCount})',
            value: money(data.stillDue),
          ),
        // The one per-day figure on this screen. The hero used to print
        // "₹812.52 a day" above a stat that said "₹813" — the same value in two
        // formats, three lines apart.
        (label: 'Spend / day', value: money(summary.dailyAverage)),
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
        : 'Out this month includes ${included.join(' + ')}';

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
        summary.daysElapsed < summary.daysInMonth &&
        summary.projectedSpendPaise > 0;
    final paceLabel = 'On pace for ${money(summary.projectedSpend)}';

    final provenance = <String>[
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

    // The hero is read as one sentence (children excluded, so no number is
    // read twice); its links stay reachable as custom actions, which TalkBack
    // lists under "Actions".
    final actions = <CustomSemanticsAction, VoidCallback>{
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
      child: HeroSurface(
        padding: const EdgeInsets.fromLTRB(T.s5, T.s5, T.s5, T.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: T.s2,
              runSpacing: T.s2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Spent this month',
                  maxLines: 1,
                  style: T.label.copyWith(
                    color: p.heroMuted,
                    letterSpacing: 0.4,
                    fontSize: 12,
                  ),
                ),
                if (showPace)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: T.s2,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(T.r5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.speed_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            paceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.label.copyWith(
                              color: Colors.white,
                              letterSpacing: 0,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: T.s3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: MoneyText(
                summary.spend,
                animate: true,
                style: T.heroNumber.copyWith(fontSize: 46),
              ),
            ),
            const SizedBox(height: T.s3),
            Row(
              children: [
                Expanded(
                  child: _MonthProgress(
                    fraction: summary.daysInMonth == 0
                        ? 0
                        : summary.daysElapsed / summary.daysInMonth,
                  ),
                ),
                const SizedBox(width: T.s3),
                Text(
                  'Day ${summary.daysElapsed} of ${summary.daysInMonth}',
                  maxLines: 1,
                  style: T.bodySmall.copyWith(
                    color: p.heroMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: T.s5),
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                // Three money columns only fit side by side at body
                // size. Once text grows, reflow to two columns so
                // values are not elided into unreadable stubs.
                final twoColumns = constraints.maxWidth < 260 || scale >= 1.2;
                if (!twoColumns) {
                  return Row(
                    children: [
                      for (var i = 0; i < stats.length; i++) ...[
                        if (i > 0) const SizedBox(width: T.s2),
                        Expanded(
                          child: _HeroStat(
                            label: stats[i].label,
                            value: stats[i].value,
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
                    for (final stat in stats)
                      SizedBox(
                        width: cellWidth,
                        child: _HeroStat(label: stat.label, value: stat.value),
                      ),
                  ],
                );
              },
            ),
            if (otherTransfers > 0 || !hasIncome) const SizedBox(height: T.s2),
            if (otherTransfers > 0)
              _HeroLink(
                text: '${money(Paise(otherTransfers))} transfers not counted',
                semanticsLabel:
                    '${money(Paise(otherTransfers))} moved as transfers and not counted as spending. Show the transfers.',
                onTap: onOpenActivity == null
                    ? null
                    : () => onOpenActivity!(
                        const ActivityRequest(transfersOnly: true),
                      ),
              ),
            if (!hasIncome)
              // SBI rarely sends a salary SMS; its statement shows it.
              _HeroLink(
                icon: Icons.account_balance_rounded,
                text:
                    statementLine ??
                    'No salary in your SMS. Import an SBI statement to see '
                        'each month salary to salary',
                semanticsLabel:
                    statementLine ??
                    'No salary was found in your messages. Import an SBI '
                        'statement to see spending salary to salary.',
                onTap: () => StatementsScreen.open(context),
              ),
            const SizedBox(height: T.s2),
            Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
            const SizedBox(height: T.s3),
            // One footnote instead of three loose lines.
            Text(
              [
                ?includedLine,
                moneyInText,
                provenance,
              ].where((t) => t.trim().isNotEmpty).join(' · '),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: T.bodySmall.copyWith(
                color: p.heroMuted,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ],
        ),
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

/// A tappable line in the hero's receipt. It keeps a 48 dp target even though
/// the type is small, because this is the door into the transfers ledger.
class _HeroLink extends StatelessWidget {
  const _HeroLink({
    required this.text,
    required this.semanticsLabel,
    this.onTap,
    this.icon = Icons.swap_horiz_rounded,
  });

  final IconData icon;
  final String text;
  final String semanticsLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Semantics(
      button: onTap != null,
      label: semanticsLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Icon(icon, size: 15, color: p.heroMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.bodySmall.copyWith(
                    color: p.heroInk,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: p.heroMuted,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 16, color: p.heroMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // A frosted tile: light glass over the hero gradient.
    return Container(
      padding: const EdgeInsets.fromLTRB(T.s3, T.s2 + 2, T.s2, T.s2 + 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(T.r3),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.label.copyWith(
              color: T.of(context).heroMuted,
              fontSize: 11.5,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: T.money.copyWith(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How far through the month we are: a slim mint line under the number.
class _MonthProgress extends StatelessWidget {
  const _MonthProgress({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: SizedBox(
          height: 4,
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: Colors.white.withValues(alpha: 0.14)),
              ),
              FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFE0E7FF), T.mintGlow],
                    ),
                  ),
                  child: SizedBox.expand(),
                ),
              ),
            ],
          ),
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
      final days = only?.dueDate == null ? null : daysUntilDate(only!.dueDate!);
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
      builder: (context) => Padding(
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
    );
  }
}

class _PaceSection extends StatelessWidget {
  const _PaceSection({required this.summary});

  final MonthlySummary summary;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final dayCount = math
        .max(summary.daysElapsed, summary.dailySpend.length)
        .clamp(1, summary.daysInMonth);
    final daily = List<int>.generate(
      dayCount,
      (i) => i < summary.dailySpend.length ? summary.dailySpend[i] : 0,
    );
    final previous = summary.previousSpend;

    return SoftSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "This month's pace",
                  style: T.sectionTitle.copyWith(color: p.ink, fontSize: 16),
                ),
              ),
              const SizedBox(width: T.s2),
              Pill(
                '${summary.daysElapsed} of ${summary.daysInMonth} days',
                tone: PillTone.brand,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: T.s3),
          DailyBars(
            values: daily,
            month: summary.monthStart,
            todayIndex: (summary.daysElapsed - 1).clamp(0, daily.length - 1),
            height: 82,
          ),
          const SizedBox(height: T.s3),
          Divider(height: 1, color: p.primary.withValues(alpha: 0.14)),
          const SizedBox(height: T.s3),
          PaceBars(
            spend: summary.spend,
            projected: summary.projectedSpend,
            previous: previous,
          ),
          if (summary.daysElapsed < summary.daysInMonth) ...[
            const SizedBox(height: T.s3),
            Text(
              'Projection assumes the rest of the month spends like the first '
              '${summary.daysElapsed} days.',
              style: T.bodySmall.copyWith(
                color: p.inkMuted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Where it went',
            action: 'Insights',
            onAction: onSeeAll,
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: T.s2),
          CategoryDonut(categories: summary.byCategory, total: summary.spend),
        ],
      ),
    );
  }
}

class _CardStrip extends StatelessWidget {
  const _CardStrip({required this.cards, this.onOpen});

  final List<CardMetrics> cards;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Cards',
          action: 'Manage',
          onAction: onOpen,
          padding: const EdgeInsets.only(bottom: T.s2, left: T.s1),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: T.s3),
                SizedBox(
                  width: cards.length == 1 ? null : 238,
                  child: CardFace(
                    metrics: cards[i],
                    compact: true,
                    onTap: onOpen,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// "Worth knowing": the two highest-ranked insights, rendered with the **same**
/// tile the Insights screen uses.
///
/// This replaces `_InsightPreview`, a second, degraded copy of `InsightTile` that
/// dropped the chip, the tone border, the "in 1 days" grammar fix and the
/// calendar-day bill countdown. That copy is exactly why the same phone could say
/// "American Express bill due in 2 days" in the banner and "Bill due in 1 days"
/// three sections below it.
class _InsightSection extends StatelessWidget {
  const _InsightSection({
    required this.insights,
    required this.transactions,
    this.onSeeAll,
    this.onTab,
    this.onOpenActivity,
  });

  final List<Insight> insights;
  final List<Txn> transactions;
  final VoidCallback? onSeeAll;
  final ValueChanged<int>? onTab;
  final ValueChanged<ActivityRequest>? onOpenActivity;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Worth knowing',
          action: 'All insights',
          onAction: onSeeAll,
          padding: const EdgeInsets.only(bottom: T.s3, left: T.s1),
        ),
        for (final insight in insights.take(2))
          Padding(
            padding: const EdgeInsets.only(bottom: T.s3),
            child: InsightTile(
              insight: insight,
              onAction: insightActionHandler(
                insight,
                openActivity: onOpenActivity,
                openTab: onTab,
                transactions: transactions,
                onRecurring: onTab == null ? null : () => onTab!(3),
              ),
              onDismiss: () => state.dismissInsight(insight.id),
            ),
          ),
      ],
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.transactions, this.onSeeAll});

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
    return AppCard(
      padding: const EdgeInsets.fromLTRB(T.s2, T.s3, T.s2, T.s1),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: T.s2),
            child: SectionHeader(
              title: 'Recent',
              action: 'See all',
              onAction: onSeeAll,
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: T.s1),
          for (var i = 0; i < top.length; i++) ...[
            TxnRow(
              txn: top[i],
              onTap: () => showTransactionDetail(context, top[i]),
            ),
            if (i != top.length - 1)
              Divider(height: 1, indent: 64, color: p.outlineVariant),
          ],
        ],
      ),
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
                      : 'Allow SMS access so Finance SMS can read bank and UPI alerts, or look around with generated demo data first.'),
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/money_format.dart';
import '../app/widgets/kit.dart';
import '../data/finance_repository.dart';
import '../engine/insights_engine.dart';
import '../state/app_state.dart';
import 'insight_actions.dart';
import 'transactions_screen.dart';
import 'widgets/insight_breakdowns.dart';
import 'widgets/insight_tile.dart';
import 'widgets/txn_common.dart';

/// Insights: what needs attention, what is recurring, and where the money went.
/// Every claim on this screen is backed by a number the engine computed.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, this.onNavigate, this.onOpenActivity});

  /// Switches the shell tab (1 = activity, 2 = cards, 3 = insights).
  final ValueChanged<int>? onNavigate;

  /// Opens Activity with a filter already applied.
  final ValueChanged<ActivityRequest>? onOpenActivity;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  /// True once a load has finished since this screen mounted.
  ///
  /// The skeleton is the only honest state until then: an empty snapshot exists
  /// while the first scan runs, and painting "Nothing to analyse yet" over it is
  /// a claim the app has not checked yet. That flash is what this removes.
  bool _settled = false;

  /// Lets a "See recurring" insight action scroll to that section instead of
  /// promising a destination it cannot reach.
  final GlobalKey _recurringKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final data = state.data;
    final p = T.of(context);

    if (!_settled && !state.isLoading && !state.isScanning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_settled) setState(() => _settled = true);
      });
    }
    final booting =
        data.isEmpty && (state.isLoading || state.isScanning || !_settled);

    final Widget body;
    if (booting) {
      body = const _InsightsSkeleton();
    } else if (data.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(T.s5, T.s6, T.s5, 96),
        children: [
          EmptyState(
            icon: Icons.insights_rounded,
            title: 'Nothing to analyse yet',
            body:
                'Once a few bank messages are read, this screen shows what '
                'changed, what is recurring and where the money went.',
            actionLabel: 'Scan SMS',
            onAction: state.scanInbox,
            secondaryLabel: 'See a demo',
            onSecondary: state.startDemo,
          ),
        ],
      );
    } else {
      // The engine counts elapsed hours, so a bill due on 27 Oct reads "in 1
      // days" on the evening of the 25th. Count calendar days here so Home,
      // Cards and Insights all give the same countdown (one implementation,
      // owned by `InsightTile`).
      final insights = withCalendarDueDates(data.insights, data.cards);
      final attention = insights
          .where(
            (insight) =>
                insight.tone == InsightTone.warning ||
                insight.tone == InsightTone.caution,
          )
          .toList(growable: false);
      final other = insights
          .where(
            (insight) =>
                insight.tone == InsightTone.positive ||
                insight.tone == InsightTone.neutral,
          )
          .toList(growable: false);
      final categories = data.summary.byCategory;

      body = RefreshIndicator(
        onRefresh: state.scanInbox,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, 96),
          children: [
            _Header(data: data, attentionCount: attention.length),
            const SizedBox(height: T.s5),
            const SectionHeader(
              title: 'Needs attention',
              padding: EdgeInsets.only(bottom: T.s3, left: T.s1),
            ),
            if (data.phishingAlerts.isEmpty && attention.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: T.s1),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: p.positive,
                    ),
                    const SizedBox(width: T.s2),
                    Expanded(
                      child: Text(
                        'Nothing needs your attention right now.',
                        style: T.body.copyWith(color: p.inkSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            if (data.phishingAlerts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: T.s3),
                child: _FraudCard(
                  alerts: data.phishingAlerts,
                  onOpen: (alert) => _showAlert(context, alert),
                ),
              ),
            for (final insight in attention)
              Padding(
                padding: const EdgeInsets.only(bottom: T.s3),
                child: _tile(context, state, insight),
              ),
            if (other.isNotEmpty) ...[
              const SizedBox(height: T.s4),
              const SectionHeader(
                title: 'Worth a look',
                padding: EdgeInsets.only(bottom: T.s3, left: T.s1),
              ),
              for (final insight in other)
                Padding(
                  padding: const EdgeInsets.only(bottom: T.s3),
                  child: _tile(context, state, insight),
                ),
            ],
            if (attention.isEmpty && other.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: T.s2, left: T.s1),
                child: Text(
                  'No insights yet — a few more messages will give this screen '
                  'something to work with.',
                  style: T.bodySmall.copyWith(color: p.inkMuted),
                ),
              ),
            const SizedBox(height: T.s4),
            SectionHeader(
              key: _recurringKey,
              title: 'Recurring payments',
              padding: const EdgeInsets.only(bottom: T.s2, left: T.s1),
            ),
            if (data.recurring.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: T.s1),
                child: Row(
                  children: [
                    Icon(Icons.autorenew_rounded, size: 18, color: p.inkMuted),
                    const SizedBox(width: T.s2),
                    Expanded(
                      child: Text(
                        'Nothing recurring detected yet — we need three similar charges.',
                        style: T.bodySmall.copyWith(color: p.inkMuted),
                      ),
                    ),
                  ],
                ),
              )
            else
              AppCard(
                padding: const EdgeInsets.fromLTRB(T.s4, T.s1, T.s4, T.s1),
                child: Column(
                  children: [
                    for (var i = 0; i < data.recurring.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, color: p.outlineVariant),
                      RecurringRow(series: data.recurring[i]),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: T.s5),
            SectionHeader(
              title: 'Where the money went',
              subtitle:
                  '${money(data.summary.spend)} across ${categories.length} '
                  '${categories.length == 1 ? 'category' : 'categories'}',
              padding: const EdgeInsets.only(bottom: T.s2, left: T.s1),
            ),
            if (categories.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: T.s1),
                child: Text(
                  'No spending recorded this month yet.',
                  style: T.bodySmall.copyWith(color: p.inkMuted),
                ),
              )
            else
              AppCard(
                padding: const EdgeInsets.fromLTRB(T.s4, T.s1, T.s4, T.s2),
                child: Column(
                  children: [
                    for (var i = 0; i < categories.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, color: p.outlineVariant),
                      CategoryBreakdownRow(total: categories[i], index: i),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: T.s5),
            Center(
              child: Text(
                'Calculated on this phone from your messages.',
                style: T.bodySmall.copyWith(color: p.inkMuted, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Insights'), titleSpacing: T.s5),
      body: SafeArea(top: false, bottom: false, child: body),
    );
  }

  /// One insight card, with its action and its dismiss wired. Both lists on this
  /// screen go through it, so neither can drift from Home's rendering — and the
  /// engine's `Insight.action` finally has a destination.
  Widget _tile(BuildContext context, AppState state, Insight insight) {
    return InsightTile(
      insight: insight,
      onAction: insightActionHandler(
        insight,
        openActivity: widget.onOpenActivity,
        openTab: widget.onNavigate,
        transactions: state.data.transactions,
        onRecurring: _scrollToRecurring,
      ),
      onDismiss: () => state.dismissInsight(insight.id),
    );
  }

  /// "See recurring" lands on the section already on this screen instead of
  /// pretending to navigate somewhere else.
  void _scrollToRecurring() {
    final target = _recurringKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: T.medium,
      curve: T.curveOut,
      alignment: 0.1,
    );
  }

  void _showAlert(BuildContext context, PhishingAlert alert) {
    final p = T.of(context);
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Possible fraud message'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'From ${alert.sender}',
                  style: T.body.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${shortDateWithYear(alert.receivedAt)} · '
                  '${clockTime(alert.receivedAt)}',
                  style: T.bodySmall.copyWith(color: p.inkMuted),
                ),
                const SizedBox(height: T.s3),
                Text(
                  alert.preview,
                  style: T.body.copyWith(color: p.ink),
                ),
                const SizedBox(height: T.s4),
                Text(
                  'Why we flagged it',
                  style: T.label.copyWith(color: p.inkSecondary),
                ),
                const SizedBox(height: T.s1),
                Text(
                  _humanSignals(alert.reason),
                  style: T.bodySmall.copyWith(color: p.inkMuted),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _FraudCard extends StatelessWidget {  const _FraudCard({required this.alerts, required this.onOpen});

  final List<PhishingAlert> alerts;
  final ValueChanged<PhishingAlert> onOpen;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final shown = alerts.take(2).toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(T.s4),
      decoration: BoxDecoration(
        color: p.surface,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.danger.withValues(alpha: p.isDark ? 0.07 : 0.06), p.surface],
          stops: const [0, 0.6],
        ),
        border: p.isDark ? Border.all(color: p.outlineVariant) : null,
        boxShadow: p.isDark ? null : p.shadowSoft,
        borderRadius: BorderRadius.circular(T.r4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconDisc(icon: Icons.gpp_maybe_rounded, color: p.danger, size: 40),
              const SizedBox(width: T.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Possible fraud messages',
                      style: T.cardTitle.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Kept out of your totals. Nothing was opened.',
                      style: T.bodySmall.copyWith(color: p.inkSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: T.s2),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: p.outlineVariant),
            Semantics(
              button: true,
              label:
                  'Fraud message from ${shown[i].sender}. ${_preview(shown[i].preview)}. Open.',
              excludeSemantics: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onOpen(shown[i]),
                  borderRadius: BorderRadius.circular(T.r2),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: T.s2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: p.danger,
                          ),
                          const SizedBox(width: T.s2),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  shown[i].sender,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: T.bodySmall.copyWith(
                                    color: p.danger,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                  ),
                                ),
                                Text(
                                  _preview(shown[i].preview),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: T.bodySmall.copyWith(
                                    color: p.inkSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: p.danger,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (alerts.length > shown.length) ...[
            const SizedBox(height: T.s1),
            Text(
              '+${alerts.length - shown.length} more flagged',
              style: T.bodySmall.copyWith(
                color: p.danger,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.data, required this.attentionCount});

  final HomeData data;
  final int attentionCount;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final summary = data.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    monthYearLabel(summary.monthStart),
                    style: T.label.copyWith(
                      color: p.inkMuted,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'What changed',
                    style: T.title.copyWith(color: p.ink, fontSize: 26),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${data.insights.length} signals from ${data.transactions.length} entries',
                    style: T.bodySmall.copyWith(color: p.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: T.s2),
            IconBadge(
              icon: Icons.insights_rounded,
              color: p.primary,
              size: 48,
              iconSize: 24,
            ),
          ],
        ),
        if (attentionCount > 0) ...[
          const SizedBox(height: T.s3),
          Pill(
            '$attentionCount ${attentionCount == 1 ? 'needs' : 'need'} a look',
            tone: PillTone.caution,
            icon: Icons.priority_high_rounded,
          ),
        ],
      ],
    );
  }
}

class _InsightsSkeleton extends StatelessWidget {
  const _InsightsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, 96),
      children: const [
        SkeletonBox(height: 72, radius: T.r2),
        SizedBox(height: T.s5),
        SkeletonBox(height: 130, radius: T.r3),
        SizedBox(height: T.s3),
        SkeletonBox(height: 130, radius: T.r3),
        SizedBox(height: T.s5),
        SkeletonBox(height: 180, radius: T.r3),
      ],
    );
  }
}

String _preview(String body) {
  final clean = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (clean.length <= 120) return clean;
  return '${clean.substring(0, 120).trimRight()}…';
}

String _humanSignals(String raw) {
  final words = <String>[];
  for (final part in raw.split(',')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final spaced = trimmed.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match[1]!.toLowerCase()}',
    );
    final value = spaced.trim();
    if (value.isEmpty) continue;
    words.add('${value[0].toUpperCase()}${value.substring(1)}');
  }
  if (words.isEmpty) {
    return 'The wording matches known fake-alert patterns.';
  }
  return words.join(' · ');
}

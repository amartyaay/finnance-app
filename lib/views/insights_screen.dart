import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/widgets/kit.dart';
import '../data/finance_repository.dart';
import '../domain/money.dart';
import '../engine/insights_engine.dart';
import '../state/app_state.dart';
import 'widgets/insight_breakdowns.dart';
import 'widgets/insight_tile.dart';
import 'widgets/txn_common.dart';

/// Insights: what needs attention, what is recurring, and where the money went.
/// Every claim on this screen is backed by a number the engine computed.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final data = state.data;
    final scheme = Theme.of(context).colorScheme;

    final Widget body;
    if (data.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(T.s5, T.s8, T.s5, 96),
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
      final attention = data.insights
          .where(
            (insight) =>
                insight.tone == InsightTone.warning ||
                insight.tone == InsightTone.caution,
          )
          .toList(growable: false);
      final other = data.insights
          .where(
            (insight) =>
                insight.tone == InsightTone.positive ||
                insight.tone == InsightTone.neutral,
          )
          .toList(growable: false);

      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, 96),
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${monthYearLabel(data.summary.monthStart)}  ·  ',
                  style: T.body.copyWith(color: scheme.onSurfaceVariant),
                ),
                TextSpan(
                  text: inr(data.summary.spend),
                  style: T.money.copyWith(color: scheme.onSurface),
                ),
                TextSpan(
                  text: ' spent',
                  style: T.body.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: T.s5),
          const SectionHeader(title: 'Needs attention'),
          if (data.phishingAlerts.isEmpty && attention.isEmpty)
            Text(
              'Nothing needs your attention right now.',
              style: T.body.copyWith(color: scheme.onSurfaceVariant),
            ),
          for (final alert in data.phishingAlerts)
            Padding(
              padding: const EdgeInsets.only(bottom: T.s3),
              child: NoticeBanner(
                title: 'Possible fraud message',
                body: _preview(alert.preview),
                icon: Icons.gpp_maybe_rounded,
                tone: PillTone.danger,
                actionLabel: 'View',
                onAction: () => _showAlert(context, alert),
              ),
            ),
          for (final insight in attention)
            Padding(
              padding: const EdgeInsets.only(bottom: T.s3),
              child: InsightTile(insight: insight),
            ),
          for (final insight in other)
            Padding(
              padding: const EdgeInsets.only(bottom: T.s3),
              child: InsightTile(insight: insight),
            ),
          if (attention.isEmpty && other.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: T.s2),
              child: Text(
                'No insights yet — a few more messages will give this screen '
                'something to work with.',
                style: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: T.s4),
          const SectionHeader(title: 'Recurring payments'),
          if (data.recurring.isEmpty)
            Text(
              'Nothing recurring detected yet (needs 3 similar charges).',
              style: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            AppCard(
              padding: const EdgeInsets.fromLTRB(T.s4, T.s1, T.s4, T.s1),
              child: Column(
                children: [
                  for (var i = 0; i < data.recurring.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    RecurringRow(series: data.recurring[i]),
                  ],
                ],
              ),
            ),
          const SizedBox(height: T.s6),
          const SectionHeader(title: 'Where the money went'),
          if (data.summary.byCategory.isEmpty)
            Text(
              'No spending recorded this month yet.',
              style: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            AppCard(
              padding: const EdgeInsets.fromLTRB(T.s4, T.s3, T.s4, T.s3),
              child: Column(
                children: [
                  for (
                    var i = 0;
                    i < data.summary.byCategory.length;
                    i++
                  ) ...[
                    if (i > 0) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: T.s3),
                      child: CategoryBreakdownRow(
                        total: data.summary.byCategory[i],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Insights'), titleSpacing: T.s5),
      body: SafeArea(top: false, bottom: false, child: body),
    );
  }

  void _showAlert(BuildContext context, PhishingAlert alert) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
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
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${shortDateWithYear(alert.receivedAt)} · '
                  '${clockTime(alert.receivedAt)}',
                  style: T.bodySmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: T.s3),
                Text(
                  alert.preview,
                  style: T.body.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: T.s4),
                Text(
                  'Why we flagged it',
                  style: T.label.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: T.s1),
                Text(
                  _humanSignals(alert.reason),
                  style: T.bodySmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
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

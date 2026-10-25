import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/widgets/kit.dart';
import '../../domain/money.dart';
import '../../engine/card_metrics.dart';
import 'card_gauge.dart';
import 'txn_common.dart';

/// One card, in the order a person checks it: is a bill about to bite, how much
/// of the limit is gone, then the dates.
class CardTile extends StatelessWidget {
  const CardTile({super.key, required this.metrics});

  final CardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = metrics.card;
    // Percentage, bar and "used / limit" all read the same CardMetrics object,
    // so they can never disagree about what the used amount is. "This cycle" is
    // spend, not outstanding, and is labelled as such further down.
    final percent = metrics.utilization == null
        ? null
        : (metrics.utilization! * 100).round();
    final subtitle = card.displayName == card.issuer
        ? card.masked
        : '${card.issuer} · ${card.masked}';
    final daysToDue = metrics.daysToDue;

    return AppCard(
      padding: const EdgeInsets.all(T.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (metrics.dueSoon && daysToDue != null) ...[
            NoticeBanner(
              title: daysToDue <= 0
                  ? 'Bill due today'
                  : 'Bill due in $daysToDue ${daysToDue == 1 ? 'day' : 'days'}',
              body:
                  '${inr(metrics.totalDue)}'
                  '${metrics.dueDate == null ? '' : ' by ${shortDate(metrics.dueDate!)}'}. '
                  'Paying the full amount avoids interest.',
              icon: Icons.event_available_rounded,
              tone: PillTone.caution,
            ),
            const SizedBox(height: T.s4),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.cardTitle.copyWith(color: scheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.bodySmall.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: T.s2),
              Pill(
                metrics.band.label,
                tone: utilizationBandTone(metrics.band),
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: T.s4),
          Row(
            children: [
              Text(
                percent == null ? 'No limit' : '$percent% used',
                maxLines: 1,
                style: T.bodySmall.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: T.s2),
              Expanded(
                child: Text(
                  percent == null
                      ? 'Limit not set'
                      : '${inr(metrics.outstanding)} / ${inr(metrics.limit)}',
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: T.s2),
          ShareBar(
            share: metrics.utilization ?? 0,
            color: utilizationBandColor(metrics.band),
            height: 8,
          ),
          const SizedBox(height: T.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'This cycle',
                  value: inrCompact(metrics.spentThisCycle),
                ),
              ),
              const SizedBox(width: T.s3),
              Expanded(
                child: _MiniStat(
                  label: 'Statement',
                  value: _statementLabel(metrics.daysToStatement),
                ),
              ),
            ],
          ),
          const SizedBox(height: T.s2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MiniStat(label: 'Due', value: _dueLabel(metrics)),
              ),
              const SizedBox(width: T.s3),
              Expanded(
                child: _MiniStat(
                  label: 'Minimum due',
                  value: metrics.minimumDue == null
                      ? '—'
                      : inrCompact(metrics.minimumDue!),
                ),
              ),
            ],
          ),
          const SizedBox(height: T.s3),
          Text(
            metrics.band.advice,
            style: T.bodySmall.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  String _statementLabel(int days) {
    if (days <= 0) return 'today';
    if (days == 1) return 'tomorrow';
    return 'in $days days';
  }

  String _dueLabel(CardMetrics metrics) {
    final due = metrics.dueDate;
    if (due == null) return 'Not set';
    final days = metrics.daysToDue;
    if (days == null) return shortDate(due);
    return '${shortDate(due)} · ${daysUntilLabel(days)}';
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: T.s3, vertical: T.s2 + 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(T.r2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.label.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: T.body.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}

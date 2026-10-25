import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/widgets/kit.dart';
import '../../domain/money.dart';
import '../../engine/monthly_summary.dart';
import '../../engine/recurring_detector.dart';
import 'txn_common.dart';

/// A detected subscription: who, how much, when it lands next, and what it costs
/// over a year — the number that actually changes decisions.
class RecurringRow extends StatelessWidget {
  const RecurringRow({super.key, required this.series});

  final RecurringSeries series;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = series.daysUntilNext;
    final when = switch (days) {
      < 0 => 'was expected ${shortDate(series.nextExpected)}',
      0 => 'next ${shortDate(series.nextExpected)} · today',
      1 => 'next ${shortDate(series.nextExpected)} · tomorrow',
      _ => 'next ${shortDate(series.nextExpected)} · in $days days',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: T.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  series.merchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.cardTitle.copyWith(color: scheme.onSurface),
                ),
              ),
              const SizedBox(width: T.s3),
              Text(
                inr(series.amount),
                style: T.money.copyWith(color: scheme.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'every ${series.intervalDays} days · $when',
            style: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            '${inr(Paise(series.annualisedPaise))} a year at this pace',
            style: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One row of "where the money went": the bar carries the share, the pill
/// carries the direction of change.
class CategoryBreakdownRow extends StatelessWidget {
  const CategoryBreakdownRow({super.key, required this.total});

  final CategoryTotal total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final change = total.change;
    final Widget? changeChip;
    if (change.abs() < 0.005) {
      changeChip = null;
    } else if (change > 0) {
      changeChip = Pill(
        '▲ ${(change * 100).round()}%',
        tone: PillTone.danger,
        dense: true,
      );
    } else {
      changeChip = Pill(
        '▼ ${(-change * 100).round()}%',
        tone: PillTone.positive,
        dense: true,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                total.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.cardTitle.copyWith(color: scheme.onSurface),
              ),
            ),
            const SizedBox(width: T.s3),
            Text(
              inr(total.amount),
              style: T.money.copyWith(color: scheme.onSurface),
            ),
          ],
        ),
        const SizedBox(height: T.s2),
        Row(
          children: [
            if (changeChip != null) ...[
              changeChip,
              const SizedBox(width: T.s2),
            ],
            Expanded(
              child: ShareBar(
                share: total.share,
                color: categoryColor(total.kind),
                height: 8,
              ),
            ),
            const SizedBox(width: T.s2),
            Text(
              '${(total.share * 100).round()}%',
              style: T.label.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

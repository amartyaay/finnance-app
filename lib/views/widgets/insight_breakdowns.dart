import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/money_format.dart';
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
    final p = T.of(context);
    final days = series.daysUntilNext;
    final when = switch (days) {
      < 0 => 'was expected ${shortDate(series.nextExpected)}',
      0 => 'today',
      1 => 'tomorrow',
      _ => 'in $days days',
    };
    final semantics =
        '${series.merchant}. ${money(series.amount)} every '
        '${series.intervalDays} days. Next ${shortDate(series.nextExpected)}, '
        '$when. ${money(Paise(series.annualisedPaise))} a year at this pace.';
    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: T.s3),
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(
            icon: Icons.autorenew_rounded,
            color: p.info,
            size: 38,
            iconSize: 19,
          ),
          const SizedBox(width: T.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  series.merchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.cardTitle.copyWith(color: p.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  'Every ${series.intervalDays} days · next ${shortDate(series.nextExpected)} · $when',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.bodySmall.copyWith(
                    color: p.inkMuted,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${money(Paise(series.annualisedPaise))} a year at this pace',
                  style: T.bodySmall.copyWith(color: p.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: T.s2),
          MoneyText(
            series.amount,
            style: T.money.copyWith(fontSize: 14),
            color: p.ink,
          ),
        ],
      ),
      ),
    );
  }
}

/// One row of "where the money went": a ranked bar carries the share, the pill
/// carries the direction of change.
class CategoryBreakdownRow extends StatelessWidget {
  const CategoryBreakdownRow({
    super.key,
    required this.total,
    required this.index,
  });

  final CategoryTotal total;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final change = total.change;
    final Widget? changeChip;
    if (change.abs() < 0.005) {
      changeChip = null;
    } else if (change > 0) {
      changeChip = Pill(
        '▲ ${(change * 100).round()}%',
        tone: PillTone.caution,
        dense: true,
      );
    } else {
      changeChip = Pill(
        '▼ ${(-change * 100).round()}%',
        tone: PillTone.positive,
        dense: true,
      );
    }
    final changeWords = change.abs() < 0.005
        ? 'About the same as last month.'
        : '${(change.abs() * 100).round()} percent ${change > 0 ? 'more' : 'less'} than last month.';
    final semantics =
        '${total.name}. ${money(total.amount)}, '
        '${(total.share * 100).round()} percent of spending. $changeWords';
    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: T.s3),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '${index + 1}',
                style: T.money.copyWith(
                  color: p.inkMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: T.s2),
              Expanded(
                child: Text(
                  total.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.cardTitle.copyWith(color: p.ink),
                ),
              ),
              const SizedBox(width: T.s2),
              MoneyText(
                total.amount,
                style: T.money.copyWith(fontSize: 14),
                color: p.ink,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: ShareBar(
                  share: total.share,
                  color: categoryColor(context, total.kind),
                  height: 7,
                ),
              ),
              const SizedBox(width: T.s3),
              SizedBox(
                width: 40,
                child: Text(
                  '${(total.share * 100).round()}%',
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  style: T.money.copyWith(
                    color: p.inkMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (changeChip != null) ...[
            const SizedBox(height: 6),
            changeChip,
          ],
        ],
      ),
      ),
    );
  }
}

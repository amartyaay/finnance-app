import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/widgets/kit.dart';
import '../../domain/money.dart';
import '../../engine/card_metrics.dart';
import 'charts.dart';
import 'txn_common.dart';

/// Band colour, used for the ring and the utilisation bars. Colour never travels
/// alone here — every place that paints it also prints the band's word.
Color utilizationBandColor(UtilizationBand band, BuildContext context) {
  final p = T.of(context);
  return switch (band) {
    UtilizationBand.excellent || UtilizationBand.healthy => p.positive,
    UtilizationBand.watch => p.caution,
    UtilizationBand.high || UtilizationBand.critical => p.danger,
    UtilizationBand.unknown => p.inkMuted,
  };
}

PillTone utilizationBandTone(UtilizationBand band) => switch (band) {
  UtilizationBand.excellent || UtilizationBand.healthy => PillTone.positive,
  UtilizationBand.watch => PillTone.caution,
  UtilizationBand.high || UtilizationBand.critical => PillTone.danger,
  UtilizationBand.unknown => PillTone.neutral,
};

/// The aggregate card summary: one ring, one caption, three numbers. This is
/// the only ring on the screen — individual cards carry their own small gauge
/// on the face itself.
class CardSummaryCard extends StatelessWidget {
  const CardSummaryCard({
    super.key,
    required this.cards,
    required this.utilization,
    required this.limit,
    required this.band,
    required this.totalDue,
    required this.nextDue,
  });

  final List<CardMetrics> cards;
  final double? utilization;
  final Paise limit;
  final UtilizationBand band;
  final Paise totalDue;
  final DateTime? nextDue;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final limitedCards = cards
        .where((c) => (c.card.creditLimitPaise ?? 0) > 0)
        .length;
    final percent = utilization == null
        ? null
        : (utilization! * 100).round();
    final color = utilizationBandColor(band, context);
    final used = utilization == null
        ? null
        : Paise((limit.value * utilization!).round());
    final caption = utilization == null
        ? 'Add a card limit to see total utilisation.'
        : 'of ${inr(limit)} across $limitedCards '
              '${limitedCards == 1 ? 'card' : 'cards'} with a limit';
    final limitNote = limitedCards == cards.length
        ? 'All limits set'
        : '$limitedCards of ${cards.length} limits set';

    return AppCard(
      padding: const EdgeInsets.all(T.s4),
      child: Column(
        children: [
          Row(
            children: [
              UtilizationArc(
                value: utilization,
                color: color,
                track: p.surfaceSunken,
                size: 92,
                stroke: 9,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      percent == null ? '—' : '$percent%',
                      maxLines: 1,
                      style: T.moneyLarge(p.ink).copyWith(fontSize: 21),
                    ),
                    Text(
                      'used',
                      style: T.bodySmall.copyWith(
                        color: p.inkMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: T.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: T.s2,
                      runSpacing: T.s1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Pill(
                          band.label,
                          tone: utilizationBandTone(band),
                          dense: true,
                        ),
                        Text(
                          limitNote,
                          style: T.bodySmall.copyWith(
                            color: p.inkMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: T.bodySmall.copyWith(color: p.inkSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      used == null
                          ? 'Set a limit on each card below.'
                          : '${inr(used)} used · ${inr(Paise((limit.value - used.value).clamp(0, limit.value)))} available',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: T.bodySmall.copyWith(color: p.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: T.s4),
          Divider(height: 1, color: p.outlineVariant),
          const SizedBox(height: T.s3),
          Row(
            children: [
              Expanded(
                child: _SummaryStat(
                  label: 'Cards',
                  value: '${cards.length}',
                  align: CrossAxisAlignment.start,
                ),
              ),
              _StatDivider(color: p.outlineVariant),
              Expanded(
                child: _SummaryStat(
                  label: 'Total due',
                  value: inrCompact(totalDue),
                  align: CrossAxisAlignment.start,
                ),
              ),
              _StatDivider(color: p.outlineVariant),
              Expanded(
                child: _SummaryStat(
                  label: 'Next due',
                  value: nextDue == null ? '—' : shortDate(nextDue!),
                  align: CrossAxisAlignment.start,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.value,
    required this.align,
  });

  final String label;
  final String value;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: T.label.copyWith(color: p.inkMuted, letterSpacing: 0.2),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: T.cardTitle.copyWith(color: p.ink, fontSize: 16),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: T.s3),
      color: color,
    );
  }
}

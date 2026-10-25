import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/widgets/kit.dart';
import '../../domain/money.dart';
import '../../engine/card_metrics.dart';
import 'txn_common.dart';

/// Band colour, used for the ring and the utilisation bars. Colour never travels
/// alone here — every place that paints it also prints the band's word.
Color utilizationBandColor(UtilizationBand band) => switch (band) {
  UtilizationBand.excellent || UtilizationBand.healthy => T.positive,
  UtilizationBand.watch => T.caution,
  UtilizationBand.high || UtilizationBand.critical => T.danger,
  UtilizationBand.unknown => T.inkMuted,
};

PillTone utilizationBandTone(UtilizationBand band) => switch (band) {
  UtilizationBand.excellent || UtilizationBand.healthy => PillTone.positive,
  UtilizationBand.watch => PillTone.caution,
  UtilizationBand.high || UtilizationBand.critical => PillTone.danger,
  UtilizationBand.unknown => PillTone.neutral,
};

/// The aggregate utilisation arc. This is the only ring in the app: lists use a
/// plain bar because a ring per row is decoration, not information.
class UtilizationRing extends StatelessWidget {
  const UtilizationRing({
    super.key,
    required this.utilization,
    required this.color,
    this.size = 120,
    this.stroke = 10,
  });

  final double? utilization;
  final Color color;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The ring and its label are the same number: the aggregate utilisation that
    // the Cards screen received. Never derive this from a per-card cycle total.
    final percent = utilization == null ? null : (utilization! * 100).round();
    final percentStyle = T.moneyLarge(scheme.onSurface).copyWith(fontSize: 24);
    return Semantics(
      label: percent == null
          ? 'Total utilisation unknown until a card limit is set'
          : 'Total utilisation $percent percent',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _UtilizationRingPainter(
                  value: (utilization ?? 0).clamp(0.0, 1.0).toDouble(),
                  color: color,
                  track: scheme.surfaceContainerHigh,
                  stroke: stroke,
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // "100%" at 1.3x is wider than the ring; scale the glyphs a
                // touch rather than let the label paint outside the arc.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    percent == null ? '—' : '$percent%',
                    maxLines: 1,
                    style: percentStyle,
                  ),
                ),
                Text(
                  'used',
                  style: T.label.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UtilizationRingPainter extends CustomPainter {
  _UtilizationRingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - stroke) / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_UtilizationRingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.track != track ||
      oldDelegate.stroke != stroke;
}

/// Header of the Cards screen: total utilisation, the limit it is measured
/// against, and the three numbers people open a card screen for.
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
    final scheme = Theme.of(context).colorScheme;
    // The ring only has a denominator for cards whose limit is known; the
    // caption must count the same cards, or the screen contradicts itself when
    // one card has no limit set yet.
    final limitedCards = cards
        .where((c) => (c.card.creditLimitPaise ?? 0) > 0)
        .length;
    final caption = utilization == null
        ? 'Add a card limit to see total utilisation.'
        : 'of ${inr(limit)} limit across $limitedCards '
              '${limitedCards == 1 ? 'card' : 'cards'}';
    return AppCard(
      padding: const EdgeInsets.fromLTRB(T.s4, T.s5, T.s4, T.s4),
      child: Column(
        children: [
          UtilizationRing(
            utilization: utilization,
            color: utilizationBandColor(band),
          ),
          const SizedBox(height: T.s3),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: T.s4),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: T.s3),
          Row(
            children: [
              Expanded(
                child: _SummaryStat(label: 'Cards', value: '${cards.length}'),
              ),
              _StatDivider(color: scheme.outlineVariant),
              Expanded(
                child: _SummaryStat(
                  label: 'Total due',
                  value: inrCompact(totalDue),
                ),
              ),
              _StatDivider(color: scheme.outlineVariant),
              Expanded(
                child: _SummaryStat(
                  label: 'Next due',
                  value: nextDue == null ? '—' : shortDate(nextDue!),
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
  const _SummaryStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: T.label.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: T.cardTitle.copyWith(color: scheme.onSurface),
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
    return Container(width: 1, height: 32, color: color);
  }
}

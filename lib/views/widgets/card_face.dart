import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/widgets/kit.dart';
import '../../domain/money.dart';
import '../../engine/card_metrics.dart';
import 'txn_common.dart';

/// Height a [CardFace] needs at the current text scale. The face is a fixed
/// composition (like the physical card), but it must grow with accessibility
/// text settings rather than clip.
double cardFaceHeight(BuildContext context, {bool compact = false}) {
  final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
  return (compact ? 138.0 : 206.0) +
      (scale - 1).clamp(0.0, 0.6) * (compact ? 34 : 86);
}

/// One credit card, drawn as a card: tonal by issuer, masked number in tracked
/// numerals, utilisation arc, and the next due date. Every number comes from
/// [CardMetrics]; the face is a picture of the same data the rows below show.
class CardFace extends StatelessWidget {
  const CardFace({
    super.key,
    required this.metrics,
    this.compact = false,
    this.onTap,
  });

  final CardMetrics metrics;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final card = metrics.card;
    final style = T.faceFor(card.issuer);
    final percent = metrics.utilization == null
        ? null
        : (metrics.utilization! * 100).round();
    final hasBill = metrics.totalDuePaise > 0;
    final due = metrics.dueDate;
    final days = metrics.daysToDue;
    final height = cardFaceHeight(context, compact: compact);

    final content = Container(
      height: height,
      decoration: BoxDecoration(
        gradient: style.gradient,
        borderRadius: BorderRadius.circular(T.r4),
        boxShadow: p.shadowCard,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(T.r4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: _CardPatternPainter(glow: style.glow),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(compact ? T.s4 : T.s5),
              child: compact
                  ? _CompactFace(
                      metrics: metrics,
                      percent: percent,
                      hasBill: hasBill,
                      due: due,
                      days: days,
                      ink: style.ink,
                      mutedInk: style.mutedInk,
                      glow: style.glow,
                    )
                  : _FullFace(
                      metrics: metrics,
                      percent: percent,
                      hasBill: hasBill,
                      due: due,
                      days: days,
                      ink: style.ink,
                      mutedInk: style.mutedInk,
                      glow: style.glow,
                    ),
            ),
          ],
        ),
      ),
    );

    final label = _semantics(percent);
    if (onTap == null) {
      return Semantics(container: true, label: label, excludeSemantics: true, child: content);
    }
    return Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      child: _Pressable(onTap: onTap!, radius: T.r4, child: content),
    );
  }

  String _semantics(int? percent) {
    final card = metrics.card;
    final buffer = StringBuffer()
      ..write('${card.displayName}, ${card.issuer} card ending ${card.last4}. ');
    if (percent == null) {
      buffer.write('Utilisation unknown until a limit is set. ');
    } else {
      buffer.write(
        '$percent percent of the limit used, ${metrics.band.label.toLowerCase()}. ',
      );
    }
    if (metrics.totalDuePaise > 0) {
      buffer.write(
        '${inr(metrics.totalDue)} due${metrics.dueDate == null ? '' : ' by ${shortDate(metrics.dueDate!)}'}. ',
      );
    } else {
      buffer.write('No bill due. ');
    }
    if (metrics.limit.value > 0) {
      buffer.write(
        '${inr(metrics.outstanding)} outstanding of ${inr(metrics.limit)} limit.',
      );
    }
    return buffer.toString();
  }
}

class _FullFace extends StatelessWidget {
  const _FullFace({
    required this.metrics,
    required this.percent,
    required this.hasBill,
    required this.due,
    required this.days,
    required this.ink,
    required this.mutedInk,
    required this.glow,
  });

  final CardMetrics metrics;
  final int? percent;
  final bool hasBill;
  final DateTime? due;
  final int? days;
  final Color ink;
  final Color mutedInk;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    final card = metrics.card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                card.issuer.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.label.copyWith(
                  color: mutedInk,
                  letterSpacing: 1.4,
                  fontSize: 11.5,
                ),
              ),
            ),
            Icon(Icons.contactless_rounded, size: 18, color: mutedInk),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          card.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: T.cardTitle.copyWith(
            color: ink,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const Spacer(),
        Text(
          card.masked,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: ink,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 3.2,
            height: 1.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: T.s1),
        if (hasBill && due != null)
          _DueChip(label: _dueLabel, glow: glow, ink: ink, mutedInk: mutedInk)
        else
          Text(
            due == null ? 'No bill due' : 'Next due ${shortDate(due!)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.bodySmall.copyWith(color: mutedInk, fontSize: 12),
          ),
        const Spacer(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasBill ? 'TOTAL DUE' : 'SPENT THIS CYCLE',
                    maxLines: 1,
                    style: T.label.copyWith(
                      color: mutedInk,
                      fontSize: 11.5,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      hasBill
                          ? inr(metrics.totalDue)
                          : inr(metrics.spentThisCycle),
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: ink,
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        height: 1.1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: T.s2),
            _FaceGauge(
              percent: percent,
              color: glow,
              ink: ink,
              mutedInk: mutedInk,
              caption: metrics.limit.value > 0
                  ? 'of ${inrCompact(metrics.limit)}'
                  : 'no limit',
            ),
          ],
        ),
      ],
    );
  }

  String get _dueLabel {
    if (days == null) return 'Due ${shortDate(due!)}';
    if (days! <= 0) return 'Due today';
    if (days! == 1) return 'Due tomorrow';
    return 'Due in $days days';
  }
}

class _CompactFace extends StatelessWidget {
  const _CompactFace({
    required this.metrics,
    required this.percent,
    required this.hasBill,
    required this.due,
    required this.days,
    required this.ink,
    required this.mutedInk,
    required this.glow,
  });

  final CardMetrics metrics;
  final int? percent;
  final bool hasBill;
  final DateTime? due;
  final int? days;
  final Color ink;
  final Color mutedInk;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    final card = metrics.card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                card.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.cardTitle.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
            ),
            Icon(Icons.contactless_rounded, size: 16, color: mutedInk),
          ],
        ),
        const SizedBox(height: T.s1),
        Text(
          card.masked,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: mutedInk,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.6,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const Spacer(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                percent == null ? 'Limit not set' : '$percent% used',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.money.copyWith(
                  color: ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (hasBill && due != null)
              Text(
                days == null ? shortDate(due!) : 'in $days d',
                maxLines: 1,
                style: T.bodySmall.copyWith(
                  color: ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Container(
                height: 5,
                color: ink.withValues(alpha: 0.18),
              ),
              FractionallySizedBox(
                widthFactor: (metrics.utilization ?? 0).clamp(0.0, 1.0),
                child: Container(height: 5, color: glow),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DueChip extends StatelessWidget {
  const _DueChip({
    required this.label,
    required this.glow,
    required this.ink,
    required this.mutedInk,
  });

  final String label;
  final Color glow;
  final Color ink;
  final Color mutedInk;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: T.s2, vertical: 4),
        decoration: BoxDecoration(
          color: ink.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(T.r5),
          border: Border.all(color: ink.withValues(alpha: 0.16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_rounded, size: 13, color: glow),
            const SizedBox(width: 5),
            Text(
              label,
              maxLines: 1,
              style: T.bodySmall.copyWith(
                color: ink,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaceGauge extends StatelessWidget {
  const _FaceGauge({
    required this.percent,
    required this.color,
    required this.ink,
    required this.mutedInk,
    required this.caption,
  });

  final int? percent;
  final Color color;
  final Color ink;
  final Color mutedInk;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 62,
          height: 62,
          child: Stack(
            alignment: Alignment.center,
            children: [
              RepaintBoundary(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: (percent ?? 0) / 100),
                  duration: T.chartDraw,
                  curve: T.curveOut,
                  builder: (context, value, _) => CustomPaint(
                    size: const Size.square(62),
                    painter: _MiniArcPainter(
                      value: value,
                      color: color,
                      track: ink.withValues(alpha: 0.18),
                    ),
                  ),
                ),
              ),
              Text(
                percent == null ? '—' : '$percent%',
                maxLines: 1,
                style: T.money.copyWith(
                  color: ink,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          maxLines: 1,
          style: T.bodySmall.copyWith(color: mutedInk, fontSize: 11.5),
        ),
      ],
    );
  }
}

class _MiniArcPainter extends CustomPainter {
  const _MiniArcPainter({
    required this.value,
    required this.color,
    required this.track,
  });

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - 5) / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value.clamp(0.0, 1.0),
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_MiniArcPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.track != track;
}

class _CardPatternPainter extends CustomPainter {
  const _CardPatternPainter({required this.glow});

  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Colors.white.withValues(alpha: 0.055);
    final center = Offset(size.width * 0.92, size.height * 0.08);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(center, size.width * 0.10 * i, circle);
    }
    final sheen = Path()
      ..moveTo(size.width * 0.55, size.height)
      ..lineTo(size.width * 0.95, 0)
      ..lineTo(size.width * 1.02, 0)
      ..lineTo(size.width * 0.62, size.height)
      ..close();
    canvas.drawPath(
      sheen,
      Paint()..color = Colors.white.withValues(alpha: 0.035),
    );
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [glow.withValues(alpha: 0.18), glow.withValues(alpha: 0)],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.1, size.height * 0.95),
          radius: size.width * 0.55,
        ),
      );
    canvas.drawRect(Offset.zero & size, glowPaint);
  }

  @override
  bool shouldRepaint(_CardPatternPainter oldDelegate) =>
      oldDelegate.glow != glow;
}

class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.child,
    required this.onTap,
    required this.radius,
  });

  final Widget child;
  final VoidCallback onTap;
  final double radius;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 120),
     
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/money_format.dart';
import '../../app/widgets/kit.dart';
import '../../domain/money.dart';
import '../../engine/monthly_summary.dart';
import 'txn_common.dart';

/// A category ring with direct labels. Segments use the ranked ramp: colour
/// says *how big*, the legend says *what*. Every chart also states its numbers
/// in text, so the painting is never the only source of the value.
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({
    super.key,
    required this.categories,
    required this.total,
    this.maxSlices = 5,
    this.diameter = 124,
    this.stroke = 15,
  });

  final List<CategoryTotal> categories;
  final Paise total;
  final int maxSlices;
  final double diameter;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final slices = _slices();
    if (slices.isEmpty || total.value <= 0) return const SizedBox.shrink();
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final summary = _summary(slices);
    final colors = [
      for (final slice in slices)
        slice.category == null
            ? p.inkMuted
            : categoryColor(context, slice.category!.kind),
    ];
    final donut = Semantics(
      label: summary,
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(
          alignment: Alignment.center,
          children: [
            RepaintBoundary(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: T.chartDraw,
                curve: T.curveOut,
                builder: (context, value, _) => CustomPaint(
                  size: Size.square(diameter),
                  painter: _DonutPainter(
                    fractions: [for (final s in slices) s.total.share / _sum(slices)],
                    colors: colors,
                    track: p.surfaceSunken,
                    stroke: stroke,
                    progress: value,
                  ),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    money(total),
                    style: T.moneyLarge(p.ink).copyWith(fontSize: 19),
                  ),
                ),
                Text(
                  'this month',
                  style: T.bodySmall.copyWith(
                    color: p.inkMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < slices.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == slices.length - 1 ? 0 : 8),
            child: _LegendRow(
              total: slices[i].total,
              color: colors[i],
              share: slices[i].total.share / _sum(slices),
            ),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 280 || textScale >= 1.25;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: donut),
              const SizedBox(height: T.s4),
              legend,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            donut,
            const SizedBox(width: T.s4),
            Expanded(child: legend),
          ],
        );
      },
    );
  }

  List<_Slice> _slices() {
    if (categories.isEmpty) return const [];
    final top = categories.take(maxSlices).toList(growable: false);
    if (categories.length <= maxSlices) {
      return [for (final category in top) _Slice(category, null)];
    }
    final rest = categories.skip(maxSlices);
    var amount = 0;
    for (final category in rest) {
      amount += category.paise;
    }
    final share = total.value == 0 ? 0.0 : amount / total.value;
    return [
      for (final category in top) _Slice(category, null),
      _Slice(null, CategoryTotal(
        name: 'Other',
        kind: categories.first.kind,
        paise: amount,
        txnCount: 0,
        share: share,
        previousPaise: 0,
      )),
    ];
  }

  static double _sum(List<_Slice> slices) =>
      slices.fold<double>(0, (sum, slice) => sum + slice.total.share);

  String _summary(List<_Slice> slices) {
    final parts = <String>[];
    for (final slice in slices) {
      final share = total.value == 0
          ? 0
          : (slice.total.paise / total.value * 100).round();
      parts.add('${slice.name} ${money(slice.total.amount)}, $share percent');
    }
    return 'Spending by category, biggest first. ${parts.join('; ')}. '
        'Total ${money(total)}.';
  }
}

class _Slice {
  const _Slice(this.category, this.other);

  final CategoryTotal? category;
  final CategoryTotal? other;

  CategoryTotal get total => category ?? other!;
  String get name => category?.name ?? 'Other';
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.total,
    required this.color,
    required this.share,
  });

  final CategoryTotal total;
  final Color color;
  final double share;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The money column may never take more than half the legend width: the
        // category name is the label and has to keep room. At a real font the
        // amount fits in that half; under a wide fallback font it ellipsizes
        // instead of pushing the row past its bounds — this row was 5.5 px over
        // at 360 dp, the second automatic-fail-adjacent overflow in round 2.
        final amountWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth * 0.52
            : 96.0;
        return Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: T.s2),
            Expanded(
              child: Text(
                total.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.bodySmall.copyWith(
                  color: p.inkSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: T.s1),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: amountWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(total.amount),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: T.money.copyWith(color: p.ink, fontSize: 13),
                  ),
                  Text(
                    '${(share * 100).round()}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.bodySmall.copyWith(
                      color: p.inkMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.fractions,
    required this.colors,
    required this.track,
    required this.stroke,
    required this.progress,
  });

  final List<double> fractions;
  final List<Color> colors;
  final Color track;
  final double stroke;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - stroke) / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);

    const gap = 0.035; // radians between slices, so adjacent ranks stay legible
    var start = -math.pi / 2;
    for (var i = 0; i < fractions.length; i++) {
      final sweep = fractions[i] * math.pi * 2 * progress;
      if (sweep <= 0.001) continue;
      final usable = math.max(0.0, sweep - (fractions.length > 1 ? gap : 0));
      canvas.drawArc(
        rect,
        start + gap / 2,
        usable,
        false,
        paint..color = colors[i],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.stroke != stroke ||
      oldDelegate.track != track ||
      oldDelegate.colors != colors ||
      oldDelegate.fractions != fractions;
}

/// Daily spend for the month so far, with a "today" marker and the average as
/// a dashed rule. A single semantic summary replaces 31 unreadable bars.
class DailyBars extends StatefulWidget {
  const DailyBars({
    super.key,
    required this.values,
    required this.month,
    this.todayIndex,
    this.height = 86,
    this.color,
    this.todayColor,
  });

  final List<int> values;
  final DateTime month;
  final int? todayIndex;
  final double height;
  final Color? color;
  final Color? todayColor;

  @override
  State<DailyBars> createState() => _DailyBarsState();
}

class _DailyBarsState extends State<DailyBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: T.chartDraw,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final values = widget.values;
    if (values.isEmpty) return const SizedBox.shrink();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final progress = reduceMotion ? 1.0 : T.curveOut.transform(_controller.value);
    var maxValue = 0;
    var total = 0;
    var maxIndex = 0;
    for (var i = 0; i < values.length; i++) {
      total += values[i];
      if (values[i] > maxValue) {
        maxValue = values[i];
        maxIndex = i;
      }
    }
    final average = (total / values.length).round();
    final today = widget.todayIndex;
    final todayValue = today != null && today >= 0 && today < values.length
        ? values[today]
        : null;
    final maxDay = DateTime(
      widget.month.year,
      widget.month.month,
      // [month] is the first bar's day: the 1st for a month, a Monday for a
      // week.
      widget.month.day + maxIndex,
    );

    final semantics =
        'Daily spending for ${values.length} days. '
        '${todayValue == null ? '' : 'Today ${money(Paise(todayValue))}. '}'
        'Average ${money(Paise(average))}. '
        'Highest ${money(Paise(maxValue))} on ${shortDate(maxDay)}.';

    return Semantics(
      label: semantics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              height: widget.height,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _DailyBarsPainter(
                    values: values,
                    todayIndex: today,
                    maxValue: maxValue,
                    average: average,
                    bar: widget.color ?? p.primary,
                    todayBar: widget.todayColor ?? p.accent,
                    baseline: p.outlineVariant,
                    averageLine: p.inkMuted.withValues(alpha: 0.45),
                    progress: progress,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: Row(
              children: [
                Text(
                  shortDate(widget.month),
                  style: T.bodySmall.copyWith(color: p.inkMuted, fontSize: 12),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    today == null
                        ? shortDate(
                            DateTime(
                              widget.month.year,
                              widget.month.month,
                              widget.month.day + values.length - 1,
                            ),
                          )
                        : 'Today · ${money(Paise(todayValue ?? 0))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.bodySmall.copyWith(
                      color: today == null ? p.inkMuted : p.inkSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyBarsPainter extends CustomPainter {
  const _DailyBarsPainter({
    required this.values,
    required this.todayIndex,
    required this.maxValue,
    required this.average,
    required this.bar,
    required this.todayBar,
    required this.baseline,
    required this.averageLine,
    required this.progress,
  });

  final List<int> values;
  final int? todayIndex;
  final int maxValue;
  final int average;
  final Color bar;
  final Color todayBar;
  final Color baseline;
  final Color averageLine;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final gap = n > 24 ? 2.0 : 3.0;
    final barWidth = math.max(1.0, (size.width - gap * (n - 1)) / n);
    final paint = Paint()..style = PaintingStyle.fill;
    final baseY = size.height - 1;

    // Baseline.
    canvas.drawRect(
      Rect.fromLTWH(0, baseY, size.width, 1),
      paint..color = baseline,
    );

    if (maxValue > 0) {
      for (var i = 0; i < n; i++) {
        final value = values[i] * progress;
        final ratio = (value / maxValue).clamp(0.0, 1.0);
        // A small day is still a bar, never a dot.
        final h = math.max(4.0, ratio * (size.height - 10));
        final left = i * (barWidth + gap);
        final isToday = todayIndex == i;
        if (values[i] == 0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(left, baseY - 3, barWidth, 3),
              const Radius.circular(2),
            ),
            paint..color = baseline,
          );
          continue;
        }
        final rect = Rect.fromLTWH(left, baseY - h, barWidth, h);
        final colour = isToday ? todayBar : bar;
        // Columns, not pills: top corners capped at 5 px (a full round cap
        // turned short bars into blobs), filled with a soft vertical fade.
        final top = Radius.circular(math.min(barWidth / 2, 5));
        const foot = Radius.circular(1.5);
        paint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colour, colour.withValues(alpha: 0.55)],
        ).createShader(rect);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: top,
            topRight: top,
            bottomLeft: foot,
            bottomRight: foot,
          ),
          paint,
        );
        paint.shader = null;
      }

      // Average rule.
      final avgY = baseY - (average / maxValue).clamp(0.0, 1.0) * (size.height - 10);
      final dash = Paint()
        ..color = averageLine
        ..strokeWidth = 1;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, avgY), Offset(math.min(x + 4, size.width), avgY), dash);
        x += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DailyBarsPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.maxValue != maxValue ||
      oldDelegate.values != values ||
      oldDelegate.todayIndex != todayIndex ||
      oldDelegate.bar != bar ||
      oldDelegate.todayBar != todayBar;
}

/// Three comparison bars: what is spent, what the month projects to, and last
/// month. The bars share one scale so the comparison is honest.
class PaceBars extends StatelessWidget {
  const PaceBars({
    super.key,
    required this.spend,
    required this.projected,
    required this.previous,
  });

  final Paise spend;
  final Paise projected;
  final Paise previous;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final scale = math.max(
      1,
      math.max(spend.value, math.max(projected.value, previous.value)),
    );
    final rows = <({String label, Paise amount, Color color, double share})>[
      (
        label: 'Spent so far',
        amount: spend,
        color: p.primary,
        share: spend.value / scale,
      ),
      (
        label: 'Projected month-end',
        amount: projected,
        color: p.accent,
        share: projected.value / scale,
      ),
      (
        label: 'Last month',
        amount: previous,
        color: p.inkMuted,
        share: previous.value / scale,
      ),
    ];
    return Semantics(
      label:
          'Spent so far ${money(spend)}. Projected month-end ${money(projected)}. '
          'Last month ${money(previous)}.',
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: T.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    rows[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.bodySmall.copyWith(
                      color: p.inkSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: T.s2),
                Text(
                  money(rows[i].amount),
                  maxLines: 1,
                  softWrap: false,
                  style: T.money.copyWith(
                    color: p.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ShareBar(
              share: rows[i].share,
              color: rows[i].color.withValues(alpha: i == 2 ? 0.55 : 1),
              height: 6,
            ),
          ],
        ],
      ),
    );
  }
}

/// Circular utilisation arc with threshold notches. Used inside card faces and
/// as the one aggregate ring on the Cards screen.
class UtilizationArc extends StatelessWidget {
  const UtilizationArc({
    super.key,
    required this.value,
    required this.color,
    required this.track,
    this.size = 124,
    this.stroke = 12,
    this.center,
    this.notches = true,
    this.gap = 0.0,
  });

  final double? value;
  final Color color;
  final Color track;
  final double size;
  final double stroke;
  final Widget? center;
  final bool notches;

  /// Gap at the start of the arc, in radians. 0 = closed ring.
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (value ?? 0).clamp(0.0, 1.0)),
              duration: T.chartDraw,
              curve: T.curveOut,
              builder: (context, animated, _) => CustomPaint(
                size: Size.square(size),
                painter: _ArcPainter(
                  value: animated,
                  color: color,
                  track: track,
                  stroke: stroke,
                  notches: notches,
                  gap: gap,
                ),
              ),
            ),
          ),
          ?center,
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
    required this.notches,
    required this.gap,
  });

  final double value;
  final Color color;
  final Color track;
  final double stroke;
  final bool notches;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - stroke) / 2 - 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final sweep = math.pi * 2 - gap;
    canvas.drawArc(rect, -math.pi / 2 + gap / 2, sweep, false, paint..color = track);
    if (value > 0.001) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + gap / 2,
        sweep * value,
        false,
        paint..color = color,
      );
    }
    if (!notches) return;
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;
    for (final mark in const [0.30, 0.50, 0.75]) {
      final angle = -math.pi / 2 + gap / 2 + sweep * mark;
      final inner = size.center(Offset.zero) +
          Offset(math.cos(angle), math.sin(angle)) * (rect.width / 2 - stroke / 2);
      final outer = size.center(Offset.zero) +
          Offset(math.cos(angle), math.sin(angle)) * (rect.width / 2 + stroke / 2);
      canvas.drawLine(inner, outer, tick);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.track != track ||
      oldDelegate.stroke != stroke ||
      oldDelegate.notches != notches ||
      oldDelegate.gap != gap;
}

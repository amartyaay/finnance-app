import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens.dart';
import '../money_format.dart';
import '../../domain/money.dart';

/// Small shared widget kit. Screens compose these so spacing, radii and type
/// stay consistent without each screen re-inventing them.
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(T.s4),
    this.onTap,
    this.color,
    this.border = true,
    this.shadow = false,
    this.radius = T.r4,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  /// The default card edge: a soft shadow in light (no line) and a hairline
  /// in dark, where shadows do not read. False for a flat inset surface.
  final bool border;
  final bool shadow;
  final double radius;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final edge = widget.border && widget.color == null;
    final decoration = BoxDecoration(
      color: widget.color ?? p.surface,
      borderRadius: BorderRadius.circular(widget.radius),
      border: edge && p.isDark ? Border.all(color: p.outlineVariant) : null,
      boxShadow: widget.shadow || (edge && !p.isDark) ? p.shadowSoft : null,
    );
    final padded = Padding(padding: widget.padding, child: widget.child);

    if (widget.onTap == null) {
      return DecoratedBox(decoration: decoration, child: padded);
    }

    return Semantics(
      button: true,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: decoration,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(widget.radius),
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              child: padded,
            ),
          ),
        ),
      ),
    );
  }
}

/// A tinted canvas. Use this for one section per screen so the page has a
/// second surface tone instead of a wall of identical white boxes.
class SoftSection extends StatelessWidget {
  const SoftSection({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(T.s4),
    this.radius = T.r4,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: p.tintGradient,
        borderRadius: BorderRadius.circular(radius),
        border: p.isDark ? Border.all(color: p.outlineVariant) : null,
        boxShadow: p.isDark ? null : p.shadowSoft,
      ),
      child: child,
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.onAction,
    this.padding = const EdgeInsets.only(bottom: T.s3),
  });

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: T.sectionTitle.copyWith(color: p.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: T.bodySmall.copyWith(color: p.inkMuted),
                  ),
                ],
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: p.primary,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: T.s2),
                tapTargetSize: MaterialTapTargetSize.padded,
                textStyle: T.bodySmall.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: p.primary,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(action!),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 16, color: p.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Money, set the way a financial product should set it: the rupee mark is
/// small and quiet, the integer carries the weight, paise are smaller and
/// muted. Animated only when the value changes after the first frame.
class MoneyText extends StatefulWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.style,
    this.color,
    this.compact = false,
    this.animate = false,
    this.prefix,
  });

  final Paise amount;
  final TextStyle? style;
  final Color? color;
  final bool compact;
  final bool animate;

  /// A leading sign such as `+` or `−`, kept out of [amount] so the number
  /// itself stays a magnitude.
  final String? prefix;

  @override
  State<MoneyText> createState() => _MoneyTextState();
}

class _MoneyTextState extends State<MoneyText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: T.medium,
    value: 1,
  );
  late int _from;
  late int _to;
  late int _value;

  @override
  void initState() {
    super.initState();
    _from = widget.amount.value;
    _to = widget.amount.value;
    _value = widget.amount.value;
    _controller.addListener(_tick);
  }

  void _tick() {
    setState(() {
      _value = (_from + (_to - _from) * T.curveOut.transform(_controller.value))
          .round();
    });
  }

  @override
  void didUpdateWidget(MoneyText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.amount.value == _to) return;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!widget.animate || reduceMotion) {
      _controller.stop();
      _from = widget.amount.value;
      _to = widget.amount.value;
      _value = widget.amount.value;
      return;
    }
    _from = _value;
    _to = widget.amount.value;
    _controller.duration = T.medium;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.removeListener(_tick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final base = (widget.style ?? T.money).copyWith(
      color: widget.color ?? widget.style?.color ?? p.ink,
    );

    if (widget.compact) {
      final text = widget.animate && _value != widget.amount.value
          ? moneyCompact(Paise(_value))
          : moneyCompact(widget.amount);
      return Text(
        '${widget.prefix ?? ''}$text',
        style: base,
        maxLines: 1,
        softWrap: false,
      );
    }

    final parts = moneyParts(
      widget.animate && _value != widget.amount.value
          ? Paise(_value)
          : widget.amount,
    );
    final color = base.color ?? p.ink;
    final symbol = base.copyWith(
      fontSize: (base.fontSize ?? 15.5) * 0.66,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      color: color.withValues(alpha: 0.62),
    );
    final minor = base.copyWith(
      fontSize: (base.fontSize ?? 15.5) * 0.62,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      color: color.withValues(alpha: 0.62),
    );
    final spokenParts = moneyParts(widget.amount);
    final spoken = '${spokenParts.major}${spokenParts.minor ?? ''}';
    final spokenPrefix = widget.prefix == '+'
        ? 'plus '
        : widget.prefix == '−'
        ? 'minus '
        : '';

    return Semantics(
      label:
          '$spokenPrefix${widget.amount.value < 0 ? 'minus ' : ''}rupees $spoken',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            if (widget.prefix != null)
              TextSpan(
                text: widget.prefix,
                style: base.copyWith(color: color.withValues(alpha: 0.85)),
              ),
            TextSpan(text: parts.symbol, style: symbol),
            TextSpan(text: parts.major),
            if (parts.minor != null) TextSpan(text: parts.minor, style: minor),
          ],
        ),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
      ),
    );
  }
}

enum PillTone { neutral, positive, caution, danger, info, brand }

/// A small rounded label. Its text is **shrinkable**: the chip is a fixed piece
/// of chrome inside rows that get only ~60 dp at 360 dp / 1.3x text, so the label
/// ellipsizes instead of forcing the row to overflow (the round-2 automatic fail
/// was a 63 px overflow from exactly this: a `Row` of unbreakable text).
class Pill extends StatelessWidget {
  const Pill(
    this.label, {
    super.key,
    this.tone = PillTone.neutral,
    this.icon,
    this.dense = false,
  });

  final String label;
  final PillTone tone;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final (bg, fg) = switch (tone) {
      PillTone.neutral => (p.surfaceMuted, p.inkSecondary),
      PillTone.positive => (p.positiveSoft, p.positive),
      PillTone.caution => (p.cautionSoft, p.caution),
      PillTone.danger => (p.dangerSoft, p.danger),
      PillTone.info => (p.infoSoft, p.info),
      PillTone.brand => (p.primarySoft, p.primary),
    };
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: TextStyle(
        fontFamily: T.fontFamily,
        fontSize: dense ? 12 : 12,
        fontWeight: FontWeight.w600,
        color: fg,
        letterSpacing: 0.1,
      ),
    );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? T.s2 : T.s3,
        vertical: dense ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(T.r5),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // `Flexible` only makes sense with a bounded main axis. Inside a
          // horizontally scrolling row there is none, so the label keeps its
          // intrinsic width and the row scrolls instead of asserting.
          final shrinkable = constraints.hasBoundedWidth;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: dense ? 13 : 14, color: fg),
                const SizedBox(width: 4),
              ],
              if (shrinkable) Flexible(child: text) else text,
            ],
          );
        },
      ),
    );
  }
}

/// One horizontally scrolling strip of chips — the single implementation of the
/// filter-chip row (All messages and Activity both use it).
///
/// Two things are deliberate. The row clips to its own bounds, so a chip can
/// never paint past the padded viewport; and the edge fade is a [ShaderMask]
/// painted *over* the chips. The previous version drew a gradient underneath a
/// row with `clipBehavior: Clip.none`, which left chips guillotined at the screen
/// edge while the fade sat hidden behind them.
class ChipStrip extends StatefulWidget {
  const ChipStrip({
    super.key,
    required this.children,
    this.spacing = T.s2,
    this.padding = EdgeInsets.zero,
    this.fade = 24,
  });

  final List<Widget> children;
  final double spacing;
  final EdgeInsetsGeometry padding;

  /// Width of the edge fade. Set to 0 to disable it.
  final double fade;

  @override
  State<ChipStrip> createState() => _ChipStripState();
}

class _ChipStripState extends State<ChipStrip> {
  final ScrollController _scroll = ScrollController();
  bool _moreLeft = false;
  bool _moreRight = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateEdges);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateEdges());
  }

  @override
  void didUpdateWidget(ChipStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.children.length != widget.children.length ||
        oldWidget.fade != widget.fade) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateEdges());
    }
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_updateEdges)
      ..dispose();
    super.dispose();
  }

  /// The fade only appears on a side that has more chips to show, so a strip
  /// that fits still reads as complete.
  void _updateEdges() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    final moreLeft = position.pixels > 1;
    final moreRight = position.pixels < position.maxScrollExtent - 1;
    if (moreLeft == _moreLeft && moreRight == _moreRight) return;
    setState(() {
      _moreLeft = moreLeft;
      _moreRight = moreRight;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strip = SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.hardEdge,
      padding: widget.padding,
      child: Row(
        children: [
          for (var i = 0; i < widget.children.length; i++) ...[
            if (i > 0) SizedBox(width: widget.spacing),
            widget.children[i],
          ],
        ],
      ),
    );
    if (widget.fade <= 0) return strip;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final stop = bounds.width <= 0
            ? 0.0
            : (widget.fade / bounds.width).clamp(0.0, 0.2);
        final (colors, stops) = switch ((_moreLeft, _moreRight)) {
          (true, true) => (
            const [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            [0.0, stop, 1 - stop, 1.0],
          ),
          (true, false) => (
            const [Colors.transparent, Colors.black, Colors.black],
            [0.0, stop, 1.0],
          ),
          (false, true) => (
            const [Colors.black, Colors.black, Colors.transparent],
            [0.0, 1 - stop, 1.0],
          ),
          (false, false) => (const [Colors.black, Colors.black], [0.0, 1.0]),
        };
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: colors,
          stops: stops,
        ).createShader(bounds);
      },
      child: strip,
    );
  }
}

/// The one filter chip in the app: a quiet outline pill when unselected, solid
/// ink with canvas-coloured text when selected.
///
/// It used to exist twice — this `ChoiceChip` on All messages with an ink label
/// on an ink fill (1.0:1, an invisible label) and a hand-rolled container on
/// Activity. Both screens now build chips here, so the selected state has exactly
/// one definition and it is legible: near-white on near-black is ~16:1.
class FilterChipView extends StatelessWidget {
  const FilterChipView({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final ink = selected ? p.bg : p.inkSecondary;
    return Semantics(
      button: true,
      selected: selected,
      child: ChoiceChip(
        showCheckmark: false,
        selected: selected,
        onSelected: (_) {
          HapticFeedback.selectionClick();
          onTap();
        },
        selectedColor: p.ink,
        backgroundColor: p.surface,
        side: BorderSide(color: selected ? p.ink : p.outlineVariant),
        labelPadding: const EdgeInsets.symmetric(horizontal: T.s1),
        avatar: icon == null ? null : Icon(icon, size: 14, color: ink),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: T.bodySmall.copyWith(
            color: ink,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// A soft tinted square that holds a single icon. Keeps icon weight and tile
/// radius consistent across every screen.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.color,
    this.size = 40,
    this.iconSize = 20,
    this.radius = T.r2,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final tone = color ?? p.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: p.isDark ? 0.18 : 0.11),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, size: iconSize, color: tone),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: T.s6, vertical: T.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EmptyIllustration(icon: icon),
          const SizedBox(height: T.s5),
          Text(
            title,
            textAlign: TextAlign.center,
            style: T.title.copyWith(color: p.ink),
          ),
          const SizedBox(height: T.s2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: T.body.copyWith(color: p.inkSecondary),
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: T.s5),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
          if (secondaryLabel != null) ...[
            const SizedBox(height: T.s2),
            TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ],
      ),
    );
  }
}

/// A quiet illustration: concentric orbits and a dot field behind the icon.
/// Drawn once, static, no assets.
class _EmptyIllustration extends StatelessWidget {
  const _EmptyIllustration({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              size: const Size.square(132),
              painter: _OrbitPainter(
                ring: p.primary.withValues(alpha: p.isDark ? 0.34 : 0.22),
                dot: p.accent.withValues(alpha: p.isDark ? 0.5 : 0.32),
                core: p.primarySoft,
              ),
            ),
          ),
          Icon(icon, size: 38, color: p.primary),
        ],
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter({
    required this.ring,
    required this.dot,
    required this.core,
  });

  final Color ring;
  final Color dot;
  final Color core;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = ring;
    canvas.drawCircle(center, size.width * 0.30, paint);
    canvas.drawCircle(
      center,
      size.width * 0.43,
      paint..color = ring.withValues(alpha: 0.45),
    );
    canvas.drawCircle(center, size.width * 0.19, Paint()..color = core);
    final dotPaint = Paint()..color = dot;
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 + 0.35;
      final radius = size.width * 0.43;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        i.isEven ? 3 : 2,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) =>
      oldDelegate.ring != ring ||
      oldDelegate.dot != dot ||
      oldDelegate.core != core;
}

class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.info_rounded,
    this.tone = PillTone.info,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final IconData icon;
  final PillTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

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
    // A calm card with a tinted icon disc: the colour carries the tone, the
    // words stay in ink so a warning reads as information, not an alarm.
    return Container(
      padding: const EdgeInsets.fromLTRB(T.s4, T.s4, T.s3, T.s4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(T.r4),
        border: p.isDark ? Border.all(color: p.outlineVariant) : null,
        boxShadow: p.isDark ? null : p.shadowSoft,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconDisc(icon: icon, color: fg),
          const SizedBox(width: T.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 1),
                Text(
                  title,
                  style: T.cardTitle.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: T.bodySmall.copyWith(
                    color: p.inkSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                if (actionLabel != null) ...[
                  const SizedBox(height: T.s1),
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: fg,
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: T.s1),
                      alignment: Alignment.centerLeft,
                      textStyle: T.bodySmall.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(actionLabel!),
                        Icon(Icons.arrow_forward_rounded, size: 14, color: fg),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A round, softly tinted disc holding an icon — the app's one way of giving
/// a row or a notice its colour.
class IconDisc extends StatelessWidget {
  const IconDisc({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: p.isDark ? 0.18 : 0.11),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// The brand surface: a deep gradient with two soft light blooms (the "mesh
/// gradient" look), painted in code — no image assets, crisp at any size.
/// Used for the one hero per screen.
class HeroSurface extends StatelessWidget {
  const HeroSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(T.s5),
    this.radius = T.r5,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Defaults to the palette's hero gradient.
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: p.shadowCard),
      child: ClipRRect(
        borderRadius: shape,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: gradient ?? p.heroGradient),
          child: CustomPaint(
            painter: _BloomPainter(dark: p.isDark),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// The page's ambient light: a soft violet glow from the top left and a
/// cyan one from the top right, fading into the canvas. Painted once behind
/// all four tabs by the shell.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _AmbientPainter(p.primary, dark: p.isDark)),
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter(this.primary, {required this.dark});

  final Color primary;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    void glow(Offset centre, double radius, Color color) {
      final rect = Rect.fromCircle(center: centre, radius: radius);
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }

    final w = size.width;
    glow(
      Offset(w * 0.1, -w * 0.15),
      w * 1.0,
      primary.withValues(alpha: dark ? 0.22 : 0.10),
    );
    glow(
      Offset(w * 1.05, w * 0.05),
      w * 0.75,
      T.mintGlow.withValues(alpha: dark ? 0.10 : 0.07),
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter oldDelegate) =>
      oldDelegate.primary != primary || oldDelegate.dark != dark;
}

class _BloomPainter extends CustomPainter {
  const _BloomPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    void bloom(Offset centre, double radius, Color color) {
      final rect = Rect.fromCircle(center: centre, radius: radius);
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }

    final w = size.width;
    final h = size.height;
    // Magenta light from the top right, a cyan pool bottom left.
    bloom(
      Offset(w * 0.92, h * 0.02),
      w * 0.62,
      T.magentaGlow.withValues(alpha: dark ? 0.30 : 0.34),
    );
    bloom(
      Offset(w * 0.05, h * 1.05),
      w * 0.70,
      T.mintGlow.withValues(alpha: dark ? 0.22 : 0.26),
    );
    // A faint diagonal sheen across the face.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.6],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_BloomPainter oldDelegate) => oldDelegate.dark != dark;
}

/// A thin horizontal bar used in category and utilisation breakdowns.
class ShareBar extends StatefulWidget {
  const ShareBar({
    super.key,
    required this.share,
    required this.color,
    this.height = 6,
    this.animate = true,
    this.ticks = false,
  });

  final double share;
  final Color color;
  final double height;
  final bool animate;
  final bool ticks;

  @override
  State<ShareBar> createState() => _ShareBarState();
}

class _ShareBarState extends State<ShareBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: T.slow,
    value: 1,
  );
  late double _from = 0;
  late double _to = widget.share.clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller.value = 0;
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(ShareBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.share.clamp(0.0, 1.0);
    if ((next - _to).abs() < 0.0001) return;
    _from = _current;
    _to = next;
    if (!widget.animate) {
      _controller.value = 1;
      return;
    }
    _controller.forward(from: 0);
  }

  double get _current =>
      _from + (_to - _from) * T.curveOut.transform(_controller.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final value = widget.animate ? _current : _to;
        return SizedBox(
          height: widget.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: p.surfaceSunken,
                  borderRadius: BorderRadius.circular(widget.height),
                ),
              ),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(widget.height),
                  ),
                ),
              ),
              if (widget.ticks)
                CustomPaint(
                  painter: _TickPainter(
                    color: p.inkMuted.withValues(alpha: 0.40),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TickPainter extends CustomPainter {
  const _TickPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (final mark in const [0.30, 0.50, 0.75]) {
      final x = size.width * mark;
      canvas.drawLine(
        Offset(x, size.height * 0.15),
        Offset(x, size.height * 0.85),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TickPainter oldDelegate) => oldDelegate.color != color;
}

/// Skeleton placeholder used while the first load runs. Its pulse is the only
/// ambient loop in the app.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.height = 16,
    this.width = double.infinity,
    this.radius = 8,
  });

  final double height;
  final double width;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      return Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: p.surfaceMuted,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Color.lerp(p.surfaceMuted, p.surfaceSunken, _controller.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Staggered entrance for page sections: a short fade and rise, 240 ms,
/// ease-out, never a bounce. Runs once, and not at all when the platform asks
/// for reduced motion.
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = const Duration(milliseconds: 240),
  });

  final Widget child;
  final int index;
  final Duration duration;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  static const _stagger = Duration(milliseconds: 38);

  late final Duration _total =
      widget.duration + _stagger * math.min(widget.index, 7);
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _total,
  );
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      math.min(0.35, (widget.index * 0.06)),
      1,
      curve: T.curveOut,
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) return widget.child;
    return FadeTransition(
      opacity: _animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(_animation),
        child: widget.child,
      ),
    );
  }
}

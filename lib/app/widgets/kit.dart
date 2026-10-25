import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../../domain/money.dart';

/// Small shared widget kit. Screens compose these so spacing, radii and type
/// stay consistent without each screen re-inventing them.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(T.s4),
    this.onTap,
    this.color,
    this.border = true,
    this.shadow = false,
    this.radius = T.r3,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final bool border;
  final bool shadow;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? scheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: scheme.outlineVariant) : null,
        boxShadow: shadow ? T.shadowSoft : null,
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: content,
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
    this.padding = const EdgeInsets.only(bottom: T.s3),
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(title, style: T.cardTitle.copyWith(color: scheme.onSurface))),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: T.s2),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

/// Money text with optional animated count-up from a previous value.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.style,
    this.color,
    this.compact = false,
    this.animate = false,
  });

  final Paise amount;
  final TextStyle? style;
  final Color? color;
  final bool compact;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = (style ?? T.money).copyWith(color: color ?? scheme.onSurface);
    final text = compact ? inrCompact(amount) : inr(amount);
    if (!animate) return Text(text, style: textStyle);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: T.slow,
      curve: T.curveOut,
      builder: (context, value, _) => Text(
        compact
            ? inrCompact(Paise((amount.value * value).round()))
            : inr(Paise((amount.value * value).round())),
        style: textStyle,
      ),
    );
  }
}

enum PillTone { neutral, positive, caution, danger, info, brand }

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
    final (bg, fg) = switch (tone) {
      PillTone.neutral => (Theme.of(context).colorScheme.surfaceContainerHigh, T.inkSecondary),
      PillTone.positive => (T.positiveSoft, T.positive),
      PillTone.caution => (T.cautionSoft, T.caution),
      PillTone.danger => (T.dangerSoft, T.danger),
      PillTone.info => (T.infoSoft, T.info),
      PillTone.brand => (T.primarySoft, T.primary),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? T.s2 : T.s3,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(T.r5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w600,
              color: fg,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: T.s6, vertical: T.s7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(T.r4),
            ),
            child: Icon(icon, color: scheme.onPrimaryContainer, size: 26),
          ),
          const SizedBox(height: T.s4),
          Text(title, textAlign: TextAlign.center, style: T.title.copyWith(color: scheme.onSurface)),
          const SizedBox(height: T.s2),
          Text(
            body,
            textAlign: TextAlign.center,
            style: T.body.copyWith(color: scheme.onSurfaceVariant),
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

class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.info_outline_rounded,
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
    final (bg, fg) = switch (tone) {
      PillTone.danger => (T.dangerSoft, T.danger),
      PillTone.caution => (T.cautionSoft, T.caution),
      PillTone.positive => (T.positiveSoft, T.positive),
      PillTone.brand => (T.primarySoft, T.primary),
      _ => (T.infoSoft, T.info),
    };
    return Container(
      padding: const EdgeInsets.all(T.s4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(T.r3),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: T.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: T.cardTitle.copyWith(color: fg, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(body, style: T.body.copyWith(color: fg.withValues(alpha: 0.9), fontSize: 13)),
                if (actionLabel != null) ...[
                  const SizedBox(height: T.s2),
                  GestureDetector(
                    onTap: onAction,
                    child: Text(
                      actionLabel!,
                      style: T.body.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                        decorationColor: fg,
                      ),
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

/// A thin horizontal bar used in category breakdowns.
class ShareBar extends StatelessWidget {
  const ShareBar({
    super.key,
    required this.share,
    required this.color,
    this.height = 6,
  });

  final double share;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(height: height, color: scheme.surfaceContainerHigh),
          FractionallySizedBox(
            widthFactor: share.clamp(0.0, 1.0),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton placeholder used while the first load runs.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.height = 16, this.width = double.infinity, this.radius = 8});

  final double height;
  final double width;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Color.lerp(
            scheme.surfaceContainerLow,
            scheme.surfaceContainerHigh,
            _controller.value,
          ),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

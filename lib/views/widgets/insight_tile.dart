import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/widgets/kit.dart';
import '../../domain/money.dart';
import '../../engine/insights_engine.dart';

/// Tone never appears as colour alone: the same tone also picks the icon and
/// the chip word, so the meaning survives a colour-blind reader.
Color insightToneColor(BuildContext context, InsightTone tone) {
  final p = T.of(context);
  return switch (tone) {
    InsightTone.warning => p.danger,
    InsightTone.caution => p.caution,
    InsightTone.positive => p.positive,
    InsightTone.neutral => p.info,
  };
}

PillTone insightTonePill(InsightTone tone) => switch (tone) {
  InsightTone.warning => PillTone.danger,
  InsightTone.caution => PillTone.caution,
  InsightTone.positive => PillTone.positive,
  InsightTone.neutral => PillTone.info,
};

IconData insightToneIcon(InsightTone tone) => switch (tone) {
  InsightTone.warning => Icons.error_rounded,
  InsightTone.caution => Icons.visibility_rounded,
  InsightTone.positive => Icons.trending_up_rounded,
  InsightTone.neutral => Icons.insights_rounded,
};

/// The engine speaks in counts ("in 1 days"). The card is the last place to
/// clean the grammar up without touching the number.
String _tidyTitle(String title) {
  if (title.contains('in 1 days')) {
    return title.replaceFirst('in 1 days', 'tomorrow');
  }
  if (title.contains('in 0 days')) {
    return title.replaceFirst('in 0 days', 'today');
  }
  return title;
}

/// One claim, ranked by how much it matters. Warnings and cautions get a tint
/// so they lead the eye; everything else stays on the calm surface.
class InsightTile extends StatelessWidget {
  const InsightTile({super.key, required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final toneColor = insightToneColor(context, insight.tone);
    final emphasised = insight.tone == InsightTone.warning ||
        insight.tone == InsightTone.caution;
    final amount = insight.amountPaise;
    final chip = insight.chip?.trim();
    final title = _tidyTitle(insight.title);
    final semantics = [
      switch (insight.tone) {
        InsightTone.warning => 'Warning',
        InsightTone.caution => 'Watch',
        InsightTone.positive => 'Good news',
        InsightTone.neutral => 'Note',
      },
      title,
      insight.body,
      if (amount != null && amount != 0) inr(Paise(amount)),
    ].join('. ');

    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          border: Border.all(
            color: emphasised
                ? toneColor.withValues(alpha: 0.30)
                : p.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(T.r3),
        ),
        padding: const EdgeInsets.all(T.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconBadge(
                  icon: insightToneIcon(insight.tone),
                  color: toneColor,
                  size: 36,
                  iconSize: 18,
                ),
                if (chip != null && chip.isNotEmpty) ...[
                  const SizedBox(width: T.s2),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Pill(
                        chip,
                        tone: insightTonePill(insight.tone),
                        dense: true,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (amount != null && amount != 0)
                  MoneyText(
                    Paise(amount),
                    compact: true,
                    style: T.money.copyWith(fontSize: 16),
                    color: toneColor,
                  ),
              ],
            ),
            const SizedBox(height: T.s3),
            Text(
              title,
              style: T.cardTitle.copyWith(color: p.ink, fontSize: 15.5),
            ),
            const SizedBox(height: T.s1),
            Text(
              insight.body,
              style: T.bodySmall.copyWith(
                color: p.inkSecondary,
                height: 1.42,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

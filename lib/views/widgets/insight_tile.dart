import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/widgets/kit.dart';
import '../../domain/money.dart';
import '../../engine/insights_engine.dart';

/// Tone never appears as colour alone: the same tone also picks the pill word
/// and the icon, so the meaning survives a colour-blind reader.
Color insightToneColor(InsightTone tone) => switch (tone) {
  InsightTone.warning => T.danger,
  InsightTone.caution => T.caution,
  InsightTone.positive => T.positive,
  InsightTone.neutral => T.info,
};

PillTone insightTonePill(InsightTone tone) => switch (tone) {
  InsightTone.warning => PillTone.danger,
  InsightTone.caution => PillTone.caution,
  InsightTone.positive => PillTone.positive,
  InsightTone.neutral => PillTone.info,
};

class InsightTile extends StatelessWidget {
  const InsightTile({super.key, required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final toneColor = insightToneColor(insight.tone);
    final amount = insight.amountPaise;
    final chip = insight.chip?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(T.r3),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(T.r3),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: toneColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(T.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (chip != null && chip.isNotEmpty) ...[
                        Pill(
                          chip,
                          tone: insightTonePill(insight.tone),
                          dense: true,
                        ),
                        const SizedBox(height: T.s2),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              insight.title,
                              style: T.cardTitle.copyWith(
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                          if (amount != null && amount != 0) ...[
                            const SizedBox(width: T.s3),
                            MoneyText(Paise(amount)),
                          ],
                        ],
                      ),
                      const SizedBox(height: T.s1),
                      Text(
                        insight.body,
                        style: T.body.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

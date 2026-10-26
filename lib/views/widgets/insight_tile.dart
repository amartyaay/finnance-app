import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/design_tokens.dart';
import '../../app/money_format.dart';
import '../../app/widgets/kit.dart';
import '../../domain/money.dart';
import '../../engine/card_metrics.dart';
import '../../engine/insights_engine.dart';
import 'txn_common.dart';

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

/// What the insight's action button promises to open.
String insightActionLabel(InsightAction action) => switch (action) {
  InsightAction.categories => 'See categories',
  InsightAction.transactions => 'See entries',
  InsightAction.cards => 'See cards',
  InsightAction.recurring => 'See recurring',
  InsightAction.none => '',
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

/// Re-titles the engine's bill reminders with a calendar-day countdown.
///
/// The engine's `daysToDue` is an hours-based difference, so a bill due the day
/// after tomorrow can read "in 1 days" late in the evening. The card metrics
/// carry the real due date, and the countdown is re-derived from it here.
///
/// This lives beside [InsightTile] because both screens that render an insight
/// need it: Home used to skip it, which is how "bill due in 2 days" ended up
/// beside "Bill due in 1 days" on the same phone.
List<Insight> withCalendarDueDates(
  List<Insight> insights,
  List<CardMetrics> cards,
) => [for (final insight in insights) _calendarDue(insight, cards)];

Insight _calendarDue(Insight insight, List<CardMetrics> cards) {
  if (!insight.id.startsWith('due:')) return insight;
  final key = insight.id.substring('due:'.length);
  for (final card in cards) {
    if (card.card.key != key) continue;
    final due = card.dueDate;
    if (due == null) return insight;
    return Insight(
      id: insight.id,
      title: 'Bill ${billDuePhrase(daysUntilDate(due))}',
      body: insight.body,
      tone: insight.tone,
      chip: insight.chip,
      amountPaise: insight.amountPaise,
      action: insight.action,
    );
  }
  return insight;
}

/// One claim, ranked by how much it matters. Warnings and cautions get a tint
/// so they lead the eye; everything else stays on the calm surface.
///
/// This is the **single** insight row: Home's preview and the Insights list both
/// render it, so the chip, the tone border, the grammar fix and the bill
/// countdown cannot drift apart (round 2 shipped "due in 2 days" on Home beside
/// "due in 1 days" on Insights because a private copy of this widget dropped all
/// four behaviours).
///
/// [onAction] consumes [Insight.action]; [onDismiss] hides the insight for good
/// through `AppState.dismissInsight`.
class InsightTile extends StatelessWidget {
  const InsightTile({
    super.key,
    required this.insight,
    this.onAction,
    this.onDismiss,
  });

  final Insight insight;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final toneColor = insightToneColor(context, insight.tone);
    final amount = insight.amountPaise;
    final chip = insight.chip?.trim();
    final title = _tidyTitle(insight.title);
    final hasAmount = amount != null && amount != 0;
    final actionLabel = insightActionLabel(insight.action);
    final hasAction = onAction != null && insight.action != InsightAction.none;
    final semantics = [
      switch (insight.tone) {
        InsightTone.warning => 'Warning',
        InsightTone.caution => 'Watch',
        InsightTone.positive => 'Good news',
        InsightTone.neutral => 'Note',
      },
      title,
      insight.body,
      if (hasAmount) money(Paise(amount)),
      if (hasAction) '$actionLabel, button',
      if (onDismiss != null) 'Dismiss, button',
    ].join('. ');

    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: Container(
        // Flat surface, soft shadow: the tone lives in the icon disc.
        decoration: BoxDecoration(
          color: p.surface,
          border: p.isDark ? Border.all(color: p.outlineVariant) : null,
          boxShadow: p.isDark ? null : p.shadowSoft,
          borderRadius: BorderRadius.circular(T.r4),
        ),
        padding: const EdgeInsets.all(T.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconDisc(
                  icon: insightToneIcon(insight.tone),
                  color: toneColor,
                  size: 38,
                ),
                if (chip != null && chip.isNotEmpty) ...[
                  const SizedBox(width: T.s2),
                  // Expanded, not a Spacer: the chip gets every spare dp and
                  // ellipsizes, which is exactly what a 63 px overflow at
                  // 360 dp / 1.3x needed.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Pill(
                        chip,
                        tone: insightTonePill(insight.tone),
                        dense: true,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (hasAmount) ...[
                  const SizedBox(width: T.s2),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: MoneyText(
                        Paise(amount),
                        compact: true,
                        style: T.money.copyWith(fontSize: 16),
                        color: toneColor,
                      ),
                    ),
                  ),
                ],
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
            if (hasAction || onDismiss != null) ...[
              const SizedBox(height: T.s1),
              Row(
                children: [
                  if (hasAction)
                    // Expanded, and the label ellipsizes inside the button: a
                    // long action name at 1.3x text must not push the row past
                    // the card edge (that is a 22 px overflow with a wide font).
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            onAction!();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: toneColor,
                            minimumSize: const Size(48, 44),
                            padding: const EdgeInsets.symmetric(
                              horizontal: T.s2,
                            ),
                            textStyle: T.bodySmall.copyWith(
                              color: toneColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  actionLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 14,
                                color: toneColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (onDismiss != null)
                    const Spacer(),
                  if (onDismiss != null)
                    IconButton(
                      tooltip: 'Dismiss insight',
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onDismiss!();
                      },
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: p.inkMuted,
                      ),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 44),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

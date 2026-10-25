import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/widgets/kit.dart';
import '../domain/money.dart';
import '../engine/card_metrics.dart';
import '../state/app_state.dart';
import 'widgets/card_gauge.dart';
import 'widgets/card_limits_card.dart';
import 'widgets/card_tile.dart';

/// Cards: utilisation first, because that is the number that affects a credit
/// score, then the dates that decide when money needs to move.
class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final cards = state.data.cards;

    final Widget body;
    if (state.isLoading && cards.isEmpty) {
      body = const _CardsSkeleton();
    } else if (cards.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(T.s5, T.s8, T.s5, 96),
        children: [
          EmptyState(
            icon: Icons.credit_card_off_rounded,
            title: 'No cards found yet',
            body:
                'Card alerts with a masked number create cards automatically. '
                'Scan your messages and every card you use appears here.',
            actionLabel: 'Scan SMS',
            onAction: state.isScanning ? null : state.scanInbox,
          ),
        ],
      );
    } else {
      final limitTotal = cards.fold<int>(
        0,
        (sum, card) => sum + (card.card.creditLimitPaise ?? 0),
      );
      // Single source for the ring: HomeData aggregates outstanding against the
      // known limits. Never rebuild this from per-card cycle spend.
      final utilization = state.data.totalUtilization;
      final band = utilization == null
          ? UtilizationBand.unknown
          : const CardMetricsCalculator().bandFor(utilization, limitTotal);
      final totalDue = cards.fold<int>(
        0,
        (sum, card) => sum + card.totalDuePaise,
      );
      final nextDue = _nextDueDate(cards);

      body = RefreshIndicator(
        onRefresh: state.scanInbox,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, 96),
          children: [
            CardSummaryCard(
              cards: cards,
              utilization: utilization,
              limit: Paise(limitTotal),
              band: band,
              totalDue: Paise(totalDue),
              nextDue: nextDue,
            ),
            const SizedBox(height: T.s4),
            for (final card in cards) ...[
              CardTile(metrics: card),
              const SizedBox(height: T.s3),
            ],
            const SizedBox(height: T.s2),
            CardLimitsCard(cards: cards),
            const SizedBox(height: T.s3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: T.s1),
                Flexible(
                  child: Text(
                    'Card data stays on this phone.',
                    style: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Cards'), titleSpacing: T.s5),
      body: SafeArea(top: false, bottom: false, child: body),
    );
  }

  DateTime? _nextDueDate(List<CardMetrics> cards) {
    DateTime? next;
    for (final card in cards) {
      final due = card.dueDate;
      if (due == null) continue;
      if (next == null || due.isBefore(next)) next = due;
    }
    return next;
  }
}

class _CardsSkeleton extends StatelessWidget {
  const _CardsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, 96),
      children: [
        const SkeletonBox(height: 236, radius: T.r3),
        const SizedBox(height: T.s4),
        for (var i = 0; i < 2; i++) ...[
          const SkeletonBox(height: 252, radius: T.r3),
          const SizedBox(height: T.s3),
        ],
      ],
    );
  }
}

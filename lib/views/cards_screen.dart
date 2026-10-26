import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/widgets/kit.dart';
import '../domain/money.dart';
import '../engine/card_metrics.dart';
import '../state/app_state.dart';
import 'widgets/card_face.dart';
import 'widgets/card_gauge.dart';
import 'widgets/card_limits_card.dart';
import 'widgets/txn_common.dart';

/// Cards: each card is drawn as a card, because the thing people recognise is
/// the card, not a row of statistics. Utilisation and due dates stay one tap
/// from the face.
class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  final PageController _pager = PageController(viewportFraction: 0.92);
  int _page = 0;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = T.of(context);
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
      final faceHeight = cardFaceHeight(context);
      final dueCards = [...cards.where((c) => c.dueDate != null)]
        ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

      body = RefreshIndicator(
        onRefresh: state.scanInbox,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: T.s1, bottom: 96),
          children: [
            SizedBox(
              height: faceHeight + 10,
              child: PageView.builder(
                // The face's glow shadow must not be cut to the pager's box.
                clipBehavior: Clip.none,
                controller: _pager,
                itemCount: cards.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(
                    left: T.s5,
                    right: T.s5,
                    top: 2,
                    bottom: 8,
                  ),
                  // The face was a picture with no way in. Tapping it opens that
                  // card's detail sheet (limit, statement day, due day) — the one
                  // place those facts can be supplied.
                  child: CardFace(
                    metrics: cards[index],
                    onTap: () => _openCard(cards[index]),
                  ),
                ),
              ),
            ),
            if (cards.length > 1) ...[
              const SizedBox(height: T.s2),
              _PagerDots(
                count: cards.length,
                active: _page,
                controller: _pager,
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(T.s5, T.s4, T.s5, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CardSummaryCard(
                    cards: cards,
                    utilization: utilization,
                    limit: Paise(limitTotal),
                    band: band,
                    totalDue: Paise(totalDue),
                    nextDue: nextDue,
                  ),
                  if (dueCards.isNotEmpty) ...[
                    const SizedBox(height: T.s5),
                    SectionHeader(
                      title: 'Bills',
                      subtitle: 'The dates that decide when money moves',
                      padding: const EdgeInsets.only(bottom: T.s2, left: T.s1),
                    ),
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: T.s4,
                        vertical: T.s1,
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < dueCards.length; i++) ...[
                            if (i > 0)
                              Divider(height: 1, color: p.outlineVariant),
                            _BillRow(metrics: dueCards[i]),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: T.s5),
                  SectionHeader(
                    title: 'Limits & dates',
                    subtitle: 'Only you can supply these two facts',
                    padding: const EdgeInsets.only(bottom: T.s2, left: T.s1),
                  ),
                  CardLimitsCard(cards: cards),
                  const SizedBox(height: T.s4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_rounded, size: 14, color: p.inkMuted),
                      const SizedBox(width: T.s1),
                      Flexible(
                        child: Text(
                          'Card data stays on this phone.',
                          style: T.bodySmall.copyWith(
                            color: p.inkMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Transparent: the shell paints the ambient glow behind every tab.
    return Scaffold(
      backgroundColor: Colors.transparent,
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

  /// Opens the card's own sheet. Haptic first: this is a real object, and the
  /// tap should feel like one.
  void _openCard(CardMetrics metrics) {
    HapticFeedback.lightImpact();
    showCardEditSheet(context, metrics.card);
  }
}

class _PagerDots extends StatelessWidget {
  const _PagerDots({
    required this.count,
    required this.active,
    required this.controller,
  });

  final int count;
  final int active;
  final PageController controller;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              controller.animateToPage(
                i,
                duration: T.medium,
                curve: T.curveOut,
              );
            },
            child: Semantics(
              button: true,
              label: 'Card ${i + 1} of $count',
              child: SizedBox(
                height: 28,
                width: 28,
                child: Center(
                  child: AnimatedContainer(
                    duration: T.medium,
                    curve: T.curveOut,
                    width: i == active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == active ? p.primary : p.outline,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.metrics});

  final CardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final due = metrics.dueDate;
    final hasBill = metrics.totalDuePaise > 0;
    // Calendar days, not elapsed hours: a bill due tomorrow is never "today".
    final days = hasBill && due != null
        ? daysUntilDate(due, now: viewNow(context))
        : metrics.daysToDue;
    final tone = days != null && days < 0 && hasBill
        ? p.danger
        : metrics.dueSoon
        ? p.caution
        : p.primary;
    final dueLabel = due == null
        ? 'No date set'
        : hasBill
        ? '${shortDate(due)} · ${days == null ? '' : daysUntilLabel(days)}'
        : 'Next ${shortDate(due)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: T.s3),
      child: Row(
        children: [
          IconDisc(icon: Icons.event_rounded, color: tone, size: 40),
          const SizedBox(width: T.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metrics.card.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.cardTitle.copyWith(color: p.ink),
                ),
                const SizedBox(height: 1),
                Text(
                  dueLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.bodySmall.copyWith(color: p.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: T.s2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyText(
                hasBill ? metrics.totalDue : metrics.spentThisCycle,
                style: T.money.copyWith(fontSize: 14),
                color: p.ink,
              ),
              const SizedBox(height: 1),
              Text(
                hasBill ? 'total due' : 'this cycle',
                style: T.bodySmall.copyWith(color: p.inkMuted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardsSkeleton extends StatelessWidget {
  const _CardsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, 96),
      children: const [
        SkeletonBox(height: 224, radius: T.r4),
        SizedBox(height: T.s4),
        SkeletonBox(height: 190, radius: T.r3),
        SizedBox(height: T.s4),
        SkeletonBox(height: 64, radius: T.r3),
        SizedBox(height: T.s3),
        SkeletonBox(height: 200, radius: T.r3),
      ],
    );
  }
}

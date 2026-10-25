import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/widgets/kit.dart';
import '../data/finance_repository.dart';
import '../domain/enums.dart';
import '../domain/money.dart';
import '../domain/transaction.dart';
import '../engine/card_metrics.dart';
import '../engine/insights_engine.dart';
import '../engine/monthly_summary.dart';
import '../state/app_state.dart';

/// The dashboard. Answers three questions in one screen, in this order:
/// how much have I spent, is anything wrong, and where did it go.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.onNavigate, this.onOpenSettings});

  /// Switches the shell tab (1 = activity, 2 = cards, 3 = insights).
  final ValueChanged<int>? onNavigate;

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final data = state.data;

    if (state.isLoading && data.isEmpty) {
      return const _HomeSkeleton();
    }
    if (data.isEmpty) {
      return _EmptyHome(state: state);
    }

    return RefreshIndicator(
      onRefresh: state.scanInbox,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            titleSpacing: T.s5,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  style: T.bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(_monthLabel(data.summary.monthStart), style: T.title),
              ],
            ),
            actions: [
              if (state.isDemo)
                Padding(
                  padding: const EdgeInsets.only(right: T.s2),
                  child: Center(
                    child: ActionChip(
                      label: const Text('Demo'),
                      onPressed: state.exitDemo,
                      avatar: const Icon(Icons.science_outlined, size: 16),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Settings',
                onPressed: onOpenSettings,
                icon: const Icon(Icons.account_circle_outlined),
              ),
              IconButton(
                tooltip: 'Scan SMS',
                onPressed: state.isScanning ? null : state.scanInbox,
                icon: state.isScanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
              ),
              const SizedBox(width: T.s2),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, 96),
            sliver: SliverList.list(
              children: [
                _HeroCard(summary: data.summary),
                const SizedBox(height: T.s4),
                _Attention(
                  data: data,
                  onNavigate: onNavigate,
                  onReview: () => onNavigate?.call(1),
                ),
                if (data.summary.byCategory.isNotEmpty) ...[
                  const SizedBox(height: T.s4),
                  _CategoryCard(
                    summary: data.summary,
                    onSeeAll: () => onNavigate?.call(3),
                  ),
                ],
                if (data.cards.isNotEmpty) ...[
                  const SizedBox(height: T.s4),
                  _CardStrip(
                    cards: data.cards,
                    onOpen: () => onNavigate?.call(2),
                  ),
                ],
                if (data.insights.isNotEmpty) ...[
                  const SizedBox(height: T.s4),
                  _InsightPreview(
                    insights: data.insights,
                    onSeeAll: () => onNavigate?.call(3),
                  ),
                ],
                const SizedBox(height: T.s4),
                _RecentList(
                  transactions: data.transactions,
                  onSeeAll: () => onNavigate?.call(1),
                ),
                const SizedBox(height: T.s5),
                _PrivacyFooter(
                  smsRead: data.smsMessagesRead,
                  needsReview: data.needsReview.length,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'Late night';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String _monthLabel(DateTime month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${names[month.month - 1]} ${month.year}';
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.summary});

  final MonthlySummary summary;

  @override
  Widget build(BuildContext context) {
    final change = summary.monthOverMonth;
    final up = change > 0;
    final net = summary.net;

    // One source for the three stats: the parent lays them out as a row or as a
    // two-column wrap, so the cell itself never assumes a fixed width.
    final stats = <({String label, String value})>[
      (label: 'Came in', value: inrCompact(summary.income)),
      (
        label: net.value < 0 ? 'Over' : 'Left',
        // "Over" is a magnitude, so it never carries a minus sign.
        value: inrCompact(Paise(net.value.abs())),
      ),
      (label: 'Per day', value: inrCompact(summary.dailyAverage)),
    ];

    return Container(
      padding: const EdgeInsets.all(T.s5),
      decoration: BoxDecoration(
        gradient: T.heroGradient,
        borderRadius: BorderRadius.circular(T.r4),
        boxShadow: T.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap, not Row: at 1.3x the label and the delta pill are each close to
          // the full card width, so the pill drops to its own run instead of
          // overflowing the header.
          Wrap(
            spacing: T.s2,
            runSpacing: T.s2,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'SPENT THIS MONTH',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.label.copyWith(
                  color: Colors.white.withValues(alpha: 0.78),
                  letterSpacing: 1.1,
                ),
              ),
              if (summary.previousSpendPaise > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: T.s2,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(T.r5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        up
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${(change.abs() * 100).round()}% vs last month',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.label.copyWith(
                            color: Colors.white,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: T.s3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              summary.spend,
              animate: false,
              style: T.heroNumber,
            ),
          ),
          const SizedBox(height: T.s2),
          Text(
            summary.daysElapsed >= 3
                ? 'On track for about ${inr(summary.projectedSpend)} by ${summary.daysInMonth} ${_monthShort(summary.monthStart)}'
                : '${summary.txnCount} payments so far',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: T.body.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: T.s4),
          Divider(color: Colors.white.withValues(alpha: 0.18), height: 1),
          const SizedBox(height: T.s4),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              // Three money columns only fit side by side at body size. Once
              // text grows, reflow to two columns so values are not elided into
              // unreadable stubs.
              final twoColumns = constraints.maxWidth < 260 || scale >= 1.2;
              if (!twoColumns) {
                return Row(
                  children: [
                    for (final stat in stats)
                      Expanded(
                        child: _HeroStat(label: stat.label, value: stat.value),
                      ),
                  ],
                );
              }
              final cellWidth = (constraints.maxWidth - T.s4) / 2;
              return Wrap(
                spacing: T.s4,
                runSpacing: T.s3,
                children: [
                  for (final stat in stats)
                    SizedBox(
                      width: cellWidth,
                      child: _HeroStat(label: stat.label, value: stat.value),
                    ),
                ],
              );
            },
          ),
          if (summary.transferPaise > 0) ...[
            const SizedBox(height: T.s3),
            Text(
              'Excludes ${inrCompact(Paise(summary.transferPaise))} in card bills and transfers',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: T.bodySmall.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _monthShort(DateTime month) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[month.month - 1];
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: T.label.copyWith(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: T.money.copyWith(
            color: Colors.white,
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// A one-row alert: icon, title plus at most two lines of body, trailing text
/// action. The old stacked banner pushed the category section below the fold on
/// a 412x915 phone, so the action moved to the right edge and the copy is
/// bounded instead of allowed to wrap freely.
class _CompactNotice extends StatelessWidget {
  const _CompactNotice({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final PillTone tone;
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
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
      padding: const EdgeInsets.fromLTRB(T.s3, T.s2, T.s1, T.s2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(T.r3),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: T.s2),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.cardTitle.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.bodySmall.copyWith(
                    color: fg.withValues(alpha: 0.92),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: T.s1),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: fg,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: T.s2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: T.bodySmall.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            child: Text(actionLabel, maxLines: 1),
          ),
        ],
      ),
    );
  }
}

class _Attention extends StatelessWidget {
  const _Attention({
    required this.data,
    required this.onReview,
    this.onNavigate,
  });

  final HomeData data;
  final VoidCallback onReview;
  final ValueChanged<int>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];

    for (final alert in data.phishingAlerts.take(1)) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: T.s3),
          child: _CompactNotice(
            tone: PillTone.danger,
            icon: Icons.gpp_maybe_rounded,
            title: 'Possible fraud message',
            body:
                '${alert.sender} · ${alert.preview.length > 90 ? '${alert.preview.substring(0, 90)}…' : alert.preview}',
            actionLabel: 'Check',
            onAction: () => _showPhishing(context, alert),
          ),
        ),
      );
    }

    for (final card in data.cards.where((c) => c.dueSoon).take(1)) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: T.s3),
          child: _CompactNotice(
            tone: PillTone.caution,
            icon: Icons.event_available_rounded,
            title:
                '${card.card.displayName} bill due in ${card.daysToDue} days',
            body:
                '${inr(card.totalDue)} total due${card.minimumDue != null ? ' · ${inr(card.minimumDue!)} minimum' : ''}. '
                'Paying in full avoids interest.',
            actionLabel: 'See card',
            onAction: () => onNavigate?.call(2),
          ),
        ),
      );
    }

    if (data.needsReview.isNotEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: T.s3),
          child: _CompactNotice(
            tone: PillTone.info,
            icon: Icons.help_outline_rounded,
            title:
                '${data.needsReview.length} payment${data.needsReview.length == 1 ? '' : 's'} to confirm',
            body:
                'We parsed these but could not name the merchant with confidence.',
            actionLabel: 'Review',
            onAction: onReview,
          ),
        ),
      );
    }

    if (widgets.isEmpty) return const SizedBox.shrink();
    return Column(children: widgets);
  }

  void _showPhishing(BuildContext context, PhishingAlert alert) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(T.s5, 0, T.s5, T.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Pill(
                  'Likely fraud',
                  tone: PillTone.danger,
                  icon: Icons.gpp_bad_rounded,
                ),
                const Spacer(),
                Text(_timeOfDay(alert.receivedAt), style: T.bodySmall),
              ],
            ),
            const SizedBox(height: T.s4),
            Text('From ${alert.sender}', style: T.cardTitle),
            const SizedBox(height: T.s3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(T.s3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(T.r2),
              ),
              child: Text(
                alert.preview,
                style: T.body.copyWith(fontSize: 13.5),
              ),
            ),
            const SizedBox(height: T.s4),
            Text(
              'Why this was flagged',
              style: T.cardTitle.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: T.s2),
            Text(
              'This message uses the wording and links typical of KYC, refund or '
              'parcel scams. Your bank never asks you to confirm details or share an '
              'OTP through a link.',
              style: T.body,
            ),
            const SizedBox(height: T.s3),
            Text(
              'It was kept out of your spending totals, and no link was opened.',
              style: T.bodySmall,
            ),
            const SizedBox(height: T.s5),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _timeOfDay(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${date.hour < 12 ? 'am' : 'pm'}';
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.summary, this.onSeeAll});

  final MonthlySummary summary;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final top = summary.byCategory.take(5).toList(growable: false);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Where it went',
            action: 'All categories',
            onAction: onSeeAll,
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: T.s2),
          for (var i = 0; i < top.length; i++) ...[
            _CategoryRow(category: top[i], color: T.chart[i % T.chart.length]),
            if (i != top.length - 1) const SizedBox(height: T.s3),
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.color});

  final CategoryTotal category;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final change = category.change;
    // Only a material move earns the extra pill; below 25% the amount and the
    // category name are the information that matters.
    final showChange = change.abs() >= 0.25 && category.previousPaise > 0;
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: T.s2),
            Expanded(
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.body.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: T.s2),
            // The amount is never flexed or ellipsized: it wins the row.
            Text(
              inr(category.amount),
              maxLines: 1,
              style: T.money.copyWith(fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Row(
            children: [
              Expanded(
                child: ShareBar(share: category.share, color: color),
              ),
              if (showChange) ...[
                const SizedBox(width: T.s2),
                Semantics(
                  label:
                      '${change > 0 ? 'Up' : 'Down'} ${(change.abs() * 100).round()} percent vs last month',
                  child: ExcludeSemantics(
                    child: Pill(
                      '${change > 0 ? '▲' : '▼'} ${(change.abs() * 100).round()}%',
                      dense: true,
                      tone: change > 0 ? PillTone.caution : PillTone.positive,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CardStrip extends StatelessWidget {
  const _CardStrip({required this.cards, this.onOpen});

  final List<CardMetrics> cards;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: T.s1),
          child: SectionHeader(
            title: 'Cards',
            action: 'Manage',
            onAction: onOpen,
            padding: EdgeInsets.zero,
          ),
        ),
        // A horizontal ListView needs a fixed height; at 1.3x the card content
        // is taller than that fixed box. An intrinsic Row inside a horizontal
        // scroll view lets the strip grow with the text instead of clipping it.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: T.s3),
                _MiniCard(metrics: cards[i], onTap: onOpen),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.metrics, this.onTap});

  final CardMetrics metrics;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final utilization = metrics.utilization;
    final color = _bandColor(metrics.band);

    return SizedBox(
      width: 244,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(T.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    metrics.card.displayName,
                    maxLines: 1,
                    style: T.cardTitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(metrics.card.masked, maxLines: 1, style: T.bodySmall),
              ],
            ),
            const SizedBox(height: T.s3),
            // Percent, "used" and the band word wrap as a group so a long band
            // label ("Excellent") moves to the next run at 1.3x instead of
            // pushing the number out of the card.
            Wrap(
              spacing: T.s2,
              runSpacing: T.s1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      utilization == null
                          ? '—'
                          : '${(utilization * 100).round()}%',
                      maxLines: 1,
                      style: T.moneyLarge(
                        utilization == null ? scheme.onSurface : color,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('used', style: T.bodySmall),
                    ),
                  ],
                ),
                Pill(
                  metrics.band.label,
                  tone: _bandTone(metrics.band),
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: T.s2),
            ShareBar(share: utilization ?? 0, color: color, height: 5),
            const SizedBox(height: T.s2),
            Text(
              utilization == null
                  ? 'Add the card limit for utilisation'
                  : '${inrCompact(metrics.outstanding)} of ${inrCompact(metrics.limit)}',
              style: T.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  static Color _bandColor(UtilizationBand band) => switch (band) {
    UtilizationBand.excellent || UtilizationBand.healthy => T.positive,
    UtilizationBand.watch => T.caution,
    UtilizationBand.high || UtilizationBand.critical => T.danger,
    UtilizationBand.unknown => T.inkMuted,
  };

  static PillTone _bandTone(UtilizationBand band) => switch (band) {
    UtilizationBand.excellent || UtilizationBand.healthy => PillTone.positive,
    UtilizationBand.watch => PillTone.caution,
    UtilizationBand.high || UtilizationBand.critical => PillTone.danger,
    UtilizationBand.unknown => PillTone.neutral,
  };
}

class _InsightPreview extends StatelessWidget {
  const _InsightPreview({required this.insights, this.onSeeAll});

  final List<Insight> insights;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: T.s1),
          child: SectionHeader(
            title: 'Worth knowing',
            action: 'All insights',
            onAction: onSeeAll,
            padding: EdgeInsets.zero,
          ),
        ),
        for (final insight in insights.take(2)) ...[
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: insight.tone == InsightTone.positive
                        ? T.positive
                        : insight.tone == InsightTone.warning
                        ? T.danger
                        : insight.tone == InsightTone.caution
                        ? T.caution
                        : T.info,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: T.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(insight.title, style: T.cardTitle),
                      const SizedBox(height: 2),
                      Text(insight.body, style: T.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: T.s3),
        ],
      ],
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.transactions, this.onSeeAll});

  final List<Txn> transactions;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final recent = transactions.take(5).toList(growable: false);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(T.s4, T.s4, T.s4, T.s2),
      child: Column(
        children: [
          SectionHeader(
            title: 'Recent',
            action: 'See all',
            onAction: onSeeAll,
            padding: EdgeInsets.zero,
          ),
          for (var i = 0; i < recent.length; i++) ...[
            _RecentRow(txn: recent[i]),
            if (i != recent.length - 1)
              Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.txn});

  final Txn txn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = T.chart[txn.categoryKind.index % T.chart.length];
    final isIncome = txn.kind == TxnKind.income;
    final isTransfer = txn.kind == TxnKind.transfer;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: T.s3),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(T.r2),
            ),
            child: Icon(_iconFor(txn.categoryKind), size: 19, color: color),
          ),
          const SizedBox(width: T.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txn.title,
                  style: T.body.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  _subtitle(txn),
                  style: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: T.s2),
          Text(
            '${isIncome
                ? '+'
                : isTransfer
                ? ''
                : '−'}${inr(txn.amount)}',
            style: T.money.copyWith(
              fontSize: 14,
              color: isIncome
                  ? T.primary
                  : isTransfer
                  ? scheme.onSurfaceVariant
                  : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  static String _subtitle(Txn txn) {
    final parts = <String>[
      if (txn.categoryName != null) txn.categoryName!,
      if (txn.instrument != Instrument.unknown) txn.instrument.label,
      if (txn.last4 != null) '••${txn.last4}',
      _time(txn.occurredAt),
    ];
    return parts.join(' · ');
  }

  static String _time(DateTime date) {
    final today = DateTime.now();
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final clock = '$hour:$minute ${date.hour < 12 ? 'am' : 'pm'}';
    if (isToday) return clock;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  static IconData _iconFor(SpendCategoryKind kind) => switch (kind) {
    SpendCategoryKind.food => Icons.restaurant_rounded,
    SpendCategoryKind.groceries => Icons.shopping_basket_rounded,
    SpendCategoryKind.transport => Icons.directions_car_rounded,
    SpendCategoryKind.shopping => Icons.shopping_bag_rounded,
    SpendCategoryKind.bills => Icons.receipt_long_rounded,
    SpendCategoryKind.rent => Icons.home_rounded,
    SpendCategoryKind.entertainment => Icons.movie_rounded,
    SpendCategoryKind.health => Icons.favorite_rounded,
    SpendCategoryKind.education => Icons.school_rounded,
    SpendCategoryKind.travel => Icons.flight_takeoff_rounded,
    SpendCategoryKind.fuel => Icons.local_gas_station_rounded,
    SpendCategoryKind.investments => Icons.trending_up_rounded,
    SpendCategoryKind.transfers => Icons.swap_horiz_rounded,
    SpendCategoryKind.income => Icons.south_west_rounded,
    SpendCategoryKind.cash => Icons.atm_rounded,
    SpendCategoryKind.other => Icons.circle_outlined,
  };
}

class _PrivacyFooter extends StatelessWidget {
  const _PrivacyFooter({required this.smsRead, required this.needsReview});

  final int smsRead;
  final int needsReview;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final parts = <String>[
      if (smsRead > 0) '$smsRead messages read',
      if (needsReview > 0) '$needsReview to confirm',
      'nothing uploaded',
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, size: 14, color: muted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            parts.join(' · '),
            textAlign: TextAlign.center,
            style: T.bodySmall.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: EmptyState(
              icon: Icons.qr_code_scanner_rounded,
              title: 'No transactions yet',
              body:
                  state.errorMessage ??
                  (state.hasSmsPermission
                      ? 'Your inbox has no bank alerts we could read. Tap scan after a payment, or explore the app with demo data.'
                      : 'Allow SMS access so Finance SMS can read bank and UPI alerts, or look around with generated demo data first.'),
              actionLabel: state.hasSmsPermission
                  ? 'Scan inbox'
                  : 'Allow SMS access',
              onAction: state.hasSmsPermission
                  ? state.scanInbox
                  : state.requestPermission,
              secondaryLabel: 'Explore with demo data',
              onSecondary: state.startDemo,
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(T.s5),
        children: const [
          SkeletonBox(height: 34, width: 180),
          SizedBox(height: T.s5),
          SkeletonBox(height: 200, radius: 20),
          SizedBox(height: T.s4),
          SkeletonBox(height: 120, radius: 16),
          SizedBox(height: T.s4),
          SkeletonBox(height: 180, radius: 16),
        ],
      ),
    );
  }
}

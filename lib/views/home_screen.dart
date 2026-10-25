import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/design_tokens.dart';
import '../app/widgets/kit.dart';
import '../data/finance_repository.dart';
import '../domain/money.dart';
import '../domain/transaction.dart';
import '../engine/card_metrics.dart';
import '../engine/insights_engine.dart';
import '../engine/monthly_summary.dart';
import '../state/app_state.dart';
import 'widgets/card_face.dart';
import 'widgets/charts.dart';
import 'widgets/txn_common.dart';
import 'widgets/txn_detail_sheet.dart';
import 'widgets/txn_row.dart';

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

    final summary = data.summary;
    final hasAttention =
        data.phishingAlerts.isNotEmpty ||
        data.cards.any((c) => c.dueSoon) ||
        data.needsReview.isNotEmpty;

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
                    color: T.of(context).inkMuted,
                    fontSize: 12,
                  ),
                ),
                Text(
                  monthYearLabel(summary.monthStart),
                  style: T.title.copyWith(color: T.of(context).ink),
                ),
              ],
            ),
            actions: [
              if (state.isDemo)
                Padding(
                  padding: const EdgeInsets.only(right: T.s1),
                  child: Center(
                    child: ActionChip(
                      label: const Text('Demo'),
                      onPressed: state.exitDemo,
                      avatar: const Icon(Icons.science_rounded, size: 15),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Settings',
                onPressed: onOpenSettings,
                icon: const Icon(Icons.account_circle_rounded),
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
              const SizedBox(width: T.s1),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(T.s5, T.s2, T.s5, 104),
            sliver: SliverList.list(
              children: [
                Entrance(
                  index: 0,
                  child: _HeroCard(
                    summary: summary,
                    smsRead: data.smsMessagesRead,
                    needsReview: data.needsReview.length,
                    lastScanAt: data.lastScanAt,
                  ),
                ),
                if (hasAttention) ...[
                  const SizedBox(height: T.s3),
                  Entrance(
                    index: 1,
                    child: _Attention(
                      data: data,
                      onNavigate: onNavigate,
                      onReview: () => onNavigate?.call(1),
                    ),
                  ),
                ],
                const SizedBox(height: T.s4),
                Entrance(
                  index: 2,
                  child: _PaceSection(summary: summary),
                ),
                if (summary.byCategory.isNotEmpty) ...[
                  const SizedBox(height: T.s4),
                  Entrance(
                    index: 3,
                    child: _CategoryCard(
                      summary: summary,
                      onSeeAll: () => onNavigate?.call(3),
                    ),
                  ),
                ],
                if (data.cards.isNotEmpty) ...[
                  const SizedBox(height: T.s5),
                  Entrance(
                    index: 4,
                    child: _CardStrip(
                      cards: data.cards,
                      onOpen: () => onNavigate?.call(2),
                    ),
                  ),
                ],
                if (data.insights.isNotEmpty) ...[
                  const SizedBox(height: T.s5),
                  Entrance(
                    index: 5,
                    child: _InsightPreview(
                      insights: data.insights,
                      onSeeAll: () => onNavigate?.call(3),
                    ),
                  ),
                ],
                const SizedBox(height: T.s5),
                Entrance(
                  index: 6,
                  child: _RecentList(
                    transactions: data.transactions,
                    onSeeAll: () => onNavigate?.call(1),
                  ),
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

  /// Truncate on a word boundary, so a warning never ends mid-URL.
  static String _clipWords(String text, int max) {
    final clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length <= max) return clean;
    final window = clean.substring(0, max);
    final space = window.lastIndexOf(' ');
    final cut = space > max ~/ 2 ? window.substring(0, space) : window;
    return '${cut.trimRight()}…';
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

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.summary,
    required this.smsRead,
    required this.needsReview,
    required this.lastScanAt,
  });

  final MonthlySummary summary;
  final int smsRead;
  final int needsReview;
  final DateTime? lastScanAt;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final change = summary.monthOverMonth;
    final up = change > 0;
    final net = summary.net;

    final stats = <({String label, String value})>[
                      (label: 'Came in', value: inrCompact(summary.income)),
                      (
                        label: net.value < 0 ? 'Over' : 'Left over',
                        // "Over" is a magnitude, so it never carries a minus sign.
                        value: inrCompact(Paise(net.value.abs())),
                      ),
                      (label: 'Spend / day', value: inrCompact(summary.dailyAverage)),
    ];

    final provenance = <String>[
      if (smsRead > 0) '$smsRead messages read',
      needsReview > 0 ? '$needsReview to confirm' : 'all clear',
      if (lastScanAt != null) 'as of ${clockTime(lastScanAt!)}',
    ].join(' · ');

    final previousMonth = DateTime(
      summary.monthStart.year,
      summary.monthStart.month - 1,
    );
    final deltaLabel =
        '${(change.abs() * 100).round()}% vs '
        '${MediaQuery.textScalerOf(context).scale(12) / 12 >= 1.2 ? HomeScreen._monthShort(previousMonth) : 'last month'}';

    final spoken =
        '${monthYearLabel(summary.monthStart)}. Spent ${_spoken(summary.spend)}. '
        '${inr(summary.dailyAverage)} a day. '
        '${summary.previousSpendPaise > 0 ? '${(change.abs() * 100).round()} percent ${up ? 'more' : 'less'} than last month. ' : ''}'
        '${_spoken(summary.income)} came in; '
        '${net.value < 0 ? '${_spoken(Paise(net.value.abs()))} over' : '${_spoken(Paise(net.value.abs()))} left'}.';

    return Semantics(
      container: true,
      label: spoken,
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          gradient: p.heroGradient,
          borderRadius: BorderRadius.circular(T.r4),
          boxShadow: p.shadowCard,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(T.r4),
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _HeroPatternPainter(
                      ring: Colors.white.withValues(alpha: 0.055),
                      glow: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(T.s5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: T.s2,
                      runSpacing: T.s2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Spent this month',
                          maxLines: 1,
                          style: T.label.copyWith(
                            color: p.heroMuted,
                            letterSpacing: 0.4,
                            fontSize: 12,
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
                                    deltaLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: T.label.copyWith(
                                      color: Colors.white,
                                      letterSpacing: 0,
                                      fontSize: 12,
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
                        animate: true,
                        style: T.heroNumber,
                      ),
                    ),
                    const SizedBox(height: T.s1),
                    Text(
                      '${inr(summary.dailyAverage)} a day · '
                      '${summary.daysElapsed} of ${summary.daysInMonth} days',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: T.body.copyWith(
                        color: p.heroInk,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      provenance,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: T.bodySmall.copyWith(
                        color: p.heroMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: T.s4),
                    Divider(
                      color: Colors.white.withValues(alpha: 0.16),
                      height: 1,
                    ),
                    const SizedBox(height: T.s3),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final scale =
                            MediaQuery.textScalerOf(context).scale(14) / 14;
                        // Three money columns only fit side by side at body
                        // size. Once text grows, reflow to two columns so
                        // values are not elided into unreadable stubs.
                        final twoColumns =
                            constraints.maxWidth < 260 || scale >= 1.2;
                        if (!twoColumns) {
                          return Row(
                            children: [
                              for (final stat in stats)
                                Expanded(
                                  child: _HeroStat(
                                    label: stat.label,
                                    value: stat.value,
                                  ),
                                ),
                            ],
                          );
                        }
                        final cellWidth =
                            (constraints.maxWidth - T.s4) / 2;
                        return Wrap(
                          spacing: T.s4,
                          runSpacing: T.s3,
                          children: [
                            for (final stat in stats)
                              SizedBox(
                                width: cellWidth,
                                child: _HeroStat(
                                  label: stat.label,
                                  value: stat.value,
                                ),
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
                          color: p.heroMuted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _spoken(Paise amount) =>
      inr(amount).replaceFirst('₹', '').replaceFirst('-', 'minus ');
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
            color: T.of(context).heroMuted,
            fontSize: 12,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: T.money.copyWith(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _HeroPatternPainter extends CustomPainter {
  const _HeroPatternPainter({required this.ring, required this.glow});

  final Color ring;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ring;
    final center = Offset(size.width * 1.02, size.height * 0.04);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(center, size.width * 0.12 * i, paint);
    }
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [glow, glow.withValues(alpha: 0)],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.15, size.height * 0.95),
          radius: size.width * 0.55,
        ),
      );
    canvas.drawRect(Offset.zero & size, glowPaint);
  }

  @override
  bool shouldRepaint(_HeroPatternPainter oldDelegate) =>
      oldDelegate.ring != ring || oldDelegate.glow != glow;
}

/// A one-row alert: icon, title plus at most two lines of body, trailing text
/// action. Compact enough that three of them still leave the spend chart above
/// the fold on a 412x915 phone.
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
    final p = T.of(context);
    final (bg, fg) = switch (tone) {
      PillTone.danger => (p.dangerSoft, p.danger),
      PillTone.caution => (p.cautionSoft, p.caution),
      PillTone.positive => (p.positiveSoft, p.positive),
      PillTone.brand => (p.primarySoft, p.primary),
      _ => (p.infoSoft, p.info),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(T.s3, T.s2, T.s1, T.s2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(T.r3),
        border: Border.all(color: fg.withValues(alpha: 0.12)),
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
                '${alert.sender} · ${HomeScreen._clipWords(alert.preview, 90)}',
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
            icon: Icons.help_rounded,
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
    final p = T.of(context);
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
                Text(
                  clockTime(alert.receivedAt),
                  style: T.bodySmall.copyWith(color: p.inkMuted),
                ),
              ],
            ),
            const SizedBox(height: T.s4),
            Text(
              'From ${alert.sender}',
              style: T.cardTitle.copyWith(color: p.ink),
            ),
            const SizedBox(height: T.s3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(T.s3),
              decoration: BoxDecoration(
                color: p.surfaceMuted,
                borderRadius: BorderRadius.circular(T.r2),
              ),
              child: Text(
                alert.preview,
                style: T.body.copyWith(fontSize: 13.5, color: p.inkSecondary),
              ),
            ),
            const SizedBox(height: T.s4),
            Text(
              'Why this was flagged',
              style: T.cardTitle.copyWith(
                fontWeight: FontWeight.w700,
                color: p.ink,
              ),
            ),
            const SizedBox(height: T.s2),
            Text(
              'This message uses the wording and links typical of KYC, refund or '
              'parcel scams. Your bank never asks you to confirm details or share an '
              'OTP through a link.',
              style: T.body.copyWith(color: p.inkSecondary),
            ),
            const SizedBox(height: T.s3),
            Text(
              'It was kept out of your spending totals, and no link was opened.',
              style: T.bodySmall.copyWith(color: p.inkMuted),
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
}

class _PaceSection extends StatelessWidget {
  const _PaceSection({required this.summary});

  final MonthlySummary summary;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final dayCount = math.max(
      summary.daysElapsed,
      summary.dailySpend.length,
    ).clamp(1, summary.daysInMonth);
    final daily = List<int>.generate(
      dayCount,
      (i) => i < summary.dailySpend.length ? summary.dailySpend[i] : 0,
    );
    final previous = summary.previousSpend;

    return SoftSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "This month's pace",
                  style: T.sectionTitle.copyWith(
                    color: p.ink,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: T.s2),
              Pill(
                '${summary.daysElapsed} of ${summary.daysInMonth} days',
                tone: PillTone.brand,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: T.s3),
          DailyBars(
            values: daily,
            month: summary.monthStart,
            todayIndex: (summary.daysElapsed - 1).clamp(0, daily.length - 1),
            height: 82,
          ),
          const SizedBox(height: T.s3),
          Divider(height: 1, color: p.primary.withValues(alpha: 0.14)),
          const SizedBox(height: T.s3),
          PaceBars(
            spend: summary.spend,
            projected: summary.projectedSpend,
            previous: previous,
          ),
          if (summary.daysElapsed < summary.daysInMonth) ...[
            const SizedBox(height: T.s3),
            Text(
              'Projection assumes the rest of the month spends like the first '
              '${summary.daysElapsed} days.',
              style: T.bodySmall.copyWith(
                color: p.inkMuted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.summary, this.onSeeAll});

  final MonthlySummary summary;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Where it went',
            action: 'Insights',
            onAction: onSeeAll,
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: T.s2),
          CategoryDonut(
            categories: summary.byCategory,
            total: summary.spend,
          ),
        ],
      ),
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
        SectionHeader(
          title: 'Cards',
          action: 'Manage',
          onAction: onOpen,
          padding: const EdgeInsets.only(bottom: T.s2, left: T.s1),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: T.s3),
                SizedBox(
                  width: cards.length == 1 ? null : 238,
                  child: CardFace(
                    metrics: cards[i],
                    compact: true,
                    onTap: onOpen,
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

class _InsightPreview extends StatelessWidget {
  const _InsightPreview({required this.insights, this.onSeeAll});

  final List<Insight> insights;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Worth knowing',
          action: 'All insights',
          onAction: onSeeAll,
          padding: const EdgeInsets.only(bottom: T.s3, left: T.s1),
        ),
        for (final insight in insights.take(2)) ...[
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBadge(
                  icon: _icon(insight.tone),
                  color: _toneColor(context, insight.tone),
                  size: 38,
                  iconSize: 19,
                ),
                const SizedBox(width: T.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        insight.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: T.cardTitle.copyWith(
                          color: T.of(context).ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        insight.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: T.bodySmall.copyWith(
                          color: T.of(context).inkMuted,
                          height: 1.35,
                        ),
                      ),
                      if (insight.amountPaise != null &&
                          insight.amountPaise != 0) ...[
                        const SizedBox(height: 6),
                        MoneyText(
                          Paise(insight.amountPaise!),
                          compact: true,
                          style: T.money.copyWith(fontSize: 13),
                          color: T.of(context).ink,
                        ),
                      ],
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

  static IconData _icon(InsightTone tone) => switch (tone) {
    InsightTone.warning => Icons.error_rounded,
    InsightTone.caution => Icons.visibility_rounded,
    InsightTone.positive => Icons.trending_up_rounded,
    InsightTone.neutral => Icons.insights_rounded,
  };

  static Color _toneColor(BuildContext context, InsightTone tone) {
    final p = T.of(context);
    return switch (tone) {
      InsightTone.warning => p.danger,
      InsightTone.caution => p.caution,
      InsightTone.positive => p.positive,
      InsightTone.neutral => p.info,
    };
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.transactions, this.onSeeAll});

  final List<Txn> transactions;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final recent = transactions.take(5).toList(growable: false);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(T.s2, T.s3, T.s2, T.s1),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: T.s2),
            child: SectionHeader(
              title: 'Recent',
              action: 'See all',
              onAction: onSeeAll,
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: T.s1),
          for (var i = 0; i < recent.length; i++) ...[
            TxnRow(
              txn: recent[i],
              onTap: () => showTransactionDetail(context, recent[i]),
            ),
            if (i != recent.length - 1)
              Divider(height: 1, indent: 64, color: p.outlineVariant),
          ],
        ],
      ),
    );
  }
}

class _PrivacyFooter extends StatelessWidget {
  const _PrivacyFooter({required this.smsRead, required this.needsReview});

  final int smsRead;
  final int needsReview;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    final parts = <String>[
      if (smsRead > 0) '$smsRead messages read',
      if (needsReview > 0) '$needsReview to confirm',
      'nothing uploaded',
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_rounded, size: 14, color: p.inkMuted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            parts.join(' · '),
            textAlign: TextAlign.center,
            style: T.bodySmall.copyWith(color: p.inkMuted, fontSize: 12),
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
          SkeletonBox(height: 30, width: 190),
          SizedBox(height: T.s5),
          SkeletonBox(height: 300, radius: T.r4),
          SizedBox(height: T.s4),
          SkeletonBox(height: 64, radius: T.r3),
          SizedBox(height: T.s3),
          SkeletonBox(height: 288, radius: T.r4),
          SizedBox(height: T.s4),
          SkeletonBox(height: 238, radius: T.r3),
        ],
      ),
    );
  }
}

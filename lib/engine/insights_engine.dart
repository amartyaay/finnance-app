import '../domain/enums.dart';
import '../domain/money.dart';
import '../domain/transaction.dart';
import 'card_metrics.dart';
import 'monthly_summary.dart';
import 'recurring_detector.dart';

enum InsightTone { positive, neutral, caution, warning }

enum InsightAction { none, categories, cards, recurring, transactions }

/// One human sentence the app can honestly claim, with the numbers that back it.
class Insight {
  const Insight({
    required this.id,
    required this.title,
    required this.body,
    required this.tone,
    this.chip,
    this.amountPaise,
    this.action = InsightAction.none,
  });

  final String id;
  final String title;
  final String body;
  final InsightTone tone;
  final String? chip;
  final int? amountPaise;
  final InsightAction action;
}

/// Turns raw transactions into statements a user would actually want to read.
///
/// Every rule is skipped unless the evidence is strong enough to be worth the
/// user's attention — an insight feed that fires constantly gets ignored.
class InsightsEngine {
  const InsightsEngine({this.minAmountPaise = 50000});

  /// Below ₹500 a "spike" is noise, not a signal.
  final int minAmountPaise;

  List<Insight> build({
    required List<Txn> transactions,
    required MonthlySummary summary,
    required List<CardMetrics> cards,
    required List<RecurringSeries> recurring,
    required DateTime now,
  }) {
    final insights = <Insight>[
      ..._categorySpikes(transactions, summary),
      ..._duplicateCharges(transactions, now),
      ..._cardPressure(cards),
      ..._billsDue(cards),
      ..._upcomingRecurring(recurring, now),
      ..._savings(summary),
      ..._projection(summary),
      ..._smallSpends(transactions, now),
      ..._largestSpend(transactions, now),
    ];

    const weight = {
      InsightTone.warning: 0,
      InsightTone.caution: 1,
      InsightTone.positive: 2,
      InsightTone.neutral: 3,
    };
    insights.sort(
      (a, b) => (weight[a.tone] ?? 3).compareTo(weight[b.tone] ?? 3),
    );
    return insights;
  }

  List<Insight> _categorySpikes(List<Txn> txns, MonthlySummary summary) {
    final out = <Insight>[];
    for (final category in summary.byCategory) {
      if (category.paise < minAmountPaise) continue;
      if (category.previousPaise < minAmountPaise) continue;
      // "Other is 3.6x your usual" says nothing a person can act on; an
      // uncategorised pile is a review task, not a spending trend.
      if (category.kind == SpendCategoryKind.other) continue;
      final ratio = category.paise / category.previousPaise;
      if (ratio < 1.4) continue;
      out.add(
        Insight(
          id: 'spike:${category.kind.name}',
          title:
              '${category.name} is ${ratio.toStringAsFixed(1)}× your usual',
          body:
              '${_rupees(category.amount)} this month vs ${_rupees(category.previous)} last month. '
              '${ratio > 2 ? 'That is a big jump — worth a look.' : 'Probably the extra week.'}',
          tone: ratio > 2 ? InsightTone.caution : InsightTone.neutral,
          chip: category.name,
          amountPaise: category.paise - category.previousPaise,
          action: InsightAction.categories,
        ),
      );
    }
    return out;
  }

  List<Insight> _duplicateCharges(List<Txn> txns, DateTime now) {
    final out = <Insight>[];
    final recent = txns
        .where(
          (t) =>
              t.isDuplicateOfKey == null &&
              t.kind == TxnKind.spend &&
              now.difference(t.occurredAt).inDays <= 30,
        )
        .toList()
      ..sort((a, b) => b.occurredAtMs.compareTo(a.occurredAtMs));

    for (var i = 0; i < recent.length; i++) {
      for (var j = i + 1; j < recent.length; j++) {
        final a = recent[i];
        final b = recent[j];
        if (a.occurredAt.difference(b.occurredAt).inMinutes.abs() > 30) break;
        if (a.amountPaise != b.amountPaise) continue;
        if ((a.merchant ?? '').toLowerCase() != (b.merchant ?? '').toLowerCase()) {
          continue;
        }
        if ((a.merchant ?? '').isEmpty) continue;
        out.add(
          Insight(
            id: 'dup:${a.key}',
            title: 'Possible duplicate charge',
            body:
                '${_rupees(a.amount)} at ${a.merchant} was charged twice within 30 minutes. '
                'If this was one payment, ask for a refund.',
            tone: InsightTone.warning,
            chip: a.merchant,
            amountPaise: a.amountPaise,
            action: InsightAction.transactions,
          ),
        );
        break;
      }
      if (out.length >= 2) break;
    }
    return out;
  }

  List<Insight> _cardPressure(List<CardMetrics> cards) {
    return [
      for (final card in cards)
        if (card.utilization != null &&
            card.utilization! >= 0.3 &&
            card.band != UtilizationBand.unknown)
          Insight(
            id: 'util:${card.card.key}',
            title: '${card.card.displayName} is at ${(card.utilization! * 100).round()}% utilisation',
            body:
                '${_rupees(card.outstanding)} of ${_rupees(card.limit)} used, ${card.daysToStatement} days before the statement date. '
                '${card.projectedUtilization != null ? 'On this pace you would end the cycle at ${(card.projectedUtilization! * 100).round()}%.' : ''} '
                '${card.headroomTo30 != null && card.headroomTo30!.value > 0 ? 'Paying ${_rupees(card.headroomTo30!)} would bring it under 30%.' : ''}',
            tone: card.utilization! >= 0.5
                ? InsightTone.warning
                : InsightTone.caution,
            chip: card.card.masked,
            action: InsightAction.cards,
          ),
    ];
  }

  List<Insight> _billsDue(List<CardMetrics> cards) {
    return [
      for (final card in cards)
        if (card.dueSoon)
          Insight(
            id: 'due:${card.card.key}',
            title: 'Bill due in ${card.daysToDue} days',
            body:
                '${_rupees(card.totalDue)} on ${card.card.title}.'
                '${card.minimumDue != null ? ' Minimum due ${_rupees(card.minimumDue!)}.' : ''} Paying the full amount avoids interest.',
            tone: (card.daysToDue ?? 99) <= 2
                ? InsightTone.warning
                : InsightTone.caution,
            chip: card.card.masked,
            amountPaise: card.totalDuePaise,
            action: InsightAction.cards,
          ),
    ];
  }

  List<Insight> _upcomingRecurring(List<RecurringSeries> recurring, DateTime now) {
    return [
      for (final series in recurring)
        if (series.nextExpected.difference(now).inDays >= 0 &&
            series.nextExpected.difference(now).inDays <= 7)
          Insight(
            id: 'rec:${series.merchant}',
            title: '${series.merchant} renews soon',
            body:
                '${_rupees(series.amount)} expected on ${_shortDate(series.nextExpected)}. '
                'That is ${_rupees(Paise(series.annualisedPaise))} a year if it keeps going.',
            tone: InsightTone.neutral,
            chip: series.categoryName,
            amountPaise: series.medianAmountPaise,
            action: InsightAction.recurring,
          ),
    ];
  }

  /// Measured exactly like Home's "Left": what came in minus everything that
  /// went out (spend, cash and card bills), so the two never disagree.
  List<Insight> _savings(MonthlySummary summary) {
    if (summary.incomePaise <= 0) return const [];
    final left = summary.left;
    final out = summary.moneyOut;
    if (left.value < 0) {
      return [
        Insight(
          id: 'savings:over',
          title: 'More went out than came in',
          body:
              '${_rupees(out)} out against ${_rupees(summary.income)} in this month, '
              'a gap of ${_rupees(Paise(-left.value))}. Check the top two categories.',
          tone: InsightTone.caution,
          action: InsightAction.categories,
        ),
      ];
    }
    final rate = left.value / summary.incomePaise;
    if (rate >= 0.3) {
      return [
        Insight(
          id: 'savings:positive',
          title: 'You are keeping ${(rate * 100).round()}% of what came in',
          body:
              '${_rupees(left)} left after ${_rupees(out)} went out this month '
              '(spending, cash and card bills). Anything above 30% is a strong month.',
          tone: InsightTone.positive,
          action: InsightAction.transactions,
        ),
      ];
    }
    if (rate < 0.1) {
      return [
        Insight(
          id: 'savings:low',
          title: 'Spending is close to income this month',
          body:
              '${_rupees(out)} went out against ${_rupees(summary.income)} in, so only '
              '${_rupees(left)} is left.',
          tone: InsightTone.caution,
          action: InsightAction.categories,
        ),
      ];
    }
    return const [];
  }


  List<Insight> _projection(MonthlySummary summary) {
    if (summary.previousSpendPaise <= 0 || summary.daysElapsed < 5) {
      return const [];
    }
    final projected = summary.projectedSpendPaise;
    if (projected <= summary.previousSpendPaise * 1.2) return const [];
    return [
      Insight(
        id: 'projection',
        title: 'On track to spend more than last month',
        body:
            'At ${_rupees(summary.dailyAverage)} a day you will finish around ${_rupees(Paise(projected))}, '
            'against ${_rupees(summary.previousSpend)} last month.',
        tone: InsightTone.caution,
        amountPaise: projected - summary.previousSpendPaise,
        action: InsightAction.categories,
      ),
    ];
  }

  List<Insight> _smallSpends(List<Txn> txns, DateTime now) {
    final start = DateTime(now.year, now.month);
    final small = txns.where(
      (t) =>
          t.isDuplicateOfKey == null &&
          t.kind == TxnKind.spend &&
          t.amountPaise < 30000 &&
          !t.occurredAt.isBefore(start),
    );
    if (small.length < 8) return const [];
    final total = small.fold<int>(0, (sum, t) => sum + t.amountPaise);
    if (total < 100000) return const [];
    return [
      Insight(
        id: 'small-spends',
        title: '${small.length} small payments added up',
        body:
            'Payments under ₹300 came to ${_rupees(Paise(total))} this month across '
            '${small.length} charges — the easiest place to find room.',
        tone: InsightTone.neutral,
        amountPaise: total,
        action: InsightAction.transactions,
      ),
    ];
  }

  List<Insight> _largestSpend(List<Txn> txns, DateTime now) {
    final start = DateTime(now.year, now.month);
    final spends = txns
        .where(
          (t) =>
              t.isDuplicateOfKey == null &&
              t.kind == TxnKind.spend &&
              !t.occurredAt.isBefore(start),
        )
        .toList();
    if (spends.length < 3) return const [];
    spends.sort((a, b) => b.amountPaise.compareTo(a.amountPaise));
    final top = spends.first;
    final median = spends[spends.length ~/ 2].amountPaise;
    if (median <= 0 || top.amountPaise < median * 3) return const [];
    return [
      Insight(
        id: 'largest',
        title: 'Biggest payment: ${top.title}',
        body:
            '${_rupees(top.amount)} on ${_shortDate(top.occurredAt)} — '
            '${(top.amountPaise / median).toStringAsFixed(1)}× your typical payment.',
        tone: InsightTone.neutral,
        chip: top.categoryName,
        amountPaise: top.amountPaise,
        action: InsightAction.transactions,
      ),
    ];
  }

  static String _shortDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}

/// Whole rupees for sentences: "₹21,380 this month vs ₹5,946" reads better
/// than "₹21,379.60 vs ₹5,946".
String _rupees(Paise amount) =>
    inr(Paise(((amount.value / 100).round()) * 100));

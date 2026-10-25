// Sanity-checks the demo dataset and the engines without Flutter.
// Run: dart run tool/demo_check.dart
import 'package:finnance_app/data/demo_data.dart';
import 'package:finnance_app/engine/card_metrics.dart';
import 'package:finnance_app/engine/dedupe_engine.dart';
import 'package:finnance_app/engine/insights_engine.dart';
import 'package:finnance_app/engine/monthly_summary.dart';
import 'package:finnance_app/engine/recurring_detector.dart';
import 'package:finnance_app/domain/money.dart';

void main() {
  final now = DateTime(2026, 6, 18, 14, 30);
  final demo = DemoDataset(now: now);
  final all = const DedupeEngine().mark(demo.transactions);
  final visible = all.where((t) => t.isDuplicateOfKey == null).toList();

  final summary = SummaryCalculator().forMonth(all, now);
  final previous = SummaryCalculator().forMonth(all, now, monthOffset: -1);

  print('transactions: ${demo.transactions.length} '
      '(${all.length - visible.length} merged as duplicate alerts)');
  print('spend this month: ${inr(summary.spend)}  txns ${summary.txnCount}');
  print('income: ${inr(summary.income)}  net ${inr(summary.net)}  '
      'savings ${(summary.savingsRate * 100).toStringAsFixed(1)}%');
  print('previous: ${inr(previous.spend)}  MoM ${(summary.monthOverMonth * 100).round()}%');
  print('projected: ${inr(summary.projectedSpend)}  daily ${inr(summary.dailyAverage)}');
  print('categories:');
  for (final c in summary.byCategory) {
    print('  ${c.name.padRight(18)} ${inr(c.amount).padLeft(12)}  '
        '${(c.share * 100).toStringAsFixed(1)}%  '
        'MoM ${c.previousPaise == 0 ? "n/a" : "${(c.change * 100).round()}%"}');
  }

  final cards = [
    for (final card in demo.cards)
      CardMetricsCalculator().compute(
        card: card,
        transactions: all,
        now: now,
        latestBill: demo.bills.where((b) => b.cardKey == '${card.issuer}|${card.last4}').firstOrNull,
      ),
  ];
  print('cards:');
  for (final c in cards) {
    print('  ${c.card.title.padRight(32)} ${inr(c.outstanding).padLeft(12)} / '
        '${inr(c.limit).padLeft(12)}  ${((c.utilization ?? 0) * 100).toStringAsFixed(1)}% '
        '[${c.band.label}] cycle ${c.spentThisCycle} due ${c.totalDuePaise} in ${c.daysToDue}d');
  }

  final recurring = const RecurringDetector().detect(all);
  print('recurring (${recurring.length}):');
  for (final r in recurring.take(8)) {
    print('  ${r.merchant.padRight(22)} ${inr(r.amount).padLeft(10)} every ${r.intervalDays}d '
        'next ${r.nextExpected.toIso8601String().substring(0, 10)} '
        'annual ${inr(Paise(r.annualisedPaise))}');
  }

  final insights = InsightsEngine().build(
    transactions: all,
    summary: summary,
    cards: cards,
    recurring: recurring,
    now: now,
  );
  print('insights (${insights.length}):');
  for (final i in insights) {
    print('  [${i.tone.name}] ${i.title}\n      ${i.body}');
  }
}

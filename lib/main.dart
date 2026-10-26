import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/budget_store.dart';
import 'data/sqlite_finance_repository.dart';
import 'engine/budget.dart';
import 'engine/monthly_summary.dart';
import 'services/daily_digest_channel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FinanceApp());
}

/// The 10 pm run. `DailyDigestReceiver` starts a headless engine on this
/// entry point: parse the alerts that arrived today, measure the month
/// against the budget, and hand the notification text back to Android.
@pragma('vm:entry-point')
Future<void> digestMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = ChannelDigestScheduler.channel;
  try {
    final repository = SqliteFinanceRepository();
    await repository.processStored();
    final data = await repository.load();
    final budget = await BudgetStore().load();
    if (!budget.dailyDigest) return;
    final now = DateTime.now();
    final status = BudgetStatus.of(
      budget: budget,
      month: const SummaryCalculator().forMonth(data.transactions, now),
      ledger: data.transactions,
      now: now,
    );
    final digest = DailyDigest.compose(
      status,
      topToday: DailyDigest.topToday(data.transactions, now),
    );
    await channel.invokeMethod<void>('post', {
      'title': digest.title,
      'body': digest.body,
      'background': true,
    });
  } on Object catch (error) {
    debugPrint('daily digest failed: $error');
  } finally {
    try {
      await channel.invokeMethod<void>('done');
    } on PlatformException {
      // The receiver's own timeout ends the run.
    }
  }
}

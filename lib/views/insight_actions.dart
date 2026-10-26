import 'package:flutter/material.dart';
import '../domain/transaction.dart';
import '../engine/insights_engine.dart';
import 'transactions_screen.dart';
import 'tabs.dart';
import 'widgets/txn_common.dart';

/// Turns [Insight.action] into a real destination.
///
/// The engine has been computing an action for every insight since round 1 and
/// nothing consumed it, so every insight card was a dead end. Home and Insights
/// both call this one function — an action must not mean two things on two
/// screens, and the destination must not be re-invented per screen.
///
/// Returns `null` when the caller has nothing to open (for example a screen with
/// no navigation at all), so the card renders without a button that would do
/// nothing.
VoidCallback? insightActionHandler(
  Insight insight, {
  void Function(ActivityRequest request)? openActivity,
  void Function(int tab)? openTab,
  List<Txn> transactions = const [],
  VoidCallback? onRecurring,
}) {
  switch (insight.action) {
    case InsightAction.none:
      return null;

    case InsightAction.cards:
      return openTab == null ? null : () => openTab(Tabs.cards);

    case InsightAction.recurring:
      return onRecurring ?? (openTab == null ? null : () => openTab(Tabs.insights));

    case InsightAction.categories:
      final chip = insight.chip?.trim();
      if (chip != null && chip.isNotEmpty && openActivity != null) {
        // The chip is the category's display name; the ledger filters by kind,
        // so resolve the kind the same way the rest of the app does.
        final kind = categoryKindForName(chip, transactions);
        return () => openActivity(ActivityRequest(category: kind));
      }
      return openTab == null ? null : () => openTab(Tabs.activity);

    case InsightAction.transactions:
      final chip = insight.chip?.trim();
      if (chip != null && chip.isNotEmpty && openActivity != null) {
        // A merchant chip narrows the ledger to that merchant rather than
        // dropping the reader at the top of the month.
        return () => openActivity(ActivityRequest(query: chip));
      }
      return openTab == null ? null : () => openTab(Tabs.activity);
  }
}

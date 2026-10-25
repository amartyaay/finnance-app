import '../domain/enums.dart';
import '../domain/money.dart';
import '../domain/transaction.dart';

/// A detected recurring payment (subscription, EMI, rent, SIP, bill).
class RecurringSeries {
  const RecurringSeries({
    required this.merchant,
    required this.label,
    required this.medianAmountPaise,
    required this.occurrences,
    required this.intervalDays,
    required this.lastSeen,
    required this.nextExpected,
    required this.categoryName,
    required this.categoryKind,
    required this.isAmountStable,
  });

  final String merchant;
  final String label;
  final int medianAmountPaise;
  final List<int> occurrences;
  final int intervalDays;
  final DateTime lastSeen;
  final DateTime nextExpected;
  final String categoryName;
  final SpendCategoryKind categoryKind;
  final bool isAmountStable;

  Paise get amount => Paise(medianAmountPaise);
  int get daysUntilNext => nextExpected.difference(DateTime.now()).inDays;
  int get annualisedPaise =>
      intervalDays <= 0 ? 0 : (medianAmountPaise * 365 / intervalDays).round();
}

/// Rule-based recurrence detection from transactions alone.
///
/// Requires at least [minOccurrences] charges from the same merchant, spaced
/// roughly a month (or a week / a year) apart, with amounts inside a tolerance
/// band. Deliberately conservative: a false "subscription" is more annoying
/// than a missed one.
class RecurringDetector {
  const RecurringDetector({
    this.minOccurrences = 3,
    this.amountTolerance = 0.12,
    this.intervalToleranceDays = 6,
  });

  final int minOccurrences;
  final double amountTolerance;
  final int intervalToleranceDays;

  List<RecurringSeries> detect(List<Txn> transactions) {
    final byMerchant = <String, List<Txn>>{};
    for (final txn in transactions) {
      if (txn.isDuplicateOfKey != null) continue;
      if (txn.kind != TxnKind.spend) continue;
      final key = _normalise(txn.merchant ?? txn.title);
      if (key.length < 3) continue;
      byMerchant.putIfAbsent(key, () => []).add(txn);
    }

    final results = <RecurringSeries>[];
    for (final entry in byMerchant.entries) {
      final items = entry.value..sort((a, b) => a.occurredAtMs.compareTo(b.occurredAtMs));
      if (items.length < minOccurrences) continue;

      final amounts = items.map((t) => t.amountPaise).toList()..sort();
      final median = amounts[amounts.length ~/ 2];
      if (median <= 0) continue;
      final stable = amounts.every(
        (a) => (a - median).abs() <= median * amountTolerance,
      );
      // A merchant with wildly varying amounts (Amazon, Swiggy) is not a
      // subscription, however regular the purchases look.
      if (!stable) continue;

      final gaps = <int>[];
      for (var i = 1; i < items.length; i++) {
        gaps.add(
          items[i].occurredAt.difference(items[i - 1].occurredAt).inDays,
        );
      }
      if (gaps.isEmpty) continue;
      gaps.sort();
      final medianGap = gaps[gaps.length ~/ 2];
      if (medianGap < 5) continue;

      final expected = _expectedInterval(medianGap);
      if (expected == null) continue;
      final matches = gaps.every(
        (g) => (g - expected).abs() <= intervalToleranceDays,
      );
      if (!matches) continue;

      final last = items.last;
      results.add(
        RecurringSeries(
          merchant: last.merchant ?? last.title,
          label: last.categoryName ?? 'Recurring payment',
          medianAmountPaise: median,
          occurrences: items.map((t) => t.occurredAtMs).toList(growable: false),
          intervalDays: expected,
          lastSeen: last.occurredAt,
          nextExpected: last.occurredAt.add(Duration(days: expected)),
          categoryName: last.categoryName ?? 'Other',
          categoryKind: last.categoryKind,
          isAmountStable: stable,
        ),
      );
    }

    results.sort((a, b) => b.medianAmountPaise.compareTo(a.medianAmountPaise));
    return results;
  }

  int? _expectedInterval(int medianGap) {
    if (medianGap <= 9) return 7;
    if (medianGap <= 19) return 14;
    if (medianGap <= 40) return 30;
    if (medianGap <= 100) return 90;
    if (medianGap <= 200) return 180;
    if (medianGap <= 400) return 365;
    return null;
  }

  static String _normalise(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

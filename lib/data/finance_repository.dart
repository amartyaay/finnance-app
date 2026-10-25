import '../domain/enums.dart';
import '../domain/sms_message.dart';
import '../domain/transaction.dart';
import '../engine/card_metrics.dart';
import '../engine/txn_guards.dart';
import '../engine/insights_engine.dart';
import '../engine/monthly_summary.dart';
import '../engine/recurring_detector.dart';

/// Everything a screen needs, computed once per data change.
class HomeData {
  const HomeData({
    required this.transactions,
    required this.summary,
    required this.previousSummary,
    required this.cards,
    required this.recurring,
    required this.insights,
    required this.phishingAlerts,
    required this.needsReview,
    required this.lastScanAt,
    required this.smsMessagesRead,
    required this.isDemo,
    required this.categories,
  });

  final List<Txn> transactions;
  final MonthlySummary summary;
  final MonthlySummary previousSummary;
  final List<CardMetrics> cards;
  final List<RecurringSeries> recurring;
  final List<Insight> insights;

  /// Messages the classifier flagged as phishing/fraud, newest first.
  final List<PhishingAlert> phishingAlerts;
  final List<Txn> needsReview;
  final DateTime? lastScanAt;
  final int smsMessagesRead;
  final bool isDemo;
  final List<String> categories;

  static HomeData empty(DateTime now) => HomeData(
    transactions: const [],
    summary: MonthlySummary.empty(now),
    previousSummary: MonthlySummary.empty(now),
    cards: const [],
    recurring: const [],
    insights: const [],
    phishingAlerts: const [],
    needsReview: const [],
    lastScanAt: null,
    smsMessagesRead: 0,
    isDemo: false,
    categories: const [],
  );

  bool get isEmpty => transactions.isEmpty && smsMessagesRead == 0;

  List<CardMetrics> get cardsWithLimit =>
      cards.where((c) => c.card.creditLimitPaise != null).toList(growable: false);

  /// Aggregate utilisation across cards that have a known limit.
  double? get totalUtilization {
    var used = 0;
    var limit = 0;
    for (final card in cards) {
      final cardLimit = card.card.creditLimitPaise;
      if (cardLimit == null || cardLimit <= 0) continue;
      used += card.outstandingPaise;
      limit += cardLimit;
    }
    if (limit <= 0) return null;
    return used / limit;
  }
}

class PhishingAlert {
  const PhishingAlert({
    required this.smsId,
    required this.sender,
    required this.preview,
    required this.receivedAtMs,
    required this.reason,
    required this.score,
  });

  final String smsId;
  final String sender;
  final String preview;
  final int receivedAtMs;
  final String reason;
  final double score;

  DateTime get receivedAt => DateTime.fromMillisecondsSinceEpoch(receivedAtMs);
}

class IngestResult {
  const IngestResult({
    required this.smsRead,
    required this.transactionsFound,
    required this.duplicatesMerged,
    required this.phishingFound,
  });

  final int smsRead;
  final int transactionsFound;
  final int duplicatesMerged;
  final int phishingFound;

  static const none = IngestResult(
    smsRead: 0,
    transactionsFound: 0,
    duplicatesMerged: 0,
    phishingFound: 0,
  );
}

/// The data boundary the UI talks to.
abstract class FinanceRepository {
  bool get isDemo;

  Future<HomeData> load();

  /// Reads new SMS (Android) and turns them into transactions.
  Future<IngestResult> ingest();

  Future<void> assignCategory({
    required String txnKey,
    required String categoryName,
    required SpendCategoryKind kind,
  });

  Future<void> saveCard(CardAccount card);

  Future<void> dismissInsight(String id);

  /// Seeds a realistic demo dataset and switches the app into demo mode.
  Future<void> startDemo();

  /// Returns to real data.
  Future<void> exitDemo();

  Future<void> clearAll();
}

/// Raised when SMS permission is missing so the UI can show the right state.
class SmsPermissionMissing implements Exception {
  const SmsPermissionMissing();

  @override
  String toString() => 'SMS permission is required to read transaction alerts.';
}

/// Shared composition of the engines so both repositories behave identically.
class HomeDataBuilder {
  HomeDataBuilder({
    this.summaryCalculator = const SummaryCalculator(),
    this.cardCalculator = const CardMetricsCalculator(),
    this.recurringDetector = const RecurringDetector(),
    this.insightsEngine = const InsightsEngine(),
  });

  final SummaryCalculator summaryCalculator;
  final CardMetricsCalculator cardCalculator;
  final RecurringDetector recurringDetector;
  final InsightsEngine insightsEngine;

  HomeData build({
    required List<Txn> transactions,
    required List<CardAccount> cards,
    required List<CardBillNotice> bills,
    required List<SmsMessage> smsMessages,
    required List<SmsAssessment> assessments,
    required List<String> categories,
    required DateTime now,
    required bool isDemo,
    required DateTime? lastScanAt,
    required int smsRead,
    required List<Txn> needsReview,
  }) {
    // Ledger admission, applied to every data source (real, demo, import).
    // Dedupe already ran in the repository that owns the storage; this only
    // decides whether a parsed row is allowed to affect totals at all.
    final counted = [
      for (final txn in transactions)
        if (const TxnGuards().isCountable(txn)) txn,
    ];

    final visible = counted
        .where((t) => t.isDuplicateOfKey == null)
        .toList(growable: false);
    final summary = summaryCalculator.forMonth(counted, now);
    final previous = summaryCalculator.forMonth(counted, now, monthOffset: -1);

    final cardMetrics = <CardMetrics>[
      for (final card in cards)
        cardCalculator.compute(
          card: card,
          transactions: counted,
          now: now,
          latestBill: _latestBillFor(card, bills),
        ),
    ]..sort((a, b) => b.outstandingPaise.compareTo(a.outstandingPaise));

    final recurring = recurringDetector.detect(counted);
    final insights = insightsEngine.build(
      transactions: counted,
      summary: summary,
      cards: cardMetrics,
      recurring: recurring,
      now: now,
    );

    final alerts = <PhishingAlert>[];
    for (var i = 0; i < smsMessages.length && i < assessments.length; i++) {
      final assessment = assessments[i];
      if (!assessment.isPhishing) continue;
      final message = smsMessages[i];
      alerts.add(
        PhishingAlert(
          smsId: message.id,
          sender: message.sender,
          preview: message.body,
          receivedAtMs: message.receivedAtMs,
          reason: assessment.topSignals().map((s) => s.code).join(', '),
          score: assessment.score,
        ),
      );
    }
    alerts.sort((a, b) => b.receivedAtMs.compareTo(a.receivedAtMs));

    return HomeData(
      transactions: visible,
      summary: summary,
      previousSummary: previous,
      cards: cardMetrics,
      recurring: recurring,
      insights: insights,
      phishingAlerts: alerts.take(5).toList(growable: false),
      needsReview: needsReview,
      lastScanAt: lastScanAt,
      smsMessagesRead: smsRead,
      isDemo: isDemo,
      categories: categories,
    );
  }

  CardBillNotice? _latestBillFor(CardAccount card, List<CardBillNotice> bills) {
    CardBillNotice? latest;
    for (final bill in bills) {
      if (bill.cardKey != card.key) continue;
      if (latest == null || (bill.receivedAtMs ?? 0) > (latest.receivedAtMs ?? 0)) {
        latest = bill;
      }
    }
    return latest;
  }
}

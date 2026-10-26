import '../domain/enums.dart';
import '../domain/merchant_rule.dart';
import '../domain/money.dart';
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
    int? needsReviewCount,
  }) : _needsReviewCount = needsReviewCount;

  final List<Txn> transactions;
  final MonthlySummary summary;
  final MonthlySummary previousSummary;
  final List<CardMetrics> cards;
  final List<RecurringSeries> recurring;
  final List<Insight> insights;

  /// Messages the classifier flagged as phishing/fraud, newest first.
  final List<PhishingAlert> phishingAlerts;
  final List<Txn> needsReview;

  final int? _needsReviewCount;

  /// Total flagged rows, which may exceed the capped [needsReview] list (the UI
  /// shows at most 20 at a time but the badge can still say "27").
  int get needsReviewCount => _needsReviewCount ?? needsReview.length;

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

  /// This data seen from another month: only the two summaries change, so
  /// every figure derived from them (out, left, money in) follows the month.
  HomeData withSummaries(MonthlySummary month, MonthlySummary previous) =>
      HomeData(
        transactions: transactions,
        summary: month,
        previousSummary: previous,
        cards: cards,
        recurring: recurring,
        insights: insights,
        phishingAlerts: phishingAlerts,
        needsReview: needsReview,
        lastScanAt: lastScanAt,
        smsMessagesRead: smsMessagesRead,
        isDemo: isDemo,
        categories: categories,
        needsReviewCount: _needsReviewCount,
      );

  /// Months back from the current one to the oldest transaction (0 when all
  /// data is from this month).
  int monthsOfHistory(DateTime now) {
    if (transactions.isEmpty) return 0;
    var oldest = transactions.first.occurredAt;
    for (final txn in transactions) {
      if (txn.occurredAt.isBefore(oldest)) oldest = txn.occurredAt;
    }
    final months = (now.year - oldest.year) * 12 + now.month - oldest.month;
    return months < 0 ? 0 : months;
  }

  /// Money that actually left the accounts this month (spend + cash + card
  /// bill payments). "Left"/"Over" is measured against this, not against
  /// category spend alone.
  Paise get moneyOut => summary.moneyOut;

  /// True income minus money out. Negative means the user is down this month.
  Paise get left => summary.left;

  /// What is still unpaid across the latest card bills.
  Paise get stillDue => Paise(
    cards.fold<int>(0, (sum, card) => sum + card.billDuePaise),
  );

  /// Cards that still owe something on their latest bill.
  int get unpaidBillCount => cards.where((c) => c.billDuePaise > 0).length;

  /// False when no salary/interest credit was seen: the UI must say so rather
  /// than claim a savings rate.
  bool get hasTrueIncome => summary.hasTrueIncome;

  /// Refunds booked this month (reported separately from income).
  Paise get refunds => summary.refunds;

  /// Money-in by kind for the current month: salary/interest are true income,
  /// the rest (refund, cashback, cardPayment, walletLoad, redemption,
  /// selfTransfer, p2pReceive) are reported on their own line.
  Map<MoneyInKind, int> get moneyInByKind {
    final byKind = <MoneyInKind, int>{};
    for (final txn in transactions) {
      final kind = txn.moneyInKind;
      if (kind == MoneyInKind.none) continue;
      if (txn.occurredAt.isBefore(summary.monthStart)) continue;
      final start = summary.monthStart;
      if (!txn.occurredAt.isBefore(DateTime(start.year, start.month + 1))) {
        continue;
      }
      byKind.update(kind, (v) => v + txn.amountPaise, ifAbsent: () => txn.amountPaise);
    }
    return byKind;
  }

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

  /// Re-derives the whole ledger from the stored raw messages.
  ///
  /// Used when the parser rules or the schema change: an existing install must
  /// never keep showing numbers an older parser produced. User category
  /// overrides and learned merchant rules are preserved.
  Future<IngestResult> reparseAll();

  /// Removes one card the user (or an old parser) created by mistake.
  Future<void> deleteCard(String issuer, String last4);

  Future<void> assignCategory({
    required String txnKey,
    required String categoryName,
    required SpendCategoryKind kind,
  });

  /// Deletes a row the user says is not a transaction and stores a negative
  /// rule (sender + merchant + amount band) so a re-scan cannot add it back.
  Future<void> excludeTxn(String txnKey);

  /// Learned merchant rules, most used first. Backs the Settings "undo" list.
  Future<List<MerchantRule>> merchantRules();

  /// Deletes a learned rule; future alerts fall back to the bundled categoriser.
  Future<void> forgetMerchantRule(String signature);

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
    int? needsReviewCount,
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
          latestBill: _latestBillFor(
            card,
            bills,
            allowUnkeyed: cards.where((c) => c.issuer == card.issuer).length == 1,
          ),
          // A bill payment without a card mask can only be attributed when the
          // issuer has exactly one card; otherwise guessing would move money
          // between cards.
          attributeUnkeyedPayments:
              cards.where((c) => c.issuer == card.issuer).length == 1,
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
      needsReviewCount: needsReviewCount,
    );
  }

  /// A bill whose SMS printed no card mask (`issuer|`) belongs to the issuer's
  /// only card. With more than one card of that issuer it cannot be attributed.
  CardBillNotice? _latestBillFor(
    CardAccount card,
    List<CardBillNotice> bills, {
    bool allowUnkeyed = false,
  }) {
    CardBillNotice? latest;
    for (final bill in bills) {
      final keyed = bill.cardKey == card.key;
      final unkeyed = allowUnkeyed && bill.cardKey == '${card.issuer}|';
      if (!keyed && !unkeyed) continue;
      if (latest == null || (bill.receivedAtMs ?? 0) > (latest.receivedAtMs ?? 0)) {
        latest = bill;
      }
    }
    return latest;
  }
}

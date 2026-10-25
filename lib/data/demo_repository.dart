import 'dart:async';

import '../domain/enums.dart';
import '../domain/merchant_rule.dart';
import '../domain/transaction.dart';
import '../data/demo_data.dart';
import '../data/finance_repository.dart';
import '../engine/card_metrics.dart';
import '../engine/dedupe_engine.dart';
import '../engine/merchant_learning.dart';
import '../engine/review_queue.dart';

/// In-memory repository used by demo mode and by widget tests.
///
/// Demo mode is a first-class feature: it lets someone judge the product in ten
/// seconds without granting SMS access, and it is explicitly labelled everywhere.
///
/// It mirrors the SQLite repository's learning loop in memory: categorising a
/// row writes a merchant rule that applies to the rest of the demo ledger,
/// "not a transaction" removes the row and remembers the alert shape, and both
/// can be undone. That is what makes the flow testable without a device or a
/// database.
class DemoFinanceRepository implements FinanceRepository {
  DemoFinanceRepository({DateTime? now})
    : _dataset = DemoDataset(now: now ?? DateTime.now()),
      _now = now ?? DateTime.now() {
    _data = _build();
  }

  final DemoDataset _dataset;
  final DateTime _now;
  final HomeDataBuilder _builder = HomeDataBuilder();
  final List<CardAccount> _cards = [];
  late HomeData _data;

  final MerchantLearning _learning = const MerchantLearning();
  final ReviewQueue _reviewQueue = const ReviewQueue();

  /// Learned rules, keyed by merchant signature.
  final Map<String, MerchantRule> _rules = {};

  /// Negative rules (“never count this alert shape”).
  final Set<String> _excludedShapes = {};

  /// Rows removed one by one, including rows whose signature bands differ.
  final Set<String> _excludedKeys = {};

  @override
  bool get isDemo => true;

  HomeData _build() {
    if (_cards.isEmpty) _cards.addAll(_dataset.cards);

    final applied = <String, int>{};
    final transactions = <Txn>[];
    for (final base in _dataset.transactions) {
      if (_excludedKeys.contains(base.key)) continue;

      final override = _categoryOverrides[base.key];
      if (override != null) {
        transactions.add(
          base.copyWith(
            categoryName: override.name,
            categoryKind: override.kind,
            categorySource: CategorySource.user,
          ),
        );
        continue;
      }

      final rule = _learning.match(_rules, base);
      if (rule == null) {
        transactions.add(base);
        continue;
      }
      applied.update(rule.signature, (v) => v + 1, ifAbsent: () => 1);
      transactions.add(
        base.copyWith(
          categoryName: rule.categoryName,
          categoryKind: rule.categoryKind,
          categorySource: CategorySource.learned,
        ),
      );
    }

    // Demo `hits` is the number of rows the rule currently covers, so the
    // Settings list is meaningful without pretending a scanner ran.
    for (final entry in applied.entries) {
      final rule = _rules[entry.key];
      if (rule == null) continue;
      _rules[entry.key] = rule.copyWith(hits: entry.value);
    }

    final review = _reviewQueue.select(transactions);
    return _builder.build(
      transactions: _dedupe.mark(transactions),
      cards: _cards,
      bills: _dataset.bills,
      smsMessages: _dataset.sms,
      assessments: _dataset.assessments,
      categories: DemoDataset.categories,
      now: _now,
      isDemo: true,
      lastScanAt: _now.subtract(const Duration(minutes: 12)),
      smsRead: _dataset.sms.length,
      needsReview: review,
      needsReviewCount: _reviewQueue.count(transactions),
    );
  }

  final _dedupe = const DedupeEngine();
  final Map<String, ({String name, SpendCategoryKind kind})> _categoryOverrides = {};

  @override
  Future<HomeData> load() async => _data;

  @override
  Future<IngestResult> ingest() async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    // A rescan replays the demo inbox through the stored negative rules: a row
    // whose shape the user rejected is not booked again, exactly like
    // `excluded_shapes` in SQLite.
    for (final base in _dataset.transactions) {
      if (_excludedShapes.contains(_learning.exclusionFor(base))) {
        _excludedKeys.add(base.key);
      }
    }
    _data = _build();
    return IngestResult(
      smsRead: _dataset.sms.length,
      transactionsFound: _data.transactions.length,
      duplicatesMerged: 0,
      phishingFound: _dataset.assessments.where((a) => a.isPhishing).length,
    );
  }

  @override
  Future<IngestResult> reparseAll() async {
    // The demo dataset is generated, not parsed: rebuilding is the honest
    // equivalent and keeps the user's category overrides.
    _data = _build();
    return IngestResult(
      smsRead: _dataset.sms.length,
      transactionsFound: _data.transactions.length,
      duplicatesMerged: 0,
      phishingFound: _data.phishingAlerts.length,
    );
  }

  @override
  Future<void> deleteCard(String issuer, String last4) async {
    _cards.removeWhere((c) => c.issuer == issuer && c.last4 == last4);
    _data = _build();
  }

  @override
  Future<void> assignCategory({
    required String txnKey,
    required String categoryName,
    required SpendCategoryKind kind,
  }) async {
    _categoryOverrides[txnKey] = (name: categoryName, kind: kind);

    final base = _baseTxn(txnKey);
    if (base != null && _learning.shouldLearn(base, kind)) {
      final signature = _learning.signatureFor(base);
      if (signature != null) {
        final existing = _rules[signature];
        _rules[signature] = MerchantRule(
          signature: signature,
          categoryName: categoryName,
          categoryKind: kind,
          hits: existing?.hits ?? 0,
          sampleMerchant: base.merchant ?? existing?.sampleMerchant,
          createdAtMs: existing?.createdAtMs ?? _now.millisecondsSinceEpoch,
          lastUsedAtMs: existing?.lastUsedAtMs,
        );
      }
    }
    _data = _build();
  }

  @override
  Future<void> excludeTxn(String txnKey) async {
    final base = _baseTxn(txnKey);
    if (base == null) return;
    _excludedKeys.add(txnKey);
    _excludedShapes.add(_learning.exclusionFor(base));
    _data = _build();
  }

  @override
  Future<List<MerchantRule>> merchantRules() async {
    final rules = _rules.values.toList(growable: false)
      ..sort((a, b) => b.hits.compareTo(a.hits));
    return rules;
  }

  @override
  Future<void> forgetMerchantRule(String signature) async {
    _rules.remove(signature);
    _data = _build();
  }

  Txn? _baseTxn(String key) {
    for (final txn in _dataset.transactions) {
      if (txn.key == key) return txn;
    }
    return null;
  }

  @override
  Future<void> saveCard(CardAccount card) async {
    final index = _cards.indexWhere((c) => c.key == card.key);
    if (index >= 0) {
      _cards[index] = card;
    } else {
      _cards.add(card);
    }
    _data = _build();
  }

  @override
  Future<void> dismissInsight(String id) async {
    _dismissed.add(id);
    _data = _build();
  }

  final Set<String> _dismissed = {};

  @override
  Future<void> startDemo() async {}

  @override
  Future<void> exitDemo() async {}

  @override
  Future<void> clearAll() async {
    _categoryOverrides.clear();
    _rules.clear();
    _excludedShapes.clear();
    _excludedKeys.clear();
    _cards
      ..clear()
      ..addAll(_dataset.cards);
    _data = _build();
  }
}

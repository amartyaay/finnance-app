import 'dart:async';

import '../domain/enums.dart';
import '../data/demo_data.dart';
import '../data/finance_repository.dart';
import '../engine/card_metrics.dart';
import '../engine/dedupe_engine.dart';

/// In-memory repository used by demo mode and by widget tests.
///
/// Demo mode is a first-class feature: it lets someone judge the product in ten
/// seconds without granting SMS access, and it is explicitly labelled everywhere.
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

  @override
  bool get isDemo => true;

  HomeData _build() {
    if (_cards.isEmpty) _cards.addAll(_dataset.cards);
    final transactions = _dataset.transactions
        .map(
          (t) => _categoryOverrides.containsKey(t.key)
              ? t.copyWith(
                  categoryName: _categoryOverrides[t.key]!.name,
                  categoryKind: _categoryOverrides[t.key]!.kind,
                  categorySource: CategorySource.user,
                )
              : t,
        )
        .toList(growable: false);

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
      needsReview: const [],
    );
  }

  final _dedupe = const DedupeEngine();
  final Map<String, ({String name, SpendCategoryKind kind})> _categoryOverrides = {};

  @override
  Future<HomeData> load() async => _data;

  @override
  Future<IngestResult> ingest() async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    return IngestResult(
      smsRead: _dataset.sms.length,
      transactionsFound: _dataset.transactions.length,
      duplicatesMerged: 0,
      phishingFound: _dataset.assessments.where((a) => a.isPhishing).length,
    );
  }

  @override
  Future<void> assignCategory({
    required String txnKey,
    required String categoryName,
    required SpendCategoryKind kind,
  }) async {
    _categoryOverrides[txnKey] = (name: categoryName, kind: kind);
    _data = _build();
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
    _cards
      ..clear()
      ..addAll(_dataset.cards);
    _data = _build();
  }
}



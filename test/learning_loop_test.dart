// The learning loop and the review queue, without a device or a database.
//
// Covered:
//   * MerchantSignature — the normalisation contract for rule keys;
//   * ReviewQueue      — the three v8 review triggers, the 20-row cap, ordering;
//   * MerchantLearning — sender fallback, rule precedence, no overwriting a
//                        user's own choice;
//   * DemoFinanceRepository — learn / undo / "not a transaction" in memory;
//   * AppState         — the methods a Settings or detail-sheet button calls.

import 'package:finnance_app/data/demo_repository.dart';
import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/merchant_rule.dart';
import 'package:finnance_app/domain/merchant_signature.dart';
import 'package:finnance_app/domain/transaction.dart';
import 'package:finnance_app/engine/merchant_learning.dart';
import 'package:finnance_app/engine/review_queue.dart';
import 'package:finnance_app/services/sms_reader.dart';
import 'package:finnance_app/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime(2026, 6, 15, 12);

Txn _txn({
  String? key,
  required int atMs,
  int amountPaise = 300000,
  TxnKind kind = TxnKind.spend,
  Instrument instrument = Instrument.upi,
  String? sender = 'HDFCBK',
  String? merchant = 'Pluxee Meal',
  String? vpa,
  double confidence = 0.9,
  int? amountScore = 6,
  String? duplicateOf,
  CategorySource categorySource = CategorySource.rule,
}) {
  return Txn(
    key: key ?? 'k:$atMs',
    occurredAtMs: atMs,
    amountPaise: amountPaise,
    kind: kind,
    instrument: instrument,
    sender: sender,
    merchant: merchant,
    counterpartyVpa: vpa,
    confidence: confidence,
    amountScore: amountScore,
    isDuplicateOfKey: duplicateOf,
    categorySource: categorySource,
  );
}

class _GrantedGate implements SmsPermissionGate {
  const _GrantedGate();

  @override
  Future<bool> isGranted() async => true;

  @override
  Future<bool> request() async => true;

  @override
  Future<void> openSettings() async {}
}

void main() {
  group('MerchantSignature', () {
    test('lowercases, strips punctuation and keeps three tokens', () {
      expect(MerchantSignature.of('Pluxee Meal'), 'pluxee meal');
      expect(MerchantSignature.of('PLUXEE-MEAL 4411'), 'pluxee meal');
      expect(
        MerchantSignature.of('ICICI Prudential Asset Management Ltd'),
        'icici prudential asset',
      );
      expect(MerchantSignature.of('WWW.AMAZON'), 'www amazon');
      expect(MerchantSignature.of('Store42'), 'store');
      expect(MerchantSignature.of('  H&M  '), 'h&m');
    });

    test('falls back to the sender entity only when there is no merchant', () {
      expect(MerchantSignature.of('', senderEntity: 'HDFC Bank'), 'hdfc bank');
      expect(
        MerchantSignature.of(null, senderEntity: 'American Express'),
        'american express',
      );
      expect(MerchantSignature.of('Netflix', senderEntity: 'HDFC Bank'), 'netflix');
      expect(MerchantSignature.of(null), isNull);
      expect(MerchantSignature.of('  ###  '), isNull);
    });

    test('amount bands group the same alert shape', () {
      expect(MerchantSignature.amountBand(9999), 'lt100');
      expect(MerchantSignature.amountBand(10000), '100-500');
      expect(MerchantSignature.amountBand(50000), '500-1k');
      expect(MerchantSignature.amountBand(500000), '5k-10k');
      expect(MerchantSignature.amountBand(5000000), 'ge50k');
    });

    test('exclusion key ignores order numbers and small amount drift', () {
      final a = MerchantSignature.exclusion(
        sender: 'HDFCBK',
        merchant: 'Pluxee Meal 4411',
        amountPaise: 30000,
      );
      final b = MerchantSignature.exclusion(
        sender: 'HDFCBK',
        merchant: 'PLUXEE MEAL 9982',
        amountPaise: 39900,
      );
      expect(a, b);
      expect(a, contains('100-500'));
    });
  });

  group('ReviewQueue', () {
    const queue = ReviewQueue();

    test('flags low confidence', () {
      expect(
        queue.reviews(_txn(atMs: 1, confidence: 0.59)),
        isTrue,
      );
      expect(queue.reviews(_txn(atMs: 1, confidence: 0.6)), isFalse);
    });

    test('flags a weak amount candidate even at high confidence', () {
      expect(queue.reviews(_txn(atMs: 1, amountScore: 3)), isTrue);
      expect(queue.reviews(_txn(atMs: 1, amountScore: 4)), isFalse);
      // Rows written before v8 have no score: unknown is not "weak".
      expect(queue.reviews(_txn(atMs: 1, amountScore: null)), isFalse);
    });

    test('flags an anonymous spend, but not an anonymous transfer', () {
      expect(
        queue.reviews(_txn(atMs: 1, merchant: null, vpa: null)),
        isTrue,
      );
      expect(
        queue.reviews(
          _txn(atMs: 1, merchant: null, vpa: null, kind: TxnKind.transfer),
        ),
        isFalse,
      );
      expect(
        queue.reviews(_txn(atMs: 1, merchant: null, vpa: 'shop@ybl')),
        isFalse,
      );
    });

    test('never surfaces a duplicate row', () {
      expect(
        queue.reviews(_txn(atMs: 1, confidence: 0.2, duplicateOf: 'other')),
        isFalse,
      );
    });

    test('caps at 20, newest first, and still counts the whole queue', () {
      final rows = [
        for (var i = 0; i < 25; i++)
          _txn(key: 'low:$i', atMs: 1000 + i, confidence: 0.2),
      ];
      final selected = queue.select(rows);
      expect(selected, hasLength(20));
      expect(selected.first.occurredAtMs, 1024);
      expect(selected.last.occurredAtMs, 1005);
      expect(queue.count(rows), 25);
    });
  });

  group('MerchantLearning', () {
    const learning = MerchantLearning();
    final rule = MerchantRuleFixture.netflix;

    test('matches a merchant-keyed rule and counts the hit', () {
      final txn = _txn(atMs: 1, merchant: 'Netflix');
      final match = learning.match({rule.signature: rule}, txn);
      expect(match, isNotNull);
      expect(match!.withHit().hits, 1);
    });

    test('a sender-keyed rule does not rewrite an income row', () {
      final income = _txn(
        atMs: 1,
        merchant: null,
        kind: TxnKind.income,
        categorySource: CategorySource.rule,
      );
      final senderRule = MerchantRuleFixture.senderFallback;
      expect(learning.signatureFor(income), 'hdfc bank');
      expect(learning.match({senderRule.signature: senderRule}, income), isNull);
    });

    test('a user category is never overwritten by a later rule', () {
      final user = _txn(
        atMs: 1,
        merchant: 'Netflix',
        categorySource: CategorySource.user,
      );
      expect(learning.matchesSignature(user, 'netflix'), isFalse);
      expect(
        learning.matchesSignature(
          _txn(atMs: 1, merchant: 'Netflix'),
          'netflix',
        ),
        isTrue,
      );
    });

    test('does not learn a sender-wide "Other" rule', () {
      final anonymous = _txn(atMs: 1, merchant: null);
      expect(learning.shouldLearn(anonymous, SpendCategoryKind.other), isFalse);
      expect(learning.shouldLearn(anonymous, SpendCategoryKind.food), isTrue);
      expect(
        learning.shouldLearn(
          _txn(atMs: 1, merchant: 'Pluxee Meal'),
          SpendCategoryKind.food,
        ),
        isTrue,
      );
    });
  });

  group('DemoFinanceRepository learning', () {
    test('one correction recategorises the rest of the merchant', () async {
      final repo = DemoFinanceRepository(now: _now);
      final before = await repo.load();
      final seed = before.transactions.firstWhere(
        (t) => t.merchant == 'Netflix' && t.kind == TxnKind.spend,
      );
      final netflixRows = before.transactions
          .where((t) => t.merchant == 'Netflix')
          .length;
      expect(netflixRows, greaterThan(1));

      await repo.assignCategory(
        txnKey: seed.key,
        categoryName: 'Shopping',
        kind: SpendCategoryKind.shopping,
      );

      final after = await repo.load();
      final rows = after.transactions.where((t) => t.merchant == 'Netflix');
      expect(rows.every((t) => t.categoryName == 'Shopping'), isTrue);
      expect(
        rows.where((t) => t.categorySource == CategorySource.learned).length,
        netflixRows - 1,
      );

      final rules = await repo.merchantRules();
      final netflix = rules.singleWhere((r) => r.signature == 'netflix');
      expect(netflix.categoryName, 'Shopping');
      expect(netflix.hits, netflixRows - 1);
    });

    test('forgetting a rule reverts future rows, not the user choice', () async {
      final repo = DemoFinanceRepository(now: _now);
      final before = await repo.load();
      final seed = before.transactions.firstWhere(
        (t) => t.merchant == 'Netflix',
      );
      await repo.assignCategory(
        txnKey: seed.key,
        categoryName: 'Shopping',
        kind: SpendCategoryKind.shopping,
      );
      await repo.forgetMerchantRule('netflix');

      final after = await repo.load();
      expect(await repo.merchantRules(), isEmpty);
      final seedRow = after.transactions.firstWhere((t) => t.key == seed.key);
      expect(seedRow.categoryName, 'Shopping');
      final other = after.transactions.firstWhere(
        (t) => t.merchant == 'Netflix' && t.key != seed.key,
      );
      expect(other.categoryName, isNot('Shopping'));
    });

    test('"not a transaction" deletes the row and survives a rescan', () async {
      final repo = DemoFinanceRepository(now: _now);
      final before = await repo.load();
      final target = before.transactions.first;
      final count = before.transactions.length;

      await repo.excludeTxn(target.key);
      final after = await repo.load();
      expect(after.transactions.length, count - 1);
      expect(after.transactions.any((t) => t.key == target.key), isFalse);

      await repo.ingest();
      final rescanned = await repo.load();
      expect(rescanned.transactions.any((t) => t.key == target.key), isFalse);
      // A rescan also skips any other stored row with the rejected shape.
      expect(
        rescanned.transactions.length,
        lessThanOrEqualTo(after.transactions.length),
      );
    });
  });

  group('AppState actions', () {
    Future<AppState> readyState() async {
      final state = AppState(
        repository: DemoFinanceRepository(now: _now),
        permissions: const _GrantedGate(),
        now: () => _now,
      );
      await state.init();
      return state;
    }

    test('notATransaction removes the row from the surfaced data', () async {
      final state = await readyState();
      final target = state.data.transactions.first;
      final count = state.data.transactions.length;

      await state.notATransaction(target);

      expect(state.data.transactions.length, count - 1);
      expect(state.data.transactions.any((t) => t.key == target.key), isFalse);
    });

    test('setCategory teaches a rule that forgetMerchantRule removes', () async {
      final state = await readyState();
      final target = state.data.transactions.firstWhere(
        (t) => t.merchant == 'Netflix',
      );
      await state.setCategory(target, 'Travel', SpendCategoryKind.travel);

      final rules = await state.merchantRules();
      expect(rules.any((r) => r.signature == 'netflix'), isTrue);

      await state.forgetMerchantRule('netflix');
      expect(await state.merchantRules(), isEmpty);
    });

    test('the surfaced review queue is capped and counted', () async {
      final state = await readyState();
      final data = state.data;
      expect(data.needsReview.length, lessThanOrEqualTo(20));
      expect(data.needsReviewCount, greaterThanOrEqualTo(data.needsReview.length));
      for (var i = 1; i < data.needsReview.length; i++) {
        expect(
          data.needsReview[i - 1].occurredAtMs,
          greaterThanOrEqualTo(data.needsReview[i].occurredAtMs),
        );
      }
    });
  });
}

/// Shared rule fixtures.
class MerchantRuleFixture {
  const MerchantRuleFixture._();

  static const MerchantRule netflix = MerchantRule(
    signature: 'netflix',
    categoryName: 'Entertainment',
    categoryKind: SpendCategoryKind.entertainment,
  );

  static const MerchantRule senderFallback = MerchantRule(
    signature: 'hdfc bank',
    categoryName: 'Food & dining',
    categoryKind: SpendCategoryKind.food,
  );
}

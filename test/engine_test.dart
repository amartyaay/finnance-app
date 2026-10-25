// Focused unit tests for the pure-Dart analytics layer.
//
// Everything here is deterministic: `now` is passed in explicitly, so the tests
// do not depend on the wall clock, the device locale or the time zone.
//
// Covered:
//   * SummaryCalculator  — month boundaries, kind buckets, savingsRate,
//                          monthOverMonth, projection, duplicate exclusion.
//   * CardMetricsCalculator — utilisation maths, band thresholds, statement
//                          cycles, bill payments, refunds, headroomTo30.
//   * DedupeEngine       — bank+wallet merge, time window, same-sender rule.
//   * RecurringDetector  — monthly detection, amount stability, weekly cadence.
//   * money.dart         — Indian grouping, parsing, compact notation.

import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/money.dart';
import 'package:finnance_app/domain/transaction.dart';
import 'package:finnance_app/engine/card_metrics.dart';
import 'package:finnance_app/engine/dedupe_engine.dart';
import 'package:finnance_app/engine/monthly_summary.dart';
import 'package:finnance_app/engine/recurring_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unique keys: DedupeEngine groups by key, so two test rows must never collide.
int _keySeq = 0;

Txn _txn({
  required DateTime at,
  required int amountPaise,
  TxnKind kind = TxnKind.spend,
  Instrument instrument = Instrument.upi,
  String? sender,
  String? merchant,
  String? cardKey,
  String? last4,
  String? issuer,
  String? referenceId,
  int? availableLimitPaise,
  String? duplicateOfKey,
  String? categoryName,
  SpendCategoryKind categoryKind = SpendCategoryKind.other,
  TransferReason transferReason = TransferReason.none,
  bool needsReview = false,
}) {
  return Txn(
    key: 'test-key-${_keySeq++}',
    occurredAtMs: at.millisecondsSinceEpoch,
    amountPaise: amountPaise,
    kind: kind,
    instrument: instrument,
    sender: sender,
    merchant: merchant,
    cardKey: cardKey,
    last4: last4,
    issuer: issuer,
    referenceId: referenceId,
    availableLimitPaise: availableLimitPaise,
    isDuplicateOfKey: duplicateOfKey,
    categoryName: categoryName,
    categoryKind: categoryKind,
    transferReason: transferReason,
    needsReview: needsReview,
  );
}

void main() {
  // -------------------------------------------------------------------------
  // SummaryCalculator
  // -------------------------------------------------------------------------
  group('SummaryCalculator', () {
    final now = DateTime(2026, 3, 15, 12);

    test('month boundaries and kind buckets', () {
      final txns = <Txn>[
        // Previous month: only spend feeds previousSpendPaise.
        _txn(at: DateTime(2026, 2, 28, 23), amountPaise: 10000),
        // First and last day of the target month.
        _txn(at: DateTime(2026, 3, 1), amountPaise: 20000),
        _txn(at: DateTime(2026, 3, 31, 23, 59), amountPaise: 30000),
        // Next month: excluded from every bucket.
        _txn(at: DateTime(2026, 4, 1), amountPaise: 40000),
        _txn(
          at: DateTime(2026, 3, 10),
          amountPaise: 100000,
          kind: TxnKind.income,
          instrument: Instrument.bankAccount,
        ),
        _txn(
          at: DateTime(2026, 3, 12),
          amountPaise: 500000,
          kind: TxnKind.transfer,
          instrument: Instrument.creditCard,
        ),
        _txn(at: DateTime(2026, 3, 5), amountPaise: 5000, kind: TxnKind.cash),
      ];

      final summary = const SummaryCalculator().forMonth(txns, now);

      expect(summary.spendPaise, 50000); // 20,000 + 30,000
      expect(summary.incomePaise, 100000);
      expect(summary.transferPaise, 500000);
      expect(summary.cashPaise, 5000);
      expect(summary.txnCount, 5);
      expect(summary.previousSpendPaise, 10000);
      expect(summary.daysElapsed, 15);
      expect(summary.daysInMonth, 31);

      // Cash and transfers are cashflow, never consumption.
      expect(summary.cash, const Paise(5000));
      expect(summary.spend, const Paise(50000));
      expect(summary.net, const Paise(50000)); // income - spend

      expect(summary.dailySpend.length, 31);
      expect(summary.dailySpend[0], 20000); // 1 March
      expect(summary.dailySpend[30], 30000); // 31 March
      expect(summary.dailySpend.reduce((a, b) => a + b), 50000);
    });

    test('projection is linear over days elapsed', () {
      final txns = <Txn>[
        _txn(at: DateTime(2026, 3, 1), amountPaise: 150000),
      ];
      final summary = const SummaryCalculator().forMonth(txns, now);
      // Rs 1,500 by day 15 of 31 -> 1,500 / 15 * 31 = Rs 3,100.
      expect(summary.projectedSpendPaise, 310000);
      expect(summary.dailyAverage, const Paise(10000));
    });

    test('a completed month projects the actual total', () {
      final txns = <Txn>[
        _txn(at: DateTime(2026, 2, 2), amountPaise: 250000),
        _txn(at: DateTime(2026, 2, 20), amountPaise: 50000),
      ];
      final february = const SummaryCalculator()
          .forMonth(txns, now, monthOffset: -1);
      expect(february.monthStart, DateTime(2026, 2, 1));
      expect(february.daysElapsed, 28);
      expect(february.daysInMonth, 28);
      expect(february.projectedSpendPaise, 300000); // no over-projection
      expect(february.previousSpendPaise, 0);
    });

    test('duplicate rows never reach the totals', () {
      final txns = <Txn>[
        _txn(at: DateTime(2026, 3, 2), amountPaise: 99000),
        _txn(
          at: DateTime(2026, 3, 2),
          amountPaise: 99000,
          duplicateOfKey: 'test-key-0',
        ),
        _txn(
          at: DateTime(2026, 2, 2),
          amountPaise: 50000,
          duplicateOfKey: 'some-winner',
        ),
      ];
      final summary = const SummaryCalculator().forMonth(txns, now);
      expect(summary.spendPaise, 99000);
      expect(summary.txnCount, 1);
      expect(summary.previousSpendPaise, 0);
    });

    test('an unconfirmed (needsReview) row is not counted until reviewed', () {
      // ARCHITECTURE.md §7: a row the parser could not confirm must not move a
      // total in a hidden way. Proved defect: a ₹12,340 needsReview row was
      // added straight into spend.
      final txns = <Txn>[
        _txn(at: DateTime(2026, 3, 4), amountPaise: 500000, merchant: 'Amazon'),
        _txn(
          at: DateTime(2026, 3, 5),
          amountPaise: 1234000,
          needsReview: true,
        ),
      ];
      final summary = const SummaryCalculator().forMonth(txns, now);
      expect(summary.spendPaise, 500000);
      expect(summary.txnCount, 1);
    });

    test('savingsRate is net income over income, zero without income', () {
      final withIncome = const SummaryCalculator().forMonth(
        <Txn>[
          _txn(
            at: DateTime(2026, 3, 3),
            amountPaise: 1000000,
            kind: TxnKind.income,
            instrument: Instrument.bankAccount,
          ),
          _txn(at: DateTime(2026, 3, 4), amountPaise: 300000),
        ],
        now,
      );
      expect(withIncome.savingsRate, closeTo(0.7, 1e-9));

      final noIncome = const SummaryCalculator().forMonth(
        <Txn>[_txn(at: DateTime(2026, 3, 4), amountPaise: 300000)],
        now,
      );
      expect(noIncome.savingsRate, 0);
    });

    test('monthOverMonth compares against the previous calendar month', () {
      final txns = <Txn>[
        _txn(at: DateTime(2026, 2, 10), amountPaise: 500000),
        _txn(at: DateTime(2026, 2, 11), amountPaise: 500000),
        _txn(at: DateTime(2026, 3, 10), amountPaise: 1200000),
      ];
      final summary = const SummaryCalculator().forMonth(txns, now);
      // Previous month = Rs 10,000; this month = Rs 12,000 -> +20%.
      expect(summary.previousSpendPaise, 1000000);
      expect(summary.monthOverMonth, closeTo(0.2, 1e-9));

      final noHistory = const SummaryCalculator().forMonth(
        <Txn>[_txn(at: DateTime(2026, 3, 10), amountPaise: 1200000)],
        now,
      );
      expect(noHistory.monthOverMonth, 0);
    });

    test('categories carry count, share and previous-month delta', () {
      final txns = <Txn>[
        _txn(
          at: DateTime(2026, 3, 1),
          amountPaise: 30000,
          categoryName: 'Food & dining',
          categoryKind: SpendCategoryKind.food,
        ),
        _txn(
          at: DateTime(2026, 3, 2),
          amountPaise: 20000,
          categoryName: 'Food & dining',
          categoryKind: SpendCategoryKind.food,
        ),
        _txn(
          at: DateTime(2026, 3, 3),
          amountPaise: 10000,
          categoryName: 'Transport',
          categoryKind: SpendCategoryKind.transport,
        ),
        _txn(
          at: DateTime(2026, 2, 3),
          amountPaise: 40000,
          categoryName: 'Food & dining',
          categoryKind: SpendCategoryKind.food,
        ),
      ];
      final summary = const SummaryCalculator().forMonth(txns, now);
      final food = summary.categoryFor(SpendCategoryKind.food)!;

      expect(summary.byCategory.first.kind, SpendCategoryKind.food);
      expect(food.paise, 50000);
      expect(food.txnCount, 2);
      expect(food.share, closeTo(5 / 6, 1e-9));
      expect(food.previousPaise, 40000);
      expect(food.change, closeTo(0.25, 1e-9));
      expect(summary.categoryFor(SpendCategoryKind.health), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // CardMetricsCalculator
  // -------------------------------------------------------------------------
  group('CardMetricsCalculator', () {
    const calculator = CardMetricsCalculator();
    final now = DateTime(2026, 3, 15, 12);
    const limit = 10000000; // Rs 1,00,000

    const card = CardAccount(
      issuer: 'HDFC Bank',
      last4: '1234',
      creditLimitPaise: limit,
      statementDay: 12,
      dueDay: 2,
    );

    Txn cardSpend(int paise, {DateTime? at}) => _txn(
      at: at ?? DateTime(2026, 3, 14),
      amountPaise: paise,
      instrument: Instrument.creditCard,
      cardKey: card.key,
      last4: card.last4,
      issuer: card.issuer,
      merchant: 'AMAZON',
    );

    test('utilisation is outstanding over limit', () {
      final metrics = calculator.compute(
        card: card,
        transactions: <Txn>[cardSpend(2500000)],
        now: now,
      );
      expect(metrics.outstandingPaise, 2500000);
      expect(metrics.utilization, closeTo(0.25, 1e-9));
      expect(metrics.band, UtilizationBand.healthy);
      expect(metrics.availableLimitPaise, 7500000);
      expect(metrics.spentThisCyclePaise, 2500000);
      expect(metrics.txnCount, 1);
    });

    test('band thresholds at the documented boundaries', () {
      expect(calculator.bandFor(0.099, limit), UtilizationBand.excellent);
      expect(calculator.bandFor(0.10, limit), UtilizationBand.healthy);
      expect(calculator.bandFor(0.299, limit), UtilizationBand.healthy);
      expect(calculator.bandFor(0.30, limit), UtilizationBand.watch);
      expect(calculator.bandFor(0.499, limit), UtilizationBand.watch);
      expect(calculator.bandFor(0.50, limit), UtilizationBand.high);
      expect(calculator.bandFor(0.749, limit), UtilizationBand.high);
      expect(calculator.bandFor(0.75, limit), UtilizationBand.critical);
      expect(calculator.bandFor(null, limit), UtilizationBand.unknown);
      expect(calculator.bandFor(0.4, 0), UtilizationBand.unknown);
    });

    test('statement cycle starts on the statement day when it is past', () {
      final cycle = calculator.cycleFor(now, 5);
      expect(cycle.start, DateTime(2026, 3, 5));
      expect(cycle.end, DateTime(2026, 4, 5));

      final metrics = calculator.compute(
        card: const CardAccount(
          issuer: 'HDFC Bank',
          last4: '1234',
          creditLimitPaise: limit,
          statementDay: 5,
        ),
        transactions: <Txn>[cardSpend(2500000, at: DateTime(2026, 3, 6))],
        now: DateTime(2026, 3, 15),
      );
      expect(metrics.statementDate, DateTime(2026, 4, 5));
      expect(metrics.daysToStatement, 21);
      expect(metrics.spentThisCyclePaise, 2500000);
    });

    test('statement cycle starts last month when the day is still ahead', () {
      final cycle = calculator.cycleFor(now, 20);
      expect(cycle.start, DateTime(2026, 2, 20));
      expect(cycle.end, DateTime(2026, 3, 20));

      final metrics = calculator.compute(
        card: const CardAccount(
          issuer: 'HDFC Bank',
          last4: '1234',
          creditLimitPaise: limit,
          statementDay: 20,
        ),
        transactions: <Txn>[cardSpend(2500000, at: DateTime(2026, 3, 1))],
        now: DateTime(2026, 3, 15),
      );
      expect(metrics.statementDate, DateTime(2026, 3, 20));
      expect(metrics.daysToStatement, 5);
      expect(metrics.spentThisCyclePaise, 2500000);
    });

    test('a bill payment (transfer) reduces outstanding', () {
      final metrics = calculator.compute(
        card: card,
        transactions: <Txn>[
          cardSpend(2000000, at: DateTime(2026, 3, 13)),
          _txn(
            at: DateTime(2026, 3, 14),
            amountPaise: 500000,
            kind: TxnKind.transfer,
            instrument: Instrument.creditCard,
            cardKey: card.key,
            merchant: 'HDFC Bank',
            referenceId: 'BILLPAY1',
          ),
        ],
        now: now,
      );
      expect(metrics.outstandingPaise, 1500000);
      expect(metrics.utilization, closeTo(0.15, 1e-9));
      expect(metrics.band, UtilizationBand.healthy);
      expect(metrics.availableLimitPaise, 8500000);
    });

    test('a stale bill has no negative countdown and is not "due soon"', () {
      // Proved: a bill whose due date was more than a year old produced
      // daysToDue = -526 with dueSoon = true (the 12-iteration roll-forward
      // gave up). The next occurrence must be computed, then clamped at 0.
      final staleBill = CardBillNotice(
        cardKey: card.key,
        totalDuePaise: 7257085,
        minimumDuePaise: 1278600,
        dueDateMs: DateTime(2024, 5, 18).millisecondsSinceEpoch,
        statementDateMs: DateTime(2024, 4, 30).millisecondsSinceEpoch,
      );
      final metrics = calculator.compute(
        card: card,
        transactions: const <Txn>[],
        now: DateTime(2026, 10, 25),
        latestBill: staleBill,
      );

      // 18 Oct is behind us, so the next occurrence is 18 Nov 2026.
      expect(metrics.dueDate, DateTime(2026, 11, 18));
      expect(metrics.daysToDue, 24);
      expect(metrics.daysToDue!, greaterThanOrEqualTo(0));
      expect(metrics.dueSoon, isFalse);
    });

    test('dueSoon only fires for a genuinely imminent unpaid bill', () {
      CardMetrics withDue(DateTime due) => calculator.compute(
        card: card,
        transactions: const <Txn>[],
        now: now,
        latestBill: CardBillNotice(
          cardKey: card.key,
          totalDuePaise: 500000,
          dueDateMs: due.millisecondsSinceEpoch,
          statementDateMs: now.millisecondsSinceEpoch,
        ),
      );

      expect(withDue(DateTime(2026, 3, 18)).dueSoon, isTrue);
      expect(withDue(DateTime(2026, 4, 30)).dueSoon, isFalse);
    });

    test('a refund (income) reduces outstanding', () {
      final metrics = calculator.compute(
        card: card,
        transactions: <Txn>[
          cardSpend(1000000, at: DateTime(2026, 3, 13)),
          _txn(
            at: DateTime(2026, 3, 14),
            amountPaise: 300000,
            kind: TxnKind.income,
            instrument: Instrument.creditCard,
            cardKey: card.key,
            merchant: 'AMAZON',
          ),
        ],
        now: now,
      );
      expect(metrics.outstandingPaise, 700000);
      expect(metrics.utilization, closeTo(0.07, 1e-9));
      expect(metrics.band, UtilizationBand.excellent);
    });

    test('headroomTo30 is the gap to the 30% guideline', () {
      CardMetrics metricsWith(int outstanding) => calculator.compute(
        card: card,
        transactions: <Txn>[cardSpend(outstanding)],
        now: now,
      );

      // 30% of Rs 1,00,000 = Rs 30,000.
      expect(metricsWith(2000000).headroomTo30, const Paise(1000000));
      expect(metricsWith(3000000).headroomTo30, const Paise(0));
      expect(metricsWith(4000000).headroomTo30, const Paise(0));

      final noLimit = calculator.compute(
        card: const CardAccount(issuer: 'HDFC Bank', last4: '1234'),
        transactions: <Txn>[
          _txn(
            at: DateTime(2026, 3, 14),
            amountPaise: 100000,
            instrument: Instrument.creditCard,
            cardKey: 'HDFC Bank|1234',
          ),
        ],
        now: now,
      );
      expect(noLimit.headroomTo30, isNull);
      expect(noLimit.utilization, isNull);
      expect(noLimit.band, UtilizationBand.unknown);
    });
  });

  // -------------------------------------------------------------------------
  // DedupeEngine
  // -------------------------------------------------------------------------
  group('DedupeEngine', () {
    const engine = DedupeEngine();
    final t0 = DateTime(2026, 3, 15, 18, 30);

    test('bank and wallet alerts for the same payment merge', () {
      final bank = _txn(
        at: t0,
        amountPaise: 15000,
        sender: 'HDFCBK',
        instrument: Instrument.upi,
        merchant: 'Sree Krishna Stores',
        cardKey: 'HDFC Bank|4821',
        last4: '4821',
      );
      final wallet = _txn(
        at: t0.add(const Duration(seconds: 40)),
        amountPaise: 15000,
        sender: 'PHONEPE',
        instrument: Instrument.wallet,
        merchant: 'Sree Krishna Stores',
      );

      final marked = engine.mark(<Txn>[bank, wallet]);
      final duplicates = marked.where((t) => t.isDuplicateOfKey != null).toList();
      final survivors = marked.where((t) => t.isDuplicateOfKey == null).toList();

      expect(marked.length, 2);
      expect(duplicates.length, 1);
      expect(survivors.length, 1);
      // The richer row (card key + merchant + UPI) must win.
      expect(survivors.single.last4, '4821');
      expect(duplicates.single.isDuplicateOfKey, survivors.single.key);
    });

    test('two different payments of the same amount 20 minutes apart stay apart',
        () {
      final first = _txn(
        at: t0,
        amountPaise: 49900,
        sender: 'HDFCBK',
        merchant: 'Blue Tokai',
      );
      final second = _txn(
        at: t0.add(const Duration(minutes: 20)),
        amountPaise: 49900,
        sender: 'ICICIB',
        merchant: 'Third Wave Coffee',
      );

      final marked = engine.mark(<Txn>[first, second]);
      expect(marked.where((t) => t.isDuplicateOfKey != null), isEmpty);
    });

    test('same-sender duplicates are not merged', () {
      final first = _txn(
        at: t0,
        amountPaise: 25000,
        sender: 'HDFCBK',
        merchant: 'Cafe Coffee Day',
        cardKey: 'HDFC Bank|4821',
      );
      final second = _txn(
        at: t0.add(const Duration(seconds: 30)),
        amountPaise: 25000,
        sender: 'HDFCBK',
        merchant: 'Cafe Coffee Day',
        cardKey: 'HDFC Bank|4821',
      );

      final marked = engine.mark(<Txn>[first, second]);
      // A bank sending the same alert twice is a real double charge, not a
      // duplicate notification, so both rows must survive.
      expect(marked.where((t) => t.isDuplicateOfKey != null), isEmpty);
    });

    // ---- Card-bill payments (the double-count bug) --------------------------

    test('a bill payment is paired across 36 h and the issuer leg survives', () {
      // The real defect: the bank debit and the issuer's "payment received"
      // arrive hours apart, so the 180 s window never paired them, and both
      // rows counted in moneyOut. ₹3,772 became 754,400 paise.
      final bankLeg = _txn(
        at: t0,
        amountPaise: 377200,
        kind: TxnKind.transfer,
        transferReason: TransferReason.creditCardBill,
        instrument: Instrument.bankAccount,
        sender: 'HDFCBK',
        merchant: 'BILLDESK',
        last4: '4821',
      );
      final issuerLeg = _txn(
        at: t0.add(const Duration(hours: 36)),
        amountPaise: 377200,
        kind: TxnKind.transfer,
        transferReason: TransferReason.creditCardBill,
        instrument: Instrument.creditCard,
        sender: 'HDFCBK',
        cardKey: 'HDFC Bank|4821',
        last4: '4821',
        availableLimitPaise: 7330440,
      );

      final marked = engine.mark(<Txn>[bankLeg, issuerLeg]);
      final duplicates = marked.where((t) => t.isDuplicateOfKey != null).toList();
      final survivors = marked.where((t) => t.isDuplicateOfKey == null).toList();

      expect(marked.length, 2);
      expect(survivors.length, 1);
      expect(duplicates.single.key, bankLeg.key);
      expect(survivors.single.cardKey, 'HDFC Bank|4821');
      expect(survivors.single.transferReason, TransferReason.creditCardBill);

      // The guarantee that matters: one payment, one card-bill rupee.
      final summary = const SummaryCalculator().forMonth(marked, t0);
      expect(summary.cardBillPaymentPaise, 377200);
      expect(summary.moneyOutPaise, 377200);
    });

    test('an SBI debit and an Axis payment 47 s apart keep the Axis leg', () {
      // Proved wrong survivor: the SBI UPI debit won the group, the Axis
      // "payment received" (the only leg with a cardKey) was dropped, and the
      // ₹72,570.85 bill kept showing as due.
      final sbi = _txn(
        at: t0,
        amountPaise: 7257085,
        kind: TxnKind.transfer,
        instrument: Instrument.upi,
        sender: 'SBIUPI',
        merchant: 'PhonePe',
      );
      final axis = _txn(
        at: t0.add(const Duration(seconds: 47)),
        amountPaise: 7257085,
        kind: TxnKind.transfer,
        transferReason: TransferReason.creditCardBill,
        instrument: Instrument.creditCard,
        sender: 'AXISBK',
        cardKey: 'Axis Bank|5365',
        last4: '5365',
      );

      final marked = engine.mark(<Txn>[sbi, axis]);
      final duplicates = marked.where((t) => t.isDuplicateOfKey != null).toList();
      final survivors = marked.where((t) => t.isDuplicateOfKey == null).toList();

      expect(survivors.single.cardKey, 'Axis Bank|5365');
      expect(survivors.single.transferReason, TransferReason.creditCardBill);
      expect(duplicates.single.key, sbi.key);
    });

    test('bill legs more than 48 h apart are not one event', () {
      Txn leg(DateTime at) => _txn(
        at: at,
        amountPaise: 500000,
        kind: TxnKind.transfer,
        transferReason: TransferReason.creditCardBill,
        instrument: Instrument.creditCard,
        sender: 'HDFCBK',
        cardKey: 'HDFC Bank|1234',
      );

      final marked = engine.mark(<Txn>[
        leg(t0),
        leg(t0.add(const Duration(hours: 49))),
      ]);
      // The narrow bill rule is capped at 48 h; the general 180 s window is
      // deliberately untouched, so these stay two rows.
      expect(marked.where((t) => t.isDuplicateOfKey != null), isEmpty);
    });

    test('two bill legs with different reference ids are two payments', () {
      Txn leg(DateTime at, String ref) => _txn(
        at: at,
        amountPaise: 500000,
        kind: TxnKind.transfer,
        transferReason: TransferReason.creditCardBill,
        instrument: Instrument.creditCard,
        sender: 'HDFCBK',
        cardKey: 'HDFC Bank|1234',
        referenceId: ref,
      );

      final marked = engine.mark(<Txn>[
        leg(t0, 'REF000001'),
        leg(t0.add(const Duration(hours: 30)), 'REF000002'),
      ]);
      expect(marked.where((t) => t.isDuplicateOfKey != null), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // RecurringDetector
  // -------------------------------------------------------------------------
  group('RecurringDetector', () {
    const detector = RecurringDetector();

    Txn netflix(DateTime at, int paise) => _txn(
      at: at,
      amountPaise: paise,
      merchant: 'Netflix',
      categoryName: 'Entertainment',
      categoryKind: SpendCategoryKind.entertainment,
    );

    test('three monthly Netflix charges are detected', () {
      final series = detector.detect(<Txn>[
        netflix(DateTime(2026, 1, 5), 64900),
        netflix(DateTime(2026, 2, 5), 64900),
        netflix(DateTime(2026, 3, 5), 64900),
      ]);

      expect(series.length, 1);
      expect(series.single.merchant, 'Netflix');
      expect(series.single.occurrences.length, 3);
      expect(series.single.intervalDays, 30);
      expect(series.single.isAmountStable, isTrue);
      expect(series.single.nextExpected, DateTime(2026, 4, 4));
    });

    test('two occurrences are not enough', () {
      final series = detector.detect(<Txn>[
        netflix(DateTime(2026, 2, 5), 64900),
        netflix(DateTime(2026, 3, 5), 64900),
      ]);
      expect(series, isEmpty);
    });

    test('irregular amounts are rejected', () {
      // Rs 649, Rs 1,299, Rs 649: a 100% swing is not a subscription.
      final series = detector.detect(<Txn>[
        netflix(DateTime(2026, 1, 5), 64900),
        netflix(DateTime(2026, 2, 5), 129900),
        netflix(DateTime(2026, 3, 5), 64900),
      ]);
      expect(
        series,
        isEmpty,
        reason: 'amounts outside the tolerance band must not be a recurring '
            'series (isAmountStable=false alone is not a rejection)',
      );
    });

    test('weekly cadence is accepted', () {
      final series = detector.detect(<Txn>[
        netflix(DateTime(2026, 3, 1), 19900),
        netflix(DateTime(2026, 3, 8), 19900),
        netflix(DateTime(2026, 3, 15), 19900),
        netflix(DateTime(2026, 3, 22), 19900),
      ]);
      expect(series.length, 1);
      expect(series.single.intervalDays, 7);
      expect(series.single.isAmountStable, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // money.dart
  // -------------------------------------------------------------------------
  group('money', () {
    test('inr uses Indian lakh/crore grouping', () {
      expect(inr(const Paise(12990000)), '₹1,29,900');
      expect(inr(const Paise(12990050)), '₹1,29,900.50');
      expect(inr(const Paise(1000000000)), '₹1,00,00,000');
      expect(inr(const Paise(0)), '₹0');
      expect(inr(const Paise(12990050), forceDecimals: true), '₹1,29,900.50');
    });

    test('parseAmountToPaise handles Indian grouping and prefixes', () {
      expect(parseAmountToPaise('1,29,900.50'), const Paise(12990050));
      expect(parseAmountToPaise('Rs. 1,299'), const Paise(129900));
      expect(parseAmountToPaise('INR42.97'), const Paise(4297));
      expect(parseAmountToPaise('₹ 99'), const Paise(9900));
      expect(parseAmountToPaise('rs 0.50'), const Paise(50));
      expect(parseAmountToPaise('abc'), isNull);
      expect(parseAmountToPaise(''), isNull);
    });

    test('inrCompact abbreviates rupees', () {
      expect(inrCompact(const Paise(99900)), '₹999');
      expect(inrCompact(const Paise(450000)), '₹4.5k');
      expect(inrCompact(const Paise(1299000)), '₹13k');
      expect(inrCompact(const Paise(12990000)), '₹1.3L');
      expect(inrCompact(const Paise(1000000000)), '₹1Cr');
      expect(inrCompact(const Paise(-450000)), '-₹4.5k');
    });
  });
}

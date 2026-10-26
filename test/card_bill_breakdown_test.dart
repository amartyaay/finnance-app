// One card-bill payment, broken down by the card's own purchases.
import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/transaction.dart';
import 'package:finnance_app/engine/card_bill_breakdown.dart';
import 'package:flutter_test/flutter_test.dart';

Txn _t(
  String key,
  DateTime at,
  int paise,
  TxnKind kind, {
  String? card = 'Axis Bank|5365',
  TransferReason reason = TransferReason.none,
  String? category,
  SpendCategoryKind cat = SpendCategoryKind.other,
}) => Txn(
  key: key,
  occurredAtMs: at.millisecondsSinceEpoch,
  amountPaise: paise,
  kind: kind,
  instrument: Instrument.creditCard,
  cardKey: card,
  transferReason: reason,
  categoryName: category,
  categoryKind: cat,
);

void main() {
  test('groups the card purchases since the previous payment', () {
    final ledger = [
      _t(
        'old-pay',
        DateTime(2026, 6, 17),
        100000,
        TxnKind.transfer,
        reason: TransferReason.creditCardBill,
      ),
      _t(
        'before',
        DateTime(2026, 6, 10),
        99900,
        TxnKind.spend,
        category: 'Shopping',
      ),
      _t(
        'a',
        DateTime(2026, 6, 20),
        30000,
        TxnKind.spend,
        category: 'Food & dining',
        cat: SpendCategoryKind.food,
      ),
      _t(
        'b',
        DateTime(2026, 7, 1),
        20000,
        TxnKind.spend,
        category: 'Food & dining',
        cat: SpendCategoryKind.food,
      ),
      _t('c', DateTime(2026, 7, 5), 50000, TxnKind.spend, category: 'Shopping'),
      _t(
        'other-card',
        DateTime(2026, 7, 6),
        70000,
        TxnKind.spend,
        card: 'HDFC Bank|4821',
        category: 'Travel',
      ),
      _t(
        'pay',
        DateTime(2026, 7, 17),
        100000,
        TxnKind.transfer,
        reason: TransferReason.creditCardBill,
      ),
    ];
    final b = CardBillBreakdown.of(ledger.last, ledger)!;
    expect(b.from, DateTime(2026, 6, 17));
    expect(b.count, 3);
    expect(b.totalPaise, 100000);
    expect(
      [for (final r in b.byCategory) (r.name, r.paise)],
      [('Food & dining', 50000), ('Shopping', 50000)],
    );
  });

  test('a payment settles the latest card statement before it', () {
    final ledger = [
      _t(
        'jun',
        DateTime(2026, 6, 20),
        10000,
        TxnKind.spend,
        category: 'Shopping',
      ),
      _t(
        'jul-a',
        DateTime(2026, 7, 2),
        30000,
        TxnKind.spend,
        category: 'Shopping',
      ),
      _t(
        'jul-b',
        DateTime(2026, 7, 15, 9),
        20000,
        TxnKind.spend,
        category: 'Travel',
      ),
      _t(
        'after',
        DateTime(2026, 7, 16, 9),
        99900,
        TxnKind.spend,
        category: 'Shopping',
      ),
      _t(
        'pay',
        DateTime(2026, 7, 30),
        50000,
        TxnKind.transfer,
        reason: TransferReason.creditCardBill,
      ),
    ];
    CardBillNotice notice(DateTime d, int total) => CardBillNotice(
      cardKey: 'Axis Bank|5365',
      totalDuePaise: total,
      statementDateMs: d.millisecondsSinceEpoch,
    );
    final b = CardBillBreakdown.of(
      ledger.last,
      ledger,
      notices: [
        notice(DateTime(2026, 6, 15), 1),
        notice(DateTime(2026, 7, 15), 50000),
      ],
    )!;
    expect(b.byStatement, isTrue);
    expect(b.statementTotalPaise, 50000);
    expect(b.count, 3); // 20 Jun, 2 Jul, 15 Jul; not 16 Jul
    expect(b.totalPaise, 60000);
  });

  test('not a card bill: no breakdown', () {
    final spend = _t('x', DateTime(2026, 7, 1), 100, TxnKind.spend);
    expect(CardBillBreakdown.of(spend, [spend]), isNull);
  });
}

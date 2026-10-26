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

  test('not a card bill: no breakdown', () {
    final spend = _t('x', DateTime(2026, 7, 1), 100, TxnKind.spend);
    expect(CardBillBreakdown.of(spend, [spend]), isNull);
  });
}

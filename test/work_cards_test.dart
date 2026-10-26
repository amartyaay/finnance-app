// A corporate card's purchases are the employer's money.
import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/transaction.dart';
import 'package:finnance_app/engine/work_cards.dart';
import 'package:flutter_test/flutter_test.dart';

Txn _spend(String key, String card, String body) => Txn(
  key: key,
  occurredAtMs: DateTime(2026, 7, 14).millisecondsSinceEpoch,
  amountPaise: 11151000,
  kind: TxnKind.spend,
  instrument: Instrument.creditCard,
  cardKey: card,
  rawBody: body,
);

void main() {
  test('purchases on a card its issuer calls corporate leave personal spend', () {
    final out = const WorkCards().apply([
      _spend('hotel', 'American Express|1008', 'Alert: You have spent INR 111510 on your card at JW MARRIOTT'),
      _spend('flag', 'American Express|1008', "Alert: You've spent INR 500 on your AMEX Corp Card ** 1008 at ORIENTAL"),
      _spend('own', 'Axis Bank|5365', 'Spent INR 164 Axis Bank Card no. XX5365'),
    ]);
    expect(out.firstWhere((t) => t.key == 'hotel').kind, TxnKind.transfer);
    expect(out.firstWhere((t) => t.key == 'hotel').categoryName, 'Work card');
    expect(out.firstWhere((t) => t.key == 'own').kind, TxnKind.spend);
  });
}

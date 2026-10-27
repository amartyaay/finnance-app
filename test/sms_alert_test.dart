// The "Spent ₹X" notification an arriving SMS can raise is decided by the
// app's own parser: promotions with an amount never raise one.
import 'package:finnance_app/domain/sms_message.dart';
import 'package:finnance_app/services/sms/sms_alert.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/spam_corpus.dart';

SmsAlert? _decide(String sender, String body) => SmsAlert.decide(
  SmsMessage(
    id: 't',
    sender: sender,
    body: body,
    receivedAtMs: DateTime(2026, 10, 27, 11).millisecondsSinceEpoch,
  ),
);

void main() {
  test('the two promotions from the owner\'s phone raise nothing', () {
    expect(
      _decide(
        'JM-HDFCBN-P',
        'Celebrate Festive Treats with the Lifetime FREE HDFC Bank UPI RuPay '
            'Credit Card. Rs.500 benefits + up to 3% CashPoints: '
            'https://1.hdfc.bank.in/HDFCBK/s/BAg42JRO',
      ),
      isNull,
    );
    expect(
      _decide(
        'VD-PHRMSY-P',
        'Rs.50 expire tonight!: Save 25% on your medicine order + Get Rs.100 '
            'wallet credits. Code: EASYAIDX: https://1xp.io/PHRMSY/0GkXsP *TC PharmEasy',
      ),
      isNull,
    );
  });

  test('a real debit raises one, with the amount grouped Indian-style', () {
    final alert = _decide(
      'AX-SBIUPI-S',
      'Dear UPI user A/C X4642 debited by 105590.00 on date 17Jul26 trf to '
          'Swiggy Refno 829874253985 If not u? call-1800111109 -SBI',
    );
    expect(alert, isNotNull);
    expect(alert!.title, 'Spent ₹1,05,590');
  });

  test('nothing the spam corpus keeps out of the ledger raises one', () {
    final raised = [
      for (final f in spamCorpus)
        if (!f.countsTowardLedger && _decide(f.sender, f.body) != null) f.id,
    ];
    expect(raised, isEmpty);
  });
}

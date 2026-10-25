// Quick behavioural probe of the SMS pipeline, independent of Flutter.
// Run: dart run tool/parser_check.dart
import 'package:finnance_app/domain/sms_message.dart';
import 'package:finnance_app/services/sms/sender_registry.dart';
import 'package:finnance_app/services/sms/sms_classifier.dart';
import 'package:finnance_app/services/sms/transaction_extractor.dart';

final _cases = <({String sender, String body, String expect})>[
  (
    sender: 'VM-HDFCBK-T',
    body: 'Rs.250.00 debited from a/c XX4412 on 05-06-26 to Swiggy via UPI. '
        'UPI Ref 126038293410. Avl Bal Rs.42,180.55',
    expect: 'transaction amount=25000 upi Swiggy',
  ),
  (
    sender: 'VK-ICICIB-T',
    body: 'INR 8,999.00 spent on ICICI Bank Credit Card XX9077 on 07-Jun-26 at Croma. '
        'Avl Limit: INR 1,42,000.00',
    expect: 'transaction amount=899900 creditCard 9077 limit=14200000 Croma',
  ),
  (
    sender: 'VM-HDFCBK-T',
    body: '482913 is your OTP for txn of Rs.2,499 at Amazon on card XX4821. Do not share.',
    expect: 'informational, no transaction',
  ),
  (
    sender: 'VM-PHONEP-T',
    body: 'Rahul has requested money of Rs.500. Approve only if you know the person.',
    expect: 'informational',
  ),
  (
    sender: 'VM-SBIINB-T',
    body: 'Rs.5000 debited from A/c XX1234 and Rs.5000 credited to A/c XX5678 on 12Jun26',
    expect: 'transfer',
  ),
  (
    sender: 'VM-HDFCBK-T',
    body: 'Your salary of Rs 1,25,000.00 credited to account XX4412 on 01-Jun-26. '
        'Avl Bal Rs 1,40,000',
    expect: 'income 12500000',
  ),
  (
    sender: 'VK-AMAZON-T',
    body: 'Refund of Rs.499 for your Amazon order has been credited to your account.',
    expect: 'income 49900',
  ),
  (
    sender: 'VM-PAYTMB-T',
    body: 'Rs.2000 added to your Paytm Wallet via UPI. New balance Rs.2350.',
    expect: 'transfer walletLoad',
  ),
  (
    sender: 'VM-HDFCBK-T',
    body: 'Rs.5000 withdrawn from ATM at HDFC Bank Indiranagar on 12-06-26. '
        'Avl Bal Rs.30,000',
    expect: 'cash 500000 atm',
  ),
  (
    sender: 'VK-ICICIB-T',
    body: 'Payment of Rs.18,452.00 received on your ICICI Bank Credit Card XX9077. '
        'Thank you for your payment.',
    expect: 'transfer creditCardBill 1845200',
  ),
  (
    sender: 'AD-HDFCBK-P',
    body: 'Apply now! Get 5% cashback on HDFC Bank Credit Card. Offer ends soon. T&C apply.',
    expect: 'promo',
  ),
  (
    sender: 'AD-KYCVERIFY',
    body: 'Dear customer, your SBI account will be BLOCKED in 24 hrs. '
        'Update KYC: http://sbi-kyc-verify.xyz/login',
    expect: 'phishing',
  ),
  (
    sender: '+919845012233',
    body: 'Sir your parcel is held at customs. Pay Rs.250 to this UPI: rakesh@ybl',
    expect: 'phishing',
  ),
  (
    sender: 'VM-HDFCBK-T',
    body: 'Rs.035.43 debited from a/c XX4412 to NETFLIX. Avl Bal Rs.3,120.11',
    expect: 'transaction amount=3543',
  ),
  (
    sender: 'VM-HDFCBK-T',
    body: 'Rs 1,29,900 debited from a/c XX4412 on 03Jun26 to Croma. Avl Bal Rs 20,000',
    expect: 'transaction amount=12990000',
  ),
  (
    sender: 'VM-KOTAKB-T',
    body: 'Spent Rs.1,250.50 on Kotak Credit Card XX7788 at Swiggy. Avl bal Rs.48,000',
    expect: 'transaction creditCard 125050',
  ),
];

void main() {
  final classifier = SmsClassifier();
  final extractor = TransactionExtractor();
  final registry = const SenderRegistry();
  var pass = 0;

  for (final testCase in _cases) {
    final message = SmsMessage(
      id: 'probe',
      sender: testCase.sender,
      body: testCase.body,
      receivedAtMs: DateTime(2026, 6, 10, 12).millisecondsSinceEpoch,
    );
    final assessment = classifier.assess(message);
    final sender = registry.resolve(testCase.sender);
    final txn = assessment.isTransaction ? extractor.extract(message, sender) : null;

    final got = txn == null
        ? '${assessment.cls.name} (no transaction)'
        : 'transaction amount=${txn.amountPaise} ${txn.instrument.name} '
              '${txn.merchant ?? '-'} last4=${txn.last4 ?? '-'} '
              'reason=${txn.transferReason.name} kind=${txn.kind.name} '
              'limit=${txn.availableLimitPaise ?? '-'} conf=${txn.confidence.toStringAsFixed(2)}';

    // Loose check: the words the expectation cares about must appear.
    final expectWords = testCase.expect
        .replaceAll(RegExp(r'[(),]'), ' ')
        .split(' ')
        .where((w) => w.length > 2 && !w.contains('=')).map((w) => w.toLowerCase())
        .toList();
    final numberChecks = RegExp(r'(\d+)')
        .allMatches(testCase.expect)
        .map((m) => m.group(0)!)
        .toList();
    var ok = expectWords.every(got.toLowerCase().contains) &&
        numberChecks.every(got.contains);
    if (ok) pass++;

    print('${ok ? 'PASS' : 'FAIL'}  ${testCase.sender}  ${testCase.body.substring(0, 42)}…');
    if (!ok) {
      print('   expect: ${testCase.expect}');
      print('   got   : $got');
      print('   class : ${assessment.cls.name} ${assessment.score.toStringAsFixed(2)} '
          '${assessment.topSignals().join(' ')} trust=${sender.trust.name}');
    }
  }
  print('\n$pass/${_cases.length} probes pass');
}

// Scratch verification for the principal-engineer review. Delete after use.
import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/sms_message.dart';
import 'package:finnance_app/engine/card_metrics.dart';
import 'package:finnance_app/engine/dedupe_engine.dart';
import 'package:finnance_app/services/sms/sender_registry.dart';
import 'package:finnance_app/services/sms/sms_classifier.dart';
import 'package:finnance_app/services/sms/transaction_extractor.dart';

void main() {
  final classifier = SmsClassifier();
  final extractor = TransactionExtractor();
  final registry = const SenderRegistry();

  void show(String sender, String body) {
    final m = SmsMessage(id: 'x', sender: sender, body: body, receivedAtMs: 1750000000000);
    final a = classifier.assess(m);
    final s = registry.resolve(sender);
    final t = extractor.extract(m, s);
    print('--- $sender');
    print('class=${a.cls.name} score=${a.score.toStringAsFixed(2)} '
        'signals=${a.signals.map((e) => '${e.code}(${e.weight})').join(',')}');
    if (t == null) {
      print('txn=null');
    } else {
      print('txn kind=${t.kind.name} inst=${t.instrument.name} '
          'amount=${t.amountPaise} merchant=${t.merchant} last4=${t.last4} '
          'cardKey=${t.cardKey} needsReview=${t.needsReview}');
      final card = CardAccount(issuer: 'HDFC Bank', last4: '4821');
      if (t.cardKey == card.key) {
        final m = const CardMetricsCalculator().compute(
          card: card,
          transactions: [t],
          now: DateTime(2026, 5, 20),
        );
        print('PHANTOM CARD metrics: outstanding=${m.outstandingPaise} '
            'thisCycle=${m.spentThisCyclePaise} count=${m.txnCount} '
            'band=${m.band.name}');
      }
    }
  }

  // real-data-findings.md §C: the issuer's own KYC advisory, sampled as a false
  // phishing flag. Expected: informational/caution, never fraud.
  show(
    'AD-AIRBNK-S',
    'As per RBI guidelines,your A/c has been blocked due to KYC overdue. '
        'Update: https://i.airtel.in/AIRBNK/kyc',
  );
  // real inbox, genuine bank alert with "SMS BLOCK" footer.
  show(
    'AD-HDFCBK-S',
    'Spent Rs.638 On HDFC Bank Card 6859 At SWIGGY LIMITED On 2026-06-12:22:06:09.'
        'Not You? To Block+Reissue Call 18002586161/SMS BLOCK CC 6859 to 7308080808',
  );
  // OTP with "never share" (must stay informational).
  show(
    'AD-HDFCBK-T',
    '123456 is your OTP for service - Login request on HDFC Bank MyCards. '
        'Valid for 2 mins. Never share OTP @mycards',
  );
  // H07: bank-account debit paying a card bill.
  show(
    'VK-HDFCBK',
    'Rs.5,000.00 debited from your HDFC Bank A/c **4821 on 12-05-24 to BILLDESK '
        '(HDFC Bank Credit Card bill). Avl Bal Rs.7,340.55.',
  );
  // Plain bank-account UPI debit: does it fabricate a card?
  show(
    'VK-HDFCBK',
    'Rs.250.00 debited from your HDFC Bank A/c XX1234 on 12-05-24 to '
        'SWIGGY. Avl Bal Rs.7,340.55.',
  );

  // Dedupe loser marking.
  final a = SmsMessage(
    id: 'a',
    sender: 'VK-HDFCBK',
    body: 'Rs.408.00 debited from your HDFC Bank A/c XX1234 to PLUXEE. Avl Bal Rs.7340.55.',
    receivedAtMs: 1750000000000,
  );
  final b = SmsMessage(
    id: 'b',
    sender: 'VK-HDFCBK',
    body: 'Rs.408.00 debited from your HDFC Bank A/c XX1234 to PLUXEE. Avl Bal Rs.6932.55.',
    receivedAtMs: 1750000173000,
  );
  final txns = [
    extractor.extract(a, registry.resolve(a.sender))!,
    extractor.extract(b, registry.resolve(b.sender))!,
  ];
  final marked = const DedupeEngine().mark(txns);
  print('--- dedupe: ${marked.map((t) => '${t.key} dupOf=${t.isDuplicateOfKey}').join(' | ')}');
  print('kinds after dedupe: ${marked.map((t) => t.kind.name).join(',')}');
  print('SpendCategoryKind values: ${SpendCategoryKind.values.length}, '
      'TxnKind: ${TxnKind.values.length}');
}

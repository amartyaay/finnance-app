// Regressions found by the gold-set audit (tool/audit_accuracy.dart).
//
// Each case is a real template from the owner's inbox with the numbers and
// names changed. They run the same pipeline as the app: classifier → extractor
// → ledger admission → dedupe.
import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/sms_message.dart';
import 'package:finnance_app/domain/transaction.dart';
import 'package:finnance_app/engine/dedupe_engine.dart';
import 'package:finnance_app/engine/txn_guards.dart';
import 'package:finnance_app/services/sms/sender_registry.dart';
import 'package:finnance_app/services/sms/sms_classifier.dart';
import 'package:finnance_app/services/sms/transaction_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

final _classifier = SmsClassifier();
final _extractor = TransactionExtractor();
const _registry = SenderRegistry();
const _guards = TxnGuards();

int _t0 = DateTime(2026, 7, 1, 10).millisecondsSinceEpoch;
var _seq = 0;

SmsMessage _msg(String sender, String body, {int minutes = 0}) => SmsMessage(
  id: 'g${_seq++}',
  sender: sender,
  body: body,
  receivedAtMs: _t0 + minutes * 60 * 1000,
);

Txn? _parse(SmsMessage m) {
  if (!_classifier.assess(m).isTransaction) return null;
  return _extractor.extract(m, _registry.resolve(m.sender));
}

/// Rows the ledger would count.
List<Txn> _ledger(List<SmsMessage> messages) {
  final rows = [
    for (final m in messages) ?_parse(m),
  ].where(_guards.isCountable).toList();
  return const DedupeEngine()
      .mark(rows)
      .where((t) => t.isDuplicateOfKey == null)
      .toList();
}

void main() {
  group('missed spends', () {
    test('SBI debit-card POS alert (no verb) is a spend', () {
      final rows = _ledger([
        _msg('JX-ATMSBI-S',
            'Dear Customer, transaction number 617314255060 for Rs.331.45 by SBI Debit Card X7361 done at 99999999 on 22Jun26 at 20:08:27. Your updated available balance is Rs.16263.50. If not done by you, forward this SMS to 7400165218/ call 1800111109 to block card. GOI helpline for cyber fraud 1930.'),
      ]);
      expect(rows, hasLength(1));
      expect(rows.single.kind, TxnKind.spend);
      expect(rows.single.amountPaise, 33145);
    });

    test('SBI UPI "trf to <shop>" is spend at that shop, not a transfer', () {
      final rows = _ledger([
        _msg('JK-SBIUPI-S',
            'Dear UPI user A/C X4642 debited by 1003.45 on date 25Sep26 trf to ZEPTO Refno 023138726410 If not u? call-1800111109 for other services-18001234-SBI'),
      ]);
      expect(rows.single.kind, TxnKind.spend);
      expect(rows.single.merchant, 'ZEPTO');
    });

    test('a biller receipt with no bank alert counts once', () {
      final rows = _ledger([
        _msg('Airtel-S',
            'Recharge of INR 361.00 is successful for your Airtel Mobile on 02-07-2026 20:09, Transaction ID 98054502.Check your balance on Airtel App i.airtel.in/SerAIr .'),
      ]);
      expect(rows.single.kind, TxnKind.spend);
      expect(rows.single.amountPaise, 36100);
      expect(rows.single.sourceType, TxnSourceType.receipt);
    });

    test('Jio prints the price as the plan name', () {
      final rows = _ledger([
        _msg('JA-JioPay-S',
            'Recharge Successful ! Plan Name : 666.00 Jio Number : 9000000000 Validity - 70 Days Transaction ID : BR000CQOG3PP'),
      ]);
      expect(rows.single.amountPaise, 66600);
    });
  });

  group('never double count', () {
    test('a receipt is folded into the card alert for the same payment', () {
      final rows = _ledger([
        _msg('AD-HDFCBK-S',
            'Spent Rs.349 On HDFC Bank Card 6859 At JIOHOTSTAR On 2026-07-01:10:00:00.Not You? To Block+Reissue Call 18002586161'),
        _msg('VA-JIOHTT-S',
            'Yay! Super 3 Months is successfully activated on your JioHotstar account. Amount paid: Rs.349.00. Next billing date: 1st October, 2026',
            minutes: 2),
      ]);
      expect(rows, hasLength(1));
      expect(rows.single.sourceType, TxnSourceType.sms);
    });

    test('two orders from one merchant a day apart both survive', () {
      final rows = _ledger([
        _msg('VM-SWIGGY-S',
            'Payment Confirmed! Your Swiggy Order #241715088209620 of Rs. 417.0 was successfully paid on 01/07/2026 at 09:01 PM. Txn ID: 265822297000201.'),
        _msg('AD-HDFCBK-S',
            'Spent Rs.404 On HDFC Bank Card 6859 At SWIGGY FOOD On 2026-07-02:19:19:37.Not You? Call 18002586161',
            minutes: 22 * 60),
      ]);
      expect(rows, hasLength(2));
    });

    test('a fund-house unit confirmation is not a second SIP debit', () {
      final rows = _ledger([
        _msg('AD-HDFCBK-S',
            'PAYMENT ALERT! INR 3000.00 deducted from HDFC Bank A/C No 3619 towards HDFC MUTUAL FUND UMRN: HDFC2024316000002449'),
        _msg('AD-HDFCMF-S',
            'Your SIP Purchase in Folio 32680595/92 under HDFC Multi Cap Fund Regular Growth for Rs. 2,999.85 has been processed at the NAV of 18.78 for 159.736 units.',
            minutes: 600),
      ]);
      expect(rows, hasLength(1));
      expect(rows.single.amountPaise, 300000);
    });

    test('the same refund re-sent from a second header is one refund', () {
      const body =
          'Alert! Rs. 200 refunded by Swiggy BENGALURU IND on 18/AUG/2026 & adjusted against HDFC Bank Credit Card 6859 View updated balance here: https://1.hdfc.bank.in/HDFCBK/s/';
      final rows = _ledger([
        _msg('VD-HDFCBK-S', '${body}B47ekYVd'),
        _msg('VM-HDFCBK-S', '${body}Ny8q7vyk', minutes: 12),
      ]);
      expect(rows, hasLength(1));
    });

    test('debit at one bank + credit at another with one UPI ref is one self transfer', () {
      final rows = _ledger([
        _msg('AX-SBIUPI-S',
            'Dear UPI user A/C X4642 debited by 13000.00 on date 17Jul26 trf to Bank Account XXX Refno 649507747508 If not u? call-1800111109 for other services-18001234-SBI'),
        _msg('VM-HDFCBK-S',
            'Credit Alert! Rs.13000.00 credited to HDFC Bank A/c XX3619 on 17-07-26 from VPA 9000000000@axl (UPI 649507747508)',
            minutes: 80),
      ]);
      expect(rows, hasLength(1));
      expect(rows.single.kind, TxnKind.transfer);
    });
  });

  group('card bills: pair the two legs, never two payments', () {
    test('Axis ₹5,000 and HDFC ₹5,000 two hours apart stay two payments', () {
      final rows = _ledger([
        _msg('AX-AXISBK-S',
            'Payment of INR 5000.00 received towards your Axis Bank Credit Card XX5365 on 01-07-26.'),
        _msg('AD-HDFCBK-S',
            'DEAR HDFCBANK CARDMEMBER, PAYMENT OF Rs. 5000.00 RECEIVED TOWARDS YOUR CREDIT CARD ENDING WITH 6859 ON 01-07-2026.',
            minutes: 120),
      ]);
      expect(rows, hasLength(2));
    });

    test("HDFC's 'received' and next-day 'credited' notices are one payment", () {
      final rows = _ledger([
        _msg('AD-HDFCBK-S',
            'DEAR HDFCBANK CARDMEMBER, PAYMENT OF Rs. 5552.00 RECEIVED TOWARDS YOUR CREDIT CARD ENDING WITH 6859 ON 01-07-2026.'),
        _msg('VD-HDFCBK-S',
            'HDFC Bank Cardmember, Online Payment of Rs.5552 vide Ref# 123BX45L6O7Z890 was credited to your card ending 6859 on 02-07-2026.',
            minutes: 30 * 60),
      ]);
      expect(rows, hasLength(1));
    });

    test('two real ₹3,000 payments to one card a day apart stay two', () {
      final rows = _ledger([
        _msg('AD-HDFCBK-S',
            'DEAR HDFCBANK CARDMEMBER, PAYMENT OF Rs. 3000.00 RECEIVED TOWARDS YOUR CREDIT CARD ENDING WITH 6859 ON 01-07-2026.'),
        _msg('AD-HDFCBK-S',
            'DEAR HDFCBANK CARDMEMBER, PAYMENT OF Rs. 3000.00 RECEIVED TOWARDS YOUR CREDIT CARD ENDING WITH 6859 ON 02-07-2026.',
            minutes: 20 * 60),
      ]);
      expect(rows, hasLength(2));
    });
  });

  group('never count spam or restatements', () {
    test('a -P header never posts, whatever the copy says', () {
      final rows = _ledger([
        _msg('AV-650022-P',
            'Important Update: Your Prepaid bill payment of Rs.2249 was successful. You could have paid up to Rs.562 less with Airtel Axis Bank Credit Card.'),
      ]);
      expect(rows, isEmpty);
    });

    test('a card spend converted to EMI is not a new debit', () {
      final rows = _ledger([
        _msg('BP-HDFCBK-S',
            'HDFC Bank Cardmember, Txn of Rs.12685.00 at FLIPKART PAYMENTS GURGAON IND converted to 06 months EMI on 13/10/2026. Refer amort schedule sent to your registered email id.'),
      ]);
      expect(rows, isEmpty);
    });

    test('a terminated SIP is not an investment', () {
      final rows = _ledger([
        _msg('VA-KFINMF-S',
            'Your SIP request received in Folio-XXXXXXXX0941 with Motilal Oswal Mutual Fund for Rs.1000.00 vide Txn Ref No.587984829 is terminated due to 3 consecutive trxns failure.'),
      ]);
      expect(rows, isEmpty);
    });

    test('"trf to PhonePe" is never spend: the app is a pipe', () {
      final rows = _ledger([
        _msg('AX-SBIUPI-S',
            'Dear UPI user A/C X4642 debited by 72570.85 on date 17Jul26 trf to PhonePe Refno 829874253985 If not u? call-1800111109 for other services-18001234-SBI'),
      ]);
      expect(rows.single.kind, TxnKind.transfer);
      expect(rows.single.needsReview, isTrue);
    });

    test('broker payouts are redemptions, not income', () {
      final rows = _ledger([
        _msg('JK-SBIPSG-S',
            'Dear Customer, INR 99.17 credited to your A/c No XX4642 on 05/09/2026 through NEFT with UTR AXNH262480433942 by GR0WW INVEST TECH PVT LTD - DSCNBA'),
      ]);
      expect(rows.single.moneyInKind.isTrueIncome, isFalse);
    });

    test('SBI CBS "has credit for UPI/REVERSAL" is a refund', () {
      final rows = _ledger([
        _msg('JD-CBSSBI-S',
            'Your A/C XXXXX454642 has credit for UPI/REVERSAL/437397693549/2206 of Rs 595.00 on 25/06/26. Avl Bal Rs 15,612.55.-SBI'),
      ]);
      expect(rows.single.moneyInKind, MoneyInKind.refund);
      expect(rows.single.amountPaise, 59500);
    });
  });

  group('phishing precision', () {
    test("the issuer's own KYC reminder on its own domain is not phishing", () {
      final a = _classifier.assess(_msg('AX-AIRBNK-S',
          'As per RBI guidelines,your A/c will blocked today as KYC is due Update: https://i.airtel.in/AIRBNK/sbakyc Visit Airtel Payments Bank Outlet Call 180023400'));
      expect(a.cls, isNot(SmsClass.phishing));
    });

    test('a streaming advert is not phishing', () {
      final a = _classifier.assess(_msg('AX-ARTXTM-P',
          'India vs Pakistan - Ready to cheer? Watch Team India LIVE on Airtel Xstream Play. Get access now https://open.airtelxstream.in/Getit'));
      expect(a.cls, isNot(SmsClass.phishing));
    });

    test('a KYC block threat on a lookalike domain still is', () {
      final a = _classifier.assess(_msg('VM-SBIINB',
          'Dear customer your SBI account will be blocked today as KYC is due. Update now: http://sbi-kyc-update.top/verify'));
      expect(a.cls, SmsClass.phishing);
    });
  });
}

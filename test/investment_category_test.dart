// A SIP debit is an investment, not a generic transfer.
import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/sms_message.dart';
import 'package:finnance_app/services/categorizer.dart';
import 'package:finnance_app/services/sms/sender_registry.dart';
import 'package:finnance_app/services/sms/transaction_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an HDFC mandate debit to a fund house is Investments', () {
    final m = SmsMessage(
      id: 'x',
      sender: 'AX-HDFCBK-S',
      body: 'PAYMENT ALERT!\nINR 3000.00 deducted from HDFC Bank A/C No 3619 '
          'towards WhiteOak Capital Mutual Fund UMRN: HDFC0000000022785946',
      receivedAtMs: DateTime(2026, 10, 27, 13, 30).millisecondsSinceEpoch,
    );
    final t = TransactionExtractor().extract(
      m,
      const SenderRegistry().resolve(m.sender),
    )!;
    expect(t.transferReason, TransferReason.investment);
    expect(t.merchant, 'WhiteOak Capital Mutual Fund');
    final c = const Categorizer().categorize(
      t.merchant,
      kind: t.kind,
      transferReason: t.transferReason,
    );
    expect(c.kind, SpendCategoryKind.investments);
  });
}

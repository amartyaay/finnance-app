// The shipped on-device model: loads, matches the app's classes, and behaves
// sensibly on templates it must get right. Parity with the Python trainer is
// checked on real messages by tool/check_sms_model_parity.dart.
import 'dart:io';

import 'package:finnance_app/services/sms/sms_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final model = SmsModel.fromJson(File(SmsModel.assetPath).readAsStringSync());

  test('FNV-1a 32 matches the reference vectors', () {
    expect(SmsModel.fnv1a32(''), 0x811C9DC5);
    expect(SmsModel.fnv1a32('a'), 0xE40C292C);
    expect(SmsModel.fnv1a32('foobar'), 0xBF9CF968);
  });

  test('features mask digits and URLs and carry the DLT category', () {
    final f = SmsModel.features('VM-HDFCBK-S', 'Rs.2000 debited https://x.io/a');
    expect(f, containsAll(['w:rs', 'w:0', 'w:debited', 'w:__url__', 'dlt:S']));
    expect(f.any((x) => x.contains('2000')), isFalse);
  });

  test('a bank debit alert reads as money moved', () {
    final p = model.predict('JK-SBIUPI-S',
        'Dear UPI user A/C X4642 debited by 240.00 on date 12Oct26 trf to ZEPTO Refno 123456789012 If not u? call-1800111109 -SBI');
    expect(p.best, SmsModelClass.debit);
    expect(p.money, greaterThan(0.9));
  });

  test('an OTP and a loan offer do not', () {
    final otp = model.predict('JM-HDFCBK-S',
        'OTP is 400545 for txn of INR 417.00 at Swiggy on HDFC Bank card ending 6859. Do not share OTP for security reasons');
    expect(otp.money, lessThan(0.5));
    final promo = model.predict('VM-HDFCBN-P',
        'Exclusive: Limited Time Offer for You. Rs.50000 Loan on HDFC Bank Card at 1.67% p.m for you. T&C');
    expect(promo.best, SmsModelClass.promo);
  });
}

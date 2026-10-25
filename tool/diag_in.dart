import 'dart:convert';
import 'dart:io';
import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/sms_message.dart';
import 'package:finnance_app/services/sms/sender_registry.dart';
import 'package:finnance_app/services/sms/sms_classifier.dart';
import 'package:finnance_app/services/sms/transaction_extractor.dart';
void main(List<String> args) {
  final raw = jsonDecode(File(args.first).readAsStringSync()) as List<dynamic>;
  final c = SmsClassifier(); final e = TransactionExtractor(); const r = SenderRegistry();
  for (final item in raw) {
    final m = item as Map<String, dynamic>;
    final msg = SmsMessage(id: m['id'] as String, sender: m['sender'] as String, body: m['body'] as String, receivedAtMs: m['received_at'] as int);
    if (!c.assess(msg).isTransaction) continue;
    final t = e.extract(msg, r.resolve(msg.sender));
    if (t == null) continue;
    if (t.moneyInKind == MoneyInKind.none) continue;
    final body = (t.rawBody ?? '').replaceAll(RegExp(r'\s+'), ' ');
    print('${t.kind.name}/${t.moneyInKind.name} Rs${t.amountPaise / 100} | ${body.length > 95 ? body.substring(0, 95) : body}');
  }
}

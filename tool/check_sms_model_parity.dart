// Proves the shipped model in Dart is the model that was trained in Python:
// same features, same hashes, same probabilities, on real messages.
//
// Usage (after tool/train_sms_model.py, which writes .local/model_parity.json):
//   dart run tool/check_sms_model_parity.dart .local/inbox_full.json
import 'dart:convert';
import 'dart:io';

import 'package:finnance_app/services/sms/sms_model.dart';

void main(List<String> args) {
  final inbox = {
    for (final m in jsonDecode(File(args.first).readAsStringSync()) as List)
      (m as Map<String, dynamic>)['id'] as String: m,
  };
  final expected =
      jsonDecode(File('.local/model_parity.json').readAsStringSync()) as Map<String, dynamic>;
  final model = SmsModel.fromJson(File(SmsModel.assetPath).readAsStringSync());
  var worst = 0.0;
  var argmaxDiffer = 0;
  for (final entry in expected.entries) {
    final m = inbox[entry.key]!;
    final got = model.predict(m['sender'] as String, m['body'] as String).probabilities;
    final want = (entry.value as List).cast<num>();
    var bestWant = 0;
    for (var c = 0; c < got.length; c++) {
      final d = (got[c] - want[c]).abs();
      if (d > worst) worst = d;
      if (want[c] > want[bestWant]) bestWant = c;
    }
    if (SmsModelPrediction(got).best.index != bestWant) argmaxDiffer++;
  }
  stdout.writeln('parity on ${expected.length} real messages: '
      'max |Δp| ${worst.toStringAsExponential(2)}, argmax differs $argmaxDiffer');
  if (worst > 1e-6 || argmaxDiffer > 0) exitCode = 1;
}

// Replays a real inbox through the current parser, offline.
//
// Why: iterating on parsing rules against a phone is slow and needs the device
// plugged in. This takes a JSON export of `sms_messages` (see
// tool/export_inbox.py) and reports the same numbers tool/measure_inbox.py does,
// but against the *current* Dart code — so a rule change can be measured in
// seconds, in CI, with no device.
//
// Usage:
//   python tool/export_inbox.py <db> > inbox.json
//   dart run tool/replay_inbox.dart inbox.json
import 'dart:convert';
import 'dart:io';

import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/sms_message.dart';
import 'package:finnance_app/domain/transaction.dart';
import 'package:finnance_app/engine/dedupe_engine.dart';
import 'package:finnance_app/engine/txn_guards.dart';
import 'package:finnance_app/services/categorizer.dart';
import 'package:finnance_app/services/sms/sender_registry.dart';
import 'package:finnance_app/services/sms/sms_classifier.dart';
import 'package:finnance_app/services/sms/transaction_extractor.dart';

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'inbox.json';
  final raw = jsonDecode(File(path).readAsStringSync()) as List<dynamic>;

  final classifier = SmsClassifier();
  final extractor = TransactionExtractor();
  final registry = const SenderRegistry();
  final categorizer = const Categorizer();
  final guards = const TxnGuards();

  final classes = <String, int>{};
  final txns = <Txn>[];

  for (final item in raw) {
    final map = item as Map<String, dynamic>;
    final message = SmsMessage(
      id: map['id'] as String,
      sender: map['sender'] as String,
      body: map['body'] as String,
      receivedAtMs: map['received_at'] as int,
    );
    final assessment = classifier.assess(message);
    classes.update(assessment.cls.name, (v) => v + 1, ifAbsent: () => 1);
    if (!assessment.isTransaction) continue;
    final sender = registry.resolve(message.sender);
    final txn = extractor.extract(message, sender);
    if (txn == null) continue;
    final category = categorizer.categorize(
      txn.merchant,
      kind: txn.kind,
      transferReason: txn.transferReason,
    );
    txns.add(
      txn.copyWith(
        categoryName: category.name,
        categoryKind: category.kind,
        categorySource: CategorySource.rule,
      ),
    );
  }

  final admitted = txns.where(guards.isCountable).toList();
  final resolved = const DedupeEngine().mark(admitted);
  final counted = resolved.where((t) => t.isDuplicateOfKey == null).toList();

  final spend = counted.where((t) => t.kind == TxnKind.spend).toList();
  final spendTotal = spend.fold<int>(0, (sum, t) => sum + t.amountPaise);
  final other = spend.where((t) => t.categoryKind == SpendCategoryKind.other);
  final otherTotal = other.fold<int>(0, (sum, t) => sum + t.amountPaise);

  final byCategory = <String, int>{};
  for (final txn in spend) {
    byCategory.update(
      txn.categoryName ?? 'Other',
      (v) => v + txn.amountPaise,
      ifAbsent: () => txn.amountPaise,
    );
  }
  final categories = byCategory.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final otherRows = [...other]..sort((a, b) => b.amountPaise.compareTo(a.amountPaise));
  for (final txn in otherRows.take(8)) {
    final body = (txn.rawBody ?? '').replaceAll(RegExp(r'\s+'), ' ');
    stdout.writeln(
      'OTHER ₹${(txn.amountPaise / 100).toStringAsFixed(0).padLeft(8)}  '
      '${(txn.merchant ?? '-').padRight(22).substring(0, 22)} | ${body.length > 78 ? body.substring(0, 78) : body}',
    );
  }

  stdout
    ..writeln('messages: ${raw.length}')
    ..writeln('classes: ${classes.entries.map((e) => '${e.key}=${e.value}').join(', ')}')
    ..writeln('parsed: ${txns.length}   admitted: ${admitted.length}   '
        'duplicates merged: ${admitted.length - counted.length}   counted: ${counted.length}')
    ..writeln('spend: ${(spendTotal / 100).toStringAsFixed(0)}   '
        'other: ${(spendTotal == 0 ? 0 : otherTotal / spendTotal * 100).toStringAsFixed(1)}% of spend')
    ..writeln('--- spend by category ---');
  for (final entry in categories) {
    final share = spendTotal == 0 ? 0 : entry.value / spendTotal * 100;
    stdout.writeln(
      '${entry.key.padRight(20)} ₹${(entry.value / 100).toStringAsFixed(0).padLeft(10)}  '
      '${share.toStringAsFixed(1)}%',
    );
  }
}

// TEMPORARY diagnostic: dumps credit-card-bill legs and their pairing.
import 'dart:convert';
import 'dart:io';

import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/sms_message.dart';
import 'package:finnance_app/domain/transaction.dart';
import 'package:finnance_app/engine/dedupe_engine.dart';
import 'package:finnance_app/engine/txn_guards.dart';
import 'package:finnance_app/services/sms/sender_registry.dart';
import 'package:finnance_app/services/sms/sms_classifier.dart';
import 'package:finnance_app/services/sms/transaction_extractor.dart';

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'inbox.json';
  final raw = jsonDecode(File(path).readAsStringSync()) as List<dynamic>;
  final classifier = SmsClassifier();
  final extractor = TransactionExtractor();
  final registry = const SenderRegistry();
  final guards = const TxnGuards();

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
    if (!assessment.isTransaction) continue;
    final txn = extractor.extract(message, registry.resolve(message.sender));
    if (txn == null) continue;
    if (!guards.isCountable(txn)) continue;
    txns.add(txn);
  }
  final marked = const DedupeEngine().mark(txns);
  final counted = marked.where((t) => t.isDuplicateOfKey == null).toList();

  final bills =
      counted.where((t) => t.transferReason == TransferReason.creditCardBill).toList();
  bills.sort((a, b) => a.occurredAtMs.compareTo(b.occurredAtMs));
  var total = 0;
  stdout.writeln('cardBill rows counted: ${bills.length}');
  for (final t in bills) {
    total += t.amountPaise;
    final body = (t.rawBody ?? '').replaceAll(RegExp(r'\s+'), ' ');
    stdout.writeln(
      '${DateTime.fromMillisecondsSinceEpoch(t.occurredAtMs)}  '
      '₹${(t.amountPaise / 100).toStringAsFixed(2).padLeft(10)}  '
      '${t.sender}  cardKey=${t.cardKey} last4=${t.last4} issuer=${t.issuer} '
      'merchant=${t.merchant}\n    $body',
    );
  }
  stdout.writeln('sum counted cardBill: ₹${(total / 100).toStringAsFixed(2)}');

  // Group same-amount card-bill rows, regardless of gap.
  final byAmount = <int, List<Txn>>{};
  for (final t in bills) {
    byAmount.putIfAbsent(t.amountPaise, () => <Txn>[]).add(t);
  }
  stdout.writeln('\n--- same-amount groups (all gaps) ---');
  for (final entry in byAmount.entries) {
    if (entry.value.length < 2) continue;
    stdout.writeln('₹${(entry.key / 100).toStringAsFixed(2)} x${entry.value.length}');
    for (final t in entry.value) {
      final body = (t.rawBody ?? '').replaceAll(RegExp(r'\s+'), ' ');
      final gap = (t.occurredAtMs - entry.value.first.occurredAtMs) / 1000;
      stdout.writeln(
        '   +${gap.toStringAsFixed(0)}s ${t.sender} '
        'cardKey=${t.cardKey} last4=${t.last4} '
        '| ${body.length > 110 ? body.substring(0, 110) : body}',
      );
    }
  }

  // All duplicate merges, for reference, with the winner printed in full.
  stdout.writeln('\n--- duplicate merges ---');
  for (final t in marked.where((t) => t.isDuplicateOfKey != null)) {
    final winner = marked.firstWhere((w) => w.key == t.isDuplicateOfKey);
    final body = (t.rawBody ?? '').replaceAll(RegExp(r'\s+'), ' ');
    String row(Txn x) =>
        '${x.sender} reason=${x.transferReason.name} kind=${x.kind.name} '
        'cardKey=${x.cardKey} last4=${x.last4} merchant=${x.merchant} '
        'ref=${x.referenceId} limit=${x.availableLimitPaise} bal=${x.balanceAfterPaise}';
    stdout.writeln(
      '₹${(t.amountPaise / 100).toStringAsFixed(2)} '
      'gap=${((t.occurredAtMs - winner.occurredAtMs) / 1000).toStringAsFixed(0)}s\n'
      '  WINNER ${row(winner)}\n'
      '    ${(winner.rawBody ?? '').replaceAll(RegExp(r'\s+'), ' ')}\n'
      '  LOSER  ${row(t)}\n'
      '    ${body.length > 130 ? body.substring(0, 130) : body}',
    );
  }

  stdout.writeln('\n--- needsReview rows ---');
  for (final t in counted.where((t) => t.needsReview)) {
    final body = (t.rawBody ?? '').replaceAll(RegExp(r'\s+'), ' ');
    stdout.writeln(
      '₹${(t.amountPaise / 100).toStringAsFixed(2)} kind=${t.kind.name} '
      'cat=${t.categoryName} conf=${t.confidence.toStringAsFixed(2)} '
      '| ${body.length > 110 ? body.substring(0, 110) : body}',
    );
  }

  stdout.writeln('\n--- spend rows mentioning 12340 ---');
  for (final t in counted) {
    final body = t.rawBody ?? '';
    if (body.contains('12,340') || body.contains('12340')) {
      stdout.writeln(
        '₹${(t.amountPaise / 100).toStringAsFixed(2)} ${t.kind.name} '
        'review=${t.needsReview} | $body',
      );
    }
  }
}

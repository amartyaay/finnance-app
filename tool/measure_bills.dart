// Measures the **card-bill guarantee** on a replayed inbox, offline.
//
// The guarantee: one real card-bill payment produces exactly one counted
// `transfer/creditCardBill` row, and `sum(cardBillPaymentPaise)` equals the sum
// of the bills actually paid. The old `tool/measure_inbox.py` certified P2 with
// a 10-minute bucket and never compared a bill to its payment, so it reported
// zero duplicates while six HDFC payment pairs (₹44,497.59) were counted twice.
//
// Usage:
//   python tool/export_inbox.py <db> inbox.json
//   dart run tool/measure_bills.dart inbox.json
//
// Exits non-zero when a double count, a missing payment or a negative due
// countdown is found, so it can gate CI.
import 'dart:convert';
import 'dart:io';

import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/sms_message.dart';
import 'package:finnance_app/domain/transaction.dart';
import 'package:finnance_app/engine/card_metrics.dart';
import 'package:finnance_app/engine/dedupe_engine.dart';
import 'package:finnance_app/engine/txn_guards.dart';
import 'package:finnance_app/services/sms/sender_registry.dart';
import 'package:finnance_app/services/sms/sms_classifier.dart';
import 'package:finnance_app/services/sms/transaction_extractor.dart';

String _rs(int paise) =>
    'Rs ${(paise / 100).toStringAsFixed(2)}';

String _date(DateTime at) =>
    '${at.year}-${at.month.toString().padLeft(2, '0')}-'
    '${at.day.toString().padLeft(2, '0')}';

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'inbox.json';
  final raw = jsonDecode(File(path).readAsStringSync()) as List<dynamic>;

  final classifier = SmsClassifier();
  final extractor = TransactionExtractor();
  const registry = SenderRegistry();
  const guards = TxnGuards();
  final now = args.length > 1
      ? DateTime.parse(args[1])
      : DateTime.fromMillisecondsSinceEpoch(
          raw
              .map((item) => (item as Map<String, dynamic>)['received_at'] as int)
              .fold<int>(0, (a, b) => a > b ? a : b),
        );

  final txns = <Txn>[];
  final notices = <CardBillNotice>[];
  final noticeKeys = <String>{};
  for (final item in raw) {
    final map = item as Map<String, dynamic>;
    final message = SmsMessage(
      id: map['id'] as String,
      sender: map['sender'] as String,
      body: map['body'] as String,
      receivedAtMs: map['received_at'] as int,
    );
    final assessment = classifier.assess(message);
    if (assessment.isTransaction) {
      final txn = extractor.extract(message, registry.resolve(message.sender));
      if (txn != null && guards.isCountable(txn)) txns.add(txn);
    }
    final bill = extractor.billNotice(message, registry.resolve(message.sender));
    if (bill != null) {
      // One statement, one notice (same rule as the `card_bills` unique index).
      final key = '${bill.cardKey}|${bill.totalDuePaise}|${bill.dueDateMs}';
      if (noticeKeys.add(key)) notices.add(bill);
    }
  }

  final marked = const DedupeEngine().mark(txns);
  final counted = marked.where((t) => t.isDuplicateOfKey == null).toList();
  final failures = <String>[];

  // ---------------------------------------------------------------------
  // 1. One row per card-bill event.
  // ---------------------------------------------------------------------
  final countedBillRows = counted
      .where((t) => t.transferReason == TransferReason.creditCardBill)
      .toList();
  final countedBillSum = countedBillRows.fold<int>(
    0,
    (sum, t) => sum + t.amountPaise,
  );

  final byAmount = <int, List<Txn>>{};
  for (final txn in marked) {
    byAmount.putIfAbsent(txn.amountPaise, () => <Txn>[]).add(txn);
  }
  final events = <List<Txn>>[];
  for (final rows in byAmount.values) {
    final sorted = [...rows]..sort((a, b) => a.occurredAtMs.compareTo(b.occurredAtMs));
    var cluster = <Txn>[];
    for (final txn in sorted) {
      if (cluster.isNotEmpty &&
          txn.occurredAtMs - cluster.last.occurredAtMs >
              DedupeEngine.billWindowSeconds * 1000) {
        if (cluster.any(
          (t) => t.transferReason == TransferReason.creditCardBill,
        )) {
          events.add(cluster);
        }
        cluster = <Txn>[];
      }
      cluster.add(txn);
    }
    if (cluster.any((t) => t.transferReason == TransferReason.creditCardBill)) {
      events.add(cluster);
    }
  }

  var doubleCounted = 0;
  var missing = 0;
  var paidBillSum = 0;
  stdout.writeln('== Card-bill payment events (same amount, <= 48 h) ==');
  for (final event in events) {
    final amount = event.first.amountPaise;
    paidBillSum += amount;
    final countedBillAmount = event
            .where(
              (t) =>
                  t.isDuplicateOfKey == null &&
                  t.transferReason == TransferReason.creditCardBill,
            )
            .length *
        amount;
    final extra = countedBillAmount - amount;
    if (extra > 0) {
      doubleCounted += extra;
      failures.add('double count ${_rs(extra)}');
    } else if (extra < 0) {
      missing += -extra;
      failures.add('missing payment ${_rs(-extra)}');
    }
    final flag = extra == 0
        ? 'ok'
        : extra > 0
        ? 'DOUBLE-COUNTED ${_rs(extra)}'
        : 'MISSING ${_rs(-extra)}';
    stdout.writeln(
      '  ${_date(event.first.occurredAt)}  ${_rs(amount).padLeft(13)}  '
      'rows=${event.length} counted=$countedBillAmount  $flag',
    );
    for (final txn in event) {
      final body = (txn.rawBody ?? '').replaceAll(RegExp(r'\s+'), ' ');
      stdout.writeln(
        '      ${txn.isDuplicateOfKey == null ? 'COUNT' : 'dup  '} '
        '${txn.transferReason.name.padRight(14)} card=${txn.cardKey} '
        '${body.length > 74 ? '${body.substring(0, 74)}...' : body}',
      );
    }
  }

  stdout
    ..writeln()
    ..writeln('card-bill rows counted : ${countedBillRows.length}')
    ..writeln('cardBillPaymentPaise    : ${_rs(countedBillSum)}')
    ..writeln('distinct payment events : ${events.length}')
    ..writeln('sum of paid bills       : ${_rs(paidBillSum)}')
    ..writeln('double-counted          : ${_rs(doubleCounted)}')
    ..writeln('payments missing        : ${_rs(missing)}');

  // ---------------------------------------------------------------------
  // 2. Every bill that has a matching counted payment must not be due.
  // ---------------------------------------------------------------------
  stdout.writeln();
  stdout.writeln('== Bills vs counted payments ==');
  final sortedNotices = [...notices]
    ..sort((a, b) => (a.statementDateMs ?? 0).compareTo(b.statementDateMs ?? 0));
  for (final bill in sortedNotices) {
    final issuer = bill.cardKey.split('|').first;
    final statement = bill.statementDateMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(bill.statementDateMs!);
    final due = bill.dueDate;
    bool inWindow(Txn txn) {
      // Payments can land just before the statement SMS is generated; allow a
      // 45-day lead and a month after the due date.
      final earliest = (statement ?? txn.occurredAt)
          .subtract(const Duration(days: 45))
          .millisecondsSinceEpoch;
      final latest = (due ?? txn.occurredAt)
          .add(const Duration(days: 30))
          .millisecondsSinceEpoch;
      return txn.occurredAtMs >= earliest && txn.occurredAtMs <= latest;
    }

    bool sameBill(Txn txn) {
      if (txn.amountPaise != bill.totalDuePaise) return false;
      final sameCard = txn.cardKey == bill.cardKey;
      final unkeyed = txn.cardKey == null && txn.issuer == issuer;
      return (sameCard || unkeyed) && inWindow(txn);
    }

    final payment = countedBillRows.where(sameBill).firstOrNull;
    // A payment that the dedupe engine swallowed is exactly the defect: the
    // bill was paid, the row exists, but it is not counted and the bill renders
    // as due.
    final swallowed = marked
        .where(
          (t) =>
              t.isDuplicateOfKey != null &&
              t.transferReason == TransferReason.creditCardBill &&
              sameBill(t),
        )
        .firstOrNull;

    final state = payment != null
        ? 'paid'
        : swallowed != null
        ? 'DUE (payment swallowed by dedupe)'
        : 'no matching payment in inbox';
    if (swallowed != null) {
      failures.add(
        'paid bill ${_rs(bill.totalDuePaise)} rendered due (${bill.cardKey})',
      );
    }
    stdout.writeln(
      '  ${bill.cardKey.padRight(20)} ${_rs(bill.totalDuePaise).padLeft(13)}  '
      'stmt=${statement == null ? '-' : _date(statement)} '
      'due=${due == null ? '-' : _date(due)}  -> $state'
      '${payment == null ? '' : ' on ${_date(payment.occurredAt)}'}',
    );
  }

  // ---------------------------------------------------------------------
  // 3. The Cards screen view: latest statement, unpaid amount, countdown.
  // ---------------------------------------------------------------------
  stdout.writeln();
  stdout.writeln('== Cards (latest statement) ==');
  final cardsByKey = <String, CardAccount>{};
  for (final notice in notices) {
    final parts = notice.cardKey.split('|');
    if (parts.length != 2 || parts[1].isEmpty) continue;
    final statement = notice.statementDateMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(notice.statementDateMs!);
    cardsByKey.putIfAbsent(
      notice.cardKey,
      () => CardAccount(
        issuer: parts[0],
        last4: parts[1],
        statementDay: statement?.day,
        dueDay: notice.dueDate?.day,
      ),
    );
  }
  var totalDue = 0;
  var dueSoonCount = 0;
  for (final card in cardsByKey.values) {
    CardBillNotice? latest;
    for (final notice in notices) {
      if (notice.cardKey != card.key) continue;
      if (latest == null ||
          (notice.statementDateMs ?? notice.receivedAtMs ?? 0) >
              (latest.statementDateMs ?? latest.receivedAtMs ?? 0)) {
        latest = notice;
      }
    }
    final metrics = const CardMetricsCalculator().compute(
      card: card,
      transactions: counted,
      now: now,
      latestBill: latest,
    );
    totalDue += metrics.billDuePaise;
    if (metrics.dueSoon) dueSoonCount++;
    if ((metrics.daysToDue ?? 0) < 0) {
      failures.add('negative daysToDue ${metrics.daysToDue}');
    }
    stdout.writeln(
      '  ${card.key.padRight(20)} total=${_rs(metrics.totalDuePaise).padLeft(13)} '
      'unpaid=${_rs(metrics.billDuePaise).padLeft(13)} '
      'paid=${metrics.billIsPaid} daysToDue=${metrics.daysToDue} '
      'dueSoon=${metrics.dueSoon}',
    );
  }
  stdout
    ..writeln('  unpaid across latest bills: ${_rs(totalDue)}')
    ..writeln('  dueSoon cards             : $dueSoonCount');

  // ---------------------------------------------------------------------
  // 4. Result
  // ---------------------------------------------------------------------
  stdout.writeln();
  if (failures.isEmpty) {
    stdout.writeln('PASS: one counted row per card-bill event; no unpaid bill '
        'with a matching payment; no negative countdown.');
  } else {
    stdout.writeln('FAIL: ${failures.join('; ')}');
    exitCode = 1;
  }
}

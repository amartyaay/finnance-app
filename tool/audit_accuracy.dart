// Scores the current parser against the hand-labelled gold set.
//
// Why: replay_inbox.dart says what the parser *does*; this says whether it is
// *right*. The gold labels (docs/eval/gold-labelling.md) were written by reading
// each message, never by running the parser, so agreement here is evidence.
//
// Usage:
//   dart run tool/audit_accuracy.dart .local/inbox.json .local/gold [--list]
//
// Prints ids and reasons only — never message bodies — so the report can be
// pasted into an issue. `--list` adds every disagreement (ids only).
// `--show id,id` prints those messages in full, for local debugging only.
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

/// The app books every inflow as `income` and says what it really is in
/// `moneyInKind`; only salary/interest/other-income is income to the user.
TxnKind effectiveKind(Txn t) {
  if (t.kind == TxnKind.income && !t.moneyInKind.isTrueIncome) {
    return TxnKind.transfer;
  }
  return t.kind;
}

class Gold {
  Gold(Map<String, dynamic> j)
    : id = j['id'] as String,
      label = j['label'] as String,
      kind = j['kind'] as String?,
      amountPaise = j['amount'] == null
          ? null
          : ((j['amount'] as num) * 100).round(),
      dupOf = j['dup_of'] as String?;

  final String id;
  final String label;
  final String? kind;
  final int? amountPaise;
  final String? dupOf;

  bool get movesMoney => label == 'debit' || label == 'credit';

  /// What the app should call this row, in its own vocabulary.
  TxnKind? get expectedKind {
    if (!movesMoney) return null;
    if (label == 'debit') {
      return switch (kind) {
        'spend' => TxnKind.spend,
        'cash' => TxnKind.cash,
        _ => TxnKind.transfer, // p2p, self, card bill, investment, EMI
      };
    }
    return switch (kind) {
      'salary' || 'interest' => TxnKind.income,
      _ => TxnKind.transfer,
    };
  }
}

String? _flag(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

void main(List<String> args) {
  final inboxPath = args.isNotEmpty ? args[0] : '.local/inbox.json';
  final goldDir = args.length > 1 && !args[1].startsWith('--')
      ? args[1]
      : '.local/gold';
  final listAll = args.contains('--list');
  final jsonOut = _flag(args, '--json');
  final show = (_flag(args, '--show') ?? '').split(',').where((s) => s.isNotEmpty).toSet();

  final gold = <String, Gold>{};
  for (final file in Directory(goldDir).listSync().whereType<File>()) {
    if (!RegExp(r'labels_\d+\.jsonl$').hasMatch(file.path)) continue;
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final g = Gold(jsonDecode(line) as Map<String, dynamic>);
      gold[g.id] = g;
    }
  }

  // Root of each duplicate chain: one money movement, one root.
  String root(String id) {
    var current = id;
    final seen = <String>{};
    while (gold[current]?.dupOf != null && seen.add(current)) {
      current = gold[current]!.dupOf!;
    }
    return current;
  }

  final raw = jsonDecode(File(inboxPath).readAsStringSync()) as List<dynamic>;
  final classifier = SmsClassifier();
  final extractor = TransactionExtractor();
  const registry = SenderRegistry();
  const categorizer = Categorizer();
  const guards = TxnGuards();

  final classOf = <String, SmsClass>{};
  final parsed = <Txn>[];
  final msgOfKey = <String, String>{};
  final collapsedByKey = <String>[];
  for (final item in raw) {
    final map = item as Map<String, dynamic>;
    final id = map['id'] as String;
    final message = SmsMessage(
      id: id,
      sender: map['sender'] as String,
      body: map['body'] as String,
      receivedAtMs: map['received_at'] as int,
    );
    final assessment = classifier.assess(message);
    classOf[id] = assessment.cls;
    final txn = assessment.isTransaction
        ? extractor.extract(message, registry.resolve(message.sender))
        : null;
    if (show.contains(id)) {
      final g = gold[id];
      stdout.writeln('--- $id [${message.sender}] gold=${g?.label}/${g?.kind} '
          '${g?.amountPaise} dup=${g?.dupOf} | app=${assessment.cls.name} '
          '${txn == null ? '' : '${txn.kind.name}/${txn.moneyInKind.name}/${txn.transferReason.name} ${txn.amountPaise} ${txn.merchant} ref=${txn.referenceId} countable=${guards.isCountable(txn)}'}');
      stdout.writeln(message.body.replaceAll(RegExp(r'\s+'), ' '));
    }
    if (txn == null) continue;
    if (txn == null) continue;
    if (msgOfKey.containsKey(txn.key)) {
      // Same dedupe key as an earlier message: the database's UNIQUE index
      // keeps one row, which is the behaviour being measured.
      collapsedByKey.add(id);
      continue;
    }
    msgOfKey[txn.key] = id;
    final category = categorizer.categorize(
      txn.merchant,
      kind: txn.kind,
      transferReason: txn.transferReason,
    );
    parsed.add(
      txn.copyWith(categoryName: category.name, categoryKind: category.kind),
    );
  }

  final admitted = parsed.where(guards.isCountable).toList();
  final resolved = const DedupeEngine().mark(admitted);
  final idOfKey = {for (final e in msgOfKey.entries) e.key: e.value};
  for (final t in resolved) {
    final id = msgOfKey[t.key]!;
    if (show.contains(id) && t.isDuplicateOfKey != null) {
      stdout.writeln('    $id merged into ${idOfKey[t.isDuplicateOfKey]}');
    }
  }
  final counted = <String, Txn>{
    for (final t in resolved)
      if (t.isDuplicateOfKey == null) msgOfKey[t.key]!: t,
  };

  final unlabelled = counted.keys.where((id) => !gold.containsKey(id)).length;
  final labelled = gold.values.where((g) => classOf.containsKey(g.id)).toList();

  // ---- P1: rows counted that move no money --------------------------------
  final falseRows = <String, List<String>>{};
  for (final entry in counted.entries) {
    final g = gold[entry.key];
    if (g == null || g.movesMoney) continue;
    falseRows.putIfAbsent(g.label, () => []).add(entry.key);
  }
  final falseSpend = [
    for (final e in counted.entries)
      if (gold[e.key] != null &&
          !gold[e.key]!.movesMoney &&
          e.value.kind == TxnKind.spend)
        e.key,
  ];

  // ---- P2: one movement counted more than once ------------------------------
  final perRoot = <String, List<String>>{};
  for (final id in counted.keys) {
    final g = gold[id];
    if (g == null || !g.movesMoney) continue;
    perRoot.putIfAbsent(root(id), () => []).add(id);
  }
  final doubles = perRoot.entries.where((e) => e.value.length > 1).toList();

  // ---- Recall: real movements the app never counted -------------------------
  final movements = labelled
      .where((g) => g.movesMoney && g.dupOf == null)
      .toList();
  final missed = movements.where((g) => !perRoot.containsKey(g.id)).toList();
  final missedSpend = missed.where((g) => g.expectedKind == TxnKind.spend).toList();

  // ---- Kind and amount agreement on movements the app did count -------------
  final kindWrong = <String>[];
  final amountWrong = <String>[];
  final directionWrong = <String>[];
  final confusion = <String, int>{};
  for (final entry in perRoot.entries) {
    final g = gold[entry.key]!;
    final t = counted[entry.value.first]!;
    final want = g.expectedKind!;
    final got = effectiveKind(t);
    confusion.update('${want.name}->${got.name}', (v) => v + 1, ifAbsent: () => 1);
    final appIn = t.moneyInKind != MoneyInKind.none || t.kind == TxnKind.income;
    final goldIn = g.label == 'credit';
    if (appIn != goldIn) directionWrong.add(g.id);
    if (want != got) kindWrong.add(g.id);
    final amount = g.amountPaise;
    if (amount != null && (amount - t.amountPaise).abs() > 100) {
      amountWrong.add(g.id);
    }
  }

  // ---- Totals ----------------------------------------------------------------
  int sum(Iterable<int> xs) => xs.fold(0, (a, b) => a + b);
  final goldSpend = sum(
    movements
        .where((g) => g.expectedKind == TxnKind.spend)
        .map((g) => g.amountPaise ?? 0),
  );
  // Only rows from labelled messages: the inbox may hold more than the set.
  final countedLabelled = {
    for (final e in counted.entries)
      if (gold.containsKey(e.key)) e.key: e.value,
  };
  final appSpend = sum(
    countedLabelled.values
        .where((t) => t.kind == TxnKind.spend)
        .map((t) => t.amountPaise),
  );
  final correctSpend = sum(
    perRoot.entries
        .where((e) =>
            gold[e.key]!.expectedKind == TxnKind.spend &&
            counted[e.value.first]!.kind == TxnKind.spend)
        .map((e) => counted[e.value.first]!.amountPaise),
  );

  // ---- Classifier agreement (spam / phishing / otp) -------------------------
  SmsClass want(Gold g) => switch (g.label) {
    'debit' || 'credit' => SmsClass.transaction,
    'promo' => SmsClass.promo,
    'phishing' => SmsClass.phishing,
    _ => SmsClass.informational,
  };
  var classAgree = 0;
  var moneyAgree = 0;
  var promoBlocked = 0;
  final classConfusion = <String, int>{};
  final phishingFalse = <String>[];
  final promoMissed = <String>[];
  for (final g in labelled) {
    final got = classOf[g.id]!;
    final expected = want(g);
    // `unknown` on a non-money message is safe: it can never be counted.
    final ok = got == expected ||
        (got == SmsClass.unknown && expected != SmsClass.transaction);
    if (ok) classAgree++;
    // What matters for the ledger: does the app treat it as money moving?
    // A duplicate notice (fund-house confirmation) may go either way.
    final goldMoney = g.movesMoney && g.dupOf == null;
    final appMoney = got == SmsClass.transaction;
    if (goldMoney == appMoney || (g.movesMoney && g.dupOf != null)) moneyAgree++;
    if (g.label == 'promo' && got != SmsClass.transaction) promoBlocked++;
    classConfusion.update('${g.label}->${got.name}', (v) => v + 1, ifAbsent: () => 1);
    if (got == SmsClass.phishing && g.label != 'phishing') phishingFalse.add(g.id);
    if (g.label == 'promo' && got == SmsClass.transaction) promoMissed.add(g.id);
  }

  String pct(int a, int b) => b == 0 ? '—' : '${(a / b * 100).toStringAsFixed(1)} %';
  String rs(int p) => '₹${(p / 100).toStringAsFixed(0)}';
  final spendCounted =
      countedLabelled.values.where((t) => t.kind == TxnKind.spend).length;
  final spendRight = perRoot.entries
      .where((e) =>
          gold[e.key]!.expectedKind == TxnKind.spend &&
          counted[e.value.first]!.kind == TxnKind.spend)
      .length;
  final goldSpendRows = movements.where((g) => g.expectedKind == TxnKind.spend).length;

  final out = stdout
    ..writeln('== Accuracy audit against the gold set ==')
    ..writeln('messages ${raw.length} · labelled ${labelled.length} · '
        'real movements ${movements.length} · counted by app ${counted.length}'
        '${unlabelled > 0 ? ' ($unlabelled outside the gold set)' : ''}')
    ..writeln('')
    ..writeln('P1  rows counted that moved no money : '
        '${sum(falseRows.values.map((v) => v.length))}  '
        '${falseRows.entries.map((e) => '${e.key}=${e.value.length}').join(' ')}')
    ..writeln('    of which counted as SPEND         : ${falseSpend.length}')
    ..writeln('P2  movements counted twice           : ${doubles.length}')
    ..writeln('')
    ..writeln('Spend precision  ${pct(spendRight, spendCounted)}  ($spendRight of $spendCounted spend rows are real spend)')
    ..writeln('Spend recall     ${pct(spendRight, goldSpendRows)}  ($spendRight of $goldSpendRows real spends found)')
    ..writeln('Movement recall  ${pct(movements.length - missed.length, movements.length)}  '
        '(missed ${missed.length}, of which spend ${missedSpend.length})')
    ..writeln('Kind agreement   ${pct(perRoot.length - kindWrong.length, perRoot.length)}  '
        '(wrong ${kindWrong.length})')
    ..writeln('Amount agreement ${pct(perRoot.length - amountWrong.length, perRoot.length)}  '
        '(wrong ${amountWrong.length})')
    ..writeln('Direction errors ${directionWrong.length}')
    ..writeln('')
    ..writeln('Spend total  gold ${rs(goldSpend)} · app ${rs(appSpend)} · '
        'correctly counted ${rs(correctSpend)} '
        '(${pct(correctSpend, goldSpend)} of real spend)')
    ..writeln('')
    ..writeln('Money / no-money agreement ${pct(moneyAgree, labelled.length)}  '
        '· promos kept out of the ledger ${pct(promoBlocked, labelled.where((g) => g.label == 'promo').length)}')
    ..writeln('Classifier agreement ${pct(classAgree, labelled.length)} (strict, per class)  '
        '· phishing false alarms ${phishingFalse.length} '
        '· promos classed as transaction ${promoMissed.length}')
    ..writeln('kind confusion (gold->app): '
        '${(confusion.entries.toList()..sort((a, b) => b.value - a.value)).map((e) => '${e.key}=${e.value}').join('  ')}');

  void list(String title, Iterable<String> ids) {
    if (ids.isEmpty) return;
    out.writeln('$title: ${ids.join(', ')}');
  }

  out.writeln('');
  for (final e in falseRows.entries) {
    list('P1 ${e.key}', e.value);
  }
  list('P2 doubles', doubles.map((e) => '${e.key}<-${e.value.join('+')}'));
  if (listAll) {
    list('missed spend', missedSpend.map((g) => g.id));
    list('missed other', missed.where((g) => !missedSpend.contains(g)).map((g) => '${g.id}(${g.label}/${g.kind})'));
    list('kind wrong', kindWrong.map((id) => '$id(${gold[id]!.kind}->${effectiveKind(counted[perRoot[id]!.first]!).name})'));
    list('amount wrong', amountWrong);
    list('phishing false', phishingFalse);
    list('promo as txn', promoMissed);
    out.writeln('class confusion: ${(classConfusion.entries.toList()..sort((a, b) => b.value - a.value)).map((e) => '${e.key}=${e.value}').join('  ')}');
  }

  if (jsonOut != null) {
    File(jsonOut).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'labelled': labelled.length,
      'movements': movements.length,
      'p1_false_rows': sum(falseRows.values.map((v) => v.length)),
      'p1_false_spend': falseSpend.length,
      'p2_doubles': doubles.length,
      'spend_precision': spendCounted == 0 ? null : spendRight / spendCounted,
      'spend_recall': goldSpendRows == 0 ? null : spendRight / goldSpendRows,
      'movement_recall': movements.isEmpty ? null : (movements.length - missed.length) / movements.length,
      'kind_agreement': perRoot.isEmpty ? null : (perRoot.length - kindWrong.length) / perRoot.length,
      'amount_agreement': perRoot.isEmpty ? null : (perRoot.length - amountWrong.length) / perRoot.length,
      'classifier_agreement': labelled.isEmpty ? null : classAgree / labelled.length,
      'money_agreement': labelled.isEmpty ? null : moneyAgree / labelled.length,
      'phishing_false': phishingFalse.length,
      'gold_spend_paise': goldSpend,
      'app_spend_paise': appSpend,
    }));
  }
}

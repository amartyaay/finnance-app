// Executable assertion suite for the SMS parser.
//
// Every fixture in `test/fixtures/sms_corpus.dart` (extracted verbatim from
// `docs/research/01-sms-corpus.md` §10) is pushed through the real pipeline:
//
//   SmsClassifier.assess()  -> what the message is
//   TransactionExtractor.extract() -> the ledger row it would create
//
// The assertions encode the *research document's* expectations, not the current
// implementation's behaviour. A failure here is a parser gap, never a test bug:
// see `docs/research/parser-gap-report.md`.
//
// `flutter test test/sms_corpus_test.dart` prints a per-bucket pass rate and a
// tab-separated mismatch block at the end.
//
// ignore_for_file: avoid_print

import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/sms_message.dart';
import 'package:finnance_app/domain/transaction.dart';
import 'package:finnance_app/engine/dedupe_engine.dart';
import 'package:finnance_app/services/sms/sender_registry.dart';
import 'package:finnance_app/services/sms/sms_classifier.dart';
import 'package:finnance_app/services/sms/transaction_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/sms_corpus.dart';

/// One fixed instant for every fixture so parse results are deterministic.
const int _receivedAtMs = 1750000000000;

const SenderRegistry _registry = SenderRegistry();
final SmsClassifier _classifier = SmsClassifier();
final TransactionExtractor _extractor = TransactionExtractor();

// ---------------------------------------------------------------------------
// Result collection
// ---------------------------------------------------------------------------

class Mismatch {
  const Mismatch(this.field, this.expected, this.actual);

  final String field;
  final Object? expected;
  final Object? actual;

  @override
  String toString() => '$field expected=$expected actual=$actual';

  String toTsv() => '$field\t$expected\t$actual';
}

class CheckResult {
  CheckResult(this.bucket, this.label);

  final SmsBucket bucket;
  final String label;
  final List<Mismatch> mismatches = <Mismatch>[];

  bool get passed => mismatches.isEmpty;
}

final List<CheckResult> _checks = <CheckResult>[];

CheckResult _newCheck(SmsBucket bucket, String label) {
  final check = CheckResult(bucket, label);
  _checks.add(check);
  return check;
}

void _expect(CheckResult check, String field, Object? expected, Object? actual) {
  if (expected != actual) {
    check.mismatches.add(Mismatch(field, expected, actual));
  }
}

String _reason(CheckResult check) =>
    check.mismatches.map((m) => m.toString()).join('; ');

// ---------------------------------------------------------------------------
// Fixture translation
// ---------------------------------------------------------------------------

SmsMessage _message(SmsFixture fixture) => SmsMessage(
  id: fixture.id,
  sender: fixture.sender,
  body: fixture.body,
  receivedAtMs: _receivedAtMs,
);

TxnKind _expectedKind(SmsFixture fixture) {
  // Cash is a movement of money, not consumption: the research doc's ATM rows
  // carry `direction: expense` because cash leaves the account, but the app
  // models an ATM withdrawal as `TxnKind.cash`.
  if (fixture.instrument == SmsInstrument.atm) return TxnKind.cash;
  return switch (fixture.direction) {
    SmsDirection.expense => TxnKind.spend,
    SmsDirection.transfer => TxnKind.transfer,
    SmsDirection.income => TxnKind.income,
    null => TxnKind.spend,
  };
}

Instrument _expectedInstrument(SmsInstrument instrument) => switch (instrument) {
  SmsInstrument.upi => Instrument.upi,
  SmsInstrument.debitCard => Instrument.debitCard,
  SmsInstrument.creditCard => Instrument.creditCard,
  SmsInstrument.account => Instrument.bankAccount,
  SmsInstrument.wallet => Instrument.wallet,
  SmsInstrument.atm => Instrument.atm,
};

String _normaliseLabel(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Issuer identity check.
///
/// The research doc writes the canonical issuer ("Kotak Mahindra Bank",
/// "OneCard (CSB Bank)"), while the parser may return a shorter label
/// ("Kotak", "OneCard"). Either direction of containment still identifies the
/// same bank; a different bank is a failure. Two rows carry a note instead of an
/// issuer (e.g. "unknown (mask 6314)") — those are recorded in the gap report's
/// fixture-anomaly section and cannot be asserted.
bool _issuerMatches(String expected, String? actual) {
  if (actual == null) return false;
  final want = _normaliseLabel(expected);
  final got = _normaliseLabel(actual);
  return want == got || want.contains(got) || got.contains(want);
}

bool _issuerIsNote(String expected) =>
    expected.toLowerCase().startsWith('unknown');

// ---------------------------------------------------------------------------
// Per-fixture assertions
// ---------------------------------------------------------------------------

void _checkTransactionFixture(SmsFixture fixture) {
  final message = _message(fixture);
  final assessment = _classifier.assess(message);
  final sender = _registry.resolve(fixture.sender);
  final txn = _extractor.extract(message, sender);
  final check = _newCheck(fixture.bucket, fixture.id);

  if (fixture.expectsNoTransaction) {
    // A message may be classified as a transaction *or* parsed into a Txn on its
    // own; only when both happen does a row reach the ledger.
    if (assessment.isTransaction) {
      check.mismatches.add(
        const Mismatch('classifier', 'not transaction', 'transaction'),
      );
    }
    if (assessment.isTransaction && txn != null) {
      check.mismatches.add(
        Mismatch(
          'ledger',
          'no row',
          'row amount=${txn.amountPaise} merchant=${txn.merchant}',
        ),
      );
    }
    expect(check.mismatches, isEmpty, reason: '${fixture.id} ${_reason(check)}');
    return;
  }

  _expect(
    check,
    'classifier',
    SmsClass.transaction.name,
    assessment.cls.name,
  );

  if (txn == null) {
    check.mismatches.add(const Mismatch('extract', 'Txn', 'null'));
    expect(check.mismatches, isEmpty, reason: '${fixture.id} ${_reason(check)}');
    return;
  }

  _expect(check, 'amountPaise', fixture.amountPaise, txn.amountPaise);
  _expect(check, 'kind', _expectedKind(fixture).name, txn.kind.name);

  final instrument = fixture.instrument;
  if (instrument == null) {
    check.mismatches.add(const Mismatch('instrument', 'non-null', 'null'));
  } else {
    _expect(
      check,
      'instrument',
      _expectedInstrument(instrument).name,
      txn.instrument.name,
    );
  }

  if (fixture.last4 != null) {
    _expect(check, 'last4', fixture.last4, txn.last4);
  }
  // Card identity, not just the tail: a bill-payment pair can only keep the
  // issuer leg if that leg binds `issuer|last4`. Asserting it is what stops the
  // "credit card ending with NNNN" regression from passing silently.
  if (fixture.cardKey != null) {
    _expect(check, 'cardKey', fixture.cardKey, txn.cardKey);
  }
  if (fixture.moneyInKind != null) {
    _expect(check, 'moneyInKind', fixture.moneyInKind, txn.moneyInKind.name);
  }

  final issuer = fixture.issuer;
  if (issuer != null && !_issuerIsNote(issuer)) {
    if (!_issuerMatches(issuer, txn.issuer)) {
      check.mismatches.add(Mismatch('issuer', issuer, txn.issuer));
    }
  }

  if (fixture.referenceId != null) {
    _expect(
      check,
      'referenceId',
      fixture.referenceId!.toUpperCase(),
      txn.referenceId,
    );
  }

  final merchant = fixture.merchantContains;
  if (merchant != null && merchant.trim().isNotEmpty) {
    final actual = txn.merchant;
    final ok = actual != null &&
        actual.toLowerCase().contains(merchant.trim().toLowerCase());
    if (!ok) {
      check.mismatches.add(Mismatch('merchant', 'contains "$merchant"', actual));
    }
  }

  expect(check.mismatches, isEmpty, reason: '${fixture.id} ${_reason(check)}');
}

// ---------------------------------------------------------------------------
// Duplicate groups
// ---------------------------------------------------------------------------

Map<String, List<SmsFixture>> _duplicateGroups() {
  final groups = <String, List<SmsFixture>>{};
  for (final fixture in smsCorpus) {
    final group = fixture.isDuplicateGroup;
    if (group == null) continue;
    groups.putIfAbsent(group, () => <SmsFixture>[]).add(fixture);
  }
  return groups;
}

void _checkDuplicateGroup(String group, List<SmsFixture> fixtures) {
  final check = _newCheck(SmsBucket.duplicatePairs, 'dupe:$group');
  final txns = <Txn>[];

  for (final fixture in fixtures) {
    // Offset fixtures are the real shape of a card-bill pair: the bank debit
    // and the issuer's "payment received" arrive hours apart.
    final txn = _extractor.extract(
      SmsMessage(
        id: fixture.id,
        sender: fixture.sender,
        body: fixture.body,
        receivedAtMs: _receivedAtMs + fixture.receivedOffsetSeconds * 1000,
      ),
      _registry.resolve(fixture.sender),
    );
    if (txn == null) {
      check.mismatches.add(Mismatch('${fixture.id}.extract', 'Txn', 'null'));
    } else {
      txns.add(txn);
    }
  }

  if (txns.length != fixtures.length) {
    expect(check.mismatches, isEmpty, reason: '${check.label} ${_reason(check)}');
    return;
  }

  final marked = const DedupeEngine().mark(txns);
  final survivors = marked.where((t) => t.isDuplicateOfKey == null).toList();

  _expect(check, 'rowCount', fixtures.length, marked.length);
  _expect(check, 'survivingRows', 1, survivors.length);
  _expect(check, 'groupAmount', 1, marked.map((t) => t.amountPaise).toSet().length);
  // A card-bill group must keep the leg that names the card. Whatever the
  // arrival order, the funding-account debit may not win the group.
  if (fixtures.any((f) => f.cardKey != null) && survivors.length == 1) {
    _expect(
      check,
      'survivorReason',
      TransferReason.creditCardBill.name,
      survivors.single.transferReason.name,
    );
    _expect(check, 'survivorCardKey', true, survivors.single.cardKey != null);
  }

  expect(check.mismatches, isEmpty, reason: '${check.label} ${_reason(check)}');
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

String _summary() {
  final buffer = StringBuffer();
  buffer.writeln('===SMS-SUMMARY-BEGIN===');
  buffer.writeln('SMS parser corpus — pass rate by bucket');

  final byBucket = <SmsBucket, List<CheckResult>>{};
  for (final check in _checks) {
    byBucket.putIfAbsent(check.bucket, () => <CheckResult>[]).add(check);
  }

  var passed = 0;
  var total = 0;
  for (final bucket in SmsBucket.values) {
    final checks = byBucket[bucket];
    if (checks == null || checks.isEmpty) continue;
    final pass = checks.where((c) => c.passed).length;
    passed += pass;
    total += checks.length;
    final rate = (pass * 100 / checks.length).toStringAsFixed(1);
    buffer.writeln(
      'SUMMARY\t${bucket.label}\t$pass\t${checks.length}\t$rate',
    );
  }
  final overall = total == 0 ? '0.0' : (passed * 100 / total).toStringAsFixed(1);
  buffer.writeln('SUMMARY\tOVERALL\t$passed\t$total\t$overall');
  buffer.writeln('===SMS-SUMMARY-END===');

  buffer.writeln('===SMS-GAPS-BEGIN===');
  for (final check in _checks.where((c) => !c.passed)) {
    for (final mismatch in check.mismatches) {
      buffer.writeln(
        'GAP\t${check.label}\t${check.bucket.name}\t${mismatch.toTsv()}',
      );
    }
  }
  buffer.writeln('===SMS-GAPS-END===');
  return buffer.toString();
}

String _excerpt(String body) {
  final clean = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  return clean.length <= 44 ? clean : '${clean.substring(0, 44)}…';
}

// ---------------------------------------------------------------------------

void main() {
  group('Fixture coverage', () {
    // 103 §10 rows + H11/H12 (the two real HDFC bill-payment legs, 20 h apart)
    // + H13 (the "credited to your card ending" issuer template). The corpus
    // grew by three because the existing rows never asserted `cardKey`, which is
    // why an issuer leg with no card identity could pass 109/109 checks.
    test('matches the coverage audit (106 rows)', () {
      expect(smsCorpus.length, 106);
      final counts = <String, int>{};
      for (final fixture in smsCorpus) {
        final prefix = fixture.id.substring(0, 1);
        counts.update(prefix, (v) => v + 1, ifAbsent: () => 1);
      }
      const expected = <String, int>{
        'A': 9,
        'B': 7,
        'C': 14,
        'D': 3,
        'E': 5,
        'F': 7,
        'G': 10,
        'H': 13,
        'I': 7,
        'J': 5,
        'K': 20,
        'L': 6,
      };
      expect(counts, expected);
    });

    test('every id is unique and every positive row has a direction', () {
      final ids = smsCorpus.map((f) => f.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final fixture in smsCorpus.where((f) => !f.expectsNoTransaction)) {
        expect(fixture.direction, isNotNull, reason: fixture.id);
        expect(fixture.amountPaise, isNotNull, reason: fixture.id);
        expect(fixture.instrument, isNotNull, reason: fixture.id);
      }
    });
  });

  for (final bucket in SmsBucket.values) {
    final fixtures = smsCorpus.where((f) => f.bucket == bucket).toList();
    if (fixtures.isEmpty) continue;
    group('${bucket.label} (${fixtures.length})', () {
      for (final fixture in fixtures) {
        test(
          '${fixture.id} · ${_excerpt(fixture.body)}',
          () => _checkTransactionFixture(fixture),
        );
      }
    });
  }

  group('Duplicate pairs', () {
    final groups = _duplicateGroups();
    for (final entry in groups.entries) {
      test(
        '${entry.key} (${entry.value.length} alerts -> 1 row)',
        () => _checkDuplicateGroup(entry.key, entry.value),
      );
    }
  });

  tearDownAll(() => print(_summary()));
}

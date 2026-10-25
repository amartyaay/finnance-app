// Executable assertion suite for the SMS classifier.
//
// Every fixture in `test/fixtures/spam_corpus.dart` (extracted verbatim from
// `docs/research/02-spam-and-phishing.md` Appendix A) is pushed through
// `SmsClassifier.assess()`.
//
// The corpus keeps the research document's five-class taxonomy
// (`SpamClass.transaction / informational / otp / promo / fraud`). The shipped
// `SmsClass` enum only has `transaction / informational / promo / phishing /
// unknown`, so the mapping below is the taxonomy gap made explicit:
//
//   otp   -> informational   (no separate OTP class in the app)
//   fraud -> phishing        (the app calls it phishing)
//
// The mapping is asserted, never used to relax the expectation: an OTP that
// classifies as `promo` or `transaction` still fails.
//
// `flutter test test/spam_corpus_test.dart` prints a per-class pass rate and a
// tab-separated mismatch block at the end.
//
// ignore_for_file: avoid_print

import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/sms_message.dart';
import 'package:finnance_app/services/sms/sms_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/spam_corpus.dart';

const int _receivedAtMs = 1750000000000;

final SmsClassifier _classifier = SmsClassifier();

/// Research taxonomy -> shipped enum. See the file header.
SmsClass _shippedClassOf(SpamClass expected) => switch (expected) {
  SpamClass.transaction => SmsClass.transaction,
  SpamClass.informational => SmsClass.informational,
  SpamClass.otp => SmsClass.informational,
  SpamClass.promo => SmsClass.promo,
  SpamClass.fraud => SmsClass.phishing,
};

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

  final String bucket;
  final String label;
  final List<Mismatch> mismatches = <Mismatch>[];

  bool get passed => mismatches.isEmpty;
}

final List<CheckResult> _checks = <CheckResult>[];

CheckResult _newCheck(String bucket, String label) {
  final check = CheckResult(bucket, label);
  _checks.add(check);
  return check;
}

void _checkFixture(SpamFixture fixture) {
  final assessment = _classifier.assess(
    SmsMessage(
      id: fixture.id,
      sender: fixture.sender,
      body: fixture.body,
      receivedAtMs: _receivedAtMs,
    ),
  );
  final check = _newCheck(fixture.bucket, fixture.id);

  final shipped = _shippedClassOf(fixture.expected);
  if (assessment.cls != shipped) {
    check.mismatches.add(
      Mismatch(
        'cls',
        '${fixture.expected.name}(${shipped.name})',
        assessment.cls.name,
      ),
    );
  }

  // Hard rule H6: a message the research document does not put in the ledger
  // must never be counted. A `transaction` from an unverified sender is the one
  // documented exception: it stays a transaction but is flagged
  // `countsTowardLedger: false` (fraud-16), so the rule only applies to the
  // non-transaction classes.
  if (fixture.expected != SpamClass.transaction &&
      !fixture.countsTowardLedger &&
      assessment.isTransaction) {
    check.mismatches.add(
      const Mismatch('countsTowardLedger', 'false', 'transaction'),
    );
  }
  if (fixture.expected == SpamClass.fraud && assessment.isTransaction) {
    check.mismatches.add(
      const Mismatch('fraudIsNeverSpend', 'false', 'transaction'),
    );
  }

  expect(
    check.mismatches,
    isEmpty,
    reason: '${fixture.id} ${check.mismatches.map((m) => m.toString()).join('; ')}',
  );
}

String _summary() {
  final buffer = StringBuffer();
  buffer.writeln('===SPAM-SUMMARY-BEGIN===');
  buffer.writeln('SMS classifier corpus — pass rate by class');

  final buckets = <String, List<CheckResult>>{};
  for (final check in _checks) {
    buckets.putIfAbsent(check.bucket, () => <CheckResult>[]).add(check);
  }

  var passed = 0;
  var total = 0;
  // Fixed display order: the research taxonomy, not map insertion order.
  for (final bucket in SpamClass.values.map((c) => c.name)) {
    final checks = buckets[bucket];
    if (checks == null || checks.isEmpty) continue;
    final pass = checks.where((c) => c.passed).length;
    passed += pass;
    total += checks.length;
    final rate = (pass * 100 / checks.length).toStringAsFixed(1);
    buffer.writeln('SUMMARY\t$bucket\t$pass\t${checks.length}\t$rate');
  }
  final overall = total == 0 ? '0.0' : (passed * 100 / total).toStringAsFixed(1);
  buffer.writeln('SUMMARY\tOVERALL\t$passed\t$total\t$overall');
  buffer.writeln('===SPAM-SUMMARY-END===');

  buffer.writeln('===SPAM-GAPS-BEGIN===');
  for (final check in _checks.where((c) => !c.passed)) {
    for (final mismatch in check.mismatches) {
      buffer.writeln(
        'GAP\t${check.label}\t${check.bucket}\t${mismatch.toTsv()}',
      );
    }
  }
  buffer.writeln('===SPAM-GAPS-END===');
  return buffer.toString();
}

String _excerpt(String body) {
  final clean = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  return clean.length <= 44 ? clean : '${clean.substring(0, 44)}…';
}

void main() {
  group('Fixture coverage', () {
    test('matches the Appendix A corpus (77 rows)', () {
      expect(spamCorpus.length, 77);
      final counts = <String, int>{};
      for (final fixture in spamCorpus) {
        counts.update(
          fixture.expected.name,
          (v) => v + 1,
          ifAbsent: () => 1,
        );
      }
      expect(counts, <String, int>{
        'transaction': 19,
        'informational': 13,
        'otp': 9,
        'promo': 14,
        'fraud': 22,
      });
      expect(
        spamCorpus.map((f) => f.id).toSet().length,
        spamCorpus.length,
        reason: 'fixture ids must be unique',
      );
    });
  });

  for (final spamClass in SpamClass.values) {
    final fixtures =
        spamCorpus.where((f) => f.expected == spamClass).toList();
    if (fixtures.isEmpty) continue;
    group('${spamClass.name} (${fixtures.length})', () {
      for (final fixture in fixtures) {
        test(
          '${fixture.id} · ${_excerpt(fixture.body)}',
          () => _checkFixture(fixture),
        );
      }
    });
  }

  tearDownAll(() => print(_summary()));
}

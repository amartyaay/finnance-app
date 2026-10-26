// The SBI statement pipeline on the three synthetic layouts from
// docs/research/07-sbi-statement.md §8 — the same 15 transactions each time,
// so one expected table covers all of them.
import 'dart:io';

import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/statement.dart';
import 'package:finnance_app/engine/salary_cycles.dart';
import 'package:finnance_app/services/statement/statement_importer.dart';
import 'package:finnance_app/services/statement/statement_table.dart';
import 'package:finnance_app/services/statement/statement_words.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/sbi_statements.dart';

const _importer = StatementImporter();

const _expectedKinds = [
  StatementKind.otherCredit, // NEFT ACME — becomes salary by recurrence
  StatementKind.spend, // Swiggy
  StatementKind.cardBill, // CRED
  StatementKind.selfTransfer, // IMPS to own HDFC, "Self"
  StatementKind.cash, // ATM
  StatementKind.spend, // BigBasket
  StatementKind.investment, // ICCL mutual fund SIP
  StatementKind.spend, // debit card, Amazon Pay
  StatementKind.refund, // Amazon seller refund
  StatementKind.toPerson, // rent to Ramesh
  StatementKind.fromPerson, // Priya, dinner
  StatementKind.spend, // Uber
  StatementKind.interest,
  StatementKind.spend, // BESCOM bill pay
  StatementKind.otherCredit, // NEFT ACME again
];

void main() {
  // The 2026 OnlineSBI "Account Statement" PDF: column labels drawn as vector
  // art (only "Balance" is text), slash dates, "-" in empty cells, narration
  // centred on the dated line, and the branch name under every row.
  test('a statement with no column labels in its text', () {
    final text = File('test/fixtures/sbi_statement_2026.txt')
        .readAsStringSync()
        .replaceAll('\r\n', '\n'); // a Windows checkout adds CR
    final statement = _importer.parse(wordsFromText(text));
    expect(statement.periodFrom, DateTime(2026, 9, 1));
    expect(statement.rows, hasLength(5));
    expect(statement.verifiedRows, 4); // the first has no opening balance
    expect([for (final r in statement.rows) r.debitPaise], [50000, 0, 24500, 16100, 0]);
    expect([for (final r in statement.rows) r.creditPaise], [0, 8000000, 0, 0, 120000]);
    // "WDL TFR" printed above the date belongs to its own row, and the branch
    // name is dropped rather than glued onto the next one.
    expect(statement.rows[2].description, startsWith('WDL TFR UPI/DR/222/ZEPTO'));
    expect(statement.rows.any((r) => r.description.contains('JAWAHARNAGAR')), isFalse);
    expect(statement.rows[1].counterparty, 'DELOITTE CONSUL');
  });

  // Header variants seen in other exports: units glued to the labels, and the
  // labels wrapped across two printed lines.
  group('header variants', () {
    const header =
        'Txn Date  Value     Description                   Ref No./Cheque          Debit       Credit       Balance';
    test('units glued to the labels', () {
      final text = sbiLayoutB.replaceFirst(
        header,
        'Txn Date  Value     Narration                     Ref No./Cheque     Withdrawals(INR) Deposits(INR) Balance(INR)',
      );
      expect(_importer.parse(wordsFromText(text)).rows, hasLength(15));
    });
    test('labels split over two lines', () {
      final text = sbiLayoutB.replaceFirst(
        '$header\n          Date                                    No.',
        'Txn Date  Value     Description                   Ref No./Cheque\n'
            '          Date                                    No.                Debit       Credit       Balance',
      );
      expect(text, isNot(sbiLayoutB));
      expect(_importer.parse(wordsFromText(text)).rows, hasLength(15));
    });
  });

  // Layout A prints no UPI note, so "rent sept" is only known in B and C.
  for (final (name, text, printsNote) in [
    ('A (CBS e-statement)', sbiLayoutA, false),
    ('B (OnlineSBI PDF)', sbiLayoutB, true),
    ('C (YONO export)', sbiLayoutC, true),
  ]) {
    group('layout $name', () {
      final statement = _importer.parse(wordsFromText(text));

      test('reads the account, period and balances', () {
        expect(statement.bank, 'SBI');
        expect(statement.accountMask, '7890');
        expect(statement.holderName, 'RAHUL VERMA');
        expect(statement.periodFrom, DateTime(2026, 9, 1));
        expect(statement.periodTo, DateTime(2026, 10, 3));
        expect(statement.openingBalancePaise, 4231560);
        expect(statement.closingBalancePaise, 17271770);
      });

      test('every row reconciles with the running balance', () {
        expect(statement.rows, hasLength(15));
        expect(statement.verifiedRows, 15);
        expect(statement.fullyVerified, isTrue);
        final debits = statement.rows.fold(0, (s, r) => s + r.debitPaise);
        final credits = statement.rows.fold(0, (s, r) => s + r.creditPaise);
        expect(debits, 9715890);
        expect(credits, 22756100);
      });

      test('classifies every row', () {
        expect(statement.rows.map((r) => r.kind).toList(), _expectedKinds);
        expect(statement.rows[1].categoryKind, SpendCategoryKind.food);
        expect(statement.rows[5].categoryKind, SpendCategoryKind.groceries);
        expect(statement.rows[11].categoryKind, SpendCategoryKind.transport);
        expect(statement.rows[9].categoryName, printsNote ? 'Rent' : 'Transfers');
      });

      test('finds the salary by recurrence and splits salary to salary', () {
        final analysis = _importer.analyse(
          statement.rows,
          from: statement.periodFrom,
          to: statement.periodTo,
        );
        expect(analysis.salary.found, isTrue);
        expect(analysis.salary.rowIndexes, hasLength(2));
        expect(analysis.salary.typicalPaise, 11245000);

        expect(analysis.cycles, hasLength(2));
        final september = analysis.cycles.last; // newest first
        expect(september.start, DateTime(2026, 9, 1));
        expect(september.end, DateTime(2026, 10, 1));
        expect(september.isPartial, isFalse);
        expect(september.salaryPaise, 11245000);
        // ₹5,944.90 merchants + ₹18,000 rent − ₹1,499 refund.
        expect(september.spentPaise, 2244590);
        expect(september.cardBillsPaise, 3821400);
        expect(september.cashPaise, 500000);
        expect(september.investedPaise, 500000);
        expect(analysis.cycles.first.isPartial, isTrue);
      });
    });
  }

  group('the arithmetic is the authority', () {
    test('a debit printed under Credit is corrected by the balance', () {
      // Move the ₹486 Swiggy debit right, into the Credit band.
      final moved = sbiLayoutC.replaceFirst(
        '624512345601            486.00           - 1,54,279.60',
        '624512345601                 -      486.00 1,54,279.60',
      );
      expect(moved, isNot(sbiLayoutC));
      final s = const StatementTableBuilder().build(wordsFromText(moved));
      expect(s.verifiedRows, 15);
      expect(s.rows[1].debitPaise, 48600);
      expect(s.warnings.join(), contains('swapped'));
    });

    test('a dropped row breaks the chain and is reported, not hidden', () {
      final dropped = sbiLayoutC.replaceFirst(
        RegExp(r'06/09/2026  ATM WDL.*\n.*BENGALURU\n'),
        '',
      );
      final s = const StatementTableBuilder().build(wordsFromText(dropped));
      expect(s.rows, hasLength(14));
      expect(s.fullyVerified, isFalse);
      expect(s.warnings.join(), contains('did not reconcile'));
    });

    test('money is parsed as integer paise', () {
      expect(StatementTableBuilder.toPaise('1,12,450.00'), 11245000);
      expect(StatementTableBuilder.toPaise('2618072.00Cr'), 261807200);
      expect(StatementTableBuilder.toPaise('1,111.05Dr'), -111105);
      expect(StatementTableBuilder.toPaise('0.07'), 7);
      expect(StatementTableBuilder.toPaise('12.5'), isNull);
    });
  });

  group('salary detection', () {
    StatementRow credit(DateTime d, int rupees, String who, {String? desc}) =>
        StatementRow(
          date: d,
          description: desc ?? 'NEFT*HDFC0001234*N1*$who',
          debitPaise: 0,
          creditPaise: rupees * 100,
          balancePaise: null,
          kind: StatementKind.otherCredit,
          counterparty: who,
        );

    test('the word salary glued to a reference still counts', () {
      expect(
        SalaryDetector.mentionsSalary('BULK POSTING-CTD74413970014100Salary of August'),
        isTrue,
      );
      expect(SalaryDetector.mentionsSalary('PENSION FOR SEP'), isTrue);
      expect(SalaryDetector.mentionsSalary('UNIVERSAL STORES'), isFalse);
    });

    test('a bonus stays in its cycle; a refund-sized credit is not salary', () {
      final rows = [
        credit(DateTime(2026, 6, 1), 112450, 'ACME SOFTWARE PV T'),
        credit(DateTime(2026, 7, 1), 148000, 'ACME SOFTWARE PVT'),
        credit(DateTime(2026, 7, 6), 6200, 'ACME SOFTWARE PVT'),
        credit(DateTime(2026, 8, 1), 112450, 'ACME SOFTWARE PVT LTD'),
      ];
      final verdict = const SalaryDetector().detect(rows);
      expect(verdict.found, isTrue);
      final cycles = const SalaryCycleBuilder().build(rows, verdict);
      // The ₹6,200 five days after payday does not open a cycle.
      expect(cycles.map((c) => c.start), [
        DateTime(2026, 8, 1),
        DateTime(2026, 7, 1),
        DateTime(2026, 6, 1),
      ]);
    });

    test('a user override wins both ways', () {
      final rows = [
        credit(DateTime(2026, 6, 1), 50000, 'MOM'),
        credit(DateTime(2026, 7, 1), 50000, 'MOM').copyWith(isSalaryOverride: false),
        credit(DateTime(2026, 7, 3), 30000, 'FREELANCE').copyWith(isSalaryOverride: true),
      ];
      final verdict = const SalaryDetector().detect(rows);
      expect(verdict.rowIndexes, {2});
    });
  });
}

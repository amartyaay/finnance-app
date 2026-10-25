/// Statement file → classified rows → salary → salary-to-salary cycles.
///
/// Pure: the PDF engine sits outside (`readPdfWords`), so everything here runs
/// in `flutter test` on any host.
library;

import '../../domain/statement.dart';
import '../../engine/salary_cycles.dart';
import 'statement_classifier.dart';
import 'statement_table.dart';
import 'statement_words.dart';

class StatementAnalysis {
  const StatementAnalysis({required this.salary, required this.cycles});

  final SalaryVerdict salary;

  /// Newest first.
  final List<SalaryCycle> cycles;
}

class StatementImporter {
  const StatementImporter({
    this.table = const StatementTableBuilder(),
    this.classifier = const StatementClassifier(),
    this.salaryDetector = const SalaryDetector(),
    this.cycleBuilder = const SalaryCycleBuilder(),
  });

  final StatementTableBuilder table;
  final StatementClassifier classifier;
  final SalaryDetector salaryDetector;
  final SalaryCycleBuilder cycleBuilder;

  /// Parses and classifies one file. Throws nothing for a bad table: an empty
  /// or unbalanced result comes back with its warnings for the screen to show.
  BankStatement parse(List<PdfWord> words) {
    final statement = table.build(words);
    return BankStatement(
      bank: statement.bank,
      accountMask: statement.accountMask,
      holderName: statement.holderName,
      periodFrom: statement.periodFrom,
      periodTo: statement.periodTo,
      openingBalancePaise: statement.openingBalancePaise,
      closingBalancePaise: statement.closingBalancePaise,
      warnings: statement.warnings,
      rows: [
        for (final row in statement.rows)
          classifier.classify(row, holderName: statement.holderName),
      ],
    );
  }

  /// Salary and cycles over every stored row of an account (several imported
  /// statements together). Rows must already be de-duplicated.
  StatementAnalysis analyse(
    List<StatementRow> rows, {
    DateTime? from,
    DateTime? to,
  }) {
    final sorted = [...rows]..sort((a, b) => a.date.compareTo(b.date));
    final verdict = salaryDetector.detect(sorted);
    final salaried = [
      for (var i = 0; i < sorted.length; i++)
        verdict.rowIndexes.contains(i) && sorted[i].kind != StatementKind.salary
            ? sorted[i].copyWith(
                kind: StatementKind.salary,
                categoryName: 'Income',
              )
            : sorted[i],
    ];
    return StatementAnalysis(
      salary: verdict,
      cycles: cycleBuilder.build(salaried, verdict, periodFrom: from, periodTo: to),
    );
  }
}

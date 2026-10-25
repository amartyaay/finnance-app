/// Salary detection and salary-to-salary cycles over bank-statement rows.
///
/// Salary is found from behaviour, not only from the word "salary": SBI often
/// prints an employer NEFT as `BY TRANSFER-NEFT*HDFC0000001*N2930…*DELOITTE C`,
/// with nothing that says "salary". The detector looks for a payer that credits
/// a similar, large amount about once a month; a narration that does say
/// SALARY/SAL/PAYROLL is enough on its own. The user can always override a row
/// either way, and the override wins.
library;

import '../domain/statement.dart';

/// Why a set of credits was taken as salary — shown to the user verbatim.
class SalaryVerdict {
  const SalaryVerdict({
    required this.rowIndexes,
    required this.payer,
    required this.reason,
    required this.typicalPaise,
  });

  static const SalaryVerdict none = SalaryVerdict(
    rowIndexes: {},
    payer: null,
    reason: 'No salary credit found in this statement.',
    typicalPaise: 0,
  );

  final Set<int> rowIndexes;
  final String? payer;
  final String reason;

  /// Median salary credit, for "typical salary" copy.
  final int typicalPaise;

  bool get found => rowIndexes.isNotEmpty;
}

class SalaryDetector {
  const SalaryDetector({
    this.minimumPaise = 500000, // ₹5,000: below this a credit is not a salary.
  });

  final int minimumPaise;

  /// `SALARY` with no leading word boundary: SBI glues it to a reference
  /// (`CTD74413970014100Salary of August`). The short `SAL` form needs a
  /// non-letter on both sides.
  static final RegExp _salaryWord = RegExp(
    r'salary|payroll|wages|stipend|pension|(?<![a-z])sal(?![a-z])',
    caseSensitive: false,
  );

  static bool mentionsSalary(String narration) =>
      _salaryWord.hasMatch(narration);

  SalaryVerdict detect(List<StatementRow> rows) {
    final forced = <int>{};
    final banned = <int>{};
    for (var i = 0; i < rows.length; i++) {
      final override = rows[i].isSalaryOverride;
      if (override == true) forced.add(i);
      if (override == false) banned.add(i);
    }

    // Candidates: credits that could be pay. Refunds, interest, own-account
    // moves, redemptions and cashback are never salary.
    final groups = <String, List<int>>{};
    final worded = <int>{};
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.isDebit || banned.contains(i)) continue;
      if (row.creditPaise < minimumPaise) continue;
      if (!_couldBeSalary(row.kind)) continue;
      if (mentionsSalary(row.description)) worded.add(i);
      final key = payerKey(row.counterparty);
      groups.putIfAbsent(key, () => []).add(i);
    }

    // The best recurring payer: credits in at least two different months,
    // roughly monthly, with amounts that do not swing wildly.
    String? bestKey;
    var bestScore = 0.0;
    for (final entry in groups.entries) {
      if (entry.key == 'unknown') continue;
      final score = _recurrenceScore(entry.value.map((i) => rows[i]).toList());
      if (score > bestScore) {
        bestScore = score;
        bestKey = entry.key;
      }
    }

    final chosen = <int>{...forced, ...worded};
    String reason;
    if (bestKey != null && bestScore >= 2) {
      chosen.addAll(groups[bestKey]!);
      final months = _distinctMonths(groups[bestKey]!.map((i) => rows[i]));
      reason =
          'A similar credit from ${rows[groups[bestKey]!.first].counterparty} '
          'arrived in $months different months.';
    } else if (worded.isNotEmpty) {
      reason = 'The bank narration says salary.';
    } else if (forced.isNotEmpty) {
      reason = 'You marked these credits as salary.';
    } else {
      return SalaryVerdict.none;
    }
    if (forced.isNotEmpty && chosen.length > forced.length) {
      reason = '$reason Your own choices are applied too.';
    }
    chosen.removeAll(banned);
    if (chosen.isEmpty) return SalaryVerdict.none;

    final amounts = chosen.map((i) => rows[i].creditPaise).toList()..sort();
    return SalaryVerdict(
      rowIndexes: chosen,
      payer: bestKey == null ? null : rows[groups[bestKey]!.first].counterparty,
      reason: reason,
      typicalPaise: amounts[amounts.length ~/ 2],
    );
  }

  /// The same employer every month, however SBI wrapped the name: letters
  /// only, company suffixes dropped, first ten characters ("ACME SOFTWARE PV T"
  /// and "ACME SOFTWARE PVT" are one payer).
  static String payerKey(String? counterparty) {
    if (counterparty == null) return 'unknown';
    var key = counterparty.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    key = key.replaceAll(RegExp(r'(?:pvt|private|ltd|limited|llp|india)+$'), '');
    if (key.length < 3) return 'unknown';
    return key.length > 10 ? key.substring(0, 10) : key;
  }

  bool _couldBeSalary(StatementKind kind) => switch (kind) {
    StatementKind.salary ||
    StatementKind.otherCredit ||
    StatementKind.fromPerson => true,
    _ => false,
  };

  /// 0 for a one-off. Otherwise about the number of months it recurs in,
  /// discounted when the gaps are not monthly or the amounts are erratic.
  double _recurrenceScore(List<StatementRow> rows) {
    final months = _distinctMonths(rows);
    if (months < 2) return 0;
    rows.sort((a, b) => a.date.compareTo(b.date));
    var monthlyGaps = 0;
    var gaps = 0;
    for (var i = 1; i < rows.length; i++) {
      final days = rows[i].date.difference(rows[i - 1].date).inDays;
      if (days < 10) continue; // A bonus or arrears inside the same cycle.
      gaps++;
      if (days >= 24 && days <= 38) monthlyGaps++;
    }
    if (gaps == 0) return 0;
    final cadence = monthlyGaps / gaps;

    // Steadiness of each month's main credit: a reimbursement five days after
    // payday or a 30 % bonus month must not make a salary look erratic.
    final monthly = <int, int>{};
    for (final r in rows) {
      final month = r.date.year * 12 + r.date.month;
      if ((monthly[month] ?? 0) < r.creditPaise) monthly[month] = r.creditPaise;
    }
    final amounts = monthly.values.toList()..sort();
    final median = amounts[amounts.length ~/ 2];
    final steady = amounts
            .where((a) => (a - median).abs() <= median * 0.35)
            .length /
        amounts.length;

    return months * cadence * steady;
  }

  int _distinctMonths(Iterable<StatementRow> rows) =>
      rows.map((r) => r.date.year * 12 + r.date.month).toSet().length;
}

/// One salary-to-salary window.
class SalaryCycle {
  SalaryCycle({
    required this.start,
    required this.end,
    required this.isPartial,
    required this.rows,
  });

  /// Day the salary landed (or the statement's first day for the stretch
  /// before the first salary).
  final DateTime start;

  /// Day the next salary landed (exclusive), or the statement's last day + 1
  /// for the cycle still running.
  final DateTime end;

  /// True when the window is not a full salary-to-salary cycle: the stretch
  /// before the first salary, or the cycle the statement ends inside.
  final bool isPartial;

  final List<StatementRow> rows;

  /// Filled by [SalaryCycleBuilder] for rows that are salary.
  final Set<StatementRow> salaryRows = {};

  int get days => end.difference(start).inDays;

  int _sum(bool Function(StatementRow r) test, {bool debit = true}) => rows
      .where(test)
      .fold(0, (sum, r) => sum + (debit ? r.debitPaise : r.creditPaise));

  int get salaryPaise =>
      salaryRows.fold(0, (sum, r) => sum + r.creditPaise);

  /// Interest and unnamed credits. Unnamed credits are reported but never
  /// called income in the copy.
  int get otherInPaise => _sum(
    (r) =>
        !r.isDebit &&
        !salaryRows.contains(r) &&
        (r.kind == StatementKind.interest || r.kind == StatementKind.otherCredit),
    debit: false,
  );

  int get refundsPaise => _sum(
    (r) =>
        !r.isDebit &&
        (r.kind == StatementKind.refund || r.kind == StatementKind.cashback),
    debit: false,
  );

  /// Consumption: merchants, people, fees, unnamed debits — net of refunds.
  int get spentPaise =>
      _sum((r) => r.isDebit && r.kind.isSpend) - refundsPaise;

  int get cardBillsPaise => _sum((r) => r.isDebit && r.kind == StatementKind.cardBill);
  int get cashPaise => _sum((r) => r.isDebit && r.kind == StatementKind.cash);
  int get loanPaise => _sum((r) => r.isDebit && r.kind == StatementKind.loan);
  int get investedPaise =>
      _sum((r) => r.isDebit && r.kind == StatementKind.investment);

  /// Money that left for good this cycle. Investments and own-account moves
  /// are not "out": the money is still the user's.
  int get outPaise => spentPaise + cardBillsPaise + cashPaise + loanPaise;

  /// Salary plus other income minus everything that left. Negative when the
  /// cycle ran on savings.
  int get leftPaise => salaryPaise + otherInPaise - outPaise;

  /// Spend by category name, largest first. Refunds are netted into the
  /// category of the matching merchant when the categoriser placed them there.
  List<MapEntry<String, int>> get spendByCategory {
    final totals = <String, int>{};
    for (final r in rows) {
      if (r.isDebit && r.kind.isSpend) {
        final name = r.kind == StatementKind.toPerson
            ? 'Sent to people'
            : r.kind == StatementKind.charges
            ? 'Bank charges'
            : r.categoryName;
        totals.update(name, (v) => v + r.debitPaise, ifAbsent: () => r.debitPaise);
      }
    }
    for (final r in rows) {
      if (!r.isDebit &&
          (r.kind == StatementKind.refund || r.kind == StatementKind.cashback)) {
        final name = totals.containsKey(r.categoryName) ? r.categoryName : null;
        if (name != null) {
          totals.update(name, (v) => v - r.creditPaise);
        } else {
          totals.update(
            'Refunds',
            (v) => v - r.creditPaise,
            ifAbsent: () => -r.creditPaise,
          );
        }
      }
    }
    return totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }
}

class SalaryCycleBuilder {
  const SalaryCycleBuilder();

  /// Cycles newest first. Without any salary, one partial cycle covers the
  /// whole statement so the categories still render.
  List<SalaryCycle> build(
    List<StatementRow> rows,
    SalaryVerdict verdict, {
    DateTime? periodFrom,
    DateTime? periodTo,
  }) {
    if (rows.isEmpty) return const [];
    final sorted = [...rows]..sort((a, b) => a.date.compareTo(b.date));
    final first = periodFrom ?? sorted.first.date;
    final lastDay = periodTo ?? sorted.last.date;
    final end = DateTime(lastDay.year, lastDay.month, lastDay.day + 1);
    final salaryRows = {for (final i in verdict.rowIndexes) rows[i]};

    // Anchors: salary days. A second credit within 15 days of an anchor is a
    // bonus or arrears inside the same cycle, not a new cycle.
    final anchors = <DateTime>[];
    for (final r in sorted.where(salaryRows.contains)) {
      final day = DateTime(r.date.year, r.date.month, r.date.day);
      if (anchors.isEmpty || day.difference(anchors.last).inDays > 15) {
        anchors.add(day);
      }
    }

    final cycles = <SalaryCycle>[];
    final starts = [
      if (anchors.isEmpty || first.isBefore(anchors.first)) first,
      ...anchors,
    ];
    for (var i = 0; i < starts.length; i++) {
      final start = starts[i];
      final stop = i + 1 < starts.length ? starts[i + 1] : end;
      final inWindow = sorted
          .where((r) => !r.date.isBefore(start) && r.date.isBefore(stop))
          .toList();
      if (inWindow.isEmpty) continue;
      final beforeFirstSalary = anchors.isEmpty || start.isBefore(anchors.first);
      final runningCycle = i == starts.length - 1;
      final cycle = SalaryCycle(
        start: start,
        end: stop,
        isPartial: beforeFirstSalary || runningCycle,
        rows: inWindow,
      );
      cycle.salaryRows.addAll(inWindow.where(salaryRows.contains));
      cycles.add(cycle);
    }
    return cycles.reversed.toList();
  }
}

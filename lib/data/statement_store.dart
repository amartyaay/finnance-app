import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/enums.dart';
import '../domain/statement.dart';
import '../engine/salary_cycles.dart';
import '../engine/statement_merge.dart';
import '../services/statement/statement_classifier.dart';
import 'app_database.dart';

/// One imported account, for the statements screen.
class StatementAccount {
  const StatementAccount({
    required this.accountKey,
    required this.bank,
    required this.accountMask,
    required this.holderName,
    required this.from,
    required this.to,
    required this.files,
    required this.rows,
    required this.verified,
  });

  final String accountKey;
  final String bank;
  final String? accountMask;
  final String? holderName;
  final DateTime? from;
  final DateTime? to;
  final int files;
  final int rows;
  final int verified;
}

/// What an import changed.
class StatementImportResult {
  const StatementImportResult({
    required this.added,
    required this.alreadyKnown,
    required this.sameFile,
  });

  /// New rows stored.
  final int added;

  /// Rows an earlier, overlapping statement had already stored.
  final int alreadyKnown;

  /// The exact file was imported before; nothing changed.
  final bool sameFile;
}

/// Persistence for imported bank statements. Never touches the SMS ledger:
/// the two sources are kept apart so a statement can never double count an
/// SMS row (they are reconciled for display, not merged into one table).
class StatementStore {
  StatementStore({AppDatabase? database, DateTime Function()? now})
    : _db = database ?? AppDatabase(),
      _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;
  static const _classifier = StatementClassifier();

  Future<StatementImportResult> save(
    BankStatement statement, {
    required String fileHash,
  }) async {
    final db = await _db.database;
    final existing = await db.query(
      'statements',
      columns: const ['id'],
      where: 'file_hash = ?',
      whereArgs: [fileHash],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return const StatementImportResult(
        added: 0,
        alreadyKnown: 0,
        sameFile: true,
      );
    }

    return db.transaction((txn) async {
      final id = await txn.insert('statements', {
        'file_hash': fileHash,
        'bank': statement.bank,
        'account_key': statement.accountKey,
        'account_mask': statement.accountMask,
        'holder_name': statement.holderName,
        'period_from': statement.periodFrom?.millisecondsSinceEpoch,
        'period_to': statement.periodTo?.millisecondsSinceEpoch,
        'opening_paise': statement.openingBalancePaise,
        'closing_paise': statement.closingBalancePaise,
        'rows_total': statement.rows.length,
        'rows_verified': statement.verifiedRows,
        'imported_at': _now().millisecondsSinceEpoch,
      });
      var added = 0;
      var known = 0;
      for (final row in statement.rows) {
        final inserted = await txn.insert('statement_rows', {
          'row_key': row.identity(statement.accountKey),
          'statement_id': id,
          'account_key': statement.accountKey,
          'txn_date': row.date.millisecondsSinceEpoch,
          'description': row.description,
          'reference': row.reference,
          'debit_paise': row.debitPaise,
          'credit_paise': row.creditPaise,
          'balance_paise': row.balancePaise,
          'verified': row.balanceVerified ? 1 : 0,
          'kind': row.kind.name,
          'counterparty': row.counterparty,
          'category_name': row.categoryName,
          'category_kind': row.categoryKind.name,
          'salary_override': null,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (inserted > 0) {
          added++;
        } else {
          known++;
        }
      }
      return StatementImportResult(
        added: added,
        alreadyKnown: known,
        sameFile: false,
      );
    });
  }

  Future<List<StatementAccount>> accounts() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT s.account_key, s.bank, s.account_mask, s.holder_name,
             MIN(r.txn_date) AS first_date, MAX(r.txn_date) AS last_date,
             COUNT(DISTINCT s.id) AS files, COUNT(r.id) AS row_count,
             SUM(r.verified) AS verified
      FROM statements s JOIN statement_rows r ON r.statement_id = s.id
      GROUP BY s.account_key
      ORDER BY last_date DESC
    ''');
    DateTime? date(Object? ms) =>
        ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms as int);
    return [
      for (final r in rows)
        StatementAccount(
          accountKey: r['account_key'] as String,
          bank: r['bank'] as String,
          accountMask: r['account_mask'] as String?,
          holderName: r['holder_name'] as String?,
          from: date(r['first_date']),
          to: date(r['last_date']),
          files: r['files'] as int,
          rows: r['row_count'] as int,
          verified: (r['verified'] as int?) ?? 0,
        ),
    ];
  }

  Future<List<StatementRow>> rows(String accountKey) async {
    final db = await _db.database;
    final rows = await db.query(
      'statement_rows',
      where: 'account_key = ?',
      whereArgs: [accountKey],
      orderBy: 'txn_date ASC, id ASC',
    );
    final holderRow = await db.query(
      'statements',
      columns: const ['holder_name'],
      where: 'account_key = ? AND holder_name IS NOT NULL',
      whereArgs: [accountKey],
      limit: 1,
    );
    final holder = holderRow.isEmpty
        ? null
        : holderRow.first['holder_name'] as String?;
    // Rows are re-read through the current classifier, so a rule added after
    // the import (own FDs, a card bill paid via PhonePe) applies without
    // re-importing. A category is replaced only when the kind changed; a
    // category the user picked on an unchanged row stays.
    final rules = await payeeRules();
    StatementRow fresh(StatementRow stored) {
      final next = _classifier.classify(stored, holderName: holder);
      final row = next.kind == stored.kind
          ? stored.copyWith(counterparty: next.counterparty)
          : next.copyWith(isSalaryOverride: stored.isSalaryOverride);
      final rule = PayeeRule.matching(rules, row);
      if (rule == null) return row;
      // A payment the user named (rent to a person) is spending in that
      // category; a payee rule never turns a credit into spend.
      return row.copyWith(
        kind: row.isDebit && rule.kind != SpendCategoryKind.transfers
            ? StatementKind.spend
            : row.kind,
        categoryName: rule.categoryName,
        categoryKind: rule.kind,
      );
    }

    return [
      for (final r in rows)
        fresh(
          StatementRow(
            key: r['row_key'] as String,
            date: DateTime.fromMillisecondsSinceEpoch(r['txn_date'] as int),
            description: r['description'] as String,
            reference: r['reference'] as String?,
            debitPaise: r['debit_paise'] as int,
            creditPaise: r['credit_paise'] as int,
            balancePaise: r['balance_paise'] as int?,
            balanceVerified: r['verified'] == 1,
            kind: StatementKind.values.byName(r['kind'] as String),
            counterparty: r['counterparty'] as String?,
            categoryName: r['category_name'] as String,
            categoryKind: SpendCategoryKind.values.byName(
              r['category_kind'] as String,
            ),
            isSalaryOverride: switch (r['salary_override']) {
              1 => true,
              0 => false,
              _ => null,
            },
          ),
        ),
    ];
  }

  /// The days each imported account is covered by a statement: from the
  /// earliest statement period start to the latest period end (row dates
  /// when a file printed no period).
  Future<List<StatementCoverage>> coverage() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT s.account_key, s.bank, s.account_mask,
             MIN(COALESCE(s.period_from, r.txn_date)) AS first_date,
             MAX(COALESCE(s.period_to, r.txn_date)) AS last_date
      FROM statements s JOIN statement_rows r ON r.statement_id = s.id
      GROUP BY s.account_key
    ''');
    return [
      for (final r in rows)
        StatementCoverage(
          accountKey: r['account_key'] as String,
          bank: r['bank'] as String,
          accountMask: r['account_mask'] as String?,
          from: DateTime.fromMillisecondsSinceEpoch(r['first_date'] as int),
          to: DateTime.fromMillisecondsSinceEpoch(r['last_date'] as int),
        ),
    ];
  }

  /// Every account's rows for the ledger, with the salary verdict applied:
  /// a credit the detector (or the user) calls salary is booked as salary.
  Future<Map<String, List<StatementRow>>> ledgerRows() async {
    final out = <String, List<StatementRow>>{};
    for (final c in await coverage()) {
      final sorted = await rows(c.accountKey);
      final verdict = const SalaryDetector().detect(sorted);
      out[c.accountKey] = [
        for (var i = 0; i < sorted.length; i++)
          verdict.rowIndexes.contains(i) &&
                  sorted[i].kind != StatementKind.salary
              ? sorted[i].copyWith(
                  kind: StatementKind.salary,
                  categoryName: 'Income',
                )
              : sorted[i].isSalaryOverride == false &&
                    sorted[i].kind == StatementKind.salary
              ? sorted[i].copyWith(kind: StatementKind.otherCredit)
              : sorted[i],
      ];
    }
    return out;
  }

  /// Rules the user made by categorising one statement payment: "payments to
  /// BANOTH from 30 Apr are Rent". Kept in `app_meta` as JSON.
  Future<List<PayeeRule>> payeeRules() async {
    final db = await _db.database;
    final rows = await db.query(
      'app_meta',
      where: 'key = ?',
      whereArgs: [_payeeRulesKey],
      limit: 1,
    );
    if (rows.isEmpty) return const [];
    try {
      final list = jsonDecode(rows.first['value'] as String) as List<dynamic>;
      return [
        for (final item in list)
          PayeeRule.fromJson(item as Map<String, dynamic>),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Categorises every payment to [payee] from [from] on (this one and later
  /// ones), replacing an earlier rule for the same payee and start.
  Future<void> addPayeeRule(PayeeRule rule) async {
    final rules = [
      for (final r in await payeeRules())
        if (!(r.payee == rule.payee && r.fromMs == rule.fromMs)) r,
      rule,
    ];
    final db = await _db.database;
    await db.insert('app_meta', {
      'key': _payeeRulesKey,
      'value': jsonEncode([for (final r in rules) r.toJson()]),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static const _payeeRulesKey = 'statement_payee_rules';

  /// The counterparty and date of a stored row, for making a payee rule.
  Future<({String? payee, DateTime date})?> rowPayee(String rowKey) async {
    final db = await _db.database;
    final rows = await db.query(
      'statement_rows',
      columns: const ['counterparty', 'txn_date'],
      where: 'row_key = ?',
      whereArgs: [rowKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (
      payee: rows.first['counterparty'] as String?,
      date: DateTime.fromMillisecondsSinceEpoch(rows.first['txn_date'] as int),
    );
  }

  /// "This is / is not my salary"; null clears the choice.
  Future<void> setSalaryOverride(String rowKey, bool? isSalary) async {
    final db = await _db.database;
    await db.update(
      'statement_rows',
      {'salary_override': isSalary == null ? null : (isSalary ? 1 : 0)},
      where: 'row_key = ?',
      whereArgs: [rowKey],
    );
  }

  Future<void> setCategory(
    String rowKey,
    String name,
    SpendCategoryKind kind,
  ) async {
    final db = await _db.database;
    await db.update(
      'statement_rows',
      {'category_name': name, 'category_kind': kind.name},
      where: 'row_key = ?',
      whereArgs: [rowKey],
    );
  }

  /// Forgets an account's imported statements entirely.
  Future<void> deleteAccount(String accountKey) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete(
        'statement_rows',
        where: 'account_key = ?',
        whereArgs: [accountKey],
      );
      await txn.delete(
        'statements',
        where: 'account_key = ?',
        whereArgs: [accountKey],
      );
    });
  }
}

/// "Payments to [payee] from [fromMs] on are [categoryName]". The newest
/// rule that has started wins, so rent can move to a new landlord.
class PayeeRule {
  const PayeeRule({
    required this.payee,
    required this.categoryName,
    required this.kind,
    this.fromMs,
  });

  /// Upper-cased counterparty as the statement prints it ("BANOTH").
  final String payee;
  final String categoryName;
  final SpendCategoryKind kind;
  final int? fromMs;

  factory PayeeRule.fromJson(Map<String, dynamic> json) => PayeeRule(
    payee: json['payee'] as String,
    categoryName: json['category'] as String,
    kind: SpendCategoryKind.values.byName(json['kind'] as String),
    fromMs: json['from'] as int?,
  );

  Map<String, Object?> toJson() => {
    'payee': payee,
    'category': categoryName,
    'kind': kind.name,
    'from': fromMs,
  };

  static PayeeRule? matching(List<PayeeRule> rules, StatementRow row) {
    final payee = row.counterparty?.trim().toUpperCase();
    if (payee == null || payee.isEmpty) return null;
    PayeeRule? best;
    for (final rule in rules) {
      if (rule.payee != payee) continue;
      if (rule.fromMs != null &&
          row.date.millisecondsSinceEpoch < rule.fromMs!) {
        continue;
      }
      if (best == null || (rule.fromMs ?? 0) > (best.fromMs ?? 0)) best = rule;
    }
    return best;
  }
}

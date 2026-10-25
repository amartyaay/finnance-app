import 'package:sqflite/sqflite.dart';

import '../domain/enums.dart';
import '../domain/statement.dart';
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
      return const StatementImportResult(added: 0, alreadyKnown: 0, sameFile: true);
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
      return StatementImportResult(added: added, alreadyKnown: known, sameFile: false);
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
    return [
      for (final r in rows)
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
          categoryKind: SpendCategoryKind.values.byName(r['category_kind'] as String),
          isSalaryOverride: switch (r['salary_override']) {
            1 => true,
            0 => false,
            _ => null,
          },
        ),
    ];
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
      await txn.delete('statement_rows', where: 'account_key = ?', whereArgs: [accountKey]);
      await txn.delete('statements', where: 'account_key = ?', whereArgs: [accountKey]);
    });
  }
}

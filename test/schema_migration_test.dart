// Schema contract: a v7 database must upgrade to v8 without losing a row.
//
// Running the real sqflite plugin needs Android, and the FFI test harness is not
// available offline in this project, so this test drives the *actual* migration
// methods (`AppDatabase.ensureSchema` / `upgradeSchema`) against a recording
// `Database` that starts with the v7 column set. It proves the two properties
// that matter:
//
//   1. the migration is additive — no DROP, no DELETE of ledger rows;
//   2. it is idempotent — a second open issues no further ALTER TABLE.
//
// The v8 columns and the negative-rule table are asserted explicitly.

import 'package:finnance_app/data/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

/// Minimal recording stand-in for sqflite's [Database].
///
/// Only the calls the migration makes are implemented; everything else throws
/// through the default `noSuchMethod`.
class _RecordingDatabase implements Database {
  _RecordingDatabase(Map<String, Set<String>> columns)
    : columns = {
        for (final entry in columns.entries) entry.key: {...entry.value},
      };

  /// table -> existing column names (mutated by recorded ALTERs).
  final Map<String, Set<String>> columns;

  /// Every SQL statement, in order.
  final List<String> statements = [];

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    statements.add(sql);
    final alter = RegExp(
      r'ALTER\s+TABLE\s+(\w+)\s+ADD\s+COLUMN\s+(\w+)',
      caseSensitive: false,
    ).firstMatch(sql);
    if (alter != null) {
      columns.putIfAbsent(alter.group(1)!, () => <String>{}).add(alter.group(2)!);
    }
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final pragma = RegExp(
      r'PRAGMA\s+table_info\((\w+)\)',
      caseSensitive: false,
    ).firstMatch(sql);
    if (pragma == null) return const [];
    final table = columns[pragma.group(1)!] ?? const <String>{};
    return [
      for (final name in table) {'name': name},
    ];
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unexpected Database call: ${invocation.memberName}');
}

/// The v7 shape this app actually shipped (`transactions` without
/// `amount_score`, `merchant_rules` without its new metadata).
Map<String, Set<String>> _v7Columns() => {
  'transactions': {
    'id',
    'dedupe_key',
    'sms_id',
    'occurred_at',
    'amount_paise',
    'kind',
    'instrument',
    'sender',
    'merchant',
    'vpa',
    'category_id',
    'category_name',
    'category_source',
    'category_kind',
    'transfer_reason',
    'card_key',
    'last4',
    'issuer',
    'reference_id',
    'balance_after',
    'available_limit',
    'confidence',
    'source_type',
    'duplicate_of',
    'needs_review',
    'raw_body',
    'created_at',
  },
  'merchant_rules': {'pattern', 'category_name', 'category_kind', 'hits'},
  'sms_messages': {
    'id',
    'sender',
    'body',
    'received_at',
    'sender_normalized',
    'class',
    'score',
    'processed',
  },
  'cards': {
    'id',
    'issuer',
    'last4',
    'label',
    'credit_limit',
    'statement_day',
    'due_day',
    'is_active',
    'created_at',
  },
  'card_bills': {
    'id',
    'card_key',
    'total_due',
    'min_due',
    'due_date',
    'statement_date',
    'created_at',
  },
  'pending_categories': {'sms_id', 'category_name', 'created_at'},
  'categories': {'id', 'name', 'kind', 'is_default', 'created_at'},
  'app_meta': {'key', 'value'},
};

void main() {
  group('schema v8', () {
    test('is at least the v8 schema that carries the learning loop', () {
      // The tree may move past v8 (another feature can add a v9), but the v8
      // contract below must always hold: the columns/tables this feature needs
      // are created and migrated additively.
      expect(AppDatabase.schemaVersion, greaterThanOrEqualTo(8));
    });

    test('a v7 database gains the v8 columns and table, additively', () async {
      final db = _RecordingDatabase(_v7Columns());
      await AppDatabase().upgradeSchema(db, 7, 8);

      expect(db.columns['transactions'], contains('amount_score'));
      expect(
        db.columns['merchant_rules'],
        containsAll(['sample_merchant', 'created_at', 'last_used_at']),
      );
      expect(
        db.statements.join('\n'),
        contains('CREATE TABLE IF NOT EXISTS excluded_shapes'),
      );

      // The review flag is recomputed for old rows; the ledger itself is never
      // touched by a destructive statement.
      expect(
        db.statements.join('\n'),
        contains('UPDATE transactions SET needs_review = 1'),
      );
      final destructive = db.statements.where(
        (sql) =>
            RegExp(r'^\s*DROP\b', caseSensitive: false).hasMatch(sql) ||
            RegExp(
              r'^\s*DELETE\s+FROM\s+transactions\b',
              caseSensitive: false,
            ).hasMatch(sql),
      );
      expect(destructive, isEmpty);
    });

    test('re-running the migration is a no-op for the schema', () async {
      final db = _RecordingDatabase(_v7Columns());
      await AppDatabase().upgradeSchema(db, 7, 8);
      final firstAlters = db.statements
          .where((sql) => sql.contains('ALTER TABLE'))
          .length;
      expect(firstAlters, greaterThan(0));

      db.statements.clear();
      await AppDatabase().upgradeSchema(db, 7, 8);
      expect(
        db.statements.where((sql) => sql.contains('ALTER TABLE')),
        isEmpty,
        reason: 'a partially upgraded database must not re-add columns',
      );
      // The review backfill is idempotent by predicate and may run again.
      expect(
        db.statements.join('\n'),
        contains('UPDATE transactions SET needs_review = 1'),
      );
    });

    test('a v6 database also gains the v7 sender column', () async {
      final columns = _v7Columns();
      columns['transactions'] = {...columns['transactions']!}..remove('sender');
      final db = _RecordingDatabase(columns);
      await AppDatabase().upgradeSchema(db, 6, 8);

      expect(db.columns['transactions'], contains('sender'));
      expect(db.columns['transactions'], contains('amount_score'));
      expect(
        db.statements.join('\n'),
        contains('CREATE TABLE IF NOT EXISTS excluded_shapes'),
      );
    });
  });
}

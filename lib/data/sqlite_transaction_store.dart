import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/transaction_models.dart';
import 'transaction_store.dart';

class SqliteTransactionStore implements TransactionStore {
  SqliteTransactionStore({this.databaseName = 'finance_sms_mvp.db'});

  final String databaseName;

  Database? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

    final databasesPath = await getDatabasesPath();
    final database = await openDatabase(
      p.join(databasesPath, databaseName),
      version: 5,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
      onOpen: _ensureDefaultCategories,
    );
    _database = database;
    return database;
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_sms_id TEXT NOT NULL UNIQUE,
        sender TEXT NOT NULL,
        normalized_sender TEXT NOT NULL,
        timestamp_millis INTEGER NOT NULL,
        amount_paise INTEGER NOT NULL,
        direction TEXT NOT NULL,
        instrument TEXT NOT NULL,
        account_hint TEXT,
        merchant TEXT,
        reference_id TEXT,
        card_issuer TEXT,
        card_last_digits TEXT,
        source_type TEXT NOT NULL DEFAULT 'sms',
        source_label TEXT,
        import_batch_id TEXT,
        confidence REAL NOT NULL,
        category_id INTEGER,
        category_name TEXT,
        classified_at_millis INTEGER,
        created_at_millis INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX transactions_timestamp_idx
      ON transactions(timestamp_millis DESC)
    ''');
    await db.execute('''
      CREATE INDEX transactions_reference_idx
      ON transactions(reference_id)
    ''');
    await db.execute('''
      CREATE INDEX transactions_card_idx
      ON transactions(card_issuer, card_last_digits)
    ''');
    await db.execute('''
      CREATE INDEX transactions_import_batch_idx
      ON transactions(import_batch_id)
    ''');
    await db.execute('''
      CREATE TABLE app_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await _createCategoriesTable(db);
  }

  Future<void> _upgradeSchema(Database db, int oldVersion, int version) async {
    if (oldVersion < 2) {
      await _addColumnIfMissing(db, 'transactions', 'category_id', 'INTEGER');
      await _addColumnIfMissing(db, 'transactions', 'category_name', 'TEXT');
      await _addColumnIfMissing(
        db,
        'transactions',
        'classified_at_millis',
        'INTEGER',
      );
      await _createCategoriesTable(db);
    }
    if (oldVersion < 3) {
      await _addColumnIfMissing(db, 'transactions', 'reference_id', 'TEXT');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS transactions_reference_idx
        ON transactions(reference_id)
      ''');
    }
    if (oldVersion < 4) {
      await _addColumnIfMissing(db, 'transactions', 'card_issuer', 'TEXT');
      await _addColumnIfMissing(db, 'transactions', 'card_last_digits', 'TEXT');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS transactions_card_idx
        ON transactions(card_issuer, card_last_digits)
      ''');
    }
    if (oldVersion < 5) {
      await _addColumnIfMissing(
        db,
        'transactions',
        'source_type',
        "TEXT NOT NULL DEFAULT 'sms'",
      );
      await _addColumnIfMissing(db, 'transactions', 'source_label', 'TEXT');
      await _addColumnIfMissing(db, 'transactions', 'import_batch_id', 'TEXT');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS transactions_import_batch_idx
        ON transactions(import_batch_id)
      ''');
    }
  }

  Future<void> _createCategoriesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        normalized_name TEXT NOT NULL UNIQUE,
        is_default INTEGER NOT NULL,
        created_at_millis INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final hasColumn = columns.any((row) => row['name'] == column);
    if (!hasColumn) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  Future<void> _ensureDefaultCategories(Database db) async {
    final createdAtMillis = DateTime.now().millisecondsSinceEpoch;
    for (final category in defaultExpenseCategoryNames) {
      await db.insert('categories', {
        'name': category,
        'normalized_name': _normalizeCategoryName(category),
        'is_default': 1,
        'created_at_millis': createdAtMillis,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  @override
  Future<int> upsertTransactions(
    List<ParsedTransaction> transactions, {
    required DateTime createdAt,
  }) async {
    if (transactions.isEmpty) {
      return 0;
    }

    final db = await _db;
    final createdAtMillis = createdAt.millisecondsSinceEpoch;
    return db.transaction<int>((txn) async {
      var inserted = 0;
      for (final parsed in transactions) {
        if (await _hasDuplicateTransaction(txn, parsed)) {
          continue;
        }
        final row =
            parsed
                .toFinanceTransaction(createdAtMillis: createdAtMillis)
                .toMap()
              ..remove('id');
        final id = await txn.insert(
          'transactions',
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (id > 0) {
          inserted += 1;
        }
      }
      return inserted;
    });
  }

  @override
  Future<List<FinanceTransaction>> allTransactions() async {
    final db = await _db;
    final rows = await db.query(
      'transactions',
      orderBy: 'timestamp_millis DESC',
    );
    return rows.map(FinanceTransaction.fromMap).toList(growable: false);
  }

  @override
  Future<List<FinanceTransaction>> recentTransactions({int limit = 20}) async {
    final db = await _db;
    final rows = await db.query(
      'transactions',
      orderBy: 'timestamp_millis DESC',
      limit: limit,
    );
    return rows.map(FinanceTransaction.fromMap).toList(growable: false);
  }

  @override
  Future<List<FinanceTransaction>> uncategorizedTransactions({
    int limit = 10,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'transactions',
      where: 'category_id IS NULL AND direction = ?',
      whereArgs: [TransactionDirection.expense.name],
      orderBy: 'timestamp_millis DESC',
      limit: limit,
    );
    return rows.map(FinanceTransaction.fromMap).toList(growable: false);
  }

  @override
  Future<int> monthlySpendPaise(DateTime month) async {
    final db = await _db;
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount_paise), 0) AS total
      FROM transactions
      WHERE direction = ?
        AND timestamp_millis >= ?
        AND timestamp_millis < ?
      ''',
      [
        TransactionDirection.expense.name,
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
    );
    final total = rows.first['total'];
    if (total is int) {
      return total;
    }
    if (total is num) {
      return total.toInt();
    }
    return 0;
  }

  @override
  Future<List<CreditCardSummary>> creditCardSummaries(DateTime month) async {
    final db = await _db;
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final rows = await db.rawQuery(
      '''
      SELECT
        card_issuer,
        card_last_digits,
        MIN(timestamp_millis) AS first_seen_millis,
        MAX(timestamp_millis) AS last_seen_millis,
        COALESCE(SUM(
          CASE
            WHEN direction = ?
              AND timestamp_millis >= ?
              AND timestamp_millis < ?
            THEN amount_paise
            ELSE 0
          END
        ), 0) AS monthly_spend_paise,
        COUNT(*) AS transaction_count,
        AVG(confidence) AS confidence
      FROM transactions
      WHERE card_issuer IS NOT NULL
        AND card_issuer != ''
        AND card_last_digits IS NOT NULL
        AND card_last_digits != ''
      GROUP BY card_issuer, card_last_digits
      ORDER BY monthly_spend_paise DESC, last_seen_millis DESC
      ''',
      [
        TransactionDirection.expense.name,
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
    );
    return rows.map(CreditCardSummary.fromMap).toList(growable: false);
  }

  @override
  Future<List<ExpenseCategory>> categories() async {
    final db = await _db;
    final rows = await db.query(
      'categories',
      orderBy: 'is_default DESC, name COLLATE NOCASE ASC',
    );
    return rows.map(ExpenseCategory.fromMap).toList(growable: false);
  }

  @override
  Future<ExpenseCategory> addCategory(String name) async {
    final cleanedName = _cleanCategoryName(name);
    if (cleanedName.isEmpty) {
      throw ArgumentError('Category name cannot be empty.');
    }

    final db = await _db;
    final normalizedName = _normalizeCategoryName(cleanedName);
    await db.insert('categories', {
      'name': cleanedName,
      'normalized_name': normalizedName,
      'is_default': 0,
      'created_at_millis': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    final rows = await db.query(
      'categories',
      where: 'normalized_name = ?',
      whereArgs: [normalizedName],
      limit: 1,
    );
    return ExpenseCategory.fromMap(rows.first);
  }

  @override
  Future<void> assignCategory({
    required int transactionId,
    required ExpenseCategory category,
    required DateTime classifiedAt,
  }) async {
    final db = await _db;
    await db.update(
      'transactions',
      {
        'category_id': category.id,
        'category_name': category.name,
        'classified_at_millis': classifiedAt.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }

  @override
  Future<DateTime?> lastScanAt() async {
    final db = await _db;
    final rows = await db.query(
      'app_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_lastScanKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final millis = int.tryParse(rows.first['value'] as String);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  @override
  Future<void> saveLastScanAt(DateTime scannedAt) async {
    final db = await _db;
    await db.insert('app_meta', {
      'key': _lastScanKey,
      'value': scannedAt.millisecondsSinceEpoch.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> _hasDuplicateTransaction(
    DatabaseExecutor db,
    ParsedTransaction parsed,
  ) async {
    final sourceRows = await db.query(
      'transactions',
      columns: ['id'],
      where: 'source_sms_id = ?',
      whereArgs: [parsed.sourceSmsId],
      limit: 1,
    );
    if (sourceRows.isNotEmpty) {
      return true;
    }

    final referenceId = parsed.referenceId;
    if (referenceId != null && referenceId.length >= 6) {
      final referenceRows = await db.query(
        'transactions',
        columns: ['id'],
        where: 'reference_id = ? AND amount_paise = ?',
        whereArgs: [referenceId, parsed.amountPaise],
        limit: 1,
      );
      if (referenceRows.isNotEmpty) {
        return true;
      }
    }

    final merchantKey = _normalizeMatchText(parsed.merchantOrPayee);
    if (merchantKey.length < 3) {
      return false;
    }

    const duplicateWindowMillis = 2 * 60 * 1000;
    final rows = await db.query(
      'transactions',
      columns: ['normalized_sender', 'merchant'],
      where: '''
        amount_paise = ?
        AND direction = ?
        AND timestamp_millis BETWEEN ? AND ?
      ''',
      whereArgs: [
        parsed.amountPaise,
        parsed.direction.name,
        parsed.timestampMillis - duplicateWindowMillis,
        parsed.timestampMillis + duplicateWindowMillis,
      ],
    );

    for (final row in rows) {
      final existingSender = row['normalized_sender'] as String?;
      if (existingSender == parsed.normalizedSender) {
        continue;
      }

      final existingMerchant = _normalizeMatchText(row['merchant'] as String?);
      if (_similarMatchText(merchantKey, existingMerchant)) {
        return true;
      }
    }
    return false;
  }

  static const _lastScanKey = 'last_scan_at';
}

const defaultExpenseCategoryNames = [
  'Food',
  'Travel',
  'Lifestyle',
  'Education',
  'Bills',
];

String _cleanCategoryName(String name) {
  return name.trim().replaceAll(RegExp(r'\s+'), ' ');
}

String _normalizeCategoryName(String name) {
  return _cleanCategoryName(name).toLowerCase();
}

String _normalizeMatchText(String? value) {
  if (value == null) {
    return '';
  }
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '').trim();
}

bool _similarMatchText(String left, String right) {
  if (left.isEmpty || right.isEmpty) {
    return false;
  }
  if (left == right) {
    return true;
  }
  if (left.length < 5 || right.length < 5) {
    return false;
  }
  return left.contains(right) || right.contains(left);
}

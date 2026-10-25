import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Schema owner for the whole app.
///
/// v6 is a deliberate break from the original MVP: the Dart side now owns
/// `transactions` and the Kotlin receiver only appends raw messages to
/// `sms_messages`, so there is exactly **one** parser (this one) and no
/// Kotlin/Dart drift.
class AppDatabase {
  AppDatabase({this.fileName = 'finance_sms.db'});

  final String fileName;

  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, fileName),
      version: 7,
      onCreate: _create,
      onUpgrade: _upgrade,
      onOpen: (db) async {
        // Re-assert every table on open: a database created by an older build
        // must never leave the app half-working. Journal mode is left to
        // Android (WAL is the default for sqflite); PRAGMA cannot go through
        // `execute` because it returns a row.
        await _createCore(db);
      },
    );
    _db = db;
    return db;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _create(Database db, int version) async {
    await _createCore(db);
    await _seedCategories(db);
  }

  Future<void> _createCore(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sms_messages (
        id TEXT PRIMARY KEY,
        sender TEXT NOT NULL,
        body TEXT NOT NULL,
        received_at INTEGER NOT NULL,
        sender_normalized TEXT,
        class TEXT,
        score REAL,
        processed INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS sms_messages_processed_idx
      ON sms_messages(processed, received_at DESC)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dedupe_key TEXT NOT NULL UNIQUE,
        sms_id TEXT,
        occurred_at INTEGER NOT NULL,
        amount_paise INTEGER NOT NULL,
        kind TEXT NOT NULL,
        instrument TEXT NOT NULL,
        sender TEXT,
        merchant TEXT,
        vpa TEXT,
        category_id INTEGER,
        category_name TEXT,
        category_source TEXT NOT NULL DEFAULT 'none',
        category_kind TEXT NOT NULL DEFAULT 'other',
        transfer_reason TEXT NOT NULL DEFAULT 'none',
        card_key TEXT,
        last4 TEXT,
        issuer TEXT,
        reference_id TEXT,
        balance_after INTEGER,
        available_limit INTEGER,
        confidence REAL NOT NULL DEFAULT 0.5,
        source_type TEXT NOT NULL DEFAULT 'sms',
        duplicate_of TEXT,
        needs_review INTEGER NOT NULL DEFAULT 0,
        raw_body TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS txn_occurred_idx ON transactions(occurred_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS txn_category_idx ON transactions(category_kind)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS txn_card_idx ON transactions(card_key)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        issuer TEXT NOT NULL,
        last4 TEXT NOT NULL,
        label TEXT,
        credit_limit INTEGER,
        statement_day INTEGER,
        due_day INTEGER,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        UNIQUE(issuer, last4)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS card_bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        card_key TEXT NOT NULL,
        total_due INTEGER NOT NULL,
        min_due INTEGER,
        due_date INTEGER,
        statement_date INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_categories (
        sms_id TEXT PRIMARY KEY,
        category_name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL DEFAULT 'other',
        is_default INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS merchant_rules (
        pattern TEXT PRIMARY KEY,
        category_name TEXT NOT NULL,
        category_kind TEXT NOT NULL,
        hits INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    await _createCore(db);
    if (oldVersion < 7) {
      await _addColumnIfMissing(db, 'transactions', 'sender', 'TEXT');
    }
    if (oldVersion < 6) {
      // The MVP's tables used a different `transactions` shape. Keep the user's
      // history by copying what maps cleanly, then let re-parsing fill the rest.
      final columns = await db.rawQuery('PRAGMA table_info(transactions)');
      final names = columns.map((c) => c['name']).toSet();
      if (!names.contains('dedupe_key')) {
        await db.execute('ALTER TABLE transactions ADD COLUMN dedupe_key TEXT');
        await db.execute(
          "UPDATE transactions SET dedupe_key = 'legacy:' || id WHERE dedupe_key IS NULL",
        );
      }
      for (final entry in {
        'kind': "TEXT NOT NULL DEFAULT 'spend'",
        'category_kind': "TEXT NOT NULL DEFAULT 'other'",
        'category_source': "TEXT NOT NULL DEFAULT 'none'",
        'transfer_reason': "TEXT NOT NULL DEFAULT 'none'",
        'needs_review': 'INTEGER NOT NULL DEFAULT 0',
        'duplicate_of': 'TEXT',
      }.entries) {
        if (!names.contains(entry.key)) {
          await db.execute(
            'ALTER TABLE transactions ADD COLUMN ${entry.key} ${entry.value}',
          );
        }
      }
    }
    await _seedCategories(db);
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((row) => row['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  }

  Future<void> _seedCategories(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in defaultCategories.entries) {
      await db.insert(
        'categories',
        {
          'name': entry.key,
          'kind': entry.value,
          'is_default': 1,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Category seed shared with the categoriser.
  static const Map<String, String> defaultCategories = {
    'Food & dining': 'food',
    'Groceries': 'groceries',
    'Transport': 'transport',
    'Shopping': 'shopping',
    'Bills & utilities': 'bills',
    'Rent': 'rent',
    'Entertainment': 'entertainment',
    'Health': 'health',
    'Education': 'education',
    'Travel': 'travel',
    'Fuel': 'fuel',
    'Investments': 'investments',
    'Transfers': 'transfers',
    'Income': 'income',
    'Cash': 'cash',
    'Other': 'other',
  };
}

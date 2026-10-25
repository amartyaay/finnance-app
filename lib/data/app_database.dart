import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Schema owner for the whole app.
///
/// v6 was a deliberate break from the original MVP: the Dart side now owns
/// `transactions` and the Kotlin receiver only appends raw messages to
/// `sms_messages`, so there is exactly **one** parser (this one) and no
/// Kotlin/Dart drift.
///
/// v8 adds the learning loop without a destructive migration:
///   * `transactions.amount_score` — the score of the amount candidate that was
///     chosen, so the review rule survives after the body is gone;
///   * `merchant_rules` metadata (`sample_merchant`, `created_at`,
///     `last_used_at`) next to the existing `hits`;
///   * `excluded_shapes` — the "not a transaction" negative rules.
///
/// Every column is added through [_addColumnIfMissing] and every table through
/// `IF NOT EXISTS`, and [ensureSchema] re-runs on **every open**, so a database
/// from v6, v7 or a partially-upgraded build heals itself instead of leaving
/// the app half-working.
class AppDatabase {
  AppDatabase({
    this.fileName = 'finance_sms.db',
    DatabaseFactory? factory,
    String? directory,
  }) : _factory = factory,
       _directory = directory;

  final String fileName;

  /// Injected by tests (sqflite FFI); the app uses the global plugin factory.
  final DatabaseFactory? _factory;

  /// Injected by tests. The app resolves the platform databases directory.
  final String? _directory;

  static const int schemaVersion = 9;

  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final factory = _factory ?? databaseFactory;
    final dir = _directory ?? await factory.getDatabasesPath();
    final db = await factory.openDatabase(
      p.join(dir, fileName),
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: _create,
        onUpgrade: _upgrade,
        onOpen: (db) async {
          // Re-assert every table and every v8 column on open: a database
          // created by an older build must never leave the app half-working.
          // Journal mode is left to Android (WAL is the default for sqflite);
          // PRAGMA cannot go through `execute` because it returns a row.
          await ensureSchema(db);
        },
      ),
    );
    _db = db;
    return db;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _create(Database db, int version) async {
    await ensureSchema(db);
    await _seedCategories(db);
  }

  /// Creates or heals the whole schema.
  ///
  /// Public so the migration contract can be exercised by a test without a
  /// device: it only issues `CREATE ... IF NOT EXISTS` and guarded
  /// `ALTER TABLE ... ADD COLUMN`, so running it against any older shape is
  /// safe and repeatable. [database] calls it on every open.
  Future<void> ensureSchema(Database db) async {
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
        money_in_kind TEXT NOT NULL DEFAULT 'none',
        card_key TEXT,
        last4 TEXT,
        issuer TEXT,
        reference_id TEXT,
        balance_after INTEGER,
        available_limit INTEGER,
        confidence REAL NOT NULL DEFAULT 0.5,
        amount_score INTEGER,
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
    // v8 column: older rows keep NULL, which the review rule reads as "unknown
    // amount evidence" rather than as a weak candidate.
    await _addColumnIfMissing(db, 'transactions', 'amount_score', 'INTEGER');
    // v9 column: the money-in taxonomy (`MoneyInKind`). Rows written before it
    // read as `none` and are re-derived by the reparse path.
    await _addColumnIfMissing(
      db,
      'transactions',
      'money_in_kind',
      "TEXT NOT NULL DEFAULT 'none'",
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
    // One statement, one row: the same bill can arrive as a statement SMS and a
    // due reminder, and both must not double the "still due" figure. Older
    // builds could have written duplicates, so collapse them first — a unique
    // index that fails to create would leave the whole database unopened.
    await db.execute('''
      DELETE FROM card_bills WHERE id NOT IN (
        SELECT MIN(id) FROM card_bills
        GROUP BY card_key, total_due,
          COALESCE(due_date, 0), COALESCE(statement_date, 0)
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS card_bills_dedupe_idx
      ON card_bills(
        card_key, total_due,
        COALESCE(due_date, 0), COALESCE(statement_date, 0)
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

    // `pattern` is the normalised merchant signature (see
    // `MerchantSignature`) — the key the learning loop looks up on ingest.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS merchant_rules (
        pattern TEXT PRIMARY KEY,
        category_name TEXT NOT NULL,
        category_kind TEXT NOT NULL,
        hits INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _addColumnIfMissing(
      db,
      'merchant_rules',
      'sample_merchant',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'merchant_rules',
      'created_at',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(db, 'merchant_rules', 'last_used_at', 'INTEGER');

    // Negative rules: "this alert shape is not a transaction". Additive table,
    // so v6/v7 databases gain it on open.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS excluded_shapes (
        signature TEXT PRIMARY KEY,
        sender TEXT,
        merchant TEXT,
        amount_band TEXT NOT NULL DEFAULT 'unknown',
        amount_paise INTEGER,
        hits INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  /// Applies only additive migrations, then recomputes the v8 review flags.
  ///
  /// Exposed for the "a v7 database opens cleanly" contract test. There is no
  /// `DROP`, `DELETE` or column removal anywhere in here: an old ledger keeps
  /// every row it had.
  Future<void> upgradeSchema(Database db, int oldVersion, int newVersion) =>
      _upgrade(db, oldVersion, newVersion);

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    await ensureSchema(db);
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
    if (oldVersion < 8) {
      // Recompute the review flag with the v8 rule for rows written by older
      // builds. Only ever raises the flag — a row the user already cleared
      // stays cleared because `category_source = user` rows were resolved by
      // the action that cleared them. `amount_score` stays NULL for old rows
      // (the candidate score cannot be reconstructed), so that clause is
      // skipped rather than guessed.
      await db.execute('''
        UPDATE transactions SET needs_review = 1
        WHERE needs_review = 0 AND (
          confidence < 0.6 OR (
            kind = 'spend' AND (
              merchant IS NULL OR merchant = ''
            ) AND (
              vpa IS NULL OR vpa = ''
            )
          )
        )
      ''');
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

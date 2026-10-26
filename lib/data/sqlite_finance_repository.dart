import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/category_catalog.dart';
import '../domain/enums.dart';
import '../domain/hashing.dart';
import '../domain/inbox_store.dart';
import '../domain/merchant_rule.dart';
import '../domain/merchant_signature.dart';
import '../domain/sms_inbox.dart';
import '../domain/sms_message.dart';
import '../domain/transaction.dart';
import '../engine/card_metrics.dart';
import '../engine/dedupe_engine.dart';
import '../engine/merchant_learning.dart';
import '../engine/review_queue.dart';
import '../engine/statement_merge.dart';
import '../services/categorizer.dart';
import '../services/sms/sender_registry.dart';
import '../services/sms/sms_classifier.dart';
import '../services/sms/sms_model.dart';
import '../services/sms/transaction_extractor.dart';
import '../services/sms_reader.dart';
import 'app_database.dart';
import 'finance_repository.dart';
import 'statement_store.dart';

/// SQLite-backed repository: the real app.
///
/// Ownership: this class is the only writer of `transactions`. The Kotlin
/// receiver only appends to `sms_messages`, so parsing lives in one place.
class SqliteFinanceRepository implements FinanceRepository, InboxStore {
  final SmsModel? _injectedModel;

  /// Upper bound on one inbox read; the native side clamps to the same value.
  static const int maxInboxRead = 15000;

  SqliteFinanceRepository({
    AppDatabase? database,
    SmsInboxReader? reader,
    DateTime Function()? now,
    SmsClassifier? classifier,
    TransactionExtractor? extractor,
    Categorizer? categorizer,
    SmsModel? model,
  }) : _injectedModel = model,
       _db = database ?? AppDatabase(),
       _reader = reader ?? const ChannelSmsInboxReader(),
       _now = now ?? DateTime.now,
       _classifier = classifier ?? SmsClassifier(),
       _extractor = extractor ?? TransactionExtractor(),
       _categorizer = categorizer ?? const Categorizer();

  final AppDatabase _db;
  final SmsInboxReader _reader;
  final DateTime Function() _now;
  final SmsClassifier _classifier;
  final TransactionExtractor _extractor;
  final Categorizer _categorizer;
  final HomeDataBuilder _builder = HomeDataBuilder();
  final DedupeEngine _dedupe = const DedupeEngine();
  final MerchantLearning _learning = const MerchantLearning();
  final ReviewQueue _reviewQueue = const ReviewQueue();

  @override
  bool get isDemo => false;

  @override
  Future<HomeData> load() async {
    final db = await _db.database;
    final now = _now();
    final since = now.subtract(const Duration(days: 400));

    await _applyPendingCategories(db);
    // An upgrade (new parser rules or a new schema) must never leave the old
    // ledger on screen: re-derive it once, in the background of this load.
    await _ensureFreshDerivations(db);

    final txnRows = await db.query(
      'transactions',
      where: 'occurred_at >= ?',
      whereArgs: [since.millisecondsSinceEpoch],
      orderBy: 'occurred_at DESC',
    );
    final smsLedger = _dedupe.mark(txnRows.map(_txnFromRow).toList());
    // An imported bank statement is the record for its account and period;
    // SMS cover everything else (other banks, cards, the days since).
    var transactions = smsLedger;
    try {
      final statements = StatementStore(database: _db);
      final coverage = await statements.coverage();
      if (coverage.isNotEmpty) {
        transactions = const StatementMerge().merge(
          sms: smsLedger,
          coverage: coverage,
          rows: await statements.ledgerRows(),
        );
      }
    } on DatabaseException {
      // A statement table that cannot be read must not hide the SMS ledger.
      transactions = smsLedger;
    }

    final cardRows = await db.query('cards', orderBy: 'created_at ASC');
    final cards = cardRows.map(_cardFromRow).toList(growable: false);

    final billRows = await db.query('card_bills', orderBy: 'created_at DESC');
    final bills = billRows.map(_billFromRow).toList(growable: false);

    final categoryRows = await db.query('categories', orderBy: 'name ASC');
    final categories = categoryRows
        .map((row) => row['name'] as String)
        .toList(growable: false);

    // Re-assess recent suspicious messages so the "possible fraud" card is live.
    final suspiciousRows = await db.query(
      'sms_messages',
      where: "class IN ('phishing', 'unknown')",
      orderBy: 'received_at DESC',
      limit: 12,
    );
    final smsMessages = <SmsMessage>[];
    final assessments = <SmsAssessment>[];
    for (final row in suspiciousRows) {
      final message = SmsMessage(
        id: row['id'] as String,
        sender: row['sender'] as String,
        body: row['body'] as String,
        receivedAtMs: row['received_at'] as int,
      );
      smsMessages.add(message);
      assessments.add(_classifier.assess(message));
    }

    final lastScanRow = await db.query(
      'app_meta',
      where: 'key = ?',
      whereArgs: ['last_scan_at'],
      limit: 1,
    );
    final lastScanAt = lastScanRow.isEmpty
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(lastScanRow.first['value'] as String) ?? 0,
          );

    final smsCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM sms_messages'),
        ) ??
        0;

    // The review rule is re-applied to the stored rows on every load, not just
    // trusted from the `needs_review` column: a row written by an older build
    // (or before `amount_score` existed) must surface under the current rule.
    // The list is capped newest-first; the count is the full total for badges.
    final review = _reviewQueue.select(transactions);
    final reviewCount = _reviewQueue.count(transactions);

    return _builder.build(
      transactions: transactions,
      cards: cards,
      bills: bills,
      smsMessages: smsMessages,
      assessments: assessments,
      categories: categories,
      now: now,
      isDemo: false,
      lastScanAt: lastScanAt,
      smsRead: smsCount,
      needsReview: review,
      needsReviewCount: reviewCount,
    );
  }

  @override
  Future<IngestResult> ingest() async {
    final db = await _db.database;
    final now = _now();

    List<SmsMessage> incoming;
    try {
      // A year of history, uncapped in practice: salary cycles, recurring
      // payments and card statements need more than the newest 2 000 alerts
      // (the owner's phone holds 8 000+ messages over ~20 months). After the
      // one-time backfill only newer messages are read, with a two-day overlap
      // so a late-delivered SMS is not skipped (inserts ignore duplicates).
      final backfilled = await _meta(db, 'inbox_backfill') == '$maxInboxRead';
      final newest = Sqflite.firstIntValue(
        await db.rawQuery('SELECT MAX(received_at) FROM sms_messages'),
      );
      final since = (!backfilled || newest == null)
          ? now.subtract(const Duration(days: 400)).millisecondsSinceEpoch
          : newest - const Duration(days: 2).inMilliseconds;
      incoming = await _reader.readInbox(
        limit: maxInboxRead,
        sinceMillis: since,
      );
    } on UnsupportedError {
      rethrow;
    } on PlatformException catch (error) {
      if (error.code == 'permission_denied') throw const SmsPermissionMissing();
      rethrow;
    }

    // One batch, not one transaction per row: 8 000 single inserts take tens
    // of seconds on a phone.
    final batch = db.batch();
    for (final message in incoming) {
      batch.insert('sms_messages', {
        'id': message.id,
        'sender': message.sender,
        'body': message.body,
        'received_at': message.receivedAtMs,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
    await _setMeta(db, 'inbox_backfill', '$maxInboxRead');

    final result = await _processPending(db, now);
    await _writeParserVersion(db);

    return IngestResult(
      smsRead: incoming.length,
      transactionsFound: result.found,
      duplicatesMerged: result.merged,
      phishingFound: result.phishing,
    );
  }

  /// Parses the messages the SMS receiver stored since the last scan,
  /// without reading the inbox: the 10 pm background run has no activity to
  /// read it through, but the receiver has already saved every new alert.
  Future<void> processStored() async {
    final db = await _db.database;
    await _processPending(db, _now());
  }

  /// Parses every pending message into the ledger. Shared by [ingest] and
  /// [reparseAll] so the two paths can never drift.
  Future<({int found, int merged, int phishing})> _processPending(
    Database db,
    DateTime now,
  ) async {
    final pending = await db.query(
      'sms_messages',
      where: 'processed = 0',
      orderBy: 'received_at ASC',
    );

    final model = await _secondOpinion();
    // Learned state is read once per scan and matched in memory: 2 000 alerts
    // against a handful of rules must not become 2 000 queries on a phone.
    final rules = await _loadMerchantRules(db);
    final excluded = await _loadExcludedShapes(db);
    final ruleHits = <String, int>{};
    final exclusionHits = <String, int>{};

    var found = 0;
    var phishing = 0;
    for (final row in pending) {
      final message = SmsMessage(
        id: row['id'] as String,
        sender: row['sender'] as String,
        body: row['body'] as String,
        receivedAtMs: row['received_at'] as int,
      );
      final assessment = _classifier.assess(message);
      final sender = SmsSenderResolver(_classifier).resolve(message);

      if (assessment.isPhishing) phishing++;

      if (assessment.isTransaction) {
        final txn = _extractor.extract(message, sender);
        if (txn != null) {
          // A negative rule ("this is not a transaction") is checked before the
          // row is written, so a re-scan of the same alert shape cannot bring
          // it back.
          final exclusion = _learning.exclusionFor(txn);
          if (excluded.contains(exclusion)) {
            exclusionHits.update(exclusion, (v) => v + 1, ifAbsent: () => 1);
          } else {
            final rule = _learning.match(rules, txn);
            final category = rule == null
                ? _categorizer.categorize(
                    txn.merchant,
                    kind: txn.kind,
                    transferReason: txn.transferReason,
                  )
                : (name: rule.categoryName, kind: rule.categoryKind);
            if (rule != null) {
              ruleHits.update(rule.signature, (v) => v + 1, ifAbsent: () => 1);
              rules[rule.signature] = rule.withHit(
                atMs: now.millisecondsSinceEpoch,
              );
            }
            final id = await db.insert(
              'transactions',
              _txnToRow(
                txn.copyWith(
                  categoryName: category.name,
                  categoryKind: category.kind,
                  categorySource: rule == null
                      ? CategorySource.rule
                      : CategorySource.learned,
                ),
                createdAt: now,
              ),
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            if (id > 0) found++;
            // Only a *card* key may mint a card. Rows carry `card_key` only
            // when the alert named a card (see `_extractCardLast4`), so an
            // `A/c XX1234` can no longer become a phantom credit card.
            if (txn.cardKey != null) {
              final parts = txn.cardKey!.split('|');
              if (parts.length == 2 && parts[1].isNotEmpty) {
                await _ensureCard(
                  db,
                  parts[0],
                  parts[1],
                  now,
                  availableLimitPaise: txn.availableLimitPaise,
                  amountPaise: txn.amountPaise,
                  isSpend: txn.kind == TxnKind.spend,
                );
              }
            }
          }
        }
      }

      // A statement/due SMS is *informational*, not a transaction — the bill
      // parser must run for it anyway, or `card_bills` stays empty forever.
      final bill = _extractor.billNotice(message, sender);
      if (bill != null) {
        final parts = bill.cardKey.split('|');
        if (parts.length == 2 && parts[1].isNotEmpty) {
          await _ensureCard(db, parts[0], parts[1], now);
        }
        await db.insert('card_bills', {
          'card_key': bill.cardKey,
          'total_due': bill.totalDuePaise,
          'min_due': bill.minimumDuePaise,
          'due_date': bill.dueDateMs,
          'statement_date': bill.statementDateMs,
          // The SMS time, not the scan time: after a rescan every bill would
          // otherwise look "just received" and the wrong statement would win.
          'created_at': bill.receivedAtMs ?? now.millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      await db.update(
        'sms_messages',
        {
          'processed': 1,
          'class': assessment.cls.name,
          'score': assessment.score,
          'sender_normalized': sender.normalized,
          'model_money': model?.predict(message.sender, message.body).money,
        },
        where: 'id = ?',
        whereArgs: [message.id],
      );
    }

    // Persist how often each learned rule fired. `hits` is the user's evidence
    // that the rule is doing work, and it is shown in Settings before undo.
    for (final entry in ruleHits.entries) {
      await db.rawUpdate(
        'UPDATE merchant_rules SET hits = hits + ?, last_used_at = ? '
        'WHERE pattern = ?',
        [entry.value, now.millisecondsSinceEpoch, entry.key],
      );
    }
    for (final entry in exclusionHits.entries) {
      await db.rawUpdate(
        'UPDATE excluded_shapes SET hits = hits + ? WHERE signature = ?',
        [entry.value, entry.key],
      );
    }

    // Dedupe is part of *writing* the ledger, not just of reading it. A loser
    // left in the table is still a row another reader can count, so the stored
    // set is reconciled once per ingest and the loser is removed (the winner
    // keeps the event, and the row count is what the owner is trusting).
    final merged = await _reconcileDuplicates(db, rules);
    await _cleanupPhantomCards(db);

    await db.insert('app_meta', {
      'key': 'last_scan_at',
      'value': now.millisecondsSinceEpoch.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    return (found: found, merged: merged, phishing: phishing);
  }

  /// Bumped whenever the parser changes meaning (not just formatting).
  ///
  /// Stored in `app_meta`; together with the schema version it decides whether
  /// the stored ledger has to be re-derived. Bump this on every rule change
  /// that alters what a message becomes.
  static const int parserVersion = 13;

  @override
  Future<IngestResult> reparseAll() async {
    final db = await _db.database;
    final result = await _reparse(db);
    return IngestResult(
      smsRead: result.messages,
      transactionsFound: result.found,
      duplicatesMerged: result.merged,
      phishingFound: result.phishing,
    );
  }

  /// Wipes the derived tables and re-runs extraction over the stored raw
  /// messages.
  ///
  /// Keeps what the user taught the app: `merchant_rules`, `excluded_shapes`,
  /// `pending_categories`, card settings (limits/labels) and every row's
  /// `category_source = user` choice (restored by dedupe key afterwards).
  Future<({int messages, int found, int merged, int phishing})> _reparse(
    Database db,
  ) async {
    if (_reparsing) {
      return (messages: 0, found: 0, merged: 0, phishing: 0);
    }
    _reparsing = true;
    try {
      final overrides = await db.query(
        'transactions',
        columns: const ['dedupe_key', 'category_name', 'category_kind'],
        where: "category_source = ?",
        whereArgs: [CategorySource.user.name],
      );
      final messages =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM sms_messages'),
          ) ??
          0;

      // Rows the owner typed by hand ("This is a transaction") cannot be
      // re-derived from any message, so a re-parse must carry them across
      // instead of dropping them.
      await db.delete(
        'transactions',
        where: 'source_type != ?',
        whereArgs: [TxnSourceType.manual.name],
      );
      await db.delete('card_bills');
      await db.update('sms_messages', {'processed': 0});

      final result = await _processPending(db, _now());

      for (final row in overrides) {
        final key = row['dedupe_key'] as String?;
        final name = row['category_name'] as String?;
        if (key == null || name == null) continue;
        await db.update(
          'transactions',
          {
            'category_name': name,
            'category_kind': row['category_kind'] as String? ?? 'other',
            'category_source': CategorySource.user.name,
            'needs_review': 0,
          },
          where: 'dedupe_key = ?',
          whereArgs: [key],
        );
      }

      // Old builds minted a card for every account mask; drop the ones nothing
      // in the ledger or bills supports any more.
      await _cleanupPhantomCards(db);
      await _writeParserVersion(db);
      return (
        messages: messages,
        found: result.found,
        merged: result.merged,
        phishing: result.phishing,
      );
    } finally {
      _reparsing = false;
    }
  }

  bool _reparsing = false;

  /// Re-derives the stored ledger when the parser or the schema changed, so an
  /// upgrade can never keep showing stale numbers.
  Future<void> _ensureFreshDerivations(Database db) async {
    final rows = await db.query(
      'app_meta',
      where: "key IN ('parser_version', 'schema_version')",
    );
    final meta = {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
    final fresh =
        meta['parser_version'] == '$parserVersion' &&
        meta['schema_version'] == '${AppDatabase.schemaVersion}';
    if (fresh) return;
    final messages =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM sms_messages'),
        ) ??
        0;
    if (messages == 0) {
      await _writeParserVersion(db);
      return;
    }
    await _reparse(db);
  }

  Future<String?> _meta(Database db, String key) async {
    final rows = await db.query(
      'app_meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _setMeta(Database db, String key, String value) => db.insert(
    'app_meta',
    {'key': key, 'value': value},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> _writeParserVersion(Database db) async {
    for (final entry in {
      'parser_version': '$parserVersion',
      'schema_version': '${AppDatabase.schemaVersion}',
    }.entries) {
      await db.insert('app_meta', {
        'key': entry.key,
        'value': entry.value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Applies the one dedupe engine to the persisted ledger.
  ///
  /// Runs after every ingest so a duplicate notification can never survive as a
  /// second stored row, and so a stored row that a later alert proves was a
  /// debit+credit pair is corrected to `transfer` with its category. A row the
  /// user has categorised keeps that category.
  Future<int> _reconcileDuplicates(
    Database db,
    Map<String, MerchantRule> rules,
  ) async {
    final rows = await db.query('transactions', orderBy: 'occurred_at ASC');
    if (rows.length < 2) return 0;
    final byKey = <String, Map<String, Object?>>{
      for (final row in rows) row['dedupe_key'] as String: row,
    };
    final marked = _dedupe.mark(rows.map(_txnFromRow).toList(growable: false));

    var merged = 0;
    for (final txn in marked) {
      final row = byKey[txn.key];
      if (row == null) continue;
      if (txn.isDuplicateOfKey != null) {
        // Marked, never deleted (README, ARCHITECTURE §6): the loser keeps its
        // row and its raw message, and every reader skips `duplicate_of != null`.
        if (row['duplicate_of'] != txn.isDuplicateOfKey) {
          await db.update(
            'transactions',
            {'duplicate_of': txn.isDuplicateOfKey, 'needs_review': 0},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
          merged++;
        }
        continue;
      }
      final kindChanged = row['kind'] != txn.kind.name;
      final reasonChanged = row['transfer_reason'] != txn.transferReason.name;
      final moneyInChanged = row['money_in_kind'] != txn.moneyInKind.name;
      // A winner that was previously some other group's loser must be unmarked.
      final staleDuplicate = row['duplicate_of'] != null;
      if (!kindChanged &&
          !reasonChanged &&
          !moneyInChanged &&
          !staleDuplicate) {
        continue;
      }

      final values = <String, Object?>{
        'kind': txn.kind.name,
        'transfer_reason': txn.transferReason.name,
        'money_in_kind': txn.moneyInKind.name,
        'needs_review': 0,
        if (staleDuplicate) 'duplicate_of': null,
      };
      if (row['category_source'] != CategorySource.user.name) {
        final rule = _learning.match(rules, txn);
        final category = rule == null
            ? _categorizer.categorize(
                txn.merchant,
                kind: txn.kind,
                transferReason: txn.transferReason,
              )
            : (name: rule.categoryName, kind: rule.categoryKind);
        values['category_name'] = category.name;
        values['category_kind'] = category.kind.name;
        values['category_source'] = rule == null
            ? CategorySource.rule.name
            : CategorySource.learned.name;
      }
      await db.update(
        'transactions',
        values,
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    return merged;
  }

  Future<void> _ensureCard(
    Database db,
    String issuer,
    String last4,
    DateTime now, {
    int? availableLimitPaise,
    int? amountPaise,
    bool isSpend = false,
  }) async {
    await db.insert('cards', {
      'issuer': issuer,
      'last4': last4,
      'label': null,
      'credit_limit': null,
      'statement_day': null,
      'due_day': null,
      'is_active': 1,
      'created_at': now.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    // The alert printed an available limit: the limit at that moment was the
    // available figure plus the spend that just reduced it. Persisted once, and
    // never over a limit the user typed.
    if (availableLimitPaise != null &&
        availableLimitPaise > 0 &&
        isSpend &&
        amountPaise != null &&
        amountPaise > 0) {
      await db.rawUpdate(
        'UPDATE cards SET credit_limit = ? '
        'WHERE issuer = ? AND last4 = ? AND credit_limit IS NULL',
        [availableLimitPaise + amountPaise, issuer, last4],
      );
    }
  }

  /// Removes card rows that nothing in the ledger or the bills supports.
  ///
  /// A card is kept when the user has configured it (limit/label/statement
  /// day), or when a credit-card transaction or a bill names it. This is how
  /// the 11 savings-account "cards" written by an older build disappear.
  Future<int> _cleanupPhantomCards(Database db) async {
    return db.rawDelete('''
      DELETE FROM cards
      WHERE credit_limit IS NULL
        AND label IS NULL
        AND statement_day IS NULL
        AND due_day IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM card_bills b
          WHERE b.card_key = cards.issuer || '|' || cards.last4
        )
        AND NOT EXISTS (
          SELECT 1 FROM transactions t
          WHERE t.card_key = cards.issuer || '|' || cards.last4
            AND t.instrument = 'creditCard'
        )
    ''');
  }

  @override
  Future<void> deleteCard(String issuer, String last4) async {
    final db = await _db.database;
    final key = '$issuer|$last4';
    await db.delete(
      'cards',
      where: 'issuer = ? AND last4 = ?',
      whereArgs: [issuer, last4],
    );
    await db.delete('card_bills', where: 'card_key = ?', whereArgs: [key]);
    // The phantom must not come back on the next scan, and a row that pointed
    // at it must not keep inflating a card.
    await db.update(
      'transactions',
      {'card_key': null},
      where: 'card_key = ?',
      whereArgs: [key],
    );
  }

  @override
  Future<void> assignCategory({
    required String txnKey,
    required String categoryName,
    required SpendCategoryKind kind,
  }) async {
    // A statement row's category lives with the statement.
    if (txnKey.startsWith('stmt:')) {
      final store = StatementStore(database: _db);
      final row = await store.rowPayee(txnKey);
      final payee = row?.payee?.trim().toUpperCase();
      if (row == null || payee == null || payee.isEmpty) {
        await store.setCategory(txnKey, categoryName, kind);
        return;
      }
      // Like the SMS ledger's "every payment from X": this payment and every
      // later one to the same payee (rent stays rent; earlier, different
      // payments to the same person are left alone).
      final day = DateTime(row.date.year, row.date.month, row.date.day);
      await store.addPayeeRule(
        PayeeRule(
          payee: payee,
          categoryName: categoryName,
          kind: kind,
          fromMs: day.millisecondsSinceEpoch,
        ),
      );
      return;
    }
    final db = await _db.database;
    await _assignCategoryOn(
      db,
      txnKey: txnKey,
      categoryName: categoryName,
      kind: kind,
      now: _now(),
    );
  }

  /// The one write path for "the user picked a category".
  ///
  /// Besides updating the row, this teaches the app: a rule is stored under the
  /// row's merchant signature so the next scan does not ask again, and the same
  /// rule is applied to the rows already stored (a correction on one Pluxee
  /// alert fixes the other 23 immediately).
  Future<void> _assignCategoryOn(
    Database db, {
    required String txnKey,
    required String categoryName,
    required SpendCategoryKind kind,
    required DateTime now,
  }) async {
    final rows = await db.query(
      'transactions',
      where: 'dedupe_key = ?',
      whereArgs: [txnKey],
      limit: 1,
    );
    await db.update(
      'transactions',
      {
        'category_name': categoryName,
        'category_kind': kind.name,
        'category_source': CategorySource.user.name,
        'needs_review': 0,
      },
      where: 'dedupe_key = ?',
      whereArgs: [txnKey],
    );
    if (rows.isEmpty) return;

    final txn = _txnFromRow(rows.first);
    if (!_learning.shouldLearn(txn, kind)) return;
    final signature = _learning.signatureFor(txn);
    if (signature == null) return;

    await _upsertMerchantRule(
      db,
      signature: signature,
      categoryName: categoryName,
      kind: kind,
      sampleMerchant: txn.merchant,
      now: now,
    );

    // Apply the freshly taught rule to the rest of the ledger. Rows the user
    // has already categorised are never touched; the seed row is already set.
    final stored = await db.query(
      'transactions',
      where: 'dedupe_key != ? AND occurred_at >= ?',
      whereArgs: [
        txnKey,
        now.subtract(const Duration(days: 400)).millisecondsSinceEpoch,
      ],
    );
    var applied = 0;
    for (final row in stored) {
      final candidate = _txnFromRow(row);
      if (!_learning.matchesSignature(candidate, signature)) continue;
      await db.update(
        'transactions',
        {
          'category_name': categoryName,
          'category_kind': kind.name,
          'category_source': CategorySource.learned.name,
          'needs_review': 0,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      applied++;
    }
    if (applied > 0) {
      await db.rawUpdate(
        'UPDATE merchant_rules SET hits = hits + ?, last_used_at = ? '
        'WHERE pattern = ?',
        [applied, now.millisecondsSinceEpoch, signature],
      );
    }
  }

  Future<void> _upsertMerchantRule(
    Database db, {
    required String signature,
    required String categoryName,
    required SpendCategoryKind kind,
    required String? sampleMerchant,
    required DateTime now,
  }) async {
    final existing = await db.query(
      'merchant_rules',
      where: 'pattern = ?',
      whereArgs: [signature],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('merchant_rules', {
        'pattern': signature,
        'category_name': categoryName,
        'category_kind': kind.name,
        'hits': 0,
        'sample_merchant': sampleMerchant,
        'created_at': now.millisecondsSinceEpoch,
        'last_used_at': null,
      });
      return;
    }
    // Re-categorising an existing rule updates the category but keeps the hit
    // count, which is the history of how often it has fired.
    await db.update(
      'merchant_rules',
      {
        'category_name': categoryName,
        'category_kind': kind.name,
        'sample_merchant': sampleMerchant ?? existing.first['sample_merchant'],
      },
      where: 'pattern = ?',
      whereArgs: [signature],
    );
  }

  @override
  Future<List<MerchantRule>> merchantRules() async {
    final db = await _db.database;
    final rows = await db.query(
      'merchant_rules',
      orderBy: 'hits DESC, pattern ASC',
    );
    return rows.map(_ruleFromRow).toList(growable: false);
  }

  @override
  Future<void> forgetMerchantRule(String signature) async {
    final db = await _db.database;
    await db.delete(
      'merchant_rules',
      where: 'pattern = ?',
      whereArgs: [signature],
    );
  }

  @override
  Future<void> excludeTxn(String txnKey) async {
    // The bank's own record is not a parsing mistake; there is nothing to
    // un-learn (the screen does not offer this for statement rows).
    if (txnKey.startsWith('stmt:')) return;
    final db = await _db.database;
    final rows = await db.query(
      'transactions',
      where: 'dedupe_key = ?',
      whereArgs: [txnKey],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final txn = _txnFromRow(rows.first);
    final signature = _learning.exclusionFor(txn);
    final now = _now().millisecondsSinceEpoch;
    final existing = await db.query(
      'excluded_shapes',
      where: 'signature = ?',
      whereArgs: [signature],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('excluded_shapes', {
        'signature': signature,
        'sender': txn.sender,
        'merchant': txn.merchant,
        'amount_band': MerchantSignature.amountBand(txn.amountPaise),
        'amount_paise': txn.amountPaise,
        'hits': 0,
        'created_at': now,
      });
    }
    await db.delete(
      'transactions',
      where: 'dedupe_key = ?',
      whereArgs: [txnKey],
    );
  }

  // ---- All-messages inbox --------------------------------------------------

  @override
  Future<List<SmsMessageRow>> recentMessages({
    int offset = 0,
    int limit = 50,
    String? filter,
    String? query,
  }) async {
    final db = await _db.database;
    final clauses = <String>[];
    final args = <Object?>[];

    final classClause = _classClause(filter);
    if (classClause != null) clauses.add(classClause);

    final needle = query?.trim();
    if (needle != null && needle.isNotEmpty) {
      final like = _likePattern(needle);
      // Sender ids are hyphenated DLT headers (`VM-HDFCBK-T`), so a search for
      // "hdfcbank" has to look at the header with the separators removed too.
      final compact = needle.replaceAll(RegExp(r'[\s-]+'), '');
      clauses.add(
        r"(body LIKE ? ESCAPE '\' OR sender LIKE ? ESCAPE '\' OR "
        r"REPLACE(sender, '-', '') LIKE ? ESCAPE '\')",
      );
      args
        ..add(like)
        ..add(like)
        ..add(_likePattern(compact));
    }

    final rows = await db.query(
      'sms_messages',
      columns: const [
        'id',
        'sender',
        'body',
        'received_at',
        'class',
        'model_money',
      ],
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'received_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_smsRowFromRow).toList(growable: false);
  }

  @override
  Future<InboxStats> inboxStats() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS total,
        COALESCE(SUM(CASE WHEN class = 'transaction' THEN 1 ELSE 0 END), 0)
          AS transactions,
        COALESCE(SUM(CASE WHEN class IN ('informational', 'promo') THEN 1 ELSE 0 END), 0)
          AS not_counted,
        COALESCE(SUM(CASE WHEN class = 'phishing' THEN 1 ELSE 0 END), 0)
          AS flagged,
        COALESCE(SUM(CASE WHEN class IS NULL OR class = 'unknown' THEN 1 ELSE 0 END), 0)
          AS unreviewed,
        COALESCE(SUM(CASE WHEN $possiblyMissedClause THEN 1 ELSE 0 END), 0)
          AS possibly_missed
      FROM sms_messages
    ''');
    final row = rows.isEmpty ? const <String, Object?>{} : rows.first;
    int value(String key) => (row[key] as num?)?.toInt() ?? 0;
    return InboxStats(
      total: value('total'),
      transactions: value('transactions'),
      notCounted: value('not_counted'),
      flagged: value('flagged'),
      unreviewed: value('unreviewed'),
      possiblyMissed: value('possibly_missed'),
    );
  }

  @override
  Future<Set<String>> excludedShapes() async {
    final db = await _db.database;
    return _loadExcludedShapes(db);
  }

  @override
  Future<int> applyCategoryToSignature({
    required String signature,
    required String categoryName,
    required SpendCategoryKind kind,
  }) async {
    final db = await _db.database;
    final rows = await db.query('transactions');
    final matches = <Map<String, Object?>>[];
    for (final row in rows) {
      final txn = _txnFromRow(row);
      if (_learning.signatureFor(txn) != signature) continue;
      // A sender-wide fallback key (`hdfc bank`) must not relabel salary
      // credits; the merchant-keyed rules are safe for every kind.
      if (MerchantSignature.isSenderFallback(txn.merchant) &&
          txn.kind != TxnKind.spend) {
        continue;
      }
      matches.add(row);
    }
    for (final row in matches) {
      await db.update(
        'transactions',
        {
          'category_name': categoryName,
          'category_kind': kind.name,
          'category_source': CategorySource.learned.name,
          'needs_review': 0,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    final now = _now();
    String? sampleMerchant;
    for (final row in matches) {
      final merchant = row['merchant'] as String?;
      if (merchant != null && merchant.trim().isNotEmpty) {
        sampleMerchant = merchant;
        break;
      }
    }
    await _upsertMerchantRule(
      db,
      signature: signature,
      categoryName: categoryName,
      kind: kind,
      sampleMerchant: sampleMerchant,
      now: now,
    );
    // `hits` is the evidence the rule is doing work, not guesses: the rows this
    // action just fixed plus every future alert that matches it.
    await db.rawUpdate(
      'UPDATE merchant_rules SET hits = hits + ?, last_used_at = ? '
      'WHERE pattern = ?',
      [matches.length, now.millisecondsSinceEpoch, signature],
    );
    return matches.length;
  }

  @override
  Future<void> assignCategoryOnce({
    required String txnKey,
    required String categoryName,
    required SpendCategoryKind kind,
  }) async {
    final db = await _db.database;
    await db.update(
      'transactions',
      {
        'category_name': categoryName,
        'category_kind': kind.name,
        'category_source': CategorySource.user.name,
        'needs_review': 0,
      },
      where: 'dedupe_key = ?',
      whereArgs: [txnKey],
    );
  }

  @override
  Future<int> markNotTransaction({
    required String? signature,
    required String messageId,
    required String? txnKey,
    required bool everyFromMerchant,
  }) async {
    final db = await _db.database;
    var removed = 0;

    if (everyFromMerchant && signature != null) {
      final rows = await db.query(
        'transactions',
        columns: const ['dedupe_key', 'merchant', 'sender', 'kind'],
      );
      final keys = <String>[];
      for (final row in rows) {
        final rowSignature = MerchantSignature.of(
          row['merchant'] as String?,
          senderEntity: _learning.senderEntityFor(row['sender'] as String?),
        );
        if (rowSignature != signature) continue;
        // A sender-fallback key (`hdfc bank`) is shared by every alert from
        // that bank; "not a transaction" must never sweep a salary credit or a
        // transfer, only spends.
        if (MerchantSignature.isSenderFallback(row['merchant'] as String?) &&
            row['kind'] != TxnKind.spend.name) {
          continue;
        }
        final key = row['dedupe_key'] as String?;
        if (key != null) keys.add(key);
      }
      for (final key in keys) {
        // Reuses the one "not a transaction" path (row + negative shape rule).
        await excludeTxn(key);
      }
      removed = keys.length;
    } else if (txnKey != null) {
      final rows = await db.query(
        'transactions',
        where: 'dedupe_key = ?',
        whereArgs: [txnKey],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        await excludeTxn(txnKey);
        removed = 1;
      }
    }

    // The message itself is now a record of a decided message, not a pending
    // transaction: the row chip follows immediately after the reload.
    await db.update(
      'sms_messages',
      {'processed': 1, 'class': SmsClass.informational.name},
      where: 'id = ?',
      whereArgs: [messageId],
    );
    return removed;
  }

  @override
  Future<void> createTransactionFromMessage({
    required SmsMessageRow message,
    required int amountPaise,
    required String merchant,
    required String categoryName,
    required SpendCategoryKind kind,
    required bool rememberMerchant,
    required String? signature,
  }) async {
    final db = await _db.database;
    final now = _now();
    final sender = const SenderRegistry().resolve(message.sender);
    final sms = SmsMessage(
      id: message.id,
      sender: message.sender,
      body: message.body,
      receivedAtMs: message.receivedAtMs,
    );
    final parsed = _extractor.extract(sms, sender);
    final key =
        'sms:${smsContentId(sender: message.sender, receivedAtMs: message.receivedAtMs, body: message.body)}';
    final typedMerchant = merchant.trim();
    final txn = Txn(
      key: key,
      occurredAtMs: message.receivedAtMs,
      amountPaise: amountPaise,
      kind: TxnKind.spend,
      instrument: parsed?.instrument ?? Instrument.unknown,
      sender: sender.normalized,
      merchant: typedMerchant.isEmpty ? null : typedMerchant,
      counterpartyVpa: parsed?.counterpartyVpa,
      categoryName: categoryName,
      categoryKind: kind,
      categorySource: CategorySource.user,
      cardKey: parsed?.cardKey,
      last4: parsed?.last4,
      issuer: parsed?.issuer,
      confidence: 1,
      // Manual provenance keeps this row through `reparseAll`, which cannot
      // recreate a payment the parser does not read from any message.
      sourceType: TxnSourceType.manual,
      needsReview: false,
      // Typed by a human, so the ledger admission rule must not re-derive the
      // decision from the promo/informational wording that made the parser skip
      // the message in the first place.
      rawBody: null,
    );
    await db.insert(
      'transactions',
      _txnToRow(txn, createdAt: now),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.update(
      'transactions',
      {
        'amount_paise': amountPaise,
        'merchant': typedMerchant.isEmpty ? null : typedMerchant,
        'category_name': categoryName,
        'category_kind': kind.name,
        'category_source': CategorySource.user.name,
        'needs_review': 0,
      },
      where: 'dedupe_key = ?',
      whereArgs: [key],
    );
    await db.update(
      'sms_messages',
      {'processed': 1, 'class': SmsClass.transaction.name, 'score': 1.0},
      where: 'id = ?',
      whereArgs: [message.id],
    );
    if (rememberMerchant && signature != null) {
      await applyCategoryToSignature(
        signature: signature,
        categoryName: categoryName,
        kind: kind,
      );
      // The row the owner created stays their own choice; the retroactive pass
      // marked it as rule-learned.
      await db.update(
        'transactions',
        {'category_source': CategorySource.user.name},
        where: 'dedupe_key = ?',
        whereArgs: [key],
      );
    }
  }

  /// Not counted by the rules, but the on-device model is at least 90 % sure
  /// money moved. On the time-held-out gold set this is ~12 messages a month
  /// and catches 10 of the rules' 16 misses (tool/audit_accuracy.dart --model).
  static const String possiblyMissedClause =
      "(class IS NULL OR class != 'transaction') AND model_money >= 0.9";

  SmsModel? _model;
  bool _modelTried = false;

  /// The bundled model, loaded once; null when the asset is unavailable
  /// (host tests), in which case processing simply records no second opinion.
  Future<SmsModel?> _secondOpinion() async {
    if (_modelTried) return _model;
    _modelTried = true;
    try {
      _model =
          _injectedModel ??
          SmsModel.fromJson(await rootBundle.loadString(SmsModel.assetPath));
    } catch (_) {
      _model = null;
    }
    return _model;
  }

  String? _classClause(String? filter) {
    switch (filter) {
      case 'transactions':
        return "class = 'transaction'";
      case 'notCounted':
        return "class IN ('informational', 'promo')";
      case 'flagged':
        return "class = 'phishing'";
      case 'unreviewed':
        return "(class IS NULL OR class = 'unknown')";
      case 'possiblyMissed':
        return possiblyMissedClause;
      default:
        return null;
    }
  }

  String _likePattern(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    return '%$escaped%';
  }

  SmsMessageRow _smsRowFromRow(Map<String, Object?> row) => SmsMessageRow(
    id: row['id'] as String,
    sender: row['sender'] as String,
    body: row['body'] as String,
    receivedAtMs: row['received_at'] as int,
    className: row['class'] as String?,
    modelMoney: (row['model_money'] as num?)?.toDouble(),
  );

  Future<Map<String, MerchantRule>> _loadMerchantRules(Database db) async {
    final rows = await db.query('merchant_rules');
    return {
      for (final row in rows) row['pattern'] as String: _ruleFromRow(row),
    };
  }

  Future<Set<String>> _loadExcludedShapes(Database db) async {
    final rows = await db.query('excluded_shapes', columns: ['signature']);
    return {for (final row in rows) row['signature'] as String};
  }

  MerchantRule _ruleFromRow(Map<String, Object?> row) => MerchantRule(
    signature: row['pattern'] as String,
    categoryName: row['category_name'] as String,
    categoryKind: SpendCategoryKind.values.byName(
      row['category_kind'] as String? ?? 'other',
    ),
    hits: row['hits'] as int? ?? 0,
    sampleMerchant: row['sample_merchant'] as String?,
    createdAtMs: row['created_at'] as int?,
    lastUsedAtMs: row['last_used_at'] as int?,
  );

  @override
  Future<void> saveCard(CardAccount card) async {
    final db = await _db.database;
    final existing = await db.query(
      'cards',
      where: 'issuer = ? AND last4 = ?',
      whereArgs: [card.issuer, card.last4],
      limit: 1,
    );
    final values = {
      'issuer': card.issuer,
      'last4': card.last4,
      'label': card.label,
      'credit_limit': card.creditLimitPaise,
      'statement_day': card.statementDay,
      'due_day': card.dueDay,
      'is_active': card.isActive ? 1 : 0,
    };
    if (existing.isEmpty) {
      await db.insert('cards', {
        ...values,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    } else {
      await db.update(
        'cards',
        values,
        where: 'issuer = ? AND last4 = ?',
        whereArgs: [card.issuer, card.last4],
      );
    }
  }

  @override
  Future<void> dismissInsight(String id) async {
    final db = await _db.database;
    final row = await db.query(
      'app_meta',
      where: 'key = ?',
      whereArgs: ['dismissed_insights'],
      limit: 1,
    );
    final current = row.isEmpty
        ? <String>[]
        : (jsonDecode(row.first['value'] as String) as List).cast<String>();
    if (!current.contains(id)) current.add(id);
    await db.insert('app_meta', {
      'key': 'dismissed_insights',
      'value': jsonEncode(current),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> startDemo() async {
    final db = await _db.database;
    await db.insert('app_meta', {
      'key': 'demo_mode',
      'value': '1',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> exitDemo() async {
    final db = await _db.database;
    await db.insert('app_meta', {
      'key': 'demo_mode',
      'value': '0',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> clearAll() async {
    final db = await _db.database;
    await db.delete('transactions');
    await db.delete('sms_messages');
    await db.delete('card_bills');
    await db.delete('cards');
    await db.delete('merchant_rules');
    await db.delete('excluded_shapes');
    await db.delete('app_meta');
    // Imported bank statements live in the same database and go too.
    await db.delete('statement_rows');
    await db.delete('statements');
  }

  /// Applies categories chosen from the Android notification shade.
  ///
  /// The receiver only knows the SMS content hash, which is exactly the suffix
  /// of the transaction dedupe key, so this is a direct key update.
  Future<void> _applyPendingCategories(Database db) async {
    List<Map<String, Object?>> pending;
    try {
      pending = await db.query('pending_categories');
    } on DatabaseException {
      return;
    }
    if (pending.isEmpty) return;
    for (final row in pending) {
      final name = row['category_name'] as String?;
      final smsRef = row['sms_id'] as String?;
      if (name == null || smsRef == null) continue;
      final kind = categoryKindFor(name);
      await _assignCategoryOn(
        db,
        txnKey: 'sms:$smsRef',
        categoryName: name,
        kind: kind,
        now: DateTime.now(),
      );
    }
    await db.delete('pending_categories');
  }

  // ---- row mapping ------------------------------------------------------
  Txn _txnFromRow(Map<String, Object?> row) {
    return Txn(
      id: row['id'] as int?,
      key: row['dedupe_key'] as String? ?? 'db:${row['id']}',
      occurredAtMs: row['occurred_at'] as int,
      amountPaise: row['amount_paise'] as int,
      kind: TxnKind.values.byName(row['kind'] as String? ?? 'spend'),
      instrument: Instrument.values.byName(
        row['instrument'] as String? ?? 'unknown',
      ),
      sender: row['sender'] as String?,
      merchant: row['merchant'] as String?,
      counterpartyVpa: row['vpa'] as String?,
      categoryId: row['category_id'] as int?,
      categoryName: row['category_name'] as String?,
      categorySource: CategorySource.values.byName(
        row['category_source'] as String? ?? 'none',
      ),
      categoryKind: SpendCategoryKind.values.byName(
        row['category_kind'] as String? ?? 'other',
      ),
      transferReason: TransferReason.values.byName(
        row['transfer_reason'] as String? ?? 'none',
      ),
      moneyInKind: MoneyInKind.values.byName(
        row['money_in_kind'] as String? ?? 'none',
      ),
      cardKey: row['card_key'] as String?,
      last4: row['last4'] as String?,
      issuer: row['issuer'] as String?,
      referenceId: row['reference_id'] as String?,
      balanceAfterPaise: row['balance_after'] as int?,
      availableLimitPaise: row['available_limit'] as int?,
      confidence: (row['confidence'] as num?)?.toDouble() ?? 0.5,
      amountScore: (row['amount_score'] as num?)?.toInt(),
      sourceType: TxnSourceType.values.byName(
        row['source_type'] as String? ?? 'sms',
      ),
      isDuplicateOfKey: row['duplicate_of'] as String?,
      needsReview: (row['needs_review'] as int? ?? 0) == 1,
      rawBody: row['raw_body'] as String?,
    );
  }

  Map<String, Object?> _txnToRow(Txn txn, {required DateTime createdAt}) {
    return {
      'dedupe_key': txn.key,
      'sms_id': txn.smsId,
      'occurred_at': txn.occurredAtMs,
      'amount_paise': txn.amountPaise,
      'kind': txn.kind.name,
      'instrument': txn.instrument.name,
      'sender': txn.sender,
      'merchant': txn.merchant,
      'vpa': txn.counterpartyVpa,
      'category_id': txn.categoryId,
      'category_name': txn.categoryName,
      'category_source': txn.categorySource.name,
      'category_kind': txn.categoryKind.name,
      'transfer_reason': txn.transferReason.name,
      'money_in_kind': txn.moneyInKind.name,
      'card_key': txn.cardKey,
      'last4': txn.last4,
      'issuer': txn.issuer,
      'reference_id': txn.referenceId,
      'balance_after': txn.balanceAfterPaise,
      'available_limit': txn.availableLimitPaise,
      'confidence': txn.confidence,
      'amount_score': txn.amountScore,
      'source_type': txn.sourceType.name,
      'duplicate_of': txn.isDuplicateOfKey,
      'needs_review': txn.needsReview ? 1 : 0,
      'raw_body': txn.rawBody,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  CardAccount _cardFromRow(Map<String, Object?> row) {
    return CardAccount(
      id: row['id'] as int?,
      issuer: row['issuer'] as String,
      last4: row['last4'] as String,
      label: row['label'] as String?,
      creditLimitPaise: row['credit_limit'] as int?,
      statementDay: row['statement_day'] as int?,
      dueDay: row['due_day'] as int?,
      isActive: (row['is_active'] as int? ?? 1) == 1,
    );
  }

  CardBillNotice _billFromRow(Map<String, Object?> row) {
    return CardBillNotice(
      cardKey: row['card_key'] as String,
      totalDuePaise: row['total_due'] as int,
      minimumDuePaise: row['min_due'] as int?,
      dueDateMs: row['due_date'] as int?,
      statementDateMs: row['statement_date'] as int?,
      receivedAtMs: row['created_at'] as int?,
    );
  }
}

/// Small helper so the repository can hand the extractor the resolved sender.
class SmsSenderResolver {
  SmsSenderResolver(this.classifier);

  final SmsClassifier classifier;

  SenderId resolve(SmsMessage message) =>
      const SenderRegistry().resolve(message.sender);
}

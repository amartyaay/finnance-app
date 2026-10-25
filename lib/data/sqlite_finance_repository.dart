import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/category_catalog.dart';
import '../domain/enums.dart';
import '../domain/sms_message.dart';
import '../domain/transaction.dart';
import '../engine/card_metrics.dart';
import '../engine/dedupe_engine.dart';
import '../services/categorizer.dart';
import '../services/sms/sender_registry.dart';
import '../services/sms/sms_classifier.dart';
import '../services/sms/transaction_extractor.dart';
import '../services/sms_reader.dart';
import 'app_database.dart';
import 'finance_repository.dart';

/// SQLite-backed repository: the real app.
///
/// Ownership: this class is the only writer of `transactions`. The Kotlin
/// receiver only appends to `sms_messages`, so parsing lives in one place.
class SqliteFinanceRepository implements FinanceRepository {
  SqliteFinanceRepository({
    AppDatabase? database,
    SmsInboxReader? reader,
    DateTime Function()? now,
    SmsClassifier? classifier,
    TransactionExtractor? extractor,
    Categorizer? categorizer,
  }) : _db = database ?? AppDatabase(),
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

  @override
  bool get isDemo => false;

  @override
  Future<HomeData> load() async {
    final db = await _db.database;
    final now = _now();
    final since = now.subtract(const Duration(days: 400));

    await _applyPendingCategories(db);

    final txnRows = await db.query(
      'transactions',
      where: 'occurred_at >= ?',
      whereArgs: [since.millisecondsSinceEpoch],
      orderBy: 'occurred_at DESC',
    );
    final transactions = _dedupe.mark(txnRows.map(_txnFromRow).toList());

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

    final smsCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM sms_messages'),
        ) ??
        0;

    final reviewRows = await db.query(
      'transactions',
      where: 'needs_review = 1',
      orderBy: 'occurred_at DESC',
      limit: 20,
    );

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
      needsReview: reviewRows.map(_txnFromRow).toList(growable: false),
    );
  }

  @override
  Future<IngestResult> ingest() async {
    final db = await _db.database;
    final now = _now();

    List<SmsMessage> incoming;
    try {
      incoming = await _reader.readInbox(
        limit: 2000,
        sinceMillis: now.subtract(const Duration(days: 365)).millisecondsSinceEpoch,
      );
    } on UnsupportedError {
      rethrow;
    } on PlatformException catch (error) {
      if (error.code == 'permission_denied') throw const SmsPermissionMissing();
      rethrow;
    }

    for (final message in incoming) {
      await db.insert('sms_messages', {
        'id': message.id,
        'sender': message.sender,
        'body': message.body,
        'received_at': message.receivedAtMs,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final pending = await db.query(
      'sms_messages',
      where: 'processed = 0',
      orderBy: 'received_at ASC',
      limit: 3000,
    );

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
          final category = _categorizer.categorize(
            txn.merchant,
            kind: txn.kind,
            transferReason: txn.transferReason,
          );
          final id = await db.insert(
            'transactions',
            _txnToRow(
              txn.copyWith(
                categoryName: category.name,
                categoryKind: category.kind,
                categorySource: CategorySource.rule,
              ),
              createdAt: now,
            ),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          if (id > 0) found++;
          if (txn.last4 != null) {
            await _ensureCard(db, txn.issuer ?? sender.entity ?? 'Card', txn.last4!, now);
          }
        }
        final bill = _extractor.billNotice(message, sender);
        if (bill != null) {
          await db.insert('card_bills', {
            'card_key': bill.cardKey,
            'total_due': bill.totalDuePaise,
            'min_due': bill.minimumDuePaise,
            'due_date': bill.dueDateMs,
            'statement_date': bill.statementDateMs,
            'created_at': now.millisecondsSinceEpoch,
          });
        }
      }

      await db.update(
        'sms_messages',
        {
          'processed': 1,
          'class': assessment.cls.name,
          'score': assessment.score,
          'sender_normalized': sender.normalized,
        },
        where: 'id = ?',
        whereArgs: [message.id],
      );
    }

    // Dedupe is part of *writing* the ledger, not just of reading it. A loser
    // left in the table is still a row another reader can count, so the stored
    // set is reconciled once per ingest and the loser is removed (the winner
    // keeps the event, and the row count is what the owner is trusting).
    final merged = await _reconcileDuplicates(db);

    await db.insert('app_meta', {
      'key': 'last_scan_at',
      'value': now.millisecondsSinceEpoch.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    return IngestResult(
      smsRead: incoming.length,
      transactionsFound: found,
      duplicatesMerged: merged,
      phishingFound: phishing,
    );
  }

  /// Applies the one dedupe engine to the persisted ledger.
  ///
  /// Runs after every ingest so a duplicate notification can never survive as a
  /// second stored row, and so a stored row that a later alert proves was a
  /// debit+credit pair is corrected to `transfer` with its category. A row the
  /// user has categorised keeps that category.
  Future<int> _reconcileDuplicates(Database db) async {
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
        await db.delete('transactions', where: 'id = ?', whereArgs: [row['id']]);
        merged++;
        continue;
      }
      final kindChanged = row['kind'] != txn.kind.name;
      final reasonChanged = row['transfer_reason'] != txn.transferReason.name;
      if (!kindChanged && !reasonChanged) continue;

      final values = <String, Object?>{
        'kind': txn.kind.name,
        'transfer_reason': txn.transferReason.name,
        'needs_review': 0,
      };
      if (row['category_source'] != CategorySource.user.name) {
        final category = _categorizer.categorize(
          txn.merchant,
          kind: txn.kind,
          transferReason: txn.transferReason,
        );
        values['category_name'] = category.name;
        values['category_kind'] = category.kind.name;
        values['category_source'] = CategorySource.rule.name;
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
    DateTime now,
  ) async {
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
  }

  @override
  Future<void> assignCategory({
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
    await db.delete('app_meta');
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
      await db.update(
        'transactions',
        {
          'category_name': name,
          'category_kind': kind.name,
          'category_source': CategorySource.user.name,
          'needs_review': 0,
        },
        where: 'dedupe_key = ?',
        whereArgs: ['sms:$smsRef'],
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
      instrument: Instrument.values.byName(row['instrument'] as String? ?? 'unknown'),
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
      cardKey: row['card_key'] as String?,
      last4: row['last4'] as String?,
      issuer: row['issuer'] as String?,
      referenceId: row['reference_id'] as String?,
      balanceAfterPaise: row['balance_after'] as int?,
      availableLimitPaise: row['available_limit'] as int?,
      confidence: (row['confidence'] as num?)?.toDouble() ?? 0.5,
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
      'card_key': txn.cardKey,
      'last4': txn.last4,
      'issuer': txn.issuer,
      'reference_id': txn.referenceId,
      'balance_after': txn.balanceAfterPaise,
      'available_limit': txn.availableLimitPaise,
      'confidence': txn.confidence,
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

import 'package:finnance_app/data/transaction_store.dart';
import 'package:finnance_app/models/sms_message_record.dart';
import 'package:finnance_app/models/transaction_models.dart';
import 'package:finnance_app/repositories/transaction_repository.dart';
import 'package:finnance_app/services/csv_export_service.dart';
import 'package:finnance_app/services/sms_parser_service.dart';
import 'package:finnance_app/services/sms_reader_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scanInbox parses expenses and dedupes by source SMS id', () async {
    final timestampMillis = DateTime(2026, 5, 19, 9, 0).millisecondsSinceEpoch;
    final store = _MemoryTransactionStore();
    final exportService = _FakeCsvExportService();
    final repository = TransactionRepository(
      smsReaderService: _FakeSmsReaderService(
        messages: [
          SmsMessageRecord(
            id: 'sms-1',
            sender: 'SBIUPI',
            body:
                'Rs.120.00 debited from A/c XX9988 via UPI to Tea Shop. UPI Ref 123.',
            timestampMillis: timestampMillis,
          ),
          SmsMessageRecord(
            id: 'sms-2',
            sender: 'HDFCBK',
            body: 'OTP 123456 for Rs.120 purchase. Do not share.',
            timestampMillis: timestampMillis,
          ),
          SmsMessageRecord(
            id: 'sms-1',
            sender: 'SBIUPI',
            body:
                'Rs.120.00 debited from A/c XX9988 via UPI to Tea Shop. UPI Ref 123.',
            timestampMillis: timestampMillis,
          ),
        ],
      ),
      smsParserService: DefaultSmsParserService(),
      transactionStore: store,
      csvExportService: exportService,
      now: () => DateTime(2026, 5, 19, 9, 30),
    );

    final firstScan = await repository.scanInbox();

    expect(firstScan.totalSmsRead, 3);
    expect(firstScan.parsedTransactions, 2);
    expect(firstScan.insertedTransactions, 1);
    expect(await repository.monthlySpendPaise(DateTime(2026, 5)), 12000);
    expect(await repository.recentTransactions(), hasLength(1));

    final secondScan = await repository.scanInbox();

    expect(secondScan.insertedTransactions, 0);
    final transactions = await repository.recentTransactions();
    expect(transactions, hasLength(1));
    expect(await repository.lastScanAt(), DateTime(2026, 5, 19, 9, 30));

    final food = (await repository.categories()).first;
    await repository.assignCategory(
      transactionId: transactions.first.id!,
      category: food,
    );

    expect(await repository.uncategorizedTransactions(), isEmpty);
    expect(
      await repository.exportCsv(),
      'finance-transactions-202605190930.csv',
    );
    expect(exportService.lastCsv, contains('Food'));
  });

  test(
    'scanInbox dedupes paired bank and payment app alerts by reference',
    () async {
      final timestampMillis = DateTime(
        2026,
        5,
        19,
        9,
        0,
      ).millisecondsSinceEpoch;
      final store = _MemoryTransactionStore();
      final repository = TransactionRepository(
        smsReaderService: _FakeSmsReaderService(
          messages: [
            SmsMessageRecord(
              id: 'bank-sms',
              sender: 'HDFCBK',
              body:
                  'Rs.500.00 debited from A/c XX1234 via UPI to Cafe. UPI Ref 123456789012.',
              timestampMillis: timestampMillis,
            ),
            SmsMessageRecord(
              id: 'app-sms',
              sender: 'PHONEP',
              body:
                  'Paid INR 500.00 to Cafe via UPI. UPI transaction ID 123456789012.',
              timestampMillis: timestampMillis + 30000,
            ),
          ],
        ),
        smsParserService: DefaultSmsParserService(),
        transactionStore: store,
        csvExportService: _FakeCsvExportService(),
        now: () => DateTime(2026, 5, 19, 9, 30),
      );

      final scan = await repository.scanInbox();

      expect(scan.parsedTransactions, 2);
      expect(scan.insertedTransactions, 1);
      expect(await repository.monthlySpendPaise(DateTime(2026, 5)), 50000);
      expect(await repository.recentTransactions(), hasLength(1));
    },
  );

  test(
    'scanInbox stores credit card repayment but excludes it from spend',
    () async {
      final timestampMillis = DateTime(
        2026,
        5,
        19,
        9,
        0,
      ).millisecondsSinceEpoch;
      final store = _MemoryTransactionStore();
      final repository = TransactionRepository(
        smsReaderService: _FakeSmsReaderService(
          messages: [
            SmsMessageRecord(
              id: 'card-spend',
              sender: 'ICICIC',
              body:
                  'Your ICICI Bank Credit Card ending 4321 was used for INR 5,000.00 at Amazon.',
              timestampMillis: timestampMillis,
            ),
            SmsMessageRecord(
              id: 'card-bill-payment',
              sender: 'SBIUPI',
              body:
                  'A/c XX9988 debited by INR 5,000.00 via UPI to SBI Card for credit card bill payment. UPI Ref 987654321012.',
              timestampMillis: timestampMillis + 86400000,
            ),
          ],
        ),
        smsParserService: DefaultSmsParserService(),
        transactionStore: store,
        csvExportService: _FakeCsvExportService(),
        now: () => DateTime(2026, 5, 20, 9, 30),
      );

      final scan = await repository.scanInbox();
      final transactions = await repository.recentTransactions();

      expect(scan.parsedTransactions, 2);
      expect(scan.insertedTransactions, 2);
      expect(await repository.monthlySpendPaise(DateTime(2026, 5)), 500000);
      expect(
        transactions.where(
          (transaction) =>
              transaction.direction == TransactionDirection.transfer,
        ),
        hasLength(1),
      );
      expect(await repository.uncategorizedTransactions(), hasLength(1));
    },
  );

  test('creditCardSummaries groups cards by issuer and ending', () async {
    final timestampMillis = DateTime(2026, 5, 19, 9, 0).millisecondsSinceEpoch;
    final store = _MemoryTransactionStore();
    final repository = TransactionRepository(
      smsReaderService: _FakeSmsReaderService(
        messages: [
          SmsMessageRecord(
            id: 'card-1',
            sender: 'ICICIC',
            body:
                'Your ICICI Bank Credit Card ending 4321 was used for INR 1,000.00 at Amazon.',
            timestampMillis: timestampMillis,
          ),
          SmsMessageRecord(
            id: 'card-2',
            sender: 'ICICIC',
            body:
                'Your ICICI Bank Credit Card ending 4321 was used for INR 500.00 at Swiggy.',
            timestampMillis: timestampMillis + 1000,
          ),
          SmsMessageRecord(
            id: 'card-3',
            sender: 'KOTAKC',
            body:
                'Kotak credit card ending 9876 was used for INR 250.00 at Uber.',
            timestampMillis: timestampMillis + 2000,
          ),
        ],
      ),
      smsParserService: DefaultSmsParserService(),
      transactionStore: store,
      csvExportService: _FakeCsvExportService(),
      now: () => DateTime(2026, 5, 19, 9, 30),
    );

    await repository.scanInbox();
    final summaries = await repository.creditCardSummaries(DateTime(2026, 5));

    expect(summaries, hasLength(2));
    expect(summaries.first.issuer, 'ICICI Bank');
    expect(summaries.first.lastDigits, '4321');
    expect(summaries.first.monthlySpendPaise, 150000);
  });

  test('creditCardSummaries distinguishes same ending across issuers', () async {
    final timestampMillis = DateTime(2026, 5, 19, 9, 0).millisecondsSinceEpoch;
    final store = _MemoryTransactionStore();
    final repository = TransactionRepository(
      smsReaderService: _FakeSmsReaderService(
        messages: [
          SmsMessageRecord(
            id: 'card-1',
            sender: 'ICICIC',
            body:
                'Your ICICI Bank Credit Card ending 4321 was used for INR 1,000.00 at Amazon.',
            timestampMillis: timestampMillis,
          ),
          SmsMessageRecord(
            id: 'card-2',
            sender: 'SBICRD',
            body:
                'Your SBI Card ending 4321 was used for INR 750.00 at Flipkart.',
            timestampMillis: timestampMillis + 1000,
          ),
        ],
      ),
      smsParserService: DefaultSmsParserService(),
      transactionStore: store,
      csvExportService: _FakeCsvExportService(),
      now: () => DateTime(2026, 5, 19, 9, 30),
    );

    await repository.scanInbox();
    final summaries = await repository.creditCardSummaries(DateTime(2026, 5));

    expect(summaries, hasLength(2));
    expect(summaries.map((summary) => summary.issuer).toSet(), {
      'ICICI Bank',
      'SBI Card',
    });
  });
}

class _FakeSmsReaderService implements SmsReaderService {
  const _FakeSmsReaderService({required this.messages});

  final List<SmsMessageRecord> messages;

  @override
  Future<List<SmsMessageRecord>> readInbox({
    int limit = 1000,
    int? sinceMillis,
  }) async {
    return messages.take(limit).toList(growable: false);
  }
}

class _MemoryTransactionStore implements TransactionStore {
  final Map<String, FinanceTransaction> _transactions = {};
  final List<ExpenseCategory> _categories = [
    const ExpenseCategory(
      id: 1,
      name: 'Food',
      isDefault: true,
      createdAtMillis: 0,
    ),
    const ExpenseCategory(
      id: 2,
      name: 'Travel',
      isDefault: true,
      createdAtMillis: 0,
    ),
  ];
  DateTime? _lastScanAt;

  @override
  Future<ExpenseCategory> addCategory(String name) async {
    final existing = _categories.where(
      (category) => category.name.toLowerCase() == name.toLowerCase(),
    );
    if (existing.isNotEmpty) {
      return existing.first;
    }
    final category = ExpenseCategory(
      id: _categories.length + 1,
      name: name,
      isDefault: false,
      createdAtMillis: 0,
    );
    _categories.add(category);
    return category;
  }

  @override
  Future<List<FinanceTransaction>> allTransactions() async {
    return _transactions.values.toList(growable: false);
  }

  @override
  Future<void> assignCategory({
    required int transactionId,
    required ExpenseCategory category,
    required DateTime classifiedAt,
  }) async {
    final entry = _transactions.entries.firstWhere(
      (entry) => entry.value.id == transactionId,
    );
    final transaction = entry.value;
    _transactions[entry.key] = FinanceTransaction(
      id: transaction.id,
      sourceSmsId: transaction.sourceSmsId,
      sender: transaction.sender,
      normalizedSender: transaction.normalizedSender,
      timestampMillis: transaction.timestampMillis,
      amountPaise: transaction.amountPaise,
      direction: transaction.direction,
      instrument: transaction.instrument,
      accountOrCardHint: transaction.accountOrCardHint,
      merchantOrPayee: transaction.merchantOrPayee,
      referenceId: transaction.referenceId,
      cardIssuer: transaction.cardIssuer,
      cardLastDigits: transaction.cardLastDigits,
      confidence: transaction.confidence,
      categoryId: category.id,
      categoryName: category.name,
      classifiedAtMillis: classifiedAt.millisecondsSinceEpoch,
      createdAtMillis: transaction.createdAtMillis,
    );
  }

  @override
  Future<List<ExpenseCategory>> categories() async => _categories;

  @override
  Future<List<CreditCardSummary>> creditCardSummaries(DateTime month) async {
    final byCard = <String, List<FinanceTransaction>>{};
    for (final transaction in _transactions.values) {
      final issuer = transaction.cardIssuer;
      final digits = transaction.cardLastDigits;
      if (issuer == null || digits == null) {
        continue;
      }
      final key = '$issuer|$digits';
      byCard.putIfAbsent(key, () => <FinanceTransaction>[]).add(transaction);
    }

    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final summaries = <CreditCardSummary>[];
    for (final entry in byCard.entries) {
      final grouped = entry.value;
      grouped.sort((a, b) => a.timestampMillis.compareTo(b.timestampMillis));
      final first = grouped.first;
      final last = grouped.last;
      final monthlySpend = grouped
          .where(
            (transaction) =>
                transaction.direction == TransactionDirection.expense &&
                !transaction.timestamp.isBefore(start) &&
                transaction.timestamp.isBefore(end),
          )
          .fold<int>(
            0,
            (total, transaction) => total + transaction.amountPaise,
          );
      summaries.add(
        CreditCardSummary(
          issuer: first.cardIssuer!,
          lastDigits: first.cardLastDigits!,
          firstSeenMillis: first.timestampMillis,
          lastSeenMillis: last.timestampMillis,
          monthlySpendPaise: monthlySpend,
          transactionCount: grouped.length,
          confidence:
              grouped
                  .map((transaction) => transaction.confidence)
                  .reduce((a, b) => a + b) /
              grouped.length,
        ),
      );
    }
    summaries.sort(
      (a, b) => b.monthlySpendPaise.compareTo(a.monthlySpendPaise),
    );
    return summaries;
  }

  @override
  Future<DateTime?> lastScanAt() async => _lastScanAt;

  @override
  Future<int> monthlySpendPaise(DateTime month) async {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return _transactions.values
        .where(
          (transaction) =>
              transaction.direction == TransactionDirection.expense &&
              !transaction.timestamp.isBefore(start) &&
              transaction.timestamp.isBefore(end),
        )
        .fold<int>(0, (total, transaction) => total + transaction.amountPaise);
  }

  @override
  Future<List<FinanceTransaction>> recentTransactions({int limit = 20}) async {
    final transactions = _transactions.values.toList()
      ..sort((a, b) => b.timestampMillis.compareTo(a.timestampMillis));
    return transactions.take(limit).toList(growable: false);
  }

  @override
  Future<List<FinanceTransaction>> uncategorizedTransactions({
    int limit = 10,
  }) async {
    return _transactions.values
        .where(
          (transaction) =>
              transaction.categoryId == null &&
              transaction.direction == TransactionDirection.expense,
        )
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<void> saveLastScanAt(DateTime scannedAt) async {
    _lastScanAt = scannedAt;
  }

  @override
  Future<int> upsertTransactions(
    List<ParsedTransaction> transactions, {
    required DateTime createdAt,
  }) async {
    var inserted = 0;
    for (final transaction in transactions) {
      if (_hasDuplicateTransaction(transaction)) {
        continue;
      }
      _transactions[transaction.sourceSmsId] = transaction.toFinanceTransaction(
        id: _transactions.length + 1,
        createdAtMillis: createdAt.millisecondsSinceEpoch,
      );
      inserted += 1;
    }
    return inserted;
  }

  bool _hasDuplicateTransaction(ParsedTransaction transaction) {
    if (_transactions.containsKey(transaction.sourceSmsId)) {
      return true;
    }

    final referenceId = transaction.referenceId;
    if (referenceId != null && referenceId.length >= 6) {
      final hasReferenceMatch = _transactions.values.any(
        (existing) =>
            existing.referenceId == referenceId &&
            existing.amountPaise == transaction.amountPaise,
      );
      if (hasReferenceMatch) {
        return true;
      }
    }

    final merchantKey = _normalizeMatchText(transaction.merchantOrPayee);
    if (merchantKey.length < 3) {
      return false;
    }

    const duplicateWindowMillis = 2 * 60 * 1000;
    return _transactions.values.any((existing) {
      if (existing.normalizedSender == transaction.normalizedSender ||
          existing.amountPaise != transaction.amountPaise ||
          existing.direction != transaction.direction) {
        return false;
      }

      final timeDelta = (existing.timestampMillis - transaction.timestampMillis)
          .abs();
      if (timeDelta > duplicateWindowMillis) {
        return false;
      }

      return _similarMatchText(
        merchantKey,
        _normalizeMatchText(existing.merchantOrPayee),
      );
    });
  }
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

class _FakeCsvExportService implements CsvExportService {
  String? lastCsv;

  @override
  Future<String> exportCsv({
    required String fileName,
    required String csv,
  }) async {
    lastCsv = csv;
    return fileName;
  }
}

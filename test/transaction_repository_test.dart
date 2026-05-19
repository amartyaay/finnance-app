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
  Future<DateTime?> lastScanAt() async => _lastScanAt;

  @override
  Future<int> monthlySpendPaise(DateTime month) async {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return _transactions.values
        .where(
          (transaction) =>
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
        .where((transaction) => transaction.categoryId == null)
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
      if (_transactions.containsKey(transaction.sourceSmsId)) {
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

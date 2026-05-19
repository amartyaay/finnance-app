import '../data/transaction_store.dart';
import '../models/transaction_models.dart';
import '../services/csv_export_service.dart';
import '../services/import_parser_service.dart';
import '../services/sms_parser_service.dart';
import '../services/sms_reader_service.dart';

abstract class TransactionRepositoryBase {
  Future<ScanResult> scanInbox({int limit = 1000, int? sinceMillis});

  Future<List<FinanceTransaction>> recentTransactions({int limit = 20});

  Future<List<FinanceTransaction>> uncategorizedTransactions({int limit = 10});

  Future<int> monthlySpendPaise(DateTime month);

  Future<List<CreditCardSummary>> creditCardSummaries(DateTime month);

  Future<List<ExpenseCategory>> categories();

  Future<ExpenseCategory> addCategory(String name);

  Future<void> assignCategory({
    required int transactionId,
    required ExpenseCategory category,
  });

  Future<String> exportCsv();

  Future<DateTime?> lastScanAt();

  ImportBatchPreview previewImport(ImportFilePayload file);

  Future<ImportResult> confirmImport(ImportBatchPreview preview);
}

class TransactionRepository implements TransactionRepositoryBase {
  TransactionRepository({
    required this.smsReaderService,
    required this.smsParserService,
    required this.transactionStore,
    required this.csvExportService,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SmsReaderService smsReaderService;
  final SmsParserService smsParserService;
  final TransactionStore transactionStore;
  final CsvExportService csvExportService;
  final DateTime Function() _now;

  @override
  Future<ScanResult> scanInbox({int limit = 1000, int? sinceMillis}) async {
    final smsMessages = await smsReaderService.readInbox(
      limit: limit,
      sinceMillis: sinceMillis,
    );

    final parsedTransactions = <ParsedTransaction>[];
    for (final message in smsMessages) {
      final parsed = smsParserService.parse(message);
      if (parsed != null) {
        parsedTransactions.add(parsed);
      }
    }

    final scannedAt = _now();
    final inserted = await transactionStore.upsertTransactions(
      parsedTransactions,
      createdAt: scannedAt,
    );
    await transactionStore.saveLastScanAt(scannedAt);

    return ScanResult(
      totalSmsRead: smsMessages.length,
      parsedTransactions: parsedTransactions.length,
      insertedTransactions: inserted,
      scannedAt: scannedAt,
    );
  }

  @override
  Future<List<FinanceTransaction>> recentTransactions({int limit = 20}) {
    return transactionStore.recentTransactions(limit: limit);
  }

  @override
  Future<List<FinanceTransaction>> uncategorizedTransactions({int limit = 10}) {
    return transactionStore.uncategorizedTransactions(limit: limit);
  }

  @override
  Future<int> monthlySpendPaise(DateTime month) {
    return transactionStore.monthlySpendPaise(month);
  }

  @override
  Future<List<CreditCardSummary>> creditCardSummaries(DateTime month) {
    return transactionStore.creditCardSummaries(month);
  }

  @override
  Future<List<ExpenseCategory>> categories() {
    return transactionStore.categories();
  }

  @override
  Future<ExpenseCategory> addCategory(String name) {
    return transactionStore.addCategory(name);
  }

  @override
  Future<void> assignCategory({
    required int transactionId,
    required ExpenseCategory category,
  }) {
    return transactionStore.assignCategory(
      transactionId: transactionId,
      category: category,
      classifiedAt: _now(),
    );
  }

  @override
  Future<String> exportCsv() async {
    final transactions = await transactionStore.allTransactions();
    final csv = _toCsv(transactions);
    final timestamp = _fileTimestamp(_now());
    return csvExportService.exportCsv(
      fileName: 'finance-transactions-$timestamp.csv',
      csv: csv,
    );
  }

  @override
  Future<DateTime?> lastScanAt() => transactionStore.lastScanAt();

  @override
  ImportBatchPreview previewImport(ImportFilePayload file) {
    final batchId = _buildImportBatchId(file.name, _now());
    final registry = const ImportParserRegistry();
    return registry.parserFor(file.name).parse(file: file, batchId: batchId);
  }

  @override
  Future<ImportResult> confirmImport(ImportBatchPreview preview) async {
    final importedAt = _now();
    final inserted = await transactionStore.upsertTransactions(
      preview.transactions,
      createdAt: importedAt,
    );
    return ImportResult(
      previewedTransactions: preview.transactions.length,
      insertedTransactions: inserted,
      importedAt: importedAt,
    );
  }

  String _toCsv(List<FinanceTransaction> transactions) {
    final rows = <List<String>>[
      [
        'date',
        'amount',
        'category',
        'direction',
        'merchant_or_payee',
        'instrument',
        'sender',
        'account_or_card_hint',
        'reference_id',
        'card_issuer',
        'card_last_digits',
        'source_type',
        'source_label',
        'import_batch_id',
        'confidence',
      ],
      ...transactions.map(
        (transaction) => [
          DateTime.fromMillisecondsSinceEpoch(
            transaction.timestampMillis,
          ).toIso8601String(),
          (transaction.amountPaise / 100).toStringAsFixed(2),
          transaction.categoryName ?? 'Uncategorized',
          transaction.direction.name,
          transaction.merchantOrPayee ?? '',
          transaction.instrument.name,
          transaction.sender,
          transaction.accountOrCardHint ?? '',
          transaction.referenceId ?? '',
          transaction.cardIssuer ?? '',
          transaction.cardLastDigits ?? '',
          transaction.sourceType.name,
          transaction.sourceLabel ?? '',
          transaction.importBatchId ?? '',
          transaction.confidence.toStringAsFixed(2),
        ],
      ),
    ];

    return rows.map(_csvRow).join('\n');
  }

  String _csvRow(List<String> values) {
    return values.map(_csvCell).join(',');
  }

  String _csvCell(String value) {
    final escaped = value.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n') ||
        escaped.contains('\r')) {
      return '"$escaped"';
    }
    return escaped;
  }

  String _fileTimestamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return [
      time.year,
      two(time.month),
      two(time.day),
      two(time.hour),
      two(time.minute),
    ].join('');
  }

  String _buildImportBatchId(String fileName, DateTime time) {
    final safeName = fileName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return 'import-${_fileTimestamp(time)}-$safeName';
  }
}

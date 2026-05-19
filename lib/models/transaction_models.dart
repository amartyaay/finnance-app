enum TransactionDirection { expense, transfer }

enum TransactionInstrument {
  upi,
  debitCard,
  creditCard,
  account,
  wallet,
  unknown,
}

enum TransactionSourceType { sms, csv, pdf, screenshot, manual }

extension TransactionSourceTypeLabel on TransactionSourceType {
  String get displayName {
    switch (this) {
      case TransactionSourceType.sms:
        return 'SMS';
      case TransactionSourceType.csv:
        return 'CSV';
      case TransactionSourceType.pdf:
        return 'PDF';
      case TransactionSourceType.screenshot:
        return 'Screenshot';
      case TransactionSourceType.manual:
        return 'Manual';
    }
  }
}

class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.createdAtMillis,
  });

  factory ExpenseCategory.fromMap(Map<String, Object?> map) {
    return ExpenseCategory(
      id: map['id'] as int,
      name: map['name'] as String,
      isDefault: (map['is_default'] as int) == 1,
      createdAtMillis: map['created_at_millis'] as int,
    );
  }

  final int id;
  final String name;
  final bool isDefault;
  final int createdAtMillis;
}

class ParsedTransaction {
  const ParsedTransaction({
    required this.sourceSmsId,
    required this.sender,
    required this.normalizedSender,
    required this.timestampMillis,
    required this.amountPaise,
    required this.direction,
    required this.instrument,
    this.accountOrCardHint,
    this.merchantOrPayee,
    this.referenceId,
    this.cardIssuer,
    this.cardLastDigits,
    this.sourceType = TransactionSourceType.sms,
    this.sourceLabel,
    this.importBatchId,
    required this.confidence,
    this.categoryId,
    this.categoryName,
    this.classifiedAtMillis,
  });

  final String sourceSmsId;
  final String sender;
  final String normalizedSender;
  final int timestampMillis;
  final int amountPaise;
  final TransactionDirection direction;
  final TransactionInstrument instrument;
  final String? accountOrCardHint;
  final String? merchantOrPayee;
  final String? referenceId;
  final String? cardIssuer;
  final String? cardLastDigits;
  final TransactionSourceType sourceType;
  final String? sourceLabel;
  final String? importBatchId;
  final double confidence;
  final int? categoryId;
  final String? categoryName;
  final int? classifiedAtMillis;

  FinanceTransaction toFinanceTransaction({
    int? id,
    required int createdAtMillis,
  }) {
    return FinanceTransaction(
      id: id,
      sourceSmsId: sourceSmsId,
      sender: sender,
      normalizedSender: normalizedSender,
      timestampMillis: timestampMillis,
      amountPaise: amountPaise,
      direction: direction,
      instrument: instrument,
      accountOrCardHint: accountOrCardHint,
      merchantOrPayee: merchantOrPayee,
      referenceId: referenceId,
      cardIssuer: cardIssuer,
      cardLastDigits: cardLastDigits,
      sourceType: sourceType,
      sourceLabel: sourceLabel,
      importBatchId: importBatchId,
      confidence: confidence,
      categoryId: categoryId,
      categoryName: categoryName,
      classifiedAtMillis: classifiedAtMillis,
      createdAtMillis: createdAtMillis,
    );
  }
}

class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.sourceSmsId,
    required this.sender,
    required this.normalizedSender,
    required this.timestampMillis,
    required this.amountPaise,
    required this.direction,
    required this.instrument,
    this.accountOrCardHint,
    this.merchantOrPayee,
    this.referenceId,
    this.cardIssuer,
    this.cardLastDigits,
    this.sourceType = TransactionSourceType.sms,
    this.sourceLabel,
    this.importBatchId,
    required this.confidence,
    this.categoryId,
    this.categoryName,
    this.classifiedAtMillis,
    required this.createdAtMillis,
  });

  factory FinanceTransaction.fromMap(Map<String, Object?> map) {
    return FinanceTransaction(
      id: map['id'] as int?,
      sourceSmsId: map['source_sms_id'] as String,
      sender: map['sender'] as String,
      normalizedSender: map['normalized_sender'] as String,
      timestampMillis: map['timestamp_millis'] as int,
      amountPaise: map['amount_paise'] as int,
      direction: TransactionDirection.values.byName(map['direction'] as String),
      instrument: TransactionInstrument.values.byName(
        map['instrument'] as String,
      ),
      accountOrCardHint: map['account_hint'] as String?,
      merchantOrPayee: map['merchant'] as String?,
      referenceId: map['reference_id'] as String?,
      cardIssuer: map['card_issuer'] as String?,
      cardLastDigits: map['card_last_digits'] as String?,
      sourceType: TransactionSourceType.values.byName(
        (map['source_type'] as String?) ?? TransactionSourceType.sms.name,
      ),
      sourceLabel: map['source_label'] as String?,
      importBatchId: map['import_batch_id'] as String?,
      confidence: (map['confidence'] as num).toDouble(),
      categoryId: map['category_id'] as int?,
      categoryName: map['category_name'] as String?,
      classifiedAtMillis: map['classified_at_millis'] as int?,
      createdAtMillis: map['created_at_millis'] as int,
    );
  }

  final int? id;
  final String sourceSmsId;
  final String sender;
  final String normalizedSender;
  final int timestampMillis;
  final int amountPaise;
  final TransactionDirection direction;
  final TransactionInstrument instrument;
  final String? accountOrCardHint;
  final String? merchantOrPayee;
  final String? referenceId;
  final String? cardIssuer;
  final String? cardLastDigits;
  final TransactionSourceType sourceType;
  final String? sourceLabel;
  final String? importBatchId;
  final double confidence;
  final int? categoryId;
  final String? categoryName;
  final int? classifiedAtMillis;
  final int createdAtMillis;

  DateTime get timestamp =>
      DateTime.fromMillisecondsSinceEpoch(timestampMillis);

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'source_sms_id': sourceSmsId,
      'sender': sender,
      'normalized_sender': normalizedSender,
      'timestamp_millis': timestampMillis,
      'amount_paise': amountPaise,
      'direction': direction.name,
      'instrument': instrument.name,
      'account_hint': accountOrCardHint,
      'merchant': merchantOrPayee,
      'reference_id': referenceId,
      'card_issuer': cardIssuer,
      'card_last_digits': cardLastDigits,
      'source_type': sourceType.name,
      'source_label': sourceLabel,
      'import_batch_id': importBatchId,
      'confidence': confidence,
      'category_id': categoryId,
      'category_name': categoryName,
      'classified_at_millis': classifiedAtMillis,
      'created_at_millis': createdAtMillis,
    };
  }
}

class ImportBatchPreview {
  const ImportBatchPreview({
    required this.batchId,
    required this.sourceType,
    required this.sourceLabel,
    required this.fileName,
    required this.transactions,
    required this.warnings,
  });

  final String batchId;
  final TransactionSourceType sourceType;
  final String sourceLabel;
  final String fileName;
  final List<ParsedTransaction> transactions;
  final List<String> warnings;
}

class ImportResult {
  const ImportResult({
    required this.previewedTransactions,
    required this.insertedTransactions,
    required this.importedAt,
  });

  final int previewedTransactions;
  final int insertedTransactions;
  final DateTime importedAt;
}

class CreditCardSummary {
  const CreditCardSummary({
    required this.issuer,
    required this.lastDigits,
    required this.firstSeenMillis,
    required this.lastSeenMillis,
    required this.monthlySpendPaise,
    required this.transactionCount,
    required this.confidence,
  });

  factory CreditCardSummary.fromMap(Map<String, Object?> map) {
    return CreditCardSummary(
      issuer: map['card_issuer'] as String,
      lastDigits: map['card_last_digits'] as String,
      firstSeenMillis: map['first_seen_millis'] as int,
      lastSeenMillis: map['last_seen_millis'] as int,
      monthlySpendPaise: (map['monthly_spend_paise'] as num).toInt(),
      transactionCount: (map['transaction_count'] as num).toInt(),
      confidence: (map['confidence'] as num).toDouble(),
    );
  }

  final String issuer;
  final String lastDigits;
  final int firstSeenMillis;
  final int lastSeenMillis;
  final int monthlySpendPaise;
  final int transactionCount;
  final double confidence;

  DateTime get firstSeen =>
      DateTime.fromMillisecondsSinceEpoch(firstSeenMillis);

  DateTime get lastSeen => DateTime.fromMillisecondsSinceEpoch(lastSeenMillis);

  String get maskedDigits => 'xx$lastDigits';
}

class ScanResult {
  const ScanResult({
    required this.totalSmsRead,
    required this.parsedTransactions,
    required this.insertedTransactions,
    required this.scannedAt,
  });

  final int totalSmsRead;
  final int parsedTransactions;
  final int insertedTransactions;
  final DateTime scannedAt;
}

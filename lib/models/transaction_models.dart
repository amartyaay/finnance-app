enum TransactionDirection { expense, transfer }

enum TransactionInstrument {
  upi,
  debitCard,
  creditCard,
  account,
  wallet,
  unknown,
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
      'confidence': confidence,
      'category_id': categoryId,
      'category_name': categoryName,
      'classified_at_millis': classifiedAtMillis,
      'created_at_millis': createdAtMillis,
    };
  }
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

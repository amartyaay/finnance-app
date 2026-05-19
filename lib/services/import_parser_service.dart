import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../models/transaction_models.dart';

class ImportFilePayload {
  const ImportFilePayload({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List bytes;
}

abstract class ImportParser {
  ImportBatchPreview parse({
    required ImportFilePayload file,
    required String batchId,
  });
}

class CsvImportParser implements ImportParser {
  const CsvImportParser();

  @override
  ImportBatchPreview parse({
    required ImportFilePayload file,
    required String batchId,
  }) {
    final content = utf8.decode(file.bytes, allowMalformed: true);
    final rows = _CsvTable.parse(content);
    if (rows.isEmpty) {
      return ImportBatchPreview(
        batchId: batchId,
        sourceType: TransactionSourceType.csv,
        sourceLabel: _detectSourceLabel(file.name, content),
        fileName: file.name,
        transactions: const [],
        warnings: const ['CSV file did not contain readable rows.'],
      );
    }

    final header = rows.first.map(_normalizeHeader).toList(growable: false);
    final dataRows = rows.skip(1);
    final transactions = <ParsedTransaction>[];
    final warnings = <String>[];
    final sourceLabel = _detectSourceLabel(file.name, content);

    var rowNumber = 1;
    for (final row in dataRows) {
      rowNumber += 1;
      final mapped = _mapRow(header, row);
      final parsed = _parseMappedRow(
        mapped: mapped,
        rowNumber: rowNumber,
        batchId: batchId,
        sourceLabel: sourceLabel,
      );
      if (parsed == null) {
        warnings.add('Skipped row $rowNumber because it was incomplete.');
      } else {
        transactions.add(parsed);
      }
    }

    return ImportBatchPreview(
      batchId: batchId,
      sourceType: TransactionSourceType.csv,
      sourceLabel: sourceLabel,
      fileName: file.name,
      transactions: transactions,
      warnings: warnings,
    );
  }

  ParsedTransaction? _parseMappedRow({
    required Map<String, String> mapped,
    required int rowNumber,
    required String batchId,
    required String sourceLabel,
  }) {
    final amountText =
        _firstValue(mapped, const ['amount', 'debit', 'paid', 'withdrawal']) ??
        '';
    final amountPaise = _parseAmountPaise(amountText);
    if (amountPaise <= 0) {
      return null;
    }

    final dateText =
        _firstValue(mapped, const ['date', 'transactiondate', 'time']) ?? '';
    final timestamp = _parseDate(dateText);
    if (timestamp == null) {
      return null;
    }

    final merchant =
        _firstValue(mapped, const [
          'merchant',
          'description',
          'narration',
          'payee',
          'transactiondetails',
        ]) ??
        'Imported transaction';
    final referenceId =
        _firstValue(mapped, const ['referenceid', 'utr', 'rrn', 'transactionid']);
    final typeText =
        _firstValue(mapped, const ['type', 'direction', 'creditdebit']) ?? '';
    final direction = _detectDirection(typeText, amountText, merchant);
    final instrument = _detectInstrument(mapped, merchant, sourceLabel);
    final sourceSmsId = _buildImportSourceId(
      batchId: batchId,
      rowNumber: rowNumber,
      timestampMillis: timestamp.millisecondsSinceEpoch,
      amountPaise: amountPaise,
      merchant: merchant,
      referenceId: referenceId,
    );

    return ParsedTransaction(
      sourceSmsId: sourceSmsId,
      sender: sourceLabel,
      normalizedSender: _normalizeSourceLabel(sourceLabel),
      timestampMillis: timestamp.millisecondsSinceEpoch,
      amountPaise: amountPaise,
      direction: direction,
      instrument: instrument,
      merchantOrPayee: merchant.trim(),
      referenceId: referenceId?.trim().isEmpty == true
          ? null
          : referenceId?.trim(),
      sourceType: TransactionSourceType.csv,
      sourceLabel: sourceLabel,
      importBatchId: batchId,
      confidence: 0.72,
    );
  }
}

class StatementPdfImportParser implements ImportParser {
  const StatementPdfImportParser();

  @override
  ImportBatchPreview parse({
    required ImportFilePayload file,
    required String batchId,
  }) {
    return ImportBatchPreview(
      batchId: batchId,
      sourceType: TransactionSourceType.pdf,
      sourceLabel: _detectSourceLabel(file.name, ''),
      fileName: file.name,
      transactions: const [],
      warnings: const [
        'PDF statement import is planned but not implemented in this MVP.',
      ],
    );
  }
}

class ScreenshotOcrImportParser implements ImportParser {
  const ScreenshotOcrImportParser();

  @override
  ImportBatchPreview parse({
    required ImportFilePayload file,
    required String batchId,
  }) {
    return ImportBatchPreview(
      batchId: batchId,
      sourceType: TransactionSourceType.screenshot,
      sourceLabel: _detectSourceLabel(file.name, ''),
      fileName: file.name,
      transactions: const [],
      warnings: const [
        'Screenshot OCR import is planned but not implemented in this MVP.',
      ],
    );
  }
}

class ImportParserRegistry {
  const ImportParserRegistry({
    this.csvParser = const CsvImportParser(),
    this.pdfParser = const StatementPdfImportParser(),
    this.screenshotParser = const ScreenshotOcrImportParser(),
  });

  final ImportParser csvParser;
  final ImportParser pdfParser;
  final ImportParser screenshotParser;

  ImportParser parserFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.csv')) {
      return csvParser;
    }
    if (lower.endsWith('.pdf')) {
      return pdfParser;
    }
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp')) {
      return screenshotParser;
    }
    return csvParser;
  }
}

class _CsvTable {
  static List<List<String>> parse(String content) {
    final rows = <List<String>>[];
    final currentRow = <String>[];
    final currentCell = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < content.length; i += 1) {
      final char = content[i];
      if (char == '"') {
        if (inQuotes && i + 1 < content.length && content[i + 1] == '"') {
          currentCell.write('"');
          i += 1;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        currentRow.add(currentCell.toString().trim());
        currentCell.clear();
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && i + 1 < content.length && content[i + 1] == '\n') {
          i += 1;
        }
        currentRow.add(currentCell.toString().trim());
        currentCell.clear();
        if (currentRow.any((cell) => cell.isNotEmpty)) {
          rows.add(List<String>.from(currentRow));
        }
        currentRow.clear();
      } else {
        currentCell.write(char);
      }
    }

    currentRow.add(currentCell.toString().trim());
    if (currentRow.any((cell) => cell.isNotEmpty)) {
      rows.add(currentRow);
    }
    return rows;
  }
}

Map<String, String> _mapRow(List<String> header, List<String> row) {
  final mapped = <String, String>{};
  for (var i = 0; i < min(header.length, row.length); i += 1) {
    mapped[header[i]] = row[i];
  }
  return mapped;
}

String _normalizeHeader(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String? _firstValue(Map<String, String> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];
    if (value != null && value.trim().isNotEmpty) {
      return value;
    }
  }
  return null;
}

int _parseAmountPaise(String value) {
  final cleaned = value
      .replaceAll(',', '')
      .replaceAll(RegExp(r'(rs\.?|inr|\u20B9)', caseSensitive: false), '')
      .trim();
  final amount = double.tryParse(cleaned.replaceAll(RegExp(r'[^0-9.-]'), ''));
  if (amount == null) {
    return 0;
  }
  return (amount.abs() * 100).round();
}

DateTime? _parseDate(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final iso = DateTime.tryParse(trimmed);
  if (iso != null) {
    return iso;
  }

  final match = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{2,4})').firstMatch(
    trimmed,
  );
  if (match == null) {
    return null;
  }

  final day = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  var year = int.parse(match.group(3)!);
  if (year < 100) {
    year += 2000;
  }
  return DateTime(year, month, day);
}

TransactionDirection _detectDirection(
  String typeText,
  String amountText,
  String merchant,
) {
  final text = '$typeText $amountText $merchant'.toLowerCase();
  if (text.contains('credit') ||
      text.contains('refund') ||
      text.contains('cashback') ||
      text.contains('reversal')) {
    return TransactionDirection.transfer;
  }
  return TransactionDirection.expense;
}

TransactionInstrument _detectInstrument(
  Map<String, String> row,
  String merchant,
  String sourceLabel,
) {
  final text = '${row.values.join(' ')} $merchant $sourceLabel'.toLowerCase();
  if (text.contains('upi') || text.contains('vpa')) {
    return TransactionInstrument.upi;
  }
  if (text.contains('wallet') ||
      text.contains('phonepe') ||
      text.contains('gpay') ||
      text.contains('google pay') ||
      text.contains('paytm')) {
    return TransactionInstrument.wallet;
  }
  if (text.contains('credit card') || text.contains('card')) {
    return TransactionInstrument.creditCard;
  }
  if (text.contains('account') || text.contains('bank')) {
    return TransactionInstrument.account;
  }
  return TransactionInstrument.unknown;
}

String _detectSourceLabel(String fileName, String content) {
  final text = '$fileName $content'.toLowerCase();
  if (text.contains('phonepe')) {
    return 'PhonePe';
  }
  if (text.contains('gpay') || text.contains('googlepay')) {
    return 'Google Pay';
  }
  if (text.contains('hdfc')) {
    return 'HDFC Bank';
  }
  if (text.contains('icici')) {
    return 'ICICI Bank';
  }
  if (text.contains('sbi')) {
    return 'SBI';
  }
  return 'Imported file';
}

String _normalizeSourceLabel(String value) {
  return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '');
}

String _buildImportSourceId({
  required String batchId,
  required int rowNumber,
  required int timestampMillis,
  required int amountPaise,
  required String merchant,
  required String? referenceId,
}) {
  final fingerprint = [
    batchId,
    rowNumber,
    timestampMillis,
    amountPaise,
    merchant.trim().toLowerCase(),
    referenceId?.trim().toUpperCase() ?? '',
  ].join('|');
  return 'import_${_fnv1a64(fingerprint)}';
}

String _fnv1a64(String value) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0xffffffffffffffff;

  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * prime) & mask;
  }

  return hash.toRadixString(16).padLeft(16, '0');
}

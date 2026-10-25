import 'enums.dart';
import 'money.dart';

/// One financial event derived from an SMS (or a CSV import / manual entry).
class Txn {
  const Txn({
    required this.key,
    required this.occurredAtMs,
    required this.amountPaise,
    required this.kind,
    required this.instrument,
    this.id,
    this.smsId,
    this.sender,
    this.merchant,
    this.counterpartyVpa,
    this.categoryId,
    this.categoryName,
    this.categorySource = CategorySource.none,
    this.categoryKind = SpendCategoryKind.other,
    this.transferReason = TransferReason.none,
    this.cardKey,
    this.last4,
    this.issuer,
    this.referenceId,
    this.balanceAfterPaise,
    this.availableLimitPaise,
    this.confidence = 0.5,
    this.sourceType = TxnSourceType.sms,
    this.isDuplicateOfKey,
    this.needsReview = false,
    this.rawBody,
  });

  /// Deterministic dedupe key. Two alerts about the same event share it.
  final String key;

  final int? id;
  final int? smsId;
  final String? sender;
  final int occurredAtMs;

  /// Always positive; [kind] carries the direction.
  final int amountPaise;

  final TxnKind kind;
  final Instrument instrument;

  final String? merchant;
  final String? counterpartyVpa;
  final int? categoryId;
  final String? categoryName;
  final CategorySource categorySource;
  final SpendCategoryKind categoryKind;
  final TransferReason transferReason;

  /// `issuer|last4`, e.g. `HDFC Bank|1234`.
  final String? cardKey;
  final String? last4;
  final String? issuer;

  final String? referenceId;
  final int? balanceAfterPaise;

  /// Available credit limit reported in the alert, when present.
  final int? availableLimitPaise;

  final double confidence;
  final TxnSourceType sourceType;

  /// Set when this row was the loser of a duplicate merge.
  final String? isDuplicateOfKey;

  /// Parsed but too ambiguous to count silently (shown in review).
  final bool needsReview;

  final String? rawBody;

  DateTime get occurredAt => DateTime.fromMillisecondsSinceEpoch(occurredAtMs);
  Paise get amount => Paise(amountPaise);

  String get title {
    final name = merchant?.trim();
    if (name != null && name.isNotEmpty) return name;
    if (counterpartyVpa != null && counterpartyVpa!.isNotEmpty) {
      return counterpartyVpa!.split('@').first;
    }
    return switch (kind) {
      TxnKind.income => 'Money received',
      TxnKind.transfer => transferReason.label,
      TxnKind.cash => 'ATM withdrawal',
      TxnKind.spend => 'Payment',
    };
  }

  Txn copyWith({
    int? id,
    int? categoryId,
    String? categoryName,
    CategorySource? categorySource,
    SpendCategoryKind? categoryKind,
    TxnKind? kind,
    TransferReason? transferReason,
    String? isDuplicateOfKey,
    bool? needsReview,
  }) {
    return Txn(
      key: key,
      occurredAtMs: occurredAtMs,
      amountPaise: amountPaise,
      kind: kind ?? this.kind,
      instrument: instrument,
      id: id ?? this.id,
      smsId: smsId,
      sender: sender,
      merchant: merchant,
      counterpartyVpa: counterpartyVpa,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      categorySource: categorySource ?? this.categorySource,
      categoryKind: categoryKind ?? this.categoryKind,
      transferReason: transferReason ?? this.transferReason,
      cardKey: cardKey,
      last4: last4,
      issuer: issuer,
      referenceId: referenceId,
      balanceAfterPaise: balanceAfterPaise,
      availableLimitPaise: availableLimitPaise,
      confidence: confidence,
      sourceType: sourceType,
      isDuplicateOfKey: isDuplicateOfKey ?? this.isDuplicateOfKey,
      needsReview: needsReview ?? this.needsReview,
      rawBody: rawBody,
    );
  }
}

enum TxnSourceType { sms, csv, manual }

/// A credit-card bill/statement reminder captured from an SMS.
class CardBillNotice {
  const CardBillNotice({
    required this.cardKey,
    required this.totalDuePaise,
    this.minimumDuePaise,
    this.dueDateMs,
    this.statementDateMs,
    this.receivedAtMs,
  });

  final String cardKey;
  final int totalDuePaise;
  final int? minimumDuePaise;
  final int? dueDateMs;
  final int? statementDateMs;
  final int? receivedAtMs;

  DateTime? get dueDate =>
      dueDateMs == null ? null : DateTime.fromMillisecondsSinceEpoch(dueDateMs!);
}

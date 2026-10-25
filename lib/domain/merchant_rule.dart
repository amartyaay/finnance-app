import 'enums.dart';

/// A category the user taught the app, keyed by a normalised merchant
/// signature (see `MerchantSignature`).
///
/// Stored in `merchant_rules` and applied during ingest *before* the bundled
/// categoriser, so one correction keeps working on every future scan.
class MerchantRule {
  const MerchantRule({
    required this.signature,
    required this.categoryName,
    required this.categoryKind,
    this.hits = 0,
    this.sampleMerchant,
    this.createdAtMs,
    this.lastUsedAtMs,
  });

  /// Normalised merchant key, e.g. `pluxee meal`.
  final String signature;

  final String categoryName;
  final SpendCategoryKind categoryKind;

  /// How many ingested alerts this rule has categorised.
  final int hits;

  /// The merchant text that created the rule, for Settings ("Pluxee Meal ·
  /// Food & dining").
  final String? sampleMerchant;

  final int? createdAtMs;
  final int? lastUsedAtMs;

  DateTime? get createdAt => createdAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(createdAtMs!);

  DateTime? get lastUsedAt => lastUsedAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastUsedAtMs!);

  MerchantRule withHit({int atMs = 0}) => MerchantRule(
    signature: signature,
    categoryName: categoryName,
    categoryKind: categoryKind,
    hits: hits + 1,
    sampleMerchant: sampleMerchant,
    createdAtMs: createdAtMs,
    lastUsedAtMs: atMs,
  );

  MerchantRule copyWith({
    String? categoryName,
    SpendCategoryKind? categoryKind,
    int? hits,
    String? sampleMerchant,
    int? createdAtMs,
    int? lastUsedAtMs,
  }) => MerchantRule(
    signature: signature,
    categoryName: categoryName ?? this.categoryName,
    categoryKind: categoryKind ?? this.categoryKind,
    hits: hits ?? this.hits,
    sampleMerchant: sampleMerchant ?? this.sampleMerchant,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    lastUsedAtMs: lastUsedAtMs ?? this.lastUsedAtMs,
  );
}

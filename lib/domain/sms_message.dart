import 'enums.dart';

/// A single raw SMS, exactly as read from the inbox or captured by the
/// background receiver. Immutable: parsing never mutates the original text.
class SmsMessage {
  const SmsMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAtMs,
    this.readAtMs,
  });

  /// Stable id: the inbox `_ID` on Android, or `receiver:<hash>` for messages
  /// captured live by `TransactionSmsReceiver`.
  final String id;

  /// Raw sender, e.g. `VM-HDFCBK-T` or `+919876543210`.
  final String sender;

  final String body;
  final int receivedAtMs;
  final int? readAtMs;

  DateTime get receivedAt => DateTime.fromMillisecondsSinceEpoch(receivedAtMs);

  String get lowerBody => body.toLowerCase();

  @override
  String toString() => 'SmsMessage($id, $sender, ${body.length} chars)';
}

/// Weighted evidence produced by the classifier. Every decision in the app can
/// be explained to the user by listing these signals.
class SmsSignal {
  const SmsSignal(this.code, this.weight, {this.detail});

  /// Machine code, e.g. `known_sender`, `kyc_lure`, `has_otp_word`.
  final String code;

  /// Positive pushes towards `transaction`, negative away from it.
  final int weight;

  /// Optional human-readable detail for the "why?" sheet.
  final String? detail;

  @override
  String toString() => '$code(${weight >= 0 ? '+' : ''}$weight)';
}

/// Result of classifying one SMS.
class SmsAssessment {
  const SmsAssessment({
    required this.cls,
    required this.score,
    required this.signals,
    required this.senderTrust,
  });

  final SmsClass cls;

  /// 0..1 confidence in [cls].
  final double score;

  final List<SmsSignal> signals;
  final SenderTrust senderTrust;

  bool get isTransaction => cls == SmsClass.transaction;
  bool get isPhishing => cls == SmsClass.phishing;

  /// Top reasons for the UI, strongest first, never more than [max].
  List<SmsSignal> topSignals([int max = 3]) {
    final sorted = [...signals]..sort((a, b) => b.weight.abs().compareTo(a.weight.abs()));
    return sorted.take(max).toList(growable: false);
  }

  @override
  String toString() => 'SmsAssessment(${cls.name}, ${score.toStringAsFixed(2)})';
}

/// A parsed sender id.
class SenderId {
  const SenderId({
    required this.raw,
    required this.normalized,
    required this.trust,
    this.dltPrefix,
    this.dltCategory,
    this.entity,
    this.entityKind,
  });

  final String raw;

  /// Upper-case, DLT prefix/suffix stripped, non-alphanumerics removed.
  final String normalized;

  final SenderTrust trust;

  /// `VM`, `VK`, `AD`, `AX`, `TM`, `G`, `JD`… (Indian DLT header prefixes).
  final String? dltPrefix;

  /// `T` transactional, `P` promotional, `S` service-implicit, `G` government.
  final String? dltCategory;

  /// Human entity name when we can resolve it, e.g. `HDFC Bank`.
  final String? entity;

  /// `bank`, `card`, `wallet`, `broker`, `telecom`.
  final String? entityKind;

  @override
  String toString() => 'SenderId($raw -> $normalized, ${trust.name})';
}

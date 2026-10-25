/// Deterministic hashing shared by Dart and Kotlin.
///
/// The dedupe key of an SMS transaction must be identical whether the message
/// was captured live by the Android receiver or later by an inbox scan, so both
/// sides hash the same fields with the same algorithm.
library;

/// Unsigned 64-bit FNV-1a, printed as 16 hex chars.
///
/// `BigInt` (not `int`) because Dart web cannot represent 64-bit literals, and
/// signed 64-bit arithmetic would emit a `-` for half of all inputs, which the
/// Kotlin side (`ULong`) never does.
String fnv1a64(String value) {
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  for (final codeUnit in value.codeUnits) {
    hash = (hash ^ BigInt.from(codeUnit)) & mask;
    hash = (hash * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// Stable identity of a message's *content*, independent of the inbox row id.
///
/// Uses the raw sender (not the normalised one) so the Android receiver and the
/// Dart inbox scan compute exactly the same value for the same message.
String smsContentId({
  required String sender,
  required int receivedAtMs,
  required String body,
}) {
  return fnv1a64('$sender|$receivedAtMs|${body.trim()}');
}

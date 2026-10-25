/// Money is stored as integer **paise** everywhere (1 rupee = 100 paise).
///
/// Rationale: SMS amounts arrive as decimals ("Rs. 1,299.50"); storing rupees as
/// `double` loses a paisa on rounding and makes equality/dedupe unreliable.
/// Never store money as `double`.
library;

import 'package:intl/intl.dart';

/// A positive amount of money in paise.
extension type const Paise(int value) implements Object {
  static const Paise zero = Paise(0);

  bool get isZero => value == 0;
  bool get isPositive => value > 0;

  /// Rupees, for display only (never for arithmetic).
  double get rupees => value / 100.0;

  Paise operator +(Paise other) => Paise(value + other.value);
  Paise operator -(Paise other) => Paise(value - other.value);
  Paise operator *(int factor) => Paise(value * factor);

  bool operator >(Paise other) => value > other.value;
  bool operator <(Paise other) => value < other.value;
  bool operator >=(Paise other) => value >= other.value;
  bool operator <=(Paise other) => value <= other.value;
}

const String _rupee = '₹';

final NumberFormat _inrWhole = NumberFormat.currency(
  locale: 'en_IN',
  symbol: _rupee,
  decimalDigits: 0,
);
final NumberFormat _inrPaise = NumberFormat.currency(
  locale: 'en_IN',
  symbol: _rupee,
  decimalDigits: 2,
);

/// `₹1,29,900` — Indian lakh/crore grouping, no decimals when whole.
String inr(Paise amount, {bool forceDecimals = false}) {
  final formatter =
      (!forceDecimals && amount.value % 100 == 0) ? _inrWhole : _inrPaise;
  return formatter.format(amount.rupees);
}

/// `₹1.2L`, `₹24.5k` — for dense surfaces (chart axes, list rows, chips).
String inrCompact(Paise amount) {
  final abs = amount.value.abs();
  final sign = amount.value < 0 ? '-' : '';
  if (abs >= 10000000 * 100) {
    return '$sign$_rupee${_trimZeros(abs / (10000000 * 100))}Cr';
  }
  if (abs >= 100000 * 100) {
    return '$sign$_rupee${_trimZeros(abs / (100000 * 100))}L';
  }
  if (abs >= 1000 * 100) {
    return '$sign$_rupee${_trimZeros(abs / (1000 * 100))}k';
  }
  return '$sign$_rupee${(abs / 100).round()}';
}

/// Split for typographic emphasis: `₹` + grouped integer + optional `.25`.
({String symbol, String major, String? minor}) inrParts(Paise amount) {
  final negative = amount.value < 0;
  final abs = amount.value.abs();
  final major = abs ~/ 100;
  final minor = abs % 100;
  final grouped = NumberFormat.decimalPattern('en_IN').format(major);
  return (
    symbol: negative ? '-$_rupee' : _rupee,
    major: grouped,
    minor: minor == 0 ? null : '.${minor.toString().padLeft(2, '0')}',
  );
}

String _trimZeros(double value) {
  final text = value.toStringAsFixed(value < 10 ? 1 : 0);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// Parses an amount string from an SMS body into paise.
///
/// Handles `Rs.`, `Rs`, `INR`, `₹`, Indian comma grouping (`1,29,900`) and
/// western grouping (`129,900`), and 0–2 decimal places.
Paise? parseAmountToPaise(String raw) {
  var text = raw.trim().toLowerCase();
  text = text.replaceAll(RegExp(r'(rs\.?|inr|₹)'), '');
  text = text.replaceAll(',', '');
  text = text.replaceAll(RegExp(r'\s+'), '');
  if (text.isEmpty) return null;
  final parsed = double.tryParse(text);
  if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
  if (parsed < 0) return null;
  return Paise((parsed * 100).round());
}

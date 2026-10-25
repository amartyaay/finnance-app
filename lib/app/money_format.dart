/// **One money display rule for the whole app.**
///
/// Amounts are stored as integer [Paise] and are only ever formatted here. No
/// screen, sheet or chart formats a rupee amount on its own, so two lines of the
/// same card can never disagree about the same number again (the round-2 defect:
/// "₹812.52 a day" directly above "Spend / day ₹813").
///
/// The rule, in full:
///
/// 1. **₹1,000 and above → whole rupees.** Derived, averaged, projected and
///    aggregated figures round to the rupee, because paise at that size are noise:
///    a projection reads "₹25,188", never "₹25,188.12".
/// 2. **Below ₹1,000 → rupees, plus paise only when there are paise.** A whole
///    ₹813 prints "₹813". ₹812.52 keeps them, because rounding it would hide 52
///    paise of a number the user is meant to act on.
/// 3. **One format per value per screen.** When a value appears twice on a screen
///    (a headline and a stat column, a ring and its legend) both go through
///    [money]. [moneyCompact] is only for tight chrome whose value is not also
///    printed in full elsewhere on the same screen.
/// 4. **Always grouped, in Indian lakh/crore notation.** "₹1,05,590", never
///    "₹105590". Above a lakh the compact form may say "₹1.06L".
///
/// This is a thin wrapper over `inr`/`inrCompact` in `domain/money.dart`: those
/// two stay the low-level formatters, and all display rules live here.
library;

import 'package:intl/intl.dart';

import '../domain/money.dart';

/// ₹1,000 in paise: the boundary between "paise matter" and "paise are noise".
const int _wholeRupeePaise = 1000 * 100;

/// ₹1,00,000 in paise: the point where a magnitude suffix is shorter than the
/// grouped number, so [moneyCompact] switches to `₹1.2L` / `₹1.2Cr`.
const int _lakhPaise = 100000 * 100;

const String _rupee = '₹';

final NumberFormat _groupedRupees = NumberFormat.decimalPattern('en_IN');

/// The amount as the rule actually displays it: whole rupees at ₹1,000 and
/// above, exact paise below it.
///
/// Kept public so a screen can compare two values *after* rounding (e.g. "did
/// the number I show actually change?") instead of comparing raw paise.
Paise displayAmount(Paise amount) {
  if (amount.value.abs() < _wholeRupeePaise) return amount;
  return Paise((amount.value / 100).round() * 100);
}

/// The one full money formatter: `₹813`, `₹812.52`, `₹1,05,590`.
String money(Paise amount) {
  final shown = displayAmount(amount);
  if (shown.value.abs() < _wholeRupeePaise) return inr(shown);
  final sign = shown.value < 0 ? '-' : '';
  return '$sign$_rupee${_groupedRupees.format(shown.value.abs() ~/ 100)}';
}

/// Same precision rule, with a magnitude suffix above a lakh: `₹1.06L`, `₹1.2Cr`.
///
/// Only for chrome that cannot hold the grouped number — a card limit on a face,
/// a stat column, a chart axis. Below a lakh it returns exactly [money], so the
/// common case cannot drift from the headline on the same screen.
String moneyCompact(Paise amount) {
  final shown = displayAmount(amount);
  if (shown.value.abs() < _lakhPaise) return money(shown);
  return inrCompact(shown);
}

/// The same rule split for typographic emphasis, used by `MoneyText`:
/// `₹` + grouped integer, plus `.25` only when the rule keeps paise.
({String symbol, String major, String? minor}) moneyParts(Paise amount) {
  final shown = displayAmount(amount);
  return inrParts(shown);
}

/// Spoken form for semantics labels: no symbol, minus spoken as a word.
String moneySpoken(Paise amount) {
  final shown = money(amount);
  return shown
      .replaceFirst(_rupee, '')
      .replaceFirst('-', 'minus ');
}

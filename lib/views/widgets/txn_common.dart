import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../domain/enums.dart';
import '../../domain/transaction.dart';

/// One colour and icon per spend category, so a category looks the same on
/// Activity, Cards and Insights without each screen re-picking a hue. Keyed by
/// kind (never by rank), so a category keeps its colour as the month reorders.
/// Colour is never the only signal: every use pairs it with the category's
/// icon and name, and every chart prints names and amounts.
Color categoryColor(BuildContext context, SpendCategoryKind kind) {
  final dark = T.of(context).isDark;
  final (light, night) = _categoryHues[kind]!;
  return dark ? night : light;
}

/// (light theme, dark theme) — the dark variants are lifted for contrast on
/// near-black surfaces.
const Map<SpendCategoryKind, (Color, Color)> _categoryHues = {
  SpendCategoryKind.food: (Color(0xFFE0712C), Color(0xFFF59A5F)),
  SpendCategoryKind.groceries: (Color(0xFF2E9A55), Color(0xFF63CF8A)),
  SpendCategoryKind.transport: (Color(0xFF2F74C8), Color(0xFF6FA7EE)),
  SpendCategoryKind.shopping: (Color(0xFFD0457A), Color(0xFFF07EA9)),
  SpendCategoryKind.bills: (Color(0xFF5B57D6), Color(0xFF9592F2)),
  SpendCategoryKind.rent: (Color(0xFF9A6A3F), Color(0xFFD1A47A)),
  SpendCategoryKind.entertainment: (Color(0xFF8E4FD0), Color(0xFFBE8DF0)),
  SpendCategoryKind.health: (Color(0xFFD64545), Color(0xFFF08080)),
  SpendCategoryKind.education: (Color(0xFF1E8C8C), Color(0xFF5CC6C6)),
  SpendCategoryKind.travel: (Color(0xFF1C93B8), Color(0xFF63C7E6)),
  SpendCategoryKind.fuel: (Color(0xFFC28A12), Color(0xFFE8B84E)),
  SpendCategoryKind.investments: (Color(0xFF0E7C60), Color(0xFF5FD3AC)),
  SpendCategoryKind.transfers: (Color(0xFF5F6E7A), Color(0xFF9AAAB7)),
  SpendCategoryKind.income: (Color(0xFF16754A), Color(0xFF62D6A3)),
  SpendCategoryKind.cash: (Color(0xFF6E7B3A), Color(0xFFB4C26E)),
  SpendCategoryKind.other: (Color(0xFF7A7F87), Color(0xFFA9AEB6)),
};

IconData categoryIcon(SpendCategoryKind kind) => switch (kind) {
  SpendCategoryKind.food => Icons.restaurant_rounded,
  SpendCategoryKind.groceries => Icons.local_grocery_store_rounded,
  SpendCategoryKind.transport => Icons.directions_bus_rounded,
  SpendCategoryKind.shopping => Icons.shopping_bag_rounded,
  SpendCategoryKind.bills => Icons.receipt_long_rounded,
  SpendCategoryKind.rent => Icons.home_work_rounded,
  SpendCategoryKind.entertainment => Icons.movie_rounded,
  SpendCategoryKind.health => Icons.medical_services_rounded,
  SpendCategoryKind.education => Icons.school_rounded,
  SpendCategoryKind.travel => Icons.flight_takeoff_rounded,
  SpendCategoryKind.fuel => Icons.local_gas_station_rounded,
  SpendCategoryKind.investments => Icons.trending_up_rounded,
  SpendCategoryKind.transfers => Icons.swap_horiz_rounded,
  SpendCategoryKind.income => Icons.south_west_rounded,
  SpendCategoryKind.cash => Icons.local_atm_rounded,
  SpendCategoryKind.other => Icons.category_rounded,
};

String categoryKindLabel(SpendCategoryKind kind) => switch (kind) {
  SpendCategoryKind.food => 'Food',
  SpendCategoryKind.groceries => 'Groceries',
  SpendCategoryKind.transport => 'Transport',
  SpendCategoryKind.shopping => 'Shopping',
  SpendCategoryKind.bills => 'Bills',
  SpendCategoryKind.rent => 'Rent',
  SpendCategoryKind.entertainment => 'Entertainment',
  SpendCategoryKind.health => 'Health',
  SpendCategoryKind.education => 'Education',
  SpendCategoryKind.travel => 'Travel',
  SpendCategoryKind.fuel => 'Fuel',
  SpendCategoryKind.investments => 'Investments',
  SpendCategoryKind.transfers => 'Transfers',
  SpendCategoryKind.income => 'Income',
  SpendCategoryKind.cash => 'Cash',
  SpendCategoryKind.other => 'Other',
};

/// Category pickers only carry a display name, so recover the kind the engine
/// already assigned to that name, then fall back to the bundled name map.
SpendCategoryKind categoryKindForName(String name, List<Txn> transactions) {
  final needle = name.trim().toLowerCase();
  if (needle.isEmpty) return SpendCategoryKind.other;
  for (final txn in transactions) {
    final label = txn.categoryName?.trim().toLowerCase();
    if (label != null && label == needle) return txn.categoryKind;
  }
  for (final kind in SpendCategoryKind.values) {
    if (categoryKindLabel(kind).toLowerCase() == needle) return kind;
  }
  return _nameKinds[needle] ?? SpendCategoryKind.other;
}

const Map<String, SpendCategoryKind> _nameKinds = {
  'food & dining': SpendCategoryKind.food,
  'food and dining': SpendCategoryKind.food,
  'food': SpendCategoryKind.food,
  'dining': SpendCategoryKind.food,
  'groceries': SpendCategoryKind.groceries,
  'grocery': SpendCategoryKind.groceries,
  'transport': SpendCategoryKind.transport,
  'commute': SpendCategoryKind.transport,
  'shopping': SpendCategoryKind.shopping,
  'bills & utilities': SpendCategoryKind.bills,
  'bills and utilities': SpendCategoryKind.bills,
  'bills': SpendCategoryKind.bills,
  'utilities': SpendCategoryKind.bills,
  'rent': SpendCategoryKind.rent,
  'entertainment': SpendCategoryKind.entertainment,
  'health': SpendCategoryKind.health,
  'medical': SpendCategoryKind.health,
  'education': SpendCategoryKind.education,
  'travel': SpendCategoryKind.travel,
  'fuel': SpendCategoryKind.fuel,
  'investments': SpendCategoryKind.investments,
  'investment': SpendCategoryKind.investments,
  'transfers': SpendCategoryKind.transfers,
  'transfer': SpendCategoryKind.transfers,
  'income': SpendCategoryKind.income,
  'cash': SpendCategoryKind.cash,
  'other': SpendCategoryKind.other,
};

// Dates are formatted by hand rather than through intl locales so the app reads
// the same on every device, including one with a non-English locale.
const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> _monthsLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String monthYearLabel(DateTime date) =>
    '${_monthsLong[date.month - 1]} ${date.year}';

String shortDate(DateTime date) => '${date.day} ${_months[date.month - 1]}';

String shortDateWithYear(DateTime date) =>
    '${shortDate(date)} ${date.year}';

String clockTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final suffix = time.hour < 12 ? 'am' : 'pm';
  return '$hour:$minute $suffix';
}

String dayHeading(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(day.year, day.month, day.day);
  final difference = today.difference(target).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  return shortDate(day);
}

/// Relative label for a due date, phrased the way a bill reminder would be.
String daysUntilLabel(int days) {
  if (days < 0) return '${days.abs()}d overdue';
  if (days == 0) return 'due today';
  if (days == 1) return 'due tomorrow';
  return 'in $days days';
}

/// Whole **calendar** days until [due].
///
/// `CardMetrics.daysToDue` measures elapsed hours from an instant, so a bill due
/// tomorrow at midnight reads as 0 days at 11 pm tonight. The view counts dates
/// instead, so a bill is only "today" on the day it is actually due.
int daysUntilDate(DateTime due, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final today = DateTime(clock.year, clock.month, clock.day);
  final target = DateTime(due.year, due.month, due.day);
  return target.difference(today).inDays;
}

/// `due today` / `due tomorrow` / `due in 1 day` / `due in 6 days` /
/// `2 days overdue`. Exactly one day is always singular, so no bill label can
/// read "due in 1 days".
String billDuePhrase(int days) {
  if (days < 0) {
    final overdue = days.abs();
    return '$overdue ${overdue == 1 ? 'day' : 'days'} overdue';
  }
  if (days == 0) return 'due today';
  if (days == 1) return 'due tomorrow';
  return 'due in $days days';
}

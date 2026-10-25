import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../domain/enums.dart';
import '../../domain/transaction.dart';

/// One colour and icon per spend category, so a category looks the same on
/// Activity, Cards and Insights without each screen re-picking a hue. This is a
/// single-hue ramp keyed by kind (never by rank), so a category keeps its shade
/// as the month reorders, and a red-green colour-blind reader still sees
/// luminance steps. Every chart also prints names and amounts.
Color categoryColor(BuildContext context, SpendCategoryKind kind) {
  final palette = T.of(context).ramp;
  return palette[kind.index % palette.length];
}

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

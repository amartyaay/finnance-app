import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../app/design_tokens.dart';
import '../../domain/enums.dart';
import '../../domain/transaction.dart';
import '../../engine/monthly_summary.dart';
import '../../state/app_state.dart';

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
  SpendCategoryKind.food: (Color(0xFFE0712C), Color(0xFFFB923C)),
  SpendCategoryKind.groceries: (Color(0xFF2E9A55), Color(0xFF34D399)),
  SpendCategoryKind.transport: (Color(0xFF2F74C8), Color(0xFF60A5FA)),
  SpendCategoryKind.shopping: (Color(0xFFD0457A), Color(0xFF2DD4BF)),
  SpendCategoryKind.bills: (Color(0xFF5B57D6), Color(0xFFA78BFA)),
  SpendCategoryKind.rent: (Color(0xFF9A6A3F), Color(0xFF818CF8)),
  SpendCategoryKind.entertainment: (Color(0xFF8E4FD0), Color(0xFFF472B6)),
  SpendCategoryKind.health: (Color(0xFFD64545), Color(0xFFFB7185)),
  SpendCategoryKind.education: (Color(0xFF1E8C8C), Color(0xFF22D3EE)),
  SpendCategoryKind.travel: (Color(0xFF1C93B8), Color(0xFFC084FC)),
  SpendCategoryKind.fuel: (Color(0xFFC28A12), Color(0xFFFCD34D)),
  SpendCategoryKind.investments: (Color(0xFF0E7C60), Color(0xFF4ADE80)),
  SpendCategoryKind.transfers: (Color(0xFF5F6E7A), Color(0xFF94A3B8)),
  SpendCategoryKind.income: (Color(0xFF16754A), Color(0xFF34D399)),
  SpendCategoryKind.cash: (Color(0xFF6E7B3A), Color(0xFFA3E635)),
  SpendCategoryKind.other: (Color(0xFF7A7F87), Color(0xFF94A3B8)),
};

IconData categoryIcon(SpendCategoryKind kind) => switch (kind) {
  SpendCategoryKind.food => PhosphorIconsFill.forkKnife,
  SpendCategoryKind.groceries => PhosphorIconsFill.shoppingCart,
  SpendCategoryKind.transport => PhosphorIconsFill.car,
  SpendCategoryKind.shopping => PhosphorIconsFill.bag,
  SpendCategoryKind.bills => PhosphorIconsFill.receipt,
  SpendCategoryKind.rent => PhosphorIconsFill.house,
  SpendCategoryKind.entertainment => PhosphorIconsFill.filmSlate,
  SpendCategoryKind.health => PhosphorIconsFill.heartbeat,
  SpendCategoryKind.education => PhosphorIconsFill.graduationCap,
  SpendCategoryKind.travel => PhosphorIconsFill.airplaneTilt,
  SpendCategoryKind.fuel => PhosphorIconsFill.gasPump,
  SpendCategoryKind.investments => PhosphorIconsFill.trendUp,
  SpendCategoryKind.transfers => PhosphorIconsFill.arrowsLeftRight,
  SpendCategoryKind.income => PhosphorIconsFill.arrowDownLeft,
  SpendCategoryKind.cash => PhosphorIconsFill.money,
  SpendCategoryKind.other => PhosphorIconsFill.circlesFour,
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

String shortDateWithYear(DateTime date) => '${shortDate(date)} ${date.year}';

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

/// The app's clock: [AppState.now] when one is in the tree (a fixed date in
/// the demo and the renders), the wall clock otherwise. Views ask this instead
/// of `DateTime.now()`, so a countdown and the month it sits in agree.
DateTime viewNow(BuildContext context) {
  try {
    return Provider.of<AppState>(context, listen: false).now;
  } on ProviderNotFoundException {
    return DateTime.now();
  }
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

const _monthsShort = [
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

/// "20 – 26 Oct", or "29 Sep – 5 Oct" across a month boundary.
String weekRange(DateTime start) {
  final end = DateTime(start.year, start.month, start.day + 6);
  return start.month == end.month
      ? '${start.day} – ${end.day} ${_monthsShort[end.month - 1]}'
      : '${start.day} ${_monthsShort[start.month - 1]} – '
            '${end.day} ${_monthsShort[end.month - 1]}';
}

/// The period's name as a title: "Today", "Yesterday", "Mon 20 Oct";
/// "This week", "Last week", "6 – 12 Oct"; "October 2026".
String periodTitle(SpendPeriod period, DateTime start, int offset) =>
    switch (period) {
      SpendPeriod.day =>
        offset == 0
            ? 'Today'
            : offset == -1
            ? 'Yesterday'
            : '${_weekdays[start.weekday - 1]} ${start.day} '
                  '${_monthsShort[start.month - 1]}',
      SpendPeriod.week =>
        offset == 0
            ? 'This week'
            : offset == -1
            ? 'Last week'
            : weekRange(start),
      SpendPeriod.month => monthYearLabel(start),
    };

/// The line above the title: the dates the title stands for.
String periodSubtitle(SpendPeriod period, DateTime start) => switch (period) {
  SpendPeriod.day =>
    '${start.day} ${_monthsShort[start.month - 1]} ${start.year}',
  SpendPeriod.week => weekRange(start),
  SpendPeriod.month => '${start.year}',
};

/// For sentences: "today", "this week", "on 24 Oct", "in 6 – 12 Oct".
String periodPhrase(SpendPeriod period, DateTime start, int offset) =>
    switch (period) {
      SpendPeriod.day =>
        offset == 0
            ? 'today'
            : offset == -1
            ? 'yesterday'
            : 'on ${start.day} ${_monthsShort[start.month - 1]}',
      SpendPeriod.week =>
        offset == 0
            ? 'this week'
            : offset == -1
            ? 'last week'
            : 'in ${weekRange(start)}',
      SpendPeriod.month =>
        offset == 0 ? 'this month' : 'in ${monthYearLabel(start)}',
    };

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Day · Week · Month, as one glass track with a sliding teal pill.
class PeriodTabs extends StatelessWidget {
  const PeriodTabs({super.key, required this.value, required this.onChanged});

  final SpendPeriod value;
  final ValueChanged<SpendPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = T.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: T.glass(radius: T.r5),
      child: Row(
        children: [
          for (final period in SpendPeriod.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: period == value,
                label: '${period.label} view',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(period),
                  child: AnimatedContainer(
                    duration: T.fast,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: period == value
                          ? T.teal.withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(T.r5),
                      border: Border.all(
                        color: period == value
                            ? T.teal.withValues(alpha: 0.45)
                            : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      period.label,
                      style: T.body.copyWith(
                        color: period == value ? T.teal : p.inkSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

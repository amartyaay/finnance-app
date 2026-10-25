import '../domain/enums.dart';
import '../domain/money.dart';
import '../domain/transaction.dart';

/// A credit card as the user sees it.
class CardAccount {
  const CardAccount({
    required this.issuer,
    required this.last4,
    this.label,
    this.creditLimitPaise,
    this.statementDay,
    this.dueDay,
    this.isActive = true,
    this.id,
  });

  final int? id;
  final String issuer;
  final String last4;
  final String? label;
  final int? creditLimitPaise;
  final int? statementDay;
  final int? dueDay;
  final bool isActive;

  String get key => '$issuer|$last4';
  String get displayName => label?.isNotEmpty == true ? label! : issuer;
  String get masked => '•••• $last4';
  Paise? get creditLimit => creditLimitPaise == null ? null : Paise(creditLimitPaise!);

  /// `HDFC Bank •••• 1234`
  String get title => '$issuer $masked';

  CardAccount copyWith({
    String? label,
    int? creditLimitPaise,
    int? statementDay,
    int? dueDay,
    bool? isActive,
  }) {
    return CardAccount(
      id: id,
      issuer: issuer,
      last4: last4,
      label: label ?? this.label,
      creditLimitPaise: creditLimitPaise ?? this.creditLimitPaise,
      statementDay: statementDay ?? this.statementDay,
      dueDay: dueDay ?? this.dueDay,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// How a card's utilisation is doing, in words as well as colour.
enum UtilizationBand {
  excellent,
  healthy,
  watch,
  high,
  critical,
  unknown;

  String get label => switch (this) {
    excellent => 'Excellent',
    healthy => 'Healthy',
    watch => 'Watch',
    high => 'High',
    critical => 'Critical',
    unknown => 'Set a limit',
  };

  /// One calm sentence, never alarmist.
  String get advice => switch (this) {
    excellent => 'Well under the 30% mark. Nothing to do.',
    healthy => 'Comfortably below the 30% guideline.',
    watch => 'Above the 30% guideline — pay before the statement date.',
    high => 'This can affect your score. Clear part of it before the next statement.',
    critical => 'Very high. Clear most of it before the statement date if you can.',
    unknown => 'Add the card limit to see utilisation.',
  };
}

/// Everything about one card for the current statement cycle.
class CardMetrics {
  const CardMetrics({
    required this.card,
    required this.spentThisCyclePaise,
    required this.spentLastCyclePaise,
    required this.outstandingPaise,
    required this.availableLimitPaise,
    required this.utilization,
    required this.band,
    required this.statementDate,
    required this.dueDate,
    required this.daysToStatement,
    required this.daysToDue,
    required this.totalDuePaise,
    required this.minimumDuePaise,
    required this.txnCount,
    required this.projectedUtilization,
  });

  final CardAccount card;
  final int spentThisCyclePaise;
  final int spentLastCyclePaise;
  final int outstandingPaise;
  final int? availableLimitPaise;

  /// 0..1, or null when the limit is unknown.
  final double? utilization;
  final UtilizationBand band;

  final DateTime statementDate;
  final DateTime? dueDate;
  final int daysToStatement;
  final int? daysToDue;

  final int totalDuePaise;
  final int? minimumDuePaise;
  final int txnCount;

  /// Utilisation projected at the statement date if spending continues.
  final double? projectedUtilization;

  Paise get spentThisCycle => Paise(spentThisCyclePaise);
  Paise get spentLastCycle => Paise(spentLastCyclePaise);
  Paise get outstanding => Paise(outstandingPaise);
  Paise get totalDue => Paise(totalDuePaise);
  Paise get limit => Paise(card.creditLimitPaise ?? 0);
  Paise? get availableLimit =>
      availableLimitPaise == null ? null : Paise(availableLimitPaise!);
  Paise? get minimumDue =>
      minimumDuePaise == null ? null : Paise(minimumDuePaise!);

  bool get hasBill => totalDuePaise > 0;
  bool get dueSoon => daysToDue != null && daysToDue! <= 7 && totalDuePaise > 0;

  /// Remaining headroom before the 30% guideline.
  Paise? get headroomTo30 {
    final limit = card.creditLimitPaise;
    if (limit == null || limit <= 0) return null;
    final target = (limit * 0.3).round();
    return Paise((target - outstandingPaise).clamp(0, limit));
  }
}

/// Pure calculation of card metrics from transactions + user settings.
class CardMetricsCalculator {
  const CardMetricsCalculator();

  /// Statement cycle boundaries for [now] given a statement day of month.
  ({DateTime start, DateTime end}) cycleFor(DateTime now, int? statementDay) {
    final day = (statementDay ?? 1).clamp(1, 28);
    final thisMonth = DateTime(now.year, now.month, day);
    final start = now.isBefore(thisMonth)
        ? DateTime(now.year, now.month - 1, day)
        : thisMonth;
    final end = DateTime(start.year, start.month + 1, day);
    return (start: start, end: end);
  }

  CardMetrics compute({
    required CardAccount card,
    required List<Txn> transactions,
    required DateTime now,
    CardBillNotice? latestBill,
  }) {
    final cycle = cycleFor(now, card.statementDay);
    final prevCycleStart = DateTime(cycle.start.year, cycle.start.month - 1, cycle.start.day);

    var thisCycle = 0;
    var lastCycle = 0;
    var outstanding = 0;
    var count = 0;
    int? availableFromSms;
    var latestAvailableMs = -1;

    for (final txn in transactions) {
      if (txn.isDuplicateOfKey != null) continue;
      if (txn.cardKey != card.key) continue;
      final at = txn.occurredAt;
      final signed = switch (txn.kind) {
        TxnKind.spend => txn.amountPaise,
        TxnKind.transfer => -txn.amountPaise, // bill payment / refund to card
        TxnKind.income => -txn.amountPaise, // refund / reversal
        TxnKind.cash => txn.amountPaise,
      };

      if (!at.isBefore(cycle.start) && at.isBefore(cycle.end)) {
        thisCycle += signed;
        count++;
      } else if (!at.isBefore(prevCycleStart) && at.isBefore(cycle.start)) {
        lastCycle += signed;
      }
      outstanding += signed;
      if (txn.availableLimitPaise != null &&
          at.millisecondsSinceEpoch > latestAvailableMs) {
        availableFromSms = txn.availableLimitPaise;
        latestAvailableMs = at.millisecondsSinceEpoch;
      }
    }

    final limit = card.creditLimitPaise;
    final available = availableFromSms ??
        (limit != null ? (limit - outstanding).clamp(0, limit) : null);
    final derivedOutstanding = limit != null && available != null
        ? (limit - available).clamp(0, limit)
        : outstanding;
    final effectiveOutstanding = derivedOutstanding > outstanding
        ? derivedOutstanding
        : outstanding;

    double? utilization = (limit != null && limit > 0)
        ? (effectiveOutstanding / limit).clamp(0.0, 1.5)
        : null;

    final daysToStatement = cycle.end.difference(now).inDays;
    final daysElapsedInCycle = now.difference(cycle.start).inDays.clamp(1, 35);
    final cycleLength = cycle.end.difference(cycle.start).inDays;
    final daysRemaining = (cycleLength - daysElapsedInCycle).clamp(0, 35);

    // Project the *balance* forward at the cycle's own spending rate; projecting
    // utilisation directly multiplies the rate by the cycle length and produces
    // nonsense like "195% by statement".
    final dailyRate = thisCycle / daysElapsedInCycle;
    final projected =
        (limit != null && limit > 0 && utilization != null)
        ? ((effectiveOutstanding + dailyRate * daysRemaining) / limit)
              .clamp(0.0, 2.0)
        : null;

    final hasBill = (latestBill?.totalDuePaise ?? 0) > 0;
    var dueDate = hasBill ? latestBill!.dueDate : null;
    if (!hasBill && card.dueDay != null) {
      dueDate = _nextDayOfMonth(now, card.dueDay!);
    }
    // A bill notice can arrive late; a due date in the past means the *next*
    // cycle's date, not a negative countdown.
    if (dueDate != null) {
      var guard = 0;
      while (dueDate!.isBefore(DateTime(now.year, now.month, now.day)) &&
          guard < 12) {
        dueDate = DateTime(dueDate.year, dueDate.month + 1, dueDate.day);
        guard++;
      }
    }

    return CardMetrics(
      card: card,
      spentThisCyclePaise: thisCycle.clamp(0, 0x7FFFFFFFFFFFFFFF),
      spentLastCyclePaise: lastCycle.clamp(0, 0x7FFFFFFFFFFFFFFF),
      outstandingPaise: effectiveOutstanding.clamp(0, 0x7FFFFFFFFFFFFFFF),
      availableLimitPaise: available,
      utilization: utilization,
      band: bandFor(utilization, limit),
      statementDate: cycle.end,
      dueDate: dueDate,
      daysToStatement: daysToStatement,
      daysToDue: hasBill ? dueDate?.difference(now).inDays : null,
      totalDuePaise: latestBill?.totalDuePaise ?? 0,
      minimumDuePaise: latestBill?.minimumDuePaise,
      txnCount: count,
      projectedUtilization: projected,
    );
  }

  UtilizationBand bandFor(double? utilization, int? limit) {
    if (utilization == null || limit == null || limit <= 0) {
      return UtilizationBand.unknown;
    }
    if (utilization < 0.10) return UtilizationBand.excellent;
    if (utilization < 0.30) return UtilizationBand.healthy;
    if (utilization < 0.50) return UtilizationBand.watch;
    if (utilization < 0.75) return UtilizationBand.high;
    return UtilizationBand.critical;
  }

  DateTime _nextDayOfMonth(DateTime now, int day) {
    final clamped = day.clamp(1, 28);
    final thisMonth = DateTime(now.year, now.month, clamped);
    if (thisMonth.isBefore(DateTime(now.year, now.month, now.day))) {
      return DateTime(now.year, now.month + 1, clamped);
    }
    return thisMonth;
  }
}

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
    this.limitIsEstimated = false,
  });

  final int? id;
  final String issuer;
  final String last4;
  final String? label;
  final int? creditLimitPaise;
  final int? statementDay;
  final int? dueDay;
  final bool isActive;

  /// True when the limit was inferred from an `Avl Limit` alert rather than
  /// typed by the user, so the UI can label it "estimated".
  final bool limitIsEstimated;

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
    bool? limitIsEstimated,
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
      limitIsEstimated: limitIsEstimated ?? this.limitIsEstimated,
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

  /// One calm sentence, never alarmist. "Nothing to do" is deliberately absent:
  /// the card can still have an unpaid bill, and [CardMetrics.advice] adds it.
  String get advice => switch (this) {
    excellent => 'Well under the 30% mark.',
    healthy => 'Comfortably below the 30% guideline.',
    watch => 'Above the 30% guideline — pay before the statement date.',
    high => 'Above the 30% guideline. Clear part of it before the next statement.',
    critical => 'Very high. Clear most of it before the statement date if you can.',
    unknown => 'Add the card limit to see utilisation.',
  };
}

/// Which balance a utilisation figure is measured on.
enum UtilizationBasis {
  /// Reported bill (`Total Amount Due / limit`) — what a bureau sees.
  statement,

  /// Live outstanding from the parsed ledger.
  ledger,

  /// No limit or no balance: nothing can be shown.
  unknown;

  String get label => switch (this) {
    statement => 'Reported at statement',
    ledger => 'Live from transactions',
    unknown => 'No limit set',
  };

  String get short => switch (this) {
    statement => 'reported',
    ledger => 'live',
    unknown => '—',
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
    this.paymentsThisCyclePaise = 0,
    this.reportedUtilization,
    this.liveUtilization,
    this.utilisationBasis = UtilizationBasis.unknown,
    this.billDuePaise = 0,
    this.billStatementDate,
    this.creditBalancePaise = 0,
    this.dueDateLooksWrong = false,
  });

  final CardAccount card;

  /// Gross spend on the card this cycle (payments are not subtracted — "spent
  /// this cycle" is what was bought, not what is left).
  final int spentThisCyclePaise;
  final int spentLastCyclePaise;
  final int paymentsThisCyclePaise;
  final int outstandingPaise;
  final int? availableLimitPaise;

  /// The headline utilisation: reported-at-statement when a bill is known,
  /// otherwise live. 0..1, or null when the limit is unknown.
  final double? utilization;
  final UtilizationBand band;
  final UtilizationBasis utilisationBasis;

  /// `Total Amount Due / limit` — the number a bureau sees at statement.
  final double? reportedUtilization;

  /// `outstanding / limit` from the parsed ledger.
  final double? liveUtilization;

  final DateTime statementDate;
  final DateTime? dueDate;
  final int daysToStatement;
  final int? daysToDue;

  /// Total amount due as printed on the latest bill.
  final int totalDuePaise;
  final int? minimumDuePaise;

  /// What is still unpaid on that bill (total due minus payments since the
  /// statement date), never negative.
  final int billDuePaise;
  final DateTime? billStatementDate;
  final int txnCount;

  /// Utilisation projected at the statement date if spending continues.
  final double? projectedUtilization;

  /// Positive when payments exceeded spend — a credit balance on the card.
  final int creditBalancePaise;

  /// True when the bill's due date is implausibly close to its statement date
  /// (doc §4: a genuine bill gives at least 14 days).
  final bool dueDateLooksWrong;

  Paise get spentThisCycle => Paise(spentThisCyclePaise);
  Paise get spentLastCycle => Paise(spentLastCyclePaise);
  Paise get paymentsThisCycle => Paise(paymentsThisCyclePaise);
  Paise get outstanding => Paise(outstandingPaise);
  Paise get totalDue => Paise(totalDuePaise);
  Paise get billDue => Paise(billDuePaise);
  Paise get creditBalance => Paise(creditBalancePaise);
  Paise get limit => Paise(card.creditLimitPaise ?? 0);
  Paise? get availableLimit =>
      availableLimitPaise == null ? null : Paise(availableLimitPaise!);
  Paise? get minimumDue =>
      minimumDuePaise == null ? null : Paise(minimumDuePaise!);

  bool get hasBill => totalDuePaise > 0;
  bool get billIsPaid => hasBill && billDuePaise == 0;

  /// A card can be quiet this cycle and still owe a bill; it must stay visible.
  bool get hasBillButNoSpend => hasBill && billDuePaise > 0 && txnCount == 0;

  bool get dueSoon => daysToDue != null && daysToDue! <= 7 && billDuePaise > 0;

  String get utilizationLabel => utilisationBasis.label;

  String get reportedLabel => _pct(reportedUtilization);
  String get liveLabel => _pct(liveUtilization);
  String get projectedLabel => _pct(projectedUtilization);

  /// One sentence that always mentions an unpaid bill. This is what the card
  /// tile should show — "nothing to do" while ₹42,000 is due was the bug.
  String get advice {
    if (billDuePaise > 0) {
      final due = dueDate == null ? '' : ' by ${_shortDate(dueDate!)}';
      final min = minimumDuePaise == null || minimumDuePaise == 0
          ? ''
          : ' Minimum due ${inr(Paise(minimumDuePaise!))}.';
      final basis = utilisationBasis == UtilizationBasis.statement
          ? ' Reported utilisation $reportedLabel of the limit.'
          : '';
      return '${inr(Paise(billDuePaise))} bill due$due.$min'
          ' Paying the full amount avoids interest.$basis';
    }
    if (billIsPaid) {
      return 'Bill paid. Live utilisation $liveLabel.';
    }
    return band.advice;
  }

  /// Remaining headroom before the 30% guideline, on the reported balance when
  /// one is known (that is the number the guideline is about).
  Paise? get headroomTo30 {
    final limit = card.creditLimitPaise;
    if (limit == null || limit <= 0) return null;
    final target = (limit * 0.3).round();
    final used = utilisationBasis == UtilizationBasis.statement
        ? totalDuePaise
        : outstandingPaise;
    return Paise((target - used).clamp(0, limit));
  }

  static String _pct(double? value) =>
      value == null ? '—' : '${(value * 100).round()}%';

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _shortDate(DateTime date) =>
      '${date.day} ${_months[date.month - 1]}';
}

/// Pure calculation of card metrics from transactions + user settings.
class CardMetricsCalculator {
  const CardMetricsCalculator();

  /// Statement cycle boundaries for [now] given a statement day of month.
  ///
  /// On the statement day itself the cycle that just closed is returned, so the
  /// tile can say "statement today" instead of counting 31 days.
  ({DateTime start, DateTime end}) cycleFor(DateTime now, int? statementDay) {
    final day = statementDay ?? 1;
    final today = DateTime(now.year, now.month, now.day);
    final thisMonth = _dayInMonth(now.year, now.month, day);
    if (today == thisMonth) {
      return (start: _dayInMonth(now.year, now.month - 1, day), end: today);
    }
    final start = now.isBefore(thisMonth)
        ? _dayInMonth(now.year, now.month - 1, day)
        : thisMonth;
    return (start: start, end: _dayInMonth(start.year, start.month + 1, day));
  }

  /// `DateTime(y, m, 31)` rolls into the next month in Dart; a statement on the
  /// 31st must clamp to the last day of a short month, not skip it.
  static DateTime _dayInMonth(int year, int month, int day) {
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day.clamp(1, last));
  }

  CardMetrics compute({
    required CardAccount card,
    required List<Txn> transactions,
    required DateTime now,
    CardBillNotice? latestBill,
    bool attributeUnkeyedPayments = false,
  }) {
    final cycle = cycleFor(now, card.statementDay);
    final prevCycleStart =
        _dayInMonth(cycle.start.year, cycle.start.month - 1, cycle.start.day);

    var thisCycle = 0;
    var lastCycle = 0;
    var paymentsThisCycle = 0;
    var outstanding = 0;
    var count = 0;
    int? availableFromSms;
    var latestAvailableMs = -1;

    final billStatementMs =
        latestBill?.statementDateMs ?? latestBill?.receivedAtMs;
    var paidSinceStatement = 0;

    for (final txn in transactions) {
      if (txn.isDuplicateOfKey != null) continue;
      // A bill payment usually prints no card mask. When the issuer has exactly
      // one card, an unkeyed card-bill payment belongs to it — otherwise a paid
      // bill stayed on the card forever.
      final attributed = txn.cardKey == card.key ||
          (attributeUnkeyedPayments &&
              txn.cardKey == null &&
              txn.transferReason == TransferReason.creditCardBill &&
              (txn.issuer == card.issuer ||
                  txn.issuer == null ||
                  txn.issuer == card.displayName));
      if (!attributed) continue;
      final at = txn.occurredAt;
      final signed = switch (txn.kind) {
        TxnKind.spend => txn.amountPaise,
        TxnKind.transfer => -txn.amountPaise, // bill payment / refund to card
        TxnKind.income => -txn.amountPaise, // refund / reversal
        TxnKind.cash => txn.amountPaise,
      };

      if (txn.kind == TxnKind.spend) {
        if (!at.isBefore(cycle.start) && at.isBefore(cycle.end)) {
          thisCycle += txn.amountPaise;
        } else if (!at.isBefore(prevCycleStart) && at.isBefore(cycle.start)) {
          lastCycle += txn.amountPaise;
        }
      } else if (signed < 0) {
        if (!at.isBefore(cycle.start) && at.isBefore(cycle.end)) {
          paymentsThisCycle += -signed;
        }
        if (billStatementMs != null &&
            at.millisecondsSinceEpoch >= billStatementMs) {
          paidSinceStatement += -signed;
        }
      }
      if (!at.isBefore(cycle.start) && at.isBefore(cycle.end)) count++;
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

    double? ratio(int value) =>
        (limit != null && limit > 0) ? (value / limit).clamp(0.0, 1.5) : null;

    final live = ratio(effectiveOutstanding);
    final totalDue = latestBill?.totalDuePaise ?? 0;
    final reported =
        (limit != null && limit > 0 && totalDue > 0) ? ratio(totalDue) : null;
    final basis = reported != null
        ? UtilizationBasis.statement
        : (live != null ? UtilizationBasis.ledger : UtilizationBasis.unknown);
    final utilisation = reported ?? live;

    final daysToStatement = cycle.end.difference(now).inDays;
    final daysElapsedInCycle = now.difference(cycle.start).inDays.clamp(1, 35);
    final cycleLength = cycle.end.difference(cycle.start).inDays;
    final daysRemaining = (cycleLength - daysElapsedInCycle).clamp(0, 35);

    // Project the *balance* forward at the cycle's own spending rate; projecting
    // utilisation directly multiplies the rate by the cycle length and produces
    // nonsense like "195% by statement".
    final dailyRate = thisCycle / daysElapsedInCycle;
    final projected = (limit != null && limit > 0 && utilisation != null)
        ? ((effectiveOutstanding + dailyRate * daysRemaining) / limit)
              .clamp(0.0, 2.0)
        : null;

    var dueDate = totalDue > 0 ? latestBill?.dueDate : null;
    final dueMs = latestBill?.dueDateMs;
    if (totalDue == 0 && card.dueDay != null) {
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
    final billDue = totalDue - paidSinceStatement;

    bool dueDateWrong = false;
    if (totalDue > 0 && dueMs != null && billStatementMs != null) {
      final days = (dueMs - billStatementMs) ~/ Duration.millisecondsPerDay;
      dueDateWrong = days < 14;
    }

    return CardMetrics(
      card: card,
      spentThisCyclePaise: thisCycle.clamp(0, 0x1FFFFFFFFFFFFF).toInt(),
      spentLastCyclePaise: lastCycle.clamp(0, 0x1FFFFFFFFFFFFF).toInt(),
      paymentsThisCyclePaise: paymentsThisCycle.clamp(0, 0x1FFFFFFFFFFFFF).toInt(),
      outstandingPaise: effectiveOutstanding.clamp(0, 0x1FFFFFFFFFFFFF).toInt(),
      availableLimitPaise: available,
      utilization: utilisation,
      band: bandFor(utilisation, limit),
      utilisationBasis: basis,
      reportedUtilization: reported,
      liveUtilization: live,
      statementDate: cycle.end,
      dueDate: dueDate,
      daysToStatement: daysToStatement < 0 ? 0 : daysToStatement,
      daysToDue: totalDue > 0 ? dueDate?.difference(now).inDays : null,
      totalDuePaise: totalDue,
      minimumDuePaise: latestBill?.minimumDuePaise,
      billDuePaise: billDue.clamp(0, 0x1FFFFFFFFFFFFF).toInt(),
      billStatementDate: billStatementMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(billStatementMs),
      txnCount: count,
      projectedUtilization: projected,
      creditBalancePaise: (-outstanding).clamp(0, 0x1FFFFFFFFFFFFF).toInt(),
      dueDateLooksWrong: dueDateWrong,
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
    final thisMonth = _dayInMonth(now.year, now.month, day);
    if (thisMonth.isBefore(DateTime(now.year, now.month, now.day))) {
      return _dayInMonth(now.year, now.month + 1, day);
    }
    return thisMonth;
  }
}

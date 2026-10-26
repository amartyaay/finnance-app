import '../domain/enums.dart';
import '../domain/money.dart';
import '../domain/transaction.dart';

/// The span a summary covers: Home and Activity switch between them.
enum SpendPeriod {
  day,
  week,
  month;

  String get label => switch (this) {
    day => 'Day',
    week => 'Week',
    month => 'Month',
  };

  /// Start of the period [offset] steps from the one containing [now].
  /// Weeks run Monday to Sunday.
  DateTime start(DateTime now, int offset) => switch (this) {
    day => DateTime(now.year, now.month, now.day + offset),
    week => DateTime(
      now.year,
      now.month,
      now.day - (now.weekday - 1) + 7 * offset,
    ),
    month => DateTime(now.year, now.month + offset),
  };

  DateTime end(DateTime start) => switch (this) {
    day => DateTime(start.year, start.month, start.day + 1),
    week => DateTime(start.year, start.month, start.day + 7),
    month => DateTime(start.year, start.month + 1),
  };

  /// Whole periods between the one holding [oldest] and the one holding [now].
  int stepsBetween(DateTime oldest, DateTime now) {
    final steps = switch (this) {
      day => DateTime(
        now.year,
        now.month,
        now.day,
      ).difference(DateTime(oldest.year, oldest.month, oldest.day)).inDays,
      week => start(now, 0).difference(start(oldest, 0)).inDays ~/ 7,
      month => (now.year - oldest.year) * 12 + now.month - oldest.month,
    };
    return steps < 0 ? 0 : steps;
  }
}

/// Everything the dashboard needs, computed once per data change.
class MonthlySummary {
  const MonthlySummary({
    required this.monthStart,
    required this.spendPaise,
    required this.incomePaise,
    required this.cashPaise,
    required this.transferPaise,
    required this.txnCount,
    required this.byCategory,
    required this.dailySpend,
    required this.projectedSpendPaise,
    required this.previousSpendPaise,
    required this.daysElapsed,
    required this.daysInMonth,
    this.refundPaise = 0,
    this.cashbackPaise = 0,
    this.cardBillPaymentPaise = 0,
    this.otherInflowPaise = 0,
    this.period = SpendPeriod.month,
  });

  /// Which span this is; [monthStart] is its first instant whatever the span.
  final SpendPeriod period;

  final DateTime monthStart;
  final int spendPaise;

  /// **True income only**: salary, interest and other genuine income credits.
  /// Refunds, cashback, card-bill credits, wallet loads and self transfers are
  /// never counted here — that was the fictional "Came in ₹37k" number.
  final int incomePaise;
  final int cashPaise;
  final int transferPaise;
  final int txnCount;
  final List<CategoryTotal> byCategory;

  /// One bar per bucket so far: a day of the month or week (index 0 = the
  /// first day), or an hour of a single day.
  final List<int> dailySpend;

  /// Linear projection to month-end, weighted by the days actually elapsed.
  final int projectedSpendPaise;

  final int previousSpendPaise;
  final int daysElapsed;
  final int daysInMonth;

  /// Money returned for earlier purchases this month.
  final int refundPaise;

  /// Reward credits this month.
  final int cashbackPaise;

  /// Card bill payments made this month — money that actually left the bank
  /// account and went to a card issuer.
  final int cardBillPaymentPaise;

  /// Inflows that are real money but not income: refunds, cashback, wallet
  /// loads, P2P receipts, redeemals and self transfers.
  final int otherInflowPaise;

  Paise get spend => Paise(spendPaise);
  Paise get income => Paise(incomePaise);
  Paise get projectedSpend => Paise(projectedSpendPaise);
  Paise get previousSpend => Paise(previousSpendPaise);
  Paise get cash => Paise(cashPaise);
  Paise get refunds => Paise(refundPaise);
  Paise get cashback => Paise(cashbackPaise);
  Paise get cardBillPayments => Paise(cardBillPaymentPaise);

  /// Accrual spend: what the month cost, net of refunds (doc §5.5).
  Paise get netSpend => Paise(spendPaise - refundPaise);

  /// **Money out of the accounts this month**: consumption, ATM cash and card
  /// bill payments. This is what "Left"/"Over" must be measured against.
  int get moneyOutPaise => spendPaise + cashPaise + cardBillPaymentPaise;

  Paise get moneyOut => Paise(moneyOutPaise);

  /// What is actually left this month: true income minus money out. Negative
  /// means the user is down — shown as "Over", never as a positive "Left".
  int get leftPaise => incomePaise - moneyOutPaise;

  Paise get left => Paise(leftPaise);

  /// Older consumers used `income − spend`; kept so nothing silently breaks,
  /// but the hero uses [left].
  Paise get net => Paise(incomePaise - spendPaise);

  /// True when at least one genuine income credit was seen. Without it there is
  /// no honest savings rate.
  bool get hasTrueIncome => incomePaise > 0;

  /// Share of income kept after **accrual** spend (refunds reduce spend).
  /// Null when no income was seen — the caller must say so rather than invent
  /// a rate.
  double? get savingsRateOrNull {
    if (incomePaise <= 0) return null;
    return (incomePaise - netSpend.value) / incomePaise;
  }

  double get savingsRate => savingsRateOrNull ?? 0;

  /// Month-over-month change, e.g. 0.18 for +18%.
  double get monthOverMonth {
    if (previousSpendPaise <= 0) return 0;
    return (spendPaise - previousSpendPaise) / previousSpendPaise;
  }

  Paise get dailyAverage =>
      Paise(daysElapsed == 0 ? 0 : (spendPaise / daysElapsed).round());

  CategoryTotal? categoryFor(SpendCategoryKind kind) {
    for (final entry in byCategory) {
      if (entry.kind == kind) return entry;
    }
    return null;
  }

  static MonthlySummary empty(DateTime now) => MonthlySummary(
    monthStart: DateTime(now.year, now.month),
    spendPaise: 0,
    incomePaise: 0,
    cashPaise: 0,
    transferPaise: 0,
    txnCount: 0,
    byCategory: const [],
    dailySpend: const [],
    projectedSpendPaise: 0,
    previousSpendPaise: 0,
    daysElapsed: 0,
    daysInMonth: 30,
  );
}

class CategoryTotal {
  const CategoryTotal({
    required this.name,
    required this.kind,
    required this.paise,
    required this.txnCount,
    required this.share,
    required this.previousPaise,
  });

  final String name;
  final SpendCategoryKind kind;
  final int paise;
  final int txnCount;
  final double share;
  final int previousPaise;

  Paise get amount => Paise(paise);
  Paise get previous => Paise(previousPaise);

  double get change {
    if (previousPaise <= 0) return 0;
    return (paise - previousPaise) / previousPaise;
  }
}

/// Computes a [MonthlySummary] for the calendar month containing [now].
///
/// Calendar month (not card statement cycle) is what users expect from a spend
/// app; card cycles are handled separately in `CardMetrics`.
class SummaryCalculator {
  const SummaryCalculator();

  MonthlySummary forMonth(
    List<Txn> transactions,
    DateTime now, {
    int monthOffset = 0,
  }) => forPeriod(transactions, now, SpendPeriod.month, offset: monthOffset);

  /// A day (24 hourly bars), a Monday-to-Sunday week (7 bars) or a month (a
  /// bar per day), [offset] periods from the one holding [now]; "previous"
  /// is the period just before it.
  MonthlySummary forPeriod(
    List<Txn> transactions,
    DateTime now,
    SpendPeriod period, {
    int offset = 0,
  }) {
    final monthStart = period.start(now, offset);
    final monthEnd = period.end(monthStart);
    final prevStart = period.start(now, offset - 1);
    int bucketOf(DateTime at) => period == SpendPeriod.day
        ? at.hour
        : DateTime(at.year, at.month, at.day).difference(monthStart).inDays;

    var spend = 0;
    var income = 0;
    var cash = 0;
    var transfer = 0;
    var refunds = 0;
    var cashback = 0;
    var cardBills = 0;
    var otherInflow = 0;
    var count = 0;
    var prevSpend = 0;
    final byKind = <SpendCategoryKind, _Acc>{};
    final daily = <int>[];

    for (final txn in transactions) {
      // A row the parser was not sure about, or that lost a duplicate merge,
      // must not move a total before the user confirms it. It stays in the
      // review queue; `ARCHITECTURE.md §7` promises exactly this.
      if (txn.isDuplicateOfKey != null || txn.needsReview) continue;
      final at = _effectiveAt(txn, period);
      if (at.isBefore(monthStart) || !at.isBefore(monthEnd)) {
        if (at.isBefore(monthStart) &&
            !at.isBefore(prevStart) &&
            txn.kind == TxnKind.spend) {
          prevSpend += txn.amountPaise;
        }
        continue;
      }
      count++;
      final moneyIn = txn.moneyInKind;
      switch (txn.kind) {
        case TxnKind.spend:
          spend += txn.amountPaise;
          final acc = byKind.putIfAbsent(
            txn.categoryKind,
            () => _Acc(txn.categoryName ?? 'Other'),
          );
          acc.paise += txn.amountPaise;
          acc.count++;
          final dayIdx = bucketOf(at);
          while (daily.length <= dayIdx) {
            daily.add(0);
          }
          daily[dayIdx] += txn.amountPaise;
        case TxnKind.cash:
          cash += txn.amountPaise;
        case TxnKind.income:
          // "Came in" is true income only. `none` is a legacy/CSV row that has
          // no taxonomy yet; a reparsed SMS row always carries one.
          final trueIncome =
              moneyIn.isTrueIncome || moneyIn == MoneyInKind.none;
          if (trueIncome) {
            income += txn.amountPaise;
          } else {
            otherInflow += txn.amountPaise;
          }
        case TxnKind.transfer:
          transfer += txn.amountPaise;
          if (txn.transferReason == TransferReason.creditCardBill) {
            cardBills += txn.amountPaise;
          }
      }
      switch (moneyIn) {
        case MoneyInKind.refund:
          refunds += txn.amountPaise;
        case MoneyInKind.cashback:
          cashback += txn.amountPaise;
        default:
          break;
      }
    }

    // Calendar days, so a DST-free count: a month is 28–31, a week 7, a day 1.
    final daysInMonth =
        DateTime.utc(monthEnd.year, monthEnd.month, monthEnd.day)
            .difference(
              DateTime.utc(monthStart.year, monthStart.month, monthStart.day),
            )
            .inDays;
    final daysElapsed = !now.isBefore(monthEnd)
        ? daysInMonth
        : (DateTime.utc(now.year, now.month, now.day)
                      .difference(
                        DateTime.utc(
                          monthStart.year,
                          monthStart.month,
                          monthStart.day,
                        ),
                      )
                      .inDays +
                  1)
              .clamp(1, daysInMonth);
    final projected = daysElapsed == 0
        ? 0
        : (spend / daysElapsed * daysInMonth).round();

    // Previous month, per category, for month-over-month deltas.
    final prevByKind = <SpendCategoryKind, int>{};
    for (final txn in transactions) {
      if (txn.isDuplicateOfKey != null || txn.needsReview) continue;
      if (txn.kind != TxnKind.spend) continue;
      final at = txn.occurredAt;
      if (at.isBefore(prevStart) || !at.isBefore(monthStart)) continue;
      prevByKind.update(
        txn.categoryKind,
        (v) => v + txn.amountPaise,
        ifAbsent: () => txn.amountPaise,
      );
    }

    final categories =
        byKind.entries
            .map(
              (e) => CategoryTotal(
                name: e.value.label,
                kind: e.key,
                paise: e.value.paise,
                txnCount: e.value.count,
                share: spend == 0 ? 0 : e.value.paise / spend,
                previousPaise: prevByKind[e.key] ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.paise.compareTo(a.paise));

    return MonthlySummary(
      monthStart: monthStart,
      spendPaise: spend,
      incomePaise: income,
      cashPaise: cash,
      transferPaise: transfer,
      txnCount: count,
      byCategory: categories,
      dailySpend: daily,
      projectedSpendPaise: projected,
      previousSpendPaise: prevSpend,
      daysElapsed: daysElapsed,
      daysInMonth: daysInMonth,
      refundPaise: refunds,
      cashbackPaise: cashback,
      cardBillPaymentPaise: cardBills,
      otherInflowPaise: otherInflow,
      period: period,
    );
  }
}

/// A month-end salary pays for the month ahead: in India it lands on the
/// 28th–1st, and booking it to the month it arrived in made every month show
/// the *previous* month's pay and the current one "no salary" until payday.
/// For the month view, a salary credited on or after the 25th counts from the
/// 1st of the next month.
DateTime _effectiveAt(Txn txn, SpendPeriod period) {
  final at = txn.occurredAt;
  if (period != SpendPeriod.month ||
      txn.moneyInKind != MoneyInKind.salary ||
      at.day < 25) {
    return at;
  }
  return DateTime(at.year, at.month + 1);
}

class _Acc {
  _Acc(this.label);

  final String label;
  int paise = 0;
  int count = 0;
}

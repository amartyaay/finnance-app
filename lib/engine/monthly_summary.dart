import '../domain/enums.dart';
import '../domain/money.dart';
import '../domain/transaction.dart';

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
  });

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

  /// One entry per day of the month so far (index 0 = day 1).
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
  }) {
    final monthStart = DateTime(
      now.year,
      now.month + monthOffset,
    );
    final monthEnd = DateTime(now.year, now.month + monthOffset + 1);
    final prevStart = DateTime(monthStart.year, monthStart.month - 1);

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
      if (txn.isDuplicateOfKey != null) continue;
      final at = txn.occurredAt;
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
          final dayIdx = at.day - 1;
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

    final daysInMonth = monthEnd.difference(monthStart).inDays;
    final daysElapsed = now.isAfter(monthEnd)
        ? daysInMonth
        : (now.day).clamp(1, daysInMonth);
    final projected = daysElapsed == 0
        ? 0
        : (spend / daysElapsed * daysInMonth).round();

    // Previous month, per category, for month-over-month deltas.
    final prevByKind = <SpendCategoryKind, int>{};
    for (final txn in transactions) {
      if (txn.isDuplicateOfKey != null) continue;
      if (txn.kind != TxnKind.spend) continue;
      final at = txn.occurredAt;
      if (at.isBefore(prevStart) || !at.isBefore(monthStart)) continue;
      prevByKind.update(
        txn.categoryKind,
        (v) => v + txn.amountPaise,
        ifAbsent: () => txn.amountPaise,
      );
    }

    final categories = byKind.entries
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
    );
  }
}

class _Acc {
  _Acc(this.label);

  final String label;
  int paise = 0;
  int count = 0;
}

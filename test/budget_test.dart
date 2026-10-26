// The Budget tab and the 10 pm summary read the same numbers.
import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/transaction.dart';
import 'package:finnance_app/engine/budget.dart';
import 'package:finnance_app/engine/monthly_summary.dart';
import 'package:flutter_test/flutter_test.dart';

Txn _spend(
  String key,
  DateTime at,
  int rupees, {
  SpendCategoryKind cat = SpendCategoryKind.food,
  String name = 'Food & dining',
}) => Txn(
  key: key,
  occurredAtMs: at.millisecondsSinceEpoch,
  amountPaise: rupees * 100,
  kind: TxnKind.spend,
  instrument: Instrument.upi,
  categoryKind: cat,
  categoryName: name,
);

BudgetStatus _status(List<Txn> ledger, DateTime now, Budget budget) =>
    BudgetStatus.of(
      budget: budget,
      month: const SummaryCalculator().forMonth(ledger, now),
      ledger: ledger,
      now: now,
    );

void main() {
  final now = DateTime(2026, 10, 10, 22); // day 10 of 31
  final ledger = [
    _spend('a', DateTime(2026, 10, 2), 6000),
    _spend(
      'b',
      DateTime(2026, 10, 5),
      4000,
      cat: SpendCategoryKind.rent,
      name: 'Rent',
    ),
    _spend('c', DateTime(2026, 10, 10, 13), 500),
  ];

  test('left, pace and safe-to-spend from the same month', () {
    final s = _status(ledger, now, const Budget(monthlyPaise: 3100000));
    expect(s.spentPaise, 1050000);
    expect(s.leftPaise, 2050000);
    expect(s.todayPaise, 50000);
    expect(s.daysLeft, 22); // 10th to 31st
    expect(s.safePerDayPaise, 2050000 ~/ 22);
    // Even pace by day 10 is 10/31 of 31,000 = 10,000; 10,500 is within 10 %.
    expect(s.pace, BudgetPace.onTrack);
    expect(
      _status(ledger, now, const Budget(monthlyPaise: 2000000)).pace,
      BudgetPace.ahead,
    );
    expect(
      _status(ledger, now, const Budget(monthlyPaise: 1000000)).pace,
      BudgetPace.over,
    );
  });

  test('category limits measure that category only', () {
    final s = _status(
      ledger,
      now,
      const Budget(
        monthlyPaise: 3100000,
        categoryPaise: {SpendCategoryKind.food: 500000},
      ),
    );
    final food = s.categories.single;
    expect(food.spentPaise, 650000);
    expect(food.leftPaise, -150000);
  });

  test('the 10 pm text: spent today, what is left, per day from tomorrow', () {
    final d = DailyDigest.compose(
      _status(ledger, now, const Budget(monthlyPaise: 3100000)),
      topToday: 'Food & dining',
    );
    expect(d.title, 'You spent ₹500 today · mostly Food & dining');
    // 20,500 left over the 21 days after today.
    expect(d.body, contains('₹20,500 left of ₹31,000'));
    expect(d.body, contains('₹976 a day for the next 21 days'));
  });

  test('without a budget the summary still reports the month', () {
    final d = DailyDigest.compose(_status(ledger, now, const Budget()));
    expect(d.body, contains('₹10,500 spent this month'));
    expect(d.body, contains('Set a monthly budget'));
  });

  test('over budget says by how much', () {
    final d = DailyDigest.compose(
      _status(ledger, now, const Budget(monthlyPaise: 1000000)),
    );
    expect(d.body, contains('₹500 over budget'));
  });

  test(
    'a suggested budget is the median of the last full months, rounded up',
    () {
      final history = [
        _spend('s1', DateTime(2026, 7, 5), 41200),
        _spend('s2', DateTime(2026, 8, 5), 38050),
        _spend('s3', DateTime(2026, 9, 5), 52000),
      ];
      expect(BudgetStatus.suggestMonthly(history, now), 4200000);
    },
  );

  test('the plan survives a round trip through storage', () {
    const budget = Budget(
      monthlyPaise: 5000000,
      categoryPaise: {SpendCategoryKind.food: 800000},
      savingsGoalPaise: 2000000,
      dailyDigest: false,
    );
    final back = Budget.fromJson(budget.toJson());
    expect(back.monthlyPaise, 5000000);
    expect(back.categoryPaise[SpendCategoryKind.food], 800000);
    expect(back.savingsGoalPaise, 2000000);
    expect(back.dailyDigest, isFalse);
  });
}

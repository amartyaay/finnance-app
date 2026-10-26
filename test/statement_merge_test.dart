// An imported statement is the record for its account and period; SMS fill
// in other accounts, cards and the days after the statement ends.
import 'package:finnance_app/domain/enums.dart';
import 'package:finnance_app/domain/statement.dart';
import 'package:finnance_app/domain/transaction.dart';
import 'package:finnance_app/engine/monthly_summary.dart';
import 'package:finnance_app/engine/statement_merge.dart';
import 'package:flutter_test/flutter_test.dart';

final _coverage = StatementCoverage(
  accountKey: 'SBI:4642',
  bank: 'SBI',
  accountMask: '4642',
  from: DateTime(2026, 9, 1),
  to: DateTime(2026, 9, 30),
);

Txn _sms(
  String key,
  DateTime at,
  int paise, {
  TxnKind kind = TxnKind.spend,
  String issuer = 'State Bank of India',
  String sender = 'SBIUPI',
  String? last4 = '4642',
  String? cardKey,
  Instrument instrument = Instrument.upi,
  MoneyInKind moneyIn = MoneyInKind.none,
  TransferReason reason = TransferReason.none,
  String? dupOf,
  CategorySource source = CategorySource.rule,
  String? category,
}) => Txn(
  key: key,
  occurredAtMs: at.millisecondsSinceEpoch,
  amountPaise: paise,
  kind: kind,
  instrument: instrument,
  sender: sender,
  issuer: issuer,
  last4: last4,
  cardKey: cardKey,
  moneyInKind: moneyIn,
  transferReason: reason,
  isDuplicateOfKey: dupOf,
  categorySource: source,
  categoryName: category,
  rawBody: 'Rs ${paise ~/ 100} debited from A/c X$last4',
);

StatementRow _row(
  DateTime date,
  int debit, {
  int credit = 0,
  StatementKind kind = StatementKind.spend,
  String description = 'UPI/DR/1/SHOP',
}) {
  final row = StatementRow(
    date: date,
    description: description,
    debitPaise: debit,
    creditPaise: credit,
    balancePaise: 100000,
    balanceVerified: true,
    kind: kind,
    counterparty: 'SHOP',
    categoryName: 'Groceries',
    categoryKind: SpendCategoryKind.groceries,
  );
  return row.copyWith(key: row.identity('SBI:4642'));
}

List<Txn> _merge(List<Txn> sms, List<StatementRow> rows) => const StatementMerge()
    .merge(sms: sms, coverage: [_coverage], rows: {'SBI:4642': rows});

void main() {
  test("the account's alerts in the period give way to the statement", () {
    final out = _merge(
      [
        _sms('sbi-in', DateTime(2026, 9, 5, 10), 50000),
        _sms('sbi-after', DateTime(2026, 10, 2, 10), 70000),
        _sms(
          'hdfc-card',
          DateTime(2026, 9, 6, 10),
          30000,
          issuer: 'HDFC Bank',
          sender: 'HDFCBK',
          last4: '4821',
          cardKey: 'HDFC Bank|4821',
          instrument: Instrument.creditCard,
        ),
      ],
      [_row(DateTime(2026, 9, 5), 50000), _row(DateTime(2026, 9, 9), 12000)],
    );
    final keys = out.map((t) => t.key).toList();
    expect(keys, isNot(contains('sbi-in')));
    expect(keys, containsAll(['sbi-after', 'hdfc-card']));
    final statement = out.where((t) => t.sourceType == TxnSourceType.statement);
    expect(statement, hasLength(2));
    // The matched row keeps the alert's clock; the unmatched one sits at noon.
    expect(statement.first.occurredAt, DateTime(2026, 9, 5, 10));
    expect(statement.last.occurredAt, DateTime(2026, 9, 9, 12));

    const calc = SummaryCalculator();
    final september = calc.forMonth(out, DateTime(2026, 10, 2), monthOffset: -1);
    expect(september.spendPaise, 50000 + 12000 + 30000);
  });

  test('a debit-card alert from the same bank is the account too', () {
    final out = _merge(
      [
        _sms(
          'atm-card',
          DateTime(2026, 9, 4, 17),
          24500,
          sender: 'ATMSBI',
          last4: '7361',
          cardKey: 'State Bank of India|7361',
          instrument: Instrument.debitCard,
        ),
      ],
      [_row(DateTime(2026, 9, 4), 24500, description: 'POS ATM PURCH ZEPTO')],
    );
    expect(out.where((t) => t.isDuplicateOfKey == null), hasLength(1));
    expect(out.single.sourceType, TxnSourceType.statement);
  });

  test('a card bill is counted once: the issuer confirmation survives', () {
    final issuer = _sms(
      'issuer',
      DateTime(2026, 9, 11, 9),
      377200,
      kind: TxnKind.transfer,
      issuer: 'HDFC Bank',
      sender: 'HDFCBK',
      last4: '4821',
      cardKey: 'HDFC Bank|4821',
      instrument: Instrument.creditCard,
      moneyIn: MoneyInKind.cardPayment,
      reason: TransferReason.creditCardBill,
    );
    // With the bank's alert (a duplicate of the issuer's) …
    final withAlert = _merge(
      [
        issuer,
        _sms(
          'bank-leg',
          DateTime(2026, 9, 10, 20),
          377200,
          kind: TxnKind.transfer,
          reason: TransferReason.creditCardBill,
          dupOf: 'issuer',
        ),
      ],
      [_row(DateTime(2026, 9, 10), 377200, kind: StatementKind.cardBill)],
    );
    // … and without it (the bank never sent one).
    final withoutAlert = _merge(
      [issuer],
      [_row(DateTime(2026, 9, 10), 377200, kind: StatementKind.cardBill)],
    );
    for (final out in [withAlert, withoutAlert]) {
      final counted = out.where((t) => t.isDuplicateOfKey == null).toList();
      expect(counted.map((t) => t.key), ['issuer']);
      const calc = SummaryCalculator();
      final september = calc.forMonth(out, DateTime(2026, 10, 2), monthOffset: -1);
      expect(september.cardBillPaymentPaise, 377200);
    }
  });

  test("the user's category on the alert carries over", () {
    final out = _merge(
      [
        _sms(
          'sbi',
          DateTime(2026, 9, 5, 10),
          50000,
          source: CategorySource.user,
          category: 'Rent',
        ),
      ],
      [_row(DateTime(2026, 9, 5), 50000)],
    );
    expect(out.single.categoryName, 'Rent');
    expect(out.single.categorySource, CategorySource.user);
  });

  test('salary and transfers from the statement keep their meaning', () {
    final out = _merge(const [], [
      _row(DateTime(2026, 9, 30), 0, credit: 8750000, kind: StatementKind.salary),
      _row(DateTime(2026, 9, 12), 500000, kind: StatementKind.selfTransfer),
      _row(DateTime(2026, 9, 13), 0, credit: 2000, kind: StatementKind.otherCredit),
    ]);
    const calc = SummaryCalculator();
    final september = calc.forMonth(out, DateTime(2026, 10, 2), monthOffset: -1);
    expect(september.incomePaise, 8750000);
    expect(september.spendPaise, 0);
  });
}

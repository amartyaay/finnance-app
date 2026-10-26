// The owner books SBI fixed deposits after salary and breaks them mid-month;
// tops up an HDFC account that runs the SIPs. None of it is spend or income.
import 'package:finnance_app/domain/statement.dart';
import 'package:finnance_app/services/statement/statement_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

StatementRow _row(String narration, {int debit = 0, int credit = 0}) =>
    StatementRow(
      date: DateTime(2026, 9, 30),
      description: narration,
      debitPaise: debit,
      creditPaise: credit,
      balancePaise: 0,
    );

StatementRow _classify(StatementRow row) =>
    const StatementClassifier().classify(row, holderName: 'AMARTYA AYUSHI');

void main() {
  test('booking a fixed deposit is money parked', () {
    final r = _classify(_row(
      'WDL TFR FIRDFTFRREF: 235870087933192953K580035 0045612757291 OF '
      'Mr. AMARTYAAYUSHI AT 21092',
      debit: 1000000,
    ));
    expect(r.kind, StatementKind.investment);
    expect(r.counterparty, 'Fixed deposit');
  });

  test('the monthly recurring deposit instalment', () {
    final r = _classify(_row(
      'DIRECT DR 0044705924345 OFMr. AMARTYA AYUSHI AT 21092',
      debit: 500000,
    ));
    expect(r.kind, StatementKind.investment);
    expect(r.counterparty, 'Recurring deposit');
  });

  test('breaking a deposit mid-month is not income', () {
    final r = _classify(_row(
      'DEP TFR 0045612953193 OF Mr.AMARTYA AYUSHI AT 21092',
      credit: 1000000,
    ));
    expect(r.kind, StatementKind.redemption);
    expect(r.counterparty, 'Deposit closed');
  });

  test('a top-up of the HDFC account is invested from there', () {
    final r = _classify(_row(
      'WDL TFR UPI/DR/458408588321/Bank Acc/HDFC/5010061247/Paym '
      '0097694162092 AT 21092',
      debit: 2500000,
    ));
    expect(r.kind, StatementKind.investment);
    expect(r.counterparty, 'To your HDFC account');
  });
}

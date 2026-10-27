// Rent sent and the same amount sent back by the same person cancel out.
import 'package:finnance_app/data/statement_store.dart';
import 'package:finnance_app/domain/statement.dart';
import 'package:flutter_test/flutter_test.dart';

StatementRow _row(String who, DateTime d, {int debit = 0, int credit = 0}) =>
    StatementRow(
      date: d,
      description: who,
      debitPaise: debit,
      creditPaise: credit,
      balancePaise: 0,
      kind: debit > 0 ? StatementKind.spend : StatementKind.otherCredit,
      counterparty: who,
    );

void main() {
  test('a payment and its return from the same payee cancel', () {
    final rows = pairReturned([
      _row('BANOTH', DateTime(2026, 10, 1), debit: 1190000),
      _row('BANOTHU', DateTime(2026, 10, 1), credit: 1190000),
      _row('BANOTH', DateTime(2026, 10, 1), credit: 1190000),
    ]);
    expect(rows[0].kind, StatementKind.selfTransfer);
    expect(rows[2].kind, StatementKind.selfTransfer);
    // A different payee's credit of the same amount is left alone.
    expect(rows[1].kind, StatementKind.otherCredit);
  });

  test('a different amount, or a return weeks later, is not a return', () {
    final rows = pairReturned([
      _row('BANOTH', DateTime(2026, 9, 1), debit: 1300000),
      _row('BANOTH', DateTime(2026, 9, 2), credit: 1200000),
      _row('BANOTH', DateTime(2026, 9, 30), credit: 1300000),
    ]);
    expect(rows.map((r) => r.kind), [
      StatementKind.spend,
      StatementKind.otherCredit,
      StatementKind.otherCredit,
    ]);
  });
}

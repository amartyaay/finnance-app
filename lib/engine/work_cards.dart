import '../domain/enums.dart';
import '../domain/transaction.dart';

/// A corporate card is the employer's money: its purchases (business travel,
/// hotels) are reimbursed or billed to the company, so they must not count as
/// the owner's spend. The issuer says so in its alerts ("your AMEX Corp Card",
/// "statement for AMEX Corporate Card").
///
/// Such purchases stay in the ledger, booked as transfers under "Work card",
/// so they are visible but out of every personal total.
class WorkCards {
  const WorkCards();

  static final RegExp _corporate = RegExp(
    r'\bcorp(?:orate)?\.?\s+card\b',
    caseSensitive: false,
  );

  /// Card keys whose own alerts call them corporate.
  Set<String> detect(Iterable<Txn> ledger) => {
    for (final t in ledger)
      if (t.cardKey != null && _corporate.hasMatch(t.rawBody ?? '')) t.cardKey!,
  };

  List<Txn> apply(List<Txn> ledger) {
    final work = detect(ledger);
    if (work.isEmpty) return ledger;
    return [
      for (final t in ledger)
        t.kind == TxnKind.spend && work.contains(t.cardKey)
            ? t.copyWith(
                kind: TxnKind.transfer,
                categoryName: 'Work card',
                categoryKind: SpendCategoryKind.transfers,
              )
            : t,
    ];
  }
}

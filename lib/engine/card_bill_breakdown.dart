import '../domain/enums.dart';
import '../domain/transaction.dart';

/// What a credit-card bill payment paid for.
///
/// A bank statement shows one large "card bill" debit; the card's own SMS
/// show the purchases behind it. This groups the card's spends between the
/// previous payment to the same card and this one, by category. It is an
/// approximation of the billing cycle (the statement date is rarely known),
/// and the screen says so.
class CardBillBreakdown {
  const CardBillBreakdown({
    required this.cardKey,
    required this.from,
    required this.to,
    required this.byCategory,
    required this.count,
    required this.totalPaise,
  });

  final String cardKey;

  /// Exclusive start (the previous payment, or 45 days back) and inclusive end.
  final DateTime from;
  final DateTime to;

  /// Category name → paise, largest first.
  final List<({String name, SpendCategoryKind kind, int paise, int count})>
  byCategory;
  final int count;
  final int totalPaise;

  /// Null when [payment] is not a card bill or the card cannot be named.
  static CardBillBreakdown? of(Txn payment, List<Txn> ledger) {
    if (payment.transferReason != TransferReason.creditCardBill) return null;
    final card = payment.cardKey ?? _cardFromDuplicates(payment, ledger);
    if (card == null) return null;

    final to = payment.occurredAt;
    var from = to.subtract(const Duration(days: 45));
    for (final t in ledger) {
      if (t.key == payment.key || t.cardKey != card) continue;
      if (t.transferReason != TransferReason.creditCardBill) continue;
      if (t.isDuplicateOfKey != null) continue;
      if (t.occurredAt.isBefore(to) && t.occurredAt.isAfter(from)) {
        from = t.occurredAt;
      }
    }

    final groups = <String, ({SpendCategoryKind kind, int paise, int count})>{};
    var count = 0;
    var total = 0;
    for (final t in ledger) {
      if (t.cardKey != card || t.kind != TxnKind.spend) continue;
      if (t.isDuplicateOfKey != null || t.needsReview) continue;
      if (!t.occurredAt.isAfter(from) || t.occurredAt.isAfter(to)) continue;
      final name = t.categoryName ?? 'Other';
      final g = groups[name];
      groups[name] = (
        kind: t.categoryKind,
        paise: (g?.paise ?? 0) + t.amountPaise,
        count: (g?.count ?? 0) + 1,
      );
      count++;
      total += t.amountPaise;
    }
    final byCategory = [
      for (final e in groups.entries)
        (
          name: e.key,
          kind: e.value.kind,
          paise: e.value.paise,
          count: e.value.count,
        ),
    ]..sort((a, b) => b.paise.compareTo(a.paise));
    return CardBillBreakdown(
      cardKey: card,
      from: from,
      to: to,
      byCategory: byCategory,
      count: count,
      totalPaise: total,
    );
  }

  /// A statement row that was paired with the issuer's confirmation points at
  /// it; a confirmation can be pointed at by the row.
  static String? _cardFromDuplicates(Txn payment, List<Txn> ledger) {
    for (final t in ledger) {
      if (t.cardKey == null) continue;
      if (t.key == payment.isDuplicateOfKey ||
          t.isDuplicateOfKey == payment.key) {
        return t.cardKey;
      }
    }
    return null;
  }
}

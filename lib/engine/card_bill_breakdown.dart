import '../domain/enums.dart';
import '../domain/transaction.dart';

/// What a credit-card bill payment paid for.
///
/// A bank statement shows one large "card bill" debit; the card's own SMS
/// show the purchases behind it. A payment settles the latest card statement
/// generated before it, and that statement covers the purchases since the
/// statement before. When the card's statement SMS are on the phone, that is
/// the window; otherwise it falls back to "since the previous payment".
class CardBillBreakdown {
  const CardBillBreakdown({
    required this.cardKey,
    required this.from,
    required this.to,
    required this.byCategory,
    required this.count,
    required this.totalPaise,
    this.statementDate,
    this.statementTotalPaise,
  });

  final String cardKey;

  /// Exclusive start and inclusive end of the purchases counted.
  final DateTime from;
  final DateTime to;

  /// The card statement this payment settles, when its SMS was found.
  final DateTime? statementDate;
  final int? statementTotalPaise;

  final List<({String name, SpendCategoryKind kind, int paise, int count})>
  byCategory;
  final int count;
  final int totalPaise;

  bool get byStatement => statementDate != null;

  /// Null when [payment] is not a card bill or the card cannot be named.
  static CardBillBreakdown? of(
    Txn payment,
    List<Txn> ledger, {
    List<CardBillNotice> notices = const [],
  }) {
    if (payment.transferReason != TransferReason.creditCardBill) return null;
    final card = payment.cardKey ?? _cardFromDuplicates(payment, ledger);
    if (card == null) return null;
    final paidAt = payment.occurredAt;

    DateTime? noticeDate(CardBillNotice n) {
      final ms = n.statementDateMs ?? n.receivedAtMs;
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    }

    // The card's statements, oldest first, de-duplicated by day.
    final statements = <DateTime, CardBillNotice>{};
    for (final n in notices) {
      if (n.cardKey != card) continue;
      final d = noticeDate(n);
      if (d == null) continue;
      statements[DateTime(d.year, d.month, d.day)] = n;
    }
    final dates = statements.keys.toList()..sort();
    DateTime? settled;
    DateTime? before;
    for (var i = 0; i < dates.length; i++) {
      final d = dates[i];
      if (d.isAfter(paidAt)) break;
      if (paidAt.difference(d).inDays > 60) continue;
      settled = d;
      before = i > 0 ? dates[i - 1] : null;
    }

    late DateTime from;
    late DateTime to;
    if (settled != null) {
      // Through the end of the statement day, from the end of the previous
      // statement day (or a month back).
      to = settled.add(const Duration(days: 1));
      from = (before ?? settled.subtract(const Duration(days: 31))).add(
        const Duration(days: 1),
      );
    } else {
      to = paidAt;
      from = paidAt.subtract(const Duration(days: 45));
      for (final t in ledger) {
        if (t.key == payment.key || t.cardKey != card) continue;
        if (t.transferReason != TransferReason.creditCardBill) continue;
        if (t.isDuplicateOfKey != null) continue;
        if (t.occurredAt.isBefore(to) && t.occurredAt.isAfter(from)) {
          from = t.occurredAt;
        }
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
      statementDate: settled,
      statementTotalPaise: settled == null
          ? null
          : statements[settled]!.totalDuePaise,
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

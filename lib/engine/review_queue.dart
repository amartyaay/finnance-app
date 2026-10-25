import '../domain/enums.dart';
import '../domain/transaction.dart';

/// The "needs review" rule, in one place.
///
/// A row is surfaced when the parser could not be sure about something that
/// changes the numbers:
///
///   * **confidence < 0.6** — the evidence (sender trust, instrument, merchant,
///     reference, balance) was thin, whatever the reason;
///   * **a weak amount** — the chosen rupee figure came from a candidate that
///     scored below [minAmountScore]; a second figure in the same message may
///     be the real one;
///   * **an anonymous spend** — kind `spend` with neither a merchant nor a VPA,
///     so the money is counted but the user cannot recognise it.
///
/// The extractor uses [shouldReview] when it writes the row, and the
/// repository re-applies it on load so a flag written by an older build is
/// corrected without a re-scan.
class ReviewQueue {
  const ReviewQueue({this.cap = 20});

  /// Most rows the UI is asked to show at once.
  final int cap;

  /// Below this the row is always worth a look.
  static const double minConfidence = 0.6;

  /// `AmountFinder` scores below this are weak candidates.
  static const int minAmountScore = 4;

  static bool shouldReview({
    required TxnKind kind,
    required double confidence,
    String? merchant,
    String? vpa,
    int? amountScore,
  }) {
    if (confidence < minConfidence) return true;
    if (amountScore != null && amountScore < minAmountScore) return true;
    if (kind == TxnKind.spend && _blank(merchant) && _blank(vpa)) return true;
    return false;
  }

  /// The same rule over a stored row. Duplicates are never surfaced: the
  /// survivor is the row the user should act on.
  bool reviews(Txn txn) {
    if (txn.isDuplicateOfKey != null) return false;
    return shouldReview(
      kind: txn.kind,
      confidence: txn.confidence,
      merchant: txn.merchant,
      vpa: txn.counterpartyVpa,
      amountScore: txn.amountScore,
    );
  }

  /// Newest first, capped. `HomeData.needsReview` is this list.
  List<Txn> select(Iterable<Txn> transactions) {
    final flagged = transactions.where(reviews).toList(growable: false)
      ..sort((a, b) => b.occurredAtMs.compareTo(a.occurredAtMs));
    return flagged.take(cap).toList(growable: false);
  }

  /// Full count, not capped. Drives the badge while [select] drives the list.
  int count(Iterable<Txn> transactions) => transactions.where(reviews).length;

  static bool _blank(String? value) => value == null || value.trim().isEmpty;
}

import 'enums.dart';

/// One stored SMS as the "All messages" screen needs it.
///
/// Deliberately narrower than [SmsMessage]: the inbox list is paged, so the
/// query returns only the columns a row draws. Parsing still happens through
/// the same classifier/extractor the ingest path uses — nothing is re-invented
/// in the UI.
class SmsMessageRow {
  const SmsMessageRow({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAtMs,
    this.className,
    this.modelMoney,
  });

  final String id;

  /// The on-device model's P(money moved); null before processing.
  final double? modelMoney;

  /// Not counted by the rules, but the model is at least 90 % sure money moved.
  bool get possiblyMissed =>
      smsClass != SmsClass.transaction && (modelMoney ?? 0) >= 0.9;

  /// Raw DLT header, e.g. `VM-HDFCBK-T`.
  final String sender;
  final String body;
  final int receivedAtMs;

  /// Stored value of `sms_messages.class`; null when the message has never been
  /// processed.
  final String? className;

  DateTime get receivedAt => DateTime.fromMillisecondsSinceEpoch(receivedAtMs);

  /// The stored classifier bucket, or null when unknown/unparseable.
  SmsClass? get smsClass {
    final raw = className;
    if (raw == null) return null;
    for (final value in SmsClass.values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

/// Funnel counts for the header. Computed over every stored message, not over
/// the current page or filter, so the numbers stay stable while browsing.
class InboxStats {
  const InboxStats({
    required this.total,
    required this.transactions,
    required this.notCounted,
    required this.flagged,
    required this.unreviewed,
    this.possiblyMissed = 0,
  });

  final int total;
  final int transactions;
  final int notCounted;
  final int flagged;

  /// Messages the classifier could not place. Reviewing them is optional; the
  /// count is information, never a blocker.
  final int unreviewed;

  /// Not counted by the rules but likely a real payment (model ≥ 90 %).
  final int possiblyMissed;

  static const empty = InboxStats(
    total: 0,
    transactions: 0,
    notCounted: 0,
    flagged: 0,
    unreviewed: 0,
  );

  bool get isEmpty => total == 0;
}

/// Filter chips on the inbox screen. [slug] is what the repository receives.
enum InboxFilter {
  all('All', null),
  transactions('Transactions', 'transaction'),
  notCounted('Not counted', 'notCounted'),
  flagged('Flagged', 'flagged'),
  unreviewed('Unreviewed', 'unreviewed'),

  /// Not counted, but the on-device model thinks money moved. The short,
  /// worthwhile review queue (~12 a month on the owner's phone).
  possiblyMissed('Possibly missed', 'possiblyMissed');

  const InboxFilter(this.label, this.slug);

  final String label;

  /// Repository filter key; null means no class restriction.
  final String? slug;

  static InboxFilter fromSlug(String? slug) {
    for (final filter in values) {
      if (filter.slug == slug) return filter;
    }
    return InboxFilter.all;
  }
}

/// What a row's status chip says.
enum InboxRowStatus {
  transaction('Transaction'),
  notCounted('Not counted'),
  flagged('Flagged'),
  review('Review'),

  /// Rules did not count it; the on-device model thinks money moved.
  possiblyMissed('Possibly missed');

  const InboxRowStatus(this.label);

  final String label;
}

/// Resolves the row chip from the stored class plus whether a ledger row could
/// be parsed/found. A `transaction` message that yielded no amount is shown as
/// [InboxRowStatus.review] rather than a chip with no number.
InboxRowStatus inboxRowStatus(SmsMessageRow row, {required bool hasTransaction}) {
  if (row.possiblyMissed) return InboxRowStatus.possiblyMissed;
  switch (row.smsClass) {
    case SmsClass.phishing:
      return InboxRowStatus.flagged;
    case SmsClass.informational:
    case SmsClass.promo:
      return InboxRowStatus.notCounted;
    case SmsClass.transaction:
      return hasTransaction ? InboxRowStatus.transaction : InboxRowStatus.review;
    case SmsClass.unknown:
    case null:
      return InboxRowStatus.review;
  }
}



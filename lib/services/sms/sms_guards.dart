/// Text predicates that decide whether money actually moved.
///
/// The classifier ("what is this message?") and the extractor ("which row does
/// it become?") must agree, so the patterns live here instead of drifting.
library;

class SmsGuards {
  const SmsGuards._();

  /// Hard "no money moved" phrases: declines, failures, collect requests.
  static final RegExp _stopped = RegExp(
    r'\b(?:was declined|is declined|has been declined|declined|'
    r'no amount has been debited|has not been debited|not been debited|'
    r'has failed|failed to|requested (?:money|rs|inr|₹)|has requested|'
    r'payment request|collect request|approving the request)\b',
    caseSensitive: false,
  );

  /// Future-tense / reminder phrases. These are overridden by a completed
  /// past-tense movement, but never by a decline.
  static final RegExp _future = RegExp(
    r'\b(?:is due|are due|due on|due by|minimum due|amount due|total due|'
    r'pay now|pay before|avoid (?:late|penalty)|will be debited|will be charged|'
    r'scheduled (?:for|on)|upcoming|convert your transaction|reply yes to confirm|'
    r'first debit on)\b',
    caseSensitive: false,
  );

  static final RegExp _completed = RegExp(
    r'\b(?:has been|have been|was|were|is)\s+(?:credited|debited|paid|withdrawn|'
    r'reversed|refunded|deposited)\b',
    caseSensitive: false,
  );

  /// True when the message announces money that has *not* moved: a bill due
  /// date (J03/K08/I01), a decline (K18), a collect request (K13) or a mandate
  /// that was only set up (I07).
  static bool notMovedYet(String lower) {
    if (_stopped.hasMatch(lower)) return true;
    return _future.hasMatch(lower) && !_completed.hasMatch(lower);
  }

  /// Merchant-side receipt: the payer's device, not the user's account (K14).
  /// A message that still reports the user's own balance/limit is the customer's
  /// alert (H08/L06) and is kept.
  static final RegExp _receipt = RegExp(
    r'\bthank you for (?:your )?payment\b|\breceipt\s*:|\bmintoak\b|\bsmarthub\b|'
    r'\bmerchant copy\b',
    caseSensitive: false,
  );

  static bool merchantReceipt(String lower) => _receipt.hasMatch(lower);

  /// A reversal/chargeback returns money *to* the account that raised the debit,
  /// even when the message also says "debited" (G05).
  static final RegExp _reversal = RegExp(
    r'\bhas been (?:reversed|refunded|credited)\b|\b(?:reversal|chargeback)\b|'
    r'\bwas (?:reversed|refunded)\b',
    caseSensitive: false,
  );

  static final RegExp _reversalFailed = RegExp(
    r'\breversal failed\b|\breversal of failed\b',
    caseSensitive: false,
  );

  static bool isReversal(String lower) =>
      _reversal.hasMatch(lower) && !_reversalFailed.hasMatch(lower);

  /// A warning that *tells the user not to share* credentials is the opposite of
  /// a credential request (otp-01/03/06, info-09, K17).
  static final RegExp _shareNegation = RegExp(
    r"\b(?:do not|don't|never|not|no)\s+(?:to\s+)?(?:share|disclose|reveal|give)\b",
    caseSensitive: false,
  );

  static bool shareIsNegated(String lower) => _shareNegation.hasMatch(lower);

  /// A row may only become a transaction when money actually moved. Offer,
  /// eligibility, limit and cashback-*estimate* wording ("Loan of INR 36,000
  /// available for you") must never qualify, however large the number.
  static final RegExp _moneyMoved = RegExp(
    r'\b(?:debited|debit(?:ed)?|spent|paid|payment of|sent|withdrawn|withdrew|'
    r'charged|credited|refund(?:ed)?|deposited|deposit|reversed|deducted|billed|'
    r'transferred|received|purchase[sd]?|invested|allotted)\b',
    caseSensitive: false,
  );

  static bool moneyMoved(String lower) => _moneyMoved.hasMatch(lower);

  /// Bank footers like `SMS BLOCK 696 to 7459648006` are opt-out furniture, not
  /// a "your account is blocked" lure (H01-H04).
  static String stripDltFooter(String lower) => lower
      .replaceAll(RegExp(r'\bsms\s*block\s*\d+\s*to\s*\d+\b'), ' ')
      .replaceAll(RegExp(r'\bblock\s+\d{3,4}\s+to\s+\d{6,}\b'), ' ');
}

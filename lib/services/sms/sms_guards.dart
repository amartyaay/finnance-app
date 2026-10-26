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
    r'payment request|collect request|approving the request|'
    // A card spend restated as EMI is the same purchase, not new money.
    r'converted to \d+ months? emi|'
    r'terminated due to|'
    // A cheque in clearing has not reached the account yet.
    r'under clearing|sent for clearing|in clearing|'
    // Wallet promos: "Rs 5000 cashback credited* … claim before midnight".
    r'claim (?:before|now|it|your)|credited\*)',
    caseSensitive: false,
  );

  static final RegExp _creditedBack = RegExp(
    r'\b(?:has been |is |was )?credited\b(?! (?:within|in \d))',
    caseSensitive: false,
  );

  /// A failure stated without "has": "… at MYNTRA failed.", "could not be
  /// processed", "was unsuccessful". A reversal of a failed payment ("Rs 650
  /// reversed for your failed UPI txn") did move money back and is exempt.
  static final RegExp _bareFailure = RegExp(
    r'\b(?:failed|could not be (?:processed|completed)|'
    r"couldn't be (?:processed|completed)|(?:was|is) unsuccessful|unsuccessful)\b",
    caseSensitive: false,
  );

  /// Future-tense / reminder phrases. These are overridden by a completed
  /// past-tense movement, but never by a decline.
  static final RegExp _future = RegExp(
    r'\b(?:is due|are due|due on|due by|minimum due|amount due|total due|'
    r'pay now|pay before|avoid (?:late|penalty)|will be debited|will be charged|'
    r'scheduled (?:for|on)|upcoming|convert your transaction|reply yes to confirm|'
    r'first debit on|to be paid|has been initiated|is initiated|'
    r'will be auto[- ]?debited|will be deducted)\b',
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
    // "Rs 500 credited … as reversal of failed UPI txn" did move money back.
    if (_bareFailure.hasMatch(lower) &&
        !isReversal(lower) &&
        !_creditedBack.hasMatch(lower)) {
      return true;
    }
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

  /// A merchant/biller confirming the user's **completed** payment: "Recharge
  /// of INR 361.00 is successful", "Amount paid: Rs.349.00", "Your Swiggy
  /// Order … was successfully paid", "Booking confirmed … for Rs. 7950". Often
  /// the only record of a card or UPI payment whose bank alert never came, so
  /// it becomes a `receipt` row that the dedupe engine folds into the bank
  /// alert whenever there is one.
  static final RegExp _paidReceipt = RegExp(
    r'\brecharge (?:of (?:inr|rs\.?|₹)\s*[\d,.]+ )?(?:is |was |has been )?successful|'
    r'\brecharge successful\b|রিচার্জ সফল|'
    r'\b(?:bill )?payment of (?:inr|rs\.?|₹)\s*[\d,.]+ (?:was|is|has been) successful|'
    r'\bwas successfully paid\b|\bsuccessfully paid\b|\bamount paid\s*:|'
    // Not "Amount billed": with no bank debit behind it, a billed
    // subscription was usually never paid (its mandate was cancelled).
    r'\bpayment confirmed\b|'
    r'\bbooking confirmed\b.{0,300}\bfor (?:inr|rs\.?|₹)|'
    r'\bpayment of (?:inr|rs\.?|₹)\s*[\d,.]+ using [a-z ]{2,20} is successful|'
    r'\bfor (?:inr|rs\.?|₹)\s*[\d,.]+\s+(?:confirmed|done)\b|'
    r'\b(?:inr|rs\.?|₹)\s*[\d,.]+ done for .{2,60}\bhas succeeded\b|'
    r'\bwallet has been recharged with an amount of\b|'
    r'\bwe have processed (?:inr|rs\.?|₹)|'
    r'\byour payment of (?:inr|rs\.?|₹)\s*[\d,.]+ (?:has been |is |was )?received\b|'
    // "Your payment of Rs. 500 for the Application … is confirmed" (RRB).
    r'\byour payment of (?:inr|rs\.?|₹)\s*[\d,.]+\b.{0,120}\b(?:is|has been) (?:confirmed|successful)\b|'
    r'\bhas been deducted from your \w+ wallet\b',
    caseSensitive: false,
  );

  static final RegExp _receiptVeto = RegExp(
    r'\b(?:refund|failed|pending|cancel+ed|could have|could.ve|you can|'
    r'get (?:upto|up to|flat)|offer)\b',
    caseSensitive: false,
  );

  /// Jio prints the price as the plan name: "Recharge Successful ! Plan Name :
  /// 666.00 Jio Number : …" — no currency marker for the amount finder.
  static final RegExp _planAmount = RegExp(
    r'(?:plan name|প্ল্যানের নাম)\s*:\s*(\d{1,6}(?:\.\d{1,2})?)\b',
    caseSensitive: false,
  );

  static int? planAmountPaise(String body) {
    final match = _planAmount.firstMatch(body);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!);
    return value == null || value <= 0 ? null : (value * 100).round();
  }

  static bool paidReceipt(String lower) =>
      _paidReceipt.hasMatch(lower) && !_receiptVeto.hasMatch(lower);

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

  /// The "credited to your account by mistake, please return it" scam. A
  /// bank never asks for money back by SMS; the credit is usually fake.
  static final RegExp _mistakeScam = RegExp(
    r'\bby mistake\b.{0,100}\b(?:return|refund|send (?:it )?back|transfer back)\b|'
    r'\b(?:return|send back)\b.{0,60}\bby mistake\b',
    caseSensitive: false,
  );

  static bool mistakenCreditScam(String lower) => _mistakeScam.hasMatch(lower);

  /// A row may only become a transaction when money actually moved. Offer,
  /// eligibility, limit and cashback-*estimate* wording ("Loan of INR 36,000
  /// available for you") must never qualify, however large the number.
  static final RegExp _moneyMoved = RegExp(
    r'\b(?:debited|debit(?:ed)?|spent|paid|payment of|sent|withdrawn|withdrew|'
    r'charged|credited|refund(?:ed)?|deposited|deposit|reversed|deducted|billed|'
    r'transferred|received|purchase[sd]?|invested|allotted|has credit for)\b|'
    r'\btop[\s-]*up\b.{0,40}\bsuccessful\b|'
    // SBI debit-card POS alerts carry no verb: "transaction number … for
    // Rs.331.45 by SBI Debit Card X7361 done at 99999999 on 22Jun26".
    r'\bdebit card [x*]*\d{3,4} done at\b',
    caseSensitive: false,
  );

  static bool moneyMoved(String lower) => _moneyMoved.hasMatch(lower);

  /// A fund house / RTA confirming units for an SIP or purchase ("SIP Purchase
  /// in Folio … processed at the NAV of 18.78 for 159.736 units"). It is the
  /// receipt for a debit the bank already reported, so it never posts a row.
  static final RegExp _folio = RegExp(r'\bfolio\b', caseSensitive: false);
  static final RegExp _unitsWording = RegExp(
    r'\b(?:nav|units?|allotment|allotted|sip (?:purchase|instalment|request)|'
    r'systematic purchase|purchase of rs)\b',
    caseSensitive: false,
  );

  static bool fundHouseConfirmation(String lower) =>
      _folio.hasMatch(lower) && _unitsWording.hasMatch(lower);

  /// Bank footers like `SMS BLOCK 696 to 7459648006` are opt-out furniture, not
  /// a "your account is blocked" lure (H01-H04).
  static String stripDltFooter(String lower) => lower
      .replaceAll(RegExp(r'\bsms\s*block\s*\d+\s*to\s*\d+\b'), ' ')
      .replaceAll(RegExp(r'\bblock\s+\d{3,4}\s+to\s+\d{6,}\b'), ' ');
}

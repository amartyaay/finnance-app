import '../../domain/enums.dart';
import '../../domain/hashing.dart';
import '../../domain/sms_message.dart';
import '../../domain/transaction.dart';
import '../../engine/review_queue.dart';
import 'amount_finder.dart';
import 'sender_registry.dart';
import 'sms_guards.dart';

/// Turns a transaction-classified SMS into a structured [Txn].
///
/// The extractor never guesses silently: when the amount, direction or merchant
/// cannot be established with enough evidence, the row is returned with
/// `needsReview: true` so the UI can ask instead of polluting the totals.
class TransactionExtractor {
  TransactionExtractor({
    this.registry = const SenderRegistry(),
    this.amountFinder = const AmountFinder(),
  });

  final SenderRegistry registry;
  final AmountFinder amountFinder;

  static final RegExp _creditCardBill = RegExp(
    r'\b(?:credit\s*card|cc)\s*(?:bill|payment|repayment|dues?|outstanding)\b|'
    r'\b(?:bill\s*pay|billpay|billdesk|bbps|bharat\s*bill\s*pay)\b|'
    r'\b(?:payment|paid|received)\b.{0,40}\b(?:credit\s*card|card\s*bill|card\s*payment)\b|'
    r'\bthank you for (?:your )?payment\b',
    caseSensitive: false,
  );

  /// Two legs, both on the user's *own* accounts. `deposited to your a/c` (F06)
  /// and `reversed to your a/c` (G02) have one leg and are not self transfers.
  static final RegExp _selfTransfer = RegExp(
    r'\b(?:self\s*transfer|own\s+account|own\s+a/?c|between\s+your\s+accounts|to\s+self)\b|'
    r'\bfrom\s+your\b.{0,80}\bto\s+your\b',
    caseSensitive: false,
  );

  static final RegExp _walletLoad = RegExp(
    r'\b(?:upi\s*lite|wallet|paytm\s*wallet|amazon\s*pay\s*balance|mobikwik)\b.{0,50}'
    r'\b(?:top[\s-]*up|topup|load(?:ed)?|add(?:ed)?\s*(?:money|cash)|recharge|credit)\b|'
    r'\b(?:top[\s-]*up|topup|load(?:ed)?)\b.{0,40}\b(?:upi\s*lite|wallet)\b|'
    r'\badd(?:ed)?\s+to\s+(?:your\s+)?(?:paytm|amazon\s*pay|mobikwik|phonepe|google\s*pay)?\s*wallet\b',
    caseSensitive: false,
  );

  /// Investment wording, including the asset-manager names that real SIP
  /// alerts use instead of the word "SIP": `… deducted … towards ICICI
  /// Prudential Asset Managem …` is a mutual-fund purchase, not consumption.
  ///
  /// `mf` is guarded against the aggregator tag shape `EBA*MF-AXIS` (F02), which
  /// is a redemption merchant string, not an instruction to buy a fund.
  static final RegExp _investment = RegExp(
    r'\b(?:mutual\s*fund|sip|systematic\s+investment|demat|broker|zerodha|groww|'
    r'upstox|indmoney|smallcase|nps|ppf|fixed\s+deposit|recurring\s+deposit|'
    r'\bfd\b|\brd\b|stock|equity|ipo|'
    r'prudential|amc|asset\s*manag\w*|mf(?![-*])|nav|'
    // Real debit-mandate SIPs print the AMC's *name + folio code*, never the
    // word "SIP": `via Debit Mandate for NIPPONMUTUA_REL261124_…`.
    r'nippon|bandhan|kfin|motilal|white\s*oak|whiteoak|franklin|hdfc\s*mf|'
    r'icici\s*pru|debit\s*mandate)\b',
    caseSensitive: false,
  );

  /// A loan/EMI debit is repayment of principal, not consumption.
  static final RegExp _loanEmi = RegExp(
    r'\b(?:emi|loan\s*(?:emi|repayment|instal?ment|a/?c|account)|'
    r'(?:car|home|personal|two[- ]wheeler|education)\s*loan)\b',
    caseSensitive: false,
  );

  // ---- money-in taxonomy -------------------------------------------------

  /// Salary / wages. The only inflow that makes a savings rate meaningful.
  static final RegExp _salaryWord = RegExp(
    r'\b(?:salary|sal\s*cr|wages|payroll|pension|stipend|arrears|bonus\s+credit)\b',
    caseSensitive: false,
  );

  /// Interest / dividend credited to the user.
  static final RegExp _interestWord = RegExp(
    r'\b(?:interest|dividend)\b',
    caseSensitive: false,
  );

  /// A payment credited **to the user's own credit card** — the card bill being
  /// paid off. Never income.
  static final RegExp _cardPaymentCredit = RegExp(
    r'\b(?:payment|paid|amount)\b.{0,60}\bcredited to your card\b|'
    r'\bcredited to your card\b.{0,50}\b(?:payment|ref#|on)\b|'
    r'\bpayment\b.{0,80}\btowards your\b.{0,40}\bcredit\s*card\b|'
    r'\bthank you for (?:your )?payment\b|'
    r'\bpayment (?:of|towards)\b.{0,60}\b(?:credit\s*card|card\s*(?:number|no\.?|ending))\b',
    caseSensitive: false,
  );

  /// An FD/TD closing and paying its principal into the account.
  static final RegExp _redemptionWord = RegExp(
    r'\bclosure of (?:td|fd|term\s*deposit|fixed\s*deposit)\b|'
    r'\b(?:td|fd)\s*closure\b|\bon account of closure\b|'
    r'\b(?:maturity|matured)\b.{0,30}\b(?:proceeds|credited|paid)\b|'
    r'\bredemption\b|\bswitched?\s+out\b|'
    // Broker payouts (sale proceeds, unused margin) are the user's own money.
    r'\b(?:gr[o0]ww|zerodha|upstox|angel one|angel broking|icici securities)\b',
    caseSensitive: false,
  );

  static final RegExp _refundWord = RegExp(
    r'\b(?:refund(?:ed)?|reversal|reversed|chargeback|returned|vref)\b',
    caseSensitive: false,
  );

  static final RegExp _cashbackWord = RegExp(
    r'\b(?:cashback|cash\s*back|reward\s*points?|rewards?\s+credited)\b',
    caseSensitive: false,
  );

  /// A meal/flexi/wallet load. The Pluxee template puts the wallet *after* the
  /// credit verb (`… credited with Rs.2200 towards Meal Wallet`).
  static final RegExp _walletCreditWord = RegExp(
    r'\b(?:credited|loaded|top\s*up|topup)\b.{0,50}'
    r'\b(?:wallet|meal\s*wallet|pluxee|sodexo|flexi|upi\s*lite)\b|'
    r'\b(?:wallet|meal\s*wallet)\b.{0,40}\b(?:credited|loaded|top\s*up|topup)\b',
    caseSensitive: false,
  );

  /// A credit whose payer is a **named business** (a company suffix), not a
  /// person and not the user's own account. It is a genuine receipt whose
  /// source we cannot classify further: `MoneyInKind.other`, still income.
  /// An anonymous "credited to your a/c" never matches this — it stays a self
  /// transfer, because income is never assumed.
  static final RegExp _businessCreditWord = RegExp(
    r'\b(?:credited|received|deposited)\b.{0,80}\b(?:from|by)\b.{0,24}'
    r'\b[\w&.\-]+(?:\s+[\w&.\-]+){0,3}\s+'
    r'(?:pvt\.?|private|ltd\.?|limited|llp|inc\.?|corp(?:oration)?|'
    r'technologies|solutions|services|consult(?:ing|ancy))\b',
    caseSensitive: false,
  );

  /// A credit from another person / a named payer (P2P), not income.
  static final RegExp _p2pCreditWord = RegExp(
    r'\bdeposit by transfer\b|\bfrom\s+(?:Mr|Mrs|Ms|Dr)\.?\s|'
    r'\bfrom\s+vpa\b|\breceived from\b|\btransfer(?:red)? from\b|'
    r'\bby\s+(?:neft|imps|rtgs)\s+from\b',
    caseSensitive: false,
  );

  /// A wallet credit inside marketing copy (`Get Rs.100 wallet credit`,
  /// `get a Rs.750 Amazon Pay Gift Card`) is an offer, not a movement of money.
  static final RegExp _walletOfferWording = RegExp(
    r'\b(?:get|earn|win|upto|up to|save\s+(?:up\s*to\s*)?\d+|claim|grab|unlock)\b'
    r'.{0,40}\b(?:wallet|credits?|gift\s*card|voucher|cashback)\b|'
    r'\bwallet\s*credits?\b.{0,30}\bcode\b|'
    r'\bcode\s*:',
    caseSensitive: false,
  );

  /// A payout to a named beneficiary is a transfer, not consumption. The rail
  /// must be in a real phrase: `BIL*NEFT*HS92` is a reference token, not a rail
  /// (H03).
  static final RegExp _thirdPartyRail = RegExp(
    r'\b(?:via|by|through)\s+(?:neft|imps|rtgs|cheque)\b|'
    r'\b(?:neft|imps|rtgs)\s*(?:ref|utr|no)\b|'
    r'\bcheque\s*(?:no\.?|#)',
    caseSensitive: false,
  );

  /// A phone-number UPI handle is a person, not a shop (A09).
  static final RegExp _numericVpa = RegExp(r'\b\d{6,}@[a-z]');

  /// P2A marker: a UPI debit that carries no VPA handle and reports the
  /// counterparty bank as credited is an account-to-account transfer (A03).
  static final RegExp _upiWord = RegExp(r'\bupi\b', caseSensitive: false);
  static final RegExp _creditedWord = RegExp(r'\bcredited\b', caseSensitive: false);

  static final RegExp _cash = RegExp(
    r'\b(?:atm\s*(?:wdl|withdrawal|cash)|cash\s*withdrawal|'
    r'(?:withdrawn|wdl)\b.{0,40}\batm\b|\batm\b.{0,40}\b(?:withdrawn|wdl|withdrawal))\b',
    caseSensitive: false,
  );

  static final RegExp _vpaPattern = RegExp(
    r'\b([a-zA-Z0-9][a-zA-Z0-9._-]{1,40})@([a-zA-Z][a-zA-Z0-9.]{1,20})\b',
  );

  /// `Info:` payloads and `UPI/<ref>/<vpa>` rails print the counterparty VPA
  /// last and the account holder's own VPA first (F01).
  static final RegExp _payloadMarker = RegExp(
    r'\binfo\s*:|\bupi\s*[/:\-]',
    caseSensitive: false,
  );

  /// Account/card mask contexts. Real Indian masks are 3 digits (`XX742`),
  /// single-`x` (`x2210`), Amex 5 (`**91009`), hyphenated (`XX-7007`) or a
  /// multi-segment PAN (`7121-81XX-XXXX-7007`).
  static final RegExp _maskContext = RegExp(
    r'(?:a\s*/?\s*c(?:\s*no\.?)?|acct|acc(?:ount)?(?:\s*no\.?)?|'
    r'card(?:\s*(?:no\.?|number))?|ending(?:\s*(?:with|in|no\.?))?)'
    r'[\s:.#-]*',
    caseSensitive: false,
  );
  static final RegExp _maskSegment = RegExp(r'[xX*]{1,12}[\s-]*\d{3,5}');
  static final RegExp _bareMaskDigits = RegExp(r'^\s*(\d{3,5})(?!\d)');

  static final RegExp _billRef = RegExp(
    r'BIL(?:\*[A-Z0-9]+)+',
    caseSensitive: false,
  );

  static final RegExp _upiPayloadRef = RegExp(
    r'\bupi\s*[/:\-]\s*(?:p2[am]\s*[/:\-]\s*)?([A-Z0-9]{6,24})\b',
    caseSensitive: false,
  );

  static final RegExp _bracketRrn = RegExp(
    r'\(\s*upi\s*(?:ref\s*)?(\d{12})\s*\)',
    caseSensitive: false,
  );

  static final RegExp _orderRef = RegExp(
    r'\border(?:\s*id)?(?:\s*is|:|\s)\s*([A-Z0-9][A-Z0-9-]{5,24})\b|'
    r'\b([A-Z0-9][A-Z0-9-]{5,24})\s+is your order id\b',
    caseSensitive: false,
  );

  static final RegExp _refKeyword = RegExp(
    r'\b(?:ref(?:erence)?|refno|utr|rrn|txn(?:\s*(?:id|no\.?|#))?|transaction\s*(?:id|no\.?)|'
    r'trf\s*ref|imps\s*ref|neft\s*ref|cheque\s*(?:no\.?)?|nach(?:\s*mandate)?|mandate|loan)\b'
    r'\s*(?:no\.?|id)?\s*[:#.\-]*\s*([A-Z0-9][A-Z0-9*/-]{3,24})',
    caseSensitive: false,
  );

  /// Merchant names that are really bank/railway plumbing, not merchants.
  static const Set<String> _merchantNoise = {
    'your account', 'account', 'a/c', 'ac', 'bank', 'the bank', 'inr', 'rs',
    'upi', 'neft', 'imps', 'rtgs', 'txn', 'transaction', 'payment', 'paid',
    'debited', 'credited', 'invalid', 'info', 'ref', 'reference', 'balance',
    'avl', 'available', 'transfer', 'card', 'credit card', 'debit card',
  };

  /// Generic nouns that are never a merchant, checked as the *first* token so
  /// that "merchant refund" (G04) survives while "dispute" (A02) does not.
  static const Set<String> _merchantStop = {
    'dispute', 'disputes', 'refund', 'payment', 'payments', 'charge', 'charges',
    'fee', 'fees', 'confirm', 'cancel', 'available', 'limit', 'info', 'visit',
    'call', 'sms', 'report', 'block', 'help', 'details', 'notice', 'alert',
    'request', 'order', 'due', 'credit', 'debit', 'interest', 'cheque', 'cdm',
    'bbps', 'atm', 'pos', 'neft', 'imps', 'rtgs', 'wallet', 'balance',
    'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'sept',
    'oct', 'nov', 'dec', 'you', 'your', 'the', 'and',
  };

  static const Set<String> _monthToken = {
    'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'sept',
    'oct', 'nov', 'dec',
  };

  static const Set<String> _bankWords = {
    'hdfc', 'icici', 'sbi', 'axis', 'kotak', 'idfc', 'rbl', 'indusind', 'yes',
    'au', 'federal', 'hsbc', 'amex', 'american express', 'onecard', 'canara',
    'pnb', 'bob', 'union', 'dbs', 'citibank', 'standard chartered', 'cred',
  };

  /// Anchor prepositions, in priority order. `from` first: on a credit it names
  /// the payer, and on a debit the `from your A/c` leg is rejected anyway.
  /// Card alerts print the merchant *after* the timestamp:
  /// `… 12:34:47 IST WWW AMAZON Avl Limit: …` (Axis, and several others).
  static final RegExp _postTimestampMerchant = RegExp(
    r'\bIST\s+([A-Za-z][A-Za-z0-9 .&_*/-]{2,50}?)\s+(?:Avl|Available|Not you|$)',
    caseSensitive: false,
  );

  /// SBI's person-to-person phrasing: `-Transferred to Mr. NAME. Avl Balance …`.
  static final RegExp _p2pPayee = RegExp(
    r'\btransferred\s+to\s+((?:Mr|Mrs|Ms|Dr)\.?\s+)?([A-Za-z][A-Za-z .]{2,40}?)[.,]?\s+(?:Avl|Available|$)',
    caseSensitive: false,
  );

  /// SBI UPI: `debited by 60.00 on date 11Aug26 trf to M S SHRINGERI KI Refno …`.
  static final RegExp _sbiUpiPayee = RegExp(
    r'\bdebited by\b.{0,60}?\btrf\s+to\s+(.{2,40}?)\s+refno\b',
    caseSensitive: false,
  );

  static final RegExp _neftRemitter = RegExp(
    r'\bthrough\s+(?:neft|rtgs|imps)\b.{0,60}?\bby\s+([A-Za-z][A-Za-z0-9 &.\-]{2,60}?)\s*(?:,|\binfo\b|$)',
    caseSensitive: false,
  );

  static final RegExp _honorific = RegExp(
    r'^(?:mr|mrs|ms|miss|dr|smt)\.?\s',
    caseSensitive: false,
  );

  /// Payment apps and billers that forward money elsewhere.
  static final RegExp _paymentAppPayee = RegExp(
    r'^(?:phonepe|paytm|cred\b|mobikwik|amazon\s*pay|billdesk|google\s*pay|gpay|'
    r'freecharge|razorpay|payu|cashfree)',
    caseSensitive: false,
  );

  /// `trf to Bank Account XXX` — the user moving money to another own account.
  static final RegExp _ownAccountPayee = RegExp(
    r'^(?:bank\s+)?a(?:ccount|/c)\b|^self\b',
    caseSensitive: false,
  );

  /// SBI's outgoing NEFT/IMPS wording with no named counterparty.
  static final RegExp _debitByTransfer = RegExp(
    r'\bdebit by transfer\b|\btrf\s+to\b',
    caseSensitive: false,
  );

  /// Axis-style card alert: merchant sits between the IST timestamp and the limit.
  String? _cardPostTimestampMerchant(String body) {
    final match = _postTimestampMerchant.firstMatch(body);
    final candidate = match?.group(1)?.trim();
    if (candidate == null || candidate.length < 3) return null;
    final cleaned = candidate
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[*#|/.,;:-]+$'), '')
        .trim();
    if (cleaned.isEmpty) return null;
    // "WWW AMAZON" and "WWW FLIPKART" — the WWW prefix is noise.
    return cleaned.replaceFirst(RegExp(r'^WWW\s+', caseSensitive: false), '');
  }

  /// `-Transferred to Mr. NAME` — the payee is the best merchant we have.
  String? _p2pMerchant(String body) {
    final match = _p2pPayee.firstMatch(body);
    final name = match?.group(2)?.trim();
    if (name == null || name.length < 3) return null;
    return name.replaceAll(RegExp(r'\s+'), ' ');
  }

  static final List<RegExp> _merchantAnchors = [
    RegExp(r'\bfrom\s+([A-Za-z0-9][A-Za-z0-9 .&@_*/-]{2,60})', caseSensitive: false),
    RegExp(r'\bto\s+([A-Za-z0-9][A-Za-z0-9 .&@_*/-]{2,60})', caseSensitive: false),
    RegExp(r'\btowards\s+([A-Za-z0-9][A-Za-z0-9 .&@_*/-]{2,60})', caseSensitive: false),
    RegExp(r'\bat\s+([A-Za-z0-9][A-Za-z0-9 .&@_*/-]{2,60})', caseSensitive: false),
    RegExp(r'\bvia\s+([A-Za-z0-9][A-Za-z0-9 .&@_*/-]{2,60})', caseSensitive: false),
    RegExp(r'\bfor\s+([A-Za-z][A-Za-z0-9 .&@_*/-]{2,60})', caseSensitive: false),
    RegExp(r'\bof\s+([A-Za-z][A-Za-z0-9 .&@_*/-]{2,60})', caseSensitive: false),
    RegExp(r'\binfo\s*:?\s*([A-Za-z0-9][A-Za-z0-9 .&@_*/-]{2,60})', caseSensitive: false),
  ];

  static final RegExp _merchantCut = RegExp(
    r'(?:\.(?=\s|$))|[,;:()|]|\s[-|]\s|'
    r'\b(?:avl|available|avail|bal|balance|limit|lmt|outstanding|ref|reference|'
    r'upi|imps|neft|rtgs|txn|transaction|via|using|dated|on|at|for|to|from|and|'
    r'is|has|will|call|sms|info|bank|a/c|acct|acc|account|card|standing|instruction|'
    r'subscription|mandate|nach|emi|loan|bill|statement|due|credit|debit|interest|'
    r'cheque|cdm|bbps)\b|'
    r'\d{3,}',
    caseSensitive: false,
  );

  /// Banks named in the body, used only in an issuer context (`ICICI Bank
  /// Credit Card`), so `HDFC LIFE` (I04) and `@okhdfcbank` (F01) do not win.
  static final RegExp _issuerContext = RegExp(
    r'^\s*(?:small\s+finance\s+)?(?:bank\s+)?(?:credit\s+|debit\s+)?'
    r'(?:card|a/?c|acc(?:ount)?|bank)\b',
    caseSensitive: false,
  );
  static final RegExp _bankMention = RegExp(
    r'\b(hdfc|icici|sbi|axis|kotak|idfc|rbl|indusind|yes|au|federal|hsbc|'
    r'standard chartered|amex|american express|onecard|slice|canara|pnb|bob|'
    r'union|dbs|citibank|cred)\b',
    caseSensitive: false,
  );

  Txn? extract(SmsMessage message, SenderId sender, {CardBillNotice? Function()? onBillNotice}) {
    final body = message.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lower = body.toLowerCase();

    // A reminder, decline, collect request or mandate set-up never posts a row.
    if (SmsGuards.notMovedYet(lower)) return null;
    // A biller's confirmation with no bank evidence of its own becomes a
    // `receipt` row (counted only when no bank alert covers the payment).
    if (SmsGuards.paidReceipt(lower) &&
        sender.dltCategory != 'P' &&
        !_bankEvidence.hasMatch(lower)) {
      return _receiptTxn(message, sender, body);
    }
    // A merchant's own receipt header (Swiggy, Zepto, …) is never our account.
    if (registry.isMerchantReceiptSender(sender)) return null;
    // No order without a completed movement of money: an offer, eligibility or
    // limit figure is not a payment.
    if (!SmsGuards.moneyMoved(lower)) return null;
    // The fund house's unit confirmation duplicates the bank's SIP debit.
    if (SmsGuards.fundHouseConfirmation(lower)) return null;
    // A merchant-side receipt is the payer's copy, not the user's account (K14).
    if (SmsGuards.merchantReceipt(lower) &&
        amountFinder.balanceAfter(body) == null &&
        amountFinder.availableLimit(body) == null) {
      return null;
    }

    final best = amountFinder.best(body);
    if (best == null || best.score < 2) return null;
    final amountPaise = best.paise;

    final isCredit = _isCreditMessage(lower);
    final cash = _cash.hasMatch(lower);
    // "Transferred to Mr. X" and SBI's "debit by transfer" move money out of the
    // account to another account — they are transfers, not consumption.
    // SBI's UPI debit names the payee after "trf to": a shop far more often
    // than a person (gold set: 10 of 11), so it is spend unless it is the
    // user's own bank account.
    final sbiPayee = _sbiUpiPayee.firstMatch(body)?.group(1)?.trim();
    final sbiSelf = sbiPayee != null && _ownAccountPayee.hasMatch(sbiPayee);
    // "trf to PhonePe" / "trf to CRED": the app is a pipe, not the shop. A
    // ₹72,570 "to PhonePe" was a card bill; it must never land in spend
    // unasked, so it is a transfer the user is asked about.
    final viaPaymentApp =
        sbiPayee != null && _paymentAppPayee.hasMatch(sbiPayee);
    // "trf to Mr MUKESH KUMAR": an honorific is the one reliable person signal
    // SBI prints; everything else stays spend at the payee.
    final sbiPerson = sbiPayee != null && _honorific.hasMatch(sbiPayee);
    final bankTransfer = _p2pPayee.hasMatch(body) ||
        sbiSelf ||
        viaPaymentApp ||
        sbiPerson ||
        (sbiPayee == null && _debitByTransfer.hasMatch(lower));
    // Money-in taxonomy first: a card-bill credit, refund, TD redemption or
    // wallet load must never be treated as income (only salary/interest are).
    final moneyIn = isCredit
        ? _moneyInKind(lower, body, sender)
        : MoneyInKind.none;
    // A marketing credit (`Get Rs.100 wallet credit`) is not a movement at all.
    if (isCredit && moneyIn == MoneyInKind.none) return null;
    // Only the inflows that are *really* account movements become transfers:
    // a card bill being paid off, a TD being redeemed, a wallet being loaded.
    // Refunds/cashback/P2P stay on the credit side of the ledger but are
    // excluded from income by [MoneyInKind] (never by TxnKind).
    const transferInflows = {
      MoneyInKind.cardPayment,
      MoneyInKind.redemption,
      MoneyInKind.walletLoad,
    };
    final isTransferInflow = transferInflows.contains(moneyIn);
    final transferReason = isTransferInflow
        ? moneyIn.asTransferReason
        : sbiSelf
        ? TransferReason.selfTransfer
        : viaPaymentApp && RegExp(r'^cred\b', caseSensitive: false).hasMatch(sbiPayee)
        ? TransferReason.creditCardBill
        : sbiPerson
        ? TransferReason.personTransfer
        : (moneyIn.isInflow
              ? TransferReason.none
              : _transferReason(lower, isCredit: isCredit));
    final kind = cash
        ? TxnKind.cash
        : isTransferInflow
        ? TxnKind.transfer
        : moneyIn.isInflow
        ? TxnKind.income
        : (bankTransfer
              ? TxnKind.transfer
              : _kind(
                  isCredit: isCredit,
                  cash: cash,
                  transferReason: transferReason,
                ));
    final reference = _reference(body);
    final instrument = _instrument(body, lower, sender);
    final last4 = _extractLast4(body);
    // A card key may only come from a mask the message calls a **card**. A
    // savings-account tail (`A/c XX1234`) is not a plastic, and treating it as
    // one turned 11 savings accounts into phantom credit cards.
    final cardLast4 = _extractCardLast4(body, sender);
    final issuer = _issuer(lower, sender);
    final vpa = _counterpartyVpa(body);
    // NEFT/RTGS credit: "… through NEFT with UTR … by DELOITTE CONSULTING
    // INDIA P LTD, INFO: …" — the payer is the name after "by".
    final remitter = isCredit
        ? _neftRemitter.firstMatch(body)?.group(1)?.trim()
        : null;
    final merchant = remitter ??
        (sbiPayee != null && !sbiSelf ? sbiPayee : null) ??
        _merchant(body, cash: cash, keepCompanySuffix: isCredit) ??
        _cardPostTimestampMerchant(body) ??
        _p2pMerchant(body);
    final balance = amountFinder.balanceAfter(body);
    final availableLimit = amountFinder.availableLimit(body);

    final cardKey = (cardLast4 != null)
        ? '${issuer ?? (sender.entity ?? 'Card')}|$cardLast4'
        : null;

    final confidence = _confidence(
      sender: sender,
      amount: best,
      hasMerchant: merchant != null,
      hasInstrument: instrument != Instrument.unknown,
      hasReference: reference != null,
      balanceFound: balance != null,
    );

    final needsReview = viaPaymentApp ||
        ReviewQueue.shouldReview(
          kind: kind,
          confidence: confidence,
          merchant: merchant,
          vpa: vpa,
          amountScore: best.score,
        );

    return Txn(
      key: 'sms:${smsContentId(sender: message.sender, receivedAtMs: message.receivedAtMs, body: message.body)}',
      occurredAtMs: message.receivedAtMs,
      amountPaise: amountPaise,
      kind: kind,
      instrument: instrument,
      smsId: null,
      sender: sender.normalized,
      merchant: merchant,
      counterpartyVpa: vpa,
      transferReason: transferReason,
      moneyInKind: moneyIn,
      cardKey: cardKey,
      last4: last4,
      issuer: issuer,
      referenceId: reference,
      balanceAfterPaise: balance?.paise,
      availableLimitPaise: availableLimit?.paise,
      confidence: confidence,
      amountScore: best.score,
      // A merchant's own "refund processed" (no account or card named) is a
      // receipt: it folds into the bank's refund credit when that arrives.
      sourceType: moneyIn == MoneyInKind.refund && !_bankEvidence.hasMatch(lower)
          ? TxnSourceType.receipt
          : TxnSourceType.sms,
      needsReview: needsReview,
      rawBody: body,
    );
  }

  /// Words only the user's own bank prints: an account/card mask or a balance.
  static final RegExp _bankEvidence = RegExp(
    r'\ba/c\b|\bacct?\b|\baccount\s*(?:no|number|x)|\bcard\s*(?:no\.?|ending|xx|x\d|\*)|'
    r'\bavl\.?\s*(?:bal|lmt|limit)|\bavailable\s*(?:balance|limit)',
    caseSensitive: false,
  );

  Txn? _receiptTxn(SmsMessage message, SenderId sender, String body) {
    final amount =
        amountFinder.best(body)?.paise ?? SmsGuards.planAmountPaise(body);
    if (amount == null || amount <= 0) return null;
    return Txn(
      key: 'sms:${smsContentId(sender: message.sender, receivedAtMs: message.receivedAtMs, body: message.body)}',
      occurredAtMs: message.receivedAtMs,
      amountPaise: amount,
      kind: TxnKind.spend,
      instrument: Instrument.unknown,
      sender: sender.normalized,
      merchant: sender.entity ?? _titleCase(sender.normalized),
      referenceId: _reference(body),
      confidence: 0.6,
      sourceType: TxnSourceType.receipt,
      rawBody: body,
    );
  }

  bool _isCreditMessage(String lower) {
    // A reversal credits the account even when the original verb was "debited".
    if (SmsGuards.isReversal(lower)) return true;
    if (RegExp(r'\b(?:debited|spent|paid|withdrawn|withdrew|sent|charged|purchase[sd]?)\b')
        .hasMatch(lower)) {
      return false;
    }
    return RegExp(
      r'\b(?:credited|received|refund(?:ed)?|deposited|deposit|cashback|has credit for)\b',
    ).hasMatch(lower);
  }

  TransferReason _transferReason(String lower, {required bool isCredit}) {
    if (_creditCardBill.hasMatch(lower) || _cardPaymentCredit.hasMatch(lower)) {
      return TransferReason.creditCardBill;
    }
    if (_selfTransfer.hasMatch(lower)) return TransferReason.selfTransfer;
    if (_walletLoad.hasMatch(lower) || _walletCreditWord.hasMatch(lower)) {
      return TransferReason.walletLoad;
    }
    if (_loanEmi.hasMatch(lower)) return TransferReason.loanRepayment;
    if (_investment.hasMatch(lower)) return TransferReason.investment;
    if (!isCredit && _redemptionWord.hasMatch(lower)) {
      return TransferReason.selfTransfer;
    }
    // Outbound third-party payout (E02-E05) and numeric-VPA P2P (A09) are
    // movements of money between people, not consumption. `personTransfer` is
    // the honest label — "between your own accounts" was wrong for a payout to
    // a landlord or a friend.
    if (!isCredit) {
      if (_thirdPartyRail.hasMatch(lower) || _numericVpa.hasMatch(lower)) {
        return TransferReason.personTransfer;
      }
      if (_p2pPayee.hasMatch(lower)) return TransferReason.personTransfer;
      if (_upiWord.hasMatch(lower) &&
          _creditedWord.hasMatch(lower) &&
          !_vpaPattern.hasMatch(lower)) {
        return TransferReason.personTransfer;
      }
    }
    return TransferReason.none;
  }

  /// Classifies a credit-direction message into the money-in taxonomy.
  ///
  /// Order matters: a card-bill credit and a TD redemption must be recognised
  /// before the generic "credited" fallback, because both contain the word
  /// "credited" and neither is income.
  MoneyInKind _moneyInKind(String lower, String body, SenderId sender) {
    // Marketing copy that merely *mentions* a credit is not a movement.
    if (_walletOfferWording.hasMatch(lower) &&
        !RegExp(r'\bhas been credited\b|\bwas credited\b').hasMatch(lower)) {
      return MoneyInKind.none;
    }
    final cardWording =
        RegExp(r'\bcard\b').hasMatch(lower) ||
        sender.entityKind == 'card' ||
        RegExp(r'\bcredit\s*card\b').hasMatch(lower);
    if (_cardPaymentCredit.hasMatch(lower) && cardWording) {
      return MoneyInKind.cardPayment;
    }
    if (_redemptionWord.hasMatch(lower)) return MoneyInKind.redemption;
    if (_refundWord.hasMatch(lower)) return MoneyInKind.refund;
    if (_cashbackWord.hasMatch(lower)) return MoneyInKind.cashback;
    if (_salaryWord.hasMatch(lower)) return MoneyInKind.salary;
    if (_interestWord.hasMatch(lower)) return MoneyInKind.interest;
    if (_businessCreditWord.hasMatch(lower)) return MoneyInKind.other;
    if (_walletCreditWord.hasMatch(lower)) return MoneyInKind.walletLoad;
    if (_p2pCreditWord.hasMatch(lower)) return MoneyInKind.p2pReceive;
    // An anonymous "credited to your a/c" is the user's own money moving
    // between their accounts until something names a payer.
    if (RegExp(r'\b(?:a/?c|account|acct)\b').hasMatch(lower)) {
      return MoneyInKind.selfTransfer;
    }
    return MoneyInKind.selfTransfer;
  }

  TxnKind _kind({
    required bool isCredit,
    required bool cash,
    required TransferReason transferReason,
  }) {
    if (cash) return TxnKind.cash;
    if (transferReason != TransferReason.none) return TxnKind.transfer;
    if (isCredit) return TxnKind.income;
    return TxnKind.spend;
  }

  Instrument _instrument(String body, String lower, SenderId sender) {
    if (_cash.hasMatch(lower)) return Instrument.atm;
    // A UPI-Lite/wallet debit is a wallet movement even though the body also
    // prints the parent account mask (A05).
    if (RegExp(r'\bupi\s*lite\b|\bwallet\b|\bpaytm\b|\bphonepe\b|\bmobikwik\b').hasMatch(lower)) {
      return Instrument.wallet;
    }
    if (RegExp(r'\bcredit\s*card\b|\bcc\b|\bto\s+your\s+card\b').hasMatch(lower) ||
        sender.entityKind == 'card') {
      return Instrument.creditCard;
    }
    if (RegExp(r'\bdebit\s*card\b|\batm\s*card\b|\bpos\b|\becom\b|\bcard\s*used\b')
        .hasMatch(lower)) {
      return Instrument.debitCard;
    }
    // `Kotak Card x2210` names a card without the word "credit" (C04/G04); an
    // issuer's "credited to your card ending 6859" does the same. This check
    // comes after the debit-card branch so "Debit Card ending 5522" stays a
    // debit card.
    if (RegExp(r'\bcard\s*(?:no\.?|number|ending)\b').hasMatch(lower) ||
        RegExp(r'\bcard\b[\s:*#-]*[x*]{1,4}\d{2,5}').hasMatch(lower) ||
        amountFinder.availableLimit(body) != null) {
      return Instrument.creditCard;
    }
    // Money coming back lands in the account that raised the debit (G02/G03/G05),
    // but a reversal never routes through a UPI store.
    final reversal = SmsGuards.isReversal(lower);
    if (_vpaPattern.hasMatch(body)) return Instrument.upi;
    if (!reversal && RegExp(r'\bupi\b').hasMatch(lower)) return Instrument.upi;
    if (RegExp(r'\ba/?c\b|\bacc\b|\baccount\b|\bneft\b|\bimps\b|\brtgs\b').hasMatch(lower)) {
      return Instrument.bankAccount;
    }
    // The destination decides next: a wallet sender credits the wallet (F07),
    // a card sender the card.
    if (sender.entityKind == 'card') return Instrument.creditCard;
    if (sender.entityKind == 'wallet') return Instrument.wallet;
    if (reversal) return Instrument.bankAccount;
    if (sender.entityKind == 'bank') return Instrument.bankAccount;
    if (RegExp(r'\bemi\b').hasMatch(lower)) return Instrument.emi;
    return Instrument.unknown;
  }

  /// The tail of the account/card mask. Segments are read per context, and
  /// within a context the *last* segment wins, because PANs print as
  /// `7121-81XX-XXXX-7007`. Amex prints five digits; `last4` is the final four.
  String? _extractLast4(String body) {
    for (final context in _maskContext.allMatches(body)) {
      final tail = body.substring(
        context.end,
        (context.end + 32).clamp(0, body.length),
      );
      final segments = _maskSegment.allMatches(tail).toList();
      if (segments.isNotEmpty) {
        final raw = segments.last.group(0)!.replaceAll(RegExp(r'[^0-9]'), '');
        if (raw.length >= 3) {
          return raw.length > 4 ? raw.substring(raw.length - 4) : raw;
        }
      }
      // `Credit Card 5444` prints the tail with no mask glyph at all (I01).
      final bare = _bareMaskDigits.firstMatch(tail);
      if (bare != null) return bare.group(1);
    }
    return null;
  }

  /// A **card** tail only: the mask must sit in card wording (`card`,
  /// `credit card`, `CC`, `Amex`, `corporate card`) or the sender must be a
  /// card issuer. An `A/c XX1234` / `account` mask is a deposit account and
  /// must never mint a credit card (the 21-cards-for-3-plastics bug).
  String? _extractCardLast4(String body, SenderId sender) {
    final cardSender = sender.entityKind == 'card';
    final contexts = <Match>[
      ..._cardContext.allMatches(body),
    ];
    if (contexts.isEmpty && !cardSender) return null;
    for (final context in contexts) {
      final tail = body.substring(
        context.end,
        (context.end + 40).clamp(0, body.length),
      );
      final segments = _maskSegment.allMatches(tail).toList();
      if (segments.isNotEmpty) {
        final raw = segments.first.group(0)!.replaceAll(RegExp(r'[^0-9]'), '');
        if (raw.length >= 3) {
          return raw.length > 4 ? raw.substring(raw.length - 4) : raw;
        }
      }
      // `Credit Card 5444` / `Card 6859` prints the tail with no mask glyph.
      final bare = _bareMaskDigits.firstMatch(tail);
      if (bare != null) return bare.group(1);
    }
    // A card-issuer header with a single mask elsewhere in the body is still a
    // card: `AMEX Corporate Card **********91008`. But a card issuer also sends
    // *account* alerts — `A/c XX1234 debited` from an SBI Card header is a
    // deposit account, never a new plastic.
    if (cardSender && !_accountContext.hasMatch(body)) {
      return _extractLast4(body);
    }
    return null;
  }

  static final RegExp _accountContext = RegExp(
    r"\b(?:a/?c|acct|acc(?:ount)?)(?:\s*no\.?)?\b",
    caseSensitive: false,
  );

  /// Card context for a mask: the word "card" (or `CC`/`Amex`) followed by an
  /// optional `no.`/`number`/`ending`, within a short distance of the mask.
  ///
  /// The qualifier sits **outside** the alternatives on purpose. With
  /// `credit\s*card` as its own branch, a body reading `credit card ending with
  /// 4821` matched only `credit card` (leftmost-first) and the digits 40
  /// characters later never bound — the issuer leg of a card-bill payment had
  /// no `cardKey`, which is exactly the key the bill-payment pairing needs to
  /// keep the right row.
  static final RegExp _cardContext = RegExp(
    r'\b(?:credit\s*card|corporate\s*card|debit\s*card|prepaid\s*card|'
    r'card|cc|amex|american\s*express)'
    r'(?:\s*(?:no\.?|number|ending(?:\s*(?:with|in|no\.?))?))?\b',
    caseSensitive: false,
  );

  String? _issuer(String lower, SenderId sender) {
    // 1. A wallet brand named in the body beats the sender header: a Paytm
    //    header can report an Amazon Pay refund (F07).
    if (sender.entityKind == 'wallet') {
      final brand = RegExp(r'\b(amazon\s*pay|paytm|phonepe|google\s*pay|mobikwik)\b')
          .firstMatch(lower);
      if (brand != null) {
        final name = brand.group(1)!;
        return switch (name) {
          'amazon pay' => 'Amazon Pay',
          'paytm' => 'Paytm',
          'phonepe' => 'PhonePe',
          'google pay' => 'Google Pay',
          _ => 'MobiKwik',
        };
      }
    }
    // 2. A bank named next to a card/account: `ICICI Bank credit card` (H05) is
    //    the issuer even when a payment channel (CRED) sent the SMS. The context
    //    check keeps `HDFC LIFE` (I04) and `@okhdfcbank` (F01) out.
    for (final match in _bankMention.allMatches(lower)) {
      final rest = lower.substring(match.end, (match.end + 26).clamp(0, lower.length));
      if (!_issuerContext.hasMatch(rest)) continue;
      final name = match.group(1)!;
      if (name == 'sbi' && RegExp(r'^\s*credit\s+card\b').hasMatch(rest)) {
        return 'SBI Card';
      }
      return _issuerLabel(name);
    }
    // 3. Fall back to the resolved DLT header.
    final entity = sender.entity;
    if (entity == 'CRED') return null; // a payment channel, not an issuer.
    return entity;
  }

  String _issuerLabel(String name) {
    const labels = {
      'hdfc': 'HDFC Bank',
      'icici': 'ICICI Bank',
      'sbi': 'State Bank of India',
      'axis': 'Axis Bank',
      'kotak': 'Kotak Mahindra Bank',
      'idfc': 'IDFC FIRST Bank',
      'rbl': 'RBL Bank',
      'indusind': 'IndusInd Bank',
      'yes': 'Yes Bank',
      'au': 'AU Small Finance Bank',
      'federal': 'Federal Bank',
      'hsbc': 'HSBC India',
      'standard chartered': 'Standard Chartered',
      'amex': 'American Express',
      'american express': 'American Express',
      'onecard': 'OneCard',
      'slice': 'Slice',
      'canara': 'Canara Bank',
      'pnb': 'Punjab National Bank',
      'bob': 'Bank of Baroda',
      'union': 'Union Bank of India',
      'dbs': 'DBS Bank',
      'citibank': 'Citibank',
      'cred': 'CRED',
    };
    return labels[name] ?? _titleCase(name);
  }

  String? _counterpartyVpa(String body) {
    final all = _vpaPattern.allMatches(body).toList();
    if (all.isEmpty) return null;
    return _payloadMarker.hasMatch(body) ? all.last.group(0) : all.first.group(0);
  }

  String? _merchant(
    String body, {
    required bool cash,
    bool keepCompanySuffix = false,
  }) {
    // A bill-pay tag is the counterparty of an ICICI bill payment (H01-H04).
    final bill = _billRef.firstMatch(body);
    if (bill != null) return bill.group(0)!.toUpperCase();

    // A UPI/P2A payload names the counterparty; the VPA printed earlier belongs
    // to the account holder (F01, A06).
    final hasPayload = _payloadMarker.hasMatch(body);
    final vpa = _counterpartyVpa(body);
    if (hasPayload && vpa != null) return vpa;

    if (cash) {
      final atm = _atmMerchant(body);
      if (atm != null) return atm;
    }

    for (final pattern in _merchantAnchors) {
      for (final match in pattern.allMatches(body)) {
        final candidate = _cleanMerchant(
          match.group(1)!,
          keepCompanySuffix: keepCompanySuffix,
        );
        if (_isUsableMerchant(candidate)) return candidate;
      }
    }

    if (vpa != null) return _vpaMerchant(vpa);
    return null;
  }

  /// ATM notices print `<label> <atm-id> <branch>-<city>`; only the label and
  /// the locality are merchant-worthy (D01 -> `SBG ATM MANCHERIAL`).
  String? _atmMerchant(String body) {
    final at = RegExp(r'\bat\s+([A-Za-z0-9][^,.;(]{2,70})', caseSensitive: false)
        .firstMatch(body);
    if (at == null) return null;
    final segment = at.group(1)!;
    final stop = RegExp(r'\b(?:using|from|on)\b', caseSensitive: false)
        .firstMatch(segment);
    final text = stop == null ? segment : segment.substring(0, stop.start);
    final parts = <String>[];
    for (final token in text.split(RegExp(r'[\s,/]+'))) {
      for (final piece in token.split('-')) {
        if (!RegExp(r'^[A-Za-z]{2,}$').hasMatch(piece)) continue;
        final upper = piece.toUpperCase();
        if (const {'SBH', 'ACC', 'LTD'}.contains(upper)) continue;
        if (parts.isNotEmpty && parts.last == upper) continue;
        parts.add(upper);
      }
    }
    return parts.isEmpty ? null : parts.join(' ');
  }

  String _cleanMerchant(String value, {bool keepCompanySuffix = false}) {
    var cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    // `IND*Amazon.in`, `EBA*MF-AXIS` — the aggregator tag is not the brand.
    cleaned = cleaned.replaceFirst(
      RegExp(r'^(?:ind|inf|payu|pyu|eba|mps|raz|bharatqr)\s*[*:]\s*', caseSensitive: false),
      '',
    );
    // `PAYU ZOMATO` uses a space instead of the `*` separator (C05).
    cleaned = cleaned.replaceFirst(RegExp(r'^payu\s+', caseSensitive: false), '');
    cleaned = cleaned.replaceFirst(
      RegExp(r'^(?:vpa|paid to)\s+', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceFirst(
      RegExp(r'^(?:your|the)\s+', caseSensitive: false),
      '',
    );
    // Stop at the first sentence/spatial/balance/rail token, or a long digit run
    // (a reference number is not a merchant).
    // `SWIGGY PVT LTD FOOD2` — the company suffix and a trailing digit are noise.
    // A *credit* payer keeps its full legal name: `ACME TECHNOLOGIES PVT LTD`
    // is the entity that paid, and truncating it loses the identity.
    if (!keepCompanySuffix) {
      cleaned = cleaned.replaceFirst(
        RegExp(r'\s+(?:pvt|private)\.?\s+ltd\.?.*$', caseSensitive: false),
        '',
      );
    }
    cleaned = cleaned.replaceFirst(RegExp(r'\d+$'), '');
    final cut = _merchantCut.firstMatch(cleaned);
    if (cut != null) cleaned = cleaned.substring(0, cut.start);
    cleaned = cleaned.replaceAll(RegExp(r'[\s*#|/.,;:_-]+$'), '').trim();
    return cleaned;
  }

  bool _isUsableMerchant(String candidate) {
    final lower = candidate.toLowerCase().trim();
    if (lower.length < 3) return false;
    // A brand needs a real word in it; `Rs.5` is a truncated amount, not a shop.
    if (!RegExp(r'[A-Za-z]{3,}').hasMatch(candidate)) return false;
    if (RegExp(r'^(?:rs|inr|₹)\.?\s').hasMatch(lower)) return false;
    if (RegExp(r'\d$').hasMatch(lower)) return false;
    if (RegExp(r'^\d').hasMatch(lower)) return false;
    // `20-Jul-23` and `Jan-Mar` are dates, not shops.
    if (lower.split(RegExp(r'[-\s]+')).every(_monthToken.contains)) return false;
    if (_merchantStop.contains(lower)) return false;
    if (_merchantStop.contains(lower.split(' ').first)) return false;
    if (_merchantNoise.contains(lower)) return false;
    if (RegExp(r'\d{3,}').hasMatch(lower)) return false;
    if (RegExp(r'\b(?:account|balance|ref|upi|txn|transaction|card|otp|a/c|bank)\b')
        .hasMatch(lower)) {
      return false;
    }
    // A bare bank name is the user's own institution, never the counterparty.
    final bankish = lower
        .replaceAll(RegExp(r'\b(?:bank|finance|small)\b'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (_bankWords.contains(bankish)) return false;
    return true;
  }

  String _vpaMerchant(String vpa) {
    final local = vpa.split('@').first;
    if (!RegExp(r'^[A-Za-z]{4,}$').hasMatch(local)) return vpa;
    return _titleCase(local);
  }

  String _titleCase(String value) {
    return value
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  String? _reference(String body) {
    final bill = _billRef.firstMatch(body);
    if (bill != null) {
      final token = bill.group(0)!.toUpperCase();
      final tail = token.substring(3); // starts at the first '*'
      // `BIL*000910062` is a channel tag plus a plain number (H01/H04);
      // `BIL*ONL*00059` is a coded reference and is kept whole (H02/H03).
      if (RegExp(r'^\*\d+$').hasMatch(tail)) return tail.substring(1);
      return token;
    }
    // HDFC credit: "from VPA 74…@axl (UPI 649507747508)" — the 12-digit RRN
    // the paying bank also prints, which is what pairs the two legs.
    final rrn = _bracketRrn.firstMatch(body);
    if (rrn != null) return rrn.group(1);
    for (final match in _upiPayloadRef.allMatches(body)) {
      if (match.end < body.length && body[match.end] == '@') continue; // a VPA, not a ref
      return match.group(1)!.toUpperCase();
    }
    for (final match in _orderRef.allMatches(body)) {
      final group = match.group(1) ?? match.group(2);
      if (group != null) return group.toUpperCase();
    }
    for (final match in _refKeyword.allMatches(body)) {
      final group = match.group(1);
      if (group == null || group.contains('@')) continue;
      return group.toUpperCase();
    }
    return null;
  }

  double _confidence({
    required SenderId sender,
    required AmountCandidate amount,
    required bool hasMerchant,
    required bool hasInstrument,
    required bool hasReference,
    required bool balanceFound,
  }) {
    var score = 0.35;
    if (sender.trust == SenderTrust.known) score += 0.25;
    if (sender.trust == SenderTrust.plausible) score += 0.1;
    if (amount.score >= 6) score += 0.15;
    if (hasInstrument) score += 0.1;
    if (hasMerchant) score += 0.1;
    if (hasReference) score += 0.05;
    if (balanceFound) score += 0.05;
    return score.clamp(0.05, 0.99);
  }

  /// Extracts a card bill notice (total due / min due / statement date / due
  /// date) from **any** message, including statement SMS that the classifier
  /// calls informational. A bill was never persisted because this used to run
  /// only for `isTransaction` messages.
  CardBillNotice? billNotice(SmsMessage message, SenderId sender) {
    final body = message.body;
    final lower = body.toLowerCase();
    if (!RegExp(r'\b(due|outstanding|statement|bill)\b').hasMatch(lower)) {
      return null;
    }
    // Only a *card* statement. `SIP instalment … is due`, `KYC update due` and
    // utility bills must not invent credit-card debt.
    if (!_isCardBillMessage(body, lower, sender)) return null;
    final total = _amountAfterLabel(body, const [
      'total amount due', 'total amt due', 'total due', 'total outstanding',
      'total payment', 'total amt', 'total amount', 'bill amount',
      'amount due', 'amt due', 'outstanding amount', 'payment due',
    ]);
    if (total == null) return null;
    final minimum = _amountAfterLabel(body, const [
      'minimum amount due', 'minimum payment due', 'minimum due', 'min amt due',
      'min due', 'minimum amt',
    ]);
    final dueDate = _dateAfterLabel(body, const [
      'due date', 'due on', 'due by', 'pay by', 'pay before',
    ]);
    final statementDate = _statementDate(body, message.receivedAtMs);
    final cardLast4 = _extractCardLast4(body, sender);
    final issuer = _issuer(lower, sender);
    return CardBillNotice(
      // An empty tail means "the card was not printed"; the builder attributes
      // such a bill only when the issuer has exactly one card.
      cardKey: '${issuer ?? (sender.entity ?? 'Card')}|${cardLast4 ?? ''}',
      totalDuePaise: total,
      minimumDuePaise: minimum,
      dueDateMs: dueDate?.millisecondsSinceEpoch,
      statementDateMs: statementDate,
      receivedAtMs: message.receivedAtMs,
    );
  }

  static final RegExp _cardBillWording = RegExp(
    r'\b(?:credit\s*card|card\s*(?:no\.?|number|ending)|corporate\s*card|'
    r'amex|statement\s+(?:for|of)\b.{0,30}\bcard|card\s+statement)\b',
    caseSensitive: false,
  );

  bool _isCardBillMessage(String body, String lower, SenderId sender) {
    if (_cardBillWording.hasMatch(lower)) return true;
    if (sender.entityKind == 'card') return true;
    // `AMEX Corporate Card **********91008 has been generated.`
    if (RegExp(r'\bcard\b[\s:*#-]*[x*]{2,}\d{2,5}').hasMatch(lower)) return true;
    return false;
  }

  /// Statement date: an explicit label, a `<date> statement` phrase, or — for
  /// the "your statement … has been generated" template — the day the alert
  /// arrived (banks send it on the statement date).
  int? _statementDate(String body, int receivedAtMs) {
    final explicit = _dateAfterLabel(body, const [
      'statement date', 'statement on', 'statement for',
    ]);
    if (explicit != null) return explicit.millisecondsSinceEpoch;
    final before = RegExp(
      r'(\d{1,2}[-/\s](?:[A-Za-z]{3,9}|\d{1,2})[-/\s]\d{2,4})\s+statement',
      caseSensitive: false,
    ).firstMatch(body);
    if (before != null) {
      final parts = RegExp(r'(\d{1,2})[-/\s]([A-Za-z]{3,9}|\d{1,2})[-/\s](\d{2,4})')
          .firstMatch(before.group(1)!);
      if (parts != null) {
        final parsed = _parseDate(parts.group(1)!, parts.group(2)!, parts.group(3)!);
        if (parsed != null) return parsed.millisecondsSinceEpoch;
      }
    }
    if (RegExp(r'\bstatement\b.{0,60}\b(?:generated|is ready|ready)\b',
        caseSensitive: false).hasMatch(body)) {
      return receivedAtMs;
    }
    return null;
  }

  int? _amountAfterLabel(String body, List<String> labels) {
    final lower = body.toLowerCase();
    for (final label in labels) {
      final idx = lower.indexOf(label);
      if (idx < 0) continue;
      for (final candidate in amountFinder.findAll(body)) {
        if (candidate.start >= idx && candidate.start <= idx + label.length + 45) {
          return candidate.paise;
        }
      }
    }
    return null;
  }

  DateTime? _dateAfterLabel(String body, List<String> labels) {
    final lower = body.toLowerCase();
    for (final label in labels) {
      final idx = lower.indexOf(label);
      if (idx < 0) continue;
      final window = body.substring(idx, (idx + 60).clamp(0, body.length));
      final match = RegExp(r'(\d{1,2})[-/\s]([A-Za-z]{3,9}|\d{1,2})[-/\s](\d{2,4})')
          .firstMatch(window);
      if (match == null) continue;
      final parsed = _parseDate(match.group(1)!, match.group(2)!, match.group(3)!);
      if (parsed != null) return parsed;
    }
    return null;
  }

  DateTime? _parseDate(String day, String month, String year) {
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final d = int.tryParse(day);
    final m = int.tryParse(month) ?? months[month.toLowerCase()];
    var y = int.tryParse(year);
    if (d == null || m == null || y == null) return null;
    if (y < 100) y += 2000;
    if (d < 1 || d > 31 || m < 1 || m > 12) return null;
    return DateTime(y, m, d);
  }
}

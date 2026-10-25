import '../../domain/enums.dart';
import '../../domain/sms_message.dart';
import 'amount_finder.dart';
import 'sender_registry.dart';
import 'sms_guards.dart';

/// Decides what a message *is* before any amount is trusted.
///
/// Every decision is a sum of weighted signals, so the UI can explain itself
/// ("Why did you flag this?") instead of showing a black-box label.
class SmsClassifier {
  SmsClassifier({
    this.registry = const SenderRegistry(),
    this.amountFinder = const AmountFinder(),
  });

  final SenderRegistry registry;
  final AmountFinder amountFinder;

  static final RegExp _otpWord = RegExp(
    r'\b(otp|o\.t\.p|one[- ]time password|verification code|verification pin|'
    r'passcode|do not share|never share|valid for \d+)\b',
    caseSensitive: false,
  );
  static final RegExp _debitVerb = RegExp(
    r'\b(debited|debit(?:ed)? (?:by|with|for)|spent|spent on|paid|payment of|'
    r'purchase[d]?|charged|withdrawn|withdrew|sent|transferred|billed|'
    r'txn of|transaction of|used for|deducted)\b|'
    r'\btop[\s-]*up\b.{0,40}\bsuccessful\b|'
    // SBI debit-card POS: "for Rs.331.45 by SBI Debit Card X7361 done at …".
    r'\bdebit card [x*]*\d{3,4} done at\b',
    caseSensitive: false,
  );
  static final RegExp _creditVerb = RegExp(
    r'\b(credited|credit received|received from|deposited|refund(?:ed)?|'
    r'reversal|reversed|chargeback|cashback credited|money received|has credit for)\b',
    caseSensitive: false,
  );

  /// Informational intents. Each one names a non-transaction message so the
  /// "unknown" bucket shrinks without loosening the transaction rule (SC-01).
  static final List<(String, RegExp, int)> _infoIntents = [
    (
      'balance_notice',
      RegExp(
        r'\bbalance (?:as on|is|:)|avl(?:ailable)?\.?\s*(?:bal|balance)|'
        r'minimum balance\b|\bbalance is (?:below|now)\b',
        caseSensitive: false,
      ),
      5,
    ),
    (
      'statement_wording',
      RegExp(r'\b(?:statement|account summary|passbook)\b', caseSensitive: false),
      5,
    ),
    (
      'due_summary',
      RegExp(
        r'\b(?:total|minimum|amount) due\b|\bdue date\b',
        caseSensitive: false,
      ),
      5,
    ),
    (
      'dispatch_notice',
      RegExp(r'\b(?:dispatched|delivered)\b', caseSensitive: false),
      4,
    ),
    (
      'maturity_notice',
      RegExp(r'\b(?:matur(?:es|ity)|fixed deposit)\b', caseSensitive: false),
      4,
    ),
    (
      'service_request',
      RegExp(
        r'\b(?:request|update)\b.{0,40}\b(?:registered|received|completed)\b',
        caseSensitive: false,
      ),
      4,
    ),
    (
      'branch_notice',
      RegExp(
        r'\b(?:branch|office)\b.{0,30}\b(?:remain closed|closed|holiday)\b|'
        r'\bholiday\b',
        caseSensitive: false,
      ),
      4,
    ),
    (
      'login_alert',
      RegExp(
        r'\b(?:login|log in)\b.{0,70}\b(?:new device|not you|notice)\b|'
        r'\b(?:new device)\b',
        caseSensitive: false,
      ),
      5,
    ),
    (
      'mandate_setup',
      RegExp(
        r'\b(?:e-?mandate|mandate|autopay|auto\s*pay|standing instruction)\b.{0,60}'
        r'\b(?:created|registered|activated|set up)\b',
        caseSensitive: false,
      ),
      5,
    ),
    (
      'cheque_cleared',
      RegExp(
        r'\bcheque\b.{0,60}\b(?:cleared|realised|realized)\b',
        caseSensitive: false,
      ),
      4,
    ),
    (
      'kyc_notice',
      RegExp(
        r'\b(?:complete|update|re-?kyc)\b.{0,40}\bkyc\b|\bkyc\b.{0,40}'
        r'\b(?:branch|aadhaar|pan)\b',
        caseSensitive: false,
      ),
      4,
    ),
    (
      'limit_notice',
      RegExp(
        r'\blimit\b.{0,30}\b(?:enhanced|increased|upgraded|available limit)\b|'
        r'\bavailable limit\b',
        caseSensitive: false,
      ),
      4,
    ),
  ];

  static final RegExp _promoWord = RegExp(
    r'\b(offer|offers|congratulations|you (?:are|have) (?:selected|won)|'
    r'pre-?approved|pre-?qualified|apply now|limited period|limited time|'
    r'lowest interest|instant loan|loan up to|personal loan|insurance|'
    r'cashback offer|get up to|win up to|free gift|voucher|discount|'
    r'upgrade to|elite|rewards? points?|redeem|unsubscribe|to stop|'
    r't&c apply|terms (?:and|&) conditions|click here|click the link|'
    r'register now|book now|hurry|hiring|work from home|no experience|'
    r'earn\s+(?:rs\.?|inr|₹)?\s*\d+.{0,12}(?:day|month|week)|'
    r'join now|multibagger|bonus)\b',
    caseSensitive: false,
  );
  /// KYC / account-pressure wording. Deliberately narrow: a bare "expires" or
  /// "complete your" is ordinary English (a Jio plan expires, a cart needs
  /// completing) and used to flag 151 messages of which none was fraud.
  static final RegExp _kycLure = RegExp(
    r'\b(?:kyc|k\.y\.c|re-?kyc)\b|'
    r'\b(?:pan\s*card|aadhaar|aadhar|pan)\b.{0,40}'
    r'\b(?:link(?:ed)?|update|verify|block(?:ed)?|freeze|frozen|deactivat\w*|'
    r'expir\w*|not\s+linked)\b|'
    r'\b(?:update|link|verify|complete|re-?verify)\b.{0,24}'
    r'\b(?:kyc|pan|aadhaar|aadhar)\b|'
    r'\b(?:account|card|net\s*banking|sim|wallet|a/?c)\b.{0,40}'
    r'\b(?:block(?:ed)?|suspend(?:ed)?|deactivat\w*|frozen|locked|freeze|'
    r'verify\s+your|restricted)\b|'
    r'\b(?:verify|update)\s+your\b.{0,24}\b(?:account|identity|details|card)\b',
    caseSensitive: false,
  );

  /// A real *request to the user* to hand over a credential: `share/send/tell
  /// us your OTP`, `confirm your CVV`. A bank OTP message that says "enter the
  /// OTP" is telling the user where to type the code it just sent, not asking
  /// for it, so [enter] is handled separately in [_credentialEnterAsk].
  static final RegExp _credentialShareAsk = RegExp(
    r'\b(?:share|send|tell(?:\s+us)?|provide|reply\s+with|forward|confirm|'
    r're-?send)\b.{0,40}\b(?:your|the)\b.{0,16}'
    r'\b(?:otp|o\.t\.p|pin|cvv|password|passcode|card\s*number|'
    r'aadhaar\s*number|net\s*banking\s*(?:id|password))\b|'
    r'\b(?:share|send|tell(?:\s+us)?)\b.{0,24}\botp\b',
    caseSensitive: false,
  );

  /// "Enter **your** OTP" is an ask; "enter the OTP" inside a message that
  /// already delivered a code is not. The OTP-shape gate lives in
  /// [_isCredentialAsk].
  static final RegExp _credentialEnterAsk = RegExp(
    r'\b(?:enter|submit|type|input)\s+(?:your\s+|the\s+)?'
    r'(?:otp|o\.t\.p|pin|cvv|password|passcode|upi\s*pin)\b',
    caseSensitive: false,
  );

  /// A credible threat of loss — the second half of every KYC/utility scam.
  static final RegExp _threatWording = RegExp(
    r'\b(?:will be|has been|is being)\s+(?:blocked|suspended|deactivated|'
    r'debited|charged|disconnected|frozen|locked|closed)\b|'
    r'\bwithin\s+\d+\s*(?:hrs?|hours?|minutes?)\b|'
    r'\bavoid\s+(?:late|penalty|disconnection|charges?|service\s+disconnection)\b|'
    r'\b(?:frozen|suspended|deactivated|blocked)\b',
    caseSensitive: false,
  );

  /// `visit` and a bare `call` are only a call to action next to a link, so they
  /// are handled separately (info-05, info-08, fraud-07).
  static final RegExp _phishCta = RegExp(
    r'\b(?:click|tap|login|log in|open the link|share (?:the )?otp|share your otp|'
    r'scan (?:this )?qr|pay (?:now|immediately)|confirm your details|bank details)\b',
    caseSensitive: false,
  );
  static final RegExp _url = RegExp(
    r'(?:https?://|www\.)[^\s]+|'
    r'\b[a-z0-9-]+\.(?:com|in|net|org|xyz|top|club|live|icu|info|co|biz|me|site|online|shop|vip|link)(?![a-z0-9-])(?:/[^\s]*)?',
    caseSensitive: false,
  );
  static final RegExp _otpLikeNumber = RegExp(
    r'\b(?:is|:|-)\s*(\d{4,8})\b',
    caseSensitive: false,
  );

  /// A UPI *request* is money leaving someone else's account, not ours. Indian
  /// scam messages lean on this, and naive parsers book it as a debit.
  static final RegExp _requestMoney = RegExp(
    r'\b(?:has\s+requested|requested\s+money|requests?\s+you|collect\s+request|'
    r'payment\s+request|money\s+request|approve\s+(?:the\s+)?request|'
    r'requesting\s+(?:₹|rs\.?|inr))\b',
    caseSensitive: false,
  );

  /// Any ask for credentials overrides sender trust — banks never do this.
  /// Split in two so a genuine OTP message ("enter the OTP to proceed") cannot
  /// be read as a request to hand the code over.
  bool _isCredentialAsk(String lower) {
    final negated = SmsGuards.shareIsNegated(lower);
    if (negated) return false;
    // A delivery handover code ("share OTP 3823 with the delivery agent") is a
    // receipt token, not a bank credential: parcel/pickup contexts are exempt.
    final handover = RegExp(
      r'\b(?:deliver(?:y|ed)?|rider|delivery\s+agent|technician|collect|pickup|'
      r'pick\s*up|parcel|package|courier|order)\b',
    ).hasMatch(lower) &&
        !RegExp(r'\b(?:bank|credit\s*card|debit\s*card|account|kyc|cvv)\b')
            .hasMatch(lower);
    if (_credentialShareAsk.hasMatch(lower) && !handover) return true;
    // A message that already delivered a 4–8 digit code is a genuine OTP; the
    // "enter the OTP" sentence in it points at the bank's own screen.
    final deliveredCode =
        _otpWord.hasMatch(lower) && RegExp(r'\b\d{4,8}\b').hasMatch(lower);
    if (deliveredCode || handover) return false;
    return _credentialEnterAsk.hasMatch(lower);
  }

  /// Wallet/UPI-Lite top-ups: money moves, but nothing is spent.
  static final RegExp _addMoneyVerb = RegExp(
    r'\b(?:added\s+to|top\s*up|topup|loaded|recharged|deposited)\b',
    caseSensitive: false,
  );

  /// Known social-engineering templates that are decisive on their own: a
  /// parcel fee, a QR "to receive", remote-access software, an upfront
  /// registration fee, a threat of an automatic debit (SC-04).
  static final RegExp _scamTemplate = RegExp(
    r'\b(?:parcel|courier|customs|consignment|held\s+at|detained)\b'
    r'|\bpay\s+(?:₹|rs\.?|inr)?\s*\d+.{0,40}\b(?:registration|processing|security|approval|upi|link|qr)\b'
    r'|\bscan\s+(?:this\s+)?qr\b'
    r'|\bupi\s*(?:id|pin)\b.{0,30}\b(?:send|share|pay)\b'
    r'|\b(?:anydesk|teamviewer)\b|\bshare\s+the\s+(?:code|screen)\b'
    r'|\baccount will be (?:debited|charged)\b'
    r'|\bpart[- ]time\b.{0,40}\b(?:earn|pay|registration)\b'
    r'|\bregistration (?:fee|amount|charge)\b',
    caseSensitive: false,
  );

  /// Secondary fraud vocabulary: strong evidence, but not enough to override a
  /// known-good bank header on its own (G06 is a real cashback credit).
  static final RegExp _fraudTemplate = RegExp(
    r'\b(?:won|winner|lucky draw|lottery|prize|'
    r'refund is pending|you have received a refund|scan this qr to receive|'
    r'electricity bill.*disconnect|electricity.*will be disconnected|'
    r'your sim (?:will|is)|account will be (?:blocked|suspended))\b',
    caseSensitive: false,
  );

  /// "You won INR 6 cashback" is a real, if tiny, credit dressed as marketing
  /// (G06). The same words with no destination stay promo (G07).
  static final RegExp _cashbackCredit = RegExp(
    r'\b(?:won|earned|received)\b.{0,30}\b(?:cashback|reward)\b|'
    r'\bcashback\b.{0,30}\b(?:credited|deposited)\b',
    caseSensitive: false,
  );

  /// Genuine advisories that explicitly disclaim the phishing playbook (info-05).
  static final RegExp _safeContext = RegExp(
    r'\b(?:no update is done|not (?:over|through|on) (?:phone|link|call)|'
    r'home branch|visit your (?:home )?branch|never share|do not share)\b',
    caseSensitive: false,
  );

  SmsAssessment assess(SmsMessage message) {
    final sender = registry.resolve(message.sender);
    final body = _normalize(message.body);
    // Bank opt-out footers ("SMS BLOCK 696 to …") are not a block lure.
    final lower = SmsGuards.stripDltFooter(body.toLowerCase());
    final amount = amountFinder.best(body);
    final hasAmount = amount != null && amount.score >= 3;

    final signals = <SmsSignal>[];
    var tx = 0;
    var info = 0;
    var promo = 0;
    var phish = 0;

    switch (sender.trust) {
      case SenderTrust.known:
        tx += 3;
        signals.add(const SmsSignal('known_sender', 3, detail: 'Sender id matches a known bank/wallet header'));
      case SenderTrust.plausible:
        tx += 1;
        signals.add(const SmsSignal('plausible_sender', 1));
      case SenderTrust.suspicious:
        phish += 3;
        signals.add(const SmsSignal('suspicious_sender', -3, detail: 'Numeric or unknown sender id'));
    }

    if (sender.dltCategory == 'P') {
      promo += 3;
      signals.add(const SmsSignal('dlt_promotional', -3, detail: 'DLT header is marked promotional (-P)'));
    }
    if (sender.dltCategory == 'T') {
      tx += 1;
      signals.add(const SmsSignal('dlt_transactional', 1));
    }

    if (_debitVerb.hasMatch(lower)) {
      tx += 4;
      signals.add(const SmsSignal('debit_verb', 4));
    }
    if (_creditVerb.hasMatch(lower)) {
      tx += 3;
      signals.add(const SmsSignal('credit_verb', 3));
    }
    if (hasAmount) {
      tx += 2;
      signals.add(SmsSignal('amount', 2, detail: '₹${(amount.paise / 100).toStringAsFixed(2)} found'));
    }
    if (_cashbackCredit.hasMatch(lower) &&
        hasAmount &&
        sender.trust == SenderTrust.known) {
      tx += 5;
      signals.add(const SmsSignal('cashback_credit', 5, detail: 'Cashback credit from a known sender'));
    }

    if (_otpWord.hasMatch(lower)) {
      final fakeOtp = _otpLikeNumber.hasMatch(lower) &&
          !_debitVerb.hasMatch(lower) &&
          !_creditVerb.hasMatch(lower);
      info += fakeOtp ? 8 : 5;
      signals.add(const SmsSignal('otp_wording', -5, detail: 'Contains OTP / never-share wording'));
    }
    for (final (code, pattern, weight) in _infoIntents) {
      if (!pattern.hasMatch(lower)) continue;
      info += weight;
      signals.add(SmsSignal(code, -weight));
    }
    if (_requestMoney.hasMatch(lower)) {
      info += 6;
      tx -= 4;
      signals.add(const SmsSignal('upi_request', -6, detail: 'A money request, not a payment'));
    }
    if (_addMoneyVerb.hasMatch(lower)) {
      tx += 3;
      signals.add(const SmsSignal('money_moved', 3, detail: 'Wallet / deposit wording'));
    }

    final negatedShare = SmsGuards.shareIsNegated(lower);
    final credentialAsk = _isCredentialAsk(lower);
    if (credentialAsk) {
      phish += 8;
      signals.add(const SmsSignal('credential_ask', -8, detail: 'Asks for an OTP/PIN/password'));
    }
    final scamTemplate = _scamTemplate.hasMatch(lower);
    if (scamTemplate) {
      phish += 5;
      signals.add(const SmsSignal('scam_template', -5, detail: 'Matches a known scam template'));
    }
    final fraudTemplate = _fraudTemplate.hasMatch(lower);
    if (!negatedShare && fraudTemplate) {
      phish += 5;
      signals.add(const SmsSignal('fraud_template', -5, detail: 'Matches a known social-engineering template'));
    }

    if (_promoWord.hasMatch(lower)) {
      promo += 4;
      signals.add(const SmsSignal('promo_wording', -4, detail: 'Marketing / cross-sell language'));
    }
    if (RegExp(r'\b(?:unsubscribe|to stop (?:receiving|sms)|opt out)\b')
        .hasMatch(lower)) {
      promo += 3;
      signals.add(const SmsSignal('opt_out', -3, detail: 'Bulk-marketing opt-out text'));
    }

    final safeContext = _safeContext.hasMatch(lower);
    final kycLure = !safeContext && _kycLure.hasMatch(lower);
    if (kycLure) {
      phish += 4;
      signals.add(const SmsSignal('kyc_lure', -4, detail: 'KYC / block / expiry pressure wording'));
    }

    final url = _firstUrl(lower, body);
    final risk = url == null
        ? (suspicious: false, impersonation: false, owned: false)
        : _urlRisk(url);
    final suspiciousUrl = risk.suspicious;
    final impersonation = risk.impersonation;
    if (impersonation) {
      phish += 6;
      signals.add(SmsSignal('brand_impersonation', -6, detail: url));
    } else if (suspiciousUrl) {
      phish += 3;
      signals.add(SmsSignal('suspicious_link', -3, detail: url));
    } else if (url != null) {
      info += 1;
      signals.add(SmsSignal('bank_link', -1, detail: url));
    }
    // `visit` / `call` only count as a call to action next to a link: a genuine
    // advisory says "visit your home branch" with no URL (info-05).
    final linkCta = url != null && RegExp(r'\b(?:visit|click|call)\b').hasMatch(lower);
    final callToAction = _phishCta.hasMatch(lower) || linkCta;
    final threat = _threatWording.hasMatch(lower);
    if (callToAction) {
      phish += 2;
      signals.add(const SmsSignal('call_to_action', -2));
    }

    final notMoved = SmsGuards.notMovedYet(lower);
    final receipt = SmsGuards.merchantReceipt(lower) &&
        amountFinder.balanceAfter(body) == null &&
        amountFinder.availableLimit(body) == null;

    // Decisive fraud evidence. Deliberately *not* a score threshold: a link
    // plus a call to action is an advertisement far more often than a scam, and
    // treating it as fraud flagged 151 real messages with no true positive.
    // Fraud needs one of: a credential request, a known scam template, a
    // domain impersonating the issuer, a KYC/threat pretext (with a bad channel
    // or an explicit loss threat), or an unregistered sender asking for money.
    final badChannel = suspiciousUrl || impersonation;
    final preciousPretext = kycLure || fraudTemplate;
    final strongPhish =
        credentialAsk ||
        scamTemplate ||
        impersonation ||
        (preciousPretext && badChannel) ||
        // The issuer's own KYC reminder on its own domain from its registered
        // header ("A/c will be blocked as KYC is due, update at i.airtel.in")
        // is pushy, not fraud. Gold set: 5 of 5 such messages are genuine.
        (kycLure && threat && !(_ownsLink(sender, url, risk.owned) && sender.trust == SenderTrust.known)) ||
        (fraudTemplate && threat) ||
        (sender.trust == SenderTrust.suspicious &&
            callToAction &&
            badChannel) ||
        (sender.trust == SenderTrust.suspicious && _requestMoney.hasMatch(lower));
    // No spam-as-spend: an amount plus a trusted header is not enough. Offer /
    // eligibility / limit wording ("Loan of INR 36,000 available for you") never
    // books a row; only a completed movement of money does.
    final moved = SmsGuards.moneyMoved(lower);
    final genuineTransaction = tx >= 6 &&
        hasAmount &&
        moved &&
        // A `-P` DLT header is marketing by definition: "Salary credited, game
        // upgraded. Buy cultpass…" is a promo, not a salary.
        sender.dltCategory != 'P' &&
        sender.trust != SenderTrust.suspicious;
    // The merchant's own receipt (Swiggy, Zepto, …) is not the user's account.
    final merchantSender = registry.isMerchantReceiptSender(sender);
    final paidReceipt = !notMoved &&
        SmsGuards.paidReceipt(lower) &&
        (amount != null || SmsGuards.planAmountPaise(body) != null) &&
        sender.dltCategory != 'P' &&
        sender.trust != SenderTrust.suspicious;

    SmsClass cls;
    if (strongPhish) {
      cls = SmsClass.phishing;
    } else if (paidReceipt) {
      // A biller/merchant confirming a completed payment. It posts as a
      // `receipt` row and only counts when no bank alert covers it.
      cls = SmsClass.transaction;
      signals.add(const SmsSignal('merchant_receipt', 3,
          detail: 'Merchant confirms a completed payment'));
    } else if (notMoved || receipt || merchantSender ||
        SmsGuards.fundHouseConfirmation(lower)) {
      // Nothing has moved yet (bill due, decline, collect request, mandate
      // set-up), or a fund house is confirming units for a debit the bank
      // already reported — counting both was 12 of 18 double counts.
      cls = SmsClass.informational;
    } else if (genuineTransaction) {
      cls = SmsClass.transaction;
    } else if (info >= 4 && info >= promo) {
      cls = SmsClass.informational;
    } else if (promo >= 4) {
      cls = SmsClass.promo;
    } else if (tx >= 4 && hasAmount && moved) {
      cls = SmsClass.transaction;
    } else {
      cls = SmsClass.unknown;
    }
    // A `-P` header is promotional by TRAI's DLT rules, whatever the copy says
    // ("Your bill payment of Rs.2249 was successful. You could've paid less
    // with…"). The real alert for the same payment arrives on an `-S` header.
    if (cls == SmsClass.transaction && sender.dltCategory == 'P') {
      cls = SmsClass.promo;
      signals.add(const SmsSignal('dlt_promotional_veto', -6,
          detail: 'Promotional (-P) headers never post a transaction'));
    }

    final score = _confidenceFor(
      cls: cls,
      tx: tx,
      info: info,
      promo: promo,
      phish: phish,
      hasAmount: hasAmount,
      trust: sender.trust,
    );

    return SmsAssessment(
      cls: cls,
      score: score,
      signals: signals,
      senderTrust: sender.trust,
    );
  }

  /// The first URL that is not part of a VPA / email handle.
  ///
  /// `Never share OTP @mycards.hdfc.bank.in` is an *email-style handle*, and
  /// matching its `bank.in` tail as a link was one of the two reasons every HDFC
  /// OTP was labelled fraud.
  String? _firstUrl(String lower, String body) {
    for (final match in _url.allMatches(lower)) {
      final start = match.start;
      if (start > 0) {
        final before = lower[start - 1];
        if (RegExp(r'[a-z0-9@._%-]').hasMatch(before)) continue;
      }
      final text = match.group(0)!;
      // A real link is printed as lowercase; `credited.Info:UPI…` is a sentence
      // that happens to contain a dot, not a domain.
      final original = start + text.length <= body.length
          ? body.substring(start, start + text.length)
          : text;
      if (!text.startsWith('http') && original != text) continue;
      return text.replaceAll(RegExp(r'[)\],.;:]+$'), '');
    }
    return null;
  }

  /// Registrable domains that genuinely belong to a brand. A host that *claims*
  /// a brand but is not on the list is impersonation — the one strong link-only
  /// fraud signal, and what the lookalike-header fixtures rely on.
  static const Map<String, List<String>> _brandDomains = {
    'hdfc': ['hdfcbank.com', 'hdfc.bank.in'],
    'icici': ['icicibank.com', 'icici.bank.in', 'icicipruamc.com', 'iciciprumf.com'],
    'sbi': [
      'sbi.co.in', 'sbicard.com', 'onlinesbi.sbi', 'sbi.bank.in', 'sbiyono.sbi',
      'onlinesbi.com',
    ],
    'axis': ['axisbank.com', 'axisbank.co.in', 'axbk.io'],
    'kotak': ['kotak.com', 'kotak.bank.in'],
    'idfc': ['idfcfirstbank.com', 'idfc.bank.in'],
    'rbl': ['rblbank.com', 'rbl.bank.in'],
    'yes': ['yesbank.in', 'yes.bank.in'],
    'indusind': ['indusind.com'],
    'amex': ['americanexpress.com', 'amex.in', 'amex.com'],
    'phonepe': ['phonepe.com'],
    'paytm': ['paytm.com', 'paytmbank.com', 'paytm.me'],
    'cred': ['cred.club'],
    'onecard': ['getonecard.app', 'onecard.app'],
    'uidai': ['uidai.gov.in'],
    'irctc': ['irctc.co.in'],
    'indiapost': ['indiapost.gov.in'],
  };

  /// Domains a registered header is known to own, for brands whose own
  /// domain is too generic to list as a brand (`airtel` would also match
  /// `airtelxstream.in` adverts).
  static const Map<String, List<String>> _headerDomains = {
    'AIRBNK': ['airtel.in'],
    'AIRTEL': ['airtel.in'],
    'AIRINF': ['airtel.in'],
    'JIOPAY': ['jio.com'],
  };

  bool _ownsLink(SenderId sender, String? url, bool brandOwned) {
    if (brandOwned) return true;
    if (url == null) return false;
    final domains = _headerDomains[sender.normalized];
    if (domains == null) return false;
    final host = _hostOf(url);
    return domains.any((d) => host == d || host.endsWith('.$d'));
  }

  /// Suffixes governed by a real institution (RBI's `.bank.in`, the government
  /// domains). A host under one of these is never a lookalike.
  static const Set<String> _trustedSuffixes = {
    '.bank.in', '.gov.in', '.nic.in', '.rbi.org.in', '.sbi', '.amex',
  };

  static const Set<String> _shorteners = {
    'bit.ly', 'tinyurl.com', 't.co', 'goo.gl', 'ow.ly', 'is.gd', 'cutt.ly',
    'rb.gy', 'shorturl.at', 'rebrand.ly', 't.ly', 'bit.do',
  };

  static const Set<String> _oddTlds = {
    '.xyz', '.top', '.club', '.live', '.icu', '.biz', '.vip', '.link',
    '.online', '.shop', '.site', '.me', '.co',
  };

  String _hostOf(String url) => url
      .replaceFirst(RegExp(r'^https?://'), '')
      .split('/')
      .first
      .toLowerCase();

  /// `kyc-review.top` / `hdfcbank.com` — the last two labels, keeping India's
  /// `co.in` / `com.au` style second-level suffixes intact.
  String _registrableDomain(String host) {
    final labels = host.split('.').where((l) => l.isNotEmpty).toList();
    if (labels.length <= 2) return host;
    final tld = labels.last;
    final secondLast = labels[labels.length - 2];
    const secondLevel = {'co', 'com', 'net', 'org', 'ac', 'gov', 'nic', 'edu'};
    if (secondLast.length <= 3 && secondLevel.contains(secondLast)) {
      return labels.sublist(labels.length - 3).join('.');
    }
    if (tld == 'in' && secondLevel.contains(secondLast)) {
      return labels.sublist(labels.length - 3).join('.');
    }
    return labels.sublist(labels.length - 2).join('.');
  }

  ({bool suspicious, bool impersonation, bool owned}) _urlRisk(String url) {
    final host = _hostOf(url);
    if (_trustedSuffixes.any(host.endsWith)) {
      return (suspicious: false, impersonation: false, owned: true);
    }
    final registrable = _registrableDomain(host);
    // A host that names a brand must be that brand's own domain.
    for (final entry in _brandDomains.entries) {
      final brand = entry.key;
      final claimsBrand = RegExp(
        '(^|[.\\-])${RegExp.escape(brand)}',
      ).hasMatch(host) &&
          // A three-letter brand (`yes`, `sbi`) must stand alone as a label
          // prefix — `yesbankltd` is a VPA handle, not a Yes Bank claim.
          (brand.length >= 4 ||
              RegExp('(^|[.\\-])${RegExp.escape(brand)}(?=[.\\-]|\\d)')
                  .hasMatch(host));
      if (!claimsBrand) continue;
      final trusted = entry.value.any(
        (domain) => registrable == domain || host.endsWith('.$domain'),
      );
      if (!trusted) {
        return (suspicious: true, impersonation: true, owned: false);
      }
      return (suspicious: false, impersonation: false, owned: true);
    }
    if (_shorteners.contains(host)) {
      return (suspicious: true, impersonation: false, owned: false);
    }
    if (RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$').hasMatch(host)) {
      return (suspicious: true, impersonation: false, owned: false);
    }
    if (_oddTlds.any(registrable.endsWith)) {
      return (suspicious: true, impersonation: false, owned: false);
    }
    return (suspicious: false, impersonation: false, owned: false);
  }

  double _confidenceFor({
    required SmsClass cls,
    required int tx,
    required int info,
    required int promo,
    required int phish,
    required bool hasAmount,
    required SenderTrust trust,
  }) {
    final scores = <SmsClass, num>{
      SmsClass.transaction: tx,
      SmsClass.informational: info,
      SmsClass.promo: promo,
      SmsClass.phishing: phish,
      SmsClass.unknown: 0,
    };
    final own = (scores[cls] ?? 0).toDouble();
    final rival = scores.entries
        .where((e) => e.key != cls)
        .map((e) => e.value.toDouble())
        .fold<double>(0, (a, b) => b > a ? b : a);
    final margin = own - rival;
    var confidence = 0.5 + margin * 0.06;
    if (cls == SmsClass.transaction && !hasAmount) confidence -= 0.2;
    if (trust == SenderTrust.known) confidence += 0.1;
    if (trust == SenderTrust.suspicious) confidence -= 0.05;
    return confidence.clamp(0.05, 0.99);
  }

  static String _normalize(String body) {
    return body
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[\u2013\u2014]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

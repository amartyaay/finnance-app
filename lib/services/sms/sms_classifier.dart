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
    r'txn of|transaction of|used for|deducted)\b',
    caseSensitive: false,
  );
  static final RegExp _creditVerb = RegExp(
    r'\b(credited|credit received|received from|deposited|refund(?:ed)?|'
    r'reversal|reversed|chargeback|cashback credited|money received)\b',
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
  static final RegExp _kycLure = RegExp(
    r'\b(?:kyc|k\.y\.c|re-?kyc|pan card|aadhaar|aadhar|update your|link your|'
    r'expire[sd]?|expiring|block(?:ed)?|suspend(?:ed)?|deactivat(?:e|ed)|'
    r'frozen|reactivate|verify your|verification pending|complete your)\b',
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
    r'(?:https?://|www\.)[^\s]+|\b[a-z0-9-]+\.(?:com|in|net|org|xyz|top|club|live|icu|info|co|biz|me|site|online|shop|vip|link)(?:/[^\s]*)?',
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
  static final RegExp _credentialAsk = RegExp(
    r'\b(?:share|send|tell|confirm|enter|provide)\b.{0,24}'
    r'\b(?:otp|o\.t\.p|cvv|pin|password|upi\s*pin|debit\s*card\s*number|'
    r'card\s*number|aadhaar\s*number|net\s*banking\s*(?:id|password))\b',
    caseSensitive: false,
  );

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
    r'\b(?:won|winner|lucky draw|lottery|prize|gift card|'
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
    final credentialAsk = !negatedShare && _credentialAsk.hasMatch(lower);
    if (credentialAsk) {
      phish += 8;
      signals.add(const SmsSignal('credential_ask', -8, detail: 'Asks for an OTP/PIN/password'));
    }
    final scamTemplate = _scamTemplate.hasMatch(lower);
    if (scamTemplate) {
      phish += 5;
      signals.add(const SmsSignal('scam_template', -5, detail: 'Matches a known scam template'));
    }
    if (!negatedShare && _fraudTemplate.hasMatch(lower)) {
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
    if (!safeContext && _kycLure.hasMatch(lower)) {
      phish += 4;
      signals.add(const SmsSignal('kyc_lure', -4, detail: 'KYC / block / expiry pressure wording'));
    }

    final url = _url.firstMatch(lower)?.group(0);
    final suspiciousUrl = url != null && _isSuspiciousUrl(url, sender);
    if (suspiciousUrl) {
      phish += 5;
      signals.add(SmsSignal('suspicious_link', -5, detail: url));
    } else if (url != null) {
      info += 1;
      signals.add(SmsSignal('bank_link', -1, detail: url));
    }
    // `visit` / `call` only count as a call to action next to a link: a genuine
    // advisory says "visit your home branch" with no URL (info-05).
    final linkCta = url != null && RegExp(r'\b(?:visit|click|call)\b').hasMatch(lower);
    if (_phishCta.hasMatch(lower) || linkCta) {
      phish += 3;
      signals.add(const SmsSignal('call_to_action', -3));
    }

    final notMoved = SmsGuards.notMovedYet(lower);
    final receipt = SmsGuards.merchantReceipt(lower) &&
        amountFinder.balanceAfter(body) == null &&
        amountFinder.availableLimit(body) == null;

    // Decisive fraud evidence: a credential ask or a known scam template beats a
    // perfect transaction template (fraud-02/05/06/15). A suspicious link alone
    // is not decisive — a promo on a cheap TLD stays promo (promo-07/09).
    final strongPhish = credentialAsk || scamTemplate;
    // No spam-as-spend: an amount plus a trusted header is not enough. Offer /
    // eligibility / limit wording ("Loan of INR 36,000 available for you") never
    // books a row; only a completed movement of money does.
    final moved = SmsGuards.moneyMoved(lower);
    final genuineTransaction = tx >= 6 &&
        hasAmount &&
        moved &&
        sender.trust != SenderTrust.suspicious;
    // The merchant's own receipt (Swiggy, Zepto, …) is not the user's account.
    final merchantSender = registry.isMerchantReceiptSender(sender);

    SmsClass cls;
    if (strongPhish) {
      cls = SmsClass.phishing;
    } else if (notMoved || receipt || merchantSender) {
      // Nothing has moved yet: bill due, decline, collect request, mandate set-up.
      cls = SmsClass.informational;
    } else if (phish >= 6) {
      // Heavy phishing evidence is never booked, even when the debit template is
      // perfect (fraud-02: lookalike header + non-bank domain).
      cls = SmsClass.phishing;
    } else if (genuineTransaction) {
      cls = SmsClass.transaction;
    } else if (info >= 4 && info >= promo) {
      cls = SmsClass.informational;
    } else if (promo >= 4) {
      cls = SmsClass.promo;
    } else if (phish >= 4) {
      cls = SmsClass.phishing;
    } else if (tx >= 4 && hasAmount && moved) {
      cls = SmsClass.transaction;
    } else {
      cls = SmsClass.unknown;
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

  bool _isSuspiciousUrl(String url, SenderId sender) {
    final host = url
        .replaceFirst(RegExp(r'^https?://'), '')
        .split('/')
        .first
        .toLowerCase();
    const shorteners = {
      'bit.ly', 'tinyurl.com', 't.co', 'goo.gl', 'ow.ly', 'is.gd', 'cutt.ly',
      'rb.gy', 'shorturl.at', 'rebrand.ly', 't.ly', 'bit.do',
    };
    if (shorteners.contains(host)) return true;
    if (RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$').hasMatch(host)) return true;
    const oddTlds = {'.xyz', '.top', '.club', '.live', '.icu', '.biz', '.vip', '.link', '.online', '.shop', '.site', '.me'};
    if (oddTlds.any(host.endsWith)) return true;
    // A genuine bank domain usually contains the entity we already recognise.
    final entity = sender.entity?.toLowerCase().split(' ').first;
    if (entity != null && entity.length >= 4 && !host.contains(entity)) {
      final looksBanky = RegExp(r'bank|kyc|verify|secure|update|alert|card').hasMatch(host);
      if (looksBanky) return true;
    }
    return false;
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

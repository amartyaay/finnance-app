// Classifier golden corpus extracted from
// `docs/research/02-spam-and-phishing.md` Appendix A.
//
// Every fixture is a realistic Indian bank/UPI/wallet message. Malicious domains
// and phone numbers are illustrative only — they were never registered, resolved
// or contacted.
//
// Two axes are asserted separately:
//   expected  -> what the message *is* (the research five-class taxonomy)
//   suspicion -> how much we trust it (clear / check / warn)
//
// A `transaction` can legitimately carry `check`/`warn` (unverified sender); in
// that case `countsTowardLedger` MUST be false (hard rule H6).

/// The research document's product taxonomy. It is deliberately *not* the app's
/// `SmsClass`: the research splits OTP out of informational and calls fraud
/// "fraud", while the shipped enum folds OTP into `informational` and fraud into
/// `phishing`. `spam_corpus_test.dart` owns that mapping, so the corpus stays a
/// faithful copy of the research.
enum SpamClass { transaction, informational, otp, promo, fraud }

/// How much the message is trusted, independent of what it is.
enum Suspicion { clear, check, warn }

class SpamFixture {
  const SpamFixture({
    required this.id,
    required this.sender,
    required this.body,
    required this.expected,
    required this.suspicion,
    required this.reason,
    this.countsTowardLedger = true,
    this.tags = const <String>[],
  });

  final String id;
  final String sender;
  final String body;

  /// What the message is, in the research taxonomy.
  final SpamClass expected;

  final Suspicion suspicion;

  /// Why the research document expects this class (fixture-contract `note`).
  final String reason;

  final bool countsTowardLedger;
  final List<String> tags;

  /// Fixture-contract alias for [reason].
  String get note => reason;

  /// Pass-rate bucket label.
  String get bucket => expected.name;
}
const List<SpamFixture> spamCorpus = <SpamFixture>[
  // ─────────────────────────── genuine transactions ───────────────────────────
  SpamFixture(
    id: 'tx-01',
    sender: 'VM-HDFCBK-T',
    body: 'Rs.450.00 debited from a/c XX1234 on 12-05-26 to VPA swiggy@okaxis. '
        'Avl bal Rs.12,345.67. Not you? Call 18001201243.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Trusted header + debit verb + amount + masked a/c + balance; the 1800 number is a bank toll-free.',
    tags: ['trustedHeader', 'balancePresent'],
  ),
  SpamFixture(
    id: 'tx-02',
    sender: 'VK-SBIINB-T',
    body: 'Your a/c XX9082 debited Rs.2,000.00 on 03-06-26 by UPI to 9876543210@ybl. '
        'Bal Rs.15,220.10.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'UPI debit template, amount anchored to "debited", balance present.',
    tags: ['trustedHeader', 'upi'],
  ),
  SpamFixture(
    id: 'tx-03',
    sender: 'AD-ICICIB-T',
    body: 'ICICI Bank: Rs 1,299.00 spent on your Credit Card XX4412 at AMAZON on 11-06-26. '
        'Avl limit Rs 78,701.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Card-spend template with merchant and available limit.',
    tags: ['trustedHeader', 'card'],
  ),
  SpamFixture(
    id: 'tx-04',
    sender: 'VM-AXISBK-T',
    body: 'Rs.5,000 debited from A/c XX7810 on 09-06-26. IMPS Ref 609812345678. '
        'Avl Bal 22,310.44.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'IMPS reference + balance; no promo or credential content.',
    tags: ['trustedHeader', 'imps'],
  ),
  SpamFixture(
    id: 'tx-05',
    sender: 'JD-KKBK-T',
    body: 'Kotak: Rs.249.00 debited from a/c **3344 on 10-06-26 towards Netflix. '
        'Bal Rs.9,110.02.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Merchant debit with balance; star-mask account format.',
    tags: ['trustedHeader', 'subscription'],
  ),
  SpamFixture(
    id: 'tx-06',
    sender: 'AD-PUNB-T',
    body: 'PNB: Rs.12,000.00 credited to your a/c 0XXXXXX7712 on 01-06-26 '
        '(NEFT: SALARY JUN). Bal Rs. 34,009.11.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Salary credit via NEFT from a trusted header; credit verb + balance.',
    tags: ['trustedHeader', 'credit'],
  ),
  SpamFixture(
    id: 'tx-07',
    sender: 'VM-BARB-T',
    body: 'BOB: Your a/c XX5590 has been debited by Rs.800.00 on 07-06-26 at '
        'ATM CASH WDL. Bal 6,420.15.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'ATM withdrawal template; passive "has been debited" still matches the debit rule.',
    tags: ['trustedHeader', 'atm'],
  ),
  SpamFixture(
    id: 'tx-08',
    sender: 'VK-CANBK-T',
    body: 'Rs.150.00 debited from a/c XX2231 to VPA tea@okhdfcbank on 08-06-26. '
        'Avl Bal Rs.2,004.55.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Small-ticket UPI debit; counterparty VPA is not a URL despite the dot in the handle.',
    tags: ['trustedHeader', 'vpaNotUrl'],
  ),
  SpamFixture(
    id: 'tx-09',
    sender: 'AD-IDFB-T',
    body: 'IDFC FIRST: Rs.3,499 debited on card XX8890 at FLIPKART on 05-06-26. '
        'Avl limit 46,501.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Card spend with merchant; "Avl limit" variant of the balance feature.',
    tags: ['trustedHeader', 'card'],
  ),
  SpamFixture(
    id: 'tx-10',
    sender: 'JM-YESBK-T',
    body: 'Yes Bank: Rs.99.00 debited from a/c XX6612 for E-MANDATE (SPOTIFY) on '
        '04-06-26. Bal 8,002.10.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Recurring e-mandate debit; template match beats the "E-MANDATE" lifecycle noun.',
    tags: ['trustedHeader', 'recurring'],
  ),
  SpamFixture(
    id: 'tx-11',
    sender: 'AD-FDRL-T',
    body: 'Federal Bank: A/c XX3320 debited Rs.1,000.00 on 06-06-26, UPI Ref '
        '612345678901. Bal Rs. 19,300.00.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Verb-first template with UPI reference; the 12-digit ref must not be read as an amount.',
    tags: ['trustedHeader', 'refNotAmount'],
  ),
  SpamFixture(
    id: 'tx-12',
    sender: 'VM-HDFCBK-T',
    body: 'Rs 21.00 debited from a/c XX1234 to VPA metro@okicici on 12-06-26. '
        'Bal 12,324.67. Get 5% cashback on your next Metro recharge with HDFC Bank '
        'Debit Card. T&C apply. To stop receiving, SMS STOP to 5676767.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Cross-sell tail inside a genuine debit: amount must stay 21.00, not 5% or 5676767. '
        'Offer flag set, class and suspicion unchanged.',
    tags: ['trustedHeader', 'containsOffer', 'amountTrap'],
  ),
  SpamFixture(
    id: 'tx-13',
    sender: 'VK-SBICRD-T',
    body: 'SBI Card: Rs.2,999.00 spent on your SBI Card XX3311 at CROMA on 02-06-26. '
        'Avl credit limit Rs. 41,010.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Card issuer header distinct from the bank header; still a trusted allowlist entry.',
    tags: ['trustedHeader', 'card'],
  ),
  SpamFixture(
    id: 'tx-14',
    sender: 'AD-AMZNIN-T',
    body: 'Amazon Pay: Rs.199 debited from your Amazon Pay balance for order '
        '#402-1234567 on 12-06-26. Balance Rs.310.50.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Wallet debit; order id contains digits but no currency marker, so it is not an amount.',
    tags: ['trustedHeader', 'wallet'],
  ),
  SpamFixture(
    id: 'tx-15',
    sender: 'VM-PAYTMB-T',
    body: 'Paytm: Rs.250 paid to BigBasket via UPI from your Paytm Payments Bank a/c '
        'XX4412. Ref 512345678901. Bal 1,120.00.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: '"paid" is a debit verb; balance and ref corroborate the template.',
    tags: ['trustedHeader', 'wallet', 'upi'],
  ),
  SpamFixture(
    id: 'tx-16',
    sender: 'AD-HDFCBK-T',
    body: 'Rs.75,000.00 credited to a/c XX1234 on 01-06-26 by NEFT (HDFC LTD). '
        'Avl bal Rs.87,324.67.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Large credit, trusted header, template match; "HDFC LTD" in the counterparty is not a second brand claim.',
    tags: ['trustedHeader', 'credit'],
  ),
  SpamFixture(
    id: 'tx-17',
    sender: 'VK-SBIINB-T',
    body: 'Rs.500.00 credited to your a/c XX9082 on 10-06-26 as reversal of failed UPI '
        'txn 555123456789. Bal 15,720.10.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Reversal is a credit transaction; "failed" must not make it informational.',
    tags: ['trustedHeader', 'reversal'],
  ),
  SpamFixture(
    id: 'tx-18',
    sender: 'VM-HDFCBK-T',
    body: 'Rs.1,000.00 debited from a/c XX1234 on 12-06-26 to VPA rent@okhdfcbank. '
        'Click here to view: https://hdfcbank.com/txn/abc123. Bal 11,324.67.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Genuine debit with an allowlisted "view" link. Link presence alone must NOT demote '
        'the class or trigger a warning (hard rule H3).',
    tags: ['trustedHeader', 'hasLink', 'h3'],
  ),

  // ─────────────────────── genuine informational ───────────────────────
  SpamFixture(
    id: 'info-01',
    sender: 'VM-HDFCBK-S',
    body: 'Your a/c XX1234 balance as on 12-06-26 is Rs.12,345.67. For statement, '
        'log in to HDFC Bank MobileBanking.',
    expected: SpamClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Balance-on-request notice: no money verb, no link, trusted header.',
    tags: ['trustedHeader', 'balanceOnly'],
  ),
  SpamFixture(
    id: 'info-02',
    sender: 'VK-SBIINB-S',
    body: 'Your account statement for May 2026 has been sent to your registered email. '
        'Visit onlinesbi.sbi to view.',
    expected: SpamClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Statement notice; the only domain-looking token is an allowlisted SBI domain.',
    tags: ['trustedHeader', 'statement'],
  ),
  SpamFixture(
    id: 'info-03',
    sender: 'AD-ICICIB-S',
    body: 'Cheque no. 442311 for Rs.15,000.00 has been cleared from a/c XX6677 on '
        '12-06-26.',
    expected: SpamClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Cheque-cleared notice contains an amount but no debit/credit verb applied to the account, '
        'so it is informational (I2 beats T3).',
    tags: ['trustedHeader', 'cheque'],
  ),
  SpamFixture(
    id: 'info-04',
    sender: 'VM-KKBK-S',
    body: 'Your fixed deposit KKBKFD90812 matures on 20-06-26. To renew, log in to '
        'Kotak Mobile Banking.',
    expected: SpamClass.informational,
    suspicion: Suspicion.clear,
    reason: 'FD maturity reminder; "renew" is not a money verb.',
    tags: ['trustedHeader', 'maturity'],
  ),
  SpamFixture(
    id: 'info-05',
    sender: 'VK-SBIINB-S',
    body: 'Dear Customer, as per RBI guidelines please complete your KYC by visiting '
        'your home branch with Aadhaar and PAN. No update is done over phone or link. -SBI',
    expected: SpamClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Genuine KYC reminder: KYC lure fires F5, but there is NO link, NO callback and NO '
        'deadline, and it explicitly disclaims phone/link updates. N3 offsets.',
    tags: ['trustedHeader', 'kycGenuine', 'boundary'],
  ),
  SpamFixture(
    id: 'info-06',
    sender: 'AD-HDFCBK-S',
    body: 'Your new Debit Card XX9012 has been dispatched and will be delivered in 5 '
        'working days. Track in the HDFC Bank app.',
    expected: SpamClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Card dispatch; "Track in the app" is an app reference, not a URL.',
    tags: ['trustedHeader', 'dispatch'],
  ),
  SpamFixture(
    id: 'info-07',
    sender: 'VM-AXISBK-S',
    body: 'Your e-mandate for Rs.499.00 to NETFLIX has been created successfully. It will '
        'be debited on 05th of every month.',
    expected: SpamClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Mandate creation mentions a future debit but no money moved yet; T has no debit-verb '
        'match in the past tense template, I2 wins.',
    tags: ['trustedHeader', 'emandate'],
  ),
  SpamFixture(
    id: 'info-08',
    sender: 'VK-PUNB-S',
    body: 'Your passbook has been updated. For details visit pnbindia.in or your branch.',
    expected: SpamClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Passbook update with an allowlisted domain.',
    tags: ['trustedHeader', 'passbook'],
  ),
  SpamFixture(
    id: 'info-09',
    sender: 'AD-UIDAI-G',
    body: 'Your Aadhaar OTP for update request is 480112. Do not share this OTP with '
        'anyone. -UIDAI',
    expected: SpamClass.otp,
    suspicion: Suspicion.clear,
    reason: 'Government OTP: -G suffix, no link, anti-sharing line. Classified otp, not informational.',
    tags: ['govt', 'otp'],
  ),
  SpamFixture(
    id: 'info-10',
    sender: 'VM-HDFCBK-S',
    body: 'Minimum balance alert: Your a/c XX1234 balance is below Rs.10,000. Maintain '
        'balance to avoid charges.',
    expected: SpamClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Advisory, no money verb, no link. "charges" is a noun here, not a charge event.',
    tags: ['trustedHeader', 'advisory'],
  ),
  SpamFixture(
    id: 'info-11',
    sender: 'JD-ICICIB-S',
    body: 'Your request for address update has been registered. Ref SR9081234. We will '
        'update you in 3 working days.',
    expected: SpamClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Service request acknowledgement; ref id is not an amount.',
    tags: ['trustedHeader', 'serviceRequest'],
  ),
  SpamFixture(
    id: 'info-12',
    sender: 'AD-BARB-S',
    body: 'Dear customer, our branch will remain closed on 17-06-26 on account of local '
        'holiday. Digital banking is available.',
    expected: SpamClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Branch holiday notice; "Dear customer" alone must not raise fraud weight.',
    tags: ['trustedHeader', 'branch'],
  ),
  SpamFixture(
    id: 'info-13',
    sender: 'VM-HDFCBK-S',
    body: 'Your credit card statement for May 2026 is ready. Total due Rs.12,344.00, '
        'minimum due Rs.620.00, due date 28-06-26. Pay via HDFC Bank app.',
    expected: SpamClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Statement summary with two amounts and no money movement; must not be ledgered as a spend.',
    tags: ['trustedHeader', 'statement', 'multiAmount'],
  ),
  SpamFixture(
    id: 'info-14',
    sender: 'VK-IDFB-S',
    body: 'We noticed a login to your net banking from a new device on 12-06-26 at 21:14. '
        'If this was not you, call 180010888.',
    expected: SpamClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Security notice with a genuine toll-free number; N8 applies. A 10-digit number here '
        'would flip it to check (see fraud-13).',
    tags: ['trustedHeader', 'securityNotice', 'tollFree'],
  ),

  // ─────────────────────────────── OTP ───────────────────────────────
  SpamFixture(
    id: 'otp-01',
    sender: 'VM-HDFCBK-S',
    body: '123456 is your OTP for login to HDFC Bank NetBanking. Valid for 10 mins. '
        'Do NOT share this OTP with anyone. -HDFC Bank',
    expected: SpamClass.otp,
    suspicion: Suspicion.clear,
    reason: 'Canonical legitimate OTP: code + purpose + validity + anti-sharing + no link.',
    tags: ['trustedHeader', 'otpCanonical'],
  ),
  SpamFixture(
    id: 'otp-02',
    sender: 'VK-SBIINB-T',
    body: '482913 is the OTP for your UPI txn of Rs.2,499.00 to BIGBASKET. Do not share '
        'it with anyone. -SBI',
    expected: SpamClass.otp,
    suspicion: Suspicion.clear,
    reason: 'THE critical trap: two numbers, 482913 is the OTP and 2,499.00 is a referenced txn. '
        'extractOtp must return 482913 and extractAmount must return null.',
    tags: ['trustedHeader', 'otp', 'amountTrap'],
  ),
  SpamFixture(
    id: 'otp-03',
    sender: 'AD-ICICIB-S',
    body: 'Your OTP is 771204 for card ending 4412. Never share your OTP, PIN or CVV '
        'with anyone. -ICICI Bank',
    expected: SpamClass.otp,
    suspicion: Suspicion.clear,
    reason: 'OTP with card suffix; the 4-digit "4412" is a card tail, not a code — the OTP keyword '
        'anchor picks 771204.',
    tags: ['trustedHeader', 'otp'],
  ),
  SpamFixture(
    id: 'otp-04',
    sender: 'VM-AXISBK-S',
    body: '9931 is your Axis Bank verification code. Valid 5 min. Do not disclose to '
        'anyone.',
    expected: SpamClass.otp,
    suspicion: Suspicion.clear,
    reason: '4-digit code with "verification code" synonym; no link.',
    tags: ['trustedHeader', 'otp', 'shortCode'],
  ),
  SpamFixture(
    id: 'otp-05',
    sender: 'JD-KKBK-S',
    body: 'OTP 562311 for registration on Kotak app. Do not share.',
    expected: SpamClass.otp,
    suspicion: Suspicion.clear,
    reason: 'Minimal OTP: keyword precedes the code, no amount, no link.',
    tags: ['trustedHeader', 'otp'],
  ),
  SpamFixture(
    id: 'otp-06',
    sender: 'VK-PAYTMB-T',
    body: '338291 is your Paytm OTP for txn of Rs.1,250.00 at MYNTRA. Never share OTP, '
        'even with Paytm staff.',
    expected: SpamClass.otp,
    suspicion: Suspicion.clear,
    reason: 'Wallet OTP with an amount reference; the "even with staff" line is a strong '
        'legitimacy marker (N5).',
    tags: ['trustedHeader', 'otp', 'amountTrap'],
  ),
  SpamFixture(
    id: 'otp-07',
    sender: 'AD-AMZNIN-S',
    body: '812344 is your Amazon Pay OTP. Do not share it with anyone, including Amazon.',
    expected: SpamClass.otp,
    suspicion: Suspicion.clear,
    reason: 'Non-bank wallet OTP; still trusted-brand, no link.',
    tags: ['trustedHeader', 'otp'],
  ),
  SpamFixture(
    id: 'otp-08',
    sender: 'VM-HDFCBK-T',
    body: '605512 is your OTP for adding a beneficiary. If not you, call 18001201243. '
        'Do not share.',
    expected: SpamClass.otp,
    suspicion: Suspicion.clear,
    reason: 'OTP + toll-free fraud line + anti-sharing. If the number were 10-digit this would '
        'become check, not warn.',
    tags: ['trustedHeader', 'otp', 'tollFree'],
  ),

  // ────────────────────────────── promo ──────────────────────────────
  SpamFixture(
    id: 'promo-01',
    sender: 'AD-HDFCBK-P',
    body: 'Get a Lifetime Free HDFC Bank Credit Card with vouchers worth Rs.5,000. '
        'Apply now: https://hdfcbank.com/cc?utm=promo T&C apply. To stop receiving SMS '
        'STOP to 5676767.',
    expected: SpamClass.promo,
    suspicion: Suspicion.clear,
    reason: 'Bank-branded promo on the bank real domain: promo class, clear state. A promo is not '
        'fraud just because it carries a link.',
    tags: ['trustedHeader', 'promo', 'allowlistedLink'],
  ),
  SpamFixture(
    id: 'promo-02',
    sender: 'VM-ICICIB-P',
    body: 'Pre-approved personal loan of up to Rs.15,00,000 at 10.25%. Limited period '
        'offer. Apply: https://icicibank.com/pl T&C.',
    expected: SpamClass.promo,
    suspicion: Suspicion.clear,
    reason: 'Pre-approved + limited period + apply; large rupee figure is marketing copy, '
        'not a ledger amount.',
    tags: ['trustedHeader', 'promo', 'loan'],
  ),
  SpamFixture(
    id: 'promo-03',
    sender: 'VK-AXISBK-P',
    body: 'Axis Bank: 0% interest EMI on your Axis Credit Card for 3 months. Offer ends '
        '30-06-26. Apply now T&C.',
    expected: SpamClass.promo,
    suspicion: Suspicion.clear,
    reason: '"0% interest" and "Offer ends" are promo-only constructions; no money verb.',
    tags: ['trustedHeader', 'promo', 'emi'],
  ),
  SpamFixture(
    id: 'promo-04',
    sender: 'AD-BAJAJ-P',
    body: 'Avail instant business loan up to Rs.50 lakh. No collateral. Apply online in 5 '
        'minutes. https://bajajfinserv.in T&C. Unsubscribe: reply STOP.',
    expected: SpamClass.promo,
    suspicion: Suspicion.clear,
    reason: 'NBFC promo with full opt-out furniture; "Rs.50 lakh" is a ceiling, not a transaction.',
    tags: ['promo', 'loan', 'nbfc'],
  ),
  SpamFixture(
    id: 'promo-05',
    sender: 'VM-LIC-P',
    body: 'LIC: Secure your family with Jeevan Anand. Limited period. Premium starting '
        'Rs.1,200/month. T&C. To opt out reply STOP.',
    expected: SpamClass.promo,
    suspicion: Suspicion.clear,
    reason: 'Insurance promo; "premium starting Rs." is a price, not a debit.',
    tags: ['promo', 'insurance'],
  ),
  SpamFixture(
    id: 'promo-06',
    sender: 'JD-DLF-P',
    body: '2/3 BHK luxury apartments at Gurugram starting Rs.1.2 Cr. Pre-launch offer. '
        'Site visit: 98100-12345. Unsubscribe STOP.',
    expected: SpamClass.promo,
    suspicion: Suspicion.clear,
    reason: 'Real-estate spam with a sales callback number. A mobile callback is NOT itself fraud '
        'without a bank claim or threat.',
    tags: ['promo', 'realEstate', 'callbackNumber'],
  ),
  SpamFixture(
    id: 'promo-07',
    sender: 'VK-SHOPPY-P',
    body: 'FLAT 70% OFF everything! Offer ends tonight. Shop now: bit.ly/shp70 T&C. '
        'To stop, reply STOP.',
    expected: SpamClass.promo,
    suspicion: Suspicion.clear,
    reason: 'Retail spam with a shortener: P6 fires, but with no bank claim and no credential ask '
        'it stays promo/clear, not fraud.',
    tags: ['promo', 'shortener', 'noBankClaim'],
  ),
  SpamFixture(
    id: 'promo-08',
    sender: 'AD-TIGERB-P',
    body: 'Win big! Play Teen Patti and Rummy on TigerBet. Get Rs.500 bonus on first '
        'deposit. bit.ly/tgbonus. 18+. Opt out STOP.',
    expected: SpamClass.promo,
    suspicion: Suspicion.check,
    reason: 'Gambling spam: promo class with a check state because the call to action is a deposit '
        'on an unvetted domain. Not phishing — no impersonation of the user bank.',
    tags: ['promo', 'gambling', 'shortener'],
  ),
  SpamFixture(
    id: 'promo-09',
    sender: 'VM-WEALTH-P',
    body: 'SEBI registered research: Get 3 multibagger calls daily with 90% accuracy. '
        'Join now: https://wealth-alpha.top/join. Reply STOP to opt out.',
    expected: SpamClass.promo,
    suspicion: Suspicion.check,
    reason: 'Assured-return + accuracy claims are illegal under SEBI rules; on a cheap TLD this is '
        'scammy-offer, so promo + check (not fraud: no bank/government impersonation).',
    tags: ['promo', 'investmentScam', 'untrustedDomain'],
  ),
  SpamFixture(
    id: 'promo-10',
    sender: 'AD-HDFCBK-P',
    body: 'Congratulations! You are pre-selected for a pre-approved home loan of Rs.40 '
        'lakh at 8.4%. Valid till 30-06-26. Apply now at hdfcbank.com/home-loan T&C.',
    expected: SpamClass.promo,
    suspicion: Suspicion.clear,
    reason: '"Congratulations" + "pre-approved" would raise eyebrows, but the header and domain are '
        'the bank own: benign marketing.',
    tags: ['trustedHeader', 'promo'],
  ),
  SpamFixture(
    id: 'promo-11',
    sender: 'VK-MUTUAL-P',
    body: 'Start a SIP of just Rs.500/month. Top-rated funds, zero commission. Download '
        'the app: https://groww.in/sip. T&C apply. Reply STOP to opt out.',
    expected: SpamClass.promo,
    suspicion: Suspicion.clear,
    reason: 'Fintech acquisition promo; "Rs.500/month" is a minimum, not a debit.',
    tags: ['promo', 'investments'],
  ),
  SpamFixture(
    id: 'promo-12',
    sender: 'AD-JOBALERT',
    body: 'Hiring alert! Work from home, earn Rs.25,000/month. No experience needed. '
        'WhatsApp 91-8822113344 to apply. Reply STOP to opt out.',
    expected: SpamClass.promo,
    suspicion: Suspicion.check,
    reason: 'Job lure with a WhatsApp handoff. No upfront fee in this message, so promo + check; '
        'if a registration fee appears it becomes fraud (see fraud-14).',
    tags: ['promo', 'jobLure', 'whatsapp'],
  ),
  SpamFixture(
    id: 'promo-13',
    sender: 'VM-TATAMOT-P',
    body: 'Book your Nexon EV today and save Rs.75,000 on exchange. Offer valid till '
        '30-06-26. T&C.',
    expected: SpamClass.promo,
    suspicion: Suspicion.clear,
    reason: 'Auto promo; "save Rs.75,000" is a discount, not a credit.',
    tags: ['promo', 'auto'],
  ),
  SpamFixture(
    id: 'promo-14',
    sender: 'AD-CRED-P',
    body: 'Your CRED coins expire soon. Redeem for vouchers worth up to Rs.2,000. '
        'Open the CRED app to redeem. T&C.',
    expected: SpamClass.promo,
    suspicion: Suspicion.clear,
    reason: 'Retention promo for an existing service; app deep reference, no URL.',
    tags: ['promo', 'rewards'],
  ),

  // ────────────────────────────── fraud ──────────────────────────────
  SpamFixture(
    id: 'fraud-01',
    sender: '+91 90987 65432',
    body: 'Dear Customer, Your SBI account will be blocked within 24 hrs due to '
        'incomplete KYC. Click here to update: http://sbi-kyc-verify.top/upd -SBI',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Ten-digit sender claiming SBI + KYC lure + 24-hour deadline + cheap-TLD domain: '
        'the highest-volume Indian family.',
    tags: ['numericSender', 'kycLure', 'deadline', 'untrustedDomain'],
  ),
  SpamFixture(
    id: 'fraud-02',
    sender: 'AD-HDFCBNK-T',
    body: 'Rs.12,499.00 debited from a/c XX8842. If not you, verify now at '
        'https://hdfc-secure-verify.xyz/login',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Lookalike header HDFCBNK (vs the registered HDFCBK) + non-HDFC domain. A near-perfect '
        'debit template does not save it: N2 is outweighted by the header forgery (H2).',
    tags: ['lookalikeHeader', 'debitTemplate', 'untrustedDomain'],
  ),
  SpamFixture(
    id: 'fraud-03',
    sender: 'VM-ICIClB-T',
    body: 'Your ICICI Bank account is suspended. Re-verify KYC instantly: '
        'https://icici-kyc.in-update.site/x',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Lowercase "l" stands in for "I" in the header (ICIClB). Must be caught by the '
        'mixed-case header rule plus edit distance to ICICIB.',
    tags: ['homoglyphHeader', 'kycLure', 'untrustedDomain'],
  ),
  SpamFixture(
    id: 'fraud-04',
    sender: 'VK-SBI-KYC',
    body: 'Your KYC update is pending. Share your Aadhaar OTP with our officer on '
        '9812345670 to avoid deactivation today.',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Malformed header (extra token) + explicit OTP request + mobile callback + deadline. '
        'F1 alone is nearly decisive.',
    tags: ['malformedHeader', 'credentialAsk', 'callbackNumber'],
  ),
  SpamFixture(
    id: 'fraud-05',
    sender: 'AD-HDFCBK-T',
    body: 'Dear user, you have received a refund of Rs.4,999. Share the OTP sent to your '
        'phone to receive it. -HDFC',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Refund hook + OTP request. Even with a well-formed header, the credential ask '
        'overrides trust (H1) — a bank never asks for the OTP it just sent.',
    tags: ['credentialAsk', 'refundLure', 'h1'],
  ),
  SpamFixture(
    id: 'fraud-06',
    sender: 'VM-PAYTMB',
    body: 'Your wallet is blocked. Scan this QR to receive your refund of Rs.1,500. '
        'Tap to verify: bit.ly/ptm-refund',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'QR-to-receive is impossible by construction (RBI), plus a shortener and a blocked-wallet '
        'threat.',
    tags: ['qrReceive', 'shortener', 'threat'],
  ),
  SpamFixture(
    id: 'fraud-07',
    sender: 'AD-MSEB-S',
    body: 'ALERT: Your electricity connection will be disconnected tonight as previous '
        'bill is unpaid. Call 9876543211 and update KYC immediately.',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Utility pretext + mobile callback + KYC request + same-day deadline: a documented '
        'DoT-flagged family.',
    tags: ['utilityLure', 'callbackNumber', 'kycLure'],
  ),
  SpamFixture(
    id: 'fraud-08',
    sender: 'AD-IRCTCI',
    body: 'Your IRCTC account will be suspended today. Update KYC immediately to avoid '
        'losing your booking history: http://irctc-update.site/kyc',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Travel/railway impersonation with a .site domain; header is a 6-char lookalike of a '
        'known brand token but unregistered.',
    tags: ['brandImpersonation', 'kycLure', 'untrustedDomain'],
  ),
  SpamFixture(
    id: 'fraud-09',
    sender: 'AD-INDPST',
    body: 'Your parcel is held at customs. Pay Rs.25 clearance fee: '
        'https://indiapost-tracking.top/pay',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Parcel + tiny fee + cheap TLD. The small amount is deliberate: it lowers the victim '
        'defences and captures card data.',
    tags: ['parcelLure', 'untrustedDomain'],
  ),
  SpamFixture(
    id: 'fraud-10',
    sender: '+91 8822113344',
    body: 'Part-time job: earn Rs.3,000/day liking YouTube videos. Pay Rs.500 registration '
        'and get tasks on Telegram. WhatsApp us now.',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Task scam: upfront fee to "work" is the definition of the fraud. Escalates from promo '
        'because money is requested before any service.',
    tags: ['jobScam', 'upfrontFee', 'numericSender'],
  ),
  SpamFixture(
    id: 'fraud-11',
    sender: 'AD-AXISBK-T',
    body: 'Your card XX4412 is blocked. To unblock, confirm your CVV and OTP here: '
        'http://axis-card-unblock.xyz',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Card-blocked pretext + CVV/OTP request + .xyz. CVV is never requested by any bank, '
        'in any channel.',
    tags: ['credentialAsk', 'cardBlocked', 'untrustedDomain'],
  ),
  SpamFixture(
    id: 'fraud-12',
    sender: 'AD-HDFCBK-T',
    body: 'Net banking locked. Verify at http://103.24.56.78/hdfc/login.php -HDFC Bank',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Raw IP literal in a bank message. No Indian bank links to an IP address.',
    tags: ['ipLiteral', 'untrustedDomain'],
  ),
  SpamFixture(
    id: 'fraud-13',
    sender: 'AD-PNB-S',
    body: 'Dear customer your account is debited twice. Install AnyDesk and share the code '
        'with our support to reverse Rs.2,400.',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Remote-access request: near-decisive on its own (F8). The "reverse a debit" hook is a '
        'variant of the fake-customer-care playbook.',
    tags: ['remoteAccess', 'reversalLure'],
  ),
  SpamFixture(
    id: 'fraud-14',
    sender: '+91 7012345678',
    body: 'You won Rs.25,00,000 in the KBC Lucknow lottery. Pay Rs.6,500 processing fee via '
        'UPI to claim. Call 9812345670.',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Prize + advance fee ("you must pay to receive") is the canonical lottery fraud.',
    tags: ['lottery', 'upfrontFee', 'numericSender'],
  ),
  SpamFixture(
    id: 'fraud-15',
    sender: 'AD-HDFCBK-S',
    body: 'Your account will be debited for Rs.4,999 for annual maintenance. If not you, '
        'call 9898989898 immediately to cancel.',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Money claim + 10-digit "bank" call centre. HDFC publishes 1800 lines; a mobile number '
        'plus a cancel-now deadline is the callback fraud pattern (F11).',
    tags: ['callbackNumber', 'fakeDebitClaim'],
  ),
  SpamFixture(
    id: 'fraud-16',
    sender: 'AD-9876543210',
    body: 'Rs.15,000.00 credited to your a/c XX9082 on 12-06-26 by UPI. Bal 15,220.10.',
    expected: SpamClass.transaction,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Seller scam: a flawless credit template from a 10-digit number. Class stays '
        '"transaction" (it asserts one) but trust is warn and the ledger MUST NOT count it (H6).',
    tags: ['numericSender', 'fakeCredit', 'h6', 'sellerScam'],
  ),
  SpamFixture(
    id: 'fraud-17',
    sender: 'VK-ICICIB-T',
    body: 'Dear Customer, your PAN is not linked with Aadhaar. Account will be frozen. '
        'Update now: https://pan-aadhaar-link.in',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'PAN-Aadhaar lure with a threat and a non-government .in domain. A .in TLD is not a '
        'trust signal; only the registrable domain is.',
    tags: ['panAadhaarLure', 'threat', 'untrustedDomain'],
  ),
  SpamFixture(
    id: 'fraud-18',
    sender: 'AD-UIDAI-G',
    body: 'Your Aadhaar will be deactivated. Update at http://uidai-verify.online/x',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Government impersonation: the -G suffix does not launder a non-uidai.gov.in link.',
    tags: ['govtImpersonation', 'untrustedDomain'],
  ),
  SpamFixture(
    id: 'fraud-19',
    sender: 'VM-HDFCBK-S',
    body: 'Dear Customer, we have updated our terms. Review and accept at '
        'http://hdfcbank.com.kyc-review.top/terms',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Subdomain bait: the string contains hdfcbank.com but the registrable domain is '
        'kyc-review.top. Only eTLD+1 comparison catches this.',
    tags: ['subdomainTrick', 'untrustedDomain'],
  ),
  SpamFixture(
    id: 'fraud-20',
    sender: 'AD-HDFC-S',
    body: 'To complete your video KYC, message us on WhatsApp: '
        'https://wa.me/919812345678. Keep your Aadhaar handy.',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'KYC funnel to a personal WhatsApp number. Banks never run video KYC from an '
        'unverified personal account.',
    tags: ['waLink', 'kycLure', 'brandImpersonation'],
  ),
  SpamFixture(
    id: 'fraud-21',
    sender: 'JD-SBIINB-T',
    body: 'Your account is locked for security reasons. Unlock with your net banking '
        'user id and password at https://sbi-unlock.online/secure',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Credential harvest of net-banking user id and password; no bank ever requests a '
        'password in a link.',
    tags: ['credentialAsk', 'untrustedDomain'],
  ),
  SpamFixture(
    id: 'fraud-22',
    sender: 'АD-HDFCBK-T', // leading char is Cyrillic А (U+0410)
    body: 'Your KYC is expiring. Verify within 24 hrs at https://hdfc-kyc.top/v',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Cyrillic А in the prefix renders identically. Confusable folding before allowlist '
        'comparison must catch it; otherwise the header looks ordinary.',
    tags: ['homoglyphPrefix', 'kycLure', 'untrustedDomain'],
  ),
  SpamFixture(
    id: 'fraud-23',
    sender: 'VM-PHONPE',
    body: 'Cashback of Rs.750 is pending. Accept it before it expires: '
        'https://phonepe-cashback.xyz/claim',
    expected: SpamClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Wallet-brand impersonation with an expiring-cashback hook on a .xyz domain.',
    tags: ['brandImpersonation', 'untrustedDomain', 'deadline'],
  ),
];

// SMS parsing corpus extracted from `docs/research/01-sms-corpus.md` §10.
//
// The fixture bodies, expected amounts/directions/instruments, duplicate
// groups and notes are verbatim from the research document (tier O = observed
// in a cited public corpus, V = vendor sample, I = inferred). Two fields are
// renamed to the test brief's contract:
//
//   cardIssuer -> issuer            merchant -> merchantContains
//
// `tags` is part of the fixture contract but the research document does not tag
// entries, so it defaults to an empty list. `cardLastDigits` is retained because
// an Amex card prints five digits while `last4` stays the last four.
//
// Numeric ids, card masks, VPAs and reference numbers are anonymised/fabricated.

enum SmsDirection { expense, transfer, income }

enum SmsInstrument { upi, debitCard, creditCard, account, wallet, atm }

/// Corpus bucket, derived from the `id` prefix documented in §10's coverage
/// audit. `J` (card control plane) and `K` (hard negatives and spam) both expect
/// *no* transaction, so they share [SmsBucket.negatives].
enum SmsBucket {
  upiDebits,
  debitCard,
  creditCard,
  atm,
  neftOut,
  credits,
  refunds,
  billPayments,
  autopay,
  negatives,
  duplicatePairs,
}

extension SmsBucketLabel on SmsBucket {
  String get label => switch (this) {
    SmsBucket.upiDebits => 'UPI',
    SmsBucket.debitCard => 'Debit card',
    SmsBucket.creditCard => 'Credit card',
    SmsBucket.atm => 'ATM',
    SmsBucket.neftOut => 'NEFT/IMPS',
    SmsBucket.credits => 'Credits',
    SmsBucket.refunds => 'Refunds',
    SmsBucket.billPayments => 'Bill payments',
    SmsBucket.autopay => 'Autopay',
    SmsBucket.negatives => 'Negatives',
    SmsBucket.duplicatePairs => 'Duplicate pairs',
  };
}

/// One SMS plus the outcome the parser is expected to produce.
///
/// [amountPaise] is null for messages that must never become a transaction. A
/// non-null amount on a `reject` row is the amount the SMS *mentions*, not an
/// expected ledger row. [direction] is null exactly when [confidenceHint] is
/// `reject`.
class SmsFixture {
  const SmsFixture({
    required this.id,
    required this.sender,
    required this.body,
    required this.confidenceHint,
    this.amountPaise,
    this.direction,
    this.instrument,
    this.issuer,
    this.cardLastDigits,
    this.last4,
    this.cardKey,
    this.moneyInKind,
    this.referenceId,
    this.merchantContains,
    this.isDuplicateGroup,
    this.receivedOffsetSeconds = 0,
    this.tags = const <String>[],
    this.note = '',
  });

  final String id;
  final String sender;
  final String body;

  /// 'high' | 'medium' | 'low' | 'reject'. `reject` means the message must
  /// never surface as a transaction.
  final String confidenceHint;

  final int? amountPaise;
  final SmsDirection? direction;
  final SmsInstrument? instrument;

  /// Issuer as the research document expects it (doc field: `cardIssuer`).
  final String? issuer;

  /// Card tail as printed (Amex prints five digits, some Axis templates three).
  final String? cardLastDigits;

  /// Account/card tail used for de-duplication and account matching.
  final String? last4;

  /// Expected `issuer|last4` card identity. Asserted whenever non-null: a
  /// bill-payment pair can only keep the issuer leg if that leg binds a card.
  final String? cardKey;

  /// Expected `MoneyInKind` name (e.g. `other`, `interest`). Asserted when set.
  final String? moneyInKind;

  final String? referenceId;

  /// Token the parsed merchant must contain (doc field: `merchant`).
  final String? merchantContains;

  /// Non-null when this row must collapse with the other members of the group.
  final String? isDuplicateGroup;

  /// Seconds after the corpus's fixed instant. Only duplicate groups use it:
  /// the two legs of a card-bill payment are usually hours apart.
  final int receivedOffsetSeconds;

  final List<String> tags;
  final String note;

  bool get expectsNoTransaction => confidenceHint == 'reject';

  SmsBucket get bucket => switch (id.isEmpty ? '' : id[0]) {
    'A' => SmsBucket.upiDebits,
    'B' => SmsBucket.debitCard,
    'C' => SmsBucket.creditCard,
    'D' => SmsBucket.atm,
    'E' => SmsBucket.neftOut,
    'F' => SmsBucket.credits,
    'G' => SmsBucket.refunds,
    'H' => SmsBucket.billPayments,
    'I' => SmsBucket.autopay,
    'J' || 'K' => SmsBucket.negatives,
    'L' => SmsBucket.duplicatePairs,
    _ => SmsBucket.negatives,
  };
}
const List<SmsFixture> smsCorpus = <SmsFixture>[
  // ─── A. UPI debits ─────────────────────────────────────────────────────────
  SmsFixture(
    id: 'A01',
    sender: 'VK-HDFCBK',
    body:
        'Rs.120.00 debited from a/c **4821 on 03-08-26 to VPA chaipoint@ybl (UPI Ref No 621847362514). Not you? Call 18002586161.',
    amountPaise: 12000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.upi,
    issuer: 'HDFC Bank',
    last4: '4821',
    referenceId: '621847362514',
    merchantContains: 'chaipoint',
    confidenceHint: 'high',
    note: 'V (Dibba). P2M via VPA; merchant from VPA local part.',
  ),
  SmsFixture(
    id: 'A02',
    sender: 'VM-ICICIB',
    body:
        'Rs 320.00 debited from A/c XX742 on 04-Aug-26 UPI:swiggy@icici Ref 559274810022. Call 18002662 for dispute.',
    amountPaise: 32000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.upi,
    issuer: 'ICICI Bank',
    last4: '742',
    referenceId: '559274810022',
    merchantContains: 'swiggy',
    confidenceHint: 'high',
    note: 'V (Dibba). Ref without "No"; VPA after bare "UPI:".',
  ),
  SmsFixture(
    id: 'A03',
    sender: 'VM-ICICIB',
    body:
        'ICICI Bank Acct XX240 debited for Rs 459.00 on 08-Feb-24; Axis credited. UPI:403988611918. Call 18002662 for dispute. SMS BLOCK 696 to 7668709542.',
    amountPaise: 45900,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.upi,
    issuer: 'ICICI Bank',
    last4: '240',
    referenceId: '403988611918',
    confidenceHint: 'high',
    note: 'O. P2A transfer: counterparty bank named; direction must be transfer, not expense.',
  ),
  SmsFixture(
    id: 'A04',
    sender: 'VM-ICICIB',
    body:
        'Acct XXX702 debited with INR42.97 on 03-Dec-19 and bharatpe09899148115@yesbankltd credited.Info:UPI-933716309044.Call 18002662 for dispute or SMS BLOCK 696 to 5900232221',
    amountPaise: 4297,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.upi,
    issuer: 'ICICI Bank',
    last4: '702',
    referenceId: '933716309044',
    merchantContains: 'bharatpe09899148115',
    confidenceHint: 'high',
    note: 'O. "debited ... and <vpa> credited": second verb is the counterparty, not income.',
  ),
  SmsFixture(
    id: 'A05',
    sender: 'VK-HDFCBK',
    body:
        'Rs.50.00 debited from UPI Lite (a/c **4821) to VPA kirana@ybl on 12-05-24. UPI Ref No 512345678901. UPI Lite balance Rs.1,950.00.',
    amountPaise: 5000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.wallet,
    issuer: 'HDFC Bank',
    last4: '4821',
    referenceId: '512345678901',
    merchantContains: 'kirana',
    confidenceHint: 'medium',
    note:
        'I. UPI Lite: wallet instrument, balance is the Lite wallet not the account; parent a/c **4821.',
  ),
  SmsFixture(
    id: 'A06',
    sender: 'VK-SBIINB',
    body:
        'Dear Customer, Your A/c XXXXX1234 has been debited by Rs.750.00 on 12-05-24. Info: UPI/412345678901/bigbasket@ybl. Avl Bal Rs.18,250.00.',
    amountPaise: 75000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.upi,
    issuer: 'State Bank of India',
    last4: '1234',
    referenceId: '412345678901',
    merchantContains: 'bigbasket',
    confidenceHint: 'medium',
    note: 'I. SBI Info payload: UPI/<ref>/<vpa>.',
  ),
  SmsFixture(
    id: 'A07',
    sender: 'VK-AXISBK',
    body:
        'INR 249.00 debited from your Axis Bank A/c XX5678 on 12-05-24 to zomato@axisbank. UPI Ref No 998877665544. Avl Bal INR 12,480.00.',
    amountPaise: 24900,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.upi,
    issuer: 'Axis Bank',
    last4: '5678',
    referenceId: '998877665544',
    merchantContains: 'zomato',
    confidenceHint: 'medium',
    note: 'I. "to <vpa>" without the word VPA.',
  ),
  SmsFixture(
    id: 'A08',
    sender: 'VK-HDFCBK',
    body:
        'Sent Rs.150.00 from HDFC Bank A/c *4821 to Zomato on 12-05-24. UPI Ref: 623456789012.',
    amountPaise: 15000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.upi,
    issuer: 'HDFC Bank',
    last4: '4821',
    referenceId: '623456789012',
    merchantContains: 'Zomato',
    confidenceHint: 'medium',
    note: 'I. "Sent Rs." form, no balance at all.',
  ),
  SmsFixture(
    id: 'A09',
    sender: 'VK-KOTAKB',
    body:
        'Sent Rs.899.00 from your Kotak A/c XX3321 to 9876543210@ybl on 12-05-24. UPI Ref 112233445566. Avl Bal Rs.9,301.00.',
    amountPaise: 89900,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.upi,
    issuer: 'Kotak Mahindra Bank',
    last4: '3321',
    referenceId: '112233445566',
    confidenceHint: 'medium',
    note: 'I. Numeric VPA local part => person-to-person => transfer, not expense.',
  ),

  // ─── B. Debit card POS / ECOM ──────────────────────────────────────────────
  SmsFixture(
    id: 'B01',
    sender: 'VK-SBIINB',
    body:
        'Dear Customer, Rs.849.00 spent on SBI Debit Card ending 5522 at AMAZON PAY INDIA on 02Aug26. Avl Bal Rs.12,340.55.',
    amountPaise: 84900,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.debitCard,
    issuer: 'State Bank of India',
    cardLastDigits: '5522',
    last4: '5522',
    merchantContains: 'AMAZON PAY INDIA',
    confidenceHint: 'high',
    note: 'V (Dibba). "ending <4>"; date as ddMMMyy.',
  ),
  SmsFixture(
    id: 'B02',
    sender: 'VK-HDFCBK',
    body:
        'Rs.1,299.00 spent on your HDFC Bank Debit Card ending 1234 at FLIPKART on 12-05-2024. Avl Bal Rs.45,678.90.',
    amountPaise: 129900,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.debitCard,
    issuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    merchantContains: 'FLIPKART',
    confidenceHint: 'medium',
    note: 'I. Debit card with account balance (Avl Bal, not Avl Lmt).',
  ),
  SmsFixture(
    id: 'B03',
    sender: 'VK-AXISBK',
    body:
        'INR 649.00 spent on Axis Bank Debit Card XX4321 at DMART on 12-05-24 18:42. Avl Bal INR 21,351.00.',
    amountPaise: 64900,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.debitCard,
    issuer: 'Axis Bank',
    cardLastDigits: '4321',
    last4: '4321',
    merchantContains: 'DMART',
    confidenceHint: 'medium',
    note: 'I. Explicit "Debit Card" + Avl Bal.',
  ),
  SmsFixture(
    id: 'B04',
    sender: 'VK-KOTAKB',
    body:
        'Rs.320.00 spent on your Kotak Debit Card XX8765 at SWIGGY on 12-05-2026. Avl Bal Rs.7,680.00.',
    amountPaise: 32000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.debitCard,
    issuer: 'Kotak Mahindra Bank',
    cardLastDigits: '8765',
    last4: '8765',
    merchantContains: 'SWIGGY',
    confidenceHint: 'medium',
    note: 'I. Same issuer uses "Avl bal" on credit cards too — "Debit" disambiguates.',
  ),
  SmsFixture(
    id: 'B05',
    sender: 'VK-IDFCFB',
    body:
        'INR 1,500.00 spent on your IDFC FIRST Bank Debit Card XX2468 at Croma on 12-05-24. Avl Bal INR 33,500.00.',
    amountPaise: 150000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.debitCard,
    issuer: 'IDFC FIRST Bank',
    cardLastDigits: '2468',
    last4: '2468',
    merchantContains: 'Croma',
    confidenceHint: 'medium',
    note: 'I.',
  ),
  SmsFixture(
    id: 'B06',
    sender: 'VK-HDFCBK',
    body:
        'INR 4,912.35 spent on your HDFC Bank Debit Card ending 1234 at AMAZON US on 12-05-2024 (USD 59.00). Avl Bal Rs.40,766.55.',
    amountPaise: 491235,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.debitCard,
    issuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    merchantContains: 'AMAZON US',
    confidenceHint: 'medium',
    note: 'I. Forex: INR leg is authoritative; USD leg kept as metadata. Multiple amounts.',
  ),
  SmsFixture(
    id: 'B07',
    sender: 'VK-SBIINB',
    body:
        'Rs.2,000.00 spent on SBI Debit Card ending 5522 at IRCTC on 12May24 at 09:14. Avl Bal Rs.10,340.55.',
    amountPaise: 200000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.debitCard,
    issuer: 'State Bank of India',
    cardLastDigits: '5522',
    last4: '5522',
    merchantContains: 'IRCTC',
    confidenceHint: 'medium',
    note: 'I. ddMMMyy with time suffix.',
  ),

  // ─── C. Credit-card spends ─────────────────────────────────────────────────
  SmsFixture(
    id: 'C01',
    sender: 'VM-ICICIB',
    body:
        'INR 366.19 spent on ICICI Bank Card XX2815 on 08-Jul-23 at IND*Amazon.in. Avl Lmt: INR 4,33,288.04. To dispute,call 18002662/SMS BLOCK 7007 to 8679723604',
    amountPaise: 36619,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.creditCard,
    issuer: 'ICICI Bank',
    cardLastDigits: '2815',
    last4: '2815',
    merchantContains: 'Amazon.in',
    confidenceHint: 'high',
    note: 'O. Aggregator prefix IND* stripped; lakh-grouped available limit.',
  ),
  SmsFixture(
    id: 'C02',
    sender: 'VM-ICICIB',
    body:
        'Dear Customer, INR 7,689.62 is debited on ICICI Bank Credit Card XX5533 on 12-Jun-21. Info: Swiggy. Available Limit: INR 62,762.76. Call on 18002662 for dispute or SMS BLOCK 7007 to 8891385501.',
    amountPaise: 768962,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.creditCard,
    issuer: 'ICICI Bank',
    cardLastDigits: '5533',
    last4: '5533',
    merchantContains: 'Swiggy',
    confidenceHint: 'high',
    note: 'O. "is debited on ... Credit Card" — different verb, same event.',
  ),
  SmsFixture(
    id: 'C03',
    sender: 'VK-AXISBK',
    body:
        'INR 2,000.00 spent on Axis Bank Card XX931 at INDIAN OIL SVC STN on 01-08-26 19:22. Avl Lmt INR 48,250.00. SMS BLOCK 931 to 918691000002 if not you.',
    amountPaise: 200000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.creditCard,
    issuer: 'Axis Bank',
    cardLastDigits: '931',
    last4: '931',
    merchantContains: 'INDIAN OIL SVC STN',
    confidenceHint: 'medium',
    note: 'V (Dibba). Mask is only 3 digits — never zero-pad to 4 for matching.',
  ),
  SmsFixture(
    id: 'C04',
    sender: 'VK-KOTAKB',
    body:
        'Rs.560.00 spent on Kotak Card x2210 at BOOKMYSHOW on 03-08-2026. Avl bal Rs.8,904.12. Not you? Call 18602662666.',
    amountPaise: 56000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.creditCard,
    issuer: 'Kotak Mahindra Bank',
    cardLastDigits: '2210',
    last4: '2210',
    merchantContains: 'BOOKMYSHOW',
    confidenceHint: 'medium',
    note:
        'V (Dibba). "Avl bal" on a credit card — issuer override maps it to available limit, not balance.',
  ),
  SmsFixture(
    id: 'C05',
    sender: 'VK-AMEX',
    body:
        "Alert: You've spent INR 204.35 on your AMEX card **91009 at PAYU ZOMATO on 08/03/2020 at 12:17PM IST. Please call 18004190691 if this was not made by you.",
    amountPaise: 20435,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.creditCard,
    issuer: 'American Express',
    cardLastDigits: '91009',
    last4: '1009',
    merchantContains: 'ZOMATO',
    confidenceHint: 'medium',
    note:
        'O. Amex masks 5 digits; aggregator prefix PAYU. last4 = final four of the mask.',
  ),
  SmsFixture(
    id: 'C06',
    sender: 'VM-ICICIB',
    body:
        'INR 888.00 spent on ICICI Bank Card XX4192 on 13-Jul-23 at DAILYDEL SOLUTI. Avl Lmt: INR 8,54,954.76. To dispute,call 18002662/SMS BLOCK 7007 to 8246791893',
    amountPaise: 88800,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.creditCard,
    issuer: 'ICICI Bank',
    cardLastDigits: '4192',
    last4: '4192',
    merchantContains: 'DAILYDEL SOLUTI',
    confidenceHint: 'high',
    note: 'O. Merchant truncated to 13 chars by the template.',
  ),
  SmsFixture(
    id: 'C07',
    sender: 'VK-HDFCBK',
    body:
        'Rs.2,499.00 spent on your HDFC Bank Credit Card ending 1234 at MYNTRA on 12-05-2024. Avl Lmt: Rs.71,501.00.',
    amountPaise: 249900,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.creditCard,
    issuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    merchantContains: 'MYNTRA',
    confidenceHint: 'medium',
    note: 'I.',
  ),
  SmsFixture(
    id: 'C08',
    sender: 'VK-SBICRD',
    body:
        'Rs.1,150.00 spent on your SBI Credit Card ending 4321 at SWIGGY on 12-05-2024. Available Limit: Rs.48,850.00.',
    amountPaise: 115000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.creditCard,
    issuer: 'SBI Card',
    cardLastDigits: '4321',
    last4: '4321',
    merchantContains: 'SWIGGY',
    confidenceHint: 'medium',
    note: 'I. SBI Card is a separate issuer from SBI Bank.',
  ),
  SmsFixture(
    id: 'C09',
    sender: 'VK-IDFCFB',
    body:
        'INR 799.00 spent on your IDFC FIRST Bank Credit Card XX5678 at NETFLIX on 12-05-24. Available limit: INR 59,201.00.',
    amountPaise: 79900,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.creditCard,
    issuer: 'IDFC FIRST Bank',
    cardLastDigits: '5678',
    last4: '5678',
    merchantContains: 'NETFLIX',
    confidenceHint: 'medium',
    note: 'I.',
  ),
  SmsFixture(
    id: 'C10',
    sender: 'VK-RBLBNK',
    body:
        'Rs.1,450.00 spent on your RBL Bank Credit Card XX9090 at Nykaa on 12-05-24. Available limit Rs.28,550.00.',
    amountPaise: 145000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.creditCard,
    issuer: 'RBL Bank',
    cardLastDigits: '9090',
    last4: '9090',
    merchantContains: 'Nykaa',
    confidenceHint: 'medium',
    note: 'I.',
  ),
  SmsFixture(
    id: 'C11',
    sender: 'VK-ONECRD',
    body:
        'Rs.349.00 spent on your OneCard at SWIGGY on 12-05-2024. Available limit Rs.49,651.00. -OneCard',
    amountPaise: 34900,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.creditCard,
    issuer: 'OneCard (CSB Bank)',
    merchantContains: 'SWIGGY',
    confidenceHint: 'low',
    note: 'I. No card mask at all: cannot attribute to a card without user mapping.',
  ),
  SmsFixture(
    id: 'C12',
    sender: 'VK-AUBANK',
    body:
        'Rs.2,350.00 spent on your AU Bank Credit Card XX3344 at Decathlon on 12-05-24. Available limit Rs.67,650.00.',
    amountPaise: 235000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.creditCard,
    issuer: 'AU Small Finance Bank',
    cardLastDigits: '3344',
    last4: '3344',
    merchantContains: 'Decathlon',
    confidenceHint: 'medium',
    note: 'I.',
  ),
  SmsFixture(
    id: 'C13',
    sender: 'VK-INDUSB',
    body:
        'Rs.999.00 spent on your IndusInd Bank Credit Card XX7788 at BOOKMYSHOW on 12-05-24. Available limit Rs.41,001.00.',
    amountPaise: 99900,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.creditCard,
    issuer: 'IndusInd Bank',
    cardLastDigits: '7788',
    last4: '7788',
    merchantContains: 'BOOKMYSHOW',
    confidenceHint: 'medium',
    note: 'I.',
  ),
  SmsFixture(
    id: 'C14',
    sender: 'VM-ICICIB',
    body:
        'USD 12.99 (INR 1,108.24) spent on your ICICI Bank Credit Card XX2815 at OPENAI on 12-May-24. Avl Lmt: INR 4,32,179.80. Forex markup may apply.',
    amountPaise: 110824,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.creditCard,
    issuer: 'ICICI Bank',
    cardLastDigits: '2815',
    last4: '2815',
    merchantContains: 'OPENAI',
    confidenceHint: 'high',
    note: 'I. Three amounts (USD, INR, limit); INR leg wins. Currency pair form.',
  ),

  // ─── D. ATM ────────────────────────────────────────────────────────────────
  SmsFixture(
    id: 'D01',
    sender: 'ATMSBI',
    body:
        'Rs 0368 withdrawn at SBG ATM  S10F200912001  SBH-ACC LTD-MANCHERIAL , MANCHERIAL from A/c xxxx 1710 on 221216.Txn#2699 .Avl bal Rs 76874.33. Free SBG ATM txns if AMB>25000.',
    amountPaise: 36800,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.atm,
    issuer: 'State Bank of India',
    last4: '1710',
    referenceId: '2699',
    merchantContains: 'SBG ATM MANCHERIAL',
    confidenceHint: 'medium',
    note:
        'O. Zero-padded integer amount, ddMMyy date, 4 numeric amounts in one body (txn, txn#, balance, AMB).',
  ),
  SmsFixture(
    id: 'D02',
    sender: 'VK-HDFCBK',
    body:
        'Rs.5,000.00 withdrawn from ATM using your HDFC Bank Debit Card ending 1234 at BANGALORE on 12-05-2024. Avl Bal Rs.40,678.90.',
    amountPaise: 500000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.atm,
    issuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    merchantContains: 'BANGALORE',
    confidenceHint: 'medium',
    note: 'I.',
  ),
  SmsFixture(
    id: 'D03',
    sender: 'VM-ICICIB',
    body:
        'Rs.10,000.00 withdrawn from ATM at MUMBAI using ICICI Bank Debit Card XX742 on 12-05-24. Avl Bal Rs.12,480.00.',
    amountPaise: 1000000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.atm,
    issuer: 'ICICI Bank',
    cardLastDigits: '742',
    last4: '742',
    merchantContains: 'MUMBAI',
    confidenceHint: 'medium',
    note: 'I. "withdrawn from ATM" with card mask (not account mask).',
  ),

  // ─── E. NEFT / IMPS / RTGS / cheque out ────────────────────────────────────
  SmsFixture(
    id: 'E01',
    sender: 'VK-SBIINB',
    body:
        'Your a/c no. XXXXXXXX1710 is debited for Rs.986.93 on 10-11-16 and a/c XXXXXXX133 credited (IMPS Ref no MO17335372).',
    amountPaise: 98693,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.account,
    issuer: 'State Bank of India',
    last4: '1710',
    referenceId: 'MO17335372',
    confidenceHint: 'high',
    note: 'O. Both "debited" and "credited" present; counterparty a/c 133 must not be read as income.',
  ),
  SmsFixture(
    id: 'E02',
    sender: 'VK-HDFCBK',
    body:
        'Rs.5,000.00 debited from your HDFC Bank A/c **4821 on 12-05-24 to RAHUL SHARMA (NEFT Ref HDFC1234567890). Avl Bal Rs.7,340.55.',
    amountPaise: 500000,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.account,
    issuer: 'HDFC Bank',
    last4: '4821',
    referenceId: 'HDFC1234567890',
    merchantContains: 'RAHUL SHARMA',
    confidenceHint: 'medium',
    note: 'I. NEFT out with beneficiary name.',
  ),
  SmsFixture(
    id: 'E03',
    sender: 'VM-ICICIB',
    body:
        'INR 25,000.00 transferred from ICICI Bank A/c XX742 on 12-May-24 via NEFT to RAHUL SHARMA (UTR N123456789012). Avl Bal INR 12,480.00.',
    amountPaise: 2500000,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.account,
    issuer: 'ICICI Bank',
    last4: '742',
    referenceId: 'N123456789012',
    merchantContains: 'RAHUL SHARMA',
    confidenceHint: 'medium',
    note: 'I.',
  ),
  SmsFixture(
    id: 'E04',
    sender: 'VK-SBIINB',
    body:
        'Your A/c XXXXX1234 has been debited by Rs.15,000.00 on 12-05-24 towards cheque no. 456789. Avl Bal Rs.18,250.00.',
    amountPaise: 1500000,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.account,
    issuer: 'State Bank of India',
    last4: '1234',
    referenceId: '456789',
    confidenceHint: 'medium',
    note: 'I. Cheque number looks like a plain number — must not become an amount.',
  ),
  SmsFixture(
    id: 'E05',
    sender: 'VK-AXISBK',
    body:
        'INR 1,00,000.00 transferred from Axis Bank A/c XX5678 on 12-05-24 via RTGS to ACME TRADERS (UTR AXIS9876543210). Avl Bal INR 12,480.00.',
    amountPaise: 10000000,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.account,
    issuer: 'Axis Bank',
    last4: '5678',
    referenceId: 'AXIS9876543210',
    merchantContains: 'ACME TRADERS',
    confidenceHint: 'medium',
    note: 'I. Lakh grouping in a large RTGS amount.',
  ),

  // ─── F. Credits / inflows ──────────────────────────────────────────────────
  SmsFixture(
    id: 'F01',
    sender: 'VK-SBIINB',
    body:
        'Rs 87.38 credited to account XXXXX1710 of SBIN linked to dazzlingarun2@okaxis on 2017-11-02. Info: UPI/P2A/730609020693/imgauti3@okhdfcbank',
    amountPaise: 8738,
    direction: SmsDirection.income,
    instrument: SmsInstrument.upi,
    issuer: 'State Bank of India',
    last4: '1710',
    referenceId: '730609020693',
    merchantContains: 'imgauti3@okhdfcbank',
    confidenceHint: 'high',
    note: 'O. UPI credit; P2A marker; sender VPA is the counterparty.',
  ),
  SmsFixture(
    id: 'F02',
    sender: 'VM-ICICIB',
    body:
        'Dear Customer, your ICICI Bank Account XX963 has been credited with INR 5,567.11 on 17-Sep-21. Info:EBA*MF-AXIS A-109012205*20210917113. The Available Balance is INR 51,388.62.',
    amountPaise: 556711,
    direction: SmsDirection.income,
    instrument: SmsInstrument.account,
    issuer: 'ICICI Bank',
    last4: '963',
    merchantContains: 'MF-AXIS A',
    confidenceHint: 'high',
    note: 'O. Mutual-fund redemption credit; EBA* prefix is a broker/aggregator code.',
  ),
  SmsFixture(
    id: 'F03',
    sender: 'VK-HDFCBK',
    body:
        'Your a/c XX1234 is credited with Rs.1,25,000.00 on 01-05-24 by NEFT from ACME TECHNOLOGIES PVT LTD (UTR HDFC5566778899). Avl Bal Rs.2,10,000.00.',
    amountPaise: 12500000,
    direction: SmsDirection.income,
    instrument: SmsInstrument.account,
    issuer: 'HDFC Bank',
    last4: '1234',
    referenceId: 'HDFC5566778899',
    merchantContains: 'ACME TECHNOLOGIES PVT LTD',
    moneyInKind: 'other',
    confidenceHint: 'high',
    note: 'I. Salary-shaped credit; two lakh-grouped amounts.',
  ),
  SmsFixture(
    id: 'F04',
    sender: 'VK-HDFCBK',
    body:
        'Rs.250.00 credited to your HDFC Bank A/c **4821 on 12-05-24 via IMPS from RAHUL SHARMA. Avl Bal Rs.7,590.55.',
    amountPaise: 25000,
    direction: SmsDirection.income,
    instrument: SmsInstrument.account,
    issuer: 'HDFC Bank',
    last4: '4821',
    merchantContains: 'RAHUL SHARMA',
    confidenceHint: 'medium',
    note: 'I.',
  ),
  SmsFixture(
    id: 'F05',
    sender: 'VM-ICICIB',
    body:
        'Dear Customer, Rs.345.00 credited to your ICICI Bank Account XX963 on 31-Mar-24 towards interest for Jan-Mar. Available Balance is INR 5,912.73.',
    amountPaise: 34500,
    direction: SmsDirection.income,
    instrument: SmsInstrument.account,
    issuer: 'ICICI Bank',
    last4: '963',
    confidenceHint: 'medium',
    note: 'I. Interest credit; no merchant.',
  ),
  SmsFixture(
    id: 'F06',
    sender: 'VK-SBIINB',
    body:
        'Rs.20,000.00 deposited to your A/c XX1234 via CDM on 12-05-24. Avl Bal Rs.38,250.00.',
    amountPaise: 2000000,
    direction: SmsDirection.income,
    instrument: SmsInstrument.account,
    issuer: 'State Bank of India',
    last4: '1234',
    confidenceHint: 'medium',
    note: 'I. Cash deposit machine credit.',
  ),
  SmsFixture(
    id: 'F07',
    sender: 'VK-PAYTM',
    body:
        'Your refund of Rs.96.08 for order 402-1234567-1234567 has been credited to your Amazon Pay balance. Balance is now Rs.102.00.',
    amountPaise: 9608,
    direction: SmsDirection.income,
    instrument: SmsInstrument.wallet,
    issuer: 'Amazon Pay',
    referenceId: '402-1234567-1234567',
    merchantContains: 'Amazon',
    confidenceHint: 'medium',
    note: 'I. Wallet refund; balance is wallet balance (not bank).',
  ),

  // ─── G. Refunds / reversals / cashback ─────────────────────────────────────
  SmsFixture(
    id: 'G01',
    sender: 'VM-ICICIB',
    body:
        'INR 1,299.00 has been credited to your ICICI Bank Credit Card XX2815 on 20-Jul-23 towards refund from AMAZON. Available Limit: INR 4,34,587.04.',
    amountPaise: 129900,
    direction: SmsDirection.income,
    instrument: SmsInstrument.creditCard,
    issuer: 'ICICI Bank',
    cardLastDigits: '2815',
    last4: '2815',
    merchantContains: 'AMAZON',
    confidenceHint: 'high',
    note: 'I. Refund to card must offset spend, not add income to net worth.',
  ),
  SmsFixture(
    id: 'G02',
    sender: 'VK-HDFCBK',
    body:
        'Rs.120.00 has been reversed to your a/c **4821 on 05-08-26 for UPI Ref No 621847362514. Avl Bal Rs.12,460.55. -HDFC Bank',
    amountPaise: 12000,
    direction: SmsDirection.income,
    instrument: SmsInstrument.account,
    issuer: 'HDFC Bank',
    last4: '4821',
    referenceId: '621847362514',
    confidenceHint: 'high',
    note: 'I. Reversal referencing the original UPI ref => link to A01 class of txn.',
  ),
  SmsFixture(
    id: 'G03',
    sender: 'VK-SBIINB',
    body:
        'Credit of Rs.500.00 received in your a/c XX1234 on 12-05-24 against UPI chargeback Ref 412345678901.',
    amountPaise: 50000,
    direction: SmsDirection.income,
    instrument: SmsInstrument.account,
    issuer: 'State Bank of India',
    last4: '1234',
    referenceId: '412345678901',
    confidenceHint: 'medium',
    note: 'I. Chargeback credit.',
  ),
  SmsFixture(
    id: 'G04',
    sender: 'VK-KOTAKB',
    body:
        'Rs.560.00 has been credited to Kotak Card x2210 on 18-05-2026 towards merchant refund. Avl bal Rs.9,464.12.',
    amountPaise: 56000,
    direction: SmsDirection.income,
    instrument: SmsInstrument.creditCard,
    issuer: 'Kotak Mahindra Bank',
    cardLastDigits: '2210',
    last4: '2210',
    merchantContains: 'merchant refund',
    confidenceHint: 'medium',
    note: 'I. Refund to Kotak card where the balance label is "Avl bal".',
  ),
  SmsFixture(
    id: 'G05',
    sender: 'VK-HDFCBK',
    body:
        'Rs.1,500.00 debited on 10-05-24 has been reversed. Avl Bal Rs.9,840.55. -HDFC Bank',
    amountPaise: 150000,
    direction: SmsDirection.income,
    instrument: SmsInstrument.account,
    issuer: 'HDFC Bank',
    confidenceHint: 'low',
    note: 'I. No ref, no mask, no merchantContains: match by amount+time to the original debit.',
  ),
  SmsFixture(
    id: 'G06',
    sender: 'VK-CRED',
    body:
        'Congratulations! You won INR 6 cashback. We will deposit it into your credit card XXX-6314 in the next 7 days.',
    amountPaise: 600,
    direction: SmsDirection.income,
    instrument: SmsInstrument.creditCard,
    issuer: 'unknown (mask 6314)',
    cardLastDigits: '6314',
    last4: '6314',
    confidenceHint: 'low',
    note: 'O. Future tense "will deposit" — must stay pending until a credited message arrives.',
  ),
  SmsFixture(
    id: 'G07',
    sender: 'VK-CRED',
    body:
        "Congratulations! You've Won! You have killed your bill by INR 50 . We will deposit INR 62 into your credit card XX-1101 in the next 7 days.",
    instrument: SmsInstrument.creditCard,
    cardLastDigits: '1101',
    last4: '1101',
    confidenceHint: 'reject',
    note:
        'O. Promotional cashback claim with two marketing amounts ("killed your bill by INR 50", "deposit INR 62"): nothing has moved yet, so no ledger entry.',
  ),
  SmsFixture(
    id: 'G08',
    sender: 'VM-ICICIB',
    body:
        'Dear Customer, INR 1,299.00 has been credited to your ICICI Bank Credit Card XX2815 on 20-Jul-23 towards refund from AMAZON. Available Limit: INR 4,34,587.04.',
    amountPaise: 129900,
    direction: SmsDirection.income,
    instrument: SmsInstrument.creditCard,
    issuer: 'ICICI Bank',
    cardLastDigits: '2815',
    last4: '2815',
    merchantContains: 'AMAZON',
    isDuplicateGroup: 'dup-refund-icici-2815',
    confidenceHint: 'high',
    note: 'Duplicate partner of G01 (same refund, re-sent with "Dear Customer," prefix).',
  ),
  SmsFixture(
    id: 'G09',
    sender: 'VM-ICICIB',
    body:
        'INR 1,299.00 credited to ICICI Bank Credit Card XX2815 on 20-Jul-23 towards AMAZON refund. Available Limit: INR 4,34,587.04.',
    amountPaise: 129900,
    direction: SmsDirection.income,
    instrument: SmsInstrument.creditCard,
    issuer: 'ICICI Bank',
    cardLastDigits: '2815',
    last4: '2815',
    merchantContains: 'AMAZON',
    isDuplicateGroup: 'dup-refund-icici-2815',
    confidenceHint: 'high',
    note: 'Duplicate partner of G01/G08: "has been" dropped, "from" dropped.',
  ),
  SmsFixture(
    id: 'G10',
    sender: 'VK-HDFCBK',
    body:
        'Rs.499.00 reversed to your HDFC Bank Credit Card ending 1234 on 12-05-24 towards annual fee reversal. Avl Lmt: Rs.73,001.00.',
    amountPaise: 49900,
    direction: SmsDirection.income,
    instrument: SmsInstrument.creditCard,
    issuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    confidenceHint: 'medium',
    note: 'I. Fee reversal: a real credit, but not a purchase refund.',
  ),

  // ─── H. Bill payments ──────────────────────────────────────────────────────
  SmsFixture(
    id: 'H01',
    sender: 'VM-ICICIB',
    body:
        'ICICI Bank Acc XX678 debited Rs. 035.43 on 06-Oct-24 InfoBIL*000910062.Avl Bal Rs. 05,547.61.To dispute call 18002662 or SMS BLOCK 696 to 7459648006',
    amountPaise: 3543,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.account,
    issuer: 'ICICI Bank',
    last4: '678',
    referenceId: '000910062',
    merchantContains: 'BIL*000910062',
    confidenceHint: 'high',
    note: 'O. Zero-padded amount "035.43"; BIL* marker = bill payment.',
  ),
  SmsFixture(
    id: 'H02',
    sender: 'VM-ICICIB',
    body:
        'ICICI Bank Acc XX956 debited with INR 0,100.35 on 01-Feb-23. Info:BIL*ONL*00059.Avl Bal is INR 98,829.91. For dispute Call 18002662 or SMS BLOCK 696 to 9545940104',
    amountPaise: 10035,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.account,
    issuer: 'ICICI Bank',
    last4: '956',
    referenceId: 'BIL*ONL*00059',
    merchantContains: 'BIL*ONL',
    confidenceHint: 'high',
    note: 'O. "0,100.35" is the classic zero-padded 100.35 trap.',
  ),
  SmsFixture(
    id: 'H03',
    sender: 'VM-ICICIB',
    body:
        'ICICI Bank Acc XX554 debited Rs. 2,90,812.17 on 29-Sep-23 InfoBIL*NEFT*HS92.Avl Bal Rs. 2,76,179.55.To dispute call 18002662 or SMS BLOCK 696 to 1091719546',
    amountPaise: 29081217,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.account,
    issuer: 'ICICI Bank',
    last4: '554',
    referenceId: 'BIL*NEFT*HS92',
    merchantContains: 'BIL*NEFT',
    confidenceHint: 'high',
    note: 'O. NEFT-funded bill payment; two lakh-grouped amounts.',
  ),
  SmsFixture(
    id: 'H04',
    sender: 'VM-ICICIB',
    body:
        'ICICI Bank Acc XX023 debited Rs. 48,931.04 on 01-Nov-24 InfoBIL*000922185.Avl Bal Rs. 02,491.86.To dispute call 18002662 or SMS BLOCK 696 to 2217320219',
    amountPaise: 4893104,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.account,
    issuer: 'ICICI Bank',
    last4: '023',
    referenceId: '000922185',
    merchantContains: 'BIL*000922185',
    confidenceHint: 'high',
    note: 'O. Lakh-grouped amount; mask with leading zero ("023").',
  ),
  SmsFixture(
    id: 'H05',
    sender: 'VK-CRED',
    body:
        'Payment of INR 90,885 was received for your ICICI Bank credit card 7121-81XX-XXXX-7007 JB 40-KII-6855 and you have earned 51,000 CRED coins. Your order id is YZDPEN6D1895. Payment will be credited to credit card account within the next 1 hour.',
    amountPaise: 9088500,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.creditCard,
    issuer: 'ICICI Bank',
    cardLastDigits: '7007',
    last4: '7007',
    cardKey: 'ICICI Bank|7007',
    referenceId: 'YZDPEN6D1895',
    isDuplicateGroup: 'dup-cardbill-icici-7007',
    confidenceHint: 'high',
    note:
        'O. Full PAN shape 7121-81XX-XXXX-7007 => BIN 712181 + last4 7007. Card bill, not income.',
  ),
  SmsFixture(
    id: 'H06',
    sender: 'VK-CRED',
    body:
        'Payment of INR 8,591 was received for card number XX-7007 HZ 86-WWB-1407 and you have earned 5,436 CRED coins. Payment will reflect in your credit card account in max 48 hours. 3K1L2RVN0K is your order id.',
    amountPaise: 859100,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.creditCard,
    cardLastDigits: '7007',
    last4: '7007',
    referenceId: '3K1L2RVN0K',
    confidenceHint: 'medium',
    note: 'O. Issuer not named — must resolve from the mask or user mapping.',
  ),
  SmsFixture(
    id: 'H07',
    sender: 'VK-HDFCBK',
    body:
        'Rs.5,000.00 debited from your HDFC Bank A/c **4821 on 12-05-24 to BILLDESK (HDFC Bank Credit Card bill). Avl Bal Rs.7,340.55.',
    amountPaise: 500000,
    // The fixture's own note says "not consumption", but it asserted expense.
    // A card-bill payment settles earlier spending, so it is a transfer, and it
    // is attributed to the card (that is what keeps utilisation honest).
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.creditCard,
    issuer: 'HDFC Bank',
    last4: '4821',
    merchantContains: 'BILLDESK',
    isDuplicateGroup: 'dup-cardbill-hdfc-1234',
    confidenceHint: 'medium',
    note: 'I. Family (a): bank debit to a card bill — category cardBill, not consumption.',
  ),
  SmsFixture(
    id: 'H08',
    sender: 'VK-HDFCBK',
    body:
        'Thank you for your payment of Rs.5,000.00 towards your HDFC Bank Credit Card ending 1234. Your available limit is now Rs.73,001.00.',
    amountPaise: 500000,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.creditCard,
    issuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    cardKey: 'HDFC Bank|1234',
    isDuplicateGroup: 'dup-cardbill-hdfc-1234',
    confidenceHint: 'high',
    note: 'I. Family (b): issuer confirmation; same event as H07 — must collapse to one cardPayment.',
  ),
  SmsFixture(
    id: 'H09',
    sender: 'VM-ICICIB',
    body:
        'Dear Customer, your ICICI Bank Credit Card XX2815 bill of INR 12,480.00 has been paid via BBPS from A/c XX742 on 12-May-24. Available Limit: INR 4,33,288.04.',
    amountPaise: 1248000,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.creditCard,
    issuer: 'ICICI Bank',
    cardLastDigits: '2815',
    last4: '2815',
    cardKey: 'ICICI Bank|2815',
    confidenceHint: 'medium',
    note: 'I. Combined issuer+BBPS phrasing; amount is the bill, not a purchase.',
  ),
  SmsFixture(
    id: 'H10',
    sender: 'VK-AXISBK',
    body:
        'INR 1,200.00 paid towards your Axis Bank Credit Card XX931 bill via CHEQ on 12-05-24. Available limit INR 49,450.00.',
    amountPaise: 120000,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.creditCard,
    issuer: 'Axis Bank',
    cardLastDigits: '931',
    last4: '931',
    cardKey: 'Axis Bank|931',
    merchantContains: 'CHEQ',
    confidenceHint: 'medium',
    note: 'I. Third-party bill channel (Cheq) with a 3-digit Axis mask.',
  ),
  SmsFixture(
    id: 'H11',
    sender: 'VK-HDFCBK',
    body:
        'Rs.5,861.00 debited from your HDFC Bank A/c **4821 on 17-06-26 to BILLDESK (HDFC Bank Credit Card bill). Avl Bal Rs.7,340.55.',
    amountPaise: 586100,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.creditCard,
    issuer: 'HDFC Bank',
    last4: '4821',
    merchantContains: 'BILLDESK',
    isDuplicateGroup: 'dup-cardbill-hdfc-5861',
    confidenceHint: 'high',
    note:
        'O. Bank-account leg of a real HDFC card-bill payment. It prints only the '
        'account mask, so it carries no cardKey — and that is exactly why the '
        'issuer leg (H12) must be the survivor.',
  ),
  SmsFixture(
    id: 'H12',
    sender: 'VK-HDFCBK',
    body:
        'DEAR HDFCBANK CARDMEMBER, PAYMENT OF Rs. 5861.00 RECEIVED TOWARDS YOUR CREDIT CARD ENDING WITH 6859 ON 17-6-2026.YOUR AVAILABLE LIMIT IS RS. 17428.26',
    amountPaise: 586100,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.creditCard,
    issuer: 'HDFC Bank',
    cardLastDigits: '6859',
    last4: '6859',
    cardKey: 'HDFC Bank|6859',
    isDuplicateGroup: 'dup-cardbill-hdfc-5861',
    receivedOffsetSeconds: 20 * 60 * 60,
    confidenceHint: 'high',
    note:
        'O. Issuer leg, 20 hours after the bank debit: "credit card ending with '
        'NNNN" must bind a cardKey (it did not before, because `credit card` '
        'pre-empted `ending with`).',
  ),
  SmsFixture(
    id: 'H13',
    sender: 'VK-HDFCBK',
    body:
        'HDFC Bank Cardmember, Online Payment of Rs.7683 vide Ref# 212BX6RM0PJ7003 was credited to your card ending 6859 On 31/JUL/2026_value Date 31/JUL/2026',
    amountPaise: 768300,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.creditCard,
    issuer: 'HDFC Bank',
    cardLastDigits: '6859',
    last4: '6859',
    cardKey: 'HDFC Bank|6859',
    referenceId: '212BX6RM0PJ7003',
    confidenceHint: 'high',
    note: 'O. Second real issuer template ("credited to your card ending").',
  ),

  // ─── I. Autopay / mandate / SI / EMI ───────────────────────────────────────
  SmsFixture(
    id: 'I01',
    sender: 'VM-ICICIB',
    body:
        'Dear Customer, your payment of Rs 610.64 for Youtube, as per Standing Instruction VkiVm1jJlQ, is due by 18/05/2022 and will be debited through your ICICI Bank Credit Card 5444. To cancel this debit or your Standing Instruction, please visit www.icicibank.com-Cards-Credit Cards-Standing Instruction & Recurring Charges-Manage Standing Instructions.',
    amountPaise: 61064,
    instrument: SmsInstrument.creditCard,
    issuer: 'ICICI Bank',
    cardLastDigits: '5444',
    last4: '5444',
    merchantContains: 'Youtube',
    referenceId: 'VkiVm1jJlQ',
    confidenceHint: 'reject',
    note: 'O. Reminder: "is due by ... will be debited" — no money has moved yet.',
  ),
  SmsFixture(
    id: 'I02',
    sender: 'VK-HDFCBK',
    body:
        'Rs.199.00 debited from your HDFC Bank A/c **4821 on 12-05-24 towards Standing Instruction for NETFLIX. Avl Bal Rs.8,340.55.',
    amountPaise: 19900,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.account,
    issuer: 'HDFC Bank',
    last4: '4821',
    merchantContains: 'NETFLIX',
    confidenceHint: 'high',
    note: 'I. SI executed: real spend, subtype recurring.',
  ),
  SmsFixture(
    id: 'I03',
    sender: 'VM-ICICIB',
    body:
        'Rs.299.00 debited from your ICICI Bank A/c XX742 on 12-05-24 via UPI AutoPay to spotify@axisbank. UPI Ref 556677889900. Avl Bal Rs.12,181.00.',
    amountPaise: 29900,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.upi,
    issuer: 'ICICI Bank',
    last4: '742',
    referenceId: '556677889900',
    merchantContains: 'spotify',
    confidenceHint: 'high',
    note: 'I. UPI AutoPay executed.',
  ),
  SmsFixture(
    id: 'I04',
    sender: 'VK-SBIINB',
    body:
        'Rs.15,000.00 debited from your A/c XX1234 on 05-05-24 towards NACH mandate HDFC0000123456 of HDFC LIFE. Avl Bal Rs.18,250.00.',
    amountPaise: 1500000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.account,
    issuer: 'State Bank of India',
    last4: '1234',
    referenceId: 'HDFC0000123456',
    merchantContains: 'HDFC LIFE',
    confidenceHint: 'medium',
    note: 'I. NACH: UMRN is the reference.',
  ),
  SmsFixture(
    id: 'I05',
    sender: 'VK-AXISBK',
    body:
        'INR 23,456.00 debited from your Axis Bank A/c XX5678 on 05-05-24 towards EMI for loan AXISLOAN1234. Avl Bal INR 1,12,480.00.',
    amountPaise: 2345600,
    // An EMI debit is debt service, not consumption: the purchase it settles was
    // already counted when it happened. Booked as a transfer (docs/research/03).
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.account,
    issuer: 'Axis Bank',
    last4: '5678',
    referenceId: 'AXISLOAN1234',
    confidenceHint: 'medium',
    note: 'I. Loan EMI debit, subtype emi.',
  ),
  SmsFixture(
    id: 'I06',
    sender: 'VK-HDFCBK',
    body:
        'Rs.999.00 debited on your HDFC Bank Credit Card XX1234 on 12-05-24 towards GOOGLE subscription e-mandate. Avl Lmt: Rs.72,002.00.',
    amountPaise: 99900,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.creditCard,
    issuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    merchantContains: 'GOOGLE',
    confidenceHint: 'medium',
    note: 'I. Card e-mandate executed (RBI e-mandate framework).',
  ),
  SmsFixture(
    id: 'I07',
    sender: 'VM-ICICIB',
    body:
        'UPI AutoPay mandate of Rs.299.00 created for spotify@axisbank. First debit on 15-05-24. Manage in your UPI app.',
    amountPaise: 29900,
    instrument: SmsInstrument.upi,
    issuer: 'ICICI Bank',
    confidenceHint: 'reject',
    note: 'I. Mandate registration, not a debit.',
  ),

  // ─── J. Card control plane (never transactions) ────────────────────────────
  SmsFixture(
    id: 'J01',
    sender: 'VK-HDFCBK',
    body:
        'Congratulations! Your HDFC Bank Credit Card limit has been enhanced to Rs.1,50,000.00. Enjoy the added flexibility.',
    amountPaise: 15000000,
    instrument: SmsInstrument.creditCard,
    issuer: 'HDFC Bank',
    confidenceHint: 'reject',
    note: 'I. Limit enhancement offer — updates totalLimit metadata only.',
  ),
  SmsFixture(
    id: 'J02',
    sender: 'VM-ICICIB',
    body:
        'Your ICICI Bank Credit Card statement for Apr-2024 is ready. Total Amount Due: Rs.12,480.00, Minimum Amount Due: Rs.620.00, Due Date: 18-05-2024.',
    amountPaise: 1248000,
    instrument: SmsInstrument.creditCard,
    issuer: 'ICICI Bank',
    confidenceHint: 'reject',
    note: 'I. Statement: fills statementTotalDue/minDue/dueDate; creates no transaction.',
  ),
  SmsFixture(
    id: 'J03',
    sender: 'VK-SBICRD',
    body:
        'Your SBI Card payment of Rs.620.00 is due on 18-05-2024. Pay now to avoid late payment charges.',
    amountPaise: 62000,
    instrument: SmsInstrument.creditCard,
    issuer: 'SBI Card',
    confidenceHint: 'reject',
    note: 'I. Minimum-due reminder.',
  ),
  SmsFixture(
    id: 'J04',
    sender: 'VK-KOTAKB',
    body:
        'Convert your transaction of Rs.2,000.00 into EMI at 14% for 6 months. Reply YES to confirm. T&C apply.',
    amountPaise: 200000,
    instrument: SmsInstrument.creditCard,
    issuer: 'Kotak Mahindra Bank',
    confidenceHint: 'reject',
    note: 'I. EMI conversion offer.',
  ),
  SmsFixture(
    id: 'J05',
    sender: 'VK-AXISBK',
    body:
        'Your Axis Bank Credit Card XX931 has available limit INR 48,250.00 and total credit limit INR 50,000.00 as on 12-05-24.',
    amountPaise: 4825000,
    instrument: SmsInstrument.creditCard,
    issuer: 'Axis Bank',
    cardLastDigits: '931',
    last4: '931',
    confidenceHint: 'reject',
    note: 'I. Limit info: updates total/available limit, no transaction.',
  ),

  // ─── K. Hard negatives, OTP, spam, phishing ────────────────────────────────
  SmsFixture(
    id: 'K01',
    sender: 'VM-ICICIB',
    body:
        '208716 is OTP for txn of INR 507.71 at GOOGLEPLAY on ICICI Bank Debit Card XX1566.OTPs are SECRET.DO NOT disclose it to anyone.Bank NEVER asks for OTP.',
    confidenceHint: 'reject',
    note: 'O. OTP with amount + merchant + card mask — the classic false positive.',
  ),
  SmsFixture(
    id: 'K02',
    sender: 'VM-ICICIB',
    body:
        '638072 is OTP for txn of INR 159.64 at AMAZONRECHA on ICICI Bank Credit Card XX3726. OTPs are SECRET. DO NOT disclose it to anyone. Bank NEVER asks for OTP.',
    confidenceHint: 'reject',
    note: 'O. Credit-card txn OTP.',
  ),
  SmsFixture(
    id: 'K03',
    sender: 'VK-SBICRD',
    body:
        'Your SBI Card linking OTP is: 9387. Use within 5 minutes, do not disclose to anyone',
    confidenceHint: 'reject',
    note: 'OTP (synthetic row in cited corpus).',
  ),
  SmsFixture(
    id: 'K04',
    sender: 'VK-HDFCBK',
    body:
        'Login to HDFC Bank Mobile Banking using OTP: 6721. Do not disclose with anyone.',
    confidenceHint: 'reject',
    note: 'Login OTP.',
  ),
  SmsFixture(
    id: 'K05',
    sender: 'VK-UIDAI',
    body:
        'Your Aadhaar (XX3333) e-sign OTP: 617486, valid for 15 minutes. Keep it confidential -UIDAI',
    confidenceHint: 'reject',
    note: 'KYC/e-sign OTP.',
  ),
  SmsFixture(
    id: 'K06',
    sender: 'VK-HDFCBK',
    body:
        'Dear Customer, your HDFC Bank A/c XX4821 balance is Rs.12,340.55 as on 12-05-24. For mini statement SMS MSTMT to 5676766.',
    confidenceHint: 'reject',
    note: 'I. Balance enquiry / mini-statement instruction.',
  ),
  SmsFixture(
    id: 'K07',
    sender: 'VM-ICICIB',
    body:
        'Dear Customer, please complete your re-KYC for your ICICI Bank account to avoid restrictions. Visit your nearest branch or icicibank.com.',
    confidenceHint: 'reject',
    note: 'I. KYC reminder.',
  ),
  SmsFixture(
    id: 'K08',
    sender: 'VK-SBICRD',
    body:
        'Your SBI Card bill of Rs.12,480.00 is due on 18-05-2024. Pay now to avoid late fees.',
    confidenceHint: 'reject',
    note: 'I. Bill due reminder (not the statement, not a payment).',
  ),
  SmsFixture(
    id: 'K09',
    sender: 'AD-LOANOK',
    body:
        'Get a personal loan up to Rs.5,00,000 at 10.5%*. Instant approval. Apply now: http://bit.ly/xyz',
    confidenceHint: 'reject',
    note: 'I. Loan spam from a promotional header.',
  ),
  SmsFixture(
    id: 'K10',
    sender: 'AD-JOBALR',
    body:
        'Work from home and earn Rs.25,000 per month. No experience needed. WhatsApp 98XXXXXX21 now.',
    confidenceHint: 'reject',
    note: 'I. Job/earning spam.',
  ),
  SmsFixture(
    id: 'K11',
    sender: 'AD-INSURE',
    body:
        'Your policy renewal premium of Rs.4,999 is due. Pay before 30-05-24 to keep your cover active.',
    confidenceHint: 'reject',
    note: 'I. Insurance premium reminder (could be a real debit later, but this SMS is not).',
  ),
  SmsFixture(
    id: 'K12',
    sender: '+919876543210',
    body:
        'Dear customer, your account will be blocked today. Update your KYC immediately at http://hdfc-secure-verify.xyz to avoid suspension.',
    confidenceHint: 'reject',
    note: 'I. Phishing from a 10-digit sender with a non-bank domain.',
  ),
  SmsFixture(
    id: 'K13',
    sender: 'VK-AXISBK',
    body:
        'SWIGGY BUSINESS has requested money from you on your Amazon app. On approving the request, INR 2856.15 will be debited from your A/c. To approve, visit http://amzn.in/4YvMefq - Axis Bank',
    amountPaise: 285615,
    instrument: SmsInstrument.account,
    issuer: 'Axis Bank',
    confidenceHint: 'reject',
    note: 'O. Collect request: amount + merchant + "debited" but conditional/future.',
  ),
  SmsFixture(
    id: 'K14',
    sender: 'VK-HDFCBK',
    body:
        'Thank you for the payment of Rs. 443.26 via BharatQR UPI ID gaxxxxxxxxxxxxxxx@okaxis through HDFC Bank SmartHub on 02-05-2022 18:55:04. Receipt: https://hdfcmmp.mintoak.com/HDFC360/redirect/bwnvkf -Mintoak',
    amountPaise: 44326,
    instrument: SmsInstrument.upi,
    confidenceHint: 'reject',
    note:
        'O. Merchant-side receipt (Mintoak): the money moved to the reader, so direction is not expense/income for this user — drop it.',
  ),
  SmsFixture(
    id: 'K15',
    sender: 'VK-PVRCIN',
    body:
        'Please click on the below link to get your FnB transaction receipt https://cutt.ly/hwDTWfzi . Transaction No: 7841623, TotalAmount:260 at POS:PVR VEGA MALL,BENGALURU, Thanks for Choosing PVR Cinemas',
    confidenceHint: 'reject',
    note:
        'O. POS receipt copy with "TotalAmount:" (no currency marker, no bank verb) — must not be parsed even by a lenient amount regex.',
  ),
  SmsFixture(
    id: 'K16',
    sender: 'VM-ICICIB',
    body:
        'Dear Customer, your ICICI Bank FASTag Customer ID 16219891 has been activated on 07/09/2021 16:30:07.You can start using your Tag immediately after you receive it.',
    confidenceHint: 'reject',
    note: 'O. Service activation.',
  ),
  SmsFixture(
    id: 'K17',
    sender: 'VK-SCBANK',
    body:
        "Beware of fraudsters calling to lure you with fictitious job offers and asking for payment in return. Don't click on suspicious links sent by them via email or SMS and do not share the PIN, login ID, password, OTP, debit card/credit card details etc. with anyone. To know more, visit https://nc6.in/dc9Ml4 - StanChart",
    confidenceHint: 'reject',
    note: 'O. Fraud-awareness broadcast: contains "payment", "credit card", an amount-free body.',
  ),
  SmsFixture(
    id: 'K18',
    sender: 'VK-HDFCBK',
    body:
        'Your ATM transaction of Rs.2,000.00 at BANGALORE on 12-05-24 was declined. No amount has been debited.',
    amountPaise: 200000,
    instrument: SmsInstrument.atm,
    issuer: 'HDFC Bank',
    confidenceHint: 'reject',
    note: 'I. Decline with an amount — must not post.',
  ),
  SmsFixture(
    id: 'K19',
    sender: 'VK-HDFCBN',
    body:
        'Dear Customer, HDFC Bank is now compliant with RBI e-mandate framework w.e.f. Oct 1. Register using HDFC Bank Credit card for recurring payment/subscription on merchant website/app. For the list of compliant merchants, click: hdfcbk.io/k/AnBDH7ec2in T&C apply',
    confidenceHint: 'reject',
    note: 'O. Product/compliance notice mentioning "Credit card" and "payment".',
  ),
  SmsFixture(
    id: 'K20',
    sender: 'JMBLUDRT',
    body:
        'Your Blue Dart Secure Delivery Code is 969384 and its valid for next 30 minutes. Enter this Delivery Code on the device to receive the package.',
    confidenceHint: 'reject',
    note: 'O. Delivery code that looks like an OTP.',
  ),

  // ─── L. Duplicate groups ───────────────────────────────────────────────────
  SmsFixture(
    id: 'L01',
    sender: 'VK-HDFCBK',
    body:
        'Rs.500.00 debited from a/c **4821 on 12-05-24 to VPA amazonpay@apl (UPI Ref No 778899001122). Not you? Call 18002586161.',
    amountPaise: 50000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.upi,
    issuer: 'HDFC Bank',
    last4: '4821',
    referenceId: '778899001122',
    merchantContains: 'amazonpay',
    isDuplicateGroup: 'dup-upi-cc-500',
    confidenceHint: 'high',
    note: 'Bank-side alert for a UPI payment funded by an HDFC credit card.',
  ),
  SmsFixture(
    id: 'L02',
    sender: 'VK-HDFCBK',
    body:
        'Rs.500.00 spent on your HDFC Bank Credit Card ending 1234 at AMAZON PAY on 12-05-24. Avl Lmt: Rs.72,501.00.',
    amountPaise: 50000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.creditCard,
    issuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    merchantContains: 'AMAZON PAY',
    isDuplicateGroup: 'dup-upi-cc-500',
    confidenceHint: 'high',
    note:
        'Issuer-side alert, 40s later: same amount, different instrument framing — must collapse to one row.',
  ),
  SmsFixture(
    id: 'L03',
    sender: 'VK-PHONPE',
    body: 'Rs 150 paid to SREE KRISHNA STORES via PhonePe. Transaction ID 4455667788.',
    amountPaise: 15000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.wallet,
    issuer: 'PhonePe (PSP)',
    referenceId: '4455667788',
    merchantContains: 'SREE KRISHNA STORES',
    isDuplicateGroup: 'dup-wallet-upi-150',
    confidenceHint: 'medium',
    note: 'Wallet-side alert.',
  ),
  SmsFixture(
    id: 'L04',
    sender: 'VK-HDFCBK',
    body:
        'Rs 150.00 debited from a/c **4821 on 12-05-24 to VPA sreekrishna@ybl (UPI Ref No 445566778899). Not you? Call 18002586161.',
    amountPaise: 15000,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.upi,
    issuer: 'HDFC Bank',
    last4: '4821',
    referenceId: '445566778899',
    merchantContains: 'sreekrishna',
    isDuplicateGroup: 'dup-wallet-upi-150',
    confidenceHint: 'high',
    note: 'Bank-side alert for the same PhonePe payment: references differ, amount+time+merchant match.',
  ),
  SmsFixture(
    id: 'L05',
    sender: 'VK-CRED',
    body:
        'Payment of INR 7,500 was received for your HDFC Bank credit card XX-1234 and you have earned 750 CRED coins. Your order id is CRED77889900. Payment will reflect in your credit card account in max 48 hours.',
    amountPaise: 750000,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.creditCard,
    issuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    cardKey: 'HDFC Bank|1234',
    referenceId: 'CRED77889900',
    isDuplicateGroup: 'dup-cardbill-hdfc-7500',
    confidenceHint: 'high',
    note: 'Third-party (CRED) card payment confirmation.',
  ),
  SmsFixture(
    id: 'L06',
    sender: 'VK-HDFCBK',
    body:
        'Thank you for your payment of Rs.7,500.00 towards your HDFC Bank Credit Card ending 1234. Your available limit is now Rs.80,001.00.',
    amountPaise: 750000,
    direction: SmsDirection.transfer,
    instrument: SmsInstrument.creditCard,
    issuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    cardKey: 'HDFC Bank|1234',
    isDuplicateGroup: 'dup-cardbill-hdfc-7500',
    confidenceHint: 'high',
    note: 'Issuer confirmation of the same CRED payment — canonical for available-limit math.',
  ),
];

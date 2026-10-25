# Parser gap report — Indian transactional SMS corpus

**Date:** 2026-10-25 (IST)
**Scope:** `test/sms_corpus_test.dart`, `test/spam_corpus_test.dart`, fixtures from
`docs/research/01-sms-corpus.md` §10 and `docs/research/02-spam-and-phishing.md` Appendix A.
**Code under test:** working tree of `E:\flutter_projects\finnance-app` (HEAD `43ae964`).
The parser files (`lib/services/sms/*`, `lib/engine/*`, `lib/domain/*`) are untracked and were last
written at 20:06 IST, immediately before this run. `lib/` was **not** modified by this work.

Repeat with:

```powershell
flutter test test/sms_corpus_test.dart --reporter expanded
flutter test test/spam_corpus_test.dart --reporter expanded
flutter test test/engine_test.dart
flutter test test/widget_smoke_test.dart
flutter analyze test
```

A fixture is a **single check**: every expected field must match (`amountPaise`, `kind`,
`instrument`, `last4`, `issuer`, `referenceId`, merchant token, and the classifier class). A check
fails if *any* field differs, so one bad regex can fail a row that gets every other field right.
The gap tables list **all** fields that differed for each failing fixture.

---

## 0. TL;DR

| Suite | Passed / checks | Rate |
|---|---:|---:|
| Transaction corpus (103 fixtures + 6 dedupe checks) | **47 / 109** | **43.1%** |
| Classifier corpus (77 fixtures) | **52 / 77** | **67.5%** |
| Combined fixture/classifier checks (103 + 77 fixtures) | 98 / 180 | 54.4% |
| Analytics engine (`engine_test.dart`, 21 tests) | 20 / 21 | 95.2% |
| Widget smoke (`widget_smoke_test.dart`, 2 tests) | 0 / 2 | 0% (both fail only on layout overflows) |

The parser is **not ready to be the ledger**. Three classes of defect matter most:

1. **Card/account masks are parsed for a template that does not exist** (21 fixtures). Real masks are
   3-digit (`XX742`), 4-digit with one `x` (`x2210`), 5-digit Amex (`**91009`), hyphenated
   (`XX-7007`) or multi-segment (`7121-81XX-XXXX-7007`). The current regex only accepts
   `xx`/`XXXX`/`****` + exactly four digits with whitespace.
2. **The amount scorer cancels a money verb with a mask penalty** (4 checks). In
   `A/c XX1234 debited Rs 2,000`, the masked-account penalty (−6, applied to the whole 60-char
   window) nearly cancels the debit bonus (+6), so `hasAmount` is false: the message is classified
   `unknown` and **the transaction is dropped** (F02, F03 and corpus `tx-02`, `tx-11`). This is the
   worst failure mode in the app.
3. **Direction is modelled too narrowly.** Third-party NEFT/IMPS/RTGS transfers and numeric-VPA P2P
   payments are booked as spending (5 fixtures); every mandate/standing instruction/EMI is booked as
   a *transfer* (6 fixtures); and accounts are debited for messages where **no money moved** (bill
   due, declined ATM, future SI, EMI cross-sell — 5 fixtures).

The classifier side is dominated by **informational recall** (12/13 informational fixtures fail,
mostly `unknown`) and **phishing false negatives** (6/22 fraud fixtures land in `transaction`).
Four OTP fixtures are flagged `phishing` because a *warning* — "Do NOT share this OTP" — matches the
credential-ask rule.

---

## 1. Pass rate by bucket

### Transaction corpus

| Bucket | Fixtures/checks | Passed | Rate | Failing IDs |
|---|---:|---:|---:|---|
| UPI | 9 | 2 | 22.2% | A02 A03 A04 A05 A06 A08 A09 |
| Debit card | 7 | 7 | **100%** | — |
| Credit card | 14 | 8 | 57.1% | C01 C03 C04 C05 C08 C12 |
| ATM | 3 | 1 | 33.3% | D01 D03 |
| NEFT/IMPS | 5 | 0 | **0%** | E01 E02 E03 E04 E05 |
| Credits | 7 | 0 | **0%** | F01–F07 |
| Refunds | 10 | 2 | 20.0% | G01–G06 G08 G09 |
| Bill payments | 10 | 2 | 20.0% | H01–H07 H10 |
| Autopay | 7 | 0 | **0%** | I01–I07 |
| Negatives | 25 (J+K) | 20 | 80.0% | J03 J04 K08 K14 K18 |
| Duplicate pairs | 6 fixtures + 6 dedupe checks | 5 | 41.7% | L03 L05 + 5 dedupe groups |
| **Overall** | **109** | **47** | **43.1%** | 57 fixtures + 5 dedupe groups |

### Classifier corpus

| Research class | Fixtures | Passed | Rate | Failing IDs |
|---|---:|---:|---:|---|
| transaction | 19 | 17 | 89.5% | tx-02 tx-11 |
| informational | 13 | 1 | **7.7%** | info-01…07, info-10…14 |
| otp | 9 | 5 | 55.6% | info-09 otp-01 otp-03 otp-06 |
| promo | 14 | 13 | 92.9% | promo-12 |
| fraud | 22 | 16 | 72.7% | fraud-02 05 06 10 13 15 |
| **Overall** | **77** | **52** | **67.5%** | 25 |

---

## 2. Assertion policy (how to read the tables)

- **Direction → kind.** `expense → spend`, `transfer → transfer`, `income → income`. ATM rows carry
  `direction: expense` in the research doc but are asserted as `TxnKind.cash`, because the app models
  an ATM withdrawal as cash movement, not consumption.
- **Instrument.** `account → bankAccount`; the other four names map 1:1. The research taxonomy has no
  `emi` member, so I05 (`instrument: account`) is asserted as `bankAccount` even though the parser
  deliberately returns `Instrument.emi`. This is treated as a **taxonomy difference**, not a parser
  bug (see §5).
- **Issuer.** The research doc writes canonical names (`Kotak Mahindra Bank`, `OneCard (CSB Bank)`)
  while the parser returns shorter labels (`Kotak`, `OneCard`). The test accepts containment in
  either direction, so only a *different bank* fails. Two rows store a note instead of an issuer
  (`unknown (mask 6314)`), and are not asserted (see §5).
- **Merchant.** `merchantContains` is a case-insensitive substring of `Txn.merchant`; the parser may
  return a longer or messier string as long as it contains the expected token.
- **Classifier taxonomy.** The research taxonomy has `otp` and `fraud`; the shipped `SmsClass` has
  neither, so the suite maps `otp → informational` and `fraud → phishing`. This is the *only*
  relaxation, and it is a product-taxonomy gap: the app cannot distinguish a login OTP from a
  balance alert, or a fraud attempt from other phishing, in its own type system.
- **Negatives.** A `reject` fixture passes only when the classifier does **not** say `transaction`
  *and* extractor+classifier together produce no ledger row. The extractor is allowed to return a
  `Txn` for a message the classifier rejects; the ledger gate is what matters.

---

## 3. Root causes — transaction parser (RC-01 … RC-15)

### RC-01 — Amount scorer: masked-account penalty cancels the money verb

**Evidence.** `AmountFinder._score` subtracts 6 when `xx|x{2,}|\*{2,}|ending|a/c|ac no` appears
*anywhere* in the 60 characters before a candidate. In the standard Indian template
`A/c XX1234 debited Rs. 2,000.00`, the same window contains both the mask and the amount, so
`+2 (currency) +6 (debited) −6 (mask) = 2` → `hasAmount` is false (`score >= 3` required).
The classifier then emits no `amount` signal and falls through to `unknown`; the extractor also
requires `score >= 2` but in F02/F03 the preposition is `with`, so the score drops to 1 and
`extract()` returns `null`.

Verified signals: `F02 [known_sender:3, credit_verb:3]`, `F03 [known_sender:3, credit_verb:3]` —
no `amount`; `tx-02 [known_sender:3, dlt_transactional:1, debit_verb:4]` — no `amount`.

| ID | Sender | Body excerpt | Expected → actual | Rules |
|---|---|---|---|---|
| F02 | VM-ICICIB | "your ICICI Bank Account XX963 has been credited with INR 5,567.11 …" | transaction + Txn 556711 → `unknown` + `null` | RC-01, RC-02, RC-08 |
| F03 | VK-HDFCBK | "Your a/c XX1234 is credited with Rs.1,25,000.00 …" | transaction + Txn 12500000 → `unknown` + `null` | RC-01, RC-02, RC-08 |

**Suggested fix.**

```dart
// amount_finder.dart — penalise a mask only when it is *adjacent* to the number,
// and never when a money verb sits between the mask and the amount.
final mask = RegExp(r'(?:xx|x{2,}|\*{2,}|ending|a/c|acc)\s*$');
final verb = RegExp(r'\b(?:debited|credited|spent|paid|withdrawn|received|refunded)\b');
final beforeMask = before.substring(0, before.length - (mask.firstMatch(before)?.group(0)?.length ?? 0));
score -= (mask.hasMatch(before) && !verb.hasMatch(beforeMask)) ? 6 : 0;
// also accept "credited with" / "debited with" as an amount anchor:
if (RegExp(r'\b(?:of|for|by|with|amount|amt)\s*$').hasMatch(before)) score += 2;
```

This single fix unblocks F02/F03 and classifier `tx-02`/`tx-11`.

---

### RC-02 — Card/account mask extraction only understands one template

**Evidence.** `_last4` is:

```dart
r'(?:(?:xx|x{2,}|\*{2,}|ending(?:\s*(?:with|in))?|ending no\.?)\s*(\d{4})\b)|…'
```

It requires **exactly four digits** and `xx`/`XXXX`/`****` with only whitespace before the digits.
It therefore misses: 3-digit masks (`XX742`, `XX931`, `XX023`), single-`x` masks (`x2210`), Amex
five-digit masks (`**91009`), hyphenated masks (`XX-7007`, `XX-1234`), and multi-segment masks
(`7121-81XX-XXXX-7007`, where it takes the **first** segment `7121` instead of the final `7007`).
21 fixtures fail on this alone or in combination.

| ID | Sender | Body excerpt | Expected → actual | Rules |
|---|---|---|---|---|
| A02 | VM-ICICIB | "Rs 320.00 debited from A/c XX742 …" | last4 742 → `null` | RC-02, RC-09, RC-08 |
| A03 | VM-ICICIB | "Acct XX240 debited for Rs 459.00 …" | last4 240 → `null` | RC-02 |
| A08 | VK-HDFCBK | "Sent Rs.150.00 from HDFC Bank A/c *4821 …" | last4 4821 → `null` | RC-02 |
| C03 | VK-AXISBK | "INR 2,000.00 spent on Axis Bank Card XX931 …" | last4 931 → `null` | RC-02 |
| C05 | VK-AMEX | "INR 204.35 on your AMEX card **91009 at PAYU ZOMATO …" | last4 1009 → `null` | RC-02 |
| D03 | VM-ICICIB | "… using ICICI Bank Debit Card XX742 …" | last4 742 → `null` | RC-02 |
| F05 | VM-ICICIB | "… credited to your ICICI Bank Account XX963 …" | last4 963 → `null` | RC-02 |
| H05 | VK-CRED | "… credit card 7121-81XX-XXXX-7007 …" | last4 7007 → **7121** | RC-02, RC-09 |
| H06 | VK-CRED | "… card number XX-7007 …" | last4 7007 → `null` | RC-02, RC-09 |
| H10 | VK-AXISBK | "… Credit Card XX931 bill via CHEQ …" | last4 931 → `null`; merchant CHEQ → `null` | RC-02, RC-08 |
| L05 | VK-CRED | "… credit card XX-1234 … order id is CRED77889900" | last4 1234 → `null`; ref → `null` | RC-02, RC-09 |

Also affected (mask appears in their row under another primary cause): A04, C04, E03, G04, G06,
H01, H02, H03, H04, I03.

**Suggested fix.**

```dart
static final RegExp _mask = RegExp(
  r'(?:ending(?:\s*(?:with|in|no\.?))?|a/?c|acc(?:ount)?|card(?:\s*no\.?)?)'
  r'[\s:*#-]*([x*]{1,4}[\s-]*\d{3,5})',
  caseSensitive: false,
);
static final RegExp _digits = RegExp(r'[x*]{1,4}[\s-]*(\d{3,5})', caseSensitive: false);

String? _last4(String body) {
  final all = _digits.allMatches(body).toList();
  if (all.isEmpty) return null;
  final raw = all.last.group(1)!;          // last segment wins: …-XXXX-7007
  final digits = raw.length == 5 ? raw.substring(1) : raw; // Amex: **91009 → 1009
  return digits.length >= 3 ? digits : null;
}
```

Store the printed mask (`cardLastDigits`) separately from the 3–4-digit `last4` used for matching.

---

### RC-03 — No third-party transfer / numeric-VPA P2P direction

**Evidence.** `_transferReason` only knows `creditCardBill`, `selfTransfer`, `walletLoad`,
`investment`, `loanRepayment`. An outbound NEFT/RTGS/cheque to a named beneficiary, or a UPI payment
to an all-digit VPA, therefore remains `TxnKind.spend`.

`A09` (numeric VPA `9876543210@ybl`) and `E02`–`E05` (NEFT/RTGS/cheque to `RAHUL SHARMA` /
`ACME TRADERS`) are expected to be transfers.

| ID | Sender | Body excerpt | Expected → actual | Rules |
|---|---|---|---|---|
| A09 | VK-KOTAKB | "Sent Rs.899.00 … to 9876543210@ybl …" | transfer → **spend** | RC-03 |
| E02 | VK-HDFCBK | "Rs.5,000.00 debited … to RAHUL SHARMA (NEFT Ref …)" | transfer → **spend** | RC-03 |
| E03 | VM-ICICIB | "INR 25,000.00 transferred … via NEFT to RAHUL SHARMA …" | transfer → **spend**; last4 742 → `null` | RC-03, RC-02 |
| E04 | VK-SBIINB | "… debited by Rs.15,000.00 … towards cheque no. 456789" | transfer → **spend**; ref 456789 → `null` | RC-03, RC-09 |
| E05 | VK-AXISBK | "INR 1,00,000.00 transferred … via RTGS to ACME TRADERS …" | transfer → **spend** | RC-03 |

**Suggested fix.**

```dart
// transaction_extractor.dart
static final RegExp _thirdPartyTransfer = RegExp(
  r'\b(?:neft|imps|rtgs|cheque|chq)\b|\bto\s+(?:vpa\s+)?[a-z0-9._-]{2,}@',
  caseSensitive: false,
);
// numeric VPA local part = person-to-person, not a merchant
static final RegExp _numericVpa = RegExp(r'\b(\d{6,})@[a-z]');

TransferReason _transferReason(String lower) {
  if (_creditCardBill.hasMatch(lower)) return TransferReason.creditCardBill;
  if (_selfTransfer.hasMatch(lower)) return TransferReason.selfTransfer;
  if (_thirdPartyTransfer.hasMatch(lower) || _numericVpa.hasMatch(lower)) {
    return TransferReason.selfTransfer; // or a new TransferReason.p2p
  }
  …
}
```

**Related (A04):** `_selfTransfer` now also matches `\bdebited\b.{0,80}\bcredited\b`. In A04 the
second verb is the *counterparty's* credit (`…@yesbankltd credited`), so the message becomes a
self-transfer when it is a spend. Restrict that rule to the user's own two accounts
(`from your … to your …`, `own a/c`), not any debit followed by any credit.

| ID | Sender | Body excerpt | Expected → actual | Rules |
|---|---|---|---|---|
| A04 | VM-ICICIB | "Acct XXX702 debited with INR42.97 … and bharatpe09899148115@yesbankltd credited …" | spend → **transfer**; phishing; last4 702→`null`; issuer CRED; ref `null`; merchant `Dec` | RC-03, RC-06, RC-02, RC-07, RC-09, RC-08 |

---

### RC-04 — Every mandate / standing instruction / EMI is classed as a transfer

**Evidence.** `_loanRepayment` matches `emi|loan|nach|mandate|autopay|auto pay|standing instruction|si`,
so subscriptions (Netflix, Spotify, Google) and insurance (HDFC Life) are treated as loan repayments
and removed from spending. The research corpus treats them as `expense`.

| ID | Sender | Body excerpt | Expected → actual | Rules |
|---|---|---|---|---|
| I02 | VK-HDFCBK | "… towards Standing Instruction for NETFLIX" | spend → **transfer** (reason `loanRepayment`) | RC-04 |
| I03 | VM-ICICIB | "… via UPI AutoPay to spotify@axisbank" | spend → **transfer**; last4 742→`null`; ref AUTOPAY | RC-04, RC-02, RC-09 |
| I04 | VK-SBIINB | "… towards NACH mandate HDFC0000123456 of HDFC LIFE" | spend → **transfer**; issuer HDFC; ref `null`; merchant `null` | RC-04, RC-07, RC-09, RC-08 |
| I05 | VK-AXISBK | "… towards EMI for loan AXISLOAN1234" | spend → **transfer**; `bankAccount` → **`emi`**; ref `null` | RC-04 (+ taxonomy) |
| I06 | VK-HDFCBK | "… towards GOOGLE subscription e-mandate" | spend → **transfer** | RC-04 |
| I07 | VM-ICICIB | "UPI AutoPay mandate of Rs.299.00 created … First debit on 15-05-24." | no transaction → **transaction** | RC-04, RC-05 |

**Suggested fix.**

```dart
static final RegExp _loanRepayment = RegExp(
  r'\b(?:emi\s+(?:for|of)\s+(?:a\s+)?loan|loan\s+(?:repayment|installment|instalment)|'
  r'repayment\s+of\s+loan|credit\s+card\s+(?:bill|payment|dues?))\b',
  caseSensitive: false,
);
// mandate/autopay/SI is *not* a transfer reason. A completed subscription charge
// is spend; a set-up confirmation is informational (RC-05).
```

---

### RC-05 — "Money has not moved yet" is not a veto

**Evidence.** `genuineTransaction = tx >= 6 && hasAmount && trust != suspicious` ignores bill
reminders, future debits and declines. A due reminder contains `payment of` (debit verb) + amount, so
`tx = 3 + 4 + 2 = 9` and it becomes a transaction. `K18` even says *"No amount has been debited"*.

| ID | Sender | Body excerpt | Expected → actual | Rules |
|---|---|---|---|---|
| I01 | VM-ICICIB | "… payment of Rs 610.64 … is due by 18/05/2022 and will be debited …" | no transaction → **transaction** (Txn 61064) | RC-05 |
| J03 | VK-SBICRD | "Your SBI Card payment of Rs.620.00 is due on 18-05-2024 …" | no transaction → **transaction** (Txn 62000) | RC-05 |
| J04 | VK-KOTAKB | "Convert your transaction of Rs.2,000.00 into EMI … Reply YES to confirm." | no transaction → **transaction** (Txn 200000) | RC-05 |
| K08 | VK-SBICRD | "Your SBI Card bill of Rs.12,480.00 is due on … Pay now …" | no transaction → **transaction** (Txn 1248000) | RC-05 |
| K18 | VK-HDFCBK | "Your ATM transaction of Rs.2,000.00 at BANGALORE … was declined. No amount has been debited." | no transaction → **transaction** (Txn 200000) | RC-05 |

**Suggested fix.** Add a hard "not moved" predicate *before* the cascade, and make the extractor
honour it (return `null`):

```dart
static final RegExp _notYetMoved = RegExp(
  r'\b(?:is due|are due|due on|due by|minimum due|total due|amount due|pay now|avoid late|'
  r'will be (?:debited|charged)|scheduled (?:for|on)|upcoming|was declined|has been declined|'
  r'no amount has been debited|not been debited|has failed|failed to|'
  r'requested money|has requested|payment request|convert your transaction|'
  r'reply yes to confirm)\b',
  caseSensitive: false,
);
final moved = RegExp(r'\b(?:has been|was) (?:credited|paid|debited)\b').hasMatch(lower);
final notYetMoved = _notYetMoved.hasMatch(lower) && !moved;
if (notYetMoved) cls = SmsClass.informational; // after the phishing check
```

The same predicate should add an `info` signal so `unknown` becomes `informational` even when
phishing scores are absent.

---

### RC-06 — `SMS BLOCK 696` opt-out footer triggers the KYC "block" lure

**Evidence.** `_kycLure` contains `block(?:ed)?`, which matches the literal `SMS BLOCK 696` that
ICICI appends to **every** transactional alert. That gives `phish = 4`; because the amount signal
was suppressed by RC-01, `genuineTransaction` is false, so the message is classified **phishing**.
Verified for H01: signals `[known_sender:3, debit_verb:4, kyc_lure:-4]`.

| ID | Sender | Body excerpt | Expected → actual | Rules |
|---|---|---|---|---|
| H01 | VM-ICICIB | "ICICI Bank Acc XX678 debited Rs. 035.43 … SMS BLOCK 696 to 7459648006" | transaction → **phishing**; last4/ref/instrument/merchant wrong | RC-06, RC-02, RC-09, RC-10, RC-08 |
| H02 | VM-ICICIB | "… debited with INR 0,100.35 … SMS BLOCK 696 …" | transaction → **phishing**; same fields | RC-06, RC-02, RC-09, RC-10, RC-08 |
| H03 | VM-ICICIB | "… debited Rs. 2,90,812.17 … SMS BLOCK 696 …" | transaction → **phishing**; last4/ref/merchant wrong | RC-06, RC-02, RC-09, RC-08 |
| H04 | VM-ICICIB | "… debited Rs. 48,931.04 … SMS BLOCK 696 …" | transaction → **phishing**; same fields | RC-06, RC-02, RC-09, RC-10, RC-08 |
| A04 | VM-ICICIB | "… SMS BLOCK 696 to 5900232221" | also phishing via `kyc_lure` | RC-06 (+ RC-03) |

**Suggested fix.** Stripe the DLT footer before signal matching and require account context for a
block lure:

```dart
lower = lower.replaceAll(RegExp(r'\bsms\s*block\s*\d+\s*to\s*\d+\b'), ' ');
lower = lower.replaceAll(RegExp(r'\bblock\s+\d{3,4}\s+to\s+\d{6,}\b'), ' ');

static final RegExp _kycLure = RegExp(
  r'\b(?:kyc|re-?kyc|pan\s*card|aadhaar|'
  r'(?:account|card|net\s*banking|sim)\b.{0,30}\b(?:block(?:ed)?|suspend(?:ed)?|frozen|deactivat(?:e|ed))|'
  r'verify your (?:account|identity|kyc)|complete your kyc|update your (?:kyc|details|pan))\b',
  caseSensitive: false,
);
```

---

### RC-07 — Issuer resolution: substring matching + wrong precedence

**Evidence.** `_issuer` iterates a hand-written map with `lower.contains(key)`. Consequences:
`'CRED'` matches the word **"credited"** (A04, E01, F07, G03); `'HDFC'` matches a VPA
`@okhdfcbank` (F01) and a beneficiary name `HDFC LIFE` (I04), overriding the sender's bank;
`'SBI'` wins over `'SBI CARD'` when the body says "SBI Credit Card" (C08); the AU label is
`AU Bank` vs the registry's `AU Small Finance Bank` (C12).

| ID | Sender | Expected issuer → actual | Rules |
|---|---|---|---|
| E01 | VK-SBIINB | `State Bank of India` → **CRED** | RC-07 |
| F01 | VK-SBIINB | `State Bank of India` → **HDFC Bank** | RC-07, RC-08, RC-09 |
| F07 | VK-PAYTM | `Amazon Pay` → **CRED** | RC-07, RC-08, RC-09 |
| G03 | VK-SBIINB | `State Bank of India` → **CRED** | RC-07, RC-09, RC-10 |
| I04 | VK-SBIINB | `State Bank of India` → **HDFC Bank** | RC-07 (+ RC-04) |
| C08 | VK-SBICRD | `SBI Card` → **State Bank of India** | RC-07 |
| C12 | VK-AUBANK | `AU Small Finance Bank` → **AU Bank** | RC-07 |

**Suggested fix.** Sender entity wins for bank/card/wallet senders; body parsing is only a fallback,
and it must be word-bounded:

```dart
String? _issuer(String lower, SenderId sender) {
  // The DLT header is the strongest identity signal we have.
  if (sender.entity != null) return sender.entity;
  const issuers = {
    'hdfc': 'HDFC Bank',
    'icici': 'ICICI Bank',
    'sbi\\s*credit\\s*card': 'SBI Card',
    '\\bsbi\\b': 'State Bank of India',
    '\\baxis\\b': 'Axis Bank',
    'kotak': 'Kotak Mahindra Bank',
    'idfc': 'IDFC FIRST Bank',
    'amex|american express': 'American Express',
    'au\\s*(?:small finance\\s*)?bank': 'AU Small Finance Bank',
    '\\bcred\\b': 'CRED',           // never plain "cred"
    …
  };
  for (final e in issuers.entries) {
    if (RegExp('\\b(?:${e.key})\\b').hasMatch(lower)) return e.value;
  }
  return null;
}
```

Using `SenderRegistry.entities[...].name` also fixes C08/C12/I04 without a second map.

---

### RC-08 — Merchant extraction anchors on the wrong word

**Evidence.** `_merchant` tries `at|to|towards`, then `for`, then `info`, then a VPA fallback, then
`[-|/] token`. Failure modes:
- generic nouns win: `for dispute` → **`dispute`** (A02); `towards refund from AMAZON` → the dash
  fallback matches **`Jul`** in `20-Jul-23` (G01/G08/G09);
- aggregator prefixes survive: `at IND*Amazon.in` → **`IND`** (C01);
- the first VPA is the account holder's, not the counterparty: F01 → **`Dazzlingarun2`**;
- credits have no pattern: `from RAHUL SHARMA` (F04), `for order … Amazon Pay` (F07),
  `towards merchant refund` (G04), `via CHEQ` (H10), `of HDFC LIFE` (I04) → all `null`.

| ID | Sender | Expected merchant → actual | Rules |
|---|---|---|---|
| C01 | VM-ICICIB | `Amazon.in` → **IND** | RC-08 |
| G01 | VM-ICICIB | `AMAZON` → **Jul** | RC-08 |
| G08 | VM-ICICIB | `AMAZON` → **Jul** | RC-08 |
| G09 | VM-ICICIB | `AMAZON` → **Jul** | RC-08 |
| F04 | VK-HDFCBK | `RAHUL SHARMA` → `null` | RC-08 |
| H10 | VK-AXISBK | `CHEQ` → `null` | RC-08 (+RC-02) |
| G04 | VK-KOTAKB | `merchant refund` → `null` | RC-08 (+RC-02, RC-10) |
| F07 | VK-PAYTM | `Amazon` → `null` | RC-08 (+RC-07, RC-09) |
| F01 | VK-SBIINB | `imgauti3@okhdfcbank` → **Dazzlingarun2** | RC-08 (+RC-07, RC-09) |
| I04 | VK-SBIINB | `HDFC LIFE` → `null` | RC-08 (+RC-04, RC-07, RC-09) |
| A02 | VM-ICICIB | `swiggy` → **dispute** | RC-08 (+RC-02, RC-09) |

**Suggested fix.**

```dart
// 1. strip the aggregator/biller prefix before cleaning
candidate = candidate.replaceFirst(
  RegExp(r'^(?:ind|payu|mps|raz|bill|cheq|bharatqr)\s*[*:]?\s*', caseSensitive: false), '');

// 2. reject generic nouns and date fragments
const stop = {'dispute','refund','payment','late fees','charges','confirm','cancel',
              'available','limit','info','visit','call','jan','feb','mar','apr','may',
              'jun','jul','aug','sep','oct','nov','dec'};

// 3. more prepositions: "from <name>" (credit), "via <merchant>", "of <biller>"
static final _from = RegExp(r'\bfrom\s+([A-Za-z][A-Za-z0-9 .&_-]{2,60})');
static final _via  = RegExp(r'\bvia\s+([A-Za-z][A-Za-z0-9 .&_-]{2,40})');

// 4. the counterparty VPA is the LAST vpa in an "Info: UPI/P2A/<ref>/<vpa>" payload,
//    never the account-linked one printed first.
final vpas = _vpaPattern.allMatches(body).toList();
final vpa = vpas.length > 1 ? vpas.last.group(0) : vpas.firstOrNull?.group(0);

// 5. delete the unanchored dash/pipe fallback; require whitespace around | or /
```

---

### RC-09 — Reference numbers: the `upi` branch captures the next word

**Evidence.** `_reference` starts with `\b(?:upi\s*(?:ref(?:erence)?|txn)? …` — the `ref` part is
**optional** — so `UPI:swiggy@icici Ref 559274810022` captures **`SWIGGY`** (A02), and `UPI
chargeback Ref …` captures **`CHARGEBACK`** (G03), `via UPI AutoPay … Ref 556677889900` captures
**`AUTOPAY`** (I03). It also cannot capture `BIL*000910062` (no `*`), `XX-7007` order ids,
`Txn#2699`, `cheque no. 456789`, `order 402-…`, or the numeric ref inside
`Info: UPI/412345678901/bigbasket@ybl`.

Pure-reference failure: **A06**. The other affected fixtures appear in their primary tables:
A02, A04, E04, F01, F07, G03, H01–H06, I03, I04, I05, L05.

| ID | Sender | Body excerpt | Expected ref → actual | Rules |
|---|---|---|---|---|
| A06 | VK-SBIINB | "Info: UPI/412345678901/bigbasket@ybl" | 412345678901 → `null` | RC-09 |

**Suggested fix.**

```dart
static final RegExp _reference = RegExp(
  r'\b(?:upi\s*(?:ref(?:erence)?|txn)(?:\s*(?:no\.?|id))?|utr|rrn|'
  r'ref(?:erence)?(?:\s*(?:no\.?|id))?|txn(?:\s*(?:id|no\.?))?|'
  r'transaction\s*(?:id|no\.?)|trf\s*ref|order(?:\s*id)?|cheque\s*(?:no\.?)?)'
  r'[\s:.#/-]*([A-Z0-9][A-Z0-9*/-]{5,24})\b',
  caseSensitive: false,
);

// "Info: UPI/P2A/<ref>/<vpa>" and "Info: UPI/<ref>/<vpa>"
static final RegExp _upiPayloadRef = RegExp(
  r'\bupi\s*[/:]\s*(?:p2[am]\s*[/:]\s*)?([A-Z0-9]{6,24})\b',
  caseSensitive: false,
);
```

Skip any candidate containing `@` (a VPA is not a reference), and prefer the anchored match over
`UPI:<vpa>`.

---

### RC-10 — Instrument detection misses real shorthand

**Evidence.** `_instrument` checks the generic `_upi` regex (`\bupi\b|@[a-z]{2,}|ybl|paytm|ibl|axl|apl`)
before the wallet and bank rules, and never accepts `Acc` or a bare `Card`.

| ID | Sender | Body excerpt | Expected instrument → actual | Rules |
|---|---|---|---|---|
| A05 | VK-HDFCBK | "debited from UPI Lite (a/c **4821) …" | wallet → **upi** | RC-10 |
| C04 | VK-KOTAKB | "spent on Kotak Card x2210 at BOOKMYSHOW" | creditCard → **unknown** | RC-10 (+RC-02) |
| L03 | VK-PHONPE | "Rs 150 paid to SREE KRISHNA STORES via PhonePe" | wallet → **unknown** | RC-10 (+ registry `PHONPE`) |
| D01 | ATMSBI | "Rs 0368 withdrawn at SBG ATM …" | atm → **bankAccount** | RC-10 (+RC-12) |
| G02 | VK-HDFCBK | "Rs.120.00 has been reversed to your a/c **4821 …" | bankAccount → **upi** | RC-10 (+RC-11) |
| G03 | VK-SBIINB | "… against UPI chargeback Ref 412345678901" | bankAccount → **upi** | RC-10 (+RC-07, RC-09) |
| G04 | VK-KOTAKB | "credited to Kotak Card x2210 …" | creditCard → **unknown** | RC-10 (+RC-02, RC-08) |
| H01/H02/H04 | VM-ICICIB | "Acc XX… debited …" | bankAccount → **unknown** | RC-10 (+RC-06) |

**Suggested fix.**

```dart
Instrument _instrument(String lower, SenderId sender, {required bool isCredit}) {
  if (_cash.hasMatch(lower)) return Instrument.atm;
  if (RegExp(r'\bupi\s*lite\b|\bwallet\b|\bpaytm\b|\bphonepe\b|\bmobikwik\b').hasMatch(lower)) {
    return Instrument.wallet;
  }
  if (RegExp(r'\bcredit\s*card\b|\bcard\b[\s:*#-]*[x*]{1,4}\d{2,5}').hasMatch(lower) ||
      sender.entityKind == 'card') {
    return Instrument.creditCard;   // "Kotak Card x2210", "AMEX card **91009"
  }
  if (RegExp(r'\bdebit\s*card\b|\batm\s*card\b').hasMatch(lower)) {
    return Instrument.debitCard;
  }
  if (RegExp(r'\ba/?c\b|\bacc\b|\baccount\b|\bneft\b|\bimps\b|\brtgs\b').hasMatch(lower)) {
    return Instrument.bankAccount;  // "Acc XX678", "against UPI chargeback"
  }
  if (_vpaPattern.hasMatch(lower) || RegExp(r'\bupi\b').hasMatch(lower)) {
    return Instrument.upi;
  }
  …
}
```

Registry additions: `ATMSBI → SBI ATM`, `PHONPE → PhonePe` (the registry has `PHONEP`/`PHNPE`,
not the code used by the corpus).

---

### RC-11 — Reversal semantics and over-broad self-transfer

**Evidence.** `_isCreditMessage` returns false as soon as it sees `debited`, even when the message
says the debit was reversed. `G05` therefore becomes a spend. `_selfTransfer`'s
`to your a/c` alternative matches a **deposit** destination (`F06`) and a reversal destination
(`G02`), turning both into transfers.

| ID | Sender | Body excerpt | Expected → actual | Rules |
|---|---|---|---|---|
| G05 | VK-HDFCBK | "Rs.1,500.00 debited on 10-05-24 has been reversed." | income → **spend** | RC-11 |
| F06 | VK-SBIINB | "Rs.20,000.00 deposited to your A/c XX1234 via CDM …" | income → **transfer** (`selfTransfer`) | RC-11 |
| G02 | VK-HDFCBK | "Rs.120.00 has been reversed to your a/c **4821 …" | income → **transfer**; instrument upi | RC-11 (+RC-10) |

**Suggested fix.**

```dart
bool _isCreditMessage(String lower) {
  final reversal = RegExp(r'\b(?:revers(?:ed|al)|refund(?:ed)?|chargeback|cashback credited)\b')
      .hasMatch(lower);
  if (reversal && !RegExp(r'\breversal failed\b').hasMatch(lower)) return true; // wins
  if (RegExp(r'\b(?:debited|spent|paid|withdrawn|withdrew|sent|charged|purchase)\b')
      .hasMatch(lower)) {
    return false;
  }
  …
}
```

`_selfTransfer` should require both legs to be the user's own accounts (`from your … to your …`,
`own a/c`, `self transfer`); "deposited to your A/c" and "reversed to your a/c" are one-legged.

---

### RC-12 — ATM cash path and the `ATMSBI` registry gap

**Evidence.** D01 (`ATMSBI`) is not in `SenderRegistry.entities`, so the sender is `plausible` with no
entity. The cash regex requires `withdrawn at ATM` or `withdrawn from ATM`; the real string is
`withdrawn at SBG ATM …`, so `cash` is false and the message becomes a `spend` on a bank account.
The location merchant is rejected because `_isUsableMerchant` rejects any candidate containing three
or more digits (`S10F200912001`). The reference `Txn#2699` is not matched (`#`).

| ID | Sender | Body excerpt | Expected → actual | Rules |
|---|---|---|---|---|
| D01 | ATMSBI | "Rs 0368 withdrawn at SBG ATM S10F200912001 SBH-ACC LTD-MANCHERIAL …" | cash/atm/SBI/2699/merchant → spend/bankAccount/`null`/`null`/`null` | RC-12, RC-02?, RC-09, RC-08 |

**Suggested fix.**

```dart
static final RegExp _cash = RegExp(
  r'\b(?:atm\s*(?:wdl|withdrawal|cash)|cash\s*withdrawal|'
  r'(?:withdrawn|wdl)\b.{0,40}\batm\b|\batm\b.{0,40}\b(?:withdrawn|wdl))\b',
  caseSensitive: false,
);
// registry: 'ATMSBI': (name: 'State Bank of India', kind: 'bank')  // SBI ATM header
// reference: allow txn#2699 via 'txn[\s#:]*([0-9]{3,})'
// merchant: for ATM messages, keep the location string even if it contains digits.
```

---

### RC-13 — Marketing language suppresses a genuine cashback credit

**Evidence.** G06 (`VK-CRED`, "Congratulations! You won INR 6 cashback … will deposit it into your
credit card XXX-6314") is classified `promo`: the promo words (`congratulations`, `won`) add 4, while
the credit evidence is weak (`_creditVerb` only matches `cashback credited`, not "won … cashback").
The research doc expects a transaction (cashback income). Last4 also fails (RC-02).

| ID | Sender | Body excerpt | Expected → actual | Rules |
|---|---|---|---|---|
| G06 | VK-CRED | "Congratulations! You won INR 6 cashback … credit card XXX-6314 …" | transaction → **promo**; last4 6314 → `null` | RC-13, RC-02 |

**Suggested fix.** A known card/account sender + an amount + a credit verb/destination should win
over promo wording; promo alone remains promo only when no money moves:

```dart
final cashbackCredit = RegExp(
  r'\b(?:won|earned|received)\b.{0,30}\b(?:cashback|reward)\b|\bcashback\b.{0,30}\b(?:credited|deposit)',
  caseSensitive: false,
).hasMatch(lower);
if (cashbackCredit && hasAmount && sender.trust == SenderTrust.known) {
  tx += 5; // enough to overtake promo_wording
}
```

---

### RC-14 — Dedupe engine: same-sender refusal and rigid merchant matching

**Evidence.** `DedupeEngine._sameEvent` refuses pairs with the same `sender` outright. Five of the six
corpus duplicate groups are exactly that (the bank and the card/wallet view of one payment come from
the same header), or fail because one side lost its card mask (RC-02) or its merchant strings do not
contain one another. The sixth group (single member) passes.

| Group | Members | Expected → actual | Root cause |
|---|---|---|---|
| `dup-upi-cc-500` | L01 VK-HDFCBK, L02 VK-HDFCBK | 1 row → **2 rows** | same sender (UPI + credit-card view) |
| `dup-cardbill-hdfc-1234` | H07 VK-HDFCBK, H08 VK-HDFCBK | 1 row → **2 rows** | same sender (account + card view) |
| `dup-refund-icici-2815` | G08 VM-ICICIB, G09 VM-ICICIB | 1 row → **2 rows** | same sender (two alert formats) |
| `dup-cardbill-hdfc-7500` | L05 VK-CRED, L06 VK-HDFCBK | 1 row → **2 rows** | L05 lost `last4` (RC-02), both merchants `null` |
| `dup-wallet-upi-150` | L03 VK-PHONPE, L04 VK-HDFCBK | 1 row → **2 rows** | merchants `SREE KRISHNA STORES` vs `VPA sreekrishna@ybl`; no token overlap, both non-null |

**Suggested fix.**

```dart
bool _sameEvent(Txn a, Txn b) {
  if (a.amountPaise != b.amountPaise) return false;
  if (a.kind != b.kind) return false;

  final sameSender = a.sender != null && a.sender == b.sender;
  final sameInstrument = a.instrument == b.instrument;
  final sameCard = a.cardKey != null && a.cardKey == b.cardKey;

  // Same sender + same instrument + same card is a real double charge.
  if (sameSender && sameInstrument && (a.last4 == b.last4)) return false;

  if (sameCard) return true;
  if (_merchantSimilarity(a.merchant, b.merchant) >= 0.6) return true;
  if (_tokenOverlap(a.merchant, b.merchant)) return true;       // shared token >= 5 chars
  return _complementaryInstruments(a.instrument, b.instrument); // bank/card ↔ wallet
}

bool _tokenOverlap(String? a, String? b) {
  if (a == null || b == null) return false;
  final left = _normalise(a).split(' ').where((t) => t.length >= 5).toSet();
  final right = _normalise(b).split(' ').where((t) => t.length >= 5).toSet();
  return left.intersection(right).isNotEmpty; // sreekrishna
}
```

Fixing RC-02 also fixes `dup-cardbill-hdfc-7500` (both sides get `HDFC Bank|1234`).

---

### RC-15 — Merchant-side receipts are booked as spending

**Evidence.** K14 is a merchant copy of a QR payment: *"Thank you for the payment of Rs. 443.26 via
BharatQR UPI ID gax…@okaxis through HDFC Bank SmartHub … Receipt: https://hdfcmmp.mintoak.com/…"*.
It contains a debit-like "payment" and an amount but no balance/limit, so it becomes a transaction
and double-counts the customer's payment.

| ID | Sender | Body excerpt | Expected → actual | Rules |
|---|---|---|---|---|
| K14 | VK-HDFCBK | "Thank you for the payment of Rs. 443.26 via BharatQR … Receipt: https://hdfcmmp.mintoak.com/…" | no transaction → **transaction** (Txn 44326) | RC-15 |

**Suggested fix.**

```dart
static final RegExp _merchantReceipt = RegExp(
  r'\b(?:thank you for (?:your )?payment|payment successful|receipt\s*:|'
  r'mintoak|smarthub|order\s*id|merchant copy)\b',
  caseSensitive: false,
);
// Honoured like RC-05's notYetMoved: informational, extractor returns null.
// Exception: keep it when the same message reports an available balance/limit
// (then it is the customer's own alert, e.g. L06).
```

---

## 4. Root causes — classifier corpus (SC-01 … SC-06)

### SC-01 — Informational recall collapse (11 of 12 failures)

**Evidence.** `info` only accrues from OTP wording (5/8) and `_statementWord` (4). The cascade
requires `info >= 5`, so balance alerts, dispatch notices, maturity notices, service-request
confirmations, branch notices and login alerts fall through to `unknown`. Balances have no signal at
all. `info-03` (cheque cleared) and `info-07` (mandate created) instead fall into the weak
`tx >= 4 && hasAmount → transaction` branch.

| ID | Sender | Body excerpt | Expected → actual |
|---|---|---|---|
| info-01 | VM-HDFCBK-S | "Your a/c XX1234 balance as on 12-06-26 is Rs.12,345.67 …" | informational → **unknown** |
| info-02 | VK-SBIINB-S | "Your account statement for May 2026 has been sent …" | informational → **unknown** |
| info-03 | AD-ICICIB-S | "Cheque no. 442311 for Rs.15,000.00 has been cleared …" | informational → **transaction** |
| info-04 | VM-KKBK-S | "Your fixed deposit KKBKFD90812 matures on 20-06-26 …" | informational → **unknown** |
| info-06 | AD-HDFCBK-S | "Your new Debit Card XX9012 has been dispatched …" | informational → **unknown** |
| info-07 | VM-AXISBK-S | "Your e-mandate for Rs.499.00 to NETFLIX has been created successfully …" | informational → **transaction** |
| info-10 | VM-HDFCBK-S | "Minimum balance alert: Your a/c XX1234 balance is below Rs.10,000 …" | informational → **unknown** |
| info-11 | JD-ICICIB-S | "Your request for address update has been registered. Ref SR9081234 …" | informational → **unknown** |
| info-12 | AD-BARB-S | "Dear customer, our branch will remain closed on 17-06-26 …" | informational → **unknown** |
| info-13 | VM-HDFCBK-S | "Your credit card statement for May 2026 is ready. Total due Rs.12,344.00 …" | informational → **unknown** |
| info-14 | VK-IDFB-S | "We noticed a login to your net banking from a new device …" | informational → **unknown** |

**Suggested fix.** Replace the single `_statementWord` signal with an intent table (each intent adds
4–6 to `info` and emits a named signal), and lower the informational threshold to 4 when no money
verb/amount combination is present:

```dart
static final _infoIntents = <(String, RegExp, int)>[
  ('balance', RegExp(r'\b(?:balance (?:as on|is|:)|avl(?:ailable)? (?:bal|balance))\b'), 5),
  ('statement', RegExp(r'\b(?:statement|account summary|passbook)\b'), 5),
  ('card_statement', RegExp(r'\b(?:total|minimum) due\b|\bdue date\b|\bstatement\b.*\bready\b'), 5),
  ('dispatch', RegExp(r'\b(?:dispatched|delivered|track)\b'), 4),
  ('maturity', RegExp(r'\b(?:matur(?:es|ity)|fixed deposit)\b'), 4),
  ('service_request', RegExp(r'\b(?:request|address update)\b.*\b(?:registered|received)\b'), 4),
  ('branch_notice', RegExp(r'\b(?:branch will remain closed|holiday)\b'), 4),
  ('login_alert', RegExp(r'\b(?:new device|login)\b.*\b(?:not you|notice)\b'), 5),
  ('mandate_setup', RegExp(r'\b(?:e-?mandate|mandate|autopay)\b.*\b(?:created|registered|activated)\b'), 5),
];
for (final (code, pattern, weight) in _infoIntents) {
  if (pattern.hasMatch(lower)) { info += weight; signals.add(SmsSignal(code, -weight)); }
}
// Informational beats `unknown` when there is no completed money movement:
if (info >= 4 && !_debitVerb.hasMatch(lower) && !_creditVerb.hasMatch(lower)) {
  cls = SmsClass.informational;
}
```

For `info-03`/`info-07` the `notYetMoved`/mandate-setup rule (RC-05) is the veto that keeps them out
of `transaction`.

---

### SC-02 — "Do NOT share this OTP" is read as an OTP request

**Evidence.** `_credentialAsk` is
`(?:share|send|tell|confirm|enter|provide).{0,24}(?:otp|…)`. In a **warning** — *"Do NOT share this
OTP"* / *"Never share your OTP, PIN or CVV"* — it matches and adds +8 phishing, while
`genuineTransaction` is false. Four fixtures become `phishing`.

| ID | Sender | Body excerpt | Expected → actual |
|---|---|---|---|
| info-09 | AD-UIDAI-G | "Your Aadhaar OTP for update request is 480112. Do not share this OTP …" | otp → **phishing** |
| otp-01 | VM-HDFCBK-S | "123456 is your OTP for login … Do NOT share this OTP …" | otp → **phishing** |
| otp-03 | AD-ICICIB-S | "Your OTP is 771204 for card ending 4412. Never share your OTP, PIN or CVV …" | otp → **phishing** |
| otp-06 | VK-PAYTMB-T | "338291 is your Paytm OTP for txn of Rs.1,250.00 … Never share OTP …" | otp → **phishing** |

**Suggested fix.**

```dart
final negated = RegExp(r'\b(?:do not|don\'t|never|not)\s+(?:share|disclose|reveal)\b')
    .hasMatch(lower);
if (!negated && _credentialAsk.hasMatch(lower)) {
  phish += 8;
  signals.add(const SmsSignal('credential_ask', -8));
}
// hard rule: an OTP message from a non-suspicious sender, with no credential ask,
// no suspicious URL and no "pay to receive" template, is informational.
final isOtp = _otpWord.hasMatch(lower) && _otpLikeNumber.hasMatch(lower);
if (isOtp && !credentialAsk && url == null && !_scamTemplate.hasMatch(lower)) {
  cls = SmsClass.informational;
}
```

---

### SC-03 — Legitimate RBI KYC advisory flagged as phishing

**Evidence.** info-05 says *"complete your KYC by visiting your home branch with Aadhaar and PAN. No
update is done over phone or link."* `_kycLure` (+4) and `_phishCta` (`visit`, +3) reach 7 → phishing.
The message is explicitly telling the user **not** to use a phone or link.

| ID | Sender | Body excerpt | Expected → actual |
|---|---|---|---|
| info-05 | VK-SBIINB-S | "… complete your KYC by visiting your home branch … No update is done over phone or link." | informational → **phishing** |

**Suggested fix.** Add a safe-context guard, and don't treat `visit` as a CTA without a URL:

```dart
final safeKyc = RegExp(
  r'\b(?:no update|not (?:over|through) (?:phone|link)|home branch|'
  r'never share|do not share|visit (?:your )?(?:home )?branch)\b',
  caseSensitive: false,
).hasMatch(lower);
if (!safeKyc && _kycLure.hasMatch(lower)) phish += 4;

static final RegExp _phishCta = RegExp(
  r'\b(?:click|tap|login|log in|open the link|scan (?:this )?qr|pay (?:now|immediately)|'
  r'share (?:the )?otp|claim|confirm your details|bank details)\b',
  // "visit <branch>" removed: only suspicious when a URL is present
);
```

---

### SC-04 — Fraud false negatives: `genuineTransaction` overrides phishing evidence

**Evidence.** `genuineTransaction` is computed from transaction signals only; it does not consider a
credential request, a suspicious link or a known scam template. Six fraud fixtures therefore land in
`transaction` or `unknown`, including two that ask for an OTP / app install.

| ID | Sender | Body excerpt | Expected → actual | Why |
|---|---|---|---|---|
| fraud-02 | AD-HDFCBNK-T | "… verify now at https://hdfc-secure-verify.xyz/login" | fraud → **transaction** | phish 5 (link) < 6; genuine tx wins |
| fraud-05 | AD-HDFCBK-T | "… received a refund … Share the OTP …" | fraud → **transaction** | credential ask ignored by genuine tx |
| fraud-06 | VM-PAYTMB | "Your wallet is blocked. Scan this QR … bit.ly/ptm-refund" | fraud → **transaction** | strong phish ignored by genuine tx |
| fraud-10 | +91 8822113344 | "Part-time job … Pay Rs.500 registration … Telegram …" | fraud → **unknown** | only suspicious-sender 3; no template |
| fraud-13 | AD-PNB-S | "… debited twice. Install AnyDesk and share the code …" | fraud → **unknown** | no remote-access template; no amount signal |
| fraud-15 | AD-HDFCBK-S | "Your account will be debited for Rs.4,999 … call … to cancel" | fraud → **transaction** | future-tense debit + threat not modelled |

**Suggested fix.**

```dart
final credentialAsk = !negated && _credentialAsk.hasMatch(lower);
final strongPhish = credentialAsk ||
    suspiciousUrl ||
    _scamTemplate.hasMatch(lower) ||
    RegExp(r'\b(?:anydesk|teamviewer|share (?:the )?code|registration (?:fee|amount)|'
            r'work from home|part[- ]time job|telegram|liking youtube|account will be (?:debited|charged))\b')
        .hasMatch(lower);

if (strongPhish || (phish >= 6 && !genuineTransaction)) {
  cls = SmsClass.phishing;
} else if (genuineTransaction) {
  cls = SmsClass.transaction;
}
```

Also raise the suspicious-link weight to 8, and treat a numeric/unknown sender plus a money ask as
phishing (`phish += 4` for `suspicious_sender`, not 3).

---

### SC-05 — Genuine UPI debits classified `unknown` (same cause as RC-01)

| ID | Sender | Body excerpt | Expected → actual |
|---|---|---|---|
| tx-02 | VK-SBIINB-T | "Your a/c XX9082 debited Rs.2,000.00 … Bal Rs.15,220.10." | transaction → **unknown** |
| tx-11 | AD-FDRL-T | "Federal Bank: A/c XX3320 debited Rs.1,000.00 … Bal Rs. 19,300.00." | transaction → **unknown** |

Fix: RC-01. These two are the clearest proof that the amount-scoring bug costs real transactions, not
just fixture points.

---

### SC-06 — Job-scam promo not recognised

| ID | Sender | Body excerpt | Expected → actual |
|---|---|---|---|
| promo-12 | AD-JOBALERT | "Hiring alert! Work from home, earn Rs.25,000/month … Reply STOP to opt out." | promo → **unknown** |

**Suggested fix.** Add job-scam vocabulary to `_promoWord`
(`work from home|hiring|earn\s+(?:rs\.?|₹)?\s*\d+\s*(?:/|per)?\s*(?:day|month)|no experience|whatsapp.*apply`)
and let the opt-out signal alone reach the promo threshold (`promo >= 3` when `opt_out` matched).

---

## 5. Fixture anomalies in the research documents

These are places where the research fixture itself is questionable. The suite does not paper over
them; each is called out here so nobody "fixes" the parser to match a bad expectation.

| Fixture | Issue | Recommendation |
|---|---|---|
| **H07** | `direction: expense`, but the note says *"bank debit to a card bill — category cardBill, not consumption"*. The parser returns `transfer` (reason `creditCardBill`), which matches the note. H07 and H08 are also in the same duplicate group, so one of them is redundant either way. | Change the fixture to `direction: transfer`, or drop H07 and rely on H08 (issuer confirmation). Until then, H07 is counted as a failing fixture in the bill-payments bucket. |
| **I05** | Research instrument `account`, expected `bankAccount`; the parser has `Instrument.emi` and returns it for *"towards EMI for loan"*. | Add `emi` to the research enum, or accept `emi` in the assertion. The app's model is defensible; the fixture taxonomy is behind. |
| **G06** | `issuer: 'unknown (mask 6314)'` is a note, not an issuer; `C11` uses `'OneCard (CSB Bank)'`, which is a composite label. | Split `issuer` (identity) from `note`; the test skips issuer identity when the field starts with "unknown". |
| **G09 / G08** | Two fixtures describe the same refund in different words (deliberate duplicate group) but only G08 carries `isDuplicateGroup`; G09 does too. Fine. | No action. |
| **H05 / L05** | Both contain multi-segment masks (`7121-81XX-XXXX-7007`) where the **last** four digits are the account tail. The doc says so in the note, but the fixture field `last4` cannot express "last segment of the mask". | Add a note in the schema or a `cardLastDigits` cross-check; the parser fix is unambiguous (RC-02). |
| **A05** | `direction: expense`, `instrument: wallet` — correct, but it is also the only UPI-Lite case; the parser's generic `\bupi\b` wins. | No change; this is a real parser gap (RC-10). |

---

## 6. Non-parser findings

### 6.1 `RecurringDetector` does not reject irregular amounts (`engine_test.dart`)

`detect()` computes `isAmountStable` but never filters on it. A series of ₹649 / ₹1,299 / ₹649 is
still returned as a "recurring" series (with `isAmountStable == false`), and `InsightsEngine`
does not check the flag either (`_upcomingRecurring` iterates every series). The engine test asserts
the research/UI contract — irregular amounts must be rejected — and fails:

```
RecurringDetector irregular amounts are rejected: Expected: empty
  Actual: [Instance of 'RecurringSeries']
```

Fix: `if (!stable) continue;` in `detect()`, or filter `isAmountStable` in `_upcomingRecurring`.

### 6.2 Widget smoke test: flex overflows at 360×800 with text scale 1.3

`FinanceApp` is pumped with demo data at a 360×800 logical surface and 1.3× text (Ahem in widget
tests). The app throws one 265 px horizontal overflow on the first frame, and five more after
scrolling Home. Localised with `FlutterErrorDetails.informationCollector`:

| Overflow | Widget (creator chain) | Likely cause |
|---|---|---|
| 265 px right | `Row ← Column ← Padding ← … ← _HeroCard` | "SPENT THIS MONTH" + month-over-month chip in one unconstrained `Row` |
| 23 px right | `Row ← Column ← _CategoryRow ← … ← _CategoryCard` | `Pill` change chip + amount in one `Row` |
| 58 px right | `Row ← Column ← Padding ← Container ← GestureDetector …` | tab content under a tappable card (unidentified) |
| 17 px right | same chain | same |
| 16 px bottom ×2 | `Column ← Padding ← Container ← GestureDetector …` | bottom-navigation destination label at 1.3× |

Ahem is wider than the real font, so these are worst-case; the hero Row and the nav labels are the
two worth fixing regardless (wrap the chip in `Flexible`/`FittedBox`, remove the fixed
`NavigationBar` height assumption). The test's other assertions pass: the hero amount is found
exactly, the "Where it went" category card is found and the first category row is rendered, and the
Cards tab shows the first demo card and its masked tail.

---

## 7. Suggested fix order (by unblocked checks)

| Order | Change | Fixtures unblocked (isolated) | Notes |
|---|---|---:|---|
| 1 | RC-02 mask regex | 6 fixtures + 1 dedupe group | A03 A08 C03 C05 D03 F05 (+L05 with ref) |
| 2 | RC-08 merchant extraction | 5 | C01 G01 G08 G09 F04 |
| 3 | RC-05 "not moved" guard | 5 | I01 J03 J04 K08 K18 |
| 4 | RC-01 amount scoring | 2 + 2 classifier | F02 F03 + tx-02 tx-11 |
| 5 | RC-03 direction (P2P/NEFT) | 3 | A09 E02 E05 (+E03/E04 with RC-02/09) |
| 6 | RC-07 issuer precedence | 3 | E01 C08 C12 (+A04/F01/F07/G03/I04) |
| 7 | RC-04 autopay direction | 2 | I02 I06 (+I03/I04/I05) |
| 8 | RC-06 SMS BLOCK | 0 alone; enables H01–H04 with RC-01/02/09/10 | highest *severity* (genuine tx flagged as fraud) |
| 9 | RC-09 reference regex | 1 pure (A06) + fields in ~17 | |
| 10 | RC-10 instrument order + registry PHONPE/ATMSBI | 2 | A05 L03 |
| 11 | RC-11 reversal | 1 | G05 (+F06/G02) |
| 12 | RC-14 dedupe | 5 dedupe groups | needs RC-02 for the 7500 group |
| 13 | RC-15 receipt guard | 1 | K14 |
| 14 | SC-01 informational intents | 11 classifier | biggest single classifier gain |
| 15 | SC-02 OTP negation | 4 classifier | |
| 16 | SC-04 phishing veto | 6 classifier | highest *risk*: fraud booked as spend |

If RC-01, RC-02, RC-03, RC-04, RC-05 and RC-07 land together, the transaction suite should move from
46/103 to roughly 75–80/103; the classifier suite should reach ~85% with SC-01/02/04. The remaining
failures are mostly long-tail merchant/reference formats, which is where a template-fingerprint table
(as described in the research docs) beats more regex.

---

## 8. Files produced

| File | Purpose |
|---|---|
| `test/fixtures/sms_corpus.dart` | 103 transaction fixtures, verbatim from research §10 (`issuer`/`merchantContains` renamed per the test brief; `tags` empty) |
| `test/fixtures/spam_corpus.dart` | 77 classifier fixtures, verbatim from research Appendix A (`SpamClass` keeps `otp`/`fraud`) |
| `test/sms_corpus_test.dart` | Per-fixture classifier+extractor assertions, bucket grouping, `SUMMARY`/`GAP` TSV output |
| `test/spam_corpus_test.dart` | Per-fixture classifier assertions, class grouping, `SUMMARY`/`GAP` TSV output |
| `test/engine_test.dart` | 21 pure-Dart analytics tests (summary, cards, dedupe, recurring, money) |
| `test/widget_smoke_test.dart` | Full `FinanceApp` smoke test at 360×800 / 1.3× |
| `docs/research/parser-gap-report.md` | This report |

The parser, engines and views were not modified.

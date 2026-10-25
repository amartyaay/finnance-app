# 01 — Indian transactional SMS corpus & on-device parsing spec

Status: research specification for the offline Flutter spend tracker.
Scope: SMS (and SMS-derived notifications) sent by Indian banks, card issuers, wallets and
payment apps about money movement. No bank APIs, no backend, no network at runtime.

This document is deliberately **evidence-tiered**. Indian bank templates are private DLT
templates; nobody can legally publish an exhaustive register. Every row below is tagged:

| Tier | Meaning |
|---|---|
| **O** | Observed — the literal wording appears in a public corpus of real received SMS (cited). |
| **V** | Vendor demo — published by a commercial SMS parser as a production sample (cited), wording plausible but not independently confirmed. |
| **I** | Inferred — reconstructed from bank help pages, product behaviour and the grammar in §2; **not** verified as a live template. Treat as a hypothesis, not a fixture of truth. |

Rule for implementers: **templates are hints, tokens are truth.** Parse with the token grammar
(§2) and use per-bank templates only to disambiguate instrument/direction.

---

## 0. Corpus provenance (what the evidence actually is)

| Corpus | What it is | Used for |
|---|---|---|
| [gandharvbakshi/SMS-dataset-sample-10k](https://huggingface.co/datasets/gandharvbakshi/SMS-dataset-sample-10k) (HF, 10k rows, inspectable rows API) | Real Indian SMS inbox dump, anonymised by the uploader; contains genuine bank/issuer alerts with sender headers | Tier **O** rows |
| [Dibba India bank SMS parser demo](https://dibba.ai/bank-sms-parser/india) — 5 published samples ([HDFC UPI](https://dibba.ai/bank-sms-parser/india/hdfc-upi-chai-sms), [SBI debit card](https://dibba.ai/bank-sms-parser/india/sbi-card-shopping-sms), [ICICI UPI](https://dibba.ai/bank-sms-parser/india/icici-upi-food-sms), [Axis card](https://dibba.ai/bank-sms-parser/india/axis-fuel-sms), [Kotak card](https://dibba.ai/bank-sms-parser/india/kotak-ticket-sms)) | Vendor-published "production parser" samples; dates look synthetic (2026), bodies look template-faithful | Tier **V** rows |
| [Exotel — DLT compliance guide](https://developer.exotel.com/docs/faqs/dlt-compliance.md) | Operator-side DLT mechanics: 6-char header, `{#var#}` templates, character-exact matching | §1, §2 |
| [StartMessaging — SMS sender ID India guide](https://startmessaging.com/blog/what-is-sms-sender-id) | Header = 2-char operator/category prefix + brand; prefix families | §1.2 |
| [transaction-sms-parser (npm README)](https://app.unpkg.com/@strmchsr/transaction-sms-parser@1.2.4/files/README.md) | Prior art: account/balance keyword lists, bank keyword list incl. `ATMSBI`, `ALBANK`, `BOB`, `PNB`, `KOTAK`, `IDFC`; states it is tested against Axis, ICICI, Kotak, HDFC, Standard Chartered, IDFC, Niyo, HSBC, Citi, Sodexo, IndusInd, Slice, Paytm, Amazon Pay, Lazypay, Simpl | §1.4, §2.11 |
| [transaction_sms_parser (pub.dev, Dart)](https://pub.dev/packages/transaction_sms_parser) | Prior art for a Flutter-shaped API (`TransactionInfo` / `AccountInfo` / `Balance`). **Its example SMS bodies are invented** — do not copy them as format evidence. | API shape only |

Sampling caveat: the HF inbox dump is dominated by OTPs, e-commerce logistics and personal
messages; bank alert density is low. The rows used here are quoted verbatim in §3 and are
reproducible through the rows/filter API (`.../filter?where="sms_text" LIKE '%Avl Bal%'`).

---

## 1. Sender ID (DLT header) structure

### 1.1 Anatomy

India standardised the header at **6 characters**: 2-character operator+category prefix, then a
brand mnemonic. In practice handsets display `PREFIX-BRAND`, e.g. `VK-ICICIB`, `VM-SCBANK`,
`AX-HDFCBK`; the hyphen is optional and is **not present** in some corpora
(`VKHDFCBN`, `QPPRACTO`, `JMBLUDRT`, `JDSMRTRL`, `ADSHIPRT` all appear in the HF corpus).
Brand part can be up to 6 characters (`ICICIB`, `SCBANK`, `AXISBK`, `KOTAKB`).

Because the header is registered **per category** ([StartMessaging](https://startmessaging.com/blog/what-is-sms-sender-id),
[Exotel](https://developer.exotel.com/docs/faqs/dlt-compliance.md)), one brand usually owns
several headers (transactional vs service vs promotional). A phone book of one code per bank is
therefore wrong; match on the **brand token**, not the full header.

### 1.2 Prefix families

| Prefix | Operator | Category (as documented) | Seen on bank SMS? |
|---|---|---|---|
| `JD` `JM` `JT` `JX` | Jio | transactional / OTP | yes (`JDSMRTRL`, `JMBLUDRT`) |
| `VK` `VM` `VG` `VX` | Vi (Vodafone Idea) | transactional / service | **most common** (`VK-ICICIB`, `VM-ICICIB`, `VM-SCBANK`, `VK-AXISMF`) |
| `AX` `AT` `AM` | Airtel | transactional / service | yes (inferred for bank codes; `ADSHIPRT` is legacy-style) |
| `AD` | legacy bulk / promotional class | promotional + legacy transactional | yes (`ADSHIPRT` logistics) |
| `TX` `TM` | transactional / OTP class | — | yes |
| `VA` | observed, meaning undocumented (`VA-LICOUS-S`, `VA-AWFISS`) | service | yes (non-bank) |
| `QP` | observed, meaning undocumented (`QPPRACTO`, `QPFASTag`) | service | yes (FASTag issuer!) |
| `G-`, `GD-`, `BP-`, `BK-` | claimed legacy/gateway prefixes, **unverified** — do not encode semantics | unknown | possibly |
| 6-digit numeric (`57575353`, `59039029`, `50350300`) | promotional / bulk | promotional | no — reject |
| 10-digit mobile (`+917019137405`) | P2P, not DLT | n/a | never a bank alert |

**Implementable rule (robust, evidence-independent):** don't hard-code "JD means Jio"; just
strip `^[A-Z]{2}-?` when the remainder matches a known brand token, and treat an unknown
2-letter prefix as an unknown operator (store it, don't branch on it). Operator semantics are
only useful for spam classification.

### 1.3 Suffix and variant quirks

- Trailing `-S` on some service headers (reported as "service" class by users, e.g. `-S`
  suffix on bank/CC SMS) — unverified; treat `-S` as noise and strip.
- Same brand, multiple codes: `VM-ICICIB` and `VK-ICICIB`; `VK-SCBANK` and `VM-SCBANK`.
- Product-specific codes: `ISECLT` (ICICI Securities), `AXISMF` (Axis Mutual Fund),
  `QPFASTag`, `HDFCBN` — these are **not** the retail bank and must not be mapped to the
  bank's account alerts (a mutual-fund SIP SMS is not a card spend).
- Case: always upper-case before matching.

### 1.4 Issuer code map

`O` = code observed in a cited corpus; `V` = published vendor sample; `I` = inferred/common.

| Brand token (match by prefix) | Entity | Instruments it alerts | Tier |
|---|---|---|---|
| `HDFCBK`, `HDFCBN`, `HDFC*` | HDFC Bank | account, UPI, debit card, ATM, credit card | **V** (`HDFCBK`), **O** (`VKHDFCBN`), I for CC sub-code |
| `ICICIB`, `ICICI*` | ICICI Bank | account, UPI, FASTag, debit card, credit card | **O** (`VM-ICICIB`), **V** (`ICICIB`) |
| `SBIINB` | State Bank of India (internet banking) | account, UPI, debit card | **V** |
| `SBICRD`, `SBIC*` | SBI Card (separate issuer) | credit card | **I** |
| `ATMSBI`, `SBI*` | SBI ATM / SBI | ATM, account | **O** (`ATMSBI` in npm keyword list), I for the rest |
| `AXISBK`, `AXIS*` | Axis Bank | account, UPI, debit card, credit card | **V** (`AxisBk` display) |
| `KOTAKB`, `KOTAK*`, `KKBK` | Kotak Mahindra Bank | account, UPI, debit/credit card | **V** (`KOTAKB`), I for `KKBK` |
| `IDFCFB`, `IDFC*` | IDFC FIRST Bank | account, UPI, cards | **I** (npm lists `IDFC` as a keyword) |
| `AUBANK`, `AUBL` | AU Small Finance Bank | account, UPI, cards | **I** |
| `RBLBNK`, `RBL*` | RBL Bank | account, UPI, cards | **I** |
| `YESBNK`, `YES*` | Yes Bank | account, UPI, cards | **I** (a `@yesbankltd` VPA is observed) |
| `INDUSB`, `INDUS*` | IndusInd Bank | account, UPI, cards | **I** |
| `FEDBNK`, `FEDERAL` | Federal Bank | account, UPI, cards | **I** |
| `SBM*`, `NIYO` | SBM Bank India / Niyo | account (Niyo Global), cards | **I** |
| `CSB*`, `ONECRD`, `ONECARD` | CSB Bank / OneCard (also Federal, SBM, South Indian Bank, IDFC FIRST) | credit card | **I** |
| `AMEX`, `AMEXIN` | American Express India | credit card | **O** (body), **I** (sender code) |
| `SCBANK`, `SC*` | Standard Chartered | card, account | **O** (`VK-SCBANK`, `VM-SCBANK`) |
| `HSBC`, `CITI`, `CITIBK` | HSBC / Citi India (now Axis) | card | **I** (npm: tested) |
| `CRED`, `CREDCB` | CRED (card bill payments, not a bank) | card payment received | **O** (body), **I** (sender) |
| `ISECLT` | ICICI Securities | demat/MF, never a card spend | **O** |
| `AXISMF` | Axis Mutual Fund | SIP, never a card spend | **O** |
| `QPFASTag` | FASTag issuer (NPCI/issuer bank) | FASTag top-up/wallet | **O** (sender seen) |
| `PAYTM`, `PYTM`, `PHONPE`, `PHPE`, `AMZNPY`, `GPAY`, `MOBIKWIK` | wallets / UPI PSPs | wallet txn, top-up | **I** — most PSPs notify in-app, not by SMS; PhonePe/Paytm do send SMS for some flows |
| `SLICE`, `LAZYPAY`, `SIMPL`, `UNI` | BNPL / card-like | card spend | **I** (npm: tested with Slice, Lazypay, Simpl, Uni) |
| `JUPITR`, `FIBNK` | neobanks (Federal/SBM rails) | account/UPI | **I** |

### 1.5 Normalization algorithm (Dart-ready pseudocode)

```dart
String? normalizeSender(String raw) {
  var s = raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  if (RegExp(r'^\+?\d{10,}$').hasMatch(s)) return null;        // P2P / short-code, not DLT
  if (RegExp(r'^\d{4,8}$').hasMatch(s)) return null;           // numeric promo header
  s = s.replaceFirst(RegExp(r'-S$'), '');                      // service suffix noise
  // strip a 2-letter operator prefix, with or without hyphen, only if a known brand follows
  final m = RegExp(r'^([A-Z]{2})-?(.+)$').firstMatch(s);
  if (m != null && !_brandTokens.any((b) => m.group(2)!.startsWith(b))) {
    // unknown prefix + unknown brand: keep whole token, mark operator unknown
    return s;
  }
  final brand = m?.group(2) ?? s;
  return brand;
}
```

Mapping brand → `Issuer`: match **longest prefix** in the §1.4 table; keep the raw header on the
row for auditability. Never infer the bank from the body alone unless the header is unknown
(body inference is tier-B evidence and must lower `confidenceHint`).

---

## 2. Universal token grammar (bank-agnostic)

Everything in this section is observed across ≥2 issuers unless marked otherwise. Regexes are
given as Dart-compatible strings; assume `caseSensitive: false` and `dotAll: false`.

### 2.1 Amount surface forms

| Surface | Example (observed) | Parser note |
|---|---|---|
| `Rs.120.00` | HDFC UPI | `Rs` + optional `.` + no space |
| `Rs 320.00` | ICICI UPI | space |
| `INR42.97` | ICICI P2M | no space after INR |
| `INR 7,689.62` | ICICI CC | space + Indian grouping |
| `₹5052.33` | UPI apps, some banks | rare in bank SMS; support it |
| `Rs 0368` | SBI ATM | **no decimals**, zero-padded |
| `Rs. 035.43` | ICICI bill pay | zero-padded hundredths |
| `INR 0,100.35` / `Rs. 00,985.64` / `INR 01,909` | ICICI / CRED | zero-padded to fixed width with grouping |
| `INR 4,87,363.93` | ICICI | **lakh grouping** (2,2,3) |
| `USD 12.99 (INR 1,108.24)` | forex cards/CC | currency pair — take the INR leg as `amountPaise`, keep FX leg as metadata |

```dart
// amount token; group(1) is the numeric payload (commas may remain)
r'(?:INR|Rs\.?|₹)\s?(\d[\d,]*(?:\.\d{1,2})?)'
```

Do **not** write `\d{1,3}(?:,\d{2,3})*` as the integer part: it silently truncates
`Rs 0368` to `036` and `INR 2856.15` to `285`, because the optional comma-group matches zero
times. Greedy `\d[\d,]*` plus "strip commas, then parse" is correct for every observed form.

Parsing rules (all observed quirks):

1. Strip commas, then `double.parse`. `"035.43"` → 35.43, `"0,100.35"` → 100.35,
   `"00,985.64"` → 985.64, `"0368"` → 368. **Do not** validate against Indian grouping.
2. `paise = (rupees * 100).round()`. Never store doubles for money.
3. A trailing `.00` is common (`Rs.849.00`); a bare integer (`Rs 0368`) is **rupees**, not paise.
4. Decimal with 1 digit (`Rs 19.5`) occurs in merchant receipts — multiply by 100 after
   normalising to 2 decimals (`19.50`).
5. Reject amounts of `0` unless the verb is `reversed`/`refund` (some reversals quote `INR 0`).

### 2.2 Multiple amounts in one SMS

A single alert routinely carries **2–4 numbers**:

```
INR 366.19 spent on ICICI Bank Card XX2815 ... Avl Lmt: INR 4,33,288.04
 ^txn                            ^card                      ^available limit
```

```
Rs 0368 withdrawn at SBG ATM ... on 221216.Txn#2699 .Avl bal Rs 76874.33. Free SBG ATM txns if AMB>25000.
 ^txn                                   ^ref     ^balance                     ^unrelated threshold
```

Resolution order:

1. Find all amount tokens with their character offsets.
2. Score each by the **nearest preceding label** within 40 chars:
   `Avl Bal|Avl. bal.|Available Balance|Avl Lmt|Available Limit|Total Credit Limit|Outstanding|Unbilled` ⇒ **not** the txn amount.
3. Tokens inside a "reference/ref/txn/UTR/trip/order" context ⇒ **not** an amount even if digits
   (e.g. `Txn#2699`, `trip number 909451149`, `UPI Ref No 621847362514`).
4. Remaining candidates: the **first** amount before any balance label wins (bank SMS put the
   txn amount first in ~all observed templates). If a template is known to be balance-only
   (§7), emit no transaction.
5. Percentages (`2%`, `GST 18%`), `AMB>25000`, `Rs.5/ SMS`, `50000+ Sellers` are noise — require
   a currency marker for any amount, and reject amounts followed by `%`.

### 2.3 Direction verbs

| Direction | Verbs / phrases (observed unless marked I) |
|---|---|
| **expense** (debit) | `debited`, `debited with`, `debited for`, `debited by`, `spent`, `spent on`, `withdrawn`, `paid`, `payment of ... to`, `sent`, `purchase`, `used at`, `txn of`, `charges`, `dr` (I) |
| **income** (credit) | `credited`, `credited with`, `credited to`, `received`, `deposited`, `refund ... credited`, `cashback ... credited`, `reversed to`, `added to` (wallet) |
| **transfer** (internal) | `transferred to`, `sent to`, `to VPA`, `IMPS to`, `NEFT to`, `RTGS to`, `self transfer`, `withdrawn to` (own account), `payment received for your ... card` (card bill) |

Trap (real): SBI IMPS debit reads
`Your a/c no. XXXXXXXX1710 is debited for Rs.986.93 ... and a/c XXXXXXX133 credited (IMPS Ref no MO17335372).`
Both `debited` **and** `credited` appear; the **first** verb governs, and the credited account is
the *counterparty*. Same trap in `Acct XXX702 debited with INR42.97 ... and bharatpe...@yesbankltd credited`.

Trap (real): `... has requested money from you ... INR 510.30 will be debited from your A/c` —
future/conditional collect request, **not** a debit (§7).

### 2.4 Instrument cues

| Instrument | Cues |
|---|---|
| `upi` | `UPI`, `VPA`, `@okhdfcbank/@okicici/@okaxis/@oksbi/@ybl/@paytm/@ibl/@axl/@apl`, `UPI Ref`, `UPI Lite`, `BharatQR` |
| `account` | `A/c`, `Acct`, `Account`, `a/c no.`, `XXXXXXX1710`, `NEFT`, `IMPS`, `RTGS`, `cheque`, `CDM`, `CMS` |
| `debitCard` | `Debit Card`, `ATM Card` (I), and bare `Card` when a balance (not limit) is quoted |
| `creditCard` | `Credit Card`, `Card XX<n>` **with** `Avl Lmt`/`Available Limit`/`Total Credit Limit`/`Outstanding`, `OneCard`, `AMEX card`, `SBI Card` |
| `atm` | `ATM`, `withdrawn at`, `cash withdrawal`, `CDM` (cash deposit ⇒ income) |
| `wallet` | `wallet`, `Paytm`, `Amazon Pay balance`, `PhonePe`, `Mobikwik`, `UPI Lite` (sub-wallet), `FASTag` (prepaid) |

Ambiguity to encode explicitly: **`Avl bal` can be a credit card.** Kotak's published card
sample says `Rs.560.00 spent on Kotak Card x2210 at BOOKMYSHOW ... Avl bal Rs.8,904.12`
([V](https://dibba.ai/bank-sms-parser/india/kotak-ticket-sms)). So: classify `card` first from
the word `Card`, then use `Avl Lmt`/`Available Limit` to refine to `creditCard`; fall back to
`debitCard` only when the SMS also says `Debit` or when the issuer is known to use `Avl bal` for
debit cards.

### 2.5 Card mask forms

| Surface | Issuer seen | Extraction |
|---|---|---|
| `XX2815`, `XX 1234`, `xx1234` | ICICI, HDFC | last 4 |
| `XXXX-5098`, `XXX-6314`, `X-1009` | CRED/cashback mailers | last 4 |
| `ending 5522`, `ending with 6904` | SBI, others | last 4 |
| `x2210` | Kotak | last 4 |
| `**91009` | **Amex — 5 digits** | last 4 = final four of the mask (`1009`); store mask verbatim too |
| `7121-81XX-XXXX-7007` | CRED (full PAN shape) | last4 `7007`, BIN `712181` ⇒ issuer lookup |
| `Card 5444` (no mask prefix) | ICICI SI reminder | last 4 |
| `**4821` (account) | HDFC | **account** last4, not card |
| `xxxx 1710` (SBI ATM) | SBI | account last4 (space inside mask!) |

```dart
final cardMask = RegExp(
  r'(?:card|onecard|amex card)\D{0,12}?'
  r'(?:ending(?:\s+with)?\s*)?'
  r'(?:[Xx*]{1,6}[\s-]?)?'
  r'(\d{3,6})',
  caseSensitive: false,
);
```

Then `last4 = digits.substring(digits.length - 4)`. Keep `rawMask` — Amex needs 5, Axis sometimes
prints 3 (`XX931`), and dedupe must not join a 3-digit mask to a 4-digit one.

### 2.6 Account mask forms

`A/c **4821`, `A/c XX742`, `Acct XX240`, `Account XX963`, `a/c no. XXXXXXXX1710`,
`A/c xxxx 1710`, `AC XXXXX301710`, `Account XXXXX1710`, `A/c XX1234`. Extract the **last 4 digits**
of whatever run of `X`/digits is attached to the account token; ignore the mask length.

### 2.7 VPA (UPI ID) grammar

```dart
final vpa = RegExp(r'([a-zA-Z0-9][a-zA-Z0-9.\-_]{1,60})@([a-zA-Z][a-zA-Z0-9]{1,20})');
```

Known handles (non-exhaustive, observed + common): `okhdfcbank`, `okicici`, `okaxis`, `oksbi`,
`ybl` (PhonePe), `ibl` (PhonePe/ICICI), `axl`, `paytm`, `apl` (Amazon Pay), `upi`, `icici`,
`sbi`, `hdfcbank`, `yesbankltd`, `airtel`, `freecharge`, `jupiteraxis`, `naviaxis`, `superyes`,
`fam`, `slc`, `waaxis`, `wahdfcbank`, `waicici`, `wasbi`, `timecosmos`.

Merchant-vs-person heuristic on the VPA local part:

1. All digits / `\d{10}` / `\d{12}` ⇒ **phone-number VPA** ⇒ likely P2P ⇒ `direction: transfer`.
2. Contains a business-ish token (`chai`, `swiggy`, `bharatpe`, `store`, `mart`, `pay`, `cafe`,
   `medical`, `petrol`, `books`, `food`) ⇒ likely P2M ⇒ `expense`.
3. Explicit P2A/P2M marker wins over both — ICICI/SBI embed it: `Info:UPI/P2A/730609020693/...`
   (observed). `P2A` = person-to-account (transfer); P2M = merchant (expense) *(P2M marker
   inferred, P2A observed)*.
4. If the SMS also has an `at <Merchant>` frame, prefer that name over the VPA local part.

### 2.8 Merchant capture frames

| Frame | Example | Terminators |
|---|---|---|
| `at <M>` | `at AMAZON PAY INDIA on 02Aug26`, `at PAYU ZOMATO on 08/03/2020` | ` on `, ` Avl`, ` Ref`, ` UPI`, ` Txn`, ` SMS`, `.`, `,` |
| `to VPA <vpa>` | `to VPA chaipoint@ybl (UPI Ref No ...)` | ` (`, ` UPI`, ` Ref` |
| `to <M>` | `to SWIGGY`, `to Zomato` | ` on `, ` UPI`, ` Ref`, `.` |
| `towards <M>` | `towards refund from AMAZON` (I) | ` on `, `.` |
| `Info: <M>` | `Info: Swiggy.`, `Info:BIL*ONL*00059`, `Info:EBA*NSE M 202` | `.`, ` Avl`, ` For`, end |
| `via <M>` | `via BharatQR UPI ID ... through HDFC Bank SmartHub` (merchant-side receipt) | ` through `, ` on `, `.` |
| `at POS <M>` | merchant receipts (`at POS:PVR VEGA MALL,BENGALURU`) | `,` ` Thanks` |
| `from <M>` (credit) | `from XYZ PVT LTD` (I) | `.`, ` Avl` |

Aggregator prefixes glue onto the merchant and must be split, not deleted:
`IND*Amazon.in`, `EBA*MF-AXIS`, `BIL*ONL*`, `POS*`, `PAYU ZOMATO`, `RAZORPAY*`, `Mintoak`.
Store `merchantRaw` (verbatim) and `merchant` (cleaned) separately.

### 2.9 Reference IDs

| Label | Pattern | Notes |
|---|---|---|
| `UPI Ref No 621847362514` | `UPI\s*Ref(?:\s*No)?\.?\s*[:\-]?\s*(\d{9,18})` | most common |
| `UPI Ref: 432198765` | same regex | colon variant |
| `UPI:403988611918` | `UPI\s*[:\-]\s*(\d{9,18})` | ICICI |
| `Info:UPI-933716309044` | `UPI[-/](\d{9,18})` | ICICI |
| `Ref 559274810022` | `\bRef\b\.?\s*[:\-]?\s*([A-Z0-9]{6,22})` | ICICI UPI |
| `IMPS Ref no MO17335372` | `IMPS\s*Ref(?:\s*no)?\.?\s*[:\-]?\s*([A-Z0-9]{6,22})` | SBI |
| `Txn#2699` | `Txn\s*#?\s*[:\-]?\s*([A-Z0-9]{4,22})` | SBI ATM |
| `trip number 909451149` | `trip\s*(?:number|no)\.?\s*(\d{6,})` | FASTag |
| `RRN 123456789012` | `RRN\s*[:\-]?\s*(\d{12})` | (I) card/ATM |
| `UTR: HDFC1234567890` | `UTR\s*[:\-]?\s*([A-Z0-9]{10,22})` | NEFT/RTGS (I) |
| `order id YZDPEN6D1895` | `order\s*id\s*[:\-]?\s*([A-Z0-9]{6,})` | CRED |
| `Ref No N123456789012` | generic `Ref(?:erence)?\s*(?:No|#|:)?\.?\s*([A-Z0-9]{6,22})` | NEFT |

Normalize: upper-case, strip spaces/hyphens; keep as opaque string. **Never** treat a reference
as an amount; some are 12–18 digits and will otherwise beat real amounts in a naive regex.

### 2.10 Balance / limit labels

| Label | Meaning | Surface |
|---|---|---|
| `Avl Bal`, `Avl. bal.`, `Avl bal`, `Avl Bal is` | account available balance | `Avl Bal Rs.12,340.55` |
| `Available Balance` | account balance | `The Available Balance is INR 51,388.62` |
| `Avl Lmt`, `Avl lmt` | **credit-card available limit** | `Avl Lmt: INR 4,33,288.04` |
| `Available Limit` | credit-card available limit | `Available Limit: INR 62,762.76` |
| `Total Credit Limit`, `Credit Limit` | sanctioned limit | `Total Credit Limit: Rs.1,50,000.00` (I) |
| `Outstanding`, `Total Outstanding`, `Unbilled` | card outstanding | statement/due reminders (I) |
| `Total Amount Due`, `Minimum Amount Due`, `Min Amt Due`, `Due Date` | bill metadata | statement SMS (I) |
| `Avl. bal. is Rs` | FASTag wallet balance | `Avl. bal. is Rs 689.27` |

Label-to-field mapping must be **per instrument**: `Avl Bal` on an account row is
`balanceAfterPaise`; `Avl Lmt`/`Available Limit` on a card row is `availableLimitPaise`;
`Avl bal` on a Kotak *card* row is treated as available limit (issuer-specific override).

### 2.11 Date & time surfaces

`03-08-26`, `12-Jun-21`, `08-Jul-23`, `02Aug26`, `12-05-2024`, `17-Sep-21`, `04-Aug-26`,
`221216` (ddMMyy), `08/03/2020`, `on 18-04-2021 14:36:49`, `01-08-26 19:22`, `12:17PM IST`.

Rules: day-first (no observed Indian bank uses month-first); 2-digit year pivot at ±20 years from
the SMS `receivedAt` (`26` ⇒ 2026, `16` ⇒ 2016); timezone Asia/Kolkata; if only a date is present,
stamp the SMS received time for ordering and mark `dateConfidence: low`.

### 2.12 Footer / disclaimer stripping

Cut everything after the first of these (case-insensitive) when extracting merchant/amount tails:
`Call `, `To dispute`, `SMS BLOCK`, `Not you?`, `if not you`, `in case of dispute`, `T&C`,
`Plz download`, `Free `, `For more details`, `Never share`, `Bank NEVER asks`, `-HDFC Bank`
(brand sign-off), `-Axis Bank`, `-ICICI Bank`, `-SBI`.

Keep the footer for fraud signals (`SMS BLOCK <last4>` reveals the masked card, and
`Call 1800...` numbers are a useful bank fingerprint), but never let footer digits become amounts.

### 2.13 Instrument + direction resolution table (practical precedence)

1. OTP/promo/reminder markers ⇒ **reject** (§7) before anything else.
2. `credited` as the **first** verb ⇒ `income` (unless `credit card` + `payment ... received`,
   which is a card bill payment ⇒ `transfer`, see §6).
3. `debited` / `spent` / `withdrawn` first ⇒ `expense`.
4. `to VPA` / `P2A` / `IMPS` / `NEFT` / `RTGS` / `self` ⇒ `transfer` (still an outflow; keep
   `direction: transfer` and let the spend engine decide whether it counts).
5. Instrument: explicit `Credit Card` > `Debit Card` > `ATM` > `UPI`/VPA > `a/c` > `wallet`.

---

## 3. Per-bank / per-issuer templates

Notation: `{amt}` = amount, `{acct}` = account mask, `{card}` = card mask, `{merchant}`,
`{vpa}`, `{ref}`, `{date}`, `{bal}` = balance, `{limit}` = available limit. A row's template is
the **verbatim shape** with variable slots substituted; wording, punctuation and ordering are
what matter.

### 3.1 HDFC Bank (account / UPI / debit card)

| Intent | Template (verbatim shape) | Tokens to extract | Tier |
|---|---|---|---|
| UPI P2M debit | `Rs.120.00 debited from a/c **4821 on 03-08-26 to VPA chaipoint@ybl (UPI Ref No 621847362514). Not you? Call 18002586161.` | amt, acctLast4, vpa, ref, merchant(from VPA), date | **V** |
| UPI debit, explicit sent-form | `Sent Rs.{amt} from HDFC Bank A/c *{acct} to {merchant} on {date}. UPI Ref: {ref}.` | amt, acct, merchant, ref | **I** |
| Debit card POS/ECOM | `Rs.{amt} spent on your HDFC Bank Debit Card ending {card} at {merchant} on {date}. Avl Bal Rs.{bal}.` | amt, cardLast4, merchant, bal | **I** |
| Debit card, "txn" form | `Txn of Rs.{amt} on your HDFC Bank Debit Card ending {card} at {merchant} on {date}. Avl Bal Rs.{bal}.` | same | **I** |
| ATM withdrawal | `Rs.{amt} withdrawn from ATM using your HDFC Bank Debit Card ending {card} at {location} on {date}. Avl Bal Rs.{bal}.` | amt, cardLast4, location, bal | **I** |
| NEFT/IMPS out | `Rs.{amt} debited from your HDFC Bank A/c **{acct} on {date} to {beneficiary} (NEFT Ref {ref}). Avl Bal Rs.{bal}.` | amt, acct, beneficiary, ref, bal | **I** |
| Credit (salary/IMPS) | `Rs.{amt} credited to your HDFC Bank A/c **{acct} on {date} (NEFT Ref {ref}). Avl Bal Rs.{bal}.` | amt, acct, ref, bal | **I** |
| Reversal | `Rs.{amt} has been reversed to your a/c **{acct} on {date} for UPI Ref No {ref}. Avl Bal Rs.{bal}. -HDFC Bank` | amt, acct, ref | **I** |
| UPI Lite debit | `Rs.{amt} debited from UPI Lite (a/c **{acct}) to VPA {vpa} on {date}. UPI Ref No {ref}. UPI Lite balance Rs.{bal}.` | amt, acct, vpa, ref, lite-balance → **wallet**, not account balance | **I** |

HDFC notes observed in corpus: HDFC also sends service/promo SMS from `VKHDFCBN`
(`... HDFC Bank is now compliant with RBI e-mandate framework w.e.f. Oct 1. Register using HDFC
Bank Credit card for recurring payment/subscription ...` — **O**), which must never be parsed as
a transaction. HDFC's UPI help line `18002586161` and card line `18002586161 / 18602676161` are
useful fingerprint strings.

### 3.2 HDFC Bank credit card

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| Spend | `Rs.{amt} spent on your HDFC Bank Credit Card ending {card} at {merchant} on {date}. Avl Lmt: Rs.{limit}.` | amt, cardLast4, merchant, limit | **I** |
| Spend (UPI on RuPay CC) | `Rs.{amt} debited from your HDFC Bank Credit Card ending {card} to VPA {vpa} on {date}. Avl Lmt: Rs.{limit}.` | amt, cardLast4, vpa, limit | **I** |
| Bill payment received | `Thank you for your payment of Rs.{amt} towards your HDFC Bank Credit Card ending {card}. Your available limit is now Rs.{limit}.` | amt, cardLast4, limit | **I** |
| Statement generated | `Your HDFC Bank Credit Card statement for {month} is ready. Total Amount Due: Rs.{amt}, Minimum Amount Due: Rs.{min}, Due Date: {date}.` | totalDue, minDue, dueDate (**no transaction**) | **I** |
| Limit enhancement offer | `Congratulations! Your HDFC Bank Credit Card limit has been enhanced to Rs.{limit}.` | limit only | **I** |

### 3.3 ICICI Bank (account / UPI / FASTag) — best-evidenced issuer in the corpus

| Intent | Template (verbatim shape) | Tokens | Tier |
|---|---|---|---|
| UPI debit (compact) | `Rs 320.00 debited from A/c XX742 on 04-Aug-26 UPI:swiggy@icici Ref 559274810022. Call 18002662 for dispute.` | amt, acct, vpa, ref | **V** |
| UPI P2M, "and X credited" form | `Acct XXX702 debited with INR42.97 on 03-Dec-19 and bharatpe09899148115@yesbankltd credited.Info:UPI-933716309044.Call 18002662 for dispute or SMS BLOCK 696 to 5900232221` | amt, acct, counterparty VPA, ref (`UPI-…`) | **O** |
| UPI P2A to another bank | `ICICI Bank Acct XX240 debited for Rs 459.00 on 08-Feb-24; Axis credited. UPI:403988611918. Call 18002662 for dispute. SMS BLOCK 696 to 7668709542.` | amt, acct, counterparty bank, ref; direction **transfer** | **O** |
| Account debit, generic | `ICICI Bank Acc XX678 debited Rs. 035.43 on 06-Oct-24 InfoBIL*000910062.Avl Bal Rs. 05,547.61.To dispute call 18002662 or SMS BLOCK 696 to 7459648006` | amt (`035.43`), acct, `Info` payload, bal | **O** |
| Account debit, "with INR" | `ICICI Bank Acc XX987 debited with INR 3,880.38 on 01-Feb-23. Info:BIL*ONL*00059.Avl Bal is INR 94,352.85. For dispute Call 18002662 or SMS BLOCK 696 to 9226986464` | amt, acct, bal | **O** |
| Account debit, NEFT bill | `ICICI Bank Acc XX554 debited Rs. 2,90,812.17 on 29-Sep-23 InfoBIL*NEFT*HS92.Avl Bal Rs. 2,76,179.55.To dispute call 18002662 or SMS BLOCK 696 to 1091719546` | amt, lakh grouping, `BIL*NEFT` ⇒ bill pay | **O** |
| Account debit, investment | `ICICI Bank Acc XX341 debited with INR 7,874.69 on 04-May-23. Info:EBA*NSE M 202.Avl Bal is INR 5,61,986.95. ...` | amt, acct, `EBA*` ⇒ market/broker leg | **O** |
| FASTag toll debit | `Dear Customer, ICICI Bank FASTag linked vehicle no. WT59XG4509 has been debited with Rs 70.25 on 18-04-2021 14:36:49 for toll charges with trip number 909451149 at Devanahalli Toll Plaza Plaza on 18-04-2021 14:31:50. Avl. bal. is Rs 689.27. Call 18002100104 in case of dispute.` | amt, vehicleNo, tripNo, plaza, wallet bal | **O** |
| Account credit | `Dear Customer, your ICICI Bank Account XX963 has been credited with INR 5,567.11 on 17-Sep-21. Info:EBA*MF-AXIS A-109012205*20210917113. The Available Balance is INR 51,388.62.` | amt, acct, bal, `Info` | **O** |
| Standing-instruction due | `Dear Customer, your payment of Rs 610.64 for Youtube, as per Standing Instruction VkiVm1jJlQ, is due by 18/05/2022 and will be debited through your ICICI Bank Credit Card 5444. ...` | amt, merchant `Youtube`, card 5444, dueDate; **reminder — not a txn** | **O** |
| Card txn OTP | `208716 is OTP for txn of INR 507.71 at GOOGLEPLAY on ICICI Bank Debit Card XX1566.OTPs are SECRET.DO NOT disclose it to anyone.Bank NEVER asks for OTP.` | OTP + amt + merchant; **never a transaction** | **O** |
| FASTag activation | `Dear Customer, your ICICI Bank FASTag Customer ID 16219891 has been activated on 07/09/2021 16:30:07.You can start using your Tag immediately after you receive it.` | none | **O** |

ICICI grammar notes: `Info` payload is a **codesphere**: `BIL*` = bill payment (BillDesk/BBPS),
`ONL*` = online bill, `NEFT*` = NEFT-funded bill, `EBA*` = e-broking/merchant aggregator,
`MF-` = mutual fund, `UPI-` / `UPI/P2A` = UPI. `SMS BLOCK <last4>` footer repeats the masked card.

### 3.4 ICICI Bank credit card

| Intent | Template (verbatim shape) | Tokens | Tier |
|---|---|---|---|
| Spend (spent form) | `INR 366.19 spent on ICICI Bank Card XX2815 on 08-Jul-23 at IND*Amazon.in. Avl Lmt: INR 4,33,288.04. To dispute,call 18002662/SMS BLOCK 7007 to 8679723604` | amt, cardLast4, merchant (`IND*Amazon.in` → `Amazon.in`), limit | **O** |
| Spend (debited form) | `Dear Customer, INR 7,689.62 is debited on ICICI Bank Credit Card XX5533 on 12-Jun-21. Info: Swiggy. Available Limit: INR 62,762.76. Call on 18002662 for dispute or SMS BLOCK 7007 to 8891385501.` | amt, cardLast4, merchant from `Info`, limit | **O** |
| Spend (merchant in Info + Avl Lmt) | `INR 647.80 spent on ICICI Bank Card XX6123 on 17-Jan-24 at TW Coffee  HSR. Avl Lmt: INR 5,22,275.66. To dispute,call 18002662/SMS BLOCK 7007 to 1040563688` | amt, card, merchant, limit | **O** |
| Refund to card | `INR {amt} credited to your ICICI Bank Credit Card XX{card} on {date} towards refund from {merchant}. Available Limit: INR {limit}.` | amt, card, merchant, limit | **I** |
| Bill payment received | `Payment of INR {amt} has been received towards your ICICI Bank Credit Card XX{card}. Available Limit: INR {limit}.` | amt, card, limit ⇒ **card bill, not income** | **I** |

Note the **two different verbs ICICI uses for the same event**: `spent on` and `is debited on`.
Both must map to `expense` + `creditCard`.

### 3.5 State Bank of India (account / UPI / ATM / debit card)

| Intent | Template (verbatim shape) | Tokens | Tier |
|---|---|---|---|
| Debit card ECOM/POS | `Dear Customer, Rs.849.00 spent on SBI Debit Card ending 5522 at AMAZON PAY INDIA on 02Aug26. Avl Bal Rs.12,340.55.` | amt, cardLast4, merchant, bal | **V** |
| UPI credit | `Rs 87.38 credited to account XXXXX1710 of SBIN linked to dazzlingarun2@okaxis on 2017-11-02. Info: UPI/P2A/730609020693/imgauti3@okhdfcbank` | amt, acct, sender VPA, `P2A`, ref | **O** |
| IMPS debit (dual-account phrasing) | `Your a/c no. XXXXXXXX1710 is debited for Rs.986.93 on 10-11-16 and a/c XXXXXXX133 credited (IMPS Ref no MO17335372).` | amt, acct, IMPS ref; first verb governs | **O** |
| ATM withdrawal | `Rs 0368 withdrawn at SBG ATM  S10F200912001  SBH-ACC LTD-MANCHERIAL , MANCHERIAL from A/c xxxx 1710 on 221216.Txn#2699 .Avl bal Rs 76874.33. Free SBG ATM txns if AMB>25000.` | amt, ATM id, location, acct, txn ref, bal | **O** |
| UPI debit | `Dear Customer, Your A/c XXXXX{acct} has been debited by Rs.{amt} on {date}. Info: UPI/{ref}/{vpa}. Avl Bal Rs.{bal}.` | amt, acct, ref, vpa, bal | **I** |
| NEFT/RTGS credit | `Your A/c XXXXX{acct} has been credited with Rs.{amt} on {date} by NEFT (UTR: {utr}). Avl Bal Rs.{bal}.` | amt, acct, utr, bal | **I** |
| Cheque debit | `Your A/c XXXXX{acct} has been debited by Rs.{amt} on {date} towards cheque no. {cheque}. Avl Bal Rs.{bal}.` | amt, acct, chequeNo | **I** |
| Branch/charges debit | `Your AC XXXXX301710 Debited INR 18.39 on 05/11/16 -CDM CHARGE DR . Avl Bal INR 09,573.28.Plz download Buddy` | amt, acct, `CDM CHARGE` (fee) | **O** |

SBI notes: `SBIN` appears as the bank identifier in the UPI-credit template; `SBG`/`SBH` are
SBI-group ATM/account labels (State Bank of Hyderabad legacy). SBI ATM SMS uses `ddMMyy`
(`221216`) and a 4-character `Txn#` reference.

### 3.6 SBI Card (credit card, separate issuer)

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| Spend | `Rs.{amt} spent on your SBI Credit Card ending {card} at {merchant} on {date}. Available Limit: Rs.{limit}.` | amt, card, merchant, limit | **I** |
| Payment received | `Thank you for your payment of Rs.{amt} towards your SBI Card ending {card}. Your available limit is now Rs.{limit}.` | amt, card, limit | **I** |
| Statement/due | `Your SBI Card statement is ready. Total Amount Due Rs.{amt}, Minimum Due Rs.{min}, Due Date {date}.` | metadata only | **I** |

### 3.7 Axis Bank (account / UPI)

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| UPI collect request (**not a txn**) | `SWIGGY BUSINESS has requested money from you on your Amazon app. On approving the request, INR 2856.15 will be debited from your A/c. To approve, visit http://amzn.in/4YvMefq - Axis Bank` | amt, merchant, conditional verb | **O** |
| UPI debit | `INR {amt} debited from your Axis Bank A/c XX{acct} on {date} to {vpa}. UPI Ref No {ref}. Avl Bal INR {bal}.` | amt, acct, vpa, ref, bal | **I** |
| Card spend (debit) | `INR {amt} spent on Axis Bank Card XX{card} at {merchant} on {date} {time}. Avl Lmt INR {bal}. SMS BLOCK {last4} to 918691000002 if not you.` | amt, card, merchant, bal | **V-ish** (body shape from Axis card sample, issuer word "Debit" assumed) |
| Account credit | `INR {amt} credited to your Axis Bank A/c XX{acct} on {date}. Avl Bal INR {bal}.` | amt, acct, bal | **I** |

The Axis "requested money" template is the single most important **false positive** in the corpus:
it has an amount, a merchant and the word `debited`, but is a *pending collect request*.

### 3.8 Axis Bank credit card

| Intent | Template (verbatim) | Tokens | Tier |
|---|---|---|---|
| Spend | `INR 2,000.00 spent on Axis Bank Card XX931 at INDIAN OIL SVC STN on 01-08-26 19:22. Avl Lmt INR 48,250.00. SMS BLOCK 931 to 918691000002 if not you.` | amt, card mask **3 digits**, merchant, avl limit, time | **V** |
| Spend variant | `INR {amt} spent on your Axis Bank Credit Card XX{card} at {merchant} on {date}. Available limit INR {limit}.` | same | **I** |
| Payment received | `Payment of INR {amt} received towards your Axis Bank Credit Card XX{card}. Available limit INR {limit}.` | amt, card, limit | **I** |

### 3.9 Kotak Mahindra Bank (account/UPI/debit)

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| UPI debit | `Sent Rs.{amt} from your Kotak A/c XX{acct} to {vpa} on {date}. UPI Ref {ref}. Avl Bal Rs.{bal}.` | amt, acct, vpa, ref, bal | **I** |
| Debit card spend | `Rs.{amt} spent on your Kotak Debit Card XX{card} at {merchant} on {date}. Avl Bal Rs.{bal}.` | amt, card, merchant, bal | **I** |
| Credit | `Rs.{amt} credited to your Kotak A/c XX{acct} on {date}. Avl Bal Rs.{bal}.` | amt, acct, bal | **I** |

### 3.10 Kotak credit card

| Intent | Template (verbatim) | Tokens | Tier |
|---|---|---|---|
| Spend | `Rs.560.00 spent on Kotak Card x2210 at BOOKMYSHOW on 03-08-2026. Avl bal Rs.8,904.12. Not you? Call 18602662666.` | amt, cardLast4, merchant, **`Avl bal` = available limit** | **V** |
| Spend variant | `Rs.{amt} spent on your Kotak Credit Card ending {card} at {merchant} on {date}. Avl lmt Rs.{limit}.` | same | **I** |
| Payment received | `Payment of Rs.{amt} received towards your Kotak Credit Card ending {card}. Avl lmt Rs.{limit}.` | amt, card, limit | **I** |

### 3.11 IDFC FIRST Bank

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| UPI debit | `INR {amt} debited from your IDFC FIRST Bank A/c XX{acct} on {date} to {vpa}. UPI Ref No {ref}. Avl Bal INR {bal}.` | amt, acct, vpa, ref, bal | **I** |
| Debit card spend | `INR {amt} spent on your IDFC FIRST Bank Debit Card XX{card} at {merchant} on {date}. Avl Bal INR {bal}.` | amt, card, merchant, bal | **I** |
| Credit card spend | `INR {amt} spent on your IDFC FIRST Bank Credit Card XX{card} at {merchant} on {date}. Available limit: INR {limit}.` | amt, card, merchant, limit | **I** |
| Credit card payment | `Payment of INR {amt} received towards your IDFC FIRST Bank Credit Card XX{card}. Available limit: INR {limit}.` | amt, card, limit | **I** |

### 3.12 AU Small Finance Bank

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| UPI debit | `Rs.{amt} debited from your AU Small Finance Bank A/c XX{acct} on {date} to {vpa}. UPI Ref No {ref}. Avl Bal Rs.{bal}.` | amt, acct, vpa, ref, bal | **I** |
| Debit card spend | `Rs.{amt} spent on your AU Bank Debit Card XX{card} at {merchant} on {date}. Avl Bal Rs.{bal}.` | amt, card, merchant, bal | **I** |
| Credit card spend | `Rs.{amt} spent on your AU Bank Credit Card XX{card} at {merchant} on {date}. Available limit Rs.{limit}.` | amt, card, merchant, limit | **I** |

AU's public documents (citizen charter, MITC) confirm the brand tokens `AU Bank` / `AU Small
Finance Bank` but publish no alert templates — all AU rows are inferred.

### 3.13 RBL Bank

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| Debit card / UPI | `Rs.{amt} spent on your RBL Bank Debit Card XX{card} at {merchant} on {date}. Avl Bal Rs.{bal}.` | amt, card, merchant, bal | **I** |
| Credit card spend | `Rs.{amt} spent on your RBL Bank Credit Card XX{card} at {merchant} on {date}. Available limit Rs.{limit}.` | amt, card, merchant, limit | **I** |

### 3.14 Yes Bank

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| UPI debit | `Rs.{amt} debited from your Yes Bank A/c XX{acct} on {date} to {vpa}. UPI Ref No {ref}. Avl Bal Rs.{bal}.` | amt, acct, vpa, ref, bal | **I** |
| Credit card | `Rs.{amt} spent on your Yes Bank Credit Card XX{card} at {merchant} on {date}. Available limit Rs.{limit}.` | amt, card, merchant, limit | **I** |

Note: `@yesbankltd` VPAs are common for merchant collections (observed in the ICICI P2M row), so
`yesbank` inside a body does **not** imply the alert came from Yes Bank.

### 3.15 IndusInd Bank

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| Debit card / UPI | `Rs.{amt} spent on your IndusInd Bank Debit Card XX{card} at {merchant} on {date}. Avl Bal Rs.{bal}.` | amt, card, merchant, bal | **I** |
| Credit card | `Rs.{amt} spent on your IndusInd Bank Credit Card XX{card} at {merchant} on {date}. Available limit Rs.{limit}.` | amt, card, merchant, limit | **I** |

### 3.16 Federal Bank / SBM Bank (Niyo, Jupiter, Fi rails)

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| Niyo Global card spend (SBM) | `Rs.{amt} spent on your Niyo Card XX{card} at {merchant} on {date}. Avl Bal Rs.{bal}.` | amt, card, merchant, bal | **I** |
| Niyo forex spend | `USD {fx} (INR {amt}) spent on your Niyo Card XX{card} at {merchant} on {date}.` | INR leg, FX leg | **I** |
| Federal account/UPI | `Rs.{amt} debited from your Federal Bank A/c XX{acct} on {date} to {vpa}. Avl Bal Rs.{bal}.` | amt, acct, vpa, bal | **I** |

Niyo is a **programme**, not an issuer: the SMS header is SBM/Federal, the brand word is `Niyo`.
Map instrument by the card word, and `cardIssuer` by the header, with `programme: niyo` metadata.

### 3.17 OneCard (CSB / Federal / SBM / SIB / IDFC FIRST)

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| Spend | `Rs.{amt} spent on your OneCard at {merchant} on {date}. Available limit Rs.{limit}. -OneCard` | amt, merchant, limit, no card mask (OneCard often omits last4) | **I** |
| Spend with mask | `Rs.{amt} spent on your OneCard ending {card} at {merchant} on {date}. Available limit Rs.{limit}.` | amt, card, merchant, limit | **I** |
| Payment received | `Payment of Rs.{amt} received towards your OneCard. Available limit is now Rs.{limit}.` | amt, limit | **I** |

OneCard's terms (Federal Bank [OneCard T&C](https://www.federalbank.co.in/documents/10180/58403423/OneCard+Credit+Card+Terms+and+Conditions.pdf)) confirm a pre-transaction notification
at least 24h before charge for some flows — those are reminders, not spends.

### 3.18 American Express India

| Intent | Template (verbatim) | Tokens | Tier |
|---|---|---|---|
| Spend | `Alert: You've spent INR 204.35 on your AMEX card **91009 at PAYU ZOMATO on 08/03/2020 at 12:17PM IST. Please call 18004190691 if this was not made by you.` | amt, **5-digit mask**, merchant `PAYU ZOMATO` (aggregator prefix), date+time | **O** |
| Spend variant | `You have used your American Express Card ending {5digits} for INR {amt} at {merchant} on {date}.` | same | **I** |
| Payment received | `Thank you for your payment of INR {amt}. Your American Express Card ending {5digits} available limit is INR {limit}.` | amt, mask, limit | **I** |

Amex is the only observed issuer that masks **5** digits — never truncate a 5-digit mask to 4
before storing, and dedupe Amex against a 4-digit row only via amount+time+merchant.

### 3.19 Standard Chartered / HSBC / Citi

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| Fraud-awareness broadcast (**never a txn**) | `Beware of fraudsters calling to lure you with fictitious job offers and asking for payment in return. ... do not share the PIN, login ID, password, OTP, debit card/credit card details etc. with anyone. To know more, visit https://nc6.in/dc9Ml4 - StanChart` | none | **O** |
| Card spend | `INR {amt} spent on your Standard Chartered Card XX{card} at {merchant} on {date}. Available limit INR {limit}.` | amt, card, merchant, limit | **I** |
| HSBC/Citi card spend | `Your HSBC Credit Card XX{card} was used for INR {amt} at {merchant} on {date}. Available limit INR {limit}.` | same | **I** (npm lists both as tested) |

Citi's India retail card portfolio moved to Axis in 2023–24; expect legacy Citi senders
(`CITI`, `CITIBK`) during the migration window.

### 3.20 CRED (card bill payments / cashback)

| Intent | Template (verbatim) | Tokens | Tier |
|---|---|---|---|
| Card payment received (full PAN mask) | `Payment of INR 90,885 was received for your ICICI Bank credit card 7121-81XX-XXXX-7007 JB 40-KII-6855 and you have earned 51,000 CRED coins. Your order id is YZDPEN6D1895. Payment will be credited to credit card account within the next 1 hour.` | amt, issuer (`ICICI Bank`), last4 `7007`, BIN `712181`, order id, coins | **O** |
| Card payment received (short mask) | `Payment of INR 8,591 was received for card number XX-7007 HZ 86-WWB-1407 and you have earned 5,436 CRED coins. Payment will reflect in your credit card account in max 48 hours. 3K1L2RVN0K is your order id.` | amt, last4, order id | **O** |
| Cashback (future promise) | `Congratulations! You won INR 6 cashback. We will deposit it into your credit card XXX-6314 in the next 7 days.` | amt, last4, **future tense ⇒ do not book yet** | **O** |
| Cashback (bill-kill promo) | `Congratulations! You've Won! You have killed your bill by INR 50 . We will deposit INR 62 into your credit card XX-1101 in the next 7 days.` | two amounts (savings + cashback) | **O** |

CRED is **not** a bank: its messages are card-side confirmations. The payment reduces card
outstanding; the CRED coin/`won INR` amounts are marketing and must never be booked as income.

### 3.21 Slice, LazyPay, Simpl, Uni (BNPL / card-like)

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| BNPL spend | `Rs.{amt} spent using your Slice card at {merchant} on {date}.` | amt, merchant | **I** |
| Bill repayment | `Payment of Rs.{amt} received towards your Slice bill. Thank you.` | amt ⇒ card bill, not income | **I** |
| LazyPay | `Your LazyPay transaction of Rs.{amt} at {merchant} is successful.` | amt, merchant | **I** |
| Simpl | `Rs.{amt} paid to {merchant} via Simpl. Pay by {date}.` | amt, merchant, dueDate | **I** |

BNPL messages are frequently sent by the **merchant** with the BNPL brand in the body; treat
`instrument: creditCard` with `issuer: slice/lazypay/simpl` and a `bnpl` subtype.

### 3.22 Wallets and UPI PSPs

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| Amazon Pay wallet debit (real, observed) | `Your payment on Amazon.in for Rs. 96.08 using Amazon Pay balance is successful. Your balance is now Rs. 3.82. For help/stmt: www.amazon.in/cstxn` | amt, balance, merchant=Amazon.in | **O** |
| Amazon Pay refund to wallet | `Your refund of Rs. 96.08 for order 402-1234567-1234567 has been credited to your Amazon Pay balance.` | amt | **I** |
| PhonePe debit | `Rs {amt} paid to {merchant} via PhonePe. UPI Ref {ref}.` | amt, merchant, ref | **I** |
| Paytm wallet debit | `Rs.{amt} paid to {merchant} using Paytm. Balance Rs.{bal}.` | amt, merchant, bal | **I** |
| Wallet top-up (from bank) | `Rs.{amt} added to your Paytm Wallet from A/c XX{acct}.` | amt ⇒ **transfer**, not expense | **I** |

Reality check: PhonePe/Google Pay/Paytm mostly notify **in-app** (notification, not SMS). Android
`NotificationListenerService` reading is a separate corpus and must be de-duplicated against SMS
(§8); the SMS corpus only contains wallet SMS for a minority of flows.

### 3.23 PSU banks (PNB, BoB, Canara, Union, Bank of India)

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| PNB UPI debit | `Dear Customer, Rs.{amt} has been debited from your A/c XXXXX{acct} on {date} to {vpa} (UPI Ref No {ref}). Avl Bal Rs.{bal}. -PNB` | amt, acct, vpa, ref, bal | **I** |
| BoB debit | `Rs.{amt} debited from your BoB A/c XX{acct} on {date}. Info: {merchant}. Avl Bal Rs.{bal}.` | amt, acct, merchant, bal | **I** |
| Canara debit | `Your a/c XX{acct} is debited with Rs.{amt} on {date} towards {merchant}. Balance Rs.{bal}.` | amt, acct, merchant, bal | **I** |
| Union Bank | `Rs.{amt} debited from your Union Bank A/c XX{acct} on {date} to {vpa}. Available Balance Rs.{bal}.` | amt, acct, vpa, bal | **I** |

PSU grammar is closest to SBI; reuse SBI token rules with brand-token mapping.

### 3.24 Payments banks & small finance banks

Paytm Payments Bank (now restricted), India Post Payments Bank, Airtel Payments Bank, Fino,
Jana, ESAF, Ujjivan, Equitas: same grammar family as §3.12/§3.23. No grounded templates; all
**I**. Alert headers typically `PAYTMB`, `IPPB`, `AIRTL`, `FINOBK`.

### 3.25 Co-operative / rural banks

District co-op banks often send **non-DLT** SMS from 10-digit numbers or use aggregator headers
(`QP…`). They frequently omit the mask and write `Your account is debited by Rs.{amt}` with no
account identifier. Policy: parse them, but `confidenceHint: low` and require user confirmation
before they affect budgets.

---

## 4. Cross-cutting intents (any issuer)

### 4.1 ATM / cash

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| ATM withdrawal (SBI) | see §3.5 | amt, atmId, location, acct, txn, bal | **O** |
| ATM withdrawal (generic) | `Rs.{amt} withdrawn from ATM at {location} on {date} using card ending {card}. Avl Bal Rs.{bal}.` | amt, location, card, bal | **I** |
| ATM decline | `Your ATM transaction of Rs.{amt} at {location} on {date} was declined. No amount has been debited.` | **never a txn** | **I** |
| Cash deposit (CDM) | `Rs.{amt} deposited to your A/c XX{acct} via CDM on {date}. Avl Bal Rs.{bal}.` | income | **I** |
| Bank charges | `Your AC XXXXX301710 Debited INR 18.39 on 05/11/16 -CDM CHARGE DR . Avl Bal INR 09,573.28.` | amt, fee subtype | **O** |

### 4.2 NEFT / IMPS / RTGS (out and in)

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| IMPS out (SBI style) | `Your a/c no. XXXXXXXX{acct} is debited for Rs.{amt} on {date} and a/c {counterparty} credited (IMPS Ref no {ref}).` | amt, ref; **transfer** | **O** |
| NEFT out | `Rs.{amt} debited from A/c XX{acct} on {date} by NEFT to {beneficiary} (UTR {utr}). Avl Bal Rs.{bal}.` | amt, beneficiary, utr | **I** |
| RTGS out | `Rs.{amt} transferred from A/c XX{acct} on {date} via RTGS to {beneficiary} (UTR {utr}).` | amt, beneficiary, utr | **I** |
| NEFT in | `Rs.{amt} credited to A/c XX{acct} on {date} by NEFT from {remitter} (UTR {utr}). Avl Bal Rs.{bal}.` | amt, remitter, utr | **I** |
| IMPS in | `INR {amt} received in your A/c XX{acct} on {date} via IMPS from {remitter}. Avl Bal INR {bal}.` | amt, remitter, bal | **I** |

### 4.3 Cheque

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| Cheque debit | `Your A/c XX{acct} has been debited by Rs.{amt} on {date} towards cheque no. {cheque}. Avl Bal Rs.{bal}.` | amt, chequeNo | **I** |
| Cheque return charge | `Rs.{amt} debited towards cheque return charges for cheque {cheque} on {date}.` | amt, fee | **I** |
| Cheque deposit credit | `Rs.{amt} credited to your A/c XX{acct} on {date} against cheque {cheque}. Avl Bal Rs.{bal}.` | amt, chequeNo | **I** |

### 4.4 Autopay / mandate / standing instruction / EMI

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| SI **due** (not executed) | `Dear Customer, your payment of Rs 610.64 for Youtube, as per Standing Instruction VkiVm1jJlQ, is due by 18/05/2022 and will be debited through your ICICI Bank Credit Card 5444. ...` | amt, merchant, dueDate, mandateRef | **O** |
| SI **executed** | `Rs.{amt} debited from your A/c XX{acct} on {date} towards Standing Instruction for {merchant}. Avl Bal Rs.{bal}.` | amt, merchant ⇒ **expense, recurring** | **I** |
| UPI AutoPay executed | `Rs.{amt} debited from your A/c XX{acct} on {date} via UPI AutoPay to {vpa}. UPI Ref {ref}. Avl Bal Rs.{bal}.` | amt, vpa, ref | **I** |
| UPI AutoPay mandate created | `UPI AutoPay mandate of Rs.{amt} created for {merchant}. First debit on {date}.` | metadata, **not a spend** | **I** |
| NACH debit | `Rs.{amt} debited from your A/c XX{acct} on {date} towards NACH mandate {umrn} of {merchant}. Avl Bal Rs.{bal}.` | amt, UMRN, merchant | **I** |
| NACH mandate registered | `NACH mandate {umrn} for Rs.{amt} registered for {merchant}. Debit date {date}.` | metadata | **I** |
| Card SI/e-mandate executed | `Rs.{amt} debited on your Credit Card XX{card} on {date} towards {merchant} subscription. Avl Lmt: Rs.{limit}.` | amt, card, merchant, limit | **I** |
| Loan EMI debit | `Rs.{amt} debited from your A/c XX{acct} on {date} towards EMI for loan {loanNo}. Avl Bal Rs.{bal}.` | amt, loanNo ⇒ expense, subtype emi | **I** |
| EMI conversion offer | `Convert your transaction of Rs.{amt} into EMI at {rate}% for {tenure} months.` | **offer, never a txn** | **I** |

### 4.5 International / forex

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| Forex card spend | `USD {fx} spent on your {bank} Forex Card ending {card} at {merchant} on {date}. INR {amt} debited.` | FX + INR legs | **I** |
| Credit card international spend | `USD {fx} (INR {amt}) spent on your {bank} Credit Card XX{card} at {merchant} on {date}. Avl Lmt: INR {limit}. Forex markup may apply.` | both legs, limit | **I** |
| International ATM | `INR {amt} withdrawn at {location}, {country} using card ending {card} on {date}. Avl Bal INR {bal}.` | amt, country | **I** |

Rule: for any SMS containing a non-INR currency token, use the **INR leg** as `amountPaise`;
store `fxAmount`, `fxCurrency`, and `fxRate` if derivable. If only the FX leg exists (`USD 12.99
spent ...`), compute an estimate and set `confidenceHint: low` — never silently treat USD as INR.

### 4.6 Wallet top-up, UPI Lite, FASTag

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| UPI Lite load | `Rs.{amt} loaded to UPI Lite from your A/c XX{acct} on {date}. UPI Lite balance Rs.{bal}.` | amt ⇒ **transfer to wallet**, not spend | **I** |
| UPI Lite spend | `Rs.{amt} debited from UPI Lite (a/c **{acct}) to VPA {vpa} on {date}. UPI Ref No {ref}. UPI Lite balance Rs.{bal}.` | amt ⇒ expense (wallet instrument) | **I** |
| FASTag top-up | `Rs.{amt} credited to your ICICI Bank FASTag linked vehicle {vehicle}. Avl. bal. is Rs.{bal}.` | amt ⇒ transfer to prepaid | **I** |
| FASTag toll (observed) | `Dear Customer, ICICI Bank FASTag linked vehicle no. {vehicle} has been debited with Rs {amt} on {date} for toll charges with trip number {trip} at {plaza} ... Avl. bal. is Rs {bal}.` | amt, vehicle, trip, plaza, wallet bal | **O** |
| FASTag low balance | `Your FASTag balance is low (Rs.{bal}). Recharge now.` | **not a txn** | **I** |
| Wallet top-up | `Rs.{amt} added to your {wallet} wallet from A/c XX{acct}.` | transfer | **I** |

UPI Lite is a **separate on-device wallet** on the same account: a Lite spend debits the Lite
balance, and later (or never, if the user tops up) a bank alert appears. Treat `UPI Lite` as
instrument `wallet` with `parentAccountLast4` so utilisation/budget math doesn't double count.

### 4.7 Income-side specials

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| Salary | `Your a/c XX{acct} is credited with Rs.{amt} on {date} by NEFT from {employer}. Avl Bal Rs.{bal}.` | amt, employer | **I** |
| Interest credit | `Rs.{amt} credited to your A/c XX{acct} towards interest for {period}.` | amt | **I** |
| Dividend | `Rs.{amt} credited to your A/c XX{acct} towards dividend from {company}.` | amt | **I** |
| Cashback credited | `Rs.{amt} cashback credited to your A/c XX{acct} on {date}.` | amt ⇒ income, subtype cashback | **I** |
| Reversal credited | `Rs.{amt} reversed to your card XX{card} on {date} for txn {ref}. Available limit now Rs.{limit}.` | amt, ref, limit | **I** |

---

## 5. Credit-card specifics

### 5.1 How limit and available limit appear

| Surface | Issuer examples | Field |
|---|---|---|
| `Avl Lmt: INR 4,33,288.04` | ICICI (**O**) | `availableLimitPaise` |
| `Available Limit: INR 62,762.76` | ICICI (**O**) | `availableLimitPaise` |
| `Avl Lmt INR 48,250.00` | Axis (**V**) | `availableLimitPaise` |
| `Avl bal Rs.8,904.12` | Kotak (**V**) — on a **card** | `availableLimitPaise` (issuer override) |
| `Available limit is now Rs.53,850.00` | payment confirmations (I) | `availableLimitPaise` |
| `Total Credit Limit: Rs.1,50,000.00` | statement/limit-change SMS (I) | `totalLimitPaise` |
| `Outstanding: Rs.{x}` / `Unbilled: Rs.{x}` | statement (I) | `outstandingPaise` |
| `Total Amount Due` / `Minimum Amount Due` / `Due Date` | statement (I) | bill metadata |

**Utilization model** (offline, no statements needed):

```
spendDelta    = availableLimitBefore - availableLimitAfter      // per card alert
utilization   = (totalLimitPaise - availableLimitPaise) / totalLimitPaise
```

Rules:

- If `totalLimitPaise` is unknown, do **not** guess from the first available limit — a user with
  50% utilisation would be modelled as having 0% headroom. Ask once (card setup screen) or infer
  `totalLimit = max(observed availableLimit)` and mark utilisation as a **lower bound**.
- Multiple cards: key by `(issuer, last4)`. Amex keys by 5-digit mask **and** last4.
- `availableLimitAfter` from a spend alert is authoritative for that instant; a later bill-payment
  confirmation raises it (recompute, don't add spend).
- Card payment messages are **not** spend: `(total - avail)` should drop by the payment amount.
  If a CRED payment is booked as a *transaction*, double counting is guaranteed (§6, §8).

### 5.2 Bill payments — the four distinct message families

| Family | Who sends | Example | Correct model |
|---|---|---|---|
| (a) Debit from your bank account to a card/BBPS | your **bank** | `ICICI Bank Acc XX678 debited Rs. 035.43 ... InfoBIL*000910062` (**O**) | `direction: expense` **but** `category: cardBill`; must not count as consumption |
| (b) Payment received by the issuer | **card issuer** | `Thank you for your payment of Rs.{amt} towards your ... Card ending {card}. Available limit is now Rs.{limit}.` (I) | reduces outstanding; `direction: transfer` |
| (c) Payment routed via CRED/Cheq/BillDesk/BBPS | **third party** | `Payment of INR 90,885 was received for your ICICI Bank credit card 7121-81XX-XXXX-7007 ...` (**O**, CRED) | same as (b), plus `channel: cred` |
| (d) Bill due / statement | issuer | `Total Amount Due: Rs.{x}, Minimum Amount Due: Rs.{y}, Due Date: {d}` (I) | **reminder only, no transaction** |

Matching rule for the four: a card bill payment produces up to 3 messages (bank debit, BBPS/CRED
confirmation, issuer "payment received"). Dedupe them into **one** `cardPayment` event with
`amountPaise`, `cardLast4`, `fromAccountLast4`, `channel`.

### 5.3 Statement generation

Template (I): `Your {issuer} Credit Card statement for {month} has been generated. Total Amount
Due: Rs.{total}, Minimum Amount Due: Rs.{min}, Due Date: {date}.` — carries **no transaction**;
it updates `statementTotalDuePaise`, `minDuePaise`, `dueDate` and (if present) `totalLimitPaise`.

### 5.4 Min-due / due-date reminders

`Your {issuer} Card payment of Rs.{min} is due on {date}. Pay now to avoid late fees.` — reminder;
must not create a spend, but should raise a UI nudge and must not be treated as an income either.

### 5.5 EMI conversion

Two shapes, opposite meanings:

- Offer: `Convert your transaction of Rs.{amt} into EMI at {rate}% for {tenure} months.` ⇒ **no txn**.
- Executed: `Rs.{amt} debited towards EMI conversion of txn {ref}. Avail limit restored by Rs.{amt}.`
  ⇒ expense (subtype `emi`) + limit restoration.

### 5.6 Forex markup mentions

`Forex markup of {pct}% applies on international transactions.` — metadata only. If a spend SMS
contains both a foreign amount and an INR amount, the INR amount **already includes** markup in
observed card alerts; do not apply markup again.

---

## 6. Credit / inflow templates & reversals

| Intent | Template | Tokens | Tier |
|---|---|---|---|
| UPI credit (SBI) | `Rs 87.38 credited to account XXXXX1710 of SBIN linked to dazzlingarun2@okaxis on 2017-11-02. Info: UPI/P2A/730609020693/imgauti3@okhdfcbank` | amt, acct, sender VPA, ref | **O** |
| Account credit (ICICI) | `Dear Customer, your ICICI Bank Account XX963 has been credited with INR 5,567.11 on 17-Sep-21. Info:EBA*MF-AXIS A-109012205*20210917113. The Available Balance is INR 51,388.62.` | amt, acct, `Info`, bal | **O** |
| Salary/IMPS credit | `Rs.{amt} credited to your A/c XX{acct} on {date} by NEFT from {employer} (UTR {utr}). Avl Bal Rs.{bal}.` | amt, employer, utr | **I** |
| Refund to card | `INR {amt} has been credited to your ICICI Bank Credit Card XX{card} on {date} towards refund from {merchant}. Available Limit: INR {limit}.` | amt, card, merchant, limit | **I** |
| Reversal to account | `Rs.{amt} has been reversed to your a/c **{acct} on {date} for UPI Ref No {ref}. Avl Bal Rs.{bal}.` | amt, acct, ref | **I** |
| Chargeback credit | `Credit of Rs.{amt} received in your a/c XX{acct} on {date} against UPI chargeback Ref {ref}.` | amt, ref | **I** |
| Cashback (deferred promise) | `Congratulations! You won INR 6 cashback. We will deposit it into your credit card XXX-6314 in the next 7 days.` | amt, card, **future tense** | **O** |
| Cashback credited | `Rs.{amt} cashback credited to your A/c XX{acct} on {date}.` | amt | **I** |
| Wallet refund | `Your refund of Rs. 96.08 for order 402-1234567-1234567 has been credited to your Amazon Pay balance.` | amt, orderId | **I** |
| Failed-payment auto-reversal | `Rs.{amt} debited on {date} has been reversed. Avl Bal Rs.{bal}.` | amt | **I** |
| Refund **initiated** (not yet money) | `Refund of Rs.{amt} for order {id} has been initiated by {merchant}. It will be credited within {n} days.` | **no txn** | **I** |

Booking rules:

1. `refund`/`reversal`/`chargeback` ⇒ **negative expense against the original category**, not
   income — unless the original transaction is unknown, in which case `income` with
   `subtype: refund`.
2. A refund may arrive weeks later and for a different amount (partial). Match by
   `(merchant, amount, last4)` first, then `(merchant, last4)` with a tolerance window of 90 days.
3. `will deposit` / `will be credited` / `has been initiated` ⇒ **pending**, no ledger entry.
   Promote to a real credit only when a `credited`/`received` message arrives.
4. Refund to a **credit card** does not increase bank balance; it increases available limit.
   Model it as a card-side credit (`availableLimitPaise += amt`) and as negative spend.

---

## 7. Never-a-transaction catalogue

Hard negatives. A parser that books any of these is worse than no parser.

| Category | Observed / typical wording (verbatim where possible) | Killer tokens |
|---|---|---|
| **OTP (bank/card txn)** | `208716 is OTP for txn of INR 507.71 at GOOGLEPLAY on ICICI Bank Debit Card XX1566.OTPs are SECRET.DO NOT disclose it to anyone.Bank NEVER asks for OTP.` (**O**) | `OTP`, `one time password`, `verification code`, `DO NOT disclose` |
| **OTP (login/KYC/e-sign)** | `515229 is the OTP to login to your ICICI direct account. ...` (**O**), `OTP for Aadhaar (XX1111) e-sign at HDFC Bank is 983712. ...` (**O**, synthetic row) | `OTP`, `e-sign`, `eKYC`, `CKYC` |
| **OTP (delivery)** | `Your Blue Dart Secure Delivery Code is 969384 ...` (**O**) | `Delivery Code`, `OTP` |
| **Balance enquiry / mini statement** | `Your A/c XX1234 balance is Rs.{bal} as on {date}.` / `Mini statement: ...` | `balance is`, `mini statement`, `statement of account`, `last 5 transactions` |
| **KYC / eKYC / re-KYC** | `Dear Customer, please complete your KYC ...` | `KYC`, `re-KYC`, `update your PAN` |
| **Aadhaar / UPI linking** | `Your Aadhaar is linked to {n} accounts`, `UPI ID linked successfully` | `linked`, `linking`, `activated`, `registration successful` |
| **Autopay reminder (not executed)** | `... is due by 18/05/2022 and will be debited through your ICICI Bank Credit Card 5444 ...` (**O**) | `is due`, `will be debited`, `upcoming`, `scheduled on` |
| **Bill due reminder** | `Your {issuer} Card payment of Rs.{min} is due on {date}` | `is due`, `due date`, `pay now` |
| **Limit enhancement offer** | `Congratulations! Your credit limit has been enhanced to Rs.{limit}` | `enhanced`, `upgrade`, `offer` |
| **EMI conversion offer** | `Convert your transaction of Rs.{amt} into EMI ...` | `convert`, `EMI option`, `at {x}% for {n} months` |
| **Insurance / loan spam** | `Get a personal loan up to Rs.5,00,000 at 10.5%*. Apply now.` | `apply now`, `pre-approved`, `loan up to`, `insurance`, phone-banking sender `AD-*` |
| **Job / work-from-home spam** | `Earn Rs.{amt} daily from home. WhatsApp {number}.` | `earn`, `work from home`, `part time` |
| **Phishing** | `Dear customer, your account will be blocked today. Update KYC at http://hdfc-secure-verify.xyz` | non-bank domain, `will be blocked`, `click here`, `update immediately` |
| **Collect request (pending)** | `SWIGGY BUSINESS has requested money from you on your Amazon app. On approving the request, INR 2856.15 will be debited from your A/c. ... - Axis Bank` (**O**) | `has requested money`, `on approving`, `will be debited` |
| **Merchant-side receipt** | `Thank you for the payment of Rs. 443.26 via BharatQR UPI ID gaxxx@okaxis through HDFC Bank SmartHub on 02-05-2022 18:55:04. Receipt: https://... -Mintoak` (**O**) | `Thank you for the payment`, `Receipt:`, `-Mintoak`, `through {bank} SmartHub` |
| **POS/receipt copy** | `Please click on the below link to get your FnB transaction receipt ... Transaction No: 7841623, TotalAmount:260 at POS:PVR VEGA MALL ...` (**O**) | `receipt`, `TotalAmount:`, `at POS:` |
| **Service activation / product notice** | `Dear Customer, your ICICI Bank FASTag Customer ID 16219891 has been activated ...` (**O**), `... HDFC Bank is now compliant with RBI e-mandate framework ...` (**O**) | `activated`, `is now compliant`, `w.e.f.` |
| **Fraud-awareness broadcast** | `Beware of fraudsters calling to lure you with fictitious job offers ... - StanChart` (**O**) | `beware`, `do not share`, `fraudsters` |
| **Declined / failed transaction** | `Your transaction of Rs.{amt} was declined. No amount has been debited.` (I) | `declined`, `failed`, `no amount has been debited`, `unsuccessful` |
| **EWS / pre-transaction notice** | `You will be charged Rs.{amt} on {date} for {merchant}` (OneCard T&C: ≥24h notice) | `will be charged`, `in 24 hours` |
| **Delivery/logistics** | `Arriving today: ... will be delivered by AmzAgent` (**O**) | no currency + no bank verb |
| **Maturity / policy notices** | `Your policy {no} matures on {date}` | `matures`, `premium due` |

Two-stage gate used by the parser:

1. **Sender gate** — 10-digit / 4–8-digit numeric / unknown-brand header ⇒ drop unless body matches
   a high-precision bank pattern *and* the user has added that sender as trusted.
2. **Intent gate** — reject if any hard-negative token, or if no currency+verb pair, or if the only
   verb is conditional/future (`will be`, `is due`, `has requested`).

---

## 8. Duplicate alerts (bank + issuer + wallet)

The same purchase commonly produces 2–3 messages:

| Scenario | Message A | Message B | Shared | Differs |
|---|---|---|---|---|
| CC spend via UPI (RuPay CC) | HDFC Bank: `Rs.500.00 debited from a/c **4821 ... UPI Ref No 123...` | HDFC CC issuer: `Rs.500.00 spent on your HDFC Bank Credit Card ending 1234 ... Avl Lmt: ...` | amount, time | instrument framing, account vs card mask, balance vs limit |
| Wallet + bank | PhonePe: `Rs 150 paid to {merchant} via PhonePe` | Bank: `Rs 150.00 debited ... to VPA merchant@ybl ... Ref ...` | amount, VPA/merchant, ±60s | no ref in wallet SMS, no balance |
| Card bill payment | Bank debit (`InfoBIL*`) | CRED `Payment of INR X was received ...` / issuer `Thank you for your payment` | amount, ±5 min | channel wording; CRED says "48 hours" |
| ATM | Bank ATM SMS | Issuer `Cash advance` SMS (rare) | amount, last4 | one says ATM, other says cash advance |
| Refund | Merchant email/SMS | Bank `credited ... refund` | amount ± | merchant-side is not a bank alert |

### 8.1 Dedupe key and algorithm

```text
dedupeGroup = (amountPaise, last4OrMaskKey, bucket(ts, 180s))
```

1. **Exact ref match** (`referenceId` equal, non-null) ⇒ duplicate, regardless of time.
2. **Amount + last4 + ≤180s** ⇒ duplicate **if** merchant similarity ≥ 0.6 **or** one side has no
   merchant. Never merge two same-amount messages >180s apart (two coffees are real).
3. **Cross-instrument**: `wallet`/`upi-app` row + `account` row, same amount, ≤120s ⇒ merge;
   canonical = bank row (more fields), `sourceApp` = wallet row's app.
4. **Card bill payment**: merge bank debit + issuer "payment received" + CRED confirmation,
   ≤10 min window, using amount + cardLast4; canonical = issuer confirmation for limit, bank row
   for the money movement. Result: **one** `cardPayment` event, zero consumption.
5. **Refund/reversal** must never merge with the original spend (different direction, different
   date). Merge only refund-to-refund.
6. **Prefer the richer row**: canonical fields come from the row with more of
   `{refId, balance, limit, merchant}`; the loser's unique fields are copied in
   (`availableLimitPaise`, `sourceApp`).

### 8.2 Phrasing pairs that must dedupe (regression list)

| A | B |
|---|---|
| `debited from a/c **4821` | `spent on your ... Credit Card ending 1234` |
| `is debited on ICICI Bank Credit Card XX5533` | `spent on ICICI Bank Card XX5533` |
| `Rs 150 paid to X via PhonePe` | `Rs 150.00 debited ... to VPA X@ybl` |
| `Payment of INR 5000 was received for your ... card` (CRED) | `Thank you for your payment of Rs.5000 towards your ... Card` (issuer) |
| `debited with Rs 70.25 ... for toll charges` (FASTag) | `Rs 70.25 spent ... FASTag` (wallet app) |

### 8.3 Anti-dedupe rules (must stay separate)

- Same amount, same merchant, **> 3 minutes** apart ⇒ two transactions.
- Same amount, **different last4** ⇒ different cards.
- Same amount, one `expense` and one `income` ⇒ refund vs spend.
- Same amount, one is `credit card` and other is `wallet top-up` ⇒ load vs spend.
- UPI Lite spend (wallet) + the later bank "UPI Lite load" ⇒ different events, both legit.

---

## 9. Parser pipeline & confidence hints

### 9.1 Order of operations (cheap rejections first)

| Step | Action | Cost |
|---|---|---|
| 1 | Sender prefilter (§1.5): drop 10-digit, 4–8-digit numeric, unknown brand | O(1) |
| 2 | Hard-negative gate (§7 killer tokens: `OTP`, `is due`, `will be debited`, `has requested money`, `declined`, `activated`, `receipt`, `TotalAmount:`, `beware`) | 1 regex sweep |
| 3 | Body must contain a currency token **and** a debit/credit verb | 2 sweeps |
| 4 | Amount extraction with label disambiguation (§2.2) | 1 sweep + offsets |
| 5 | Instrument + direction (§2.3, §2.4) | ordered checks |
| 6 | Identity: mask, VPA, ref, merchant, balance/limit (§2.5–2.10) | targeted regexes |
| 7 | Per-issuer template match (only to refine instrument, e.g. Kotak `Avl bal` ⇒ limit) | string startsWith + contains |
| 8 | Confidence score (§9.2) | arithmetic |
| 9 | Dedupe against last 24h window (§8) | in-memory index |

### 9.2 `confidenceHint` values

| Value | Criteria |
|---|---|
| `high` | Known DLT brand token **and** amount **and** explicit verb **and** at least two of `{last4, refId, merchant}` |
| `medium` | Known sender but missing ref/merchant, **or** unknown sender with full grammar match |
| `low` | Amount + verb only; OR forex with no INR leg; OR 10-digit sender with bank-like body; OR `Avl bal`-on-card ambiguity unresolved |
| `reject` | Hard negative, conditional/future verb, OTP, reminder, offer, receipt, merchant-side confirmation |

UI policy: `high`/`medium` auto-post; `low` goes to a "Review" queue; `reject` is dropped
(optionally logged locally for parser tuning, never uploaded).

### 9.3 Anti-patterns to avoid

- One giant alternation regex over all banks — unmaintainable and catastrophically slow on
  2 000-char marketing SMS. Use ordered token extraction.
- Parsing the **first** number in the body: OTP bodies start with a 6-digit OTP
  (`208716 is OTP for txn of INR 507.71 ...`), and ref numbers are 12–18 digits.
- Treating `Rs` as required — `INR42.97` has no space and no separator; `₹` occurs in app
  notifications.
- Assuming the SMS body is ASCII: regional-language templates exist (Hindi/Tamil/Telugu/Marathi),
  `₹` is U+20B9, and some templates use non-breaking spaces after `Rs.`.
- Assuming one SMS per event: long ICICI/Axis templates are sometimes split into 2 parts by the
  network; concatenate multipart SMS by `(sender, timestamp bucket)` before parsing.

---

## 10. Dart-ready fixture block

Copy the whole block below into `test/fixtures/sms_corpus.dart`. It is `const`-constructible,
dependency-free, and each entry is tagged with the expected parse outcome. Amounts are exact
paise conversions of the amount that appears in the body.

Coverage audit (assert these counts in a test):

| Bucket | Tag prefix | Count |
|---|---|---|
| UPI debits | `A*` | 9 |
| Debit-card POS/ECOM | `B*` | 7 |
| Credit-card spends | `C*` | 14 |
| ATM | `D*` | 3 |
| NEFT/IMPS/RTGS/cheque out | `E*` | 5 |
| Credits / inflows | `F*` | 7 |
| Refunds / reversals / cashback | `G*` | 10 |
| Bill payments (incl. card bills) | `H*` | 10 |
| Autopay / mandate / SI / EMI | `I*` | 7 |
| Card control plane (no txn) | `J*` | 5 |
| Hard negatives & spam | `K*` | 20 |
| Duplicate groups | `L*` | 6 |
| **Total** | | **103** |

```dart
// test/fixtures/sms_corpus.dart
//
// Corpus of realistic Indian transactional SMS bodies with expected parse outcomes.
// Numeric ids, card masks, VPAs and reference numbers are anonymised/fabricated.
// Wording follows the templates documented in docs/research/01-sms-corpus.md
// (tier O = observed in a cited public corpus, V = vendor-published sample, I = inferred).

enum SmsDirection { expense, transfer, income }

enum SmsInstrument { upi, debitCard, creditCard, account, wallet, atm }

/// One SMS plus the outcome the parser is expected to produce.
///
/// [amountPaise] is null for messages that must never become a transaction.
/// [direction] is null exactly when [confidenceHint] is `reject`.
/// [last4] is the account/card tail used for de-duplication and account matching.
/// [cardLastDigits] is the card tail as printed (Amex prints 5, Axis sometimes 3).
/// [isDuplicateGroup] is non-null for rows that must collapse to a single ledger row.
class SmsFixture {
  const SmsFixture({
    required this.id,
    required this.sender,
    required this.body,
    required this.confidenceHint,
    this.amountPaise,
    this.direction,
    this.instrument,
    this.cardIssuer,
    this.cardLastDigits,
    this.last4,
    this.referenceId,
    this.merchant,
    this.isDuplicateGroup,
    this.note = '',
  });

  final String id;
  final String sender;
  final String body;

  /// 'high' | 'medium' | 'low' | 'reject'
  final String confidenceHint;

  final int? amountPaise;
  final SmsDirection? direction;
  final SmsInstrument? instrument;
  final String? cardIssuer;
  final String? cardLastDigits;
  final String? last4;
  final String? referenceId;
  final String? merchant;
  final String? isDuplicateGroup;
  final String note;
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
    cardIssuer: 'HDFC Bank',
    last4: '4821',
    referenceId: '621847362514',
    merchant: 'chaipoint',
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
    cardIssuer: 'ICICI Bank',
    last4: '742',
    referenceId: '559274810022',
    merchant: 'swiggy',
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
    cardIssuer: 'ICICI Bank',
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
    cardIssuer: 'ICICI Bank',
    last4: '702',
    referenceId: '933716309044',
    merchant: 'bharatpe09899148115',
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
    cardIssuer: 'HDFC Bank',
    last4: '4821',
    referenceId: '512345678901',
    merchant: 'kirana',
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
    cardIssuer: 'State Bank of India',
    last4: '1234',
    referenceId: '412345678901',
    merchant: 'bigbasket',
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
    cardIssuer: 'Axis Bank',
    last4: '5678',
    referenceId: '998877665544',
    merchant: 'zomato',
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
    cardIssuer: 'HDFC Bank',
    last4: '4821',
    referenceId: '623456789012',
    merchant: 'Zomato',
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
    cardIssuer: 'Kotak Mahindra Bank',
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
    cardIssuer: 'State Bank of India',
    cardLastDigits: '5522',
    last4: '5522',
    merchant: 'AMAZON PAY INDIA',
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
    cardIssuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    merchant: 'FLIPKART',
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
    cardIssuer: 'Axis Bank',
    cardLastDigits: '4321',
    last4: '4321',
    merchant: 'DMART',
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
    cardIssuer: 'Kotak Mahindra Bank',
    cardLastDigits: '8765',
    last4: '8765',
    merchant: 'SWIGGY',
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
    cardIssuer: 'IDFC FIRST Bank',
    cardLastDigits: '2468',
    last4: '2468',
    merchant: 'Croma',
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
    cardIssuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    merchant: 'AMAZON US',
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
    cardIssuer: 'State Bank of India',
    cardLastDigits: '5522',
    last4: '5522',
    merchant: 'IRCTC',
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
    cardIssuer: 'ICICI Bank',
    cardLastDigits: '2815',
    last4: '2815',
    merchant: 'Amazon.in',
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
    cardIssuer: 'ICICI Bank',
    cardLastDigits: '5533',
    last4: '5533',
    merchant: 'Swiggy',
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
    cardIssuer: 'Axis Bank',
    cardLastDigits: '931',
    last4: '931',
    merchant: 'INDIAN OIL SVC STN',
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
    cardIssuer: 'Kotak Mahindra Bank',
    cardLastDigits: '2210',
    last4: '2210',
    merchant: 'BOOKMYSHOW',
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
    cardIssuer: 'American Express',
    cardLastDigits: '91009',
    last4: '1009',
    merchant: 'ZOMATO',
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
    cardIssuer: 'ICICI Bank',
    cardLastDigits: '4192',
    last4: '4192',
    merchant: 'DAILYDEL SOLUTI',
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
    cardIssuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    merchant: 'MYNTRA',
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
    cardIssuer: 'SBI Card',
    cardLastDigits: '4321',
    last4: '4321',
    merchant: 'SWIGGY',
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
    cardIssuer: 'IDFC FIRST Bank',
    cardLastDigits: '5678',
    last4: '5678',
    merchant: 'NETFLIX',
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
    cardIssuer: 'RBL Bank',
    cardLastDigits: '9090',
    last4: '9090',
    merchant: 'Nykaa',
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
    cardIssuer: 'OneCard (CSB Bank)',
    merchant: 'SWIGGY',
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
    cardIssuer: 'AU Small Finance Bank',
    cardLastDigits: '3344',
    last4: '3344',
    merchant: 'Decathlon',
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
    cardIssuer: 'IndusInd Bank',
    cardLastDigits: '7788',
    last4: '7788',
    merchant: 'BOOKMYSHOW',
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
    cardIssuer: 'ICICI Bank',
    cardLastDigits: '2815',
    last4: '2815',
    merchant: 'OPENAI',
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
    cardIssuer: 'State Bank of India',
    last4: '1710',
    referenceId: '2699',
    merchant: 'SBG ATM MANCHERIAL',
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
    cardIssuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    merchant: 'BANGALORE',
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
    cardIssuer: 'ICICI Bank',
    cardLastDigits: '742',
    last4: '742',
    merchant: 'MUMBAI',
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
    cardIssuer: 'State Bank of India',
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
    cardIssuer: 'HDFC Bank',
    last4: '4821',
    referenceId: 'HDFC1234567890',
    merchant: 'RAHUL SHARMA',
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
    cardIssuer: 'ICICI Bank',
    last4: '742',
    referenceId: 'N123456789012',
    merchant: 'RAHUL SHARMA',
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
    cardIssuer: 'State Bank of India',
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
    cardIssuer: 'Axis Bank',
    last4: '5678',
    referenceId: 'AXIS9876543210',
    merchant: 'ACME TRADERS',
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
    cardIssuer: 'State Bank of India',
    last4: '1710',
    referenceId: '730609020693',
    merchant: 'imgauti3@okhdfcbank',
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
    cardIssuer: 'ICICI Bank',
    last4: '963',
    merchant: 'MF-AXIS A',
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
    cardIssuer: 'HDFC Bank',
    last4: '1234',
    referenceId: 'HDFC5566778899',
    merchant: 'ACME TECHNOLOGIES PVT LTD',
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
    cardIssuer: 'HDFC Bank',
    last4: '4821',
    merchant: 'RAHUL SHARMA',
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
    cardIssuer: 'ICICI Bank',
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
    cardIssuer: 'State Bank of India',
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
    cardIssuer: 'Amazon Pay',
    referenceId: '402-1234567-1234567',
    merchant: 'Amazon',
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
    cardIssuer: 'ICICI Bank',
    cardLastDigits: '2815',
    last4: '2815',
    merchant: 'AMAZON',
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
    cardIssuer: 'HDFC Bank',
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
    cardIssuer: 'State Bank of India',
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
    cardIssuer: 'Kotak Mahindra Bank',
    cardLastDigits: '2210',
    last4: '2210',
    merchant: 'merchant refund',
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
    cardIssuer: 'HDFC Bank',
    confidenceHint: 'low',
    note: 'I. No ref, no mask, no merchant: match by amount+time to the original debit.',
  ),
  SmsFixture(
    id: 'G06',
    sender: 'VK-CRED',
    body:
        'Congratulations! You won INR 6 cashback. We will deposit it into your credit card XXX-6314 in the next 7 days.',
    amountPaise: 600,
    direction: SmsDirection.income,
    instrument: SmsInstrument.creditCard,
    cardIssuer: 'unknown (mask 6314)',
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
    cardIssuer: 'ICICI Bank',
    cardLastDigits: '2815',
    last4: '2815',
    merchant: 'AMAZON',
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
    cardIssuer: 'ICICI Bank',
    cardLastDigits: '2815',
    last4: '2815',
    merchant: 'AMAZON',
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
    cardIssuer: 'HDFC Bank',
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
    cardIssuer: 'ICICI Bank',
    last4: '678',
    referenceId: '000910062',
    merchant: 'BIL*000910062',
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
    cardIssuer: 'ICICI Bank',
    last4: '956',
    referenceId: 'BIL*ONL*00059',
    merchant: 'BIL*ONL',
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
    cardIssuer: 'ICICI Bank',
    last4: '554',
    referenceId: 'BIL*NEFT*HS92',
    merchant: 'BIL*NEFT',
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
    cardIssuer: 'ICICI Bank',
    last4: '023',
    referenceId: '000922185',
    merchant: 'BIL*000922185',
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
    cardIssuer: 'ICICI Bank',
    cardLastDigits: '7007',
    last4: '7007',
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
    direction: SmsDirection.expense,
    instrument: SmsInstrument.account,
    cardIssuer: 'HDFC Bank',
    last4: '4821',
    merchant: 'BILLDESK',
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
    cardIssuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
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
    cardIssuer: 'ICICI Bank',
    cardLastDigits: '2815',
    last4: '2815',
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
    cardIssuer: 'Axis Bank',
    cardLastDigits: '931',
    last4: '931',
    merchant: 'CHEQ',
    confidenceHint: 'medium',
    note: 'I. Third-party bill channel (Cheq) with a 3-digit Axis mask.',
  ),

  // ─── I. Autopay / mandate / SI / EMI ───────────────────────────────────────
  SmsFixture(
    id: 'I01',
    sender: 'VM-ICICIB',
    body:
        'Dear Customer, your payment of Rs 610.64 for Youtube, as per Standing Instruction VkiVm1jJlQ, is due by 18/05/2022 and will be debited through your ICICI Bank Credit Card 5444. To cancel this debit or your Standing Instruction, please visit www.icicibank.com-Cards-Credit Cards-Standing Instruction & Recurring Charges-Manage Standing Instructions.',
    amountPaise: 61064,
    instrument: SmsInstrument.creditCard,
    cardIssuer: 'ICICI Bank',
    cardLastDigits: '5444',
    last4: '5444',
    merchant: 'Youtube',
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
    cardIssuer: 'HDFC Bank',
    last4: '4821',
    merchant: 'NETFLIX',
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
    cardIssuer: 'ICICI Bank',
    last4: '742',
    referenceId: '556677889900',
    merchant: 'spotify',
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
    cardIssuer: 'State Bank of India',
    last4: '1234',
    referenceId: 'HDFC0000123456',
    merchant: 'HDFC LIFE',
    confidenceHint: 'medium',
    note: 'I. NACH: UMRN is the reference.',
  ),
  SmsFixture(
    id: 'I05',
    sender: 'VK-AXISBK',
    body:
        'INR 23,456.00 debited from your Axis Bank A/c XX5678 on 05-05-24 towards EMI for loan AXISLOAN1234. Avl Bal INR 1,12,480.00.',
    amountPaise: 2345600,
    direction: SmsDirection.expense,
    instrument: SmsInstrument.account,
    cardIssuer: 'Axis Bank',
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
    cardIssuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    merchant: 'GOOGLE',
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
    cardIssuer: 'ICICI Bank',
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
    cardIssuer: 'HDFC Bank',
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
    cardIssuer: 'ICICI Bank',
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
    cardIssuer: 'SBI Card',
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
    cardIssuer: 'Kotak Mahindra Bank',
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
    cardIssuer: 'Axis Bank',
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
    cardIssuer: 'Axis Bank',
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
    cardIssuer: 'HDFC Bank',
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
    cardIssuer: 'HDFC Bank',
    last4: '4821',
    referenceId: '778899001122',
    merchant: 'amazonpay',
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
    cardIssuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    merchant: 'AMAZON PAY',
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
    cardIssuer: 'PhonePe (PSP)',
    referenceId: '4455667788',
    merchant: 'SREE KRISHNA STORES',
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
    cardIssuer: 'HDFC Bank',
    last4: '4821',
    referenceId: '445566778899',
    merchant: 'sreekrishna',
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
    cardIssuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
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
    cardIssuer: 'HDFC Bank',
    cardLastDigits: '1234',
    last4: '1234',
    isDuplicateGroup: 'dup-cardbill-hdfc-7500',
    confidenceHint: 'high',
    note: 'Issuer confirmation of the same CRED payment — canonical for available-limit math.',
  ),
];
```

### 10.1 Fixture invariants worth asserting in tests

```dart
// every reject row must have no direction
for (final f in smsCorpus.where((f) => f.confidenceHint == 'reject')) {
  assert(f.direction == null, '${f.id} is reject but has a direction');
}
// duplicate groups must have >= 2 members
final groups = <String, int>{};
for (final f in smsCorpus) {
  final g = f.isDuplicateGroup;
  if (g != null) groups[g] = (groups[g] ?? 0) + 1;
}
assert(groups.values.every((c) => c >= 2));
// amounts must be paise, never rupees
assert(smsCorpus.every((f) => f.amountPaise == null || f.amountPaise! % 1 == 0));
```

---

## 11. Open questions / ambiguity

1. **Exact private templates.** Only ICICI (multiple), SBI, HDFC (one UPI flow), Axis, Kotak,
   Amex, CRED and StanChart are grounded by observed or vendor bodies. Every other bank row is
   `(I)`. Before shipping, capture 20–50 real SMS per issuer from consenting users (or the
   developer's own phone) and replace the inferred rows. The fixture file should then be
   regenerated from those captures.
2. **Header taxonomy.** The 2-letter prefix table is documented by vendors, not by TRAI text we
   could fetch. Prefixes vary by operator and are re-used for categories; `VA`, `QP` are
   observed but undocumented. Do not encode operator semantics in logic.
3. **Bank short codes** (`HDFCBK`, `ICICIB`, `SBIINB`, `AXISBK`, `KOTAKB`, …) are conventional
   but each brand owns several; and issuers rotate codes. Prefer prefix matching on the brand
   token, and allow the user to add/rename a sender mapping.
4. **Amex 5-digit mask.** `**91009` breaks the universal "last 4" assumption. Decide whether
   `last4 = '1009'` plus `rawMask` is enough to match a user-entered Amex card, or whether Amex
   cards should key on the 5-digit tail.
5. **Kotak `Avl bal` on cards.** Whether Kotak uses `Avl bal` for *both* debit and credit cards
   determines whether instrument classification can rely on the balance label. Currently handled
   by issuer override — verify with real Kotak debit-card SMS.
6. **Wallet SMS coverage.** PhonePe/Google Pay/Paytm mostly notify in-app. How much of the corpus
   is SMS vs Android notification is unknown; the app's `NotificationListenerService` corpus needs
   its own spec (and its own dedupe rules against SMS).
7. **Regional-language templates.** HDFC/ICICI/SBI send Hindi and other language variants to some
   customers. Whether the English token grammar transfers (amount formats do; verbs do not) is
   untested. A minimal per-language verb table may be needed.
8. **Multipart SMS.** Whether long ICICI/Axis bodies are ever split (and how the parts are
   concatenated) is unverified; the spec assumes a single part.
9. **`UPI Lite` accounting.** Lite is an on-device wallet funded from the account. Whether a Lite
   spend also produces a bank debit SMS (it should not, by design) determines double-count risk.
   Verify against RBI/NPCI UPI Lite documentation and real phones.
10. **FASTag wallets.** Some issuers alert on the FASTag wallet, some on the linked account, some
    on both. Whether a toll debit reaches the bank account as a separate SMS is unverified.
11. **Credit-card utilisation without total limit.** Most spend SMS expose only the *available*
    limit. Guessing total limit from the maximum observed available limit understates utilisation
    for anyone who never approaches their limit. Decide: ask the user once, or read the statement
    SMS (which contains `Total Credit Limit` in some issuers' templates).
12. **Card bill payment direction.** Modelled as `transfer` (net-worth neutral). If the ledger
    only has expense/income, booking a card bill as `expense` double counts the underlying
    purchases; the data model needs a `cardPayment` kind even if the fixture enum has only three
    directions.
13. **Merchant cleaning.** `IND*Amazon.in`, `PAYU ZOMATO`, `EBA*MF-AXIS A-109012205*20210917113`
    — no canonical mapping exists offline. The app needs a local merchant-alias table seeded with
    the top ~200 Indian merchants, and must keep `merchantRaw`.
14. **Statement/due-date parsing.** Due dates in reminders are the only offline source of the
    card's billing cycle; formats vary (`18/05/2022`, `18-05-2024`). Whether they are reliable
    enough to drive a "pay before" nudge is unknown.
15. **Truncated merchant strings.** `DAILYDEL SOLUTI` is 13 chars — likely a template field limit.
    Fuzzy merchant grouping must tolerate truncation without merging unrelated merchants.
16. **Duplicate window.** 180s is a guess. Real bank↔issuer lag can be minutes; bank↔wallet is
    usually seconds. Consider per-pair windows and a "needs confirmation" state for 3–10 minute
    gaps.
17. **`confidenceHint` thresholds** are heuristics, not measured. Once real captures exist, tune
    against a labelled set and report precision/recall per issuer.

---

## 12. Sources

| # | URL | What it grounds |
|---|---|---|
| 1 | https://huggingface.co/datasets/gandharvbakshi/SMS-dataset-sample-10k | Real Indian SMS corpus (tier **O** rows: ICICI account debit/credit/FASTag/CC, SBI UPI/IMPS/ATM, Axis collect requests, Amex spend, CRED payments, StanChart broadcasts, HDFC e-mandate notice, senders `VM-ICICIB`, `VK-SCBANK`, `VKHDFCBN`, `QPFASTag`, `JMBLUDRT`, `VK-PVRCIN`, `VK-AXISMF`, `VM-ISECLT`) |
| 2 | https://dibba.ai/bank-sms-parser/india | Index of published India samples |
| 3 | https://dibba.ai/bank-sms-parser/india/hdfc-upi-chai-sms | HDFC UPI debit body (tier **V**) |
| 4 | https://dibba.ai/bank-sms-parser/india/sbi-card-shopping-sms | SBI debit-card ECOM body (tier **V**) |
| 5 | https://dibba.ai/bank-sms-parser/india/icici-upi-food-sms | ICICI UPI debit body (tier **V**) |
| 6 | https://dibba.ai/bank-sms-parser/india/axis-fuel-sms | Axis card spend body, 3-digit mask, `Avl Lmt` (tier **V**) |
| 7 | https://dibba.ai/bank-sms-parser/india/kotak-ticket-sms | Kotak card spend, `Avl bal` on a card (tier **V**) |
| 8 | https://developer.exotel.com/docs/faqs/dlt-compliance.md | DLT header/template mechanics, 6-char sender IDs, `{#var#}` templates, character-exact matching |
| 9 | https://startmessaging.com/blog/what-is-sms-sender-id | Header = 2-char prefix + brand; prefix families (`JD/JM/JT/JX`, `VK/VM/VG/VX`, `AX/AT/AM`, `AD`, `TX/TM`) |
| 10 | https://app.unpkg.com/@strmchsr/transaction-sms-parser@1.2.4/files/README.md | Prior art: balance keywords, bank keyword list (`ATMSBI`, `ALBANK`, `BOB`, `PNB`, `KOTAK`, `IDFC`), issuer coverage list |
| 11 | https://pub.dev/packages/transaction_sms_parser | Prior art for Flutter API shape only (its sample bodies are invented) |
| 12 | https://www.federalbank.co.in/documents/10180/58403423/OneCard+Credit+Card+Terms+and+Conditions.pdf | OneCard programme on Federal rails; pre-transaction notice ≥24h |
| 13 | https://www.csb.co.in/pdf/CC-FAQ21122022.pdf | OneCard issuer FAQ (CSB Bank) |
| 14 | https://www.kotak.bank.in/en/personal-banking/cards/credit-cards/credit-card-services/insta-alert-for-cc-customers.html | Kotak InstaAlert product page (channel exists; template not published) |
| 15 | https://www.axis.bank.in/bank-smart/sms-banking | Axis SMS banking product page |

Evidence discipline: rows marked **O** are quoted from source 1; rows marked **V** from sources 2–7;
everything else is **I** and must be validated against real devices before the parser is considered
production-ready.


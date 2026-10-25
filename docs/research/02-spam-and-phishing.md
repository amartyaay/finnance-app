# 02 — Spam, Promo & Phishing Detection for Indian Bank/UPI SMS

**Status:** implementable specification (v1) · **Target:** offline Flutter/Android classifier · **Last research pass:** 2026-10-25

---

## 0. Scope, principles, non-goals

This document specifies how the app turns one raw SMS into **exactly one class** plus a **suspicion state**, entirely on-device:

| Class | Meaning in the UI |
|---|---|
| `transaction` | A money movement actually asserted by a bank/wallet: debit, credit, refund, reversal, EMI, charge, ATM. Feeds the ledger. |
| `informational` | Genuine non-money message: statement ready, cheque cleared, FD maturity, card dispatched, branch holiday, KYC reminder, e-mandate created, login-from-new-device. |
| `otp` | A one-time password / verification code. **Never** a spend. Never shown with an amount. |
| `promo` | Marketing: credit-card offers, loans, insurance, real estate, casino, stock tips, job lures. |
| `fraud` | Pretends to be the user's bank (or a govt/utility/courier) to extract credentials, money or remote access. |

Plus a second axis, `suspicion ∈ {clear, check, warn}`, which drives UX. Two axes matter because "what the message says" and "how much we trust it" are independent facts: a `transaction`-shaped message from a 10-digit number is still a `transaction` claim, but it must never move money in the ledger and must carry `warn`.

**Five design principles**

1. **Intent first, sender second, link third.** Sender trust and link presence are *evidence*, not verdicts. A real bank's DLT header plus a matching debit template outranks the presence of a URL — banks routinely append "click here to view".
2. **Never cry wolf on money.** Misclassifying a genuine debit as fraud destroys trust faster than missing one promo. Asymmetric costs: false-fraud on a bank alert is the worst error class.
3. **Credential-ask is the one unforgivable signal.** Indian banks never ask for OTP/PIN/CVV/password over SMS, in any channel, ever. [RBI's own public guidance](https://www.axio.co.in/blogs/keep-your-finances-safe-the-rbi-way) is explicit that OTP, ATM PIN, CVV and passwords must never be shared, and that receiving money requires neither a QR scan nor an OTP.
4. **Explain, never assert certainty.** We ship *reasons* ("Sender is a 10-digit number"), not probabilities the user will read as guarantees.
5. **Offline is a feature, not a limitation.** The classifier needs zero network calls. No raw SMS body ever leaves the device (see §8).

**Non-goals:** verifying a sender against the live DLT registry, resolving or fetching URLs, inspecting attachments/MMS, blocking SMS at the OS level, or detecting fraud *inside* the bank's own app.

---

## 1. The TRAI DLT regime — what the sender ID actually tells you

### 1.1 Header anatomy

India's A2P ("application-to-person") SMS does not arrive from a phone number. It arrives from a **registered alphanumeric header (sender ID)** provisioned on a telco DLT (Distributed Ledger Technology) platform under the [TCCCPR framework](https://www.trai.gov.in/sites/default/files/2025-02/Regulation_12022025.pdf). The visible sender ID is:

```
  VK   -   HDFCBK   -   T
  │        │            └── category suffix (added by the telco, May 2025 onward)
  │        └─────────────── brand header, 6 chars (extendable to 8)
  └──────────────────────── 2-char routing prefix: operator + circle
```

Total length is capped around 11 characters, which is exactly why the brand field is 6 and the suffix is 1: `2 + 1 + 6 + 1 + 1 = 11`.

### 1.2 The two-letter prefix = originating operator + licensed service area

The prefix exists for billing settlement between telcos/circles and for routing spam complaints back to the sender's operator — TRAI explicitly declined to remove it for that reason ([MediaNama](https://www.medianama.com/2025/05/223-suffixes-commercial-sms-headers-spam/)). Per [SMSGatewayHub's operator/circle tables](https://crm.smsgatewayhub.com/knowledge-base/article/what-is-ad-lm-qp-vm-jx-in-sender-id-in-india-know-your-sms-prefix-codes-explained-for-smarter-messaging):

| First char (operator) | | Second char (circle) | |
|---|---|---|---|
| A | Airtel | D | Delhi |
| V | Vodafone | M | Mumbai |
| I | Idea | X | Karnataka |
| J | Jio | Z | Maharashtra |
| B | BSNL | T | Tamil Nadu |
| M | MTNL | L | Kerala |
| T | Tata | G | Gujarat |
| R | Reliance | A/S/B/H/P/R/E/W | AP / Assam / Bihar / Haryana / Punjab / Rajasthan / UP-E / UP-W |

So `AD-HDFCBK` = Airtel/Delhi, `VM-HDFCBK` = Vodafone/Mumbai, `JD-ICICIB` = Jio/Karnataka, `VK-SBIINB` = Vodafone/Kerala.

**Implementation consequence:** the **prefix is not a trust signal and not a brand signal.** It varies by which telco/circle the sender's aggregator happened to route through, so the same bank legitimately appears as `AD-`, `VM-`, `JD-`, `JX-`, `VK-`. Never key off it — only *strip* it. A useful side effect: a "bank" SMS whose prefix letters are not in the operator/circle tables at all (e.g. `ZZ-`, `XX-`, `99-`) is malformed and worth a small suspicion bump.

### 1.3 The suffix — the actual category label

Since 6 May 2025, telcos append a one-letter category tag derived from the DLT-registered template, not chosen by the brand ([Tanla](https://www.tanla.com/blog-posts/trai-mandates-new-message-suffixes-heres-what-you-need-to-know), [MediaNama](https://www.medianama.com/2025/05/223-suffixes-commercial-sms-headers-spam/)):

| Suffix | Category | What it means | Expected content | Trust reading |
|---|---|---|---|---|
| `-T` | **Transactional** | Sent to an existing customer about a transaction they initiated or that affects their account. Explicit consent on record. | Debits, credits, EMI, OTP-for-a-transaction, e-mandate. | Highest prior for `transaction` / `otp`. Still **not proof** the brand is genuine (§1.6). |
| `-S` | **Service** (incl. **service-implicit**) | Service messages tied to an ongoing relationship. "Implicit consent" = the user never opted in but the message is a necessary consequence of using the service. | OTPs, statements, cheque/FD notices, card dispatch, delivery status, balance alerts, KYC reminders. | High prior for `informational`/`otp`. A `-S` message is where OTPs live — handle with the OTP rules before any amount parser runs. |
| `-P` | **Promotional** | Marketing. Requires DND/consent; must carry an opt-out. | Offers, cross-sell, "apply now", "to stop receiving". | Prior for `promo`. **A `-P` message that claims money moved is a red flag** — promo templates are not supposed to carry debits, so either the bank is abusing the pipe or the header is spoofed. |
| `-G` | **Government** | Government-to-citizen. | UIDAI, ITD, RBI, EPFO, utility/state notices. | Prior for `informational` at best; **never** for a bank transaction. Government impersonation with a link is a major phishing family (§3.2). |
| `-U` | *(not standardised)* | The four suffixes in the 2025 TCCCPR amendment and in every operator/vendor explainer reviewed are **T, S, P, G**. We found no primary source defining `-U`. Some aggregators/telcos have used trailing markers outside the standard. | Unknown. | **Treat as unknown: zero trust, no penalty either.** Classify on content alone. Do not let an unrecognised suffix break a legitimate debit. |

Also note the *absence* of a suffix is **not** evidence of fraud: the rollout is partial, telcos append automatically only for templates that pass DLT scrubbing, and older templates plus most person-to-person traffic still arrive bare.

**P vs T as a legitimacy signal — the honest version.** `-T` means *"a registered entity sent this against a registered transactional template via a registered header."* That is real, useful evidence: it is expensive and traceable to obtain, and TRAI has acted against header/template misuse ([PIB/DoT direction on misuse of headers and templates](https://www.pib.gov.in/PressReleasePage.aspx?PRID=1899849)). But it is **not** evidence that the header belongs to *your* bank. Headers are registered per legal entity, lookalike headers can be registered by other entities, and spoofing via SIM boxes and foreign routes still occurs. Hence: `-T` → strong discount on fraud score, never a hard override except through the trusted-allowlist path in §6.

### 1.4 Numeric series: 140 / 1600

Separate from alphanumeric headers, TRAI reserves numeric short-code series ([MediaNama, Jul 2026](https://www.medianama.com/2026/07/223-trai-releases-clarification-designated-promotional-transactional-number-series/), [ABP Live](https://news.abplive.com/technology/blocked-140-1600-numbers-you-could-miss-otps-and-bank-alerts-government-warns-trai-truecallers-1855765/amp)):

| Series | Reserved for | Notes |
|---|---|---|
| **1600xx** | Service & transactional, from RBI/SEBI/IRDAI/PFRDA-regulated entities and government departments to existing customers. | TRAI says these must not be tagged/blocked/filtered as spam. Carries OTPs and bank alerts. |
| **140xx** | Promotional, exclusively. | Not to be tagged/filtered; may be *blocked* only if the user opted out of that sector on DND. |

Practical reading: a 140-series sender can never be a bank transaction. A 1600-series sender is *plausible* for a bank alert but the series is shared by every regulated entity, so it identifies "regulated sender", not "your bank". Because TRAI forbids filtering these series, abuse is real (Truecaller publicly claims ~5.25 lakh daily spam reports from them) — so do not auto-trust the series either.

### 1.5 How spoofed / fake senders actually appear

Ranked by frequency in Indian cases:

| # | Pattern | Example | Our reading |
|---|---|---|---|
| 1 | **10-digit mobile number** claiming to be a bank | `+91 90987 65432` → "Your SBI a/c will be blocked…" | Banks do not send transactional SMS from 10-digit mobiles. Strongest single sender signal. |
| 2 | **+91 / country-code prefixed** number, or a foreign number | `+91 81234 56789`, `+234…`, `+62…` | Same as above plus international-origin smell (job/lottery scams). |
| 3 | **Unregistered alphanumeric header** with an extra token or separator | `AD-SBI-KYC`, `HDFC BANK`, `SBI.ALERT`, `VM-HDFCBK-ALERT` | Header length/charset violates the `XX-BRAND-S` grammar. |
| 4 | **Lookalike header** — one or two characters off, or a plausible-but-wrong brand code | `HDFCBNK` vs `HDFCBK`, `SBIN` vs `SBIINB`, `AXISBNK` vs `AXISBK`, `ICICIB` vs `ICIClB` (lowercase **l** for **I**) | Edit-distance-1 near-miss of a known good code. |
| 5 | **Unicode homoglyph** in the header | `АD-HDFCBK` with Cyrillic `А` (U+0410); `НDFCBK` with Cyrillic `Н` (U+041D); Greek `Ο`, `Α`, `Β`, `Ε`, `Ρ` | Renders identically on the phone, compares differently in code. Collapse before comparing ([Seqrite on homoglyph attacks](https://www.seqrite.com/blog/homoglyph-attacks-lookalike-characters-cyber-deception/)). |
| 6 | **Personal WhatsApp / `wa.me` link** as the "bank" channel | "Complete video KYC on WhatsApp: `https://wa.me/919812345678`" | Banks do use verified WhatsApp Business, but never for KYC/OTP collection, and never from a bare personal number. |
| 7 | **RCS/Google-Messages brand badge** on a non-SMS channel | Verified-looking logo on an RCS sender | Our SMS reader may see only the raw address; do not inherit the badge's implied trust. |
| 8 | **Full spoofing** (SIM box, grey route, foreign termination) | Header replaced end-to-end | Undetectable from content alone — this is exactly why §5 never lets sender trust *solely* decide, and why §7 never claims certainty. |

---

## 2. Marketing / promotional signals

### 2.1 The two families

**(a) Whole-message promo** — the entire SMS is an advertisement. Easy: the opt-out tail plus an imperative plus a sector keyword.

**(b) Cross-sell embedded inside a genuine transactional SMS** — the hard one, and very common for Indian banks. Example:

> `Rs.150.00 debited from a/c XX2231 to VPA tea@okhdfcbank on 08-06-26. Avl Bal Rs.2,004.55. Get 5% cashback on dining with HDFC Bank Credit Card. Apply now: hdfcbank.com/cc T&C apply. To stop receiving, SMS STOP to 5676767.`

This must be **classified `transaction`, amount = 150.00, `containsOffer = true`**. Two rules protect that:

- **Amount selection is anchored to the money verb**, not to the first number and not to the largest number. `5%` and `5676767` must never become the amount.
- A promo tail (`T&C apply` / `To stop receiving` / `Apply now`) is **`containsOffer`, never a class demotion**. It contributes to the promo score (which is only used as a tiebreaker/flag) and is explicitly excluded from the fraud score.

This is not a new problem: banks and merchants have been pushing promotions down the transactional pipe for over a decade ([MediaNama, 2013](https://www.medianama.com/2013/07/223-jabong-myntra-yebhi-using-transaction-sms-pipe-for-promotion-ussd-spam-via-airtel/)), and TRAI's 2025 pre-tagging direction exists precisely because variable fields were being stuffed with unregistered URLs and callback numbers ([MediaNama, Nov 2025](https://www.medianama.com/2025/11/223-trai-pre-tagged-sms-templates/)).

### 2.2 Wording that reliably marks promo

| Bucket | Signals | Regex (Dart-compatible, case-insensitive) |
|---|---|---|
| **Opt-out tail** (TRAI-mandated in promo templates) | to stop receiving, unsubscribe, opt out, reply STOP, SMS STOP | `r'\b(?:to\s+stop\s+(?:receiv|reciev)\w*|unsubscri\w*|opt[\s-]?out|reply\s+stop|sms\s+stop|to\s+opt\s+out)\b'` |
| **Legal footer** | T&C, TnC, terms apply, terms and conditions | `r'\b(?:t\s*&\s*c|tnc|terms?\s*(?:and|&)\s*conditions?|terms?\s+apply)\b'` |
| **Imperative** | apply now, apply online, book now, buy now, avail, download, register today | `r'\b(?:apply\s+(?:now|online|today)|book\s+now|buy\s+now|avail\s+(?:now|of)?|download\s+(?:now|the)|register\s+(?:now|today))\b'` |
| **Pre-approval flattery** | pre-approved, pre qualified, you are eligible, congratulations, selected | `r'\b(?:pre[\s-]?(?:approved|qualified)|you\s+are\s+(?:eligible|selected)|congratulation\w*|specially\s+selected)\b'` |
| **Deadline pressure** (commercial) | limited period, offer ends, valid till, last date, today only, hurry | `r'\b(?:limited\s+(?:period|time|offer)|offer\s+ends?|valid\s+(?:till|upto|until)|last\s+date|today\s+only|hurry)\b'` |
| **Price framing** | lowest EMI, EMI starting, 0% interest, instant approval, no paperwork, zero processing fee | `r'\b(?:lowest\s+emi|emi\s+(?:starting|from)|0%\s*(?:interest|finance)|zero\s+(?:interest|processing)|instant\s+(?:approval|sanction)|no\s+(?:paperwork|documents?))\b'` |
| **Discount** | % off, flat ₹X off, cashback, voucher, coupon, gift, reward points, assured gift | `r'\b(?:\d{1,3}\s*%\s*(?:off|discount)|flat\s+(?:rs\.?\s*)?\d+|cash\s?back|voucher|coupon|assured\s+gift|reward\s+points)\b'` |

### 2.3 Sector keywords (each adds promo weight; three are special-cased)

| Sector | Keywords | Special handling |
|---|---|---|
| Credit card / loan | credit card, personal loan, home loan, car loan, business loan, loan against, balance transfer, top-up | benign promo |
| Insurance | term plan, ULIP, endowment, premium, policy, cover, IRDAI reg. | benign promo |
| Investments | SIP, mutual fund, demat, IPO, NFO, "multibagger", "sure shot", "intraday calls", "90% accuracy", "guaranteed returns" | ⚠ `guaranteed`/`sure shot`/`accuracy` → tag `investment-scam` (SEBI prohibits assured returns) |
| Real estate | 2/3 BHK, plot, apartment, pre-launch, site visit, RERA | benign promo |
| Gaming/betting | casino, betting, teen patti, rummy, fantasy, "win big", "bonus on deposit", 18+ | tag `gambling`; almost always from 10-digit senders, never DLT |
| Jobs / WFH | work from home, part-time, earn daily, no experience, "registration fee", Telegram | ⚠ if a **fee or Telegram handoff** appears → escalate (`fraud`, §3.7) |

### 2.4 Marketing rules that matter for parsing

- `to stop receiving` / `T&C` in a message that also contains a valid debit → `containsOffer=true`, class stays `transaction`.
- Numbers in promo copy (`5%`, `Rs.5,000 voucher`, `5676767`) are **never** ledger amounts. The amount extractor requires a money verb within 40 characters (§4.3).
- A `-P` suffix is a strong promo prior, but the money-verb rule still wins: a `-P` message containing "Rs.X debited" is *suspicious*, not a transaction (§5, H4).

---

## 3. Phishing / fraud signals

### 3.1 The universal shape

Every Indian bank-impersonation SMS is the same four-part machine:

1. **Borrow a brand** — HDFC / SBI / ICICI / Axis / Paytm / UIDAI / India Post / your electricity board.
2. **Manufacture a consequence** — blocked, deactivated, suspended, frozen, disconnected, penalty, "else".
3. **Compress the clock** — "within 24 hrs", "today", "immediately", "before 6 PM".
4. **Supply the escape hatch** — a link, a phone number, a QR, or a request to install an app.

Offline we cannot see step 4's destination, so we detect steps 1–3 and the *shape* of step 4.

### 3.2 Family table with concrete rules

| # | Family | Realistic text | High-signal predicates |
|---|---|---|---|
| F1 | **Block/expiry KYC lure** | "Your SBI account will be blocked within 24 hrs due to incomplete KYC. Click here to update: `sbi-kyc-verify.top/upd`" | threat verb + deadline + `KYC`/`eKYC`/`re-KYC` + link/callback |
| F2 | **PAN–Aadhaar link** | "PAN not linked with Aadhaar. Account will be frozen tomorrow. Update: `pan-aadhaar-link.in`" | `PAN` + `Aadhaar` + `link`/`update` + threat + non-govt domain |
| F3 | **Card blocked** | "Your card XX4412 is blocked. Confirm your CVV and OTP here: `axis-card-unblock.xyz`" | `card` + block verb + `CVV`/`OTP` + link |
| F4 | **Fake refund / cashback** | "You have received a refund of Rs.4,999. Share the OTP to receive it." | `refund`/`cashback` + `share`/`send`/`confirm` + `OTP` |
| F5 | **UPI request-scam / QR-to-receive** | "Scan this QR and enter your PIN to receive Rs.15,000 in your account." | `scan` + `qr` + (`receive`/`accept`) ∨ `pin`+`receive`. **RBI: receiving money needs no QR, no PIN** ([axio/RBI](https://www.axio.co.in/blogs/keep-your-finances-safe-the-rbi-way)). |
| F6 | **Electricity / utility disconnection** | "ALERT: electricity will be disconnected tonight. Call 9xxxxxxx31 and update KYC immediately." | utility noun (`electricity`, `bijli`, `water`, `gas`, `broadband`) + disconnect + **mobile-number callback** |
| F7 | **Delivery / parcel / customs** | "Parcel held at customs. Pay Rs.25 clearance: `indiapost-tracking.top/pay`" | `parcel`/`courier`/`customs`/`consignment` + fee + link |
| F8 | **Job / part-time task** | "Earn Rs.3,000/day liking YouTube videos. Pay Rs.500 registration, tasks on Telegram." | `earn` + daily amount + (`registration`/`security deposit`/`telegram`/`whatsapp`) |
| F9 | **Remote-access takeover** | "Install AnyDesk and share the code so we can reverse the debit." | `AnyDesk`/`TeamViewer`/`QuickSupport`/`RustDesk`/`screen share`/`remote access` — near-decisive on its own |
| F10 | **Lottery / prize** | "You won Rs.25,00,000. Pay Rs.6,500 processing fee via UPI to claim." | `winner`/`won`/`lottery`/`lucky draw` + (fee ∨ UPI id) |
| F11 | **Government impersonation** | "Your Aadhaar will be deactivated. Update at `uidai-verify.online`" | `UIDAI`/`Aadhaar`/`Income Tax`/`RBI`/`EPFO` + link + threat |
| F12 | **Fake credit alert (seller scam)** | "Rs.15,000 credited to a/c XX9082 … Ship the item now." sent from a 10-digit number | clean credit template **but** untrusted sender. Never treat as proof of credit ([ET coverage of this exact scam](https://economictimes.indiatimes.com/wealth/save/rs-15000-credited-to-a/c-xxxxx9082-beware-of-this-latest-scam-how-to-identify-and-save-your-money/articleshow/110027014.cms)). |
| F13 | **Bank "support" callback** | "Rs.4,999 debited for annual maintenance. If not you, call 9xxxxxxxxx immediately to cancel." | money claim + **mobile-number** callback (banks publish toll-free 1800 lines) |
| F14 | **Account-blocked with subdomain trick** | "Review and accept at `hdfcbank.com.kyc-review.top/terms`" | brand token appears in **subdomain/path**, registrable domain is foreign |

### 3.3 Link predicates (the offline-visible part)

```dart
final urlAny      = RegExp(r'(?:https?://|www\.)[^\s<>"]+', caseSensitive: false);
final bareDomain  = RegExp(r'\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+'
                           r'(?:com|in|net|org|co|io|xyz|top|site|online|shop|store|'
                           r'club|info|icu|live|link|app|buzz|cyou|rest|fun|sbs|'
                           r'cfd|monster|click|work|finance|support|verify|biz)\b',
                           caseSensitive: false);
final ipLiteral   = RegExp(r'https?://(?:\d{1,3}\.){3}\d{1,3}');
final shortener   = RegExp(r'\b(?:bit\.ly|tinyurl\.com|t\.co|goo\.gl|ow\.ly|is\.gd|'
                           r'buff\.ly|cutt\.ly|rb\.gy|shorturl\.at|tiny\.cc|'
                           r'rebrand\.ly|t\.ly|s\.id|bit\.do|ck\.me|shorte\.st|'
                           r'clck\.ru|v\.gd|bl\.ink|1link\.in)\b', caseSensitive: false);
final waLink      = RegExp(r'\b(?:wa\.me|api\.whatsapp\.com|chat\.whatsapp\.com)\b',
                           caseSensitive: false);
final apkLink     = RegExp(r'\.apk\b|\bplay\.google\.com/store/apps/details\?id=(?!com\.(?:'
                           r'hdfcbank|sbi|icici|axis|kotak))', caseSensitive: false);
```

**Predicates that matter more than "has a link":**

1. **Brand–registrable-domain mismatch.** Extract the registrable domain (`eTLD+1`), not the hostname. `hdfc-bank-verify.xyz` → `hdfc-bank-verify.xyz` ∉ HDFC allowlist → mismatch. `hdfcbank.com.kyc-review.top` → registrable domain is `kyc-review.top` → mismatch even though the string contains `hdfcbank.com`.
2. **Brand token in the *subdomain/path* but not in the registrable domain** — the classic `bankname.com.evil.tld` trick.
3. **Shortener** — the link's destination is unknowable offline; treat as "unknown destination", never "safe".
4. **IP literal** — no legitimate Indian bank sends a raw IP.
5. **`wa.me` / personal WhatsApp** — not a bank channel.
6. **`.apk` / sideload prompt** — never legitimate for a bank; overlaps with the AnyDesk family.
7. **High-abuse TLDs** (`xyz`, `top`, `site`, `online`, `icu`, `cyou`, `sbs`, `cfd`, `monster`, `buzz`, `rest`, `lol`, `click`) — weak alone, strong in combination with a brand token.

### 3.4 Domain-impersonation mechanics worth encoding

- **Combosquat:** `hdfc-secure-verify.xyz`, `sbi-kyc-update.top`, `icici-kyc.in-update.site` — brand + security words + cheap TLD.
- **Typosquat:** `hdfcbank.co` (wrong TLD), `onlinesbl.com` (`l` for `i`), `1cicipank.com`.
- **Homoglyph/IDN:** `аxisbank.com` with Cyrillic `а`; punycode `xn--…` in the host. Collapse confusables *before* the allowlist comparison ([Seqrite](https://www.seqrite.com/blog/homoglyph-attacks-lookalike-characters-cyber-deception/)).
- **Legit-domain bait in the query string:** `evil.top/r?u=hdfcbank.com` — only the registrable domain counts.

### 3.5 Urgency and threat regexes

```dart
final deadline   = RegExp(r'\b(?:within\s*\d{1,3}\s*(?:hrs?|hours?|mins?|minutes?)|'
                          r'with\s*in\s*(?:24|48)\s*(?:hrs?|hours?)|before\s*\d{1,2}\s*(?:am|pm)|'
                          r'by\s+(?:today|tonight|tomorrow)|today\s+itself|immediately|'
                          r'urgent(?:ly)?|last\s+(?:chance|day)|expir(?:e|es|ing|ed)|'
                          r'(?:24|48)\s*(?:hrs?|hours?))\b', caseSensitive: false);

final threatVerb = RegExp(r'\b(?:block(?:ed|ing)?|deactivat\w*|suspend\w*|freez\w*|'
                          r'disabl\w*|terminat\w*|disconnect\w*|penalt\w*|'
                          r'legal\s+action|frozen|seized)\b', caseSensitive: false);

final kycLure    = RegExp(r'\b(?:k\.?y\.?c|e-?kyc|re-?kyc|video\s*kyc|pan[\s-]*(?:aadhaar|'
                          r'card|update|link)|aadhaar[\s-]*(?:update|link|verif)|'
                          r're[\s-]?verif\w*|update\s+your\s+details)\b', caseSensitive: false);

final credAsk    = RegExp(r'\b(?:share|send|provide|reply\s+with|confirm|enter|tell|'
                          r'forward|disclose|verify)\b[^.!?\n]{0,45}'
                          r'\b(?:otp|o\.t\.p|pin|upi\s*pin|cvv|password|passcode|'
                          r'net\s*-?\s*banking|user\s*id|card\s*number|debit\s*card|'
                          r'credit\s*card|aadhaar\s*number|account\s*number)\b',
                          caseSensitive: false);

// reversed order: "OTP ... share"
final credAskRev = RegExp(r'\b(?:otp|pin|cvv|password)\b[^.!?\n]{0,45}'
                          r'\b(?:share|send|provide|tell|forward|reply|give)\b',
                          caseSensitive: false);

final remoteApp  = RegExp(r'\b(?:any\s?desk|team\s?viewer|quick\s?support|rust\s?desk|'
                          r'screen\s*shar\w*|remote\s*(?:access|support|desktop)|'
                          r'mirror\s*your\s*screen)\b', caseSensitive: false);

final qrReceive  = RegExp(r'\bqr\b|scan\s+(?:this|the|below)', caseSensitive: false);
final receiveVerb= RegExp(r'\b(?:receive|accept|get|collect)\b', caseSensitive: false);

final callbackNo = RegExp(r'(?<![0-9])(?:\+91[\s-]?)?'
                          r'[6-9][0-9]{4}[\s-]?[0-9]{5}(?![0-9])'); // Indian mobile
final tollFree   = RegExp(r'\b1800[\s-]?\d{3}[\s-]?\d{3,4}\b|\b1860[\s-]?\d{3}[\s-]?\d{3,4}\b');
```

> **Validated gotcha (found by running these patterns on Dart 3.x).** The naive mobile regex `(?:\+91[\s-]?)?[6-9]\d{4}[\s-]?\d{5}\b` **false-fires inside `18001201243`** (it matches the `8001201243` tail) and inside 12-digit UPI references. That would make every genuine "call 1800…" alert look like a call-centre fraud. The `(?<![0-9])` / `(?![0-9])` guards above fix it — Dart's ECMAScript regex engine **does** support lookbehind (verified on Dart 3.x). If you must support an older SDK, iterate `allMatches` and drop any match preceded by a digit. Always pair with `!tollFree` in rule F11 regardless.

### 3.6 Composition rules (each maps to a weight in §5)

- `deadline ∧ threatVerb` → +14 (the pressure engine).
- `kycLure ∧ (urlAny ∨ callbackNo)` → +16.
- `credAsk ∨ credAskRev` → +35 (hard anchor).
- `remoteApp` → +12.
- `qrReceive ∧ receiveVerb` → +10; `qr ∨ scan` ∧ `pin` ∧ `receive` → +12.
- `urlAny` whose registrable domain ∉ brand allowlist **and** body names a bank → +18.
- `shortener ∨ ipLiteral ∨ waLink` → +12.
- brand token present in subdomain/path but registrable domain foreign → +7 (in addition to the +18).
- bank claim ∧ sender not trusted → +28.
- lookalike header → +35.

### 3.7 Escalation-only patterns

These are *not* fraud on their own, but promote `promo → fraud` or `check → warn`:

- Job/task ad **that asks for money up front** (registration/security deposit/training fee) or routes to **Telegram**.
- Investment ad promising **guaranteed / sure-shot / fixed** returns, or claiming **"SEBI registered"** while linking a non-allowlisted domain.
- Gambling/betting that asks for a **deposit to unlock a bonus**.
- Any promo that requests **Aadhaar/PAN/OTP** — immediately `fraud`.

---

## 4. OTP & credential messages

### 4.1 What a legitimate OTP looks like

Structural invariants across SBI/HDFC/ICICI/Axis/Kotak/PNB/Paytm/Amazon Pay:

1. **The code is 4–8 digits, isolated** — not adjacent to a currency marker, not part of a longer digit run.
2. **A purpose clause** follows: "for login", "for your UPI txn of Rs.X", "for adding a beneficiary", "for registration".
3. **Validity window**: "valid for 10 mins", "valid till 21:45".
4. **An anti-sharing instruction in the bank's own words**: "Do NOT share this OTP with anyone", "Never share your OTP, PIN or CVV", "even with bank staff".
5. **No URL.** Legitimate OTP SMS essentially never carries a link. A link next to an OTP is a strong fake signal.
6. **A branded sign-off** (`-HDFC Bank`, `-SBI`) and a `-T`/`-S` suffix.

### 4.2 What a fake one looks like

| Tell | Example | Predicate |
|---|---|---|
| **Asks you to *give* the code** | "Share the OTP sent to your phone to receive your refund" | `credAsk` (+35) — a real OTP SMS never asks for the OTP it just delivered |
| **OTP word, no code** | "Your OTP has been sent to your registered mobile. Click here to enter" | `otpWord ∧ ¬otpCode ∧ urlAny` → +18 |
| **OTP + link** (to a "verification" page) | "Verify your OTP at `hdfc-otp-verify.top`" | `otpWord ∧ urlAny ∧ ¬trusted` |
| **OTP for a transaction the user did not start, with a phone number to call** | "OTP 552311 for txn of Rs.8,999. If not you call 9xxxxxxxxx" | OTP + mobile callback + amount → `check`/`warn` |
| **Two OTPs in one message / multiple banks** | batching — real banks send one per event | 2+ 6-digit codes |

### 4.3 OTP-adjacent number disambiguation — the rule that protects the ledger

The classic collision:

- `OTP is 123456. Do not share.` → **OTP = 123456, no amount.**
- `Rs.123456 debited from a/c …` → **amount = 123456, no OTP.**
- `482913 is the OTP for your UPI txn of Rs.2,499.00 to BIGBASKET.` → **OTP = 482913, amount = 2499.00.** Two different numbers in one message; getting this wrong is a data-integrity bug *and* a security bug.

```dart
String? extractOtp(String s) {
  // must be preceded by an OTP keyword within 30 chars, and NOT preceded by a currency marker
  final m = RegExp(r'\b(?:otp|o\.t\.p|one[-\s]?time\s+password|verification\s+code|'
                   r'pass\s?code|security\s+code)\b[^0-9]{0,30}(\d{4,8})(?!\d)',
                   caseSensitive: false).firstMatch(s);
  if (m == null) return null;
  final start = m.start;
  // reject if a currency token sits immediately before the code
  if (RegExp(r'(?:rs\.?|inr|₹)\s*$', caseSensitive: false)
      .hasMatch(s.substring(0, m.start(1)!).trimRight())) return null;
  return m.group(1);
}
```

```dart
int? extractAmount(String s, {String? otp}) {
  final money = RegExp(r'(?:rs\.?\s*|inr\s*|₹\s*)(\d[\d,]{0,12}(?:\.\d{1,2})?)',
                       caseSensitive: false);
  final verb  = RegExp(r'\b(?:debited|credited|withdrawn|paid|spent|sent|'
                       r'transferred|received|refunded|reversed|charged|'
                       r'purchased|deposited|dr|cr|emi)\b', caseSensitive: false);
  final cands = money.allMatches(s).toList();
  int? best; int bestDist = 1 << 30;
  for (final m in cands) {
    final digits = m.group(1)!.replaceAll(',', '');
    if (otp != null && digits == otp) continue;          // never the OTP
    if (digits.length > 9) continue;                      // phone/ref/account
    // must be within 40 chars of a money verb
    final lo = (m.start - 40).clamp(0, s.length), hi = (m.end + 40).clamp(0, s.length);
    final near = s.substring(lo, hi);
    if (!verb.hasMatch(near)) continue;
    final d = _nearestVerbDistance(s, m.start);           // chars to closest verb
    if (d < bestDist) { bestDist = d; best = _toPaise(digits); }
  }
  return best;
}
```

**Hard invariant:** if `extractOtp != null` and no money verb within 40 chars of a currency token, the message is `otp` — full stop. An OTP message can never create a ledger entry, even when it contains an amount ("for txn of Rs.2,499"), because an OTP is not evidence of a completed transaction. The matching debit alert will arrive separately and be counted then.

---

## 5. The scoring model

### 5.1 Shape

Four saturating integer scores in `[0, 100]`, one per class, computed from a **single normalised string**, then a **hard-rule layer** that can override, then a **decision cascade**.

```
raw SMS
  → normalise()            §5.2
  → detectSuffix/Sender    §6
  → features()             §5.3 (boolean + extracted values, each with a name)
  → F, T, I, P             §5.4 weighted sums
  → hard rules H1–H6       §5.5
  → cascade                §5.6
  → verdict {class, suspicion, amount, isCredit, otp, flags[], reasons[]}
```

Every fired feature is retained as a **reason string** for the UI chip and for test assertions. No feature is anonymous.

### 5.2 Normalisation (do this first, always)

1. **Fold confusables**: map Cyrillic/Greek/fullwidth lookalikes to ASCII (`А→A, В→B, С→C, Е→E, Н→H, І→I, Ј→J, К→K, М→M, О→O, Р→P, Ѕ→S, Т→T, Х→X, У→Y`, Greek `Α→A, Β→B, Ε→E, Ζ→Z, Η→H, Ι→I, Κ→K, Μ→M, Ν→N, Ο→O, Ρ→P, Τ→T, Υ→Y, Χ→X`) plus `I/l/|/1` and `O/0` in **sender IDs only** (do not do this in message bodies — it would corrupt prose).
2. **Strip zero-width and bidi controls**: `U+200B–200F, U+202A–202E, U+2060, U+FEFF`.
3. **Normalise digits**: Devanagari `०–९` (U+0966–096F), Arabic-Indic `٠–٩` (U+0660–69), Bengali, Tamil, Telugu sets → ASCII. Dart has no built-in NFKC; use a bundled `intl`/`unorm_dart` dependency or a small const map. Document the choice.
4. **Lowercase a *copy*** for keyword matching; keep the original for display.
5. **Collapse whitespace**, keep one copy with punctuation and one stripped copy.

### 5.3 Weighted rule table — FRAUD score `F`

Positive weights (add, saturating at 100):

| # | Feature | Weight | Regex / predicate | Rationale |
|---|---|---|---|---|
| F1 | **Credential request** | **+35** | `credAsk ∨ credAskRev` (§3.5) | The only request a legitimate Indian bank never makes by SMS; RBI says so publicly. Near-decisive. |
| F2 | **Lookalike / malformed bank header** | **+35** | sender §6.3 `lookalike ∨ malformed` | Impersonation at the address layer; a real entity's header is registered to the real entity. |
| F3 | **Bank claim by untrusted sender** | **+28** | `brandToken ∧ senderTrust ∈ {numeric, +cc, unknown, lookalike}` | The impersonation itself, independent of payload. |
| F4 | **Non-allowlisted link host with brand in body** | **+18** | `urlAny ∧ registrableDomain ∉ allowlist(brand)` | Cheap-domain phishing kit; the dominant vector. |
| F5 | **KYC/PAN/Aadhaar lure + link or callback** | **+16** | `kycLure ∧ (urlAny ∨ callbackNo)` | Highest-volume Indian family; genuine KYC notices carry no link. |
| F6 | **Threat verb + deadline** | **+14** | `threatVerb ∧ deadline` | Manufactured urgency is the engine of every family. |
| F7 | **Shortener / IP literal / `wa.me` / APK** | **+12** | `shortener ∨ ipLiteral ∨ waLink ∨ apkLink` | Destination is unknowable offline ⇒ cannot be vetted. |
| F8 | **Remote-access app named** | **+12** | `remoteApp` | The takeover step; never legitimate for a bank. |
| F9 | **QR/PIN to *receive* money** | **+10** | `qrReceive ∧ receiveVerb` (or `pin ∧ receive`) | Impossible by construction — receiving needs no action (RBI). |
| F10 | **Refund / prize / cashback + action** | **+9** | `(refund\|cashback\|prize\|won) ∧ (credAsk ∨ urlAny ∨ callbackNo)` | Classic hook. |
| F11 | **Mobile-number callback + threat** | **+8** | `callbackNo ∧ ¬tollFree ∧ threatVerb` | Banks publish 1800/1860 lines; a 10-digit "bank" number is a call centre. |
| F12 | **Utility / parcel / lottery / task lure** | **+7** | sector nouns (§3.2 F6–F8, F10) | Non-bank pretexts used to reach the same credential box. |
| F13 | **Brand in subdomain/path, foreign registrable domain** | **+7** | `brand ∈ (subdomain ∪ path) ∧ brand ∉ registrableDomain` | `hdfcbank.com.kyc-review.top` defeats naive substring checks. |
| F14 | **Government impersonation + link** | **+6** | `(uidai\|aadhaar\|income tax\|rbi\|epfo) ∧ urlAny` | Aadhaar/PAN panic is a top-3 Indian lure. |
| F15 | **Urgency styling** | **+5** | `≥2 of {ALL-CAPS run ≥4, "!!", "URGENT", "ALERT", "FINAL NOTICE"}` | Costly-but-noisy; small weight because banks shout too. |
| F16 | **Length > 480 chars** | **+4** | `body.runes.length > 480` | Genuine DLT templates are one 160-char segment (up to ~3 concatenated); long bodies indicate OTT/email-style phishing. |
| F17 | **Grammar/phishing tells** | **+4** | `\b(?:kindly|dear\s+(?:customer|user|sir/madam)|your\s+account\s+will\s+be\s+block|do\s+the\s+needful)\b` | Translationese + missing articles correlate with kits; kept low. |
| F18 | **A second bank brand in one message** | **+4** | ≥2 distinct brand tokens | Real alerts come from one institution. |

Negative weights (subtract; floor 0):

| # | Feature | Weight | Regex / predicate | Rationale |
|---|---|---|---|---|
| N1 | **Trusted header for the claimed brand** | **−45** | sender ∈ allowlist(brand) (§6.2) | The single strongest exculpatory fact available offline. |
| N2 | **Genuine transaction template match** | **−20** | skeleton match (§5.7) | `Rs.A debited from a/c MASK on DATE to VPA X. Avl Bal Rs.B.` is a bank template, not a kit. |
| N3 | **No link, no callback, no credential ask** | **−15** | `¬urlAny ∧ ¬callbackNo ∧ ¬credAsk` | Phishing needs a channel to the victim. |
| N4 | **Allowlisted link host** | **−12** | `registrableDomain ∈ allowlist(brand)` | "Click here to view" on `hdfcbank.com` is normal. |
| N5 | **`do not share` + numeric OTP + no link** | **−10** | `doNotShare ∧ otpCode ∧ ¬urlAny` | Textbook legitimate OTP. |
| N6 | **Informational template match** | **−8** | statement/cheque/FD/dispatch/mandate skeleton | Removes the "bank + official-sounding words" false positive. |
| N7 | **Bank short code (1600-series) for the claimed brand** | **−6** | `sender ~ ^1600\d{4,}$ ∧ brand` | Regulated-sender series; weak because shared. |
| N8 | **Toll-free callback present** | **−5** | `tollFree` | Banks do put `1800…` in real fraud-report lines. |

`suspicion` mapping: `F ≥ 60 → warn`; `40 ≤ F < 60 → check`; else `clear`.
`class = fraud` requires `F ≥ 60` **or** a hard anchor (H1/H2).

### 5.4 Weighted rule tables — T / I / P

**Transaction score `T`** (class if `T ≥ 55` and not overridden)

| # | Feature | Weight | Predicate | Rationale |
|---|---|---|---|---|
| T1 | Debit verb | +30 | `\b(?:debited\|withdrawn\|paid\|spent\|sent\|transferred\|purchased\|dr)\b` | Money actually left. |
| T2 | Credit verb | +28 | `\b(?:credited\|deposited\|received\|refunded\|reversed\|cr)\b` | Money arrived (or came back). |
| T3 | Amount with currency token | +25 | `(?:rs\.?\|inr\|₹)\s*\d[\d,]*` | The atomic unit of the class. |
| T4 | Balance statement | +16 | `\b(?:avl\.?\s*bal\|available\s+bal(?:ance)?\|bal\.?)\b` | Banks append balance to every alert. |
| T5 | Masked account/card | +12 | `\b(?:[ax*]{2,}\s?\d{3,4}\|a\/c\s*[x*]{2,}\d{2,4}\|card\s*(?:no\.?\s*)?[x*]{2,}\d{4})` | Template furniture. |
| T6 | Reference ID | +10 | `\b(?:ref\|rrn\|utr\|txn\s*(?:id\|no)\|imps\|neft\|rtgs\|upi\s*ref)\b[:\s#]*\w{6,}` | Traceability ⇒ bank template. |
| T7 | Trusted header | +12 | §6.2 | Sender corroboration. |
| T8 | Transaction template match | +15 | §5.7 | Structural, not lexical. |
| T9 | `-T` suffix | +8 | suffix == T | Category prior. |
| T10 | Promo imperative | −25 | `applyNow ∨ optOut` | Offers are not money. |
| T11 | OTP present | −20 | `otpCode` | OTPs are never spends. |
| T12 | `-P` suffix | −10 | suffix == P | Promo pipe. |

**Informational score `I`** (class if `I ≥ 45` and `T < 55`)

| # | Feature | Weight | Predicate | Rationale |
|---|---|---|---|---|
| I1 | OTP pattern | +26 | `otpWord ∧ otpCode ∧ doNotShare` | → forces class `otp`. |
| I2 | Lifecycle nouns | +20 | `\b(?:statement\|cheque\|cleared\|matur\w*\|dispatch\w*\|e-?mandate\|passbook\|branch\|holiday\|minimum\s+balance\|due\s+date)\b` | Administrative, not money. |
| I3 | "No action needed" | +12 | `\b(?:no\s+action\s+(?:needed\|required)\|for\s+your\s+information\|ignore\s+if)\b` | Explicitly inert. |
| I4 | Trusted header | +10 | §6.2 | |
| I5 | `-S` suffix | +8 | suffix == S | |
| I6 | Debit + amount | −20 | `T1 ∨ T2` with `T3` | Then it is a transaction. |
| I7 | Promo imperative | −15 | | |
| I8 | Credential ask | −40 | | Escalate, do not inform. |

**Promo score `P`** (class if `P ≥ 45` and `T < 55`)

| # | Feature | Weight | Predicate | Rationale |
|---|---|---|---|---|
| P1 | Opt-out / legal footer | +24 | `optOut ∨ tAndC` | TRAI-mandated in promo templates only. |
| P2 | Imperative | +22 | `applyNow` | |
| P3 | Discount language | +16 | `\d{1,3}\s*%\s*off` \| `cashback` \| `voucher` \| `flat\s+rs` | |
| P4 | Sector keyword | +14 | §2.3 | |
| P5 | Untrusted / numeric sender | +10 | | Promo almost never uses DLT headers. |
| P6 | Short link | +8 | `shortener` | |
| P7 | Pre-approval flattery | +12 | | |
| P8 | Debit + amount | −20 | | |
| P9 | OTP | −18 | | |
| P10 | Credential ask | −50 | | That is fraud, not marketing. |

### 5.5 Hard rules (evaluated before the cascade, in this order)

- **H1 — Credential ask from a *trusted* sender ⇒ `fraud`.** This is the exception to "trusted header wins". A message from `VM-HDFCBK-T` that asks for an OTP is not HDFC. (Trust grants authority over *amounts*, never over *credentials*.)
- **H2 — Lookalike/malformed header + bank claim ⇒ `fraud`** regardless of F arithmetic.
- **H3 — Genuine-wins rule.** If `senderTrust == trusted` ∧ `txTemplateMatch` ∧ `¬credAsk` ∧ `¬remoteApp`, then `class = transaction`, `suspicion = clear`, `F` is floored to 0. **`urlAny` alone cannot defeat this.** This is the rule the product brief demands: a real bank header plus a matching debit template wins even with "click here to view".
- **H4 — `-P` suffix + money claim ⇒ `check`, never `transaction`.** If a promo-suffixed message asserts a debit, do not ledger it; surface "Promotional sender claims a transaction — verify in your bank app."
- **H5 — OTP precedence.** If `otpCode ∧ ¬credAsk` then class ∈ {`otp`, `fraud`}; never `transaction`.
- **H6 — Untrusted money event ⇒ ledger excluded.** Any `transaction`/credit claim whose sender is not `trusted` gets `countsTowardLedger = false`, `verified = false`, `suspicion ≥ check`. The app may *show* the claim but must never treat it as confirmed money (the seller/`Rs.15,000 credited` scam, F12).

### 5.6 Decision cascade

```dart
SmsVerdict classify(NormalizedSms s) {
  final f = s.toFeatures();                       // §5.3–5.4
  // ---- hard rules -------------------------------------------------------
  if (f.credAsk && f.senderTrust == SenderTrust.trusted) return verdict(fraud, warn, f, ['H1']);
  if (f.lookalikeHeader && f.bankClaim)                  return verdict(fraud, warn, f, ['H2']);
  if (f.senderTrust == SenderTrust.trusted && f.txTemplate &&
      !f.credAsk && !f.remoteApp)                        return verdict(transaction, clear, f, ['H3']);
  if (f.suffix == 'P' && f.moneyEvent)                   return verdict(promo, check, f, ['H4']);
  if (f.otpCode != null && !f.credAsk)                   return verdict(otp, f.fraud >= 40 ? check : clear, f, ['H5']);

  final F = f.fraudScore, T = f.txScore, I = f.infoScore, P = f.promoScore;

  if (F >= 60) return verdict(fraud, warn, f);
  if (T >= 55) {
    final led = f.senderTrust == SenderTrust.trusted;     // H6
    return verdict(transaction, F >= 40 ? warn : (led ? clear : check), f,
                   led ? [] : ['H6']);
  }
  if (F >= 40) return verdict(_bestOf(T, I, P), check, f);
  if (I >= 45) return verdict(informational, clear, f);
  if (P >= 45) return verdict(promo, f.scammyOffer ? check : clear, f);
  return verdict(informational, clear, f);               // low-confidence default: never warn
}
```

Note the deliberate fall-through: **when nothing scores, we say `informational` and stay quiet.** The cost of an unnecessary phishing warning is higher than the cost of an unflagged unknown.

### 5.7 Offline template fingerprinting (the precision workhorse)

Bundle ~40–80 skeletons per supported bank, with variable slots normalised before comparison:

```
'Rs.<AMT> debited from a/c <MASK> on <DATE> to <CP>. Avl bal Rs.<AMT>'
'<AMT> is your OTP for <PURPOSE>. Valid for <N> mins. Do NOT share'
'Your a/c <MASK> has been credited with Rs.<AMT> on <DATE> by <CHANNEL>'
'EMI of Rs.<AMT> debited from a/c <MASK> for Loan <REF> on <DATE>'
'Cheque no. <REF> for Rs.<AMT> has been cleared from a/c <MASK> on <DATE>'
```

Normalise by replacing `\d[\d,]*\.?\d*` → `<AMT>`, `[xX*]{2,}\d{2,4}` → `<MASK>`, `\d{2}[-/]\d{2}[-/]\d{2,4}` → `<DATE>`, VPAs/emails → `<CP>`, then compute token-set Jaccard ≥ 0.82 against the brand's skeletons. This is what makes `-20` (N2) trustworthy, and it is the difference between 85 % and 97 % precision on transactions. Skeletons are derived from the user's own device (a "learn my bank's format" onboarding step) or shipped per-bank and versioned.

### 5.8 Worked traces

| Message | Fired | Score | Verdict |
|---|---|---|---|
| `VM-HDFCBK-T`: "Rs.450.00 debited … Avl bal Rs.12,345.67. Not you? Call 18001201243." | N1 −45, N2 −20, N3 −15, N8 −5 | F=0 | `transaction`, clear, ledger ✔ |
| `VM-HDFCBK-T`: "Rs.1,000 debited … Click here to view: `https://hdfcbank.com/txn/ab12`. Bal 11,324.67" | F4 ✗ (allowlisted), N1/N2/N4 | F=0 | `transaction`, clear — **link does not demote** (H3) |
| `+91 90987 65432`: "Your SBI account will be blocked within 24 hrs due to incomplete KYC. Click: `sbi-kyc-verify.top/upd`" | F3 +28, F4 +18, F5 +16, F6 +14, F12 +7 | F=83 | `fraud`, warn |
| `AD-HDFCBNK-T`: "Rs.12,499 debited from a/c XX8842. If not you, verify now at `hdfc-secure-verify.xyz/login`" | F2 +35, F3 +28, F4 +18, N2 −20 | F=61 | `fraud`, warn (also H2) |
| `VM-PAYTMB`: "Your wallet is blocked. Scan this QR to receive your refund of Rs.1,500. `bit.ly/ptm-refund`" | F2 +35, F3 +28, F7 +12, F9 +10, F10 +9 | F=94 | `fraud`, warn |
| `-P` message: "Get a lifetime free HDFC credit card … Apply now `hdfcbank.com/cc` T&C. To stop receiving SMS STOP" | P1 +24, P2 +22, P4 +14, N4 −12 | P=48, T=0 | `promo`, clear |
| Genuine tx + cross-sell tail (`Rs.21 debited … Get 5% cashback … To stop receiving`) | T1 +30, T3 +25, T4 +16, T7 +12, T8 +15, T10 −25, P1/P2 (promo only) | T=73, P=46 | `transaction`, `containsOffer=true`, clear |
| `Rs.15,000 credited to a/c XX9082 … Ship the item now.` from a 10-digit number | F3 +28, T-sum high, N2 −20 | F≈43 | `transaction` claim, `suspicion=check`, **`countsTowardLedger=false`** (H6) |
| `482913 is the OTP for your UPI txn of Rs.2,499.00 to BIGBASKET.` | I1 +26, T11 −20, N5 −10 | I=26, T=0 | `otp`, amount **not** parsed (§4.3) |

---

## 6. Sender-ID trust model (offline, no registry)

### 6.1 Why a bundled list is legitimate

DLT headers are stable by construction — a bank does not change `HDFCBK` — so a **bundled, versioned allowlist** is a sound offline approximation of the registry. Its weakness is staleness, so it must be **data, not code**, shipped with a version stamp, and refreshed with app updates. Design for the list being partial: everything not in it is *unknown*, not *guilty*.

### 6.2 Trust tiers

| Tier | Definition | Trust | Used for |
|---|---|---|---|
| `trusted` | Header (after prefix/suffix strip and homoglyph fold) ∈ allowlist **and** the claimed brand matches the allowlist entry's brand | full | Transaction template authority (N1, H3), ledger eligibility |
| `brandedUnknown` | Well-formed `XX-HEADER[-SUF]`, 6–8 uppercase alnum, not in allowlist | medium | Informational/promo; never ledger |
| `govt` | `-G` suffix or known govt header | medium for info | never bank tx |
| `shortCode1600` | `^1600\d{4,}$` | medium | informational only |
| `shortCode140` | `^140\d{4,}$` | none for banking | promo only |
| `numeric10` | 10-digit Indian mobile, with or without `+91` | **none** | +28 if bank claim; ledger excluded |
| `international` | `+` with non-91 country code, or >10 digits | **none** | +28 if bank claim |
| `lookalike` | Near-miss of an allowlisted header (§6.3) | **negative** | +35 |
| `unparseable` | Anything else (spaces, lowercase mixes, brand names as plain words) | none | +35 if it also contains a brand token |

### 6.3 Lookalike / malformed heuristics

```dart
bool isLookalike(String header, Set<String> allow) {
  final h = foldConfusables(header.toUpperCase());
  if (allow.contains(h)) return false;
  // 1. contains a brand token but is not the registered code
  for (final b in brandTokens) { if (h.contains(b)) return true; }
  // 2. edit distance 1–2 from an allowlisted code (and length within ±2)
  for (final a in allow) {
    if ((h.length - a.length).abs() <= 2 && levenshtein(h, a) <= 2) return true;
  }
  // 3. structural violations
  if (h.length > 8) return true;
  if (!RegExp(r'^[A-Z0-9]{4,8}$').hasMatch(h)) return true;      // spaces/dots/dashes inside
  if (RegExp(r'(?:BANK|SBI|HDFC|ICICI|AXIS|KYC|ALERT|INFO|NPCI|GOV|IND)$')
        .hasMatch(h)) return true;
  return false;
}
```

Additional suspicious-header rules:

- `header.contains(RegExp('[a-z]'))` after strip — vendor headers are uppercase; a lowercase `l` impersonating `I` (`ICIClB`) is the canonical homoglyph trick.
- Header length > 8 (before suffix) — outside the DLT grammar.
- More than one `-` in the pre-suffix header (`SBI-KYC-ALERT`).
- A brand name as a plain word (`HDFC BANK`, `SBI`) — not a registered code.
- **Two different brand tokens across header and body** (`VM-HDFCBK` body says "ICICI") — brand confusion, +10.

### 6.4 Homoglyph folding table (sender IDs only)

| Confusable | → | Sources |
|---|---|---|
| `А а В С Е Н І Ј К М О Р Ѕ Т Х У` | `A a B C E H I J K M O P S T X Y` | Cyrillic |
| `Α Β Ε Ζ Η Ι Κ Μ Ν Ο Ρ Τ Υ Χ` | `A B E Z H I K M N O P T Y X` | Greek |
| `l I ǀ 1 \|` | `I` | Latin/digit |
| `0 O o` | `O` | digit/letter |
| `５ Ａ` (fullwidth) | `5 A` | fullwidth forms |

Apply to the **sender only**. In the body, keep the original text: folding `l→I` would destroy words.

### 6.5 Starter allowlist (data to verify before shipping)

> ⚠ **Every row must be checked against the bank's own published domain before release**, and re-checked each release. Header codes below are commonly observed examples (e.g. `VK-SBIINB`, `VM-HDFCBK`, `JD-ICICIB` are documented in [independent KYC-scam analysis](https://scantotal.net/blog/kyc-update-scam-india/)), not a certified registry extract. Keep this file generated from a reviewable table, with a `verified_on` date per row.

| Brand | Header codes (examples) | Allowed registrable domains |
|---|---|---|
| SBI | `SBIINB`, `SBICRD`, `SBINOT` | `sbi.co.in`, `onlinesbi.sbi`, `onlinesbi.com`, `sbicard.com` |
| HDFC Bank | `HDFCBK`, `HDFCCC`, `HDFCLT` | `hdfcbank.com`, `hdfclife.com`, `hdfcsec.com` |
| ICICI Bank | `ICICIB`, `ICICIC` | `icicibank.com`, `icicidirect.com` |
| Axis Bank | `AXISBK`, `AXISCC` | `axisbank.com`, `axis.bank.in` |
| Kotak | `KKBK`, `KOTAKB` | `kotak.com`, `kotakbank.com` |
| PNB | `PUNB`, `PNBANK` | `pnbindia.in` |
| Bank of Baroda | `BARB`, `BOBTXN` | `bankofbaroda.in`, `bankofbaroda.com` |
| Canara | `CANBK` | `canarabank.com` |
| Union Bank | `UBIN` | `unionbankofindia.co.in` |
| IDFC FIRST | `IDFB`, `IDFCBK` | `idfcfirstbank.com` |
| YES Bank | `YESBK` | `yesbank.in` |
| IndusInd | `INDB`, `INDUSB` | `indusind.com` |
| Federal | `FDRL` | `federalbank.co.in` |
| RBL | `RATN`, `RBLBNK` | `rblbank.com` |
| Bandhan | `BDBL` | `bandhanbank.com` |
| AU Small Finance | `AUBANK` | `aubank.in` |
| Paytm / PPB | `PAYTMB`, `PYTMBN` | `paytm.com`, `paytmbank.com`, `paytm.in` |
| PhonePe | `PHONPE` | `phonepe.com` |
| Google Pay | `GPAY`, `GOOGLP` | `pay.google.com`, `google.com` |
| Amazon Pay | `AMZNIN`, `AMZNPY` | `amazon.in`, `amazon.com` |
| Mobikwik | `MOBIKW` | `mobikwik.com` |
| CRED | `CRED`, `CREDCL` | `cred.club` |
| NPCI / BHIM | `NCPIPL`, `BHIMUP` | `npci.org.in`, `bhimupi.org.in` |
| UIDAI | `UIDAI` (with `-G`) | `uidai.gov.in` |
| India Post | `INDPOST`, `INDPST` | `indiapost.gov.in` |

Also bundle a **`tollFree` list per bank** (e.g. `18001201243`, `18001080`, `1800112211`) so "Call this number" can be positively matched — and a **`knownCallback` list** for the F11 penalty to be fair.

### 6.6 Sender is not enough — and we say so

Two limits must be documented in-product:

1. **Spoofing exists.** A determined attacker can present a header; TRAI's own enforcement actions exist because header misuse happens. So `trusted` grants *template authority*, not *identity proof*.
2. **The user's own bank set is a signal.** Onboarding asks which banks/wallets the user actually has. A flawless `-T` debit template from a bank the user does not hold is not "trusted" for the user — it is `brandedUnknown` + `check` (a common smishing pattern: impersonate a bank you don't use, where the user has no mental template to compare against).

---

## 7. UX guidance — warn without crying wolf

### 7.1 Three surfaces, one message list

| State | Surface | Copy |
|---|---|---|
| `clear` transaction | Normal row, amount in the ledger, bank chip | "₹450 · HDFC Bank · 12 May" + (if offer) a quiet chip: "Includes an offer" |
| `clear` promo | "Offers" tab, collapsed, never notified | "Promotional · HDFC Bank" |
| `check` | Normal row + amber chip, tap for reasons | "Unverified sender — check before you act" |
| `warn` (fraud) | Inline card **above** the message, message body collapsed, quarantine copy stored | "Looks like phishing" |

**The warning card (fraud)**

> **Looks like phishing**
> This message pretends to be from HDFC Bank, but it was not sent from HDFC Bank's registered sender ID.
> · It asks you to share an OTP — your bank never asks for an OTP, PIN or CVV.
> · The link goes to `hdfc-secure-verify.xyz`, which is not an HDFC Bank website.
> **Do not tap the link.** Open your bank's app, or call the number on the back of your card.
> [Show message] [Move to Quarantine] [Not a scam]

Non-negotiable properties of that card:

- **A reason list, always.** Never a bare "Suspicious". Every chip maps 1:1 to a fired feature, so the user can disagree with a specific claim.
- **"Looks like", not "is".** No "Confirmed fraud", no "100 %", no confidence percentage.
- **Never render the URL as a tappable link.** Show it as monospace plain text, with the registrable domain emphasised (`hdfc-secure-verify.xyz` bolded) so the mismatch is visible.
- **Never auto-open, never auto-fetch, never open a WebView, never preload a preview.** No network call on reveal. The app must not dereference attacker-controlled URLs even for "checking" — that would leak the user's IP and confirm the number is live.
- **Never auto-delete.** Quarantine is *move + keep*: the text stays on device, recoverable, because a wrongly quarantined bank alert is a missed fraud alert.
- **Always offer the real path out**: "Open HDFC Bank app" (deep link to the installed app, not the web), or the bundled toll-free number with a copy button.
- **Always offer "Not a scam".** Feedback flips a `userWhitelist` flag on that sender for that user and is logged locally; it improves precision and preserves trust.

### 7.2 What the app must *not* claim

- ❌ "This is a scam" / "Confirmed phishing" — we infer, we do not verify.
- ❌ "Safe" / "Verified" on a `clear` message — absence of signals is not proof (see §6.6, spoofing).
- ❌ Any numeric confidence, accuracy percentage, or "risk score 87/100" — false precision invites reliance.
- ❌ "Your bank will never…" as an absolute about *other* banks' practices — scope to the OTP/PIN/CVV rule, which is genuinely universal and RBI-backed.
- ❌ Legal or recovery promises. Point to `1930` / `cybercrime.gov.in` as *resources*, not as outcomes.
- ❌ Anything about the user's money being gone. We only see text.

### 7.3 Tone and accessibility

- Colour is never the only carrier: every state has an icon **and** a word (matches the repo's existing status-colour convention).
- Numbers and amounts are localised (`₹` + Indian grouping) only in *our* chrome, never re-formatted inside the quoted message.
- Hinglish/Devanagari messages get the same treatment; the warning copy should exist in English + Hindi at minimum.
- 360 px / 1.3× text: the reason chips must wrap, and the card must never push the amount off-screen.
- Screen readers: announce the state first ("Warning. Looks like phishing."), then reasons.

### 7.4 Quarantine behaviour

- Messages with `warn` move to **Settings → Quarantine** (badge count, reviewable list).
- Quarantined items keep their raw text, sender, and the fired feature list (so support can audit).
- The user can restore, delete, or report; "report" composes a *local* note + optional share-sheet export (still user-initiated, still on-device until the user chooses otherwise).
- Quarantined SMS never contribute to the ledger, and never appear in spending analytics.

---

## 8. Privacy

### 8.1 The data-flow promise

```
SMS (device inbox) → on-device parser → verdict + parsed fields
                                    ├→ local DB (SQLite/Isar), encrypted at rest
                                    └→ UI
No network egress. No analytics containing message content. No server-side model.
```

Concretely:

1. **Zero network for classification.** The classifier is pure Dart over the message string. Assert this in code review: no `http`, no `dio`, no `url_launcher`, no `WebView` in the classification path.
2. **No raw SMS leaves the device.** Not for "improving detection", not for crash reports, not for support. If the user exports, that is an explicit, local, user-initiated file they can choose to share.
3. **Minimise what we persist.** Store the parsed verdict + amount + masked account + sender, and the raw body *only* for quarantined items and only because the user may need to read it. Consider storing only a hash + excerpt for `clear` promos.
4. **Redact OTPs at rest.** Never persist the OTP digits. Show them only in the message view. (`otp` extraction is transient.)
5. **Redact in logs and crash reports.** Scrub `\d` runs in amounts, account numbers and OTPs before any `print`/`log`/Crashlytics breadcrumb; better, disable body logging entirely in release.
6. **Permission honesty.** Read only what you need, when you need it: prefer the SMS content-provider query filtered to bank senders over a blanket dump. Exclude personal 1:1 threads by default.
7. **Deletion is real.** "Delete all data" wipes the DB, the quarantine store and the learned templates, and says so.

### 8.2 Android/Play policy caveat — flag this early

`READ_SMS` is a **restricted permission** under Google Play policy; apps may only hold it if SMS is core to their documented function (default SMS handler, backup/restore, or certain financial-transaction use cases). A budgeting app that reads bank SMS sits in the grey zone and has been rejected historically. Mitigations to design for now, not later:

- **Notification Listener** (`BIND_NOTIFICATION_LISTENER_SERVICE`) reading bank-app notifications — no restricted permission, but misses SMS-only alerts.
- **Manual forward/paste**: the user shares an SMS to the app (`ACTION_SEND` intent) — zero permissions, but not automatic.
- **Default-SMS-app route** if the product can absorb it.

Whatever the path, the classifier is identical: it takes a `(sender, body, timestamp)` triple. **Keep the ingestion layer swappable behind an interface so the policy decision does not touch the detection code.**

### 8.3 How to explain it in-app

Onboarding card, 3 lines, no legalese:

> **Everything stays on your phone**
> Your bank messages are read and checked on this device. Nothing is uploaded, and there is no account to create.
> We store only what the app needs (amount, sender, and the messages you keep). Delete everything any time in Settings → Privacy.

Then, in Settings → Privacy, the specifics a sceptic wants:

- **What we read:** bank/UPI alerts from the SMS inbox (or notifications you allow).
- **What we store:** parsed transactions, quarantined messages. Not your OTPs.
- **What we send:** nothing. The app works in aeroplane mode — try it.
- **Permissions:** why each is needed, with a "revoke" link to system settings.
- **DPDP note:** processing is local, so there is no transfer to a data fiduciary; retention is user-controlled; deletion is immediate.

A useful trust-builder: a **"Works offline" badge** and an explicit statement that detection runs with the radio off. That is verifiable by the user and true by construction.

---

## 9. Never do this

| # | Never | Why |
|---|---|---|
| 1 | Auto-open, auto-fetch, preview, or resolve any URL from an SMS | Leaks IP/liveness to the attacker; the single most damaging "convenience" feature. |
| 2 | Render URLs as tappable links in the message view | A mis-tap is the whole attack; show the registrable domain as text instead. |
| 3 | Parse an OTP as an amount, or an amount as an OTP | Corrupts the ledger and can mask a real spend (§4.3). |
| 4 | Treat "contains a link" as fraud evidence by itself | Genuine bank alerts say "click here to view"; this is the #1 false-positive source. |
| 5 | Let a `-T` header override a credential ask | A spoofed or misused header must not launder an OTP request (H1). |
| 6 | Auto-delete, auto-block, or silently hide a message | A suppressed genuine fraud alert is worse than a shown spam. Quarantine, never destroy. |
| 7 | Claim certainty, or show a fake confidence number | We infer from text only; overclaiming invites reliance and, later, blame. |
| 8 | Trust a domain because it *contains* the bank name | `hdfc-bank-verify.xyz` and `hdfcbank.com.evil.top` both contain it. Compare the registrable domain. |
| 9 | Persist OTPs, CVVs, or full account numbers | Need-to-know only; redact at rest and in logs. |
| 10 | Auto-dial or auto-SMS a callback number from a message | Premium-rate and social-engineering vectors. Show it; the user decides. |
| 11 | Treat a shortener as "safe" because it looks short, or as "malicious" because it is short | Offline we cannot resolve it. Report "destination unknown". |
| 12 | Use the sender ID as the sole trust signal | Spoofing is documented; TRAI enforcement exists because it happens. |
| 13 | Send SMS bodies to any backend, "just for analytics" | Destroys the entire privacy proposition and creates a honeypot. |
| 14 | Run OCR/screen capture on other apps to read messages | Out of scope, and a permissions nightmare. |
| 15 | Classify by first keyword match and return early | Every family shares keywords with genuine traffic; the score exists to arbitrate. |
| 16 | Warn on `unknown` | Silence is the correct output for uncertainty; the cost asymmetry demands it. |
| 17 | Let a promo tail demote a valid debit | The bank's own marketing must not cost the user their ledger (§2.1). |
| 18 | Count an untrusted "Rs.X credited" as money in | The seller scam depends on exactly this (F12/H6). |
| 19 | Ship an allowlist without a verified-on date | Stale trust data silently becomes wrong trust data. |
| 20 | Hard-code Hindi/English only in the warning copy | The scam corpus is multilingual; the UI must be too. |

---

## 10. Ambiguity & edge cases

| # | Case | Why it is hard | Ruling |
|---|---|---|---|
| 1 | Genuine debit + cross-sell tail | Promo signals inside a real transaction | `transaction`, `containsOffer=true`, `clear`. Promo features never touch `F`. |
| 2 | Genuine debit + "Click here to view" | Link presence looks like phishing | H3: trusted header + template ⇒ `transaction`, `clear`. `N4` applies if the host is allowlisted. |
| 3 | Bank's real KYC reminder vs KYC scam | Both say "KYC", both name the bank | Real: no link, no deadline, "visit your branch", often `-S`. Scam: link/callback + "24 hrs"/"blocked". Rule: `kycLure ∧ (url ∨ callback) ∧ (deadline ∨ threat)` ⇒ fraud; `kycLure` alone ⇒ informational. |
| 4 | Salary credit from an employer's header | Corporate sender, bank name in body | `transaction` with `senderTrust=brandedUnknown` ⇒ `check`, ledger **excluded** until the user confirms. Offer "Trust this sender". |
| 5 | "Did you make this txn? Call 1800…" | Asks the user to *act*, which smells like social engineering | Genuine: toll-free, no link, no OTP request ⇒ `informational`, `clear`. If the number is a 10-digit mobile ⇒ F11, `check`/`warn`. |
| 6 | OTP SMS that mentions an amount | Two numbers, one message | `otp`; amount deliberately **not** parsed (§4.3). The matching debit alert will be the ledger entry. |
| 7 | OTP requested by a "bank officer" over a link | Hybrid | `credAsk ∧ url` ⇒ `fraud` (F1+F4). |
| 8 | Merchant name that looks like a domain | `AMAZON PAY INDIA PVT LTD` | Domain extractor requires a TLD from the list and a plausible host shape; merchant strings are not URLs. Add a negative test. |
| 9 | Devanagari / Hinglish / transliterated SMS | Keyword lists are English | Normalise digits; keep a Hindi/Hinglish keyword pack ("खाता", "बंद", "KYC अपडेट", "turant", "khata band"). Until it exists, these fall to `informational` (silent) — document the gap. |
| 10 | Regional numeral systems | `१२३४` is 1234 | Digit-fold table (§5.2). Mandatory before amount/OTP parsing. |
| 11 | Multiple amounts ("Rs.500 debited, bal Rs.4,500") | Which is the transaction? | Nearest-to-verb wins; balance nouns disqualify a candidate (`Avl bal Rs.X`). |
| 12 | Refund / reversal messages | Credit verb + "refund" + sometimes a link | `transaction` (credit), `clear` if trusted; link ⇒ `check` only if host is not allowlisted. |
| 13 | UPI **collect request** ("Rahul has requested ₹500") | Not a payment; a request | `informational` + `check` + explicit copy: "This is a *request* for money, not a payment. Approving it sends money." |
| 14 | E-mandate / autopay debit | Recurring, expected | `transaction`, `clear`; tag `recurring`. |
| 15 | Fake credit alert (seller scam) | Clean template, wrong sender | `transaction` claim, `check`, ledger excluded (H6). Copy: "Confirm in your bank app before shipping/acting." |
| 16 | Courier/parcel with a real courier header + link | Real logistics brands do send links | Add courier brands to the allowlist (separate table); without it, `check`, not `warn`. |
| 17 | Government `-G` sender with a link | Real govt notices do carry links | Trust the `-G` + allowlisted `.gov.in` ⇒ `informational`; `-G` + non-gov domain ⇒ fraud (F14). |
| 18 | Duplicate/replayed messages | Legit retries vs replayed phishing | Dedupe by (sender, body hash, 60 s window); never double-count the ledger. |
| 19 | Zero-width characters inside a brand name | `HDFC\u200BCBK` | Strip before *any* comparison; add a fixture. |
| 20 | Message from a bank the user doesn't hold | No mental template to compare | `brandedUnknown` + `check` (§6.6). |
| 21 | Bank maintenance/holiday notice with a link | Real and link-bearing | `informational`, `clear` if host allowlisted. |
| 22 | `-P` message that contains "Rs.X debited" | Category violation | H4: `promo` + `check`. Do not ledger. |
| 23 | Very short messages ("OTP 552211") | No context | `otp` if a code + any OTP-adjacent cue; else `informational` silent. |
| 24 | SMS with only a link | Unclassifiable | `check` (never `warn`): "This message is only a link. We can't tell who sent it." |
| 25 | International roaming debit in foreign currency | Amount + FX line | `transaction` if template matches; parse the INR figure if present, else the first currency amount with a tag `foreignCurrency`. |
| 26 | Two different 6-digit numbers, one flagged "OTP" | Ambiguous | Prefer the one adjacent to the OTP keyword; if both, take the first and set `ambiguousOtp` (don't ledger). |
| 27 | `-U` or missing suffix | Non-standard/partial rollout | Zero weight either way; classify on content (§1.3). |
| 28 | A genuine alert forwarded by a friend | Sender is a personal number, body is a real bank template | `check`, ledger excluded; copy explains it was forwarded. |

---

## 11. Implementation plan for this repo

```
lib/domain/sms/
  normalise.dart        // confusables, zero-width, digit folding, NFKC shim
  sender_id.dart        // prefix/suffix parse, tiers, allowlist lookup, lookalike
  features.dart         // named boolean/value features, regexes in one place
  templates.dart        // skeleton normaliser + Jaccard matcher
  extract.dart          // extractAmount, extractOtp, extractRef, extractBalance
  classify.dart         // hard rules H1–H6 + cascade + SmsVerdict
  explain.dart          // feature name → localised reason string
data/sender_allowlist.dart   // generated, with verified_on dates per row
test/fixtures/spam_corpus.dart   // Appendix A
test/sms_classifier_test.dart    // golden tests over the corpus
```

Acceptance gates for the classifier PR:

1. **Corpus green**: every fixture in Appendix A yields its `expected` class and `suspicion`.
2. **Zero ledger corruption**: no fixture produces an amount when an OTP is present; no `unverifiedSender` fixture sets `countsTowardLedger = true`.
3. **Zero false fraud on `tx-*`**: any `fraud` verdict on a genuine-transaction fixture is a hard test failure.
4. **Determinism**: same input ⇒ same verdict; no clocks, no locale, no network.
5. **Performance**: < 3 ms per message on a mid-range Android device (regex precompiled as `static final`, no `RegExp()` in loops).
6. **Explainability**: every non-`clear` verdict carries ≥ 1 reason code.

---

## Appendix A — Dart-ready fixture corpus

`test/fixtures/spam_corpus.dart` — **77 messages** (18 transaction, 14 informational, 8 OTP, 14 promo, 23 fraud). Domains, numbers and account masks are **illustrative**; none were registered, resolved or contacted.

```dart
// test/fixtures/spam_corpus.dart
//
// Golden corpus for the offline SMS classifier. Every fixture is a realistic
// Indian bank/UPI/wallet message. Malicious domains and phone numbers are
// illustrative only — they were never registered, resolved or contacted.
//
// Two axes are asserted separately:
//   expected  -> what the message *is*          (the 4 product classes + otp)
//   suspicion -> how much we trust it           (clear / check / warn)
//
// A `transaction` can legitimately carry `check`/`warn` (unverified sender);
// in that case `countsTowardLedger` MUST be false (hard rule H6).

enum SmsClass { transaction, informational, otp, promo, fraud }

enum Suspicion { clear, check, warn }

class SmsFixture {
  const SmsFixture({
    required this.id,
    required this.sender,
    required this.body,
    required this.expected,
    required this.suspicion,
    required this.reason,
    this.countsTowardLedger = true,
    this.tags = const [],
  });

  final String id;
  final String sender;
  final String body;
  final SmsClass expected;
  final Suspicion suspicion;
  final String reason;
  final bool countsTowardLedger;
  final List<String> tags;
}

const List<SmsFixture> spamCorpus = <SmsFixture>[
  // ─────────────────────────── genuine transactions ───────────────────────────
  SmsFixture(
    id: 'tx-01',
    sender: 'VM-HDFCBK-T',
    body: 'Rs.450.00 debited from a/c XX1234 on 12-05-26 to VPA swiggy@okaxis. '
        'Avl bal Rs.12,345.67. Not you? Call 18001201243.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Trusted header + debit verb + amount + masked a/c + balance; the 1800 number is a bank toll-free.',
    tags: ['trustedHeader', 'balancePresent'],
  ),
  SmsFixture(
    id: 'tx-02',
    sender: 'VK-SBIINB-T',
    body: 'Your a/c XX9082 debited Rs.2,000.00 on 03-06-26 by UPI to 9876543210@ybl. '
        'Bal Rs.15,220.10.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'UPI debit template, amount anchored to "debited", balance present.',
    tags: ['trustedHeader', 'upi'],
  ),
  SmsFixture(
    id: 'tx-03',
    sender: 'AD-ICICIB-T',
    body: 'ICICI Bank: Rs 1,299.00 spent on your Credit Card XX4412 at AMAZON on 11-06-26. '
        'Avl limit Rs 78,701.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Card-spend template with merchant and available limit.',
    tags: ['trustedHeader', 'card'],
  ),
  SmsFixture(
    id: 'tx-04',
    sender: 'VM-AXISBK-T',
    body: 'Rs.5,000 debited from A/c XX7810 on 09-06-26. IMPS Ref 609812345678. '
        'Avl Bal 22,310.44.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'IMPS reference + balance; no promo or credential content.',
    tags: ['trustedHeader', 'imps'],
  ),
  SmsFixture(
    id: 'tx-05',
    sender: 'JD-KKBK-T',
    body: 'Kotak: Rs.249.00 debited from a/c **3344 on 10-06-26 towards Netflix. '
        'Bal Rs.9,110.02.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Merchant debit with balance; star-mask account format.',
    tags: ['trustedHeader', 'subscription'],
  ),
  SmsFixture(
    id: 'tx-06',
    sender: 'AD-PUNB-T',
    body: 'PNB: Rs.12,000.00 credited to your a/c 0XXXXXX7712 on 01-06-26 '
        '(NEFT: SALARY JUN). Bal Rs. 34,009.11.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Salary credit via NEFT from a trusted header; credit verb + balance.',
    tags: ['trustedHeader', 'credit'],
  ),
  SmsFixture(
    id: 'tx-07',
    sender: 'VM-BARB-T',
    body: 'BOB: Your a/c XX5590 has been debited by Rs.800.00 on 07-06-26 at '
        'ATM CASH WDL. Bal 6,420.15.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'ATM withdrawal template; passive "has been debited" still matches the debit rule.',
    tags: ['trustedHeader', 'atm'],
  ),
  SmsFixture(
    id: 'tx-08',
    sender: 'VK-CANBK-T',
    body: 'Rs.150.00 debited from a/c XX2231 to VPA tea@okhdfcbank on 08-06-26. '
        'Avl Bal Rs.2,004.55.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Small-ticket UPI debit; counterparty VPA is not a URL despite the dot in the handle.',
    tags: ['trustedHeader', 'vpaNotUrl'],
  ),
  SmsFixture(
    id: 'tx-09',
    sender: 'AD-IDFB-T',
    body: 'IDFC FIRST: Rs.3,499 debited on card XX8890 at FLIPKART on 05-06-26. '
        'Avl limit 46,501.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Card spend with merchant; "Avl limit" variant of the balance feature.',
    tags: ['trustedHeader', 'card'],
  ),
  SmsFixture(
    id: 'tx-10',
    sender: 'JM-YESBK-T',
    body: 'Yes Bank: Rs.99.00 debited from a/c XX6612 for E-MANDATE (SPOTIFY) on '
        '04-06-26. Bal 8,002.10.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Recurring e-mandate debit; template match beats the "E-MANDATE" lifecycle noun.',
    tags: ['trustedHeader', 'recurring'],
  ),
  SmsFixture(
    id: 'tx-11',
    sender: 'AD-FDRL-T',
    body: 'Federal Bank: A/c XX3320 debited Rs.1,000.00 on 06-06-26, UPI Ref '
        '612345678901. Bal Rs. 19,300.00.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Verb-first template with UPI reference; the 12-digit ref must not be read as an amount.',
    tags: ['trustedHeader', 'refNotAmount'],
  ),
  SmsFixture(
    id: 'tx-12',
    sender: 'VM-HDFCBK-T',
    body: 'Rs 21.00 debited from a/c XX1234 to VPA metro@okicici on 12-06-26. '
        'Bal 12,324.67. Get 5% cashback on your next Metro recharge with HDFC Bank '
        'Debit Card. T&C apply. To stop receiving, SMS STOP to 5676767.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Cross-sell tail inside a genuine debit: amount must stay 21.00, not 5% or 5676767. '
        'Offer flag set, class and suspicion unchanged.',
    tags: ['trustedHeader', 'containsOffer', 'amountTrap'],
  ),
  SmsFixture(
    id: 'tx-13',
    sender: 'VK-SBICRD-T',
    body: 'SBI Card: Rs.2,999.00 spent on your SBI Card XX3311 at CROMA on 02-06-26. '
        'Avl credit limit Rs. 41,010.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Card issuer header distinct from the bank header; still a trusted allowlist entry.',
    tags: ['trustedHeader', 'card'],
  ),
  SmsFixture(
    id: 'tx-14',
    sender: 'AD-AMZNIN-T',
    body: 'Amazon Pay: Rs.199 debited from your Amazon Pay balance for order '
        '#402-1234567 on 12-06-26. Balance Rs.310.50.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Wallet debit; order id contains digits but no currency marker, so it is not an amount.',
    tags: ['trustedHeader', 'wallet'],
  ),
  SmsFixture(
    id: 'tx-15',
    sender: 'VM-PAYTMB-T',
    body: 'Paytm: Rs.250 paid to BigBasket via UPI from your Paytm Payments Bank a/c '
        'XX4412. Ref 512345678901. Bal 1,120.00.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: '"paid" is a debit verb; balance and ref corroborate the template.',
    tags: ['trustedHeader', 'wallet', 'upi'],
  ),
  SmsFixture(
    id: 'tx-16',
    sender: 'AD-HDFCBK-T',
    body: 'Rs.75,000.00 credited to a/c XX1234 on 01-06-26 by NEFT (HDFC LTD). '
        'Avl bal Rs.87,324.67.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Large credit, trusted header, template match; "HDFC LTD" in the counterparty is not a second brand claim.',
    tags: ['trustedHeader', 'credit'],
  ),
  SmsFixture(
    id: 'tx-17',
    sender: 'VK-SBIINB-T',
    body: 'Rs.500.00 credited to your a/c XX9082 on 10-06-26 as reversal of failed UPI '
        'txn 555123456789. Bal 15,720.10.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Reversal is a credit transaction; "failed" must not make it informational.',
    tags: ['trustedHeader', 'reversal'],
  ),
  SmsFixture(
    id: 'tx-18',
    sender: 'VM-HDFCBK-T',
    body: 'Rs.1,000.00 debited from a/c XX1234 on 12-06-26 to VPA rent@okhdfcbank. '
        'Click here to view: https://hdfcbank.com/txn/abc123. Bal 11,324.67.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.clear,
    reason: 'Genuine debit with an allowlisted "view" link. Link presence alone must NOT demote '
        'the class or trigger a warning (hard rule H3).',
    tags: ['trustedHeader', 'hasLink', 'h3'],
  ),

  // ─────────────────────── genuine informational ───────────────────────
  SmsFixture(
    id: 'info-01',
    sender: 'VM-HDFCBK-S',
    body: 'Your a/c XX1234 balance as on 12-06-26 is Rs.12,345.67. For statement, '
        'log in to HDFC Bank MobileBanking.',
    expected: SmsClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Balance-on-request notice: no money verb, no link, trusted header.',
    tags: ['trustedHeader', 'balanceOnly'],
  ),
  SmsFixture(
    id: 'info-02',
    sender: 'VK-SBIINB-S',
    body: 'Your account statement for May 2026 has been sent to your registered email. '
        'Visit onlinesbi.sbi to view.',
    expected: SmsClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Statement notice; the only domain-looking token is an allowlisted SBI domain.',
    tags: ['trustedHeader', 'statement'],
  ),
  SmsFixture(
    id: 'info-03',
    sender: 'AD-ICICIB-S',
    body: 'Cheque no. 442311 for Rs.15,000.00 has been cleared from a/c XX6677 on '
        '12-06-26.',
    expected: SmsClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Cheque-cleared notice contains an amount but no debit/credit verb applied to the account, '
        'so it is informational (I2 beats T3).',
    tags: ['trustedHeader', 'cheque'],
  ),
  SmsFixture(
    id: 'info-04',
    sender: 'VM-KKBK-S',
    body: 'Your fixed deposit KKBKFD90812 matures on 20-06-26. To renew, log in to '
        'Kotak Mobile Banking.',
    expected: SmsClass.informational,
    suspicion: Suspicion.clear,
    reason: 'FD maturity reminder; "renew" is not a money verb.',
    tags: ['trustedHeader', 'maturity'],
  ),
  SmsFixture(
    id: 'info-05',
    sender: 'VK-SBIINB-S',
    body: 'Dear Customer, as per RBI guidelines please complete your KYC by visiting '
        'your home branch with Aadhaar and PAN. No update is done over phone or link. -SBI',
    expected: SmsClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Genuine KYC reminder: KYC lure fires F5, but there is NO link, NO callback and NO '
        'deadline, and it explicitly disclaims phone/link updates. N3 offsets.',
    tags: ['trustedHeader', 'kycGenuine', 'boundary'],
  ),
  SmsFixture(
    id: 'info-06',
    sender: 'AD-HDFCBK-S',
    body: 'Your new Debit Card XX9012 has been dispatched and will be delivered in 5 '
        'working days. Track in the HDFC Bank app.',
    expected: SmsClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Card dispatch; "Track in the app" is an app reference, not a URL.',
    tags: ['trustedHeader', 'dispatch'],
  ),
  SmsFixture(
    id: 'info-07',
    sender: 'VM-AXISBK-S',
    body: 'Your e-mandate for Rs.499.00 to NETFLIX has been created successfully. It will '
        'be debited on 05th of every month.',
    expected: SmsClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Mandate creation mentions a future debit but no money moved yet; T has no debit-verb '
        'match in the past tense template, I2 wins.',
    tags: ['trustedHeader', 'emandate'],
  ),
  SmsFixture(
    id: 'info-08',
    sender: 'VK-PUNB-S',
    body: 'Your passbook has been updated. For details visit pnbindia.in or your branch.',
    expected: SmsClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Passbook update with an allowlisted domain.',
    tags: ['trustedHeader', 'passbook'],
  ),
  SmsFixture(
    id: 'info-09',
    sender: 'AD-UIDAI-G',
    body: 'Your Aadhaar OTP for update request is 480112. Do not share this OTP with '
        'anyone. -UIDAI',
    expected: SmsClass.otp,
    suspicion: Suspicion.clear,
    reason: 'Government OTP: -G suffix, no link, anti-sharing line. Classified otp, not informational.',
    tags: ['govt', 'otp'],
  ),
  SmsFixture(
    id: 'info-10',
    sender: 'VM-HDFCBK-S',
    body: 'Minimum balance alert: Your a/c XX1234 balance is below Rs.10,000. Maintain '
        'balance to avoid charges.',
    expected: SmsClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Advisory, no money verb, no link. "charges" is a noun here, not a charge event.',
    tags: ['trustedHeader', 'advisory'],
  ),
  SmsFixture(
    id: 'info-11',
    sender: 'JD-ICICIB-S',
    body: 'Your request for address update has been registered. Ref SR9081234. We will '
        'update you in 3 working days.',
    expected: SmsClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Service request acknowledgement; ref id is not an amount.',
    tags: ['trustedHeader', 'serviceRequest'],
  ),
  SmsFixture(
    id: 'info-12',
    sender: 'AD-BARB-S',
    body: 'Dear customer, our branch will remain closed on 17-06-26 on account of local '
        'holiday. Digital banking is available.',
    expected: SmsClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Branch holiday notice; "Dear customer" alone must not raise fraud weight.',
    tags: ['trustedHeader', 'branch'],
  ),
  SmsFixture(
    id: 'info-13',
    sender: 'VM-HDFCBK-S',
    body: 'Your credit card statement for May 2026 is ready. Total due Rs.12,344.00, '
        'minimum due Rs.620.00, due date 28-06-26. Pay via HDFC Bank app.',
    expected: SmsClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Statement summary with two amounts and no money movement; must not be ledgered as a spend.',
    tags: ['trustedHeader', 'statement', 'multiAmount'],
  ),
  SmsFixture(
    id: 'info-14',
    sender: 'VK-IDFB-S',
    body: 'We noticed a login to your net banking from a new device on 12-06-26 at 21:14. '
        'If this was not you, call 180010888.',
    expected: SmsClass.informational,
    suspicion: Suspicion.clear,
    reason: 'Security notice with a genuine toll-free number; N8 applies. A 10-digit number here '
        'would flip it to check (see fraud-13).',
    tags: ['trustedHeader', 'securityNotice', 'tollFree'],
  ),

  // ─────────────────────────────── OTP ───────────────────────────────
  SmsFixture(
    id: 'otp-01',
    sender: 'VM-HDFCBK-S',
    body: '123456 is your OTP for login to HDFC Bank NetBanking. Valid for 10 mins. '
        'Do NOT share this OTP with anyone. -HDFC Bank',
    expected: SmsClass.otp,
    suspicion: Suspicion.clear,
    reason: 'Canonical legitimate OTP: code + purpose + validity + anti-sharing + no link.',
    tags: ['trustedHeader', 'otpCanonical'],
  ),
  SmsFixture(
    id: 'otp-02',
    sender: 'VK-SBIINB-T',
    body: '482913 is the OTP for your UPI txn of Rs.2,499.00 to BIGBASKET. Do not share '
        'it with anyone. -SBI',
    expected: SmsClass.otp,
    suspicion: Suspicion.clear,
    reason: 'THE critical trap: two numbers, 482913 is the OTP and 2,499.00 is a referenced txn. '
        'extractOtp must return 482913 and extractAmount must return null.',
    tags: ['trustedHeader', 'otp', 'amountTrap'],
  ),
  SmsFixture(
    id: 'otp-03',
    sender: 'AD-ICICIB-S',
    body: 'Your OTP is 771204 for card ending 4412. Never share your OTP, PIN or CVV '
        'with anyone. -ICICI Bank',
    expected: SmsClass.otp,
    suspicion: Suspicion.clear,
    reason: 'OTP with card suffix; the 4-digit "4412" is a card tail, not a code — the OTP keyword '
        'anchor picks 771204.',
    tags: ['trustedHeader', 'otp'],
  ),
  SmsFixture(
    id: 'otp-04',
    sender: 'VM-AXISBK-S',
    body: '9931 is your Axis Bank verification code. Valid 5 min. Do not disclose to '
        'anyone.',
    expected: SmsClass.otp,
    suspicion: Suspicion.clear,
    reason: '4-digit code with "verification code" synonym; no link.',
    tags: ['trustedHeader', 'otp', 'shortCode'],
  ),
  SmsFixture(
    id: 'otp-05',
    sender: 'JD-KKBK-S',
    body: 'OTP 562311 for registration on Kotak app. Do not share.',
    expected: SmsClass.otp,
    suspicion: Suspicion.clear,
    reason: 'Minimal OTP: keyword precedes the code, no amount, no link.',
    tags: ['trustedHeader', 'otp'],
  ),
  SmsFixture(
    id: 'otp-06',
    sender: 'VK-PAYTMB-T',
    body: '338291 is your Paytm OTP for txn of Rs.1,250.00 at MYNTRA. Never share OTP, '
        'even with Paytm staff.',
    expected: SmsClass.otp,
    suspicion: Suspicion.clear,
    reason: 'Wallet OTP with an amount reference; the "even with staff" line is a strong '
        'legitimacy marker (N5).',
    tags: ['trustedHeader', 'otp', 'amountTrap'],
  ),
  SmsFixture(
    id: 'otp-07',
    sender: 'AD-AMZNIN-S',
    body: '812344 is your Amazon Pay OTP. Do not share it with anyone, including Amazon.',
    expected: SmsClass.otp,
    suspicion: Suspicion.clear,
    reason: 'Non-bank wallet OTP; still trusted-brand, no link.',
    tags: ['trustedHeader', 'otp'],
  ),
  SmsFixture(
    id: 'otp-08',
    sender: 'VM-HDFCBK-T',
    body: '605512 is your OTP for adding a beneficiary. If not you, call 18001201243. '
        'Do not share.',
    expected: SmsClass.otp,
    suspicion: Suspicion.clear,
    reason: 'OTP + toll-free fraud line + anti-sharing. If the number were 10-digit this would '
        'become check, not warn.',
    tags: ['trustedHeader', 'otp', 'tollFree'],
  ),

  // ────────────────────────────── promo ──────────────────────────────
  SmsFixture(
    id: 'promo-01',
    sender: 'AD-HDFCBK-P',
    body: 'Get a Lifetime Free HDFC Bank Credit Card with vouchers worth Rs.5,000. '
        'Apply now: https://hdfcbank.com/cc?utm=promo T&C apply. To stop receiving SMS '
        'STOP to 5676767.',
    expected: SmsClass.promo,
    suspicion: Suspicion.clear,
    reason: 'Bank-branded promo on the bank real domain: promo class, clear state. A promo is not '
        'fraud just because it carries a link.',
    tags: ['trustedHeader', 'promo', 'allowlistedLink'],
  ),
  SmsFixture(
    id: 'promo-02',
    sender: 'VM-ICICIB-P',
    body: 'Pre-approved personal loan of up to Rs.15,00,000 at 10.25%. Limited period '
        'offer. Apply: https://icicibank.com/pl T&C.',
    expected: SmsClass.promo,
    suspicion: Suspicion.clear,
    reason: 'Pre-approved + limited period + apply; large rupee figure is marketing copy, '
        'not a ledger amount.',
    tags: ['trustedHeader', 'promo', 'loan'],
  ),
  SmsFixture(
    id: 'promo-03',
    sender: 'VK-AXISBK-P',
    body: 'Axis Bank: 0% interest EMI on your Axis Credit Card for 3 months. Offer ends '
        '30-06-26. Apply now T&C.',
    expected: SmsClass.promo,
    suspicion: Suspicion.clear,
    reason: '"0% interest" and "Offer ends" are promo-only constructions; no money verb.',
    tags: ['trustedHeader', 'promo', 'emi'],
  ),
  SmsFixture(
    id: 'promo-04',
    sender: 'AD-BAJAJ-P',
    body: 'Avail instant business loan up to Rs.50 lakh. No collateral. Apply online in 5 '
        'minutes. https://bajajfinserv.in T&C. Unsubscribe: reply STOP.',
    expected: SmsClass.promo,
    suspicion: Suspicion.clear,
    reason: 'NBFC promo with full opt-out furniture; "Rs.50 lakh" is a ceiling, not a transaction.',
    tags: ['promo', 'loan', 'nbfc'],
  ),
  SmsFixture(
    id: 'promo-05',
    sender: 'VM-LIC-P',
    body: 'LIC: Secure your family with Jeevan Anand. Limited period. Premium starting '
        'Rs.1,200/month. T&C. To opt out reply STOP.',
    expected: SmsClass.promo,
    suspicion: Suspicion.clear,
    reason: 'Insurance promo; "premium starting Rs." is a price, not a debit.',
    tags: ['promo', 'insurance'],
  ),
  SmsFixture(
    id: 'promo-06',
    sender: 'JD-DLF-P',
    body: '2/3 BHK luxury apartments at Gurugram starting Rs.1.2 Cr. Pre-launch offer. '
        'Site visit: 98100-12345. Unsubscribe STOP.',
    expected: SmsClass.promo,
    suspicion: Suspicion.clear,
    reason: 'Real-estate spam with a sales callback number. A mobile callback is NOT itself fraud '
        'without a bank claim or threat.',
    tags: ['promo', 'realEstate', 'callbackNumber'],
  ),
  SmsFixture(
    id: 'promo-07',
    sender: 'VK-SHOPPY-P',
    body: 'FLAT 70% OFF everything! Offer ends tonight. Shop now: bit.ly/shp70 T&C. '
        'To stop, reply STOP.',
    expected: SmsClass.promo,
    suspicion: Suspicion.clear,
    reason: 'Retail spam with a shortener: P6 fires, but with no bank claim and no credential ask '
        'it stays promo/clear, not fraud.',
    tags: ['promo', 'shortener', 'noBankClaim'],
  ),
  SmsFixture(
    id: 'promo-08',
    sender: 'AD-TIGERB-P',
    body: 'Win big! Play Teen Patti and Rummy on TigerBet. Get Rs.500 bonus on first '
        'deposit. bit.ly/tgbonus. 18+. Opt out STOP.',
    expected: SmsClass.promo,
    suspicion: Suspicion.check,
    reason: 'Gambling spam: promo class with a check state because the call to action is a deposit '
        'on an unvetted domain. Not phishing — no impersonation of the user bank.',
    tags: ['promo', 'gambling', 'shortener'],
  ),
  SmsFixture(
    id: 'promo-09',
    sender: 'VM-WEALTH-P',
    body: 'SEBI registered research: Get 3 multibagger calls daily with 90% accuracy. '
        'Join now: https://wealth-alpha.top/join. Reply STOP to opt out.',
    expected: SmsClass.promo,
    suspicion: Suspicion.check,
    reason: 'Assured-return + accuracy claims are illegal under SEBI rules; on a cheap TLD this is '
        'scammy-offer, so promo + check (not fraud: no bank/government impersonation).',
    tags: ['promo', 'investmentScam', 'untrustedDomain'],
  ),
  SmsFixture(
    id: 'promo-10',
    sender: 'AD-HDFCBK-P',
    body: 'Congratulations! You are pre-selected for a pre-approved home loan of Rs.40 '
        'lakh at 8.4%. Valid till 30-06-26. Apply now at hdfcbank.com/home-loan T&C.',
    expected: SmsClass.promo,
    suspicion: Suspicion.clear,
    reason: '"Congratulations" + "pre-approved" would raise eyebrows, but the header and domain are '
        'the bank own: benign marketing.',
    tags: ['trustedHeader', 'promo'],
  ),
  SmsFixture(
    id: 'promo-11',
    sender: 'VK-MUTUAL-P',
    body: 'Start a SIP of just Rs.500/month. Top-rated funds, zero commission. Download '
        'the app: https://groww.in/sip. T&C apply. Reply STOP to opt out.',
    expected: SmsClass.promo,
    suspicion: Suspicion.clear,
    reason: 'Fintech acquisition promo; "Rs.500/month" is a minimum, not a debit.',
    tags: ['promo', 'investments'],
  ),
  SmsFixture(
    id: 'promo-12',
    sender: 'AD-JOBALERT',
    body: 'Hiring alert! Work from home, earn Rs.25,000/month. No experience needed. '
        'WhatsApp 91-8822113344 to apply. Reply STOP to opt out.',
    expected: SmsClass.promo,
    suspicion: Suspicion.check,
    reason: 'Job lure with a WhatsApp handoff. No upfront fee in this message, so promo + check; '
        'if a registration fee appears it becomes fraud (see fraud-14).',
    tags: ['promo', 'jobLure', 'whatsapp'],
  ),
  SmsFixture(
    id: 'promo-13',
    sender: 'VM-TATAMOT-P',
    body: 'Book your Nexon EV today and save Rs.75,000 on exchange. Offer valid till '
        '30-06-26. T&C.',
    expected: SmsClass.promo,
    suspicion: Suspicion.clear,
    reason: 'Auto promo; "save Rs.75,000" is a discount, not a credit.',
    tags: ['promo', 'auto'],
  ),
  SmsFixture(
    id: 'promo-14',
    sender: 'AD-CRED-P',
    body: 'Your CRED coins expire soon. Redeem for vouchers worth up to Rs.2,000. '
        'Open the CRED app to redeem. T&C.',
    expected: SmsClass.promo,
    suspicion: Suspicion.clear,
    reason: 'Retention promo for an existing service; app deep reference, no URL.',
    tags: ['promo', 'rewards'],
  ),

  // ────────────────────────────── fraud ──────────────────────────────
  SmsFixture(
    id: 'fraud-01',
    sender: '+91 90987 65432',
    body: 'Dear Customer, Your SBI account will be blocked within 24 hrs due to '
        'incomplete KYC. Click here to update: http://sbi-kyc-verify.top/upd -SBI',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Ten-digit sender claiming SBI + KYC lure + 24-hour deadline + cheap-TLD domain: '
        'the highest-volume Indian family.',
    tags: ['numericSender', 'kycLure', 'deadline', 'untrustedDomain'],
  ),
  SmsFixture(
    id: 'fraud-02',
    sender: 'AD-HDFCBNK-T',
    body: 'Rs.12,499.00 debited from a/c XX8842. If not you, verify now at '
        'https://hdfc-secure-verify.xyz/login',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Lookalike header HDFCBNK (vs the registered HDFCBK) + non-HDFC domain. A near-perfect '
        'debit template does not save it: N2 is outweighted by the header forgery (H2).',
    tags: ['lookalikeHeader', 'debitTemplate', 'untrustedDomain'],
  ),
  SmsFixture(
    id: 'fraud-03',
    sender: 'VM-ICIClB-T',
    body: 'Your ICICI Bank account is suspended. Re-verify KYC instantly: '
        'https://icici-kyc.in-update.site/x',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Lowercase "l" stands in for "I" in the header (ICIClB). Must be caught by the '
        'mixed-case header rule plus edit distance to ICICIB.',
    tags: ['homoglyphHeader', 'kycLure', 'untrustedDomain'],
  ),
  SmsFixture(
    id: 'fraud-04',
    sender: 'VK-SBI-KYC',
    body: 'Your KYC update is pending. Share your Aadhaar OTP with our officer on '
        '9812345670 to avoid deactivation today.',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Malformed header (extra token) + explicit OTP request + mobile callback + deadline. '
        'F1 alone is nearly decisive.',
    tags: ['malformedHeader', 'credentialAsk', 'callbackNumber'],
  ),
  SmsFixture(
    id: 'fraud-05',
    sender: 'AD-HDFCBK-T',
    body: 'Dear user, you have received a refund of Rs.4,999. Share the OTP sent to your '
        'phone to receive it. -HDFC',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Refund hook + OTP request. Even with a well-formed header, the credential ask '
        'overrides trust (H1) — a bank never asks for the OTP it just sent.',
    tags: ['credentialAsk', 'refundLure', 'h1'],
  ),
  SmsFixture(
    id: 'fraud-06',
    sender: 'VM-PAYTMB',
    body: 'Your wallet is blocked. Scan this QR to receive your refund of Rs.1,500. '
        'Tap to verify: bit.ly/ptm-refund',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'QR-to-receive is impossible by construction (RBI), plus a shortener and a blocked-wallet '
        'threat.',
    tags: ['qrReceive', 'shortener', 'threat'],
  ),
  SmsFixture(
    id: 'fraud-07',
    sender: 'AD-MSEB-S',
    body: 'ALERT: Your electricity connection will be disconnected tonight as previous '
        'bill is unpaid. Call 9876543211 and update KYC immediately.',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Utility pretext + mobile callback + KYC request + same-day deadline: a documented '
        'DoT-flagged family.',
    tags: ['utilityLure', 'callbackNumber', 'kycLure'],
  ),
  SmsFixture(
    id: 'fraud-08',
    sender: 'AD-IRCTCI',
    body: 'Your IRCTC account will be suspended today. Update KYC immediately to avoid '
        'losing your booking history: http://irctc-update.site/kyc',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Travel/railway impersonation with a .site domain; header is a 6-char lookalike of a '
        'known brand token but unregistered.',
    tags: ['brandImpersonation', 'kycLure', 'untrustedDomain'],
  ),
  SmsFixture(
    id: 'fraud-09',
    sender: 'AD-INDPST',
    body: 'Your parcel is held at customs. Pay Rs.25 clearance fee: '
        'https://indiapost-tracking.top/pay',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Parcel + tiny fee + cheap TLD. The small amount is deliberate: it lowers the victim '
        'defences and captures card data.',
    tags: ['parcelLure', 'untrustedDomain'],
  ),
  SmsFixture(
    id: 'fraud-10',
    sender: '+91 8822113344',
    body: 'Part-time job: earn Rs.3,000/day liking YouTube videos. Pay Rs.500 registration '
        'and get tasks on Telegram. WhatsApp us now.',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Task scam: upfront fee to "work" is the definition of the fraud. Escalates from promo '
        'because money is requested before any service.',
    tags: ['jobScam', 'upfrontFee', 'numericSender'],
  ),
  SmsFixture(
    id: 'fraud-11',
    sender: 'AD-AXISBK-T',
    body: 'Your card XX4412 is blocked. To unblock, confirm your CVV and OTP here: '
        'http://axis-card-unblock.xyz',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Card-blocked pretext + CVV/OTP request + .xyz. CVV is never requested by any bank, '
        'in any channel.',
    tags: ['credentialAsk', 'cardBlocked', 'untrustedDomain'],
  ),
  SmsFixture(
    id: 'fraud-12',
    sender: 'AD-HDFCBK-T',
    body: 'Net banking locked. Verify at http://103.24.56.78/hdfc/login.php -HDFC Bank',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Raw IP literal in a bank message. No Indian bank links to an IP address.',
    tags: ['ipLiteral', 'untrustedDomain'],
  ),
  SmsFixture(
    id: 'fraud-13',
    sender: 'AD-PNB-S',
    body: 'Dear customer your account is debited twice. Install AnyDesk and share the code '
        'with our support to reverse Rs.2,400.',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Remote-access request: near-decisive on its own (F8). The "reverse a debit" hook is a '
        'variant of the fake-customer-care playbook.',
    tags: ['remoteAccess', 'reversalLure'],
  ),
  SmsFixture(
    id: 'fraud-14',
    sender: '+91 7012345678',
    body: 'You won Rs.25,00,000 in the KBC Lucknow lottery. Pay Rs.6,500 processing fee via '
        'UPI to claim. Call 9812345670.',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Prize + advance fee ("you must pay to receive") is the canonical lottery fraud.',
    tags: ['lottery', 'upfrontFee', 'numericSender'],
  ),
  SmsFixture(
    id: 'fraud-15',
    sender: 'AD-HDFCBK-S',
    body: 'Your account will be debited for Rs.4,999 for annual maintenance. If not you, '
        'call 9898989898 immediately to cancel.',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Money claim + 10-digit "bank" call centre. HDFC publishes 1800 lines; a mobile number '
        'plus a cancel-now deadline is the callback fraud pattern (F11).',
    tags: ['callbackNumber', 'fakeDebitClaim'],
  ),
  SmsFixture(
    id: 'fraud-16',
    sender: 'AD-9876543210',
    body: 'Rs.15,000.00 credited to your a/c XX9082 on 12-06-26 by UPI. Bal 15,220.10.',
    expected: SmsClass.transaction,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Seller scam: a flawless credit template from a 10-digit number. Class stays '
        '"transaction" (it asserts one) but trust is warn and the ledger MUST NOT count it (H6).',
    tags: ['numericSender', 'fakeCredit', 'h6', 'sellerScam'],
  ),
  SmsFixture(
    id: 'fraud-17',
    sender: 'VK-ICICIB-T',
    body: 'Dear Customer, your PAN is not linked with Aadhaar. Account will be frozen. '
        'Update now: https://pan-aadhaar-link.in',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'PAN-Aadhaar lure with a threat and a non-government .in domain. A .in TLD is not a '
        'trust signal; only the registrable domain is.',
    tags: ['panAadhaarLure', 'threat', 'untrustedDomain'],
  ),
  SmsFixture(
    id: 'fraud-18',
    sender: 'AD-UIDAI-G',
    body: 'Your Aadhaar will be deactivated. Update at http://uidai-verify.online/x',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Government impersonation: the -G suffix does not launder a non-uidai.gov.in link.',
    tags: ['govtImpersonation', 'untrustedDomain'],
  ),
  SmsFixture(
    id: 'fraud-19',
    sender: 'VM-HDFCBK-S',
    body: 'Dear Customer, we have updated our terms. Review and accept at '
        'http://hdfcbank.com.kyc-review.top/terms',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Subdomain bait: the string contains hdfcbank.com but the registrable domain is '
        'kyc-review.top. Only eTLD+1 comparison catches this.',
    tags: ['subdomainTrick', 'untrustedDomain'],
  ),
  SmsFixture(
    id: 'fraud-20',
    sender: 'AD-HDFC-S',
    body: 'To complete your video KYC, message us on WhatsApp: '
        'https://wa.me/919812345678. Keep your Aadhaar handy.',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'KYC funnel to a personal WhatsApp number. Banks never run video KYC from an '
        'unverified personal account.',
    tags: ['waLink', 'kycLure', 'brandImpersonation'],
  ),
  SmsFixture(
    id: 'fraud-21',
    sender: 'JD-SBIINB-T',
    body: 'Your account is locked for security reasons. Unlock with your net banking '
        'user id and password at https://sbi-unlock.online/secure',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Credential harvest of net-banking user id and password; no bank ever requests a '
        'password in a link.',
    tags: ['credentialAsk', 'untrustedDomain'],
  ),
  SmsFixture(
    id: 'fraud-22',
    sender: 'АD-HDFCBK-T', // leading char is Cyrillic А (U+0410)
    body: 'Your KYC is expiring. Verify within 24 hrs at https://hdfc-kyc.top/v',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Cyrillic А in the prefix renders identically. Confusable folding before allowlist '
        'comparison must catch it; otherwise the header looks ordinary.',
    tags: ['homoglyphPrefix', 'kycLure', 'untrustedDomain'],
  ),
  SmsFixture(
    id: 'fraud-23',
    sender: 'VM-PHONPE',
    body: 'Cashback of Rs.750 is pending. Accept it before it expires: '
        'https://phonepe-cashback.xyz/claim',
    expected: SmsClass.fraud,
    suspicion: Suspicion.warn,
    countsTowardLedger: false,
    reason: 'Wallet-brand impersonation with an expiring-cashback hook on a .xyz domain.',
    tags: ['brandImpersonation', 'untrustedDomain', 'deadline'],
  ),
];
```

### Corpus coverage check

| Group | Count | Covers |
|---|---|---|
| `tx-*` | 18 | 9 banks + 3 wallets + card/ATM/IMPS/NEFT/UPI/e-mandate/EMI/charges, cross-sell tail, genuine link, amount traps (`5%`, `5676767`, 12-digit ref) |
| `info-*` | 14 | balance, statement, cheque, FD, genuine KYC, dispatch, mandate, passbook, min-balance, service request, branch holiday, multi-amount statement, security notice |
| `otp-*` | 8 | canonical OTP, OTP-with-amount (twice), 4-digit code, minimal OTP, wallet OTP, non-bank OTP, OTP + toll-free |
| `promo-*` | 14 | bank card/loan/EMI/home-loan, NBFC, insurance, real estate, retail + shortener, gambling, stock-tip, job lure, mutual fund, auto, rewards |
| `fraud-*` | 23 | numeric sender ×3, lookalike header, homoglyph header, homoglyph prefix, malformed header, `.xyz`/`.top`/`.site`/`.online`/`.in` domains, IP literal, subdomain trick, QR-receive, refund-OTP, card-blocked, utility, parcel, job task, lottery, callback fraud, remote access, govt impersonation, `wa.me`, credential harvest, seller-scam fake credit |

---

## Sources

**Regulatory / primary**

1. TRAI, *Telecom Commercial Communications Customer Preference (Second Amendment) Regulations, 2025* — [trai.gov.in (PDF)](https://www.trai.gov.in/sites/default/files/2025-02/Regulation_12022025.pdf)
2. TRAI, *Directions on pre-tagging of variable content in commercial message templates* (18 Nov 2025) — [trai.gov.in (PDF)](https://www.trai.gov.in/sites/default/files/2025-11/Directions_18112025_0.PDF)
3. TRAI, *Press Release No. 91 of 2026* — clarification on 140 / 1600 series — [medianama.com (PDF link)](https://www.medianama.com/2026/07/223-trai-releases-clarification-designated-promotional-transactional-number-series/)
4. PIB / DoT, *TRAI issues Directions to Access Providers to stop misuse of Headers and Message Templates* — [pib.gov.in](https://www.pib.gov.in/PressReleasePage.aspx?PRID=1899849)
5. Reserve Bank of India, customer-safety guidance ("RBI never asks for money"; never share OTP/PIN/CVV; receiving money needs no QR or OTP) — summarised at [axio.co.in](https://www.axio.co.in/blogs/keep-your-finances-safe-the-rbi-way)
6. National cybercrime reporting: [cybercrime.gov.in](https://cybercrime.gov.in) · helpline **1930** · [Sanchar Saathi](https://sancharsaathi.gov.in)

**TRAI suffixes & header anatomy**

7. MediaNama, *Will Telcos Adding Suffixes to Commercial SMS Headers Help Curb Spam?* (May 2025) — [medianama.com](https://www.medianama.com/2025/05/223-suffixes-commercial-sms-headers-spam/)
8. Tanla, *TRAI Mandates New Message Suffixes* (T/P/S/G; suffix appended by the telco after DLT scrubbing) — [tanla.com](https://www.tanla.com/blog-posts/trai-mandates-new-message-suffixes-heres-what-you-need-to-know)
9. SMSGatewayHub, *What is AD, LM, QP, VM, JX in Sender ID* (operator + circle prefix table) — [crm.smsgatewayhub.com](https://crm.smsgatewayhub.com/knowledge-base/article/what-is-ad-lm-qp-vm-jx-in-sender-id-in-india-know-your-sms-prefix-codes-explained-for-smarter-messaging)
10. MediaNama, *TRAI Mandates Six Standardized Tags for Commercial SMS* (`#url#`, `#cbn#`, `#number#`; URL/callback whitelisting) — [medianama.com](https://www.medianama.com/2025/11/223-trai-pre-tagged-sms-templates/)
11. ABP Live, *Blocked 140, 1600 Numbers? You Could Miss OTPs And Bank Alerts* (series purposes; TRAI no-filter rule; abuse claims) — [news.abplive.com](https://news.abplive.com/technology/blocked-140-1600-numbers-you-could-miss-otps-and-bank-alerts-government-warns-trai-truecallers-1855765/amp)

**Indian phishing / fraud patterns**

12. RingSafe, *Indian Phishing in 2026: SMS, Vishing, and UPI Scams* — [ringsafe.in](https://ringsafe.in/indian-context-phishing-sms-vishing-upi/)
13. ScanTotal, *KYC Update Scam SMS in India: The Exact Wording and Three Tells* (real header examples `VK-SBIINB`, `VM-HDFCBK`, `JD-ICICIB`; the "three tells") — [scantotal.net](https://scantotal.net/blog/kyc-update-scam-india/)
14. ScanTotal, *UPI Payment Scams in India* (collect requests, QR-to-receive, fake support, electricity/IRCTC) — [scantotal.net](https://scantotal.net/blog/upi-scams-india/)
15. Economic Times (NPCI awareness series), *Don't fall for fake SMS messages* — [economictimes.indiatimes.com](https://economictimes.indiatimes.com/wealth/save/dont-fall-for-fake-sms-messages-npci-explains-how-scammers-target-your-money-shares-tips-to-protect-your-bank-account-and-upi/slideshow/132832583.cms)
16. Economic Times, *"Rs 15,000 credited to a/c XXXXX9082": This "bank message" could be a scam* (seller / fake-credit scam) — [economictimes.indiatimes.com](https://economictimes.indiatimes.com/wealth/save/rs-15000-credited-to-a/c-xxxxx9082-beware-of-this-latest-scam-how-to-identify-and-save-your-money/articleshow/110027014.cms)
17. MediaNama, *Jabong, Myntra, Yebhi Using Transaction SMS Pipe For Promotion* (cross-sell abuse of the transactional pipe) — [medianama.com](https://www.medianama.com/2013/07/223-jabong-myntra-yebhi-using-transaction-sms-pipe-for-promotion-ussd-spam-via-airtel/)

**Homoglyph / lookalike technique**

18. Seqrite, *Homoglyph Attacks: How Lookalike Characters Are Exploited for Cyber Deception* — [seqrite.com](https://www.seqrite.com/blog/homoglyph-attacks-lookalike-characters-cyber-deception/)

---

*Illustrative domains (`hdfc-bank-verify.xyz`, `sbi-kyc.top`, `icici-kyc.in-update.site`, `pan-aadhaar-link.in`, `wealth-alpha.top`, etc.) and phone numbers in this document and in the fixture corpus are fictional. They were not registered, resolved, fetched or contacted at any point during this research. No live phishing infrastructure was visited.*

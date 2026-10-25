# Round 1 — India financial expert (M1–M6)

Reviewer stance: ex-fintech product owner, RBI-aware, Indian consumer-credit. I grade what the
app *claims*, not what the parser was trying to do. Every number below is reproducible.

## What I actually ran

| Source | Command | What it proves |
|---|---|---|
| Current parser on the owner's real inbox | `dart run tool/replay_inbox.dart %TEMP%\inbox.json` | 2 000 msgs → `transaction=266, unknown=819, informational=566, phishing=151, promo=198`; 266 parsed, 10 merged, **256 counted**; spend **₹3,37,093**, Other **2.9 % of spend** |
| Persisted ledger | `python tool/measure_inbox.py %TEMP%\finance_sms_after.db` | 254 rows; **0** offer-wording rows, **0** rows without a money verb, **0** same-bucket double counts — the two P1/P2 guards hold |
| Same DB, engine-level | direct SQLite | `card_bills` = **0 rows**; `cards` = **21 rows**; income ₹2,70,460 = **41 rows**, almost none of it income; spend ₹7,05,183 with **71.7 % in Other** |
| Engine probes | scratch Dart files in `%TEMP%`, run with `--packages=<repo>/.dart_tool/package_config.json` (no repo files touched) | direction/kind per real template, `MonthlySummary`, `CardMetrics`, `DedupeEngine`, `SmsClassifier` signal traces |

**Which numbers are trustworthy.** The DB and the current code disagree by 2.09× on spend
(₹7,05,183 vs ₹3,37,093) for the *same* 2 000 messages, and the DB's Other share is 71.7 %
against 2.9 % now. The DB was therefore written by an older parser. I grade the current code
(the replay + probes) and use the DB only for facts that are structural: `card_bills` is empty,
21 card rows exist, and specific rows are booked as income. Side finding, and it is a blocker:
**stored rows are never re-derived when rules improve** (`ingest` only processes
`sms_messages.processed = 0`; `_reconcileDuplicates` re-runs *dedupe*, not extraction), so an
existing install keeps a ledger that is 2× off until "Clear all data".

---

## Scores

| # | Criterion | Wt | Score | Weighted |
|---|---|---|---|---|
| M1 | Correct financial semantics (P2P/P2M, transfers, refunds, EMI, bill payments, cash) | 20 | **6.0** | 120 |
| M2 | Credit-card intelligence (utilisation basis, statement vs due, minimum due, projection) | 20 | **5.0** | 100 |
| M3 | SMS reality (templates, DLT, amount traps, duplicates, OTP) | 20 | **6.0** | 120 |
| M4 | Insight quality (useful, honest, no false precision, harmless) | 15 | **5.5** | 82.5 |
| M5 | Compliance & claims (no score, no lending, RBI/CIBIL framing, DPDP) | 15 | **8.0** | 120 |
| M6 | India-specific usefulness (categories, ₹ formatting, cycles) | 10 | **7.5** | 75 |
| | **Weighted total** | **100** | | **617.5 → 6.2 / 10** |

No automatic fail fired. In particular: a card-bill payment is **not** counted as spend (it is a
`transfer`), 30 % is called a "guideline" and never "RBI", no score is displayed anywhere, and no
product is recommended. The two headline numbers that *do* fail are the ones the rubric does not
name: **money-in** and **credit-card outstanding**.

---

## M1 — Correct financial semantics: 6.0

Working, and genuinely well modelled:

- **Card bill ≠ spend.** `Payment of Rs 25,000 towards your HDFC Credit Card has been received.` →
  `transfer / creditCardBill`, excluded from the month's spend and shown as
  "Excludes ₹X in card bills and transfers" on the hero.
- **Same-sender opposite legs collapse.** Probe: a bank debit and a credit of the same amount
  inside 120 s become **one** `transfer` row (`_oppositeLeg`), not spend + income.
- **P2M vs P2P partly separated.** `… to zomato@ybl` → spend / Food; `… to RAHUL SHARMA via UPI` →
  spend; `-Transferred to Mr. AMAR…` → transfer; `trf to PhonePe Refno` → transfer. The
  `@numeric` VPA and the named-payee heuristics are the right shape.
- Real-inbox evidence: the 30 SBI `debit by transfer` rows and the ₹72,570 PhonePe card payment
  that the old ledger counted as spend are now transfers. That is why spend fell 2×.

Wrong, with concrete cases (all verified against the current extractor):

1. **A card-bill payment booked as income.** The single worst direction error in the app.
   - `HDFC Bank Cardmember, Payment of Rs 13037.24 was credited to your card ending 6859 on 17/AUG/2026.`
     → **`income`**, category *Income*, lands in `summary.income`.
   - The same event from the same bank in a different template is correct:
     `DEAR HDFCBANK CARDMEMBER, PAYMENT OF Rs. 13037.24 RECEIVED TOWARDS YOUR CREDIT CARD ENDING 6859`
     → `transfer / creditCardBill`. Two templates, opposite semantics, four such rows in the
     real ledger (₹13,037 + ₹8,592 + ₹7,683 + ₹5,861 ≈ **₹35,173** of phantom income).
   - Cause: `_creditCardBill` needs `credit card|card bill|card payment` within 40 chars of
     `payment|paid|received`; "credited to your card" misses all three. Fix the regex, not the
     fixture.
2. **Refunds are income.** `Refund of Rs 1,499 credited to your HDFC Bank Card ending 6859` →
   `income`; six Swiggy refunds (₹70–₹816) in the real ledger are all income. `MonthlySummary.net`
   is `income − spend`, so a ₹20,000 return raises "Left" by ₹20,000 while the original purchase
   still sits in the month. `03-credit-semantics.md` §5.5 requires `NetSpend = Σ SPEND − Σ REFUND`
   and §5.1 puts refunds *outside* regular income. `TxnKind` has no refund member, so this cannot
   be expressed at all.
3. **TD closure principal is income.** `Your A/C XXXXX454642 Credited. INR 30,036.00 … on account of
   Closure of TD` → `income` (also ₹10,000). Six other TD legs in the same ledger *are*
   `transfer / selfTransfer` because a debit leg happened to arrive inside 180 s. So the same
   product is income or transfer depending on which SMS the bank sent — ₹40,036 of phantom income
   in two rows, and an undeterministic savings rate.
4. **A mutual-fund SIP is spend.** `Debit Alert! Your HDFC Bank A/c xx3619 has been debited Rs 3000
   … via Debit Mandate for NIPPONMUTUA_REL261124_140-87_177404642` → **`spend`**, category
   *Investments*, 4 rows = ₹12,000 in the real ledger. `_investment` matches `prudential|amc|nav|sip`
   but not the AMC's *name+code* form, which is how every debit-mandate SIP arrives. Doc §5.4:
   investment = transfer, part of savings. The "Investments" line in "Where it went" therefore
   mixes a transfer into a spend chart, and the ₹12,000 inflates spend.
5. **EMI is spend, and `loanRepayment` is dead code.** `EMI of Rs.12000.00 debited towards car loan
   EMI` → `spend`, merchant `car`. `TransferReason.loanRepayment` exists in `enums.dart` but
   `_transferReason` can never return it. Doc §5.4/T-IN-05 wants principal = transfer and interest
   = spend; the app books the whole EMI as consumption.
6. **Inflows that are not income, booked as income** (this is the savings-rate root cause). October,
   current parser, 8 income rows, **₹37,146 total, ₹0 of it salary** (there is no salary credit
   anywhere in the 2 000 messages):

   | ₹ | merchant | what it really is |
   |---|---|---|
   | 15,000 | — | P2P credit from Mr. AMARTYAAYUSHI (`Deposit by transfer`) |
   | 10,000 + 5,003 | Closure of TD | own money maturing |
   | 3,772 | — | card bill payment credited to the card |
   | 2,200 | Meal Wallet | Pluxee benefit-card **load** (a wallet top-up) |
   | 999.27 | BATCHID | NEFT credit to own account |
   | **100** | — | **promo**: `Rs.50 CREDITED to wallet!: Save 25% … Get Rs.100 wallet credit` |

   The promo is the one row that breaks the "no spam as spend" guarantee for *income*: the
   `moneyMoved` gate passes on "credited", and the amount scorer prefers the ₹100 offer over the
   ₹50 credit.
7. **Cash is invisible.** `TxnKind.cash` is excluded from spend by design (correct — it avoids
   double-counting) but the hero's only disclosure is "Excludes ₹X in card bills and transfers";
   ATM cash is never mentioned, and no corpus row exercises the path. A cash-heavy user's spend is
   silently understated.

**P2P labelling is also wrong in words, not just numbers:** a P2P payout is stored as
`TransferReason.selfTransfer`, whose label is **"Between your own accounts"** (`enums.dart:92`).
The Activity row for `Transferred to Mr. AMARTYAAYUSHI` therefore tells the user their rent/help
payment was a move between their own accounts.

## M2 — Credit-card intelligence: 5.0

Working:

- `headroomTo30 = max(0, 0.30·L − O)` is the right formula and the copy is honest:
  "Paying ₹6,000 would bring it under 30%."
- Aggregate utilisation is **weighted** (`ΣO / ΣL`), not averaged across cards — the doc's F-UT-2.
- Projection projects the **balance** (`effectiveOutstanding + dailyRate·daysRemaining`), not the
  utilisation rate — the comment at `card_metrics.dart:223` shows someone already got burned by the
  other version. Result is sane (27 % → 35 % at statement).
- Minimum-due copy never says "minimum due is enough": *"Minimum due ₹2,100. Paying the full amount
  avoids interest."*
- No credit balance is invented; `outstanding` clamps at 0.

Broken, and these are the blockers:

1. **Bill notices are never persisted. `card_bills` = 0 rows on a 2 000-message inbox.** In
   `sqlite_finance_repository.ingest`, `_extractor.billNotice(...)` is called **inside
   `if (assessment.isTransaction)`**; a statement SMS classifies `informational`
   (`_infoIntents` → `statement_wording`/`due_summary`, and `SmsGuards.notMovedYet` returns true on
   `total due`). Verified: `HDFC Bank Credit Card 12 Oct 2026 statement: Total Amount Due Rs
   42,000.00, Minimum Due Rs 2,100.00, Due Date 01-11-26.` → classifier `informational`,
   `extract()` null — yet `billNotice()` on the same message returns `total=₹42,000, min=₹2,100`
   correctly. So the parser can read a bill and the pipeline throws it away.
   Consequences: `CardMetrics.totalDue` is always 0, `minimumDue` always null, `dueSoon` always
   false, `_billsDue` never fires, CardTile shows "Minimum due —" forever, and the **statement-date
   vs due-date distinction the app is built around does not exist in practice**.
2. **A paid bill stays on the card.** `CardMetrics.compute` skips any row whose `cardKey` differs
   from the card. A bank-side bill payment usually prints no card mask, so `cardKey` is null and the
   payment is dropped. Controlled case (HDFC 6859, ₹2,00,000 limit, statement 12th, ₹42,000 Sep
   spend, paid in full on 28 Sep, ₹12,000 spent in October):

   | | app | truth |
   |---|---|---|
   | outstanding | **₹54,000** | ₹12,000 |
   | utilisation | **27 %** | 6 % |
   | "bill due" | ₹42,000 still shown | nil |

   Meanwhile the *other* template ("…credited to your card ending 6859") does net against the card,
   because it carries `cardKey` — as **income**. Two paths, two wrong answers.
3. **Utilisation is on the wrong basis.** The app shows live `effectiveOutstanding / limit`; the
   number a bureau sees is `TAD / limit_at_statement` (doc M-01, §2.1, quoting CIBIL's CEO on
   statement-generation reporting). In the case above the app says 27 % when the reported figure is
   21 %, and the band copy tells the user to "pay before the statement date" while the gauge they
   are watching is *unbilled* spend, not the reported balance. There is no `L_at_statement`, no
   limit history, no "based on: available limit / statement / ledger" label, and no
   "estimated reported" wording. The doc explicitly forbids shipping the bare number.
4. **No opening balance ⇒ false reassurance.** Pass only the October row and the same card reads
   **₹12,000, utilisation 6 %, band `excellent`, copy "Well under the 30% mark. Nothing to do."** —
   on a card with a ₹42,000 bill outstanding. The ledger only knows what SMS it has seen; doc §2.4
   requires "utilisation unavailable — add your statement" or a "since setup" label instead.
5. **Phantom cards.** `cardKey` is set for *any* account mask, and `_ensureCard` runs on
   `txn.last4 != null` regardless of instrument. The 256-row ledger yields **16 distinct card keys,
   11 of which have no credit-card instrument at all** (savings accounts: `HDFC Bank|3619`,
   `State Bank of India|4642`, `Card|5464`, `Card|8039`…); the on-device DB has **21 card rows** for
   three plastics and one meal card. Each appears on Cards/Home with a utilisation band, and each
   would produce a nonsense "utilisation" the moment a limit is typed in. `CBSSBI` is still missing
   from `SenderRegistry.entities` (only a comment mentions it), so SBI account rows fall back to
   `Card|<tail>` — the same account even appears twice (`Card|4642` and `State Bank of India|4642`).
6. Smaller but real: **"This cycle" nets payments** (`spentThisCycle = Σ signed`, so paying ₹25,000
   reduces "spent this cycle" instead of leaving gross spend); **statement-day off-by-one** — on
   the 12th with `statementDay = 12` the tile reads "Statement in 31 days" and the `days <= 0 →
   'today'` branch is unreachable; **statement/due day clamped to 28**, so a 30th-of-month bill
   cannot be represented (both the edit sheet and `cycleFor` clamp); **no `due ≥ statement + 14`
   check** (doc §4 requires flagging it); **overpayment shows 0, not "₹5,000 credit balance"**.

## M3 — SMS reality: 6.0

Strong, and better than most shipped apps:

- **Amount scoring is genuinely good** (`amount_finder.dart`): currency mark +2/+6 for a debit verb,
  −7 for balance/limit context, −8 for OTP wording, −6 for date/mask adjacency, +3 for a trailing
  `Dr`. It handles `Spent INR 45403 Axis Bank Card no. XX5365 16-06-26 12:34:47 IST WWW AMAZON Avl
  Limit: INR 108512.00` → ₹45,403 (not the limit, not the timestamp).
- **Duplicates: 12/12** in the corpus, including `dup-cardbill-hdfc-1234` (H07+H08) and the
  refund pair. P2/P2b on the real DB: **0** same-bucket double counts, **0** same-sender lookalikes.
- **DLT work landed:** `dltPrefixes` now carries `JM, JX, TX, BT, JA, AV, CD` and merchant/benefit
  sender sets exist — the §D2 gaps are mostly closed.
- **Corpus pass rate 107/109 = 98.2 %**, with `Negatives 25/25` (bill due, OTP, request-money,
  KYC, declines all *not* transactions). `Loan of INR 36,000 available for you` → no row. That is
  exactly the P1 hard gate the research asked for.
- The two failures are fixture problems, not parser problems: `H07` asserts `kind=spend` while its
  own note says "category cardBill, not consumption" (the app correctly returns `transfer` — fix
  the fixture or someone will "fix" the app backwards), and `F03` loses `PVT LTD`.

Blocker:

7. **Phishing precision is ~0 %, and it is the most visible wrong output in the app.**
   151 of 2 000 messages (7.5 %) are `phishing`; **61 contain OTP wording, 85 contain a URL, and of
   14 distinct sampled messages none is fraud.** Re-running the classifier over those 151 real
   bodies with the current code flags **all 151** again:

   | sender | message | reality | why it fires |
   |---|---|---|---|
   | `AD-HDFCBK-T` ×25 | `365654 is your OTP … Never share OTP @mycards.hdfc.bank.in` | bank OTP | `suspicious_link(-5)`: the `bank.in` tail of the VPA handle is matched as a link and, lacking the entity string, scores as a lookalike |
   | `JK-JIONET-S` | `… is your one time password (OTP). Please enter the OTP to proceed.` | bank OTP | `credential_ask(-8)` — `enter … OTP` counts as an ask |
   | `AD-HDFCMF-S` ×6 | `Your SIP Purchase in Folio … for Rs. 2,999.85 has been processed …` | a **real ₹2,999.85 transaction** | flagged as fraud, so it is never booked *and* the user is told their AMC is a scammer |
   | `AD-TRAYAH-P` ×6 | `Your cart is pending. Please complete your purchase.` | promo | `_kycLure` matches **"complete your"** with no KYC word |
   | `VA-GDIGIT-S` | `… Insurance Policy … is expiring … Renew now, click here` | insurer reminder | `kyc_lure` + `call_to_action` |
   | `JZ-ZESTMN-P` | `Get up to Rs 2 Lakh* credit facility …` | promo | link + "click" = phish 8 |
   | `AD-NSESMS-S` | `Beware while dealing on unsolicited tips…` | advisory | link + "Visit" |

   Mechanism: `phish >= 6` is tested **before** `info`/`promo`, and `suspicious_link(5) +
   call_to_action(3)` = 8, so *any* message with a link and the word "click/visit" is fraud. The
   research doc's rules 4–5 (issuer-domain trust; promo-with-link stays promo) are implemented in
   `_isSuspiciousUrl` but bypassed by the ordering, and `_kycLure`/`_credentialAsk` are wide enough
   to match ordinary English. On top of this, `replay` shows **819 messages (41 %) in `unknown`** with
   no way to see them, and the known P1b gap is still open (`Recharge of INR 361.00 is successful for
   your Airtel Mobile` → `unknown`, no spend).

## M4 — Insight quality: 5.5

Good instincts: every insight carries a number, tone is calm, "Probably the extra week" and
"That is a big jump — worth a look" read like a person, the duplicate-charge insight is genuinely
useful, and the hero's "Excludes ₹X in card bills and transfers" is the kind of disclosure most
apps skip.

Blockers:

8. **The savings rate is fiction.** "You are keeping 75 % of what came in" (probe) and "Came in
   ₹37,146" (real October) are computed from `(income − spend)/income` with *every* inflow counted
   as income. With ₹0 salary in the corpus, the app still presents a savings rate — doc §5.5 says
   return `null` when `RegularIncome ≤ 0` and §5.2 requires salary detection first. This is the
   single most consequential honesty failure: on the owner's phone the hero's "Came in" is mostly
   their own money moving.
9. **Partial month vs full month, unlabelled.** `monthOverMonth`, `CategoryTotal.change` and
   `_categorySpikes` compare *days-elapsed* against a *whole* previous month. On day 5 the hero pill
   can read "▼ 60 % vs last month" and a category can read "1.7× your usual" — and the parenthetical
   says **"Probably the extra week"**, which is backwards: the current month is the shorter one.
   Doc: compare same-day-of-month or pro-rate.
10. **False precision.** "₹36,500 a year at this pace" for a 3-observation ₹3,000 SIP (12 × ₹3,000 =
    ₹36,000; `annualisedPaise = amount·365/30`); "you will finish around ₹1,18,432" (exact rupees for
    a linear projection); `inrCompact(₹99,999.50)` → **"₹100k"**; `every 30 days` for a monthly SIP
    (and `nextExpected = last + 30 d` drifts ~5 days a year, so "renews soon" will fire on the wrong
    date). Projection is gated at `daysElapsed >= 3`, which still lets "on track for ₹1.5 L" fire
    after one rent payment on the 2nd.
11. **A credit-score claim.** `UtilizationBand.high.advice` = **"This can affect your score."** The
    app cannot see a score and the doc forbids implying a score outcome
    ("Lower statement utilisation may help; bureaus don't publish exact formulas"). There is also no
    "we can't see your CIBIL score" disclaimer anywhere. The band copy otherwise gets 30 % right
    ("Above the 30 % guideline — pay before the statement date"), which is the correct CIBIL
    statement-date framing and never called RBI. Nothing harmful is recommended: no lending, no
    "pay only the minimum", no product.

## M5 — Compliance & claims: 8.0

Genuinely clean: no score, no score delta, no bureau branding, no lender or affiliate, 30 % is
"guideline" (not RBI), the due-date copy is issuer-neutral, `READ_SMS`/`RECEIVE_SMS` only (no
`INTERNET` permission in the manifest, no network dependency in `pubspec.yaml`, no `print` of SMS
bodies) — so "Nothing is uploaded / no account / no analytics" is enforced by construction, not just
claimed. DPDP posture is honest ("Clear all data" really deletes; CSV export is marked "Coming
soon" rather than faked).

Deductions: the "affect your score" line (above); no RBI due-date sanity check ("due ≥ statement +
14", doc §4) even though the doc calls it mandatory; no data-export path (portability) and no
"who sees this" statement beyond "stays on this phone"; no explicit "not a lender, not a bureau".

## M6 — India-specific usefulness: 7.5

Real Indian coverage was added from the inbox: `Pluxee`, `Sodexo`, `CWT India`, `takeUforward`,
`JW Marriott`, `Country Delight`, `Blinkit/Zepto/Instamart`, `Nippon/Bandhan/KFin`, FASTag, metro
cards, `vi recharge`, `indane`. ₹ formatting is **correct**: `en_IN` grouping gives `₹1,29,900`,
`₹12,34,567.89`, `-₹5,000`, decimals only when paise ≠ 0, and `inrCompact` gives `₹1.1L` / `₹2.5k`.
That is better than most Indian fintech apps.

Gaps: `INF*Indian` (₹4,000 of fuel) → Other; `PYU*Flipkar` → Other; debit-mandate SIPs land in
spend; P2P rent to a person → Other (no "Rent paid to a person" path even though `rent` exists);
`hotel` → Food & dining catches non-hotel "HOTEL" strings; no festival/seasonal framing (Diwali,
school fees, insurance renewal season), no salary-day awareness (the whole product would improve by
anchoring "month" to payday for the many users whose salary lands on the 1st vs 7th), and no
`every month` phrasing for monthly series.

---

## Five strongest things

1. **Card-bill payments are transfers, and the hero says so** — "Excludes ₹X in card bills and
   transfers". This is the automatic-fail trap and the app clears it, both in the engine and in copy.
2. **Amount arbitration.** `Avl Limit`, `Avl Bal`, OTP codes, timestamps, dates and masks are scored
   down by explicit, commented rules; the headline spends on a real inbox come out right
   (₹1,11,510 Marriott, ₹45,403 Amazon — not the ₹1,08,512 available limit, not the timestamp).
3. **Duplicate suppression that survives reality.** Same-sender opposite legs → one transfer;
   TD closure chains resolved by union-find; Pluxee/benefit repeats collapsed. 12/12 corpus, 0
   same-bucket dupes on 2 000 real messages.
4. **The parser is measured, not asserted.** `replay_inbox` + `measure_inbox` + a 109-fixture corpus
   that prints per-bucket pass rates (98.2 %) — and the fixture comments encode *financial intent*
   ("refund to card must offset spend, not add income"), which is the right way to hold a parser
   honest.
5. **The card maths that does exist is the right maths:** weighted aggregate utilisation, balance-
   based projection (with a comment explaining why the naive version was wrong), `headroomTo30`,
   and minimum-due copy that never implies "minimum is enough".

## Every blocker to 9.5

**Wrong money (must fix before any 9.5):**

- B1. Card-bill payment booked as **income** (`…was credited to your card ending 6859`, 4 rows
  ≈ ₹35,173) while a sibling template is `transfer`.
- B2. **Refunds are income**, not negative spend (`Refund of Rs 1,499 credited to your HDFC Bank
  Card`; 6 Swiggy refunds in the ledger); savings rate and category shares both inflate.
- B3. **TD-closure principal is income** (`Closure of TD` ₹30,036 + ₹10,000), while sibling TD legs
  are self-transfers — same product, two answers.
- B4. **Debit-mandate SIP is spend** (`NIPPONMUTUA_REL…`, 4 × ₹3,000 = ₹12,000) and appears in the
  "Investments" *spend* category.
- B5. **EMI is spend** (`EMI of Rs.12000 debited towards car loan EMI`); `TransferReason.loanRepayment`
  is unreachable dead code.
- B6. **P2P to a named person is spend** (`to RAHUL SHARMA via UPI`) and, when classified as a
  transfer, is *labelled* "Between your own accounts".
- B7. **A promo became ₹100 of income** (`Get Rs.100 wallet credit`); the money-moved gate does not
  cover offers that contain "credited".
- B8. **ATM cash is excluded from spend with zero disclosure** (and untested in the corpus).
- B9. **Savings rate is presented with no salary** — doc §5.5 requires `null` + "we haven't
  identified a salary credit".

**Card intelligence (the whole M2 pillar):**

- B10. `billNotice()` is unreachable for statement SMS ⇒ `card_bills` empty ⇒ **no bill amount, no
  minimum due, no due countdown, ever**.
- B11. Bill payments without a card mask are **not applied** to the card (₹54,000 vs ₹12,000)
  ⇒ utilisation and "bill due" permanently wrong after a payment.
- B12. Utilisation shown on the **live** balance, not `TAD / limit_at_statement`; no basis label,
  no "estimated reported".
- B13. **No opening balance ⇒ "Excellent — nothing to do"** on a card with an unpaid ₹42,000 bill.
- B14. **Phantom cards**: 11 of 16 card keys are savings accounts; `CBSSBI` unresolved; one account
  exists twice under two issuer strings; "This cycle" nets payments; statement day clamped to 28 and
  off by one on the statement date itself; no `due ≥ statement + 14` validation; overpayment shows 0
  instead of a credit balance.

**SMS reality:**

- B15. **151 phishing flags / 2 000 messages, 0 true positives in a 14-message sample**, including
  37 bank OTPs and a real ₹2,999.85 SIP confirmation — `phish >= 6` (link + CTA) is evaluated before
  promo/info, and `_kycLure`/`_credentialAsk` match ordinary English (`complete your`, `enter the OTP`).
- B16. Known-good recharge receipts still dropped (`unknown`); 41 % of the inbox is `unknown` with no
  visibility.

**Trust plumbing:**

- B17. **Stored rows are never re-derived after a rule change** (`ingest` skips `processed = 1`), so
  the same inbox yields ₹7,05,183 in the DB and ₹3,37,093 from today's code. An existing user's
  numbers can only be fixed by "Clear all data".
- B18. Partial-month vs full-month comparisons with no caveat, and "Probably the extra week" arguing
  the wrong direction.
- B19. "This can affect your **score**" — the only score-adjacent claim in the app, and it is
  unsupportable; no "we cannot see your CIBIL score" disclaimer.
- B20. False precision on projections and annualisation (`₹36,500 a year`, exact-rupee month
  projections, `every 30 days`, `₹100k` for ₹99,999.50).

## Three highest-leverage fixes

1. **Give money-in a real taxonomy, and delete the fake savings rate.** Add `refund`, `cardPayment`,
   `selfTransfer`, `redemption`, `cashback`, `walletLoad` as first-class inflow kinds; make
   `NetSpend = spend − refund` (accrual, per doc §5.5); make `income` mean salary/business/interest
   only, and return `null` (with "we haven't seen a salary credit") when it is empty. Then:
   `…credited to your card` → `transfer(cardPayment)`; `Closure of TD` → `transfer(redemption)`;
   `via Debit Mandate` → `transfer(investment)`; `EMI` → split principal/interest. This one change
   fixes B1–B9 and the "Came in / Left / 73 % kept" headline in a day's work. It is also what makes
   the card balance right, because payments finally reach the card.
2. **Persist bills and put utilisation on the statement basis.** Call `billNotice()` for
   `informational` messages with a card mask (and stop `notMovedYet` from suppressing bill parsing),
   store `statement_date/total_due/min_due/due_date`, and show three numbers with a basis label:
   *reported* `100·TAD/L_stmt`, *live*, *projected*, plus "estimated" and "add your statement / since
   setup" states when the anchor is missing. This converts M2 from 5.0 to ~8.5 and is mostly wiring
   that is already written: `CardBillNotice`, `_latestBillFor`, the never-parsed
   `statementDateMs`, and the unused `totalLimit` finder.
3. **Stop calling things fraud.** Reorder the decision so a link alone can never be decisive: require
   a credential *ask* (`send/share/tell us`, not `enter`) or a payment instruction, trust the
   issuer's registrable domain (including `@*.bank.in` and `*.page.link`), drop `complete your` from
   `_kycLure`, and demote link+CTA to `caution`/`promo`. Ship a precision test on the 151 real
   bodies in this review (target: ≤ 5 flags, 0 OTPs). This removes the loudest wrong output in the
   product and lets the hidden ₹2,999.85 SIP become a transaction.

*Honourable mention (cheap, do it in the same sprint):* bump a `parser_version` in `app_meta` and
re-derive stored rows when it changes, so fixes reach existing installs (B17); and create a card
only when `instrument == creditCard` or the alert names a card, unlisting the 11 account tails (B14).

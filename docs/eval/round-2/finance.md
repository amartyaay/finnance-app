# Round 2 — India financial expert (M1–M6)

Reviewer stance: ex-fintech product owner, RBI-aware, Indian consumer credit. I grade what the
app *claims and shows*, not what the parser was trying to do. Every number below is reproducible
from the commands in the next section. I did not modify the app; scratch probes live in `%TEMP%`
and import the repo's own engines.

**Round 1: 6.2 / 10 → Round 2: 7.2 / 10 (+1.0).** The money-in taxonomy is real and the
"fabricated ₹37,146 came in" is gone; bills are finally persisted; the stale-ledger class of bug
is fixed. The score does not go higher because the same definitional defect has moved to the
screen the user trusts most: the hero's "**Out this month ₹33k**" is a hybrid of consumption and
card-bill payments that is wrong under *either* definition, Activity simultaneously prints
"**+₹3,939.66 in**" under "no income", and **six HDFC card payments are booked twice** (₹44,497.59
double counted), inflating the card-bill line and leaving the HDFC card with a phantom
₹34,895.73 credit. Card utilisation is now computed on the statement basis in the model but still
*rendered* as an unlabelled live number, with the same Axis card showing **0 % on its face and
6 % in the aggregate ring**. Two of the 2 remaining fraud flags are still false positives.

---

## What I ran

| Source | Command / artefact | What it proves |
|---|---|---|
| Current parser on the owner's 2 000-message inbox | `dart run tool/replay_inbox.dart "$env:TEMP\inbox_final.json"` | `transaction=284, unknown=866, informational=624, promo=224, phishing=2`; 282 parsed, 14 merged, **268 counted**; spend **₹3,12,407.81**, Other **0.7 %** |
| Engine-level replay (my probe, no repo files) | `dart --packages=<repo>/.dart_tool/package_config.json %TEMP%\r2_probe.dart %TEMP%\inbox_final.json` | `SummaryCalculator`, `CardMetricsCalculator`, `InsightsEngine`, `RecurringDetector`, `billNotice()`, dedupe and the money-in split |
| Real-message probes | `%TEMP%\r2_probe2.dart`, `r2_probe3.dart`, `r2_probe4.dart` | the exact 2 000 bodies for the round-1 templates, bills, ATM, SIP, UPI Lite, card masks |
| The app's own behavioural probe | `dart run tool/parser_check.dart` | **13 / 16** cases pass; 3 real-template failures (below) |
| Fixture suites | `flutter test test/sms_corpus_test.dart test/spam_corpus_test.dart` | SMS corpus **109 / 109 (100 %)**, spam corpus **77 / 77 (100 %)** |
| Device truth | `docs/shots/device-home.png`, `device-activity.png`, `device-cards.png`, `device-insights.png` (23:36, after the 23:14 DB pull) | the phone prints the same 20 313 / 33k / 11k / 6 % / 71 607.54 as the replay — the round-1 2.09× offline/device drift is gone |
| Code read | `lib/engine/*`, `lib/services/sms/*`, `lib/data/sqlite_finance_repository.dart`, `lib/data/finance_repository.dart`, `lib/views/**`, `docs/research/03-credit-semantics.md` | every formula and every string quoted below |

Which numbers are trustworthy: the replay is the source of truth for money; the phone screenshots
agree with it to the rupee this round. The round-2 end-user review
(`docs/eval/round-2/end-user.md`) independently reports the same Home ₹33k vs Activity ₹20,313 and
Cards ₹16k vs Home ₹11k contradictions from the same screenshots; my numbers come from the engine
replay and the bodies, so the two reviews corroborate rather than repeat each other. I did **not**
re-run `measure_inbox.py` against a fresh device DB, so persistence of `card_bills` is verified at
engine level plus the ingest code path (`billNotice()` runs for every message and inserts into
`card_bills`, unique-indexed), not by SQL on tonight's DB. No claim below rests on the round-1
stale DB.

Scope note: everything below is the round-2 build the brief describes (HEAD `c87e42b`, device
captures at 23:36). The working tree has since gained an in-progress Home/money-in change ("On
pace for…", a money-in breakdown, a shared money formatter); it is not part of this review and does
not change the parser, `SummaryCalculator`, `CardMetrics` or the duplicate/`moneyOut` findings.

---

## Scores

| # | Criterion | Wt | R1 | R2 | Weighted (R2) |
|---|---|---|---|---|---|
| M1 | Correct financial semantics (P2P/P2M, transfers, refunds, EMI, bill payments, cash) | 20 | 6.0 | **7.5** | 150 |
| M2 | Credit-card intelligence (utilisation basis, statement vs due, minimum due, projection) | 20 | 5.0 | **6.5** | 130 |
| M3 | SMS reality (templates, DLT, amount traps, duplicates, OTP) | 20 | 6.0 | **6.5** | 130 |
| M4 | Insight quality (useful, honest, no false precision, harmless) | 15 | 5.5 | **6.5** | 97.5 |
| M5 | Compliance & claims (no score, no lending, RBI/CIBIL framing, DPDP) | 15 | 8.0 | **8.5** | 127.5 |
| M6 | India-specific usefulness (categories, ₹ formatting, cycles) | 10 | 7.5 | **8.0** | 80 |
| | **Weighted total** | **100** | **617.5 → 6.2** | | **715 → 7.15 (reported 7.2)** |

No automatic fail fires: no card-bill payment in spend, 30 % is still a "guideline" and never
"RBI", no score is presented, no product is recommended. The integrity failure this round is not
on the rubric's fail list: **the hero's "out" and Activity's "out" are different numbers for the
same month**, and both are shown to the user at the same time.

### Delta in the numbers that matter

| Metric | R1 | R2 | Read |
|---|---:|---:|---|
| Counted rows | 256 | **268** | +12 rows, but 6 of them are duplicate HDFC payments |
| Spend (all time) | ₹3,37,093 | **₹3,12,407.81** | −7.3 %: SIPs + EMIs left spend |
| Other share of spend | 2.9 % | **0.7 %** | Fuel / Flipkart fixed |
| True income (October) | ₹37,146, ₹0 salary | **₹0** | fabricated inflow gone |
| Savings rate | 75 % | **null** | honest |
| `card_bills` | 0 | **6** | 5 with min due, 6 with statement + due |
| Card keys | 21 | **4** | one is a meal wallet, see M2 |
| Fraud flags / 2 000 | 151 | **2** | 0 OTP false positives, but 2/2 false |
| Duplicate card payments | 0 claimed | **6 HDFC pairs, ₹44,497.59** | P2 breached: one payment, two templates, 1–2 days apart |
| `unknown` | 819 (41 %) | **866 (43.3 %)** | 47 of the old phishing moved here |
| SMS corpus | 107 / 109 (98.2 %) | **109 / 109** | H07 fixture corrected |
| `parser_check` | — | **13 / 16** | the suite's own probe is red |

---

## Claim-by-claim: what the round-2 brief says, and what the evidence says

| Claim | Verdict | Evidence |
|---|---|---|
| `MoneyInKind` taxonomy persisted | **TRUE** | `enums.dart` has salary/interest/other/refund/cashback/cardPayment/selfTransfer/redemption/walletLoad/p2pReceive/none; `transactions.money_in_kind` is a NOT NULL column; `MonthlySummary` admits only `isTrueIncome` into income. |
| Card-bill credits, TD closures, wallet loads no longer income | **TRUE** | 16 `cardPayment` rows ₹1,37,761.60 (but six HDFC payments are counted twice — see the P2 row); 9 `redemption` ₹1,85,130; 6 `walletLoad` ₹8,880; 7 `refund` ₹2,446; true-income rows: **0**. `…credited to your card ending 6859` → `transfer / cardPayment`; `Closure of TD` → `transfer / redemption`. |
| SIPs / EMIs are transfers with reasons | **PARTLY** | 10 of 18 SIP confirmations booked as `transfer / investment` (₹29,998.50); **8 are `unknown` and never reach the ledger**. EMI `₹12,000` → `transfer / loanRepayment`; the whole EMI is a transfer, so the interest component is not spend (doc §5.4/§5.7). |
| True income on the 2 000 messages is ₹0 and the savings rate is null | **TRUE** | `incomePaise = 0`, `savingsRateOrNull = null`, hero "No income messages found this month". Nothing in the inbox is salary; the two "salary" strings are a promo. |
| Bill notices captured from informational SMS, 0 → 6, with total/min/statement/due | **TRUE** | 6 `CardBillNotice`s: Axis ×5 (₹11,660.26 / ₹72,570.85 / ₹11,170.43 / ₹21,931.82 / ₹5,135.94) + Amex ₹10,568. All six carry a statement date and due date; five carry a printed minimum due (Amex prints none). `_billsDue` now fires ("Bill due in 2 days, ₹10,568"). |
| Card identity gated, 21 → 4 cards | **TRUE numerically** | Card keys: `HDFC Bank|6859` (89 rows), `Card|6719` (27), `Axis Bank|5365` (21, limit ₹11,36,025.06), `American Express|1008` (3). But `Card|6719` is the **Pluxee meal wallet** (instrument wallet) with a fallback issuer "Card"; `_ensureCard` still mints on any `cardKey`, not on `instrument == creditCard`. Six HDFC payments (₹44,497.59) also lose `cardKey` to a mask-regex ordering bug. |
| Utilisation now reported/live/projected with basis labels and bill-aware advice | **MODEL ONLY, NOT RENDERED** | `UtilizationBasis`, `reportedLabel`, `liveLabel`, `projectedLabel`, `projectedBasisLabel`, `limitIsEstimated`, `dueDateLooksWrong`, `creditBalancePaise` and `CardMetrics.advice` exist; **none is read by any view** (grep: 0 matches in `lib/views`; the only bill-aware copy that reaches the screen is the Home bill banner and the `_billsDue` insight). The Cards ring uses `totalUtilization` = live outstanding; the face uses reported when a bill exists. The same Axis card reads **0 % on its face and 6 % in the ring** (see M2). |
| Fraud 151 → 2 flags with 0 OTP false positives | **TRUE, but precision is still 0 %** | 2 flags; both are genuine Airtel Payments Bank KYC notices ("As per RBI guidelines, your A/c will blocked today as KYC is due", `i.airtel.in`). No OTP is flagged. 2/2 false positives is not precision. |
| Home hero reads "Out this month / Bill due / no income messages found" instead of a fabricated "Came in ₹0" | **TRUE copy, WRONG number** | The copy is there and better. "Out this month ₹33k" = ₹20,313 spend + ₹12,679.94 card bills + ₹0 cash. True consumption is ₹20,313; the card bills that left the bank are ₹8,907.94 (the app double counts ₹3,772). ₹32,992.94 is neither (see M1/B1). |
| P2 "0 duplicate groups" (`CLAUDE.md`) | **BREACHED** | The six HDFC card payments each arrive as two SMS: `Payment of Rs 13037.24 was credited to your card ending 6859 on 17/AUG/2026.` (18 Aug, cardKey `HDFC Bank|6859`, instrument bankAccount) **and** `DEAR HDFCBANK CARDMEMBER, PAYMENT OF Rs. 13037.24 RECEIVED TOWARDS YOUR CREDIT CARD ENDING WITH 6859 ON 17-8-2026.` (17 Aug, no cardKey, instrument creditCard). Same amount, same issuer, same event, 1–2 days apart. Both rows are `creditCardBill` transfers; the 180 s dedupe window cannot see the pair. All six pairs are double booked: ₹44,497.59 counted twice. |

---

## Round-1 blockers, one by one

Legend: **FIXED** = the failing message/number from round 1 is now correct; **PARTIAL** = the
semantics moved but a visible or formula-level error remains; **OPEN** = unchanged.

| R1 | Blocker | Status | Evidence |
|---|---|---|---|
| B1 | Card-bill payment booked as income | **FIXED** | Both templates → `transfer / cardPayment`; 16 rows ₹1,37,761.60 excluded from income. |
| B2 | Refunds are income | **PARTIAL** | 7 refunds ₹2,446 are excluded from income, but not netted from spend or the original category. `netSpend` is computed and **never rendered**; August's ₹522 + ₹816 + ₹200 (+ a duplicate ₹200) refunds leave those purchases at full price in Food & dining. |
| B3 | TD-closure principal is income | **FIXED** | 9 rows ₹1,85,130 = `transfer / redemption`. Dedupe still rewrites three of them to `transferReason.selfTransfer` (June ₹23,023, Aug ₹22,022/₹15,019) while `moneyInKind` stays `redemption`; both labels are non-income, but the row's reason and kind disagree internally. |
| B4 | Debit-mandate SIP is spend | **FIXED for booked rows** | ₹1,56,247 of investments are transfers; the Nippon/Bandhan/KFin shape is caught. But 8 SIP confirmations from AMFI senders (ITI, Bajaj Finserv, Nippon) remain `unknown` — ~₹24,000 of real SIPs invisible. |
| B5 | EMI is spend; `loanRepayment` dead | **FIXED** | `EMI of Rs.12000 debited towards car loan EMI` → `transfer / loanRepayment` (₹12,685 all time). Interest is not split out as spend. |
| B6 | P2P to a named person is spend / labelled "between your own accounts" | **PARTIAL** | `Transferred to Mr. AMARTYAAYUSHI` → `personTransfer` (₹1,77,000). `Sent Rs.2,000 to rahul.sharma@okhdfcbank` → **spend / Other**; a name-looking VPA is still indistinguishable from a merchant. The UI now describes inflows by `moneyInKind`, so the visible "Between your own accounts" wording is fixed even where dedupe sets `selfTransfer`. |
| B7 | A promo became ₹100 of income | **FIXED** | `Rs.50 CREDITED to wallet… Get Rs.100 wallet credit` → no row; true income 0. |
| B8 | ATM cash excluded with no disclosure | **FIXED** | Hero footnote now says "₹X cash" inside "Out this month"; `TxnKind.cash` works (`Rs.2000 withdrawn from ATM…` → cash ₹2,000). The real inbox has **no ATM withdrawal** (all 9 ATM-word messages are promos), so the path is corpus-tested but not real-data-tested. |
| B9 | Savings rate presented with no salary | **FIXED** | `null` + hero sentence. |
| B10 | `billNotice()` unreachable ⇒ no bills, ever | **FIXED** | 6 bills; bill-aware advice, due countdown, minimum due, "paying the full amount avoids interest". |
| B11 | Bill payment without a card mask not applied | **PARTIAL** | `attributeUnkeyedPayments` now nets an unkeyed card-bill payment when the issuer has one card. The six HDFC "PAYMENT … TOWARDS YOUR CREDIT CARD ENDING WITH 6859" rows (₹44,497.59) have **no `cardKey`** because the mask regex matches `credit card` before `card ending with`; they only net via the issuer fallback. It still misses a card payment that parses as a plain transfer: `trf to PhonePe Refno` ₹72,570.85 → `transferReason = none`, `cardKey = null` (issuer SBI), so the Axis card never nets its July bill. The face still says "Total due" after the bill is paid. |
| B12 | Utilisation on the live balance, no basis label | **PARTIAL / NOT SHIPPED** | The model computes reported / live / projected. The screens show one unlabelled number; the aggregate ring is live and the per-card face is reported; no basis label, no "estimated reported". The doc's §2.1 prohibition on shipping the bare number still applies. |
| B13 | No opening balance ⇒ "Excellent — nothing to do" | **PARTIAL** | A bill anchor exists, but `outstandingPaise` is **not** S2 (`TAD + debits − credits`). Axis: app outstanding ₹71,607.54 vs statement ₹5,135.94; the ₹72,570.85 July payment is an SBI/PhonePe debit (`transferReason = none`) that never nets the card, so the real position is ~₹0 (a ₹963.31 credit). With no bill and no limit the app now says "Limit not set", which is honest; with a typed limit it would estimate from zero with **no "since setup" label**. |
| B14 | Phantom cards / cycle bugs / due-date validation / overpayment | **PARTIAL** | 21 → 4 keys, but one is a meal wallet; only **1 of 4** cards has a limit; statement day is still clamped to **1–28** in the edit sheet (`_day`) while the engine supports 29–31; a limit cannot be cleared (`copyWith` null = keep); `dueDateLooksWrong` is computed but never shown; a credit balance is computed but never shown; "spent this cycle" is now gross (fixed); statement-day "today" and the 31st clamp are fixed. |
| B15 | 151 phishing flags, 0 true positives | **MOSTLY FIXED in volume, NOT in precision** | 151 → **2**, 0 OTPs. Both remaining are false (Airtel Payments Bank KYC). The mechanism is still `kycLure` matching any "KYC" + `threatWording` matching bare "blocked"; the issuer domain (`i.airtel.in`) is not in `_brandDomains`, and a known bank sender does not downgrade the flag. |
| B16 | Recharge/wallet receipts dropped; 41 % unknown with no visibility | **HALF FIXED** | The All-messages screen makes `unknown` visible. But `unknown` is **866 (43.3 %)** and still contains real money: `Recharge of INR 361.00 is successful…` → no row; **3 UPI Lite top-ups** (₹2,000 + ₹2,000 + ₹3,534 = ₹7,534) → no row; 8 SIP confirmations → no row. |
| B17 | Stored rows never re-derived after a rule change | **FIXED** | `parserVersion = 8`; `_ensureFreshDerivations()` reparses on load when parser/schema version differs; `reparseAll()` preserves user categories and learned rules. Phone and replay now agree. |
| B18 | Partial-month vs full-month comparisons, "probably the extra week" | **OPEN** | Hero "3 % vs last month" (₹20,313 over 25 days vs ₹19,726.85 over 31) and Insights "On track … ₹25,188.12 against ₹19,726.85" (+27.7 %) are on the same Home/Insights pair. `_categorySpikes` still compares MTD to a whole previous month and still contains "Probably the extra week" (wrong direction when the current month is the partial one). |
| B19 | "This can affect your score" | **FIXED** | No "score" copy in `lib/`; band copy is "guideline"; no CIBIL branding. |
| B20 | False precision on projections/annualisation/`₹100k` | **PARTIAL** | `inrCompact(₹99,999.50)` → **"₹100k"** (verified); "finish around ₹25,188.12" is exact rupees for a linear projection; `RecurringRow` still prints "Every 30 days" and "₹X a year at this pace" (`365 / intervalDays`, `next = last + 30 d`). The SIP series is now not detected at all, so the annualisation is invisible — the code is still wrong. |

---

## M1 — Correct financial semantics: 7.5 (from 6.0)

**What is now genuinely right** (and was the round-1 ask):

- **Money-in is a taxonomy, not a direction.** True income = salary + interest + other only.
  On this inbox: **₹0 / 0 rows**. The old "₹37,146 came in" is gone; the savings rate is `null`,
  not a fabricated 75 %.
- **Card-bill credits are transfers.** Four templates, 16 rows, ₹1,37,761.60, excluded from
  income; the two HDFC wordings now agree.
- **TD closure, wallet load, cashback, P2P receipt, self-transfer, refund** are all first-class
  inflow kinds and all excluded from income.
- **SIPs and EMIs** are transfers with reasons.
- **Promo credits** no longer post a row.
- **P2P out** to a named beneficiary is `personTransfer`; the label "Between your own accounts"
  is no longer shown for it.

**What is still wrong in the money maths:**

1. **`moneyOut` is a hybrid that double counts card bills.** `moneyOut = spend + cash +
   cardBillPayment`. The research doc is explicit: a card bill is a `TRANSFER` and is excluded
   from spend/savings *because the purchases were already counted* (§5.4, §5.5, §5.7). In
   October the app shows **"Out this month ₹32,992.94"**: ₹20,313 of card/UPI consumption plus
   ₹12,679.94 of card-bill payments (of which ₹3,772 is the same payment counted twice — see M3).
   Consumption (the doc's NetSpend) was ₹20,313; the card bills that actually left the bank were
   ₹8,907.94. The headline is neither. This is the single most visible wrong number in the app.
2. **Three different "left" definitions.** `left = income − moneyOut` (hero) /
   `net = income − spend` (insights body) / `savingsRate = (income − netSpend) / income`
   (insights title). With a salary, hero "Left", "You are keeping X %" and "₹Y left after ₹Z of
   spending" would disagree by the card-bill and refund amounts. The doc defines exactly one
   (Savings = RegularIncome − NetSpend); the app has three.
3. **Refunds are excluded from income but not netted.** `netSpend` exists and is correct but is
   dead code. The "Where it went" donut and every category total are gross; a ₹816 Swiggy refund
   leaves ₹816 in Food & dining. The acc/cash split in §5.5 (accrual for savings/categories,
   cash for FreeCash) is not implemented.
4. **EMI interest is not spend.** The whole ₹12,685 is `DebtPrincipal`; doc §5.4/§5.7 wants
   principal = transfer, interest = spend. The app cannot represent the split, so spend and
   savings are understated by the interest (unknown from SMS).
5. **A single-message two-leg transfer becomes spend.** `Rs.5000 debited from A/c XX1234 and
   Rs.5000 credited to A/c XX5678 on 12Jun26` → **spend ₹5,000** (`parser_check` FAIL). The
   dedupe engine only collapses two *messages*; one SMS carrying both legs is booked as
   consumption. This is a clean, reproducible M1 error.
6. **11 real movements are dropped** (details in M3): 8 SIP confirmations (~₹24,000), 3 UPI Lite
   loads (₹7,534). The taxonomy cannot help rows that never reach it.
7. **One real movement is counted twice.** Six HDFC payments arrive as a card-side and a bank-side
   SMS, 1–2 days apart; both are now `creditCardBill` transfers, and the 180 s dedupe window does
   not merge them. **₹44,497.59 is counted twice** all-time; October's card-bill line is ₹12,679.94
   instead of ₹8,907.94. Fixing B1 (both templates → transfer) created this P2 regression.

**Formula audit against `docs/research/03-credit-semantics.md` §5.5:**

| Doc formula | App field | Verdict |
|---|---|---|
| `RegularIncome = Σ INCOME(salary, business, interest, dividend, rent)` | `incomePaise` | Mostly; `other` is a catch-all, no rent-received detection. |
| `NetSpend = Σ SPEND − Σ REFUND` | `netSpend` | Computed correctly, **never shown**. Hero/UIs use gross `spend`. |
| `Savings = RegularIncome − NetSpend` | none; `left = income − (spend + cash + card bills)` | **Wrong definition** (card bills double count). |
| `SavingsRate = Savings / RegularIncome if > 0` | `savingsRateOrNull = (income − netSpend) / income` | Formula right; unused while income = 0. |
| `Investments = Σ TRANSFER(investment)` | ₹1,56,247 | Computed; no "includes ₹X invested" line; `moneyInByKind` dead. |
| `DebtPrincipal = Σ TRANSFER(loan principal)` | ₹12,685 | Whole EMI, interest not separated. |
| `CashWithdrawn = Σ CASH(atm)` | ₹0 in this inbox | Path works (`cash` on the ATM probe). |
| `FreeCash = RegularIncome − NetSpend − Investments − DebtPrincipal − CashWithdrawn` | absent | `left` is not FreeCash and no "drawdown" state. |

---

## M2 — Credit-card intelligence: 6.5 (from 5.0)

**Real progress.** Bills are persisted and used: six statements, due dates, minimum due; the Home
banner and the `_billsDue` insight now say "American Express bill due in 2 days · ₹10,568 total
due · Paying in full avoids interest", and the minimum is never presented as enough. The
statement-day-off-by-one bug is dead (`cycleFor` returns the closing cycle on the statement day);
`_dayInMonth` handles a 31st; "spent this cycle" is gross; `due ≥ statement + 14` is computed;
`headroomTo30` uses the reported balance when a bill exists; a credit-balance field exists. The
per-card `CardMetrics.advice` string that was meant to carry the bill-aware copy is **not rendered
anywhere** (grep: 0 `.advice` reads), so the card tile itself is still the bare number.

**But the card pillar the doc is built around is still not shippable:**

1. **The basis is not on screen.** `UtilizationBasis`, `reportedLabel`, `liveLabel`,
   `projectedLabel`, `projectedBasisLabel` are never read by a view. The Cards ring says
   **6 % used / Excellent** with **"₹71,607.54 used · ₹10,64,417.52 available"**; the same card's
   latest Axis statement says **₹5,135.94**. The ring is live-ledger; the per-card face (when a
   bill exists) is reported; the two are different bases on the same screen, unlabelled.
2. **The same card reads 0 % and 6 %.** Axis reported utilisation = 5,135.94 / 11,36,025.06 =
   **0.452 %**; the face does `(0.00452 * 100).round()` → **"0 %"**, while the ring's live
   aggregate is **6 %**. The engine's own `_pct` would at least print "<1 %"; the widget bypasses
   it. The model's `advice` string ("Bill paid. Live utilisation 6 %.") would add a third figure
   if it were rendered — it is not.
3. **Cards "Total due" counts paid bills.** Cards summary sums `totalDuePaise` (₹15,703.94 →
   **₹16k**) while Home sums `billDuePaise` (**₹11k**). The Axis ₹5,135.94 is already paid
   (`billDuePaise = 0`), but its face still says **"Total due ₹5,135.94 · Due in 8 days"**. Three
   "due" numbers across two tabs, and the one on the card art is the paid one.
4. **Outstanding is not the doc's S2.** `outstandingPaise` is the sum of signed ledger rows
   (plus a `limit − available` fallback), not `TAD + post-statement debits − credits`. Axis:
   **₹71,607.54** vs statement **₹5,135.94**. The ₹72,570.85 July settlement is in the ledger only
   as an **SBI/PhonePe debit** (`trs to PhonePe Refno …`, `transferReason = none`, `cardKey =
   null`, issuer State Bank of India), so the unkeyed-payment attribution — which requires
   `creditCardBill` — never applies it to the Axis card. Attribute it and the card is at roughly
   zero (a **₹963.31 credit**), not ₹71,607.54; S2 from the October statement gives ₹1,940 (the
   25 Oct Flipkart spend), also nowhere near ₹71,607.54. HDFC reads a **₹34,895.73 credit
   balance** because its six payments are booked twice (₹44,497.59 ×2): payments ₹88,995.18 plus
   refunds ₹2,181 against card spend ₹56,280.45. With one row per payment the same card would read
   ₹9,601.86 owed. Neither number is displayed today; both are wrong and both would be displayed
   by the basis work the claim says shipped.
5. **The limit is estimated but presented as a fact.** Axis's ₹11,36,025.06 was derived from
   `Avl Limit + amount`; `limitIsEstimated` exists but is **never set or read**, and the UI
   prints "of ₹11,36,025.06" as if the user typed it. Worse, `_ensureCard` freezes the **first**
   alert's implied limit (16 Jun → ₹11,36,025.06) and never updates it; later Axis alerts imply
   ₹10,85,729 (5 Jul), ₹11,47,635.64 (23 Jul), ₹11,51,793.41 (5 Oct) and ₹11,43,177 (25 Oct).
   The doc's S1 caveat (temp limits, EMI blocking, pending auth) applies. The HDFC card (89
   rows, the main card) has **no limit at all**, so 3 of 4 cards cannot show any utilisation.
6. **Card identity is still not clean.** `Card|6719` (27 rows, Pluxee meal wallet, `instrument
   wallet`) is presented as a credit card with issuer "Card" because `_ensureCard` runs on any
   `cardKey`. The six HDFC "CREDIT CARD ENDING WITH 6859" payments (₹44,497.59) lose `cardKey`
   because `_cardContext` matches "credit card" before "card ending with"; they net only via the
   one-HDFC-card fallback. The round-1 recommendation "create a card only when `instrument ==
   creditCard` or the alert names a card" was not applied to the Pluxee case.
7. **Smaller but real:** statement day still 1–28 in the editor; a limit cannot be cleared;
   `dueDateLooksWrong` is never shown (the §4 mandatory check is invisible); `MAD ≤ TAD` is not
   validated; no limit history, so an enhanced limit would retroactively change old statements
   (F-UT-6); `projectedUtilization` clamps at 2.0 instead of showing over-limit; no "since setup"
   label; no "we can't see your CIBIL score" disclaimer; no credit-balance badge.

---

## M3 — SMS reality: 6.5 (from 6.0)

**Genuine wins.** 151 → **2** phishing flags with **0 OTP false positives**; the issuer-domain
trust list, the email-handle guard for `@mycards.hdfc.bank.in`, the OTP-shape gate and the
`share/send/tell` vs `enter` distinction are the right shapes. The fixture suites are green:
**109/109** SMS and **77/77** spam. Duplicates on the real inbox: 14 merged, 268 counted — **but
six HDFC payments are still double-booked** (item 6). The All-messages screen gives `unknown` a
home.

**Still wrong:**

1. **The 2 flags are 2 false positives.** Both are Airtel Payments Bank KYC notices quoting RBI
   and pointing at `i.airtel.in`; `_kycLure` matches bare "KYC" and `_threatWording` matches
   bare "blocked", and `strongPhish = kycLure && threat` ignores sender trust and issuer domain.
   Precision on the remainder is 0/2. The volume win is real; the promise "fraud flags" is not.
2. **The app's own probe is red: 13/16.** `tool/parser_check.dart` fails on:
   - `Rs.5000 debited from A/c XX1234 and Rs.5000 credited to A/c XX5678` → spend (should be a
     self-transfer) — M1;
   - `Rs.2000 added to your Paytm Wallet via UPI` → `unknown`, no row (should be walletLoad);
   - `Payment of Rs.18,452.00 received on your ICICI Bank Credit Card … Thank you for your
     payment.` → `informational`, no row (the "thank you for your payment" merchant-receipt
     guard fires before the card-bill wording).
   None of the three is in the corpus, so 100 % green coexists with a red behavioural probe.
3. **`unknown` is 866 (43.3 %)** and it is not harmless: **8 of 18 SIP confirmations** (ITI,
   Bajaj Finserv, Nippon; ~₹24,000) and **3 UPI Lite top-ups** (₹7,534) are dropped. The
   round-1 recharge example (`Recharge of INR 361.00 is successful…`) is still `unknown`.
4. **The ₹200 duplicate refund survives.** Two identical "Rs. 200 refunded by Swiggy…" alerts
   on 2026-08-19 are both stored; the 180 s dedupe window can't merge them, and the refund total
   is overstated by ₹200. Small, but it is the class of error the app exists to prevent.
5. **"12 to confirm"** is real and the review queue works, but 12 rows still need a human; the
   honest number is closer to 12 + the 11 dropped rows the app never asks about.
6. **Six HDFC card payments are booked twice — a P2 breach on the real inbox.** Each payment
   arrives twice, from the card and from the bank, 1–2 days apart, with the amount and card mask
   identical and the event date the same or one day apart:
   - `HDFC Bank Cardmember, Payment of Rs 13037.24 was credited to your card ending 6859 on
     17/AUG/2026.` (received 18 Aug, `cardKey = HDFC Bank|6859`, instrument bankAccount)
   - `DEAR HDFCBANK CARDMEMBER, PAYMENT OF Rs. 13037.24 RECEIVED TOWARDS YOUR CREDIT CARD ENDING
     WITH 6859 ON 17-8-2026.` (received 17 Aug, no `cardKey`, instrument creditCard)
   Same pattern for ₹5,861 (Jun), ₹7,683 (Jul/Aug), ₹5,552 (Sep), ₹8,592.35 (Sep), ₹3,772 (Oct):
   **₹44,497.59 counted twice**. `_sameEvent`'s `bothCardBill` branch would merge them, but the
   180 s window closes first. The consequence is not cosmetic: October's card-bill line is
   ₹12,679.94 instead of ₹8,907.94, the hero's "Out this month" is ₹3,772 too high, and the HDFC
   card reads a ₹34,895.73 credit instead of ₹9,601.86 owed. Round 1 did not catch this because
   one template was booked as *income* then; the taxonomy fix turned both into card payments and
   exposed the duplicate.

---

## M4 — Insight quality: 6.5 (from 5.5)

**Better instincts, honestly executed:** every insight carries a number and a calm sentence; the
bill insight is genuinely useful; "No income messages found…, so there is no 'left over' figure"
is the most adult line in the product; refunds are disclosed on the hero; "Paying in full avoids
interest" is correct.

**Still overclaiming or misleading:**

1. **"Out this month ₹33k"** and **"₹1.2L transfers not counted"** — the second is larger than
   the first, so the receipt raises more questions than it answers. The number is wrong (M1).
2. **Partial month vs full month.** Home "3 % vs last month" and Insights "finish around
   ₹25,188.12 against ₹19,726.85" (+27.7 %) are both visible; they answer "am I spending more?"
   differently. `_categorySpikes` ("Shopping is 4.4× your usual: ₹15,028 this month vs ₹3,383
   last month") compares 25 days to a 31-day month with no same-day or pro-rata basis, and the
   neutral branch still says "Probably the extra week" (the wrong direction).
3. **False precision.** "You will finish around ₹25,188.12" (exact rupees, linear projection);
   "Every 30 days" for a monthly series and `annualised = amount × 365 / 30`; `inrCompact(₹99,999.50)`
   → **"₹100k"**. The `daysElapsed < 5` projection gate is better than round 1's day-3 gate, but
   the numbers are still printed to the paisa.
4. **Recurring is empty, and the empty state is false.** "Nothing recurring detected yet — we
   need three similar charges" is shown while the inbox has **18 SIP confirmations** and a
   monthly car EMI; `RecurringDetector` only reads `kind == spend`, and SIPs/EMIs are transfers.
   The feature got *less* useful when the taxonomy got more correct.
5. **"4 signals from 268 entries" under "October 2026"** — 268 is all-time, 36 is the month.
   A user who notices the count assumes the money is wrong too.
6. **Inert insight tiles** are a UX defect but also an M4 one: the app says "Biggest payment …
   31.5× your typical payment" and "Shopping is 4.4× your usual" with no way to see the charges.

---

## M5 — Compliance & claims: 8.5 (from 8.0)

Clean by construction: no score, no score delta, no bureau branding, no lender/affiliate, 30 % is
a "guideline" and never RBI, no "pay only the minimum", no product recommendation. `READ_SMS` /
`RECEIVE_SMS` / `POST_NOTIFICATIONS` only; **no INTERNET permission**, no network dependency, no
SMS body logging; `clearAll` deletes the ledger, bills, cards and rules. The "affect your score"
line from round 1 is gone.

Deductions: no "we cannot see your CIBIL score" disclaimer; the model label "Reported at
statement" overclaims if wired (it is TAD / *current* limit, not the limit at statement); no
data-export path (the CSV rows are still "Coming soon"); no "who sees this" beyond "stays on this
phone"; the mandatory `due ≥ statement + 14` flag is computed but never shown; a derived limit is
not labelled "estimated".

---

## M6 — India-specific usefulness: 8.0 (from 7.5)

₹ formatting is excellent (`₹1,29,900`, `₹12,34,567.89`, `-₹5,000`, compact ₹1.3L/₹25k). The
category coverage that round 1 asked for landed: `INF*Indian` now Fuel (₹4,000), `PYU*Flipkar` now
Shopping, Pluxee/Sodexo meal cards, FASTag/metro/vi/indane, SIP AMCs; Other share is **0.7 %**.

Gaps: UPI Lite top-ups dropped (so the on-device wallet is invisible); a P2P payment to a name-VPA
(`rahul.sharma@okhdfcbank`) is still Other; no festival/seasonal framing; no salary-day/payday
anchoring; no "every month" phrasing (recurring empty); the meal card is presented as a credit
card.

---

## Every financially wrong output I can reproduce

| # | Where | The failing message / number | What is true |
|---|---|---|---|
| 1 | Home hero | **"Out this month ₹33k"** (₹32,992.94) | Consumption (NetSpend) ₹20,313; the card bills that left the bank ₹8,907.94. ₹32,992.94 adds card bills on top of purchases already counted (this month or a prior month) **and** double counts a ₹3,772 HDFC payment, so it is neither (doc §5.4/§5.5/§5.7). |
| 2 | Home vs Activity | Hero "No income messages found"; Activity **"+₹3,939.66 in"** | The ₹3,939.66 is a Groww NEFT credit ₹999.27 (`selfTransfer`), Axis cashback ₹72, and a Groww IMPS credit ₹2,868.39 (`selfTransfer`). None is income. |
| 3 | Cards ring | **"₹71,607.54 used" / "6 % used"** for Axis | Statement ₹5,135.94; the ₹72,570.85 July settlement is an SBI/PhonePe debit the card never sees, so the real position is ~₹0 (a ₹963.31 credit), not ₹71,607.54. |
| 4 | Cards face (Axis, second page) | **"0 %"** used | Reported 0.452 % → `.round()` = 0. The ring says 6 %. One card, two visible percentages (the unrendered `advice` would add a third). |
| 5 | Cards summary | **"Total due ₹16k"** (₹15,703.94) | Home says "Bill due ₹11k"; unpaid is ₹10,568. The Axis ₹5,135.94 is paid (`billDuePaise = 0`). |
| 6 | Cards face (Axis) | **"Total due ₹5,135.94 · Due in 8 days"** while Home's "Bill due" excludes it (`billDuePaise = 0`; the model's unrendered advice says "Bill paid.") | A paid bill is still drawn as due on the card art. |
| 7 | HDFC card model | **outstanding ₹0 / credit balance ₹34,895.73** | The six HDFC payments are booked twice (₹44,497.59 ×2). Payments ₹88,995.18 + refunds ₹2,181 vs card spend ₹56,280.45; one row per payment gives ₹9,601.86 owed. Not rendered today, but it is the number a "credit balance" badge would show. |
| 8 | Home vs Insights | **"3 % vs last month"** vs **"finish around ₹25,188.12 against ₹19,726.85"** (+27.7 %) | Same month, same previous month, two answers: 25 days vs 31 days. |
| 9 | Insights | **"Shopping is 4.4× your usual: ₹15,028 this month vs ₹3,383 last month"** | 25 days vs a whole month; no same-day-of-month or pro-rata basis. |
| 10 | Insights | **"you will finish around ₹25,188.12"** | Exact rupees for a linear projection of 25 days; false precision. |
| 11 | Formatting | `inrCompact(₹99,999.50)` → **"₹100k"** | Rounds up to a round lakh; should read ₹99,999 or ₹1L with a decimal. |
| 12 | Insights / recurring | **"Nothing recurring detected yet — we need three similar charges."** | 18 SIP confirmations and a monthly EMI exist; `RecurringDetector` only reads `kind == spend`. |
| 13 | Ingest | `Dear Investor, Your SIP installment in ITI Small Cap… Rs.3000 is processed` (and 7 more) | `unknown` → no row. 8 of 18 SIP confirmations (~₹24,000) invisible. |
| 14 | Ingest | `UPI LITE Top-up on SBI Rs.2000.00 is successful` ×2, `Rs.3534.00` | `unknown` → no row. ₹7,534 of real wallet loads invisible. |
| 15 | Ingest | `Rs.5000 debited from A/c XX1234 and Rs.5000 credited to A/c XX5678` | Booked as **spend ₹5,000** (`parser_check`); it is one self-transfer. |
| 16 | Ingest | `Payment of Rs.18,452.00 received on your ICICI Bank Credit Card … Thank you for your payment.` | `informational`, no row; a card-bill payment is not netted. |
| 17 | Fraud | 2 flags: `As per RBI guidelines,your A/c will blocked today as KYC is due … https://i.airtel.in/…` | Genuine Airtel Payments Bank KYC notices. 2/2 false positives; precision 0 %. |
| 18 | Refunds | 7 refunds ₹2,446; e.g. ₹816 refunded by Swiggy on 29/Aug | Not netted from the August Food & dining total; `netSpend` never shown. |
| 19 | EMI | `EMI of Rs.12000.00 debited towards car loan EMI` → transfer ₹12,000 | All principal; the interest component is real spend and is missing (doc §5.4/§5.7). |
| 20 | Card identity | `DEAR HDFCBANK CARDMEMBER, PAYMENT OF Rs. 13,037.24 … CREDIT CARD ENDING WITH 6859` (6 rows, ₹44,497.59) | No `cardKey`; only the one-HDFC-card fallback attributes it. |
| 21 | Cards | **"Card •••• 6719"** (Pluxee meal wallet, 27 rows) | Not a credit card; it has a wallet instrument and a fallback issuer "Card". |
| 22 | Cards | **"of ₹11,36,025.06"** (Axis limit) | Derived from `Avl Limit + amount`; `limitIsEstimated` is never set, so an estimate is shown as a typed fact. |
| 23 | Statement day | Entering 30 is clamped to 28 (`_day`) | A 30th-of-month statement cannot be represented; the engine could do it. |
| 24 | Limit edit | Emptying the limit keeps the old value (`copyWith` null = keep) | A mistyped limit cannot be cleared, only changed. |
| 25 | Card bill payments | Six HDFC payments booked twice: `Payment of Rs 13037.24 was credited to your card ending 6859 on 17/AUG/2026` (18 Aug) **and** `DEAR HDFCBANK CARDMEMBER, PAYMENT OF Rs. 13037.24 RECEIVED … ON 17-8-2026` (17 Aug) | One payment, two rows; ₹44,497.59 counted twice. October card bills ₹12,679.94 vs true ₹8,907.94; HDFC card reads a ₹34,895.73 credit. |

---

## Five strongest things

1. **The money-in taxonomy is real and enforced end-to-end.** 0 true income in 2 000 messages;
   card payments, TD redemptions (₹1,85,130), refunds (₹2,446), wallet loads (₹8,880) and
   cashback (₹2,527) are all excluded from "Came in", with a `null` savings rate and honest copy.
   The round-1 headline failure is gone at the root, not patched at the label.
2. **Bills are finally a first-class object.** `billNotice()` runs on informational SMS, six
   statements are stored with total/min/statement/due, and the Home banner/insight is bill-aware
   ("₹10,568 total due. Paying in full avoids interest."). The minimum is carried in the model and
   in the banner path (the only unpaid bill here, Amex, prints none; Axis's ₹3,144 is stored but
   its bill is paid). This is the piece round 1 said was the whole M2 pillar; it now exists. (The
   per-card `advice` string is written but not yet rendered — a wiring gap, not a missing model.)
3. **Phishing volume is fixed without breaking the corpus.** 151 → 2 flags, 0 OTP false
   positives, 109/109 SMS and 77/77 spam fixtures, and an issuer-domain allow-list that catches
   the lookalike case. The remaining false positives are a narrow, fixable rule, not a broken
   architecture.
4. **Stored ledgers re-derive on upgrade.** `parserVersion` + `_ensureFreshDerivations()` +
   `reparseAll()` (preserving user categories and learned rules) kills the "same inbox, 2.09×
   different spend" class of bug. The phone and the offline replay now agree to the rupee.
5. **The card cycle maths that exists is correct.** Statement-day "today", 31st clamping,
   gross "spent this cycle", `headroomTo30` on the reported balance, `due ≥ statement + 14`
   detection, and a credit-balance field — the pieces are right even where the UI has not caught
   up.

---

## Blockers to 9.5 (round 2)

**Money semantics (M1/M4):**

- **R2-B1. Two/three "out" numbers.** `moneyOut` = spend + cash + card bills (₹32,992.94) is not
  consumption (₹20,313) and not cash flow (₹8,907.94 once the duplicate ₹3,772 is removed). Use
  the doc's `NetSpend` for "out" and report card bills as an excluded line.
- **R2-B2. Activity's "in" includes non-income.** `_totals` sums `kind == income`, which includes
  refunds, cashbacks, P2P receipts and self-transfers: **+₹3,939.66 in** under "no income".
- **R2-B3. Refunds are not netted.** `netSpend` is dead; the donut and categories are gross. A
  ₹816 refund leaves ₹816 in Food.
- **R2-B4. EMI interest is not spend.** No principal/interest split; spend and savings are
  understated by the interest.
- **R2-B5. A single-SMS two-leg transfer is spend.** ₹5,000 in the app's own probe.

**Card intelligence (M2):**

- **R2-B6. Utilisation is not on the doc's basis in the UI.** No basis label; the ring is live,
  the face is reported; the same Axis card reads 0 % on its face and 6 % in the ring.
- **R2-B7. Outstanding is not S2.** Axis ₹71,607.54 vs ₹5,135.94; the real position is ~₹0
  (a ₹963.31 credit) once the SBI/PhonePe ₹72,570.85 payment is attributed; HDFC ₹34,895.73
  phantom credit. This is why the ring is 6 % on a card with a ₹5,136 bill.
- **R2-B8. "Total due" includes paid bills.** Cards ₹15,703.94 vs Home ₹10,568; a paid bill
  still reads "Total due … Due in 8 days".
- **R2-B9. Derived limits are presented as facts.** `limitIsEstimated` dead; no "estimated",
  no limit history; 3 of 4 cards have no limit at all.
- **R2-B10. Card identity still leaks.** Pluxee meal wallet as a credit card; six HDFC payments
  unkeyed; statement day 1–28; a limit cannot be cleared; `dueDateLooksWrong` invisible.

**SMS reality (M3):**

- **R2-B11. Real movements dropped.** 8 SIP confirmations (~₹24,000), 3 UPI Lite loads
  (₹7,534), the ICICI "thank you for your payment" bill credit; `unknown` is 43.3 %.
- **R2-B12. Fraud precision is 0/2.** KYC + "blocked" is still decisive regardless of sender
  trust or issuer domain.
- **R2-B17. Six HDFC card payments are double-booked.** ₹44,497.59 counted twice; October card
  bills ₹12,679.94 vs true ₹8,907.94; HDFC card reads a ₹34,895.73 credit. The 180 s window can
  never merge two templates that arrive a day apart.

**Insight quality (M4):**

- **R2-B13. Partial-month comparisons and exact-rupee projections.** "3 % vs last month" vs
  "+27.7 %", "4.4× your usual", "finish around ₹25,188.12", `₹100k`.
- **R2-B14. Recurring is empty for the user's actual commitments.** SIPs/EMIs are transfers;
  "Nothing recurring detected" is false.

**Trust plumbing / claims (M5/M6):**

- **R2-B15. No "we cannot see your CIBIL score" disclaimer**; "Reported at statement" would
  overclaim if wired; no export.
- **R2-B16. The receipt is bigger than the total.** "₹1.2L transfers not counted" under a
  ₹20,313 spend, not tappable; "268 entries" under an October heading; the per-day number is
  printed twice.

---

## Three highest-leverage fixes

1. **One money-out and one money-in definition, shared by Home, Activity and Cards.**
   First merge the six HDFC dual-template payment pairs (same amount, same card mask, both
   `creditCardBill`, within 72 h, one row missing `cardKey`) so the card-bill line is ₹8,907.94,
   not ₹12,679.94. Then make "out" = `NetSpend` (doc §5.5: spend − refunds) and show card bills,
   investments, debt principal and cash as *excluded* lines with amounts; make Activity's "in" use
   `RegularIncome` only (salary/interest/other) and label the rest "refunds / transfers /
   cashback". This one change removes the ₹33k-vs-₹20,313 contradiction, the "+₹3,939.66 in"
   contradiction, the three "Left" definitions, and makes the doc's savings rate the only rate.
   It is mostly wiring: `netSpend`, `otherInflowPaise` and `moneyInByKind` already exist and are
   dead.
2. **Put card utilisation on the statement basis and render the basis everywhere.**
   Compute `O = TAD + post-statement debits − credits` (S2), use `TAD / L_report` for the
   headline, and show *reported / live / projected* with their labels (the fields and copy
   already exist); make the face use `_pct` instead of `.round()` (0.452 % → "<1 %"); make
   Cards' "Total due" Σ `billDue` (₹10,568, not ₹15,703.94) and show "paid" when it is zero;
   label a derived limit "estimated". This fixes 0 %/6 %, ₹71,607.54 vs ₹5,135.94, ₹16k vs
   ₹11k and the paid-bill face in one pass.
3. **Admit the real movements the parser still drops, and stop the last false fraud flag.**
   Add the four missing shapes to admission: UPI Lite top-up (`Rs.X is successful` → walletLoad),
   AMFI SIP confirmations (ITI/Bajaj/Nippon), a one-SMS two-leg transfer (`debited from A/c X and
   credited to A/c Y`), and the ICICI "Thank you for your payment" card-bill credit before the
   merchant-receipt guard. Require a payment instruction for `kycLure && threat`, and treat a
   known bank/`.bank.in` KYC reminder as informational. That books ~₹31,500 of currently invisible
   money, removes 2/2 false fraud alerts, and makes the "no recurring" empty state stop lying
   (SIPs/EMIs then need to be included in `RecurringDetector`).

*Honourable mentions (same sprint, cheap):* fix `_cardContext` so "CREDIT CARD ENDING WITH 6859" is
recognised, **and merge it with the card-side row** rather than booking both (6 HDFC pairs,
₹44,497.59); mint a card only for `instrument == creditCard` (drop
`Card|6719`); allow statement days 29–31 and a cleared limit; render `dueDateLooksWrong`; add a
"we can't see your CIBIL score" line in Cards/Settings; and show the refund line in the month it
belongs to (accrual) rather than only the month it arrives.

---

## Score rationale

M1 gains 1.5 because the round-1 semantic errors are actually fixed and reproducible (income 0,
savings null, card/TD/wallet/SIP/EMI/promo), but the new "out" construct, the double-booked HDFC
payments and the dropped SIP/UPI Lite rows keep it out of the 8s. M2 gains 1.5 for bills and the
bill-aware banner/insight, but the utilisation basis the doc calls mandatory is still not on
screen and the live outstanding is 14× the statement — not a 7+. M3 gains 0.5 for the phishing
and fixture work, held back by a 43 % unknown bucket that contains real money, a 13/16 own-probe
and the ₹44,497.59 double count. M4 gains 1.0 for honesty, held back by the partial-month
contradiction, false precision and an empty recurring list. M5 +0.5 (score claim gone), M6 +0.5
(Fuel/Flipkart/SIP coverage). **7.15 weighted.**

The single change that would move the score most is not a parser rule: it is **one honest
money-out number, shared by every tab, built from `NetSpend`**. Today the app's most prominent
number (₹33k) is not the sum of anything the user can reconcile; fixing that is worth more than
the next ten parsing fixes.

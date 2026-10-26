# Round 3: accuracy audit

Auditor: accuracy subagent, 2026-10-26. Baseline: **HEAD `5263c06`** (clean tree). While the
audit ran, other agents committed `89e05af` and `543b493` and left uncommitted edits in
`lib/engine/dedupe_engine.dart` and `tool/audit_accuracy.dart`. Where those edits change a
number, the report says so in a separate column.

Privacy: this file has message ids, counts and paraphrased templates with the numbers taken out.
It has no message bodies. Every adversarial template in section 4 is invented.

Probes (gitignored): `.review_tmp/audit3/replica.dart` (a faithful copy of the ingest path),
`adversarial.dart` (95 synthetic cases), `statement_probe.dart` (16 statement scenarios),
`audit_copy.dart` (the auditor plus a list of direction errors).

---

## 1. Reproduced metrics

`dart run tool/audit_accuracy.dart .local/inbox_full.json <set> --list`

| Metric | CLAUDE.md held-out | Reproduced held-out (HEAD) | CLAUDE.md all | Reproduced all (HEAD) | All, **working tree** (uncommitted dedupe edit) |
|---|---:|---:|---:|---:|---:|
| Non-money rows counted (P1) | 0 | **0** | 0 | **0** | 0 |
| Movements counted twice (P2) | 1 | **1** (3169←3215) | 1 | **1** | **16** |
| Card bills counted on both legs | 0 | 0 | 0 | 0 | 0 |
| Spend recall | 98.7 % | 98.7 % (305/309) | 98.9 % | 98.9 % (450/455) | 98.9 % |
| Spend precision | 96.5 % | 96.5 % (305/316) | 97.2 % | 97.2 % (450/463) | 97.2 % |
| Phishing false alarms | 1 | 1 (3561) | 1 | 1 | 1 |
| Money / no-money agreement | 99.2 % | 99.2 % | 99.1 % | 99.1 % | 99.1 % |

**Every HEAD number reproduces.** Also measured: movement recall 96.1 % / 95.4 %, kind
agreement 97.0 % / 97.8 %, amount agreement 100 %, direction errors 6 / 7, spend total app
₹9,00,258 against gold ₹8,78,220 (all).

**Regression in the working tree: P2 goes from 1 to 16.** The uncommitted bill-pairing rewrite
in `dedupe_engine.dart` only merges two same-direction issuer alerts within 30 minutes. HDFC
confirms every card payment twice, about 23–48 h apart (first "payment received", then
"online payment credited to your card"). These 15 pairs now both count:
3340/3359, 3718/3739, 4051/4072, 4058/4073, 4436/4483, 4872/4883, 5162/5180, 5518/5543,
5936/5959, 6303/6343, 6909/6928, 7144/7176, 7661/7674, 7757/7767, 8071/8105.
The same edit does fix adversarial case D08 (two cards' payments merged into one). The fix needs
both: same card, same amount, same direction, up to 48 h apart, refs not different. **Do not
commit the edit as it stands.**

The one HEAD double (3169 + 3215) is a Pluxee refund credit and Zomato's refund receipt for the
same refund, **72.0 h** apart. The receipt window is `<= 3 days`, so a gap of a few minutes
over 72 h escapes it. Adversarial case D16 reproduces this.

---

## 2. Auditing the auditor (`tool/audit_accuracy.dart`)

I rebuilt the app's write path (`_processPending`: rows in `received_at ASC` order, UNIQUE
`dedupe_key` with the first row winning, dedupe over **all** stored rows, `needs_review`
cleared on rewritten rows, then `TxnGuards` and the `MonthlySummary` filter). I then compared
it with the auditor row by row.

| # | Weakness | Effect today | Risk |
|---|---|---|---|
| W1 | **The auditor counts `needsReview` rows, but `MonthlySummary` skips them** (`monthly_summary.dart:198`). Activity, cards, recurring and insights *do* include them. | 8 rows: 6 real spends worth ₹4,938 (3042, 3188, 3202, 3601, 3876, 5069) are missing from Home's totals but present in the auditor and in Activity. Home spend for the labelled set is ₹8,94,778; the auditor says ₹9,00,258. | Home recall is overstated. This is also why "out" differs between tabs. |
| W2 | **A row can be flagged `needs_review` but never reach the review queue.** The extractor sets `needsReview = viaPaymentApp \|\| shouldReview(...)`. `ReviewQueue.reviews` re-derives the flag *without* `viaPaymentApp`. | 5515 (a ₹14,868 "trf to CRED/PhonePe" transfer) is left out of the summary's transfers and card-bills-paid, and no screen ever asks about it. Stored flags: 8; queue count: 7. | The row stays out of the totals for good, and the user cannot see it. |
| W3 | The order is different: the auditor runs admission *before* dedupe; the app dedupes every stored row and admits afterwards. | No difference on this inbox: the replica's visible set equals the auditor's set exactly (733 rows). | Latent. A countable alert can be merged into a non-countable winner and disappear. The replica checks for this ("LOST:"); none today. |
| W4 | **P2 is scored only through gold `dup_of`.** None of the 138 `dup_of` links crosses a chunk boundary. Labellers saw one chunk at a time, and notes say "bank leg not in chunk". | I hunted independently for counted pairs with the same amount within 3 days (any sender): no unlabelled double among counted rows. In the gold set, 6660 (merchant refund notice) and 6680 (bank refund credit, 46 h later) are one refund labelled as two. | A duplicate the labeller missed scores as two correct movements. Re-check `dup_of` across the 7 chunk boundaries. |
| W5 | The card-bill check pairs legs only when **both** are labelled `card_bill_payment` and the amounts match exactly within 3 days. | 42 issuer credits but only 5 bank debits are labelled card-bill. A bank leg labelled `other`/`spend` (ruling 14, "trf to PhonePe") would never be paired. | A bill counted as spend plus its issuer leg would not show up as a P2. |
| W6 | **The kind mapping hides sub-kind errors.** `effectiveKind` folds every non-income inflow into `transfer`; gold maps refund/cashback/p2p/self/investment credits to `transfer` too. | Of 127 counted credits, 18 carry the wrong `MoneyInKind` but score as correct: own-account credits as `p2pReceive` (8), TD/RD funding or closure as `p2pReceive`/`selfTransfer` (8), a refund as `p2pReceive` (1), a meal-wallet credit as `refund` (1). | The money-in breakdown (refunds vs from-people vs own accounts) is not measured at all. |
| W7 | Direction errors are counted but not listed. 5 of the 7 are a gold convention: for a TD closure the gold root is the *debit* leg, while the app keeps the credit leg (3335, 4125, 4440, 5914, 7168). | The 2 real direction errors are 3997 and 3998: a merchant's "your payment of Rs X received" booked as **money in**. | Fix the convention so that `direction errors` means something. |
| W8 | The amount tolerance is ₹1, and foreign currency is not modelled. | Gold 5864 records a USD charge as a rupee amount (₹5.30). | Amount agreement of 100 % says nothing about FX rows. |
| W9 | Not measured at all: categories, bill notices (`card_bills`), learned rules and excluded shapes, the 400-day read window, `card_metrics` outstanding. | — | Card "Total due" and "Bill due" have no accuracy check. |
| W10 | Held-out leakage: the parser commits after labelling (for example `5263c06`, the NEFT remitter fix) were developed against the same 5,274 messages. | — | "Held-out" is held-out from labelling, not from tuning. Freeze a fresh slice (newer SMS) for round 4. |

---

## 3. Gold label spot-check

**Random sample: 60 labels.** 22 money, 12 promos that contain an amount, 14 info messages
mentioning refund/debit/credit, 6 merchant receipts, 6 otp/bill/phishing. Seed `20261026`.

- Clear errors: **1 of 60 (1.7 %)**. 7592 is labelled `promo`, but it confirms a prepaid
  payment that already happened (with a card cross-sell). Ruling 13 makes it a `debit/spend`
  with `dup_of` 7597. It is harmless today because both readings keep it out of the ledger.
- Debatable: TDR-created notices labelled `debit/investment` with no `dup_of` (4970 and 9 others).
  They are consistent with each other, so I did not count them.

**Targeted searches** (regexes over all 5,274 labels) found more:

| Id(s) | Issue | Effect on metrics |
|---|---|---|
| 5864 | A USD card charge is labelled as an INR amount. | Wrong gold amount; also a missed spend (the app does not count FX at all). |
| 6660 + 6680 | One refund (merchant notice, then bank credit 46 h later) is labelled as two originals. | 6660 counts as a "missed refund"; recall is understated. |
| 6602, 7845 | Fund-house confirmations with no bank debit nearby are labelled `debit/investment`. Ruling 12 says `info`. | Two false "missed" movements. |
| 6963, 6964 vs 8155 | The same PharmEasy "Rs X credited to wallet" promo template is labelled `credit/cashback` twice and `promo` once. | Inconsistent; the auditor cannot be right on both. |
| 4291 vs 5873 | The same service-bill-ready template is labelled `bill_notice` once and `info` once. | Cosmetic. |
| 3335, 4125, 4440, 5914, 7168 | TD closure: the root is the debit leg, so the movement direction comes out as "out". | 5 false direction errors (W7). |
| 3858, 4451 | Closure amounts were copied from other messages ("from OTP", "from TDR"). | Fine if right, but the amount cannot be checked against the body. |

**Label error rate on money-affecting labels: about 6 of 905 (0.7 %).** On a random draw it is
1.7 % (1/60). No error found makes P1 or P2 look better than it is. The errors lean toward
*understating* recall.

---

## 4. Adversarial synthetic messages (outside the gold set)

The cases run through the app's own classifier, extractor, `TxnGuards` and `DedupeEngine`
(`.review_tmp/audit3/adversarial.dart`). The results below are at HEAD. The working tree
changes only D08, which it fixes. 95 cases: 46 must not count, 30 must count with the right
kind and amount, 19 dedupe groups. **30 fail at HEAD.** One of them is debatable: A46, "debited,
will be reversed (invalid beneficiary)", counted as spend under review. Some failing templates
are approximations of real formats; these are marked *(approx.)*.

### P1: counted although no money moved

| Case | Template (paraphrased) | Expected | Got | Sev |
|---|---|---|---|---|
| A34 | "Txn of Rs X on HDFC card at MERCHANT **failed**. Any amount debited will be refunded" | not counted | **spend ₹X** | **P1** |
| A37 | "Rs X **will be auto-debited** from your card on DATE for SPOTIFY standing instruction" | not counted | **spend ₹X** | **P1** |
| A42 | "Your UPI txn of Rs X to ZEPTO **could not be processed**. If debited, it will be auto-reversed" | not counted | **spend ₹X** (merchant "ZEPTO could not be processed") | **P1** |
| A35 | From a **phone number**: "Rs X credited to your account **by mistake** from PhonePe, please return to VPA" (classic refund scam) | phishing, not counted | inflow ₹X (selfTransfer), not flagged | **P1** |
| A01 | Wallet header (-S): "Rs X cashback credited\* … claim before midnight: link \*T&C" | not counted | cashback inflow ₹X | P1 (money in) |
| A28 | "Cheque for Rs X deposited in A/c … is **under clearing**" | not counted | inflow ₹X | P1 (money in) |
| A44 *(contrived)* | A bank alert about a *blocked* suspicious card txn of ₹X | not counted | spend ₹X (review) | P1, low |

The guard gaps behind these are `SmsGuards._stopped` and `_future`. They match only
"has failed"/"failed to" (a bare "failed" passes), and they miss "will be auto-debited",
"could not be processed", "under clearing", "by mistake … return" and "claim". Phone-number
senders can post inflows (A35), although a phone-number *debit* (A38) is correctly not counted.

The other 38 P1 cases hold: pre-approved loans, "loan of Rs 36,000 available", EMI-conversion
offers, EMI due, declined, collect requests, statements, balance checks, premium due, lottery,
SIP "will be debited", mandate registered, electricity-disconnection scam, OTP-gated "received
Rs X", pre-auth hold, "refund initiated", limit enhanced, phishing "debited, click to cancel",
Paytm gift-credit promo, pending UPI.

### Wrong kind, direction or amount (spend inflated or missed)

| Case | Template | Expected | Got | Sev |
|---|---|---|---|---|
| B25 / D14 | A merchant's "your payment of Rs X **received**" (Royal Enfield, Zomato) | spend ₹X | **money in** ₹X (selfTransfer) | other (direction). The real inbox has 3997 and 3998 (₹4,398) |
| B21 *(real ICICI UPI format)* | "ICICI Acct XX debited for Rs X; ZOMATO credited. UPI:ref" | spend ₹X | transfer/personTransfer: **spend missed** | other (high frequency for ICICI users) |
| B13, B20 | "Sent Rs X from HDFC A/C to RAHUL SHARMA" / "debited … to VPA rahul.s@okicici" | p2p transfer | **spend ₹X** | other (spend inflated; the known no-honorific gap) |
| D17 | HDFC IMPS debit "Info: IMPS-ref-NAME" + SBI "Deposit by transfer from OWN NAME" | one self-transfer | **spend ₹X (review) + money in ₹X** | P2-like (transfer becomes spend + income) |
| B27 | HDFC "UPDATE: INR X debited … Info: IMPS-ref-NAME" | transfer | spend (review) | other |
| B26 | Axis "INR X debited from A/c … at ATM" | cash | spend (review) | other |
| B09, B10 | "Spent USD/EUR X on card at MERCHANT" | spend, INR unknown → ask the user | **not counted at all** | other (real: 5864) |
| B15 | "Your AutoPay of Rs X for NETFLIX was successful on card" | spend | not counted | other |
| B06, B08, D19 *(approx.)* | UPI Lite load, Paytm wallet load "Rs X added to …" | transfer | not counted | low |
| B23 | SBI "debited … towards Credit Card XX payment via NEFT" | card-bill transfer | personTransfer (so it never pairs with the issuer leg) | other, see D07 |

Correct: EMI debit, issuer "payment received", reversal credit, card refund, ATM cash (SBI),
UPI Lite spend, salary, interest, money received, NACH return charges, annual fee, loan
disbursal (not true income), Amazon Pay biller receipt, FD maturity, cashback credit, ₹1,05,590
grouping, Avl-Lmt card spend, a spend that also mentions "cashback earned".

### Dedupe

| Case | Scenario | Expected | Got | Sev |
|---|---|---|---|---|
| D13 | The **same bank alert re-sent 2 h later** from another header (VM-/AD-HDFCBK) | 1 row | **2 rows, spend ×2** | **P2** (the body-signature window is 1 h) |
| D16 | Card refund credit + merchant refund receipt **4 days** later | 1 refund | **2 refunds** | **P2** (money in). Real: 3169/3215 at 72.0 h |
| D07 | Card bill: SBI NEFT debit + issuer credit **72 h** apart (posting lag) | 1 transfer | 2 transfers | P2 (card-bills-paid doubled, not spend) |
| D09 | HDFC SIP mandate debit + fund-house "SIP Purchase of Rs X processed at NAV" (no "folio") | 1 | 2 (investment ×2) | P2 (transfer) |
| D08 | Two genuine ₹X bill payments to **two different cards** within 48 h | 2 | **1** at HEAD (fixed in the working tree, which breaks HDFC, see §1) | other (one card shows unpaid) |
| D04 | Genuine double charge: two identical card spends 60 s apart | 2 | 1 | other (documented trade-off) |
| D10 | Biller receipt ₹X + **unrelated** card spend ₹X at another merchant 8 h later | 2 spends | 1 (receipt folded into the wrong payment) | other (under-count) |
| D14 | Two receipts (Swiggy, Zomato) + one Swiggy bank debit | 2 spends | 1 spend + 1 "money in" | other |
| D11 | Debit with no merchant + an unrelated credit from a person, same amount, same bank, 20 min | 2 | 1 (collapsed into a self-transfer) | other |

Correct: bank + PhonePe for one UPI ref, own accounts at two banks sharing one UPI ref, merchant
refund notice then issuer refund (26 h), two merchants on two rails, CRED + issuer 30 h apart,
ATM switch + bank alert, failed UPI + reversal, a spend and its later refund kept as two rows.

---

## 5. Statements

`flutter test test/statement`: **27/27 pass.**

Adversarial statements (layout-C geometry; generator in `statement_probe.dart`; 4 months,
salary on the 1st):

| Case | Result | Verdict |
|---|---|---|
| S1 oldest-first | 14/14 rows verified, 4 salaries, cycle totals exact | ok |
| S2 newest-first | reversed, warned, identical to S1 | ok |
| S3 no opening balance | first row unverified and warned; totals right | ok |
| S5 newest-first + no opening | ok | ok |
| S6 / S7 page break without / with a repeated header | identical to S1 | ok |
| S9 bonus month (2.5×) | still salary; cycle salary ₹2,50,000 | ok |
| S11 monthly IMPS from the holder's own account | `selfTransfer`, no salary | ok |
| S14 salary on 31 Jul, then 2 Sep | cycles anchored correctly | ok |
| **S4** no opening + **first row's amount under the wrong column** | the ₹1,00,000 salary becomes a **₹1,00,000 spend**; July shows salary 0, spent ₹1,02,500, left **−₹1,25,500**; only a generic "1 of 14 did not reconcile" warning | **High** |
| **S8** arrears from the same employer 19 days after payday | opens a **new cycle** (1–20 Aug, then 20 Aug – 1 Oct, 42 days); arrears counted as salary | Medium |
| **S10** merchant credit without the word "refund" in the narration | booked `otherCredit` → **otherIn** (income), so "left" is inflated | Medium |
| **S15** refund in the cycle after the purchase | August **spent = −₹44,500** | Medium |
| **S16** job change (two employers, two months each) | only the first employer is salary; the last two cycles merge into one partial 3-month cycle with the new salary as "other in" | **High** |
| **S12** ₹25,000 a month by UPI from a parent | detected as **salary** and anchors the cycles | Medium (a user override exists) |
| **S13** "SALARY ADVANCE LOAN" disbursal | marked salary by the word rule | Low–medium |

Root causes are in `SalaryDetector` and `SalaryCycleBuilder` (`lib/engine/salary_cycles.dart`):
- **S16:** only one payer key wins.
- **S8:** any same-payer credit more than 15 days from an anchor becomes a new anchor.
- **S12:** `fromPerson` counts as a salary candidate.
- **S15:** `spentPaise` subtracts refunds without a floor and without attributing them back to
  the purchase cycle.
- **S4:** unverified rows count in cycle totals with the direction taken from their column
  position.

---

## 6. Prioritised fix list

1. **Do not commit the working-tree bill-pairing edit as is.** It makes P2 go 1 → 16 (HDFC's
   two issuer confirmations, 23–48 h apart). Pair same-card, same-direction issuer alerts up to
   48 h apart when refs do not distinguish them, and keep the cross-card guard that fixes D08.
2. **Close the P1 guard gaps** in `SmsGuards`: bare "failed", "could not be processed",
   "will be auto-debited", standing instruction/"SI" scheduled, "under clearing",
   "by mistake … return/refund to", "claim" next to "credited\*". Add A34, A37, A42, A35, A01
   and A28 as corpus fixtures.
3. **Do not post inflows from non-DLT phone-number senders** (A35). Phone-number debits are
   already refused; make inflows match and classify "credited by mistake, please return" as
   phishing.
4. **Make `needsReview` one rule** (W1/W2): either `MonthlySummary` counts what Activity counts
   or both exclude it. `ReviewQueue.reviews` must include `viaPaymentApp` so row 5515 can
   surface. Make the auditor report Home's number (excluding review rows) next to its own.
5. **Merchant "your payment of Rs X received"** is an outflow receipt, not money in. Fix the
   direction in the extractor (real: 3997, 3998; synthetic: B25, D14).
6. **Dedupe windows:** body-signature re-sends up to 24 h (D13), the receipt/refund window to
   ≥ 4 days for refunds (3169/3215, D16), and the card-bill window to about 96 h for NEFT
   payments (D07). Tag "towards Credit Card XX payment" as `creditCardBill` (B23).
7. **Statement salary:** support several employers over time (S16); a same-payer credit within
   the cycle must not open one (S8); keep `fromPerson` out of salary unless the user says so
   (S12); floor `spent` at 0 or carry refunds back to the purchase cycle (S15); leave unverified
   rows out of cycle totals or make them blocking (S4).
8. **ICICI UPI "debited … ; MERCHANT credited"** template → spend (B21). HDFC IMPS/ATM debits →
   transfer/cash (B26, B27, D17).
9. **Foreign-currency spends** (5864, B09, B10): admit them as spend with INR unknown and route
   them to review, instead of dropping them.
10. **Auditor upgrades:** list direction errors; score `MoneyInKind` sub-kinds; score Home's
    `MonthlySummary` view; add a P2 hunt that does not rely on `dup_of` (same amount, 4 days,
    any sender) to catch missed links; fix the TD-closure root convention; repair the gold
    labels in §3 (5864, 6660/6680, 6602, 7845, 7592, 8155 vs 6963/6964); re-check `dup_of` at
    chunk boundaries; freeze a fresh held-out slice.

# Round 3 — India financial expert (M1–M6)

Reviewer stance: ex-fintech product owner, RBI-aware, Indian consumer credit. I grade what the
app *claims and shows*. Build: HEAD `5263c06`. I did not modify `lib/` or `test/`; my probes live
in `.review_tmp/` and import the repo's own engines. No message body from `.local/` is quoted
here: real messages are referred to by audit id, sender family and amount only.

**Round 2: 7.2 / 10 → Round 3: 7.6 / 10 (+0.4).** The SMS ledger is now measured against
hand labels instead of claimed. On 3,274 held-out messages it posts **zero** non-money rows,
finds **98.7 %** of real spends, gets **every** amount right, and the ₹44,497.59 HDFC card-bill
double count is gone (0 card-bill pairs on both legs, on the full 5,274-message inbox too). That
is the biggest single improvement in three rounds. The score does not go further for three
reasons:

1. **The owner's biggest "spend" is not his money.** 12 AMEX **Corporate** Card swipes,
   ₹3,44,251, are booked as personal spend: **38 % of all spend** on the full inbox, and the
   whole of the "Travel" category (₹1,22,620 of ₹1,22,619 on the 2,000-message inbox). The
   app reads "Corp Card" (`transaction_extractor.dart:747`) and then treats it as any other
   credit card.
2. **The new salary-cycle maths is fragile where real salaries are messy.** A bonus paid on a
   different day than salary, or a ₹8,000 reimbursement five days after payday, makes the
   detector find **no salary at all**. Then a ₹4.5 lakh statement is shown as one "Left so far
   ₹4,45,000" cycle. On the statement side a NACH SIP (`BD-NIPPON INDIA MF`) is counted as
   *spent*, and an income-tax refund is netted against spending.
3. **The R2 card and insight blockers are still open.** Utilisation basis labels are still
   never rendered, "Out this month" still adds card bills to card spend, and "Probably the
   extra week" and the "a year at this pace" annualisation still ship.

---

## What I ran

| Source | Command / artefact | Result |
|---|---|---|
| Held-out accuracy audit | `dart run tool/audit_accuracy.dart .local/inbox_full.json .local/gold_heldout --list` | 5,274 messages, 3,274 labelled, 492 real movements, 733 counted (259 outside the gold set). **P1 0 · P2 1 · card bills on both legs 0**. Spend precision **96.5 %** (305/316), recall **98.7 %** (305/309), movement recall 96.1 % (19 missed, 2 of them spend), kind agreement 97.0 %, amount agreement **100 %**, 6 direction errors, phishing false alarms 1, promos kept out 100 %. |
| Failure drill-down (local only) | `audit_accuracy.dart … --show <ids>` | read each failing id privately; I classify them below by template, not by body |
| Statement tests | `flutter test test/statement/sbi_statement_test.dart`, `statements_screen_test.dart`, `pdf_reader_test.dart` | **18 + 6 + 3 = all pass**. Running the whole folder at once sat in "Running build hooks" for more than 10 minutes on first build. Run file by file, each finished in seconds. |
| Full-inbox replay | `dart run tool/replay_inbox.dart .local/inbox_full.json` and `.local/inbox.json` | 5,274 msgs: 733 counted, spend ₹9,00,258, **Other 32.8 %**. 2,000 msgs: 259 counted, spend ₹3,34,378, **Other 4.1 %**. `CLAUDE.md` still says 0.7 %. |
| Ledger probe | `.review_tmp/r3_ledger_probe.dart` (classifier → extractor → guards → `DedupeEngine`, as the audit does) | money-in by kind, transfers by reason, AMEX Corp share, meal-wallet share, person-looking "trf to" spends, surviving card-bill pairs (0) |
| Cycle/salary probes | `.review_tmp/r3_cycles_probe.dart`, `r3_cycles_probe2.dart` (synthetic SBI narrations through `StatementClassifier` + `StatementImporter.analyse`) | 25 narration spot-checks; 10 salary scenarios (bonus, reimbursement, job change, parent allowance, tenant rent, split bill, pension, loan-app credit, early pay, two occurrences); one full cycle with card bill + SIP + ITR refund |
| Code read | `lib/engine/salary_cycles.dart`, `lib/services/statement/statement_classifier.dart`, `statement_importer.dart`, `lib/views/widgets/salary_cycle_card.dart`, `salary_cycle_screen.dart`, `home_screen.dart`, `monthly_summary.dart`, `docs/eval/gold-labelling.md`, `docs/research/07-sbi-statement.md` | the formulas and strings quoted below |

Evidence limits:

- Statement import has **never been run on a real SBI PDF**. `CLAUDE.md` says so, and every
  statement test uses synthetic fixtures (`tool/make_statement_pdf.py`). My narration checks
  use the shapes that `07-sbi-statement.md` §3.1 marks as *seen* in real SBI files.
- The phone was disconnected. I made no device-DB measurement this round. The replay is the
  source of truth for money.

---

## Scores

| # | Criterion | Wt | R2 | R3 | Weighted (R3) |
|---|---|---|---|---|---|
| M1 | Correct financial semantics | 20 | 7.5 | **7.5** | 150 |
| M2 | Credit-card intelligence | 20 | 6.5 | **7.0** | 140 |
| M3 | SMS reality | 20 | 6.5 | **8.0** | 160 |
| M4 | Insight quality | 15 | 6.5 | **6.5** | 97.5 |
| M5 | Compliance & claims | 15 | 8.5 | **9.0** | 135 |
| M6 | India-specific usefulness | 10 | 8.0 | **8.0** | 80 |
| | **Weighted total** | **100** | **715 → 7.2** | | **762.5 → 7.6** |

### Automatic-fail check

| Fail condition | Status |
|---|---|
| Card-bill payment counted as spend | **Does not fire.** SMS: 27 `creditCardBill` transfers, ₹3,57,822, none in spend; 0 same-amount pairs counted on both legs. Statement: `cardBill` is outside `spentPaise`. Close call: Home's "Out this month" and the cycle's "Money out" both add card bills to spend, see B5. They are labelled "out", not "spent". |
| 30 % called an RBI rule | Does not fire (no "RBI" or "CIBIL" in `lib/views`, `lib/engine` or `lib/app`). |
| Credit score presented | Does not fire. |
| Financial product recommended | Does not fire. |

### Delta in the numbers that matter

| Metric | R2 | R3 | Read |
|---|---:|---:|---|
| Card-bill payments counted twice | 6 HDFC pairs, ₹44,497.59 | **0** | fixed: dedupe now pairs bank and issuer legs across days |
| "trf to PhonePe" card bills | ₹72,570.85 never nets Axis | **merged into the card credit** (held-out 3338/3339/4870) | fixed |
| P1 rows counted that moved no money (hand labels) | not measured | **0 / 3,274** | real evidence for the first time |
| Spend recall / precision (held-out) | not measured | **98.7 % / 96.5 %** | 10 of the 11 false spends are P2P to people |
| Amount errors | — | **0** | |
| Phishing false alarms | 2 of 2 (Airtel KYC) | **1** (held-out 3561: a courier "track your order" link) | Airtel fixed, but precision is still 0 of 1 |
| True-income rows (full inbox) | 0 | **3 salary ₹1,52,626 + 1 other ₹4,800** | the NEFT remitter fix lets salary show the employer |
| Other share of spend | 0.7 % (claimed) | **4.1 %** (2,000 msgs) / **32.8 %** (5,274) | regression, and `CLAUDE.md` is stale |
| Corporate-card spend in personal spend | not noticed | **₹3,44,251, 38 %** | new blocker B1 |
| Statement layouts / tests | — | 4 layouts, 30 tests green, 0 real PDFs | |

---

## The gold-set rulings: are they financially right?

| Ruling (`gold-labelling.md`) | Verdict | Why |
|---|---|---|
| **12. Fund-house SIP confirmation = `dup_of` the bank mandate debit**; ₹3,000 vs ₹2,999.85 allowed | **Right.** | One money movement, two witnesses. The ₹0.15 is the 0.005 % stamp duty on MF purchases (since 1 Jul 2020), so the bank leg is the correct amount. **Weak spot:** "no bank debit nearby → `info`" makes a SIP invisible whenever the debit happens on an account whose SMS goes to another phone, or by UPI-Autopay. Investments are not spend, so P1 is safe, but "Invested" under-reports. Book it as `investment` with source "fund house" when no bank leg exists. Six CBSSBI FD/TD bookings and closures (held-out 3858, 3925, 4122, 4451, 4559, 4969; ₹11k–₹45k) are still `unknown` for the same family of reason (`CBSSBI` not in `SenderRegistry`, an open todo). |
| **13. Merchant receipt counted only when no bank/card alert exists within 3 days** | **Right in principle; one direction bug.** | "One movement, one row" is right. But receipts worded "your payment of Rs X **received**" are booked as **money in**. Held-out 3997/3998, a Royal Enfield product receipt, ₹2,799 + ₹1,599, became `income/selfTransfer`. The direction must come from who the sender is (a merchant), not from the verb. A biller receipt with no bank alert is also still dropped: held-out 4739 (Jio recharge, ₹349) and 4140/4175/4694/5333 (Zepto refunds) are `informational`. |
| **14. SBI "trf to <NAME>" is spend unless it is clearly a person; "trf to PhonePe/Paytm/CRED" is a reviewed transfer** | **Half right.** | The PhonePe half is right: on this inbox 3 of those debits were card bills, and the app paired them with the issuer credit. The NAME half leans the wrong way. SBI truncates to about 16 characters, and on SBI's UPI rail P2P is a large share of value. The audit's own result: **10 of the 11 false spends are P2P** (3375, 3760, 3895, 4558, 4873, 5032, 5437, 5608, 5691, 5942; the 11th, 4613, is a debit-card fee that is arguably spend), and on the full inbox 15 person-looking "trf to" spends total ₹25,945. Worse, the two pipelines disagree. The SMS ledger makes `Mr./Ms.` P2P a `personTransfer` (not spend, ₹3,22,706), but the statement path counts **every** `toPerson` as *spent* (`StatementKind.isSpend` includes it). The same rent to the same landlord is spend on the cycle screen and a transfer on Home. Pick one rule: a separate "Sent to people" line that sits inside "out" but outside category spend, on both surfaces, learnable per payee. |
| **11. Meal/benefit wallet loads (Pluxee) = `credit/other`, not salary; wallet spends counted as spend** | **Internally inconsistent.** | 102 Pluxee spends (₹33,644) enter spend, while the loads that fund them enter neither income nor savings maths. A month with salary will then show a savings rate depressed by the meal benefit. Either count the load as benefit income (it is part of CTC), or keep both sides out of the savings maths. Do not count one side only. |
| **15. Card-bill legs are not `dup_of`; the auditor pairs them** | **Right.** | They sit on different instruments. The app counts exactly one transfer (verified: 0 surviving pairs). |
| TD closure legs merge | **Right on principal; interest is lost.** | A TD closure credit is principal plus interest. Booking the whole thing as `redemption` means the interest, which is taxable income, never appears. Split it when the SMS prints both amounts. Otherwise label it "includes interest". |

---

## The salary-to-salary cycle maths

What the code does (`salary_cycles.dart`):

- `spentPaise = spend + toPerson + charges + otherDebit − (refund + cashback)`
- `outPaise = spent + cardBills + cash + loan`
- `leftPaise = salary + (interest + otherCredit) − outPaise`

Investments and self-transfers are outside "out". The UI calls `leftPaise` **"Saved this
cycle"** and, on the detail screen, "Saved (incl. invested)".

| Item | Verdict | Evidence |
|---|---|---|
| Card bills in "out", not in "spent" | **Defensible, and labelled.** | On a bank-only view the card bill is the only trace of card spending, and the detail screen says so in one sentence. But it contradicts the doc's own §4.4 ("Not spent, shown separately: `cardBill`… and `cash`"). It also differs from Home's "Left", which does **not** subtract EMIs. Two "left" definitions again: the R2 complaint, now across screens. |
| Investments excluded from out, "Saved (incl. invested)" | **Right.** | |
| Self transfers excluded | **Right when detected, and detection is narrow.** | `_isSelf` needs the holder's full name, 6 or more letters. An IMPS from the owner's own HDFC account printed `A K SHARMA` (initials plus surname, which the doc's §3.2 asks for) becomes `otherCredit`. `otherCredit` is **added to "Saved"**: my probe shows a ₹50,000 own-money transfer lifting "Saved this cycle" from ₹1,06,000 to ₹1,56,000. |
| Refunds netting | **Over-broad, and spend can go negative.** | `_refund` matches `REFUND\|REVERSAL\|REV\|RETURN`. `BULK POSTING-ITD TAX REFUND` (an income-tax refund, which the doc lists as *seen*) is classed as `refund` and netted against consumption. Probe: ₹33,649 of real spending shows as **"Spent ₹6,000"**, with a **"Refunds −₹32,000"** category line. A refund landing in a later cycle, or one larger than that cycle's spend, gives a **negative** `spentPaise` (probe: −₹6,000). Nothing clamps it and nothing explains it. |
| P2P netting | **Asymmetric.** | `toPerson` is spent, but `fromPerson` (a friend paying back their half) is excluded both from netting and from "in". A ₹3,000 dinner split three ways shows ₹3,000 spent, not ₹1,000. |
| SIP by NACH counted as **spent** | **Wrong, and it is the round-1 B4 bug reborn on the statement side.** | `DEBIT-ACHDr … BD-NIPPON INDIA MF` (the doc's own *seen* shape): matching runs on space-stripped text, so `INDIAMF` defeats the `[^A-Z]MF` boundary. The row falls to `otherDebit`, the categoriser labels it "Investments", and it is counted in `spentPaise`. |
| "Renewal" = investment | **Wrong for anything but an FD.** | `_investment` contains bare `RENEWAL`. A UPI to Netflix with the note "renewal" and an LIC premium "policy renewal" both become **Invested**, and so are added to "Saved". |
| Cash by self-cheque | **Wrong.** | `_isSelf` runs before `_cash`, so `CASH WITHDRAWAL BY SELF CHQ…` and `CHQ PAID-SELF-CASH` become `selfTransfer`. Branch cash disappears from "out". |
| Unnamed credits in "Saved" | **Inconsistent with the copy.** | The doc says "nothing that is not salary is ever called income", yet `otherCredit` raises "Saved" while `fromPerson`, `redemption` and `selfTransfer` do not. A tenant's UPI rent (`fromPerson`) is real income and is dropped. An unrecognised own-account NEFT is not income and is counted. |
| Partial cycles | **Right.** | The stretch before the first salary and the running cycle say "In progress" / "Before first salary", and the copy switches to "Left so far". |

### Salary heuristic (`SalaryDetector`)

| Scenario (probe) | Result | Verdict |
|---|---|---|
| Salary on the 1st, **bonus on the 20th** | **No salary found.** The whole ₹4.5 lakh period is one partial cycle: "Left so far ₹4,45,000". | **Bug.** Gaps under 10 days are skipped, but a 19-day and a 12-day gap count as "not monthly", so cadence falls to 1/3. If the bonus *were* accepted it would also open a new cycle (more than 15 days from the anchor), which would swallow the next payday. |
| ₹8,000 **reimbursement 5 days after payday**, 3 months | **No salary found.** | **Bug.** The 5-day gap is skipped, but the next gap (reimbursement → next payday, 23 days) falls outside 24–38. The code comment claims this exact case is handled. The unit test "a refund-sized credit is not salary" passes only because its dates make a 26-day gap, and it never asserts that the ₹6,200 is *not* salary. In fact every credit ≥ ₹5,000 from the payer is added to `rowIndexes`, so reimbursements are counted as salary. |
| **Job change** (A × 4 months, F&F, then B × 3 at ₹1.4 lakh) | Only A is salary. A's F&F anchors a 75-day partial cycle, and B's ₹4.2 lakh shows as "other credits". | The doc's §4.3 rule (stream A stops, B starts within 45 days) is not implemented. |
| Monthly **parent allowance by UPI** from a person | Labelled **"salary"** ("a similar credit from SUNITA SH…"). | Wrong label. The doc's §4.2 says "UPI is never a salary channel"; the code admits `fromPerson`. |
| **Pension** via `RBIS0GOUPEP … TREASU` | Found by recurrence (3 months). | Right, but one month of pension is not found, although the doc calls the treasury IFSC a strong signal. |
| **`EARLYSALARY`** (a lending app, now Fibe) NEFT credit | Labelled **salary** by keyword ("The bank narration says salary"). | A loan disbursal shown as salary. Block lender names before the keyword path. |
| Salary paid early (27 Feb, 31 Mar) | Cycles 31 Jan–26 Feb and 27 Feb–30 Mar. | Right. |
| Two occurrences only | Asserted as salary. | The doc asks for a "looks like salary — confirm?" at exactly 2. Not built. |
| Two employers at once | Only the best-scoring payer is salary; the second counts only if worded. | The doc says to count both streams; the code does not. |

### Narration table vs. how SBI prints things

Right: `UPI/DR|CR/<RRN>/<name>/<bank>/<vpa>/<note>`, `NEFT*<IFSC>*<UTR>*<remitter>`,
`OTHPG/SBIPG/OTHPOS/SBIPOS`, `ATM WDL`, `CREDIT INTEREST`, `BULK POSTING`/`CEMTEX`, `SALARY`
glued to a CTD reference, `CR_` cashback, sweep/MOD, `CASH DEPOSIT SELF` → self. Money is
integer paise, the running balance is checked on every row, and a dropped row is reported,
not hidden. That is the right foundation.

Wrong or missing, against the doc's own §3.1:

- `ACHDr … <AMC> MF` → spend (above).
- `ITD TAX REFUND` → refund (above).
- `TO CLEARING-Chq` → `otherDebit` "Other"; the doc says `toPerson`, or `cardBill` when the payee is a card.
- `TO TRANSFER-INB Gift to relatives / Friends` → spend "Other"; the doc says `toPerson`.
- `CHEQ` inside `_cardBill` also matches **CHEQUE**: a credit "BY CLEARING CHEQUE…" falls through to `otherCredit` by luck, and a debit "TO CHEQUE…" would become a card bill.
- An insurer NACH (`HDFC LIFE INSURANCE`) → `otherDebit` with category Bills. That is acceptable, but the doc says spend (insurance).
- **No join with the SMS ledger** (§3.3, UPI RRN). Statement and SMS are two islands, so Home's "Out this month" and the cycle's "Money out" cover the same days with different numbers.

---

## M1 — Correct financial semantics: 7.5 (unchanged)

Gains: card bills never counted twice; the PhonePe card-bill leg is paired; salary SMS from an
employer NEFT is now recognised (3 rows ₹1,52,626); true income stays a taxonomy;
investments (115 rows, ₹3,05,550), self transfers, wallet loads and redemptions stay out of
spend.

Holding it back:

- **B1 (new): corporate-card spend is counted as personal spend.** It is ₹3,44,251, 38 % of
  spend, and equals the whole Travel category. An Amex *Corporate* Card is billed to the
  company or reimbursed by it. The employer's ₹4,800 NEFT (held-out 3320, labelled `other`,
  very likely a reimbursement) is meanwhile booked as **true income**, so both sides inflate.
- **B2:** P2P is spend on the statement but a transfer in the SMS ledger, and SBI-truncated names default to spend (11 of 11 false spends).
- **B3:** the statement-side errors listed above (NACH SIP spent, ITR refund netted, renewal = invested, self-cheque cash dropped, `otherCredit` in Saved).
- Merchant "payment received" receipts booked as money in (6 direction errors held-out).
- Meal-wallet half-counting.

## M2 — Credit-card intelligence: 7.0 (from 6.5)

Up because the outstanding is no longer corrupted: the HDFC phantom ₹34,895.73 credit (from
the doubled payments) is gone, and the Axis July bill paid via PhonePe now nets. Not higher,
because none of the R2 card items moved:

- `reportedLabel`, `liveLabel`, `projectedLabel`, `limitIsEstimated`, `dueDateLooksWrong` and `creditBalancePaise` still have **0 reads in `lib/views`**.
- The ring is live and the face is reported.
- The statement day is clamped to 1–28 in the editor.
- A corporate card sits in the personal utilisation ring. A company-liability card does not report to the user's bureau file at all, and an individual-liability one does; the app cannot tell which and does not ask.

## M3 — SMS reality: 8.0 (from 6.5)

The gold-set audit is the right instrument, and the held-out split (never tuned on) makes the
numbers credible: P1 0, amount agreement 100 %, promos kept out 100 %, phishing false alarms
172 → 1. Remaining:

- CBSSBI FD/TD alerts are unparsed (6 held-out investment legs).
- Zepto refund SMS and a Jio recharge receipt are `informational`.
- "Payment … received" merchant receipts flip direction.
- A courier tracking link is flagged as phishing (the shortlink alone should not be enough when there is no ask for credentials, money or KYC).
- A Zomato refund is counted twice (P2 1: bank credit + Zomato's own refund SMS, held-out 3169 ← 3215).

## M4 — Insight quality: 6.5 (unchanged)

The salary-to-salary cycle is the most useful new insight for an Indian salaried user, and the
copy around it is careful ("Left so far", "Before first salary", the card-bill sentence). But:

- It is **wrong in exactly the months people look at**: the bonus month and the reimbursement month.
- It can show a large "Left" with no salary found.
- A tax refund can make "Spent" look like a fifth of reality.

Still open from R2:

- `_categorySpikes` still says "Probably the extra week" (`insights_engine.dart:88`).
- `insight_breakdowns.dart:31,70` still annualise with "a year at this pace".
- Home "Left" and the cycle "Saved" use different definitions (EMIs).

## M5 — Compliance & claims: 9.0 (from 8.5)

The statement import is DPDP-sound by construction:

- PDFium runs on-device, and the password is used once and never stored (`statements_controller.dart:37`, copy on `statements_screen.dart:173/239`).
- The picked file's cached copy is deleted.
- No network is used.
- No score, no "RBI says 30 %", no product.

Two framing fixes: a lender's disbursal must not be called "salary" (`EARLYSALARY`); and
corporate-card exposure should not be framed as the user's own credit utilisation without
asking.

## M6 — India-specific usefulness: 8.0 (unchanged)

Gains: SBI statement import, salary-to-salary cycles, the Indian ₹ grouping, and recognition of
the meal wallet. Losses:

- "Other" is **32.8 %** of spend on the full inbox: Axis card merchants, 90 HDFC rows, ATMSBI POS rows, and Flipkart *flight* bookings that are not Travel.
- `CLAUDE.md` still advertises 0.7 %.
- Statement import is SBI-only and has never been tried on a real PDF.

---

## Five strongest things

1. **A real answer key.** 5,274 messages hand-labelled from the text, never from the parser, with 3,274 held out. P1 = 0, spend recall 98.7 %, 0 amount errors. Few Indian SMS trackers can state their accuracy at all.
2. **Card bills are counted once.** Cross-day pairing of the bank leg and the issuer leg works, including the PhonePe-routed bill, and R2's ₹44,497.59 double count is gone.
3. **Statement arithmetic is the authority.** Every row is balance-checked, a misplaced debit/credit is corrected by the balance, a dropped row is surfaced, and money is integer paise.
4. **Salary from behaviour, not keywords.** The employer NEFT with no "salary" word, the CTD-glued `Salary of`, and treasury pensions are all handled, and user overrides win both ways.
5. **Privacy design of the import.** The password is never stored, the cached file is deleted, everything runs on-device, and the copy says so plainly.

## Everything blocking 9.5

| # | Blocker | Evidence | Criterion |
|---|---|---|---|
| B1 | Corporate-card swipes counted as personal spend | 12 rows, ₹3,44,251 = 38 % of spend; on the 2,000 inbox it is the entire Travel line; the employer reimbursement NEFT is counted as income | M1, M2 |
| B2 | One rule for P2P across SMS and statement; truncated SBI names default to spend | 10/11 held-out false spends are P2P; 15 person-looking rows ₹25,945; `StatementKind.isSpend` includes `toPerson`, while SMS `personTransfer` is not spend | M1 |
| B3 | Salary detector fails on bonus-day and reimbursement months; accepts UPI from a parent and a lender's disbursal | probe scenarios 1, 5, 3, 7; test "refund-sized credit is not salary" asserts nothing about the credit | M4, M6 |
| B4 | Statement classifier: NACH MF SIP spent; ITR refund netted; "renewal" = investment; self-cheque cash = self transfer; `otherCredit` lifts "Saved"; initials-only own transfer not self; negative "Spent" possible | probe2: "Spent ₹6,000" for ₹33,649; probe 6: spent −₹6,000, Saved +₹50,000 | M1, M4 |
| B5 | "Out this month" (Home) and "Money out" (cycle) both add card bills to card/UPI spend, and Home "Left" ≠ cycle "Saved" (EMI) | `monthly_summary.dart:76`, `salary_cycles.dart` `outPaise`/`leftPaise` | M1, M4 |
| B6 | Utilisation basis never rendered; ring live vs face reported; corp card in the personal ring | 0 reads of the basis fields in `lib/views` | M2 |
| B7 | Statement ↔ SMS not joined (UPI RRN) | `docs/research/07` §3.3 unbuilt; two "out" figures for the same days | M1, M3 |
| B8 | Category coverage regressed: Other 4.1 % / 32.8 % | replay on both inboxes; `CLAUDE.md` still says 0.7 % | M6 |
| B9 | Merchant "payment received" receipts booked as money in; biller receipts/refunds without a bank alert dropped | held-out 3997/3998 (direction), 4739, 4140/4175/4694/5333 | M3 |
| B10 | CBSSBI FD/TD bookings and closures unparsed; TD closure interest never shown as income | 6 held-out investment legs | M1, M3 |
| B11 | Meal-wallet spends counted, loads not | 102 rows, ₹33,644 | M1 |
| B12 | R2 insight leftovers: "Probably the extra week", linear annualisation | `insights_engine.dart:88`, `insight_breakdowns.dart:31,70` | M4 |
| B13 | Phishing precision still 0/1 (courier shortlink) | held-out 3561 | M3 |
| B14 | Statement import unproven on a real SBI PDF | `CLAUDE.md` #13 | M6 |

## Three highest score-per-hour changes

1. **Corporate-card switch (≈2 h, +0.4 to +0.5).** When a card's alerts say "Corp/Corporate Card", ask once: "Is this a company card?" Default yes: its swipes become `business` (outside spend, savings and the personal utilisation ring), and an employer NEFT within 45 days that matches its bill becomes a reimbursement, not income. That one decision moves 38 % of this user's spend to where it belongs.
2. **Fix the five statement-classifier rules and the two salary bugs (≈4 h, +0.3 to +0.4).**
   - Classifier: match `MF`, `AMC` and fund-house names on the *spaced* text; drop bare `RENEWAL` except `TO TRANSFER-Renewal`/`TDR`; move `ITD|TAX REFUND` to its own `taxRefund` inflow (not netted, not salary); run `_cash` before `_isSelf`; drop `otherCredit` from `leftPaise` (show it as its own line); clamp `spentPaise` at 0 and say why.
   - Salary: drop credits below 50 % of the stream median from the cadence and from `rowIndexes` (label them "Extra from <payer>"); exclude UPI `fromPerson` and lender names from candidates.
   - Add regression tests for each probe scenario.
3. **One P2P rule and one "out" (≈3 h, +0.3).** Add a "Sent to people" line that is inside "out" and outside category spend, on Home, Activity and the cycle screen, with per-payee learning ("Rent to Ramesh" → Rent). Make "Out" = consumption + cash + people, and show card bills beside it as "Paid to cards (not counted again)". Then Home "Left" and cycle "Saved" share one formula.

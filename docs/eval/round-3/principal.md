# Round 3 — Principal engineer review

**Build reviewed:** `E:\flutter_projects\finnance-app` @ `5263c06` ("fix(parser): NEFT/RTGS credits name the remitter").
**Round-2 baseline:** `c87e42b` → `docs/eval/round-2/principal.md` (7.4 / 10).
**Delta reviewed:** `git diff c87e42b..5263c06`: 87 files, +10,376 / −584. Main areas: gold-set-driven parser and dedupe changes, incremental ingest, parser v9, SBI statement import (PDFium via `pdfrx`), salary cycles, release-manifest INTERNET removal.
**Tree note:** commit `89e05af` (on-device logistic-regression "second opinion") landed while I was reviewing, and four `lib/views/` files were modified in the working tree. **Neither is scored here.** All file:line references are to `5263c06`. `dedupe_engine.dart`, `txn_guards.dart`, `sms_guards.dart`, `card_metrics.dart`, `app_state.dart` and the statement code did not change in `89e05af`, so the audit numbers below apply to both.
**Probes:** `.review_tmp/audit_app_order.dart`, `.review_tmp/r3_bill_probe.dart`, `.review_tmp/r3_stale_bill_probe.dart` (throwaway; nothing in `lib/` or `test/` was touched). No message body from `.local/` is quoted here. The probe inputs below are synthetic.

> **Weighted score: 7.7 / 10** (round 2: **7.4**, **+0.3**)
> E1 7.8 (−0.1) · E2 8.1 (+0.7) · E3 8.2 (+0.3) · E4 7.2 (+0.4) · E5 7.5 (+0.6) · E6 7.4 (+0.2)
> (20·7.8 + 20·8.1 + 15·8.2 + 15·7.2 + 15·7.5 + 15·7.4 = 772.5 / 100.)

The headline P2 violation from round 2 is fixed and measured: card bills counted on both legs = 0 on 5,274 hand-labelled messages, and the ₹72,570.85 Axis payment now survives on the card leg. The gold-set auditor is the most valuable thing this round added, because it is the first measurement that is not just the engine checking itself. Three things hold the score below 8:
- **The new 48-hour card-bill rule over-merges.** It pairs any two bill rows of the same amount, whatever their card or direction. Two different cards paid ₹5,000 on the same day collapse into one row, so one card keeps showing its bill as due (proven, §5.1).
- **The "held-out" accuracy claim is not held-out.** The repo's own snapshots show the first unseen run at **64.6 % spend precision with 172 phishing false alarms**. Parser fixes were then made against that set, and 96.5 % was reported as "never tuned on".
- **Real-time and data-safety gaps.** About half of the round-2 list (pending-category ordering, receiver try/catch, "just this" writing a band rule, non-transactional reparse) is untouched. "Clear all data" now leaves the imported bank statements on the phone.

---

## 0. Verification log (commands run from the repo root)

| # | Command | Result |
|---|---|---|
| 1 | `flutter analyze lib` | **No issues found!** (21.6 s). |
| 2 | `flutter analyze` (whole repo) | **30 issues, exit 1** (round 2: 27). All are `avoid_print`/info in `tool/` (demo_check 13, cards_check 8, parser_check 5, audit_accuracy 2, diag_in 1) plus a stray `build/_probe_test.dart`. README:71 still says "zero issues expected". |
| 3 | `flutter test` | **316 passed, 0 failed** (`00:37 +316: All tests passed!`). Round 2: 240. |
| 4 | `flutter test test/sms_corpus_test.dart test/spam_corpus_test.dart` | `OVERALL 113/113` transactions and `OVERALL 77/77` classification. The corpus grew by 4, now with real `cardKey` assertions (`sms_corpus_test.dart:200-201, 286-293`), which closes round 2's "no cardKey coverage". |
| 5 | `dart run tool/audit_accuracy.dart .local/inbox_full.json .local/gold_heldout` | 3,274 labelled · P1 **0** · P2 **1** · card bills on both legs **0** · spend precision **96.5 %** · recall **98.7 %** · amount agreement 100 % · phishing false alarms 1 · app spend ₹5,65,880 vs gold ₹5,44,137 (+4.0 %). Matches CLAUDE.md exactly. |
| 6 | same, `.local/gold` | 5,274 labelled · P1 0 · P2 1 · bill legs 0 · precision 97.2 % · recall 98.9 % · movement recall 95.4 % · kind agreement 97.8 % · app spend ₹9,00,258 vs gold ₹8,78,220 (+2.5 %). Confusion: **13 transfer→spend** (12 are p2p UPI to a person counted as spend), 2 spend→transfer. The one P2 double is a merchant refund receipt plus the bank refund credit (₹379.50, money-in, not spend). |
| 7 | Stored snapshots `.local/audit_*.json` (timestamps + `labelled`) | `audit_heldout.json` @ 01:52, 3,274 labels: **precision 0.646, P2 2, phishing false 172, app spend ₹8,87,397 vs gold ₹5,44,137**. `audit_gold_heldout.json` @ 02:00 (after commit `1e5d85b`'s fixes): 0.965. The held-out labels were written at 01:51, so this is a one-pass tune on the held-out set. See B2. |
| 8 | `.review_tmp/audit_app_order.dart` (the auditor rewired to the app's order: dedupe all rows → admit, optionally drop `needsReview`) | The dedupe/admission order makes **no difference** on this inbox, which is good. Dropping `needsReview` as Home does (`monthly_summary.dart:198`) gives recall **97.6 %** (−1.3 pt), 9 missed spends and app spend ₹8,94,779. **The auditor certifies a ledger that is not the one Home displays.** |
| 9 | `--show` on the five missed `card_bill_payment` legs (headers only) | 4 of 5 are bank-side "trf to PhonePe" debits correctly merged into the issuer leg (`3338→3341`, `3339→3340`, `4870→4872`, `6715→6718`). That last one is round 2's ₹72,570.85 Axis case, now merged into the card leg. The fifth is a ₹1 test debit, classed unknown. |
| 10 | `.review_tmp/r3_bill_probe.dart` | Two issuer confirmations for **two different cards** (Axis XXnnnn, HDFC 6859), ₹5,000 each, 2 h apart → **1 survivor (Axis)**. Two genuine ₹3,000 payments to the same HDFC card 20 h apart → **1 survivor**. §5.1. |
| 11 | `.review_tmp/r3_stale_bill_probe.dart` | A ₹5,000 bill whose statement is from Dec 2023, evaluated at 1 Jun 2026: `hasBill=true billDue=500000 dueDate=2026-06-05 daysToDue=4 dueSoon=true`. §5.2. |
| 12 | `gradlew :app:processReleaseMainManifest` (JBR 17) | Merged **release** manifest has READ_SMS, RECEIVE_SMS, POST_NOTIFICATIONS and the dynamic-receiver permission. **No INTERNET.** `tools:node="remove"` works. The debug merge still has INTERNET (for hot reload, as documented). |

**Artifact honesty.** The auditor reproduces CLAUDE.md's numbers to the decimal, and it prints ids, not bodies, so its output is safe to commit. That is a real step up. What is *not* honest is one adjective, "held out, never tuned on" (CLAUDE.md:25, commit `1e5d85b`), and the auditor's own stored snapshots disprove it.

---

## 1. Criterion table — round 2 vs round 3

| # | Criterion | Wt | R2 | **R3** | Δ | Evidence for the delta |
|---|---|---|---:|---:|---:|---|
| **E1** | Architecture | 20 | 7.9 | **7.8** | −0.1 | **Gains:** dedupe is still one engine, now with five named passes: bill pairing `dedupe_engine.dart:101-124`, re-sent signature `:128-140`, receipts `:149-207`, same-bank opposite legs `:212-226`, shared UPI ref `:230-247`. Statement categories reuse the one `Categorizer` (`statement_classifier.dart:13,16`), and statement money is string arithmetic (`statement_table.dart:139`). **Losses:** (i) **a second ledger with a second taxonomy.** `statement_rows` has its own `StatementKind` enum (spend/toPerson/fromPerson/selfTransfer/cardBill/…), parallel to `TxnKind`+`TransferReason`+`MoneyInKind`. `StatementStore` says the two are "reconciled for display" (`statement_store.dart:50-52`), but no reconciliation code exists, so the salary-cycle screen and Home give two independent spend answers for the same days. (ii) "Not counted until confirmed" is implemented inside `SummaryCalculator` only (`monthly_summary.dart:198,263`), not in `TxnGuards`. `card_metrics`, `insights_engine` and `recurring_detector` still receive `needsReview` rows (`finance_repository.dart:252-288`), so Home and Cards disagree by construction. That is the open "one out figure" todo, made structural. (iii) A **fourth and fifth pipeline**: `tool/audit_accuracy.dart:115-167` and `test/gold_regressions_test.dart:36-40` each rebuild classifier→extractor→guards→dedupe by hand, without learned rules, exclusions or the `needsReview` drop. (iv) A second amount parser: `SmsGuards.planAmountPaise` parses through `double` (`sms_guards.dart:95-99`), outside `AmountFinder`. (v) `NativeSmsParser.kt` still ships and drives the notification amount (rubric auto-fail clause, letter only). |
| **E2** | Money maths | 20 | 7.4 | **8.1** | +0.7 | **Gains, measured against hand labels:** card bills on both legs **0** (round 2: ₹44,497 double counted). The bill-group winner is now the card leg (`_billWinner`, `dedupe_engine.dart:490-509`), proven on the real ₹72,570.85 Axis pair. P1 = 0 on 5,274 labels. Amount agreement 100 %. Spend recall 81.5 % → 98.9 %. Fund-house confirmations and `-P` headers can never post. Losers are now **marked, not deleted** (`sqlite_finance_repository.dart:530-541`). `dueSoon` has a lower bound. **Losses:** (i) **the bill pass over-merges** (§5.1). It needs neither opposite direction nor agreeing `cardKey`, so two cards' payments of one amount within 48 h become one. That under-counts money out and leaves a paid bill showing as due, the mirror of round 2's bug. (ii) **Stale bills now look current** (§5.2): the roll-forward finds the next occurrence of the due day, so a 2½-year-old ₹5,000 statement reads "due in 4 days". Round 2's actual fix (ignore statements older than ~60 days) was not made. (iii) 12 p2p UPI debits are counted as spend, about +2.5 % to +4 % of spend (CLAUDE.md acknowledges this). (iv) `needsReview` money is out of Home's month but inside Cards' cycle and Insights (E1-ii). (v) Receipts are admitted with no money verb (`txn_guards.dart:22-25`) and depend on dedupe for safety. A receipt folds into *any* same-rupee debit within 24 h (`dedupe_engine.dart:170-176`), so an unrelated payment can absorb it. That is a deliberate trade-off, but it is untested at ledger level. |
| **E3** | Testability | 15 | 7.9 | **8.2** | +0.3 | **Gains:** a 5,274-message hand-labelled answer key with an auditor that reports P1/P2/precision/recall/kind/amount. 18 gold regressions. Real-PDF tests through PDFium, including RC4-locked open and needs-password vs wrong-password (`test/statement/pdf_reader_test.dart`). SBI table tests on three layouts. 316 tests, all green. `cardKey` is now asserted in the corpus. **Losses:** (i) the held-out set is contaminated (B2), so the suite has **no generalisation measurement left**. (ii) The auditor's P2 cannot see over-merging: a wrongly merged bill leg shows up as "missed card_bill_payment", which is also exactly how a *correct* merge shows up (§0.9), so the §5.1 bug is invisible to it by construction. (iii) The auditor is not in `flutter test` or CI, and it measures a different ledger from Home (§0.8). (iv) Still **no test for `SqliteFinanceRepository`** (ingest, incremental backfill, `_reconcileDuplicates`, `excludeTxn`, `_applyPendingCategories`) and none for `StatementStore`. `schema_migration_test.dart` still drives a recording fake and asserts `schemaVersion >= 8` (`:149`). The new `statements`/`statement_rows` DDL has no test. (v) The parsers read `DateTime.now()` internally (`statement_table.dart:235,353`). |
| **E4** | Failure handling | 15 | 6.8 | **7.2** | +0.4 | **Gains:** every launch with permission now runs an incremental ingest after the first frame (`app_state.dart:84-91`), with a two-day overlap and a one-time 400-day backfill (`sqlite_finance_repository.dart:165-195`), so a receiver-captured SMS is parsed on next open. Ingest is guarded against re-entry (`app_state.dart:160`). Inserts are batched. Statement import separates *needs password*, *wrong password* and *unreadable* (`pdf_words.dart:44-55`). The screen loops back to the password sheet with a hint (`statements_screen.dart:59-80`), explains an empty parse (`:82-100`), and shows "N of M balances check out" instead of hiding unbalanced rows (`:554-597`). **Losses:** no `WidgetsBindingObserver`, so resume does not ingest. `_applyPendingCategories` still runs **before** ingest and then deletes the whole queue (`sqlite_finance_repository.dart:69`, `:1332`), so a notification category picked while the app was closed is still lost. The new init order makes this certain: `load()` runs first, the incremental ingest second. `TransactionSmsReceiver.onReceive` still has no try/catch. Statement import catches only `PdfOpenError`: a `FileSystemException` from `readAsBytes`, a pdfrx init failure or an SQLite error in `commit` escapes `_import` with no message (the `finally` resets the spinner). `PdfUnreadable` has no test. One malformed row still aborts `load()` (`_txnFromRow` uses `byName`). |
| **E5** | Data safety | 15 | 6.9 | **7.5** | +0.6 | **Gains:** dedupe losers are marked, not deleted (round-2 B5's irreversible write is gone). The **release manifest has no INTERNET** (verified by merge, §0.12). The PDF password lives in a `TextEditingController` that is cleared on dispose (`statements_screen.dart:417-418`) and is passed once to PDFium (`pdf_words.dart:45-50`). It is never stored, never logged and never in an exception message. The picked file's cache is cleared in `finally` (`statements_screen.dart:116`). Statement save is one transaction with a file-hash no-op and a balance-aware row identity (`statement.dart:146-149`). The new tables are additive (`IF NOT EXISTS`). **Losses:** (i) **"Clear all data" leaves the bank statements behind.** `clearAll()` (`sqlite_finance_repository.dart:1295-1304`) deletes seven tables but not `statements`, `statement_rows` or `pending_categories`, and the dialog promises "removes parsed alerts…from this phone". Imported statements hold the holder name, narrations and balances: the most sensitive data the app stores. (ii) "Just this payment" still writes an amount-band negative rule and hard-deletes the row (`:823-856`, `:1063-1072`), round-2 B4, unchanged. (iii) `_reparse` is still `DELETE … WHERE source_type != 'manual'` with no transaction (`:412-418`). Parser v9 makes it run on the owner's next launch over ~5,000 messages. (iv) Row identity uses `account_key = bank:unknown` when no mask is printed (`statement.dart:209`), so two unmasked accounts would merge. (v) `duplicate_of` is sticky: once marked, no code path un-marks a row. The `staleDuplicate` branch (`:547`) is unreachable, because `mark()` passes the stored `isDuplicateOfKey` through (`dedupe_engine.dart:306-311`). That is harmless today, but the code comment claims otherwise. |
| **E6** | Operability | 15 | 7.2 | **7.4** | +0.2 | **Gains:** CLAUDE.md carries an accuracy table that I reproduced to the decimal. The auditor is safe to paste (ids only). The `pdfrx 2.4.7` / `pdfrx_engine 0.4.5` pins state their reason (`pubspec.yaml`). The release permission set is checkable. **Losses:** (i) the "held out, never tuned on" claim (CLAUDE.md:25, `1e5d85b` message) is contradicted by `.local/audit_heldout.json` (§0.7). (ii) README:47 still says "different sender … within 3 minutes", but dedupe now has a 48 h bill rule, a 1 h signature rule, a 3-day receipt rule and same-sender legs. ARCHITECTURE:56 likewise. ARCHITECTURE:68 still says WAL. README:31 (quick classify) is still untrue (E4). README:42 "one parser" while `NativeSmsParser.kt` ships. (iii) Repo-wide analyze is 30 issues versus README's "zero". (iv) No CI, so the auditor and the corpus are manual habits. |

---

## 2. Rubric automatic-fail clauses

| Clause | Present? | Assessment |
|---|---|---|
| Duplicated parser logic across languages | **Yes (letter)** | `NativeSmsParser.kt` unchanged since round 2. It still cannot write `transactions`, so E1 is not zeroed. |
| `double` money | **Marginal** | New `planAmountPaise` parses through `double.tryParse(...) * 100` (`sms_guards.dart:95-99`). Correct for ≤ 2 decimals, but it is a second parse-edge double next to `parseAmountToPaise`. Statement money is strings → paise. |
| Suite passes by asserting nothing | **No** | 316 real tests; corpus asserts `cardKey`; PDF tests assert reconciled balances. |
| Unrecoverable migration | **No** | v9 + two new `IF NOT EXISTS` tables. The reparse is still non-transactional but self-healing. |

---

## 3. The five strongest things

1. **A real answer key, and an auditor that can say "wrong".** 5,274 hand-labelled messages, with written rulings for the hard cases (`docs/eval/gold-labelling.md` §11-15: meal wallets, fund-house confirmations, biller receipts, card-bill legs). `tool/audit_accuracy.dart` reports P1, P2, card-bill-leg doubles, precision, recall, kind, amount, direction and phishing false alarms, by id only. This is the first measurement in the project that was not derived from the engine's own assumptions, which was round 2's meta-blocker (B11). It immediately found 18 double counts the 10-minute checker had certified as zero.
2. **Round 2's top defect is closed and measured.** Bill payments pair across senders for up to 48 h, and the card-aware leg wins (`dedupe_engine.dart:101-124, 490-509`). Card bills counted on both legs = 0 on both label sets. The real ₹72,570.85 Axis case now merges *into* the issuer leg, so the paid bill clears on the card.
3. **Spam/money admission is principled, not keyword soup.** A `-P` DLT header can never post (`sms_classifier.dart`, `dlt_promotional_veto`). Fund-house unit confirmations never post. Receipts are a distinct `sourceType` that only survives when no bank alert covers it. Issuer-owned short-link domains stop KYC reminders from reading as fraud. Results: P1 0, promos kept out 100 %, phishing false alarms 172 → 1.
4. **The statement importer gets the hard part right: verification.** It works from word coordinates, not text (SBI layouts drift amounts away from their narration). Money is string arithmetic. Every row is checked against the printed running balance, and the result is shown ("14 of 15 balances check out") rather than hidden. Re-import is a file-hash no-op, and overlapping statements add only new rows via a balance-aware identity. Real locked-PDF tests run through PDFium.
5. **Offline-by-construction survived a dependency that wanted the network.** `pdfrx` pulls in `package:http`. The main manifest strips INTERNET with `tools:node="remove"`, and the merged release manifest confirms it (§0.12). The password is never persisted, and the picked file is cleared in `finally`. This is the right shape for DPDP-safe statement handling.

---

## 4. Blockers

### A. Round-2 blockers: status

| Round-2 blocker | Verdict | Evidence |
|---|---|---|
| **B2** card-bill double count in "Out this month" | **Fixed** | Bill legs on both sides = 0 (§0.5-0.6). |
| **B3** wrong survivor; payment leaves the card | **Fixed** | `_billWinner`; real pair `6715→6718` (§0.9). |
| **B11** P2 certificate shares the engine's blind spot | **Largely fixed** | The gold auditor is independent of the engine. New blind spot: it cannot see over-merges (B1 below). |
| **B10** docs wrong | **Partly** | "marked, never deleted" is now true. The window description, WAL, "one parser", quick-classify and "zero issues" are still false. A new false claim was added ("never tuned on"). |
| **B6** "to confirm" money moves totals | **Half fixed** | Out of Home's month (`monthly_summary.dart:198`). Still in Cards, Insights and Recurring, and in the auditor. |
| **B7** stale bill due forever | **Not fixed; now disguised** | §5.2: was `daysToDue −526`, now `4` and `dueSoon=true`. |
| **B1** real-time path | **Half fixed** | Ingest on every launch: yes. Resume: no. Pending-category order: unchanged. Receiver try/catch: none. |
| **B4** "Just this payment" writes a band rule | **Not fixed** | `sqlite_finance_repository.dart:1063-1072` → `excludeTxn` → `excluded_shapes` insert (`:842`). |
| **B5** destructive, non-transactional reparse | **Not fixed** | `:412-418`. Now runs over ~5,000 messages after the v9 bump. |
| **B8** `MoneyInKind.other` unreachable / no override | **Half fixed** | Now reachable via `_businessCreditWord` (`transaction_extractor.dart`). There is still no user override on SMS rows, though statements have a salary override. |
| **B9** wallet becomes a card | **Not re-tested; code unchanged** | `_ensureCard` still runs on any `cardKey` (`:283-296`). |

### B. Blockers to 9.5, worst first

#### B1 — The 48-hour card-bill rule merges payments to different cards, and repeat payments to the same card. **High (P2 mirror: under-count, and a paid bill shows as due).**
`dedupe_engine.dart:101-124` groups every `creditCardBill` row by amount and unions any two within 48 h unless `_refsDistinguish`. It never checks that one leg is a debit and the other a credit, or that the two `cardKey`s agree. Issuer confirmations usually print no reference. Proven in §5.1: Axis ₹5,000 + HDFC ₹5,000 two hours apart → one survivor, and the HDFC bill keeps reading as due. Two genuine ₹3,000 HDFC payments 20 h apart → one. Paying several cards the same round amount on salary day is common Indian behaviour. The auditor cannot catch it (E3-ii).
**Fix:** pair only an *outflow* with an *inflow*. Refuse when both legs carry different `cardKey`s. Allow at most one issuer leg per group. Add the two §5.1 cases as gold regressions, and have the auditor flag any merged group whose members' gold `instrument`s differ.

#### B2 — The held-out set is no longer held out, and the docs say it is. **High (measurement integrity: the meta-blocker again).**
`.local/audit_heldout.json` (01:52, labels written 01:51) records the first unseen run: **spend precision 64.6 %, P2 2, phishing false alarms 172, app spend +63 % over gold**. Commit `1e5d85b` then fixed the parser *against those messages* (hdfcbk.io, "to be paid", TD-closure legs, receipt windows, "trf to Mr/Ms"). It reported 96.5 % as "Held-out (labelled after tuning, never tuned on)", and CLAUDE.md:25 repeats it. The honest statement is: *on the first unseen batch from the same phone, precision was 64.6 %; after one tuning pass it is 96.5 %; there is currently no untouched set.* For a different user's banks, generalisation is unmeasured. The patterns added this round are literal templates from one inbox (`sms_guards.dart` `_paidReceipt`, which even includes Bengali recharge wording; `_headerDomains`; "Plan Name :"), so the risk is concrete.
**Fix:** freeze a new, time-split set (for example the next month of SMS, or a second person's inbox) that no one looks at until release. Report "first-look" numbers separately from "after tuning". Correct CLAUDE.md:25.

#### B3 — "Clear all data" leaves imported bank statements on the phone. **High (data safety / DPDP).**
`clearAll()` (`sqlite_finance_repository.dart:1295-1304`) never touches `statements`, `statement_rows` (holder name, every narration, balances) or `pending_categories`. The dialog (`settings_screen.dart:293-297`) says it removes the data "from this phone". The only way to remove a statement is per-account delete in the Statements screen.
**Fix:** delete all nine tables in one `db.transaction`. Add a repository test that counts rows in every table after `clearAll`. Change the dialog copy to name statements.

#### B4 — The notification's category is still destroyed before its transaction exists; the receiver can still lose an SMS. **High (unchanged from round 2 B1).**
`load()` calls `_applyPendingCategories` first (`:69`), and that method deletes the whole queue (`:1332`). The new init order (`app_state.dart:73`, then `:88-90`) makes the cold-start case deterministic: the row is inserted by the incremental ingest *after* the queue is gone. `TransactionSmsReceiver.onReceive` has no try/catch. There is no resume ingest.
**Fix:** apply pending categories after `_processPending`, delete only rows whose update matched, wrap the receiver in try/catch, and ingest on `AppLifecycleState.resumed`.

#### B5 — Stale bills read as current. **Medium-high.**
§5.2. `card_metrics.dart:417-423` rolls any past due date to its next day-of-month, and `_latestBillFor` (`finance_repository.dart:328-343`) has no age limit. A card that stopped sending statements keeps a confident "due in N days" with a years-old amount. That is worse than round 2's obviously wrong −526.
**Fix:** ignore a bill whose `statementDateMs`/`receivedAtMs` is more than ~45-60 days old, and add the §5.2 test.

#### B6 — Home, Cards, Insights and the auditor count different ledgers. **Medium-high.**
`needsReview` is dropped only in `SummaryCalculator` (`monthly_summary.dart:198,263`). Cards, Insights and Recurring receive the rows (`finance_repository.dart:252-288`). The auditor and the gold regression test count them (§0.8: −1.3 pt recall once they are dropped). So "out this month" ≠ Cards' cycle spend ≠ the audited number.
**Fix:** move the rule into `TxnGuards` as `isCountableForTotals`, use it in every engine, and make the auditor and `gold_regressions_test` call one shared `LedgerPipeline` that the repository also uses.

#### B7 — "Just this payment" still writes an amount-band negative rule. **Medium-high (silent future suppression; round 2 B4).**
Unchanged: `markNotTransaction(everyFromMerchant: false)` → `excludeTxn` → `excluded_shapes` insert (`:1063-1072`, `:842`).
**Fix:** the single scope should delete or mark the row only. Add a test that `excluded_shapes` is empty afterwards.

#### B8 — The reparse is non-transactional and now runs over ~5,000 messages on upgrade. **Medium.**
`:412-418`, triggered by `_ensureFreshDerivations` (`:477`) inside `load()`. A kill mid-way leaves an empty or partial ledger until the next launch.
**Fix:** run it inside one `db.transaction` (or build a shadow table and rename it), with a progress state.

#### B9 — Statement import failure paths beyond the PDF engine are unhandled; there is no repository or statement-store test. **Medium.**
`_import` (`statements_screen.dart:49-118`) catches only `PdfOpenError`. `StatementsController.preview` reads the whole file (`readAsBytes`) outside any mapping. There is no test for `PdfUnreadable`, `StatementStore.save` (overlap, same-file), `deleteAccount` or the new DDL. Accounts with no printed mask share the key `SBI:unknown` (`statement.dart:209`).
**Fix:** add a catch-all with a plain-English message, a corrupt-PDF fixture test, and an in-memory `StatementStore` test for overlap and same-file. Key unmasked accounts by holder plus file.

#### B10 — Two ledgers, no reconciliation. **Medium (architecture).**
Statement rows and SMS transactions describe the same SBI account with different taxonomies (`StatementKind` vs `TxnKind`/`TransferReason`/`MoneyInKind`), and nothing joins them. The research doc says statements "catch what SMS miss", but the app never uses them to fill SMS gaps or check SMS totals.
**Fix (staged):** first, map `StatementKind` onto the SMS enums in one table. Then show a per-cycle "SMS saw ₹X, statement shows ₹Y" reconciliation line.

#### B11 — Docs and lint. **Medium.**
README:31, :42, :47, :71 and ARCHITECTURE:56, :68 are false as described in E6. CLAUDE.md:25 says "never tuned on" (B2). Repo-wide analyze has 30 issues. `NativeSmsParser.kt` is still the auto-fail letter.

---

## 5. Proved defects (input → observed → expected)

| # | Input | Observed | Expected | File:line |
|---|---|---|---|---|
| 5.1a | `AX-AXISBK-S` "Payment of INR 5000.00 has been received towards your Axis Bank Credit Card XXnnnn" + `VM-HDFCBK-S` "Online Payment of Rs.5000 has been credited to your HDFC Bank Credit Card ending 6859", 2 h apart | both `transfer/creditCardBill`, `ref=null`; **1 survivor** (`Axis Bank\|5365`), HDFC leg marked duplicate | 2 rows; each card's bill cleared | `dedupe_engine.dart:101-124` |
| 5.1b | two identical-template HDFC ₹3,000 "credited to your … Credit Card ending 6859", 20 h apart | **1 survivor** | 2 payments (different dates in the text) | same |
| 5.2 | bill ₹5,000, statement 16 Dec 2023, due 5 Jan 2024; `now` 1 Jun 2026 | `hasBill=true billDue=500000 dueDate=2026-06-05 daysToDue=4 dueSoon=true hasBillButNoSpend=true` | stale bill ignored | `card_metrics.dart:417-423`; `finance_repository.dart:328-343` |
| 5.3 | gold set, Home's rule (drop `needsReview`) vs the auditor's | recall 98.9 % (auditor) vs 97.6 % (Home's ledger); 9 vs 3 missed spends | one ledger, one number | `monthly_summary.dart:198`; `tool/audit_accuracy.dart:155` |
| 5.4 | `clearAll()` after importing a statement | `statements`, `statement_rows`, `pending_categories` untouched | all user data removed | `sqlite_finance_repository.dart:1295-1304` |
| 5.5 | first audit of the 3,274 held-out labels | precision 0.646, phishing false 172, P2 2 (`.local/audit_heldout.json`) | reported as the generalisation figure; 0.965 is a post-tuning figure | CLAUDE.md:25 |
| 5.6 | a row with stored `duplicate_of` whose winner is gone | stays marked forever; the `staleDuplicate` branch is unreachable | either un-mark it or delete the comment | `dedupe_engine.dart:306-311`; `sqlite_finance_repository.dart:547` |

---

## 6. Three changes with the best score-per-hour

### 1. Make bill pairing direction- and card-aware, and make the auditor see over-merges (≈2 h; E2 +0.4, E3 +0.2)
- In the bill pass, require `_isInflow(a) != _isInflow(b)`, refuse when both `cardKey`s are non-null and differ, and cap each group at one issuer leg.
- Add §5.1a and §5.1b to `gold_regressions_test.dart`.
- In the auditor, report "merged across instruments" (merged groups whose gold `instrument`s differ) as a P2-mirror metric.

**Why first:** it is the only new money bug this round, it sits on the number the owner reads first, and it is a few lines.

### 2. One ledger pipeline, used by the app, the auditor and the gold tests (≈3 h; E1 +0.4, E2 +0.2, E3 +0.3, E6 +0.2)
- Extract `LedgerPipeline.build(messages, rules, exclusions)`: classify → extract → exclusions → rules → dedupe → `isCountableForTotals`, with `needsReview` and stale-bill handling inside.
- `_processPending`, `HomeDataBuilder`, `audit_accuracy.dart` and `gold_regressions_test.dart` all call it.
- Every engine (summary, cards, insights, recurring) takes the same admitted list.
- Add the auditor run on `.local/gold` as an opt-in `flutter test --tags gold` that fails on P1 > 0, P2 > 0 or bill legs > 0.

**Why second:** it closes "one out figure", B6 and the measured-ledger-≠-shown-ledger gap in one move, and turns the auditor into a gate.

### 3. Data-safety sweep (≈3 h; E5 +0.6, E4 +0.4, E6 +0.2)
- `clearAll` covers all nine tables in one transaction, with an updated dialog (B3).
- Run the reparse in a transaction (B8).
- Make "Just this payment" row-only (B7).
- Apply pending categories after ingest and delete only matched rows; add receiver try/catch; ingest on resume (B4).
- Add a statement-import catch-all and a corrupt-PDF test (B9).
- Correct CLAUDE.md:25 and README:31/:42/:47/:71 (B2, B11).
- Add the first `SqliteFinanceRepository` test, using `sqflite_common_ffi` or an in-memory fake, covering `clearAll`, `excludeTxn` and pending categories.

**Why third:** every item is small, and together they remove all remaining silent-loss and stale-data paths, which is most of what separates E4/E5 from 8.5.

**After these:** freeze a genuinely untouched evaluation set (B2), reconcile statements with SMS per salary cycle (B10), retire `NativeSmsParser.kt` (the notification amount can come from a 20-line Dart-equivalent or no amount at all), and fix the stale-bill rule (B5, ~30 min, and arguably belongs in change 1).

---

## 7. Projection

| Fix | E1 | E2 | E3 | E4 | E5 | E6 | Weighted |
|---|---|---|---|---|---|---|---|
| Bill pairing + over-merge metric + stale bills | 0 | +0.6 | +0.2 | 0 | 0 | 0 | **+0.15** |
| One ledger pipeline + gold gate | +0.4 | +0.2 | +0.3 | 0 | 0 | +0.2 | **+0.20** |
| Data-safety sweep + repository test + doc truth | 0 | 0 | +0.2 | +0.5 | +0.7 | +0.4 | **+0.27** |
| Fresh untouched eval set, reported honestly | 0 | 0 | +0.3 | 0 | 0 | +0.3 | **+0.09** |
| Delete `NativeSmsParser.kt`, statement↔SMS reconciliation | +0.6 | +0.2 | 0 | 0 | 0 | 0 | **+0.16** |

Doing the first three takes this to about **8.3-8.4**. The road to 9.5 then needs two things: the eval set to stay honest under a second user's inbox, and the app to ship a single ledger that every screen and every metric agree on.

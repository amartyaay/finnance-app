# Round 1 — Principal engineer review

**Build reviewed:** `E:\flutter_projects\finnance-app` @ `da88e2f` ("fix(dedupe): a transfer leg pairs with an income leg").
**Review window:** 2026-10-25 21:39–22:05 IST. `8f0765a` was HEAD when I started; `da88e2f` landed mid-review. Every number below was re-run on `da88e2f` unless marked.
**Working tree during the review:** clean at 21:39, dirty by 21:51 — other agents started committing/editing while this review ran. HEAD remained `da88e2f`; the working tree now contains an uncommitted **fix for B1** (`RawSmsStore.kt:33,112` → `onDowngrade` + version 7), a small `card_metrics.dart` clamp change, and a large UI pass in `design_tokens.dart` / `theme.dart` / `kit.dart`. This report grades the **committed** build; §4.B1 records the post-review working-tree fix separately. My deleted `tool/_eval_scratch.dart` also shows as an untracked deletion.
**Read:** every file in `lib/domain/`, `lib/services/sms/`, `lib/engine/`, `lib/data/`, `lib/state/`; `android/.../RawSmsStore.kt`, `TransactionSmsReceiver.kt`, `CategoryActionReceiver.kt`, `TransactionNotificationHelper.kt`, `MainActivity.kt`, `NativeSmsParser.kt`; `docs/ARCHITECTURE.md`, `docs/eval/rubric.md`, `docs/research/real-data-findings.md`, `docs/research/05-classifier-options.md`; `test/engine_test.dart`, `test/sms_corpus_test.dart`, `test/spam_corpus_test.dart`, `test/widget_smoke_test.dart`, and the fixture definitions for the failing rows.

> **Weighted score: 6.7 / 10** — E1 7.5 · E2 6.5 · E3 7.5 · E4 6.0 · E5 6.0 · E6 6.5.
> (20·7.5 + 20·6.5 + 15·7.5 + 15·6.0 + 15·6.0 + 15·6.5 = 670 / 100.)
> The uncommitted receiver fix for B1, if committed as-is, moves this to **≈7.0**; it was not in the graded commit.

This is a genuinely good parser and a genuinely unfinished product. The parsing/ledger core is close to the 9.5 bar; the mobile data platform around it (receiver ↔ Dart database contract, card identity, review accounting) is not.

---

## 0. Verification log (commands run from the repo root)

| # | Command | Result |
|---|---|---|
| 1 | `flutter analyze` | **26 issues, exit 1**. All 26 in `tool/` (25 × `avoid_print`, 1 × `unnecessary_string_interpolations`); **zero in `lib/` or `test/`**. README §Running says "zero issues expected" (README:71) — false as shipped. |
| 2 | `flutter test` | **213 passed, 2 failed** (`00:24 +213 -2`). `test/sms_corpus_test.dart` prints `OVERALL 107/109 (98.2 %)`; `test/spam_corpus_test.dart` prints `OVERALL 77/77 (100 %)` (tx 19/19, info 13/13, otp 9/9, promo 14/14, fraud 22/22). |
| 3 | Failing fixtures | **F03** (`Credits 6/7`): merchant expected `"ACME TECHNOLOGIES PVT LTD"`, actual `"ACME TECHNOLOGIES"` — the extractor deliberately strips `PVT LTD` (`transaction_extractor.dart:568-571`). **H07** (`Bill payments 9/10`): `kind` expected `spend`, actual `transfer`; `instrument` expected `bankAccount`, actual `creditCard`. If the brief's "one known-failing fixture" is H07, it is failing for a real reason (B3); F03 is a second failure and is a fixture/parser disagreement rather than a lost rupee. Commit `8f0765a` claims "fixture corpus 108/109"; the suite yields 107/109 at HEAD. |
| 4 | `dart run tool/replay_inbox.dart %TEMP%\inbox.json` (2 000 real messages) | `classes: transaction=266, unknown=819, informational=566, phishing=151, promo=198`; `parsed: 266 admitted: 266 duplicates merged: 13 counted: 253`; `spend: 337093 other: 2.9 % of spend`. This is the honest, reproducible proof of the rebuild's headline claim. |
| 5 | `python tool/measure_inbox.py %TEMP%\finance_sms_after.db` | 254 transactions; **0** offer-worded rows; **0** verbless spend rows; **0** P2/P2b duplicate groups. Looks like a pass — but the same DB has `Other` = 51 rows / ₹5,05,799 = **71.7 % of ₹7,05,183 spend** (see B12). |
| 6 | Direct SQLite queries of `%TEMP%\finance_sms_after.db` | `user_version=7`, `journal_mode=delete` (not WAL), 21 `cards` rows (0 with a limit), 40 `needs_review=1`, **0** `duplicate_of`, 0 `merchant_rules`, 126 non-`creditCard` rows carrying `card_key` (₹9,28,011). |
| 7 | One-off Dart harness (temporary, deleted) | Proved the five behaviours in §6: KYC advisory now informational, H07 card-keys the bank account, same-card/same-amount/different-merchant charges merge, `needsReview` counted, stale bill yields `daysToDue=-526`, `dueSoon=true`. |

**Who moved HEAD:** commit `da88e2f` is someone else's fix landing during this review. It also swept my temporary `tool/_eval_scratch.dart` into git (`git diff 8f0765a..HEAD`); I removed both scratch files, so the working tree shows `D tool/_eval_scratch.dart`. Drop that deletion hunk before shipping; nothing in `lib/`, `test/` or `docs/` was touched by me.

**Corpus caveat (measured, not inferred):** `%TEMP%\finance_sms_after.db` is **not a HEAD artifact**. Replaying the same 2 000 messages through HEAD gives 253 counted rows, ₹3,37,093 spend and 2.9 % Other; the supplied DB has 254 rows, ₹7,05,183 spend and 71.7 % Other. `measure_inbox.py` cannot see the difference because it never prints category share. The claimed guarantee is currently supported by the *replay harness*, not by the shipped measurement file.

---

## 1. Criterion table

| # | Criterion | Wt | Score | Evidence (file:line / run) |
|---|---|---|---:|---|
| **E1** | Architecture: one source of truth, no duplicated business logic, clean layering | 20 | **7.5** | The big wins are real: one Dart writer of `transactions` (`sqlite_finance_repository.dart:22-24`), one dedupe engine (`dedupe_engine.dart`) used at ingest *and* at load (`sqlite_finance_repository.dart:65`, `:240`), content-hash identity shared with Kotlin (`hashing.dart:13-33` ↔ `RawSmsStore.kt:104-119`), and a thin ledger gate that delegates (`txn_guards.dart:15-29` → `sms_guards.dart:38-89`). Deductions: the **second parser still exists** (`NativeSmsParser.kt`, 323 lines, its own amount scorer and verb lists) and feeds the notification amount; "money moved" still has five definitions (`sms_guards.dart:82-89`, `sms_classifier.dart:25-35`, `amount_finder.dart:43-48`, `dedupe_engine.dart:36-43`, `NativeSmsParser.kt:14-17`); the category catalogue is duplicated (`category_catalog.dart:7-24` vs `app_database.dart:231-248`); the `isDuplicateOfKey` filter is re-implemented in five consumers (`monthly_summary.dart:140,185`, `card_metrics.dart:180`, `recurring_detector.dart:57`, `insights_engine.dart:104,271,298`); `demo_mode` is written to `app_meta` (`sqlite_finance_repository.dart:398-413`) and never read (state lives in `AppState._demoMode`). |
| **E2** | Money maths: paise integers, transfers vs spend, dedupe, statement cycles | 20 | **6.5** | Integer paise is genuinely enforced (`money.dart:11-27`; no `double` money in any engine; tests at `engine_test.dart:553-579`), transfers are first-class and excluded from spend (`monthly_summary.dart:151-171`), the replay shows 0 spam-as-spend. But money attribution is wrong in the card layer: `cardKey` is set for **any** account mask (`transaction_extractor.dart:284-286`) and `_ensureCard` runs for every `last4` (`sqlite_finance_repository.dart:206-208`), so savings-account debits become cards; issuer falls back to `'Card'`; the `issuer\|last4` key collides a card with an account ending in the same four digits. Supplied DB: 21 cards, 0 limits, 126 non-card rows with `card_key`, `HDFC Bank\|6859` = 95 rows mixing `creditCard` and `bankAccount`. Also: `needsReview` rows are counted (`finance_repository.dart:184-192`; proved 12 340 paise included), stale bills produce negative countdowns (`card_metrics.dart:240-247`; proved `daysToDue=-526`, `dueSoon=true`), and the dedupe engine merges two different merchants on the same card within 3 min (proved; §6.3) then the DB deletes one. |
| **E3** | Testability: pure functions, injected clocks, corpus tests with real pass rates | 15 | **7.5** | Genuinely strong: pure `SummaryCalculator` / `CardMetricsCalculator` / `DedupeEngine` / `RecurringDetector`; `now` injected at repository (`sqlite_finance_repository.dart:28-35`), state (`app_state.dart:18-24`) and every engine; 186 corpus assertions with per-bucket rates printed; an offline replay harness that reproduces HEAD in seconds (`tool/replay_inbox.dart`). Gaps: **no repository/DB test at all** (no sqflite in tests, so `ingest`, `_reconcileDuplicates`, `_applyPendingCategories`, migration and the receiver contract are untested), and one dedupe test asserts a guarantee the code no longer has (`engine_test.dart:462-482` — it passes only because the helper leaves `last4` null; with a real card tail the rows merge, proved). `RecurringSeries.daysUntilNext` calls `DateTime.now()` inside the engine (`recurring_detector.dart:32`). |
| **E4** | Failure handling: permission, platform, empty inbox, partial parse, corrupt row | 15 | **6.0** | Good: `SmsPermissionMissing` mapping and copy (`app_state.dart:194-204`), unsupported-platform copy, empty state, `needsReview`, `UnsupportedError` rethrow. Bad: the **receiver crashes after first launch** on the SQLite version downgrade (B1); a corrupt row aborts the whole dashboard (`sqlite_finance_repository.dart:459-495` casts/NULL and `TxnKind.values.byName` with no per-row quarantine); a classifier-positive row that the extractor rejects is marked `processed=1` and never re-parsed (`sqlite_finance_repository.dart:223-233`); guard-rejected rows are dropped at display with no diagnostic store (`finance_repository.dart:184-192`, no `classifier_diagnostics` anywhere); 819 `unknown` messages have no surface. |
| **E5** | Data safety: migration, no destructive writes, offline, no PII | 15 | **6.0** | Strong: no network dependency (`pubspec.yaml`), no `print` in `lib/` (`grep` → zero), SMS bodies never logged, raw table append-only. Weak: the ledger is **not** append-only — duplicate losers are deleted (`sqlite_finance_repository.dart:274`) while the `duplicate_of` column is never written (0 in DB) and the docs say "never deleted" (ARCHITECTURE:56, README:47); pending categories are purged unconditionally (`:455`); the legacy DB `finance_sms_mvp.db` is abandoned by the filename change (E5 data loss on upgrade; no deletion, so old SMS stay on disk); the advertised WAL mode does not exist (`journal_mode=delete`, DB query; ARCHITECTURE:68). |
| **E6** | Operability: reproducible build, clean analyse, documented trade-offs, realistic roadmap | 15 | **6.5** | Reproducible Flutter/Dart toolchain; `pubspec.lock` committed; unusually good research dossier; replay harness is an operational asset. But `flutter analyze` exits 1 (26 info issues in `tool/`), two tests fail, and several load-bearing docs are false: "one parser" (README:42 vs `NativeSmsParser.kt`), "marked, never deleted" (README:47 vs `sqlite_finance_repository.dart:274`), "different sender" dedupe rule (README:47 vs `dedupe_engine.dart:205-217`), "zero issues" (README:71), "quick classify … already categorised" (README:31 vs B4), "limit from the alert" (README:21 — `_ensureCard` stores `credit_limit: null` and never updates it). The supplied "after" DB is stale (B12). |

---

## 2. Rubric automatic-fail clauses

| Clause | Present? | Assessment |
|---|---|---|
| Duplicated parser/business logic across languages | **Yes (letter of the clause)** | `NativeSmsParser.kt` is a complete second parser (amount scorer, merchant, issuer, direction) and its output is user-visible in the notification. Mitigation: it cannot write `transactions`; the ledger boundary is real. I score E1 7.5 rather than 0, but under the rubric as written this is a fail until the preview is deleted or made a pass-through of a golden-tested Dart contract. |
| `double` money | **No** | Integer paise end-to-end; `parseAmountToPaise` is the only `double` (parse edge, rounded once, `money.dart:95-98`). |
| Test suite passes by asserting nothing | **No** | 186 corpus assertions with meaningful expected fields and printed pass rates; engine maths asserted. One test is misleading (E3) but not vacuous. |
| Unrecoverable migration | **Yes in effect** | The v5 database is orphaned by the name change; the `<6` upgrade branch is unreachable and would throw if reached (indexes created before columns, `occurred_at` never added). See B6. |

---

## 3. The five strongest things

1. **The admission gate is structural, not conventional — and it is measured.** Both the extractor and the display builder require a completed money-moved verb (`transaction_extractor.dart:246-257`, `txn_guards.dart:21-23`), both call the same `SmsGuards` (`sms_guards.dart:38-89`), and the guarantee survives a real 2 000-message inbox: `measure_inbox.py` reports **0** offer-worded rows and **0** verbless spend rows; replay reports 253 counted rows and **2.9 %** Other (down from 71.7 %). This is the thing most SMS trackers get wrong, and it is done right.
2. **One deterministic identity for an SMS payment.** `sms:<fnv1a64(sender|timestamp|trim(body))>` is computed identically in Dart (`hashing.dart:13-33`) and Kotlin (`RawSmsStore.kt:104-119`), uses unsigned 64-bit (so no leading `-` divergence), and is independent of the inbox row id. The receiver and the scan converge on one `transactions` row; replay merges 13 cross-alert duplicates and leaves 0 P2 groups. Excellent design, correctly implemented.
3. **Money is integer paise and the formatting is genuinely Indian.** `Paise` is an extension type over `int` (`money.dart:11`), arithmetic never touches `double`, and `inr`/`inrParts`/`inrCompact` use `en_IN` grouping (`money.dart:32-83`; `engine_test.dart:553-579` covers ₹1,29,900, ₹1,00,00,000, ₹1.3L, ₹1Cr).
4. **The engine layer is pure and the corpus harness is honest.** Every analysis function takes `now`, every corpus failure is printed with field-level expected/actual (`sms_corpus_test.dart:224`), and `tool/replay_inbox.dart` reruns the whole pipeline offline against real data. The 77/77 classifier corpus and 107/109 transaction corpus are real measurements, not assertions of nothing.
5. **The rebuild removed the worst MVP behaviours.** Transfers are a first-class kind (`enums.dart:5-23`; card bills/SIP/wallet loads excluded from spend), the amount scorer is context-scored (`amount_finder.dart:158-244`) rather than first-match, the old duplicate resolver is gone (one engine), and the failed OTP/KYC phishing heuristics were partly reined in — the Airtel RBI KYC advisory from `real-data-findings.md` §C is now `informational` (proved, §6.1), where it used to be fraud.

---

## 4. Every blocker to 9.5

### B1 — The receiver and Flutter disagree about the SQLite version; the receiver crashes after first launch. **Critical.**
`RawSmsStore.kt:101` uses `SQLiteOpenHelper(..., DATABASE_VERSION = 6)` on `finance_sms.db`; `app_database.dart:23` opens the same file at `version: 7`, and sqflite writes `PRAGMA user_version = 7` (confirmed: the supplied DB is `user_version=7`). The next `SMS_RECEIVED` constructs `RawSmsStore` and Android calls the default `SQLiteOpenHelper.onDowngrade`, which throws `SQLiteException("Can't downgrade database from version 7 to 6")`. There is **no** `onDowngrade` override (`RawSmsStore.kt:18-29`) and no try/catch in `onReceive` (`TransactionSmsReceiver.kt:14-46`). Consequence: live capture, the quick-category notification and the receiver all die on the first SMS after the app has been opened once. The architecture's "receiver appends raw SMS" path is unreachable in practice. This is the single highest-severity defect in the build.
**Post-review status (working tree, not in `da88e2f`):** the tree now has `override fun onDowngrade { createTables(db) }` (`RawSmsStore.kt:33`) and `DATABASE_VERSION = 7` (`:112`). That is the correct minimal fix; commit it and add the 6→7 reopen test so it cannot regress. The finding is recorded as reviewed/committed because the graded commit still has the crash.

### B2 — Dedupe hides genuine same-sender double charges and then deletes the evidence. **High.**
The engine now merges same-sender, same-amount debits that share a `last4` even when the merchants differ (`dedupe_engine.dart:205-217`; `if (a.last4 != null && a.last4 == b.last4) return true;` before any merchant/ref check), and `_reconcileDuplicates` **deletes** the loser (`sqlite_finance_repository.dart:274`). Proof (§6.3): `Spent Rs.500 … Card 6859 At SWIGGY` + `Spent Rs.500 … Card 6859 At ZOMATO` 60 s apart → one survivor at the engine. This is the exact "hidden second charge" case ARCHITECTURE §6 promises to preserve ("two alerts from the same sender are treated as two real events"), and it contradicts README:47 ("marked, never deleted"). The `duplicate_of` column exists but is never written (0 non-null in the supplied DB), so the merge is unauditable and a user category on the loser is lost. `da88e2f` widens the same risk by treating `transfer` as an outgoing leg for opposite-leg merging (`dedupe_engine.dart:147-155`), so a transfer debit and an income credit of the same amount within 120 s from the same sender become one row.

### B3 — Card identity and utilisation are wrong on real data. **High.**
`_extractLast4` reads any account mask (`transaction_extractor.dart:407-425`); `extract` sets `cardKey` whenever `last4 != null` regardless of instrument (`:284-286`); and `ingest` calls `_ensureCard` for every row with a `last4` (`sqlite_finance_repository.dart:206-208`), inserting `credit_limit: null` and never learning the limit the SMS prints. In the supplied inbox DB: **21 cards, 0 with a limit**, and **126 non-credit-card rows (₹9,28,011) carry a `card_key`**; `HDFC Bank|6859` aggregates 95 rows across `creditCard` and `bankAccount` (a card and an account ending 6859 collide on `issuer|last4`, `app_database.dart:118`). H07 proves the mechanism: a bank-account debit paying a card bill becomes `instrument=creditCard`, `cardKey=HDFC Bank|4821`. There is no `deleteCard` in `FinanceRepository` (grep), so a phantom card can never be removed. This corrupts the Cards tab, utilisation, bill headroom and the "card pressure" insights — the second-most-visible feature after Home.

### B4 — Quick-categorise from the notification never survives a cold start, and its first action writes the wrong kind. **High.**
`AppState.init` calls `load()` (`app_state.dart:58`) before `_ingestQuietly()` (`:61-63`), and `load()` unconditionally applies **and then deletes every** pending category (`sqlite_finance_repository.dart:430-456`, `:455`). A notification is actionable only while the app is closed, i.e. before the transaction exists; on the next cold start the `UPDATE … WHERE dedupe_key = 'sms:<ref>'` matches 0 rows, the choice is deleted, and the row is later written with the rule category. So README:31 ("the payment is already categorised when you next open the app") is false for the only case in which the feature is used. Even when the row does exist, the notification's first action is labelled `"Food"` (`TransactionNotificationHelper.kt:53`), which is not a catalogue name (`category_catalog.dart:7-24` has `"Food & dining"`), so `categoryKindFor("Food")` returns `other` (`category_catalog.dart:26-27`) and the row displays "Food" but groups under Other.

### B5 — Receiver captures are never ingested on open or resume. **High.**
`ingest()` is called from `scanInbox()` and from `init()` **only when `_data.transactions.isEmpty`** (`app_state.dart:61-63`); `refresh()` (`:72-81`) only loads; there is no `WidgetsBindingObserver`/resume hook anywhere in `lib/` (grep). `sms_messages` rows written by the receiver with `processed=0` are therefore invisible until the user manually pulls to refresh or taps Scan. The notification says "Spent ₹X" but the ledger stays stale. The receiver also inserts `id = "rcv:<hash>"` (`RawSmsStore.kt:70`) while the inbox scan inserts the Telephony `_id` (`MainActivity.kt:202`), so one physical message is stored twice under two ids — the transaction dedupe key saves the money, but `smsRead`, classification work and the raw table are duplicated.

### B6 — The v7 migration story is not executable; the previous database is abandoned. **High (rubric auto-fail class).**
The legacy app used `finance_sms_mvp.db` (verified from `43ae964:android/.../NativeFinanceDatabase.kt`, `DATABASE_VERSION = 5`); the rebuild uses `finance_sms.db`, so the entire v5 history is silently orphaned — no copy, no deletion, no user notice. The `oldVersion < 6` branch (`app_database.dart:174-199`) is dead code for that path and would fail if it ever ran: `_createCore` creates `txn_occurred_idx` and `txn_category_idx` (`:97-105`) **before** the ALTERs that add `occurred_at`/`category_kind`, so SQLite throws "no such column"; `occurred_at`, `amount_paise`, `raw_body`, `vpa`, `card_key`, `last4`, `issuer`, `balance_after`, `available_limit` are never added; and the v7 `UNIQUE` on `dedupe_key` cannot be added by `ALTER TABLE`, so an upgraded table would silently lose the one invariant the ledger relies on. The only migration that executes is 6→7 (Kotlin-only DB → full schema), and B1 shows that contract is itself broken.

### B7 — "To confirm" money is already in the totals, and the queue is truncated. **High.**
`HomeDataBuilder` counts every guard-passing row (`finance_repository.dart:184-192`) with no `needs_review` filter; proved: one 12 340-paise `needsReview` row adds 12 340 to `MonthlySummary.spendPaise` and 1 to `txnCount`. The dashboard then shows "N payments to confirm" (`home_screen.dart:526-534`) and the row is included in spend. The research memo's tiered admission (ASSERTED = visible, not counted) is not implemented, so a low-confidence parse moves the month's total before the user confirms it. Separately, `load()` fetches at most 20 review rows (`sqlite_finance_repository.dart:115-120`) while the supplied DB has 40, so the banner undercounts by half.

### B8 — "One definition of money moved" is still not true, and the preview parser is a second rule set. **Medium-high.**
`SmsGuards.moneyMoved` is the canonical predicate and the extractor/gate use it, but `SmsClassifier` keeps its own `_debitVerb`/`_creditVerb` (`sms_classifier.dart:25-35`), `AmountFinder` has a third verb list (`amount_finder.dart:43-48`), `DedupeEngine` a fourth (`:36-43`), and `NativeSmsParser` a fifth (`:14-17`). The memo's v1 deliverable — one `assertion.dart` imported by classifier, extractor and guards (`05-classifier-options.md:292`) — is not done. The user-visible symptom is the notification amount coming from a parser that need not agree with the ledger: Kotlin defaults direction to `"expense"` whenever no transfer pattern matches (`NativeSmsParser.kt:205`), and its gate admits any message containing "upi"/"wallet"/"card" with an amount, so an offer naming a card and a rupee figure can produce "Spent ₹X" while the ledger (correctly) books nothing.

### B9 — Rejected and unparsed rows are invisible, and a parser fix will not retry them. **Medium-high.**
`TxnGuards.isCountable` drops rows only at display (`finance_repository.dart:184-192`); nothing records the reason and there is no `classifier_diagnostics` table. In `ingest`, a message classified `transaction` whose extractor returns `null` is still marked `processed = 1` (`sqlite_finance_repository.dart:223-233`), so the next parser release will never revisit it; the classification (`transaction=266`) and extraction (`parsed=266`) counts are equal on this inbox only by luck. 819 `unknown` messages (41 %) have no review surface at all. ARCHITECTURE §7 "nothing is silently dropped" is true for the *classifier* and false for the *gate*.

### B10 — Stale bill notices produce a permanent negative "due" warning. **Medium.**
`CardMetricsCalculator` keeps the latest bill regardless of age (`card_metrics.dart:233-237`), rolls a past due date forward at most 12 times (`:240-247`), and then reports `daysToDue` from the un-rolled date. Proved with a January-2024 bill and `now = 2026-06-15`: `totalDue=₹5,000`, `dueDate=2025-01-05`, `daysToDue=-526`, `dueSoon=true`, `hasBill=true`. `dueSoon` (`:137`) has no lower bound, so a two-year-old statement keeps raising a "Bill due" warning forever. Any bill older than 12 months is affected.

### B11 — The sender registry still misses the codes the real inbox identified. **Medium.**
`real-data-findings.md` §D2 lists `CBSSBI` (30 transactions), `WOCAMC`, `IPRUMF`, `BNDNMF`, `SBIPSG`, `KFINMF`, `MOAMCL`, `ETCLUB`, `JIOPAY`, `GOVTAP` as absent; the rebuild added the 7 DLT **prefixes** (`sender_registry.dart:121-130`) but **10 of the 17 entity codes remain missing** (I checked each against `entities`, 72 codes). `CBSSBI` therefore resolves `plausible`, not `known`; `entity` is null; and null `entity` is exactly what makes `_ensureCard` fall back to `'Card'` (B3) and what costs the classifier 2 points on genuine SBI alerts. The research memo's day-1 "DLT registry refresh" (`05-classifier-options.md:294`) is half-done.

### B12 — The "after" measurement file is not reproducible from HEAD, and the tool cannot tell. **Medium-high.**
Same 2 000 messages: HEAD replay → 253 counted, ₹3,37,093 spend, 2.9 % Other; `%TEMP%\finance_sms_after.db` → 254 rows, ₹7,05,183 spend, 71.7 % Other (51 rows). The file's `user_version` is 7 and it has the new columns, so it is an intermediate rebuild artifact, not a pre-rebuild one — but it is named "after" and is the artifact the reviewer is told to measure. `measure_inbox.py` prints P1/P1b/P2 but not category share, so it passes a ledger whose categoriser no longer matches the code. The commit message's "Other category 71.7 % -> 2.9 %" is true of HEAD and false of the supplied proof.

### B13 — Doc/claim drift that will burn the next engineer. **Medium.**
ARCHITECTURE:36 "Kotlin keeps a *preview* parse … it never writes financial data" (it writes `pending_categories`, a user financial decision); :56 "different sender" merge rule (code allows same sender); :68 "WAL journal mode" (`journal_mode=delete` in the real DB, and the `app_database.dart:27-31` comment repeats the false belief); README:71 "zero issues"; README:21 "limit from the alert" (never persisted); README:42 "one parser"; README:47 "marked, never deleted"; commit `8f0765a` "108/109" (actual 107/109). `flutter analyze` exit 1 will also fail any CI gate that treats info-level lints as failures. README:43 says the registry "maps ~90 bank/wallet codes"; `entities` actually contains **72**.

### B14 — Phishing volume is unchanged/greater and precision is unmeasured. **Medium.**
151 of 2 000 messages (7.6 %) are still classified `phishing`; the pre-rebuild measurement was 141 (7.05 %). The memo's target is ≤1 false warning per 1 000 (`real-data-findings.md` §E, `05-classifier-options.md:351`). The §C fix is partial: the KYC advisory is fixed, but `_phishCta` is still an ungated second regex containing `share otp` (`sms_classifier.dart:157`, used at `:353`) and `phish >= 4` can still be reached by `_kycLure` alone with no intent predicate (`:335-339`, `:394-395`). With no labelled precision set, "better to miss a scam than to cry wolf" is a hope, not a measurement.

---

## 5. Three changes with the best score-per-hour

### 1. Make the SQLite version contract single-sourced and the receiver crash-proof (≈1–2 h; E4 +1.0, E5 +0.3)
- Define the schema version once (Dart constant exported through a method channel is overkill; a comment + a test asserting both literals is enough) and set `RawSmsStore` to version 7.
- Add `onDowngrade { createTables(db); }` (or explicitly close and let Dart own the file) and wrap `insertSms`/notification in try/catch so a bad DB never kills the broadcast.
- Add the missing DB test: open a Kotlin-shaped v6 file, open it through `AppDatabase`, reopen it through a v6 `SQLiteOpenHelper` — this catches B1 forever.
**Why first:** it is the only defect that makes the app's advertised real-time path *crash*, and the fix is tiny and testable without a device.

### 2. Stop fabricating cards; learn the limit; allow deletion (≈4 h; E2 +1.5, E6 +0.2)
- Only set `cardKey` when `instrument == creditCard` **or** a bill/limit notice proves a card (`transaction_extractor.dart:284-286`), and make `_ensureCard` conditional on a card instrument (`sqlite_finance_repository.dart:206-208`).
- When an alert prints `Avl Limit`/`Total limit`, update `cards.credit_limit` (only if the user has not set one) — this is the "limit from the alert" the README already promises.
- Add `deleteCard` to `FinanceRepository` and a "remove card" action (a phantom card is currently unremovable).
- Migrate: delete `cards` rows with no credit-card transaction and no user-set limit, or mark them inactive.
**Why second:** it converts the Cards tab from 21 fake entries with `unknown` utilisation into 3 real cards, and it removes the account/card tail collision that silently mixes ₹9.28 L of bank debits into card maths.

### 3. Make ingestion event-driven and quick-categorise durable (≈3–4 h; E1 +0.5, E4 +0.8)
- In `AppState`, call `ingest()` on every cold start and on `AppLifecycleState.resumed` when `SELECT COUNT(*) FROM sms_messages WHERE processed = 0` > 0 (cheap query; or always, since replay is fast).
- Move `_applyPendingCategories` **after** the ingest in `load()`, and delete only the rows whose `UPDATE` reported > 0 changes; match by `dedupe_key` as now.
- Map notification labels to catalogue names ("Food & dining", not "Food") or read them from a single shared constant.
- Add one repository test with a fake store that covers receive → ingest → category applied.
**Why third:** it makes the two "real-time" promises in the README true and removes the silent loss of a user action; it is also the prerequisite for any lifecycle/notification work later.

**Next three (after these):** persist dedupe losers as `duplicate_of` and require a non-amount discriminator before a same-sender merge (B2); add a `classifier_diagnostics` table + surface `unknown` (B9); age out bills and guard `dueSoon` with `daysToDue >= 0` (B10).

---

## 6. Proved defects (input → observed → expected)

All from a temporary `dart run` harness against HEAD `da88e2f` (deleted after use; the inputs are literal SMS bodies, so each is reproducible in one test).

| # | Input | Observed | Expected | File:line |
|---|---|---|---|---|
| 6.1 | `AD-AIRBNK-S`, "As per RBI guidelines,your A/c has been blocked due to KYC overdue. Update: https://i.airtel.in/AIRBNK/kyc" | `informational`, signals `kyc_notice(-4), kyc_lure(-4), bank_link(-1)` | not fraud (fixed vs the old build) | `sms_classifier.dart:335-339` |
| 6.2 | `VK-HDFCBK`, H07 (`Rs.5,000 … A/c **4821 … BILLDESK (HDFC Bank Credit Card bill)`) | `kind=transfer`, `instrument=creditCard`, `last4=4821`, `cardKey=HDFC Bank\|4821` | bank-account debit; no card key | `transaction_extractor.dart:284-286`, `:374` |
| 6.3 | Two `Spent Rs.500 … Card 6859 At SWIGGY` / `… At ZOMATO`, 60 s apart | one survivor; ZOMATO marked duplicate in memory | two real charges; both survive | `dedupe_engine.dart:205-217` |
| 6.4 | Plain `Rs.250 debited from your HDFC Bank A/c XX1234 … to SWIGGY` | `instrument=bankAccount`, `cardKey=HDFC Bank\|1234` | no card key for a bank account | `transaction_extractor.dart:284-286` |
| 6.5 | `needsReview: true` spend of 12 340 paise | month spend = 12 340, txnCount = 1 | not counted until confirmed | `finance_repository.dart:184-192` |
| 6.6 | ₹5,000 bill with `dueDate = 2024-01-05`, `now = 2026-06-15` | `daysToDue=-526`, `dueSoon=true`, `hasBill=true` | stale bill ignored or clamped to ≥0 | `card_metrics.dart:137`, `:233-247` |
| 6.7 | `RawSmsStore` v6 vs `AppDatabase` v7 on `finance_sms.db`; supplied DB `user_version=7` | Android default `onDowngrade` throws on the next receive | one version contract | `RawSmsStore.kt:101` (`da88e2f`), `app_database.dart:23` |
| 6.8 | DB query of the supplied "after" DB | 21 cards / 0 limits / 126 non-card rows with `card_key` / `duplicate_of=0` / `needs_review=40` (UI caps at 20) | 3 cards; losers marked; all 40 in the queue and unconfirmed rows not counted | `sqlite_finance_repository.dart:115-120`, `:206-208`, `:274` |

---

## 7. What would move the weighted score fastest

| Fix | E1 | E2 | E3 | E4 | E5 | E6 | Weighted gain |
|---|---|---|---|---|---|---|---|
| B1 version contract + test | +0.2 | 0 | +0.2 | +1.0 | +0.3 | +0.2 | **+0.26** |
| B3 card identity + limit + delete | 0 | +1.5 | 0 | 0 | +0.2 | +0.2 | **+0.36** |
| B4/B5 ingest + pending durability | +0.5 | 0 | +0.2 | +0.8 | +0.2 | 0 | **+0.28** |
| B2 mark losers + merge discriminator | 0 | +0.7 | 0 | +0.2 | +0.5 | 0 | **+0.25** |
| B7 needsReview accounting | 0 | +0.6 | 0 | +0.2 | 0 | +0.2 | **+0.18** |
| B12 regenerate artifact + tool category share | 0 | 0 | +0.3 | 0 | 0 | +0.7 | **+0.15** |

Doing B1–B5 and B7 puts E2 around 8.5, E4 around 7.8 and E5 around 6.7 — roughly **8.0** overall. The remaining 1.5 to the 9.5 bar is mostly the hard product work (precision-labelled phishing, tiered admission, receiver/scan single id namespace, unify the five money-moved definitions, and an actual card deletion/migration story), which is why I would not call this shippable above ~7 today.

# Hisaab (formerly Finance SMS) — working notes

Android-only, offline spend tracker for India: reads the bank/UPI/card SMS already
on the phone, parses them on-device, and computes spend, card utilisation, insights
and fraud warnings. No backend, no account, no network at runtime.

This file is the **record of what was asked and what is done**. Update it every
iteration. Working branch: `main` (single-developer repo).

## Owner requirements (log of every request — keep this current)

| # | Request (owner's words, condensed) | Status |
|---|---|---|
| 1 | Clone `amartyaay/finnance-app` into `E:\flutter_projects`, run `pub get`/`analyze`, understand the code. | Done. Repo did not compile on Flutter 3.41.9 (Dart 3.12 private-named-parameters); patched, analyzed, documented in `docs/ARCHITECTURE.md`. |
| 2 | Create evaluator subagents (frontend dev, principal engineer, India finance expert, end user) and build a finance app rated **>9.5 by all**. | Round 1 done: **5.3 / 6.2 / 6.4 / 6.7**. Iterating; rubric in `docs/eval/rubric.md`. |
| 3 | Research spam identification, credit-card payments, credit usage; "proper financial identification of SMS". | Four research docs: `docs/research/01-sms-corpus.md` (103 fixtures), `02-spam-and-phishing.md` (77), `03-credit-semantics.md`, `04-ux-spec.md`. |
| 4 | **P1: never count spam as spend** (e.g. "loan available for ₹36,000"). | Done on real inbox: **0** offer-worded rows, **0** rows without a money-moved verb. Enforced by `SmsGuards.moneyMoved` + `TxnGuards` at the ledger. |
| 5 | **P2: never double count.** | Done on real inbox: **0** duplicate groups. Dedupe runs at ingest, reconciles the DB, and collapses opposite-direction legs. |
| 6 | "We need a strong data parser or a small in-house classification model — do research." | Researched (`docs/research/05-classifier-options.md`): **no model in v1**; admission gate + arithmetic confirmation beats a classifier; LR later, needs 2–3 days of labelling. |
| 7 | On-device LLM: "not at SMS-receive time is also ok; user can trigger it." | Researched (`docs/research/06-on-device-llm.md`): **S24 FE has no AICore/Gemini Nano, no S24 variant does**. Recommended manual "copy as prompt → paste answer" round trip; bundled 270M model needs `minSdk` 30 + labels. Not built yet. |
| 8 | Focus on **mobile/Android only, ignore web**. | Done: web/desktop unsupported; `README` states it; verification moved to `tool/device_shots.ps1` (device captures). |
| 9 | **Screen listing all SMS with manual categorisation**, remembered and applied to previous transactions; **optional**, never compulsory. | Done and reachable: Settings › Data › "All messages", plus the dismissible review banner. "Every payment from X" rewrites history and stores a rule; Settings › Learned categories has undo. |
| 10 | "Work on UI/UX, make it fancy, modern and good looking, along with backend/data." | Redesign landed and device-verified (`9c55679`), then wired to the real data (`abd2f3f`): true hero, inbox door, learned-rules list. Round-2 end-user score 5.3 → **6.8**. |
| 11 | "Keep updating the goal file and keep doing git commits." | This file, updated every round; every iteration is committed. |
| 12 | Session 3 focus: **spam identification**; "very very accurate" on SMS that show expenses. | Done and measured on **5 274 hand-labelled real messages** (3 274 originally held out — **but parser fixes were later made against its errors, so it is no longer a clean test set**; a fresh set from Feb–Sep 2025 is a todo): P1 **0**, P2 **1**, card bills on both legs **0**, spend recall **98.7 %** / precision **96.5 %** (held-out), phishing false alarms 172 → **1**, promos kept out **100 %**. |
| 13 | **Screen to upload an SBI bank statement with a password field**; find salary; per salary-to-salary cycle, categorise expenses. | Done (`67ca87c`): Settings › Salary & statements and a Home hero link. pdfrx/PDFium on-device, password used once; 4 SBI layouts; every row balance-checked; salary by recurrence or keyword + overrides; cycle screens. Not yet tried on a real SBI file (needs the owner's PDF + password). |
| 14 | Classifier: "super accurate", budget **≤ $2–3 / year**, cheapest best, on-device (S24 FE) preferred; network allowed only for classification. | Decided (`docs/research/08-classifier-budget.md`): **$0/year** on-device logistic regression as a second opinion over the rules; disagreements go to review. Paid APIs end up ~$5/yr (prepaid minimums); Gemini free tier trains on inputs; Gemini Nano absent on S24 FE. Model not trained yet. |
| 15 | **A subagent whose whole job is checking accuracy**: classification accuracy, spam counted, double counts. | `tool/audit_accuracy.dart` (gold set, P1/P2/card-bill legs/recall/precision/kind/amount/phishing) + an auditor agent each round. |
| 16 | No Google sign-in, no account, no network (except optional classification). | Holds: no INTERNET use at runtime. |
| 17 | "Improve UI, make it modern and fancy." | Visual pass `338a543`: bundled Inter, mesh-gradient heroes (`HeroSurface`), soft-shadow cards, floating frosted dock, frosted hero tiles, column charts, per-category hues, calm notice cards. Verified by host renders (`docs/shots/render-*.png`); not yet on the phone. |
| 18 | "UI still bad and cluttered, colour scheme bad; make it fancy, use any Flutter package." Earlier: rename the app and make a logo. | Renamed **Hisaab** with a generated logo (`tool/make_logo.py`). Owner picked concept **C · Aurora Glass** (`docs/shots/concept-c-aurora.png`, `test_visual/concepts_test.dart`). Applied app-wide: always-dark aurora backdrop, glass surfaces, teal→blue→violet gradient numbers, Phosphor icons, fl_chart daily bars. Home cut to hero → one "things need you" row → where it went → recent; details behind an ⓘ sheet. Theme picker removed. |
| 19 | "The SBI statement thing is not working; I can only see one month — let me see previous months over time." | Home steps through months (arrows, or tap the month for a month-by-month list), shared with Activity. Statement import fails loudly, accepts glued units and two-line headers, and shows a copyable layout report. **Root cause on the owner's file** (`AccountStatement_…pdf`, 2026 OnlineSBI): the column labels are vector art, only "Balance" is text, and narration is centred on the dated line. Now columns are measured from the rows (`_inferModel`), the line above a date joins its row, the branch name under each row is dropped, `01-04-2026` periods and `Mr. NAME` holders parse, and spaced NEFT (`NEFT * IFSC * UTR NAME`) yields the payer. Owner's file: **623 rows, 622 balance-verified** (the first has no opening balance), salary DELOITTE found in 6 months. |
| 20 | "The bank statement should be the record: show SMS transactions only where no statement covers the period, like the current month." | `StatementMerge`: for each imported account and the days its statements cover, that account's SMS (UPI, CBS, and its debit card) give way to the statement rows; other banks, credit cards and uncovered days stay SMS. Dedupe decisions carry over (a card bill's bank leg stays a duplicate of the issuer's confirmation; a lone card-bill row pairs with it; a merchant receipt folds in), user categories carry over, salary verdict books salary. Measured on the real inbox + statement: 95 SMS replaced, 623 statement rows in, **2** same-amount cross-source pairs left, both genuinely separate payments. Also fixed: SBI `A/C XXXXX454642` gave tail `5464` (now `4642`); parser version 11. |
| 21 | "SBI statement is the single source of truth — remove all banks. Credit-card payments in the statement: use the card SMS to break them down by category." | On covered days **every** bank-account SMS (any bank, UPI, debit card, receipts) gives way to the statement; credit cards, card-payment confirmations and wallets stay. A statement debit with the exact amount of a card's "payment received" (±3 days) becomes that card bill, whatever its narration (`trf to PhonePe`): 11 such payments on the owner's file. Tapping a card bill shows **What this paid for**: the card's purchases since the previous payment, by category (`CardBillBreakdown`). UPI to `Bank Acc/<IFSC>` is a self transfer. |
| 22 | "I send ₹24–25k to my HDFC account for investment; HDFC SMS show ₹3k deducted ~8 times a month (all investments); a bigger top-up or a non-₹3k HDFC deduction is most likely my HDFC card bill. After salary I book SBI fixed deposits and break them mid-month for expenses." | Other-bank account SMS on covered days are no longer dropped: debits that are mandates/SIPs (UMRN, mutual fund, debit mandate, NIPPON…) are investments; any other debit is that bank's card bill (named after the bank's only credit card, paired with its "payment received"); credits and receipts are dropped. SBI top-ups to `Bank Acc/HDFC` are investment in the salary cycle, a transfer in the ledger. SBI FD bookings (`FIRDFTFR`), RD instalments (`DIRECT DR 0…`) and closures (`DEP TFR 0… OF <holder>`) are investment / redemption, never spend or income. Stored statement rows are re-classified on read, so rules apply without re-import. Card-bill breakdown now uses the card's statement SMS (purchases on the statement the payment settles). Also fixed: every bottom sheet sat under the gesture bar (Import was untappable); category chips rendered one per row. |

## Decisions to keep (with evidence)

- **One parser, in Dart.** The Kotlin receiver only appends raw SMS to `sms_messages`; Dart classifies, extracts and writes `transactions`. The original repo had two parsers on one database and they had already drifted.
- **Money is integer paise** (`Paise` extension type). Never `double`.
- **Transfers are a first-class kind**: card-bill payments, self-transfers, wallet loads, SIPs and EMIs are `transfer`; ATM cash is `cash`. They never inflate spend.
- **Admission before counting**: a row needs a money-moved verb (`SmsGuards.moneyMoved`) or an explicit balance/limit delta. Offers, eligibility, sanctioned limits and cashback *estimates* can never post. This is what stops "loan of ₹36,000 available for you".
- **One dedupe engine** (`DedupeEngine`), applied at ingest and reconciled in the DB. Same sender + same amount + **opposite direction** within 120 s collapses to one `transfer`; TD-closure legs merge; same-sender merges need merchant agreement (a real double charge must survive).
- **Content-hash identity**: `sms:<fnv1a64(sender|timestamp|body)>`, bit-identical in Dart (BigInt) and Kotlin (ULong). Signed 64-bit was a real bug — half of all hashes came out with a leading `-`.
- **`1 << 62` and `0x7FFFFFFFFFFFFFFF` are unsafe**: unter dart2js the first is 0 and the second is unrepresentable. Use `0x1FFFFFFFFFFFFF` (2^53−1) with `.toInt()` if a clamp needs a bound.
- **Android only.** Web/desktop are unsupported: no SMS inbox, and browser integer semantics differ from the device's.

## Evaluator score history (target ≥ 9.5 by all four)

| Round | Commit | Frontend | Principal | Finance | End user | Main gaps called out |
|---|---|---:|---:|---:|---:|---|
| 1 | `da88e2f` | 6.4 | 6.7 | 6.2 | 5.3 | Money-in fictional (card payments/refunds/TD booked as income, SIPs as spend); `card_bills` always empty; savings accounts as cards; dedupe merges SWIGGY+ZOMATO and deletes a payment; a11y contrast 3.78:1; cards tab 0 % (dart2js clamp); no learning from corrections |
| 2 | `c87e42b` | **7.1** | **7.4** | **7.2** | **6.8** | **Card-bill double count: 6 HDFC payment pairs = ₹44,497.59 counted twice** (180 s window can't see a 1–2 day gap); "out" undefined across tabs (Home ₹33k vs Activity ₹20,313); Activity says "+₹3,939 in" while Home says no income; card intelligence is model-only (no basis labels, Axis 0 % vs ring 6 %, derived limit unlabelled and frozen); 8 of 18 SIP confirmations (~₹24,000) and 3 UPI Lite top-ups (₹7,534) dropped; a two-leg transfer booked as ₹5,000 spend; both remaining fraud flags are genuine Airtel KYC notices; 360 dp overflow in Insights (auto-fail) |'

| 3 | `587b1c4` | **7.9** | **7.7** | **7.6** | **7.1** | Corporate Amex counted as personal spend; JK-REGINF-G false phishing flag; salary misses job changes and parents' UPI; "held-out" set contaminated by tuning; UI cluttered (→ Aurora rebuild) |

Round-1 evidence: `docs/eval/round-1/`; round-2: `docs/eval/round-2/`; round-3: `docs/eval/round-3/`.

## Session progress (measured, not claimed)

| Metric | Start | Round 1 | Now |
|---|---:|---:|---:|
| Evaluator scores | — | 5.3 / 6.2 / 6.4 / 6.7 | **6.8 / 7.1 / 7.2 / 7.4** (mean 7.1) |
| Fixture corpus | 43.1 % (broken build) | 99.1 % / 100 % | **109/109** transactions, 100 % classification (the corpus has 109 checks; an earlier note said 111 — wrong) |
| `flutter test` | 29 (old MVP) | 214 / 1 | **342/342** |
| "Other" share of spend | 71.7 % | 2.9 % | **0.7 %** |
| Spam counted · verbless · duplicate groups | 1 · 4 · 3 | 0 · 0 · 0 | **0 · 0 · 0** |
| Cards in the ledger | 21 phantom | — | **4 real** (Amex, Axis, HDFC, Pluxee) |
| Fraud flags per 2 000 messages | 151 (0/14 true) | — | **2**, zero OTP false positives |
| Bill notices stored | 0 | — | **6** with due dates |


## Gold-set accuracy (hand-labelled real inbox, `tool/audit_accuracy.dart`)

Labels in `.local/gold/` (gitignored); guide and rulings in `docs/eval/gold-labelling.md`.
Run: `dart run tool/audit_accuracy.dart .local/inbox_full.json .local/gold_heldout` (held-out) or `.local/gold` (all).

| Metric | Session start (2 000) | Held-out 3 274 | All 5 274 |
|---|---:|---:|---:|
| Non-money rows counted (P1) | 3 | **0** | **0** |
| Movements counted twice (P2) | 18 | 1 | 1 |
| Card bills counted on both legs | — | 0 | **0** |
| Spend recall | 81.5 % | **98.7 %** | 98.9 % |
| Spend precision | 99.2 % | 96.5 % | 97.2 % |
| Phishing false alarms | 2 (172 on older mail) | **1** | 1 |
| Money / no-money agreement | — | 99.2 % | 99.1 % |

Remaining error is mostly UPI to a person's name with no honorific counted as spend (≈ +4 % spend).

## Real-inbox measurements (2 000 messages, Galaxy S24)

Tracked with `tool/replay_inbox.dart` (offline, re-parses raw messages with current code — the source of truth) and `tool/measure_inbox.py` (checks a pulled DB).

| Metric | Start of session | Now |
|---|---:|---:|
| "Other" share of spend | 71.7 % | **0.7 %** |
| Spam/offer rows counted | 1 | **0** |
| Spend rows with no money verb | 4 | **0** |
| Duplicate groups (10 min) | 3 | **0** |
| Counted rows | 275 | 269 |

Fixture corpus: **109/109 transactions**, **77/77 classification** (both corrected fixtures now assert the research-backed treatment).

## Open todos (priority order)

- [ ] Build a fresh, never-tuned test set from Feb–Sep 2025 messages; re-quote held-out numbers only from it.
- [ ] Corporate Amex card spend counted as personal spend (round 3, finance).
- [ ] JK-REGINF-G false phishing flag.
- [ ] Salary detection: job change (new employer name) and recurring parent UPI credits mistaken for salary.
- [ ] Round-4 evaluation of the Aurora UI on the device.

- [ ] **One "out" figure** shared by Home, Activity and Cards; reconcile Cards' "Total due" (sum of statements) with Home's "Bill due" (unpaid).
- [ ] **A coherent money-in answer**: group refunds / transfers / salary with labels, make the "transfers not counted" line tappable, and explain "no income found" next to "+₹3,939 in" in one sentence.
- [ ] **Insight tiles must act**: wire `Insight.action` to Activity/Cards/recurring, add dismiss via `AppState.dismissInsight` (currently dead code).
- [ ] **Review banner → the queue**: open `SmsInboxScreen` on the unreviewed filter, not all 2 000.
- [ ] **Period labels**: Insights shows all-time counts under an October heading; hero "3 % vs last month" and Insights' projection must be labelled as actual vs projected.
- [ ] **Duplicate per-day figure** in the hero (₹812.52 a day and Spend/day ₹813).
- [ ] **Android notification**: group amounts (₹105590 → ₹1,05,590), an "Other" action that opens the message, one notification per batch, and a permission prompt with copy instead of silent.
- [ ] Salary from SMS: only 2 real salary SMS (₹76,113) in 5 274 messages; feed the statement's salary verdict (or a marked SMS credit) into Home's `Left`.
- [ ] Train the $0 on-device LR second opinion on the gold set (time split) and wire disagreements into review.
- [ ] Try the statement import on the owner's real SBI PDF; record which layout it is.
- [ ] Reconcile statement rows with SMS rows (UPI RRN join) to measure SMS coverage of the SBI account.
- [ ] Delete the legacy `savingsRate` getter; `savingsRateOrNull` is the truth.
- [ ] Schema drift: `schemaVersion` 9 vs v9 block (harmless today, a trap later).
- [ ] Device migration test for v7→v8 (FFI native-assets build hung; proven only by a contract test).
- [ ] Refund line unexercised (no refunds in the window) — needs a fixture-level test.
- [ ] On-device AI "copy as prompt → paste answer" round trip (`docs/research/06-on-device-llm.md`), only once money-in is fully honest.

## Commands

```powershell
flutter analyze lib                          # must be zero issues
flutter test                                 # 342/342
flutter test test_visual/render_screens_test.dart  # host renders -> docs/shots/render-*.png
$env:JAVA_HOME = "C:\Users\amart\.jdks\jbr-17.0.12"
flutter build apk --debug                    # the only supported build
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s RZCY10WA89M install -r build\app\outputs\flutter-apk\app-debug.apk

powershell -File tool/device_shots.ps1       # four tabs + settings -> docs/shots/device-*.png
flutter test test_visual/render_screens_test.dart  # every screen, real fonts, light+dark -> docs/shots/render-*.png (no phone needed)
python tool/export_inbox.py <db> inbox.json  # raw messages out of a pulled DB
dart run tool/replay_inbox.dart inbox.json   # re-parse offline, print the metrics
python tool/measure_inbox.py <db>            # P1/P2 checks against a stored DB
```

Pull a DB for measurement with `cmd /c "adb exec-out run-as com.amartyaay.finnance_app cat databases/finance_sms.db > out.db"` — PowerShell `>` corrupts binary.

## Architecture

- `lib/domain/` — money (paise), enums, `Txn`, `SmsMessage`, hashing, category catalogue, merchant signature/rule, inbox models. Pure, no I/O.
- `lib/services/sms/` — `sender_registry` (DLT headers, entity table, merchant senders), `sms_classifier` (weighted signals → class), `amount_finder` (context-scored amounts), `transaction_extractor` (direction, merchant, card, bill notices), `sms_guards` (shared predicates: moneyMoved, notMovedYet, merchantReceipt).
- `lib/engine/` — `monthly_summary`, `card_metrics`, `dedupe_engine`, `recurring_detector`, `insights_engine`, `txn_guards` (ledger admission), `merchant_learning`, `review_queue`. Pure and unit-tested.
- `lib/data/` — `app_database` (schema, self-healing on open), `sqlite_finance_repository` (ingest, reparse, cards, rules), `demo_repository` + `demo_data` (4 months of generated data), `finance_repository` (`HomeData` composition).
- `lib/state/app_state.dart` — one `ChangeNotifier` the UI talks to.
- `lib/app/` — design tokens, theme, widget kit. `lib/views/` — home, activity, cards, insights, settings, onboarding, sms inbox.
- `android/.../RawSmsStore.kt` — the only Kotlin writer: raw SMS + a pending-notification-category queue. `TransactionSmsReceiver` posts a quick-classify notification.

## Conventions

- **Never loosen a test to make it pass.** The corpus encodes real bank templates; a failing fixture is either a parser bug or a wrong fixture (H07), and both get documented.
- **Measure before claiming.** Every parser claim runs through `tool/replay_inbox.dart` on the real inbox; a stale DB is not evidence.
- Money: `inr()`/`inrCompact()` only, never string concatenation.
- Colour: `T` tokens only, no raw hex; status colour always travels with a word.
- 360 dp width at 1.3× text must not overflow; 48 dp targets.
- PowerShell: edit Unicode files with the Edit tool or .NET UTF-8 I/O, never `Get-Content | Set-Content`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

# Finance SMS — working notes

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
| 9 | **Screen listing all SMS with manual categorisation**, remembered and applied to previous transactions; **optional**, never compulsory. | Built: `SmsInboxScreen` + `InboxStore` (retroactive "every payment from X", "just this", "not a transaction", "this is a transaction"). **Entry point not yet wired** (no button). |
| 10 | "Work on UI/UX, make it fancy, modern and good looking, along with backend/data." | Redesign landed and device-verified (`9c55679`): gradient hero + money typography, pace chart, category donut, card faces, neutral insights, day-grouped activity, designed dark mode, haptics, 48 dp actions. |

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

Reports: `docs/eval/round-1/{frontend,principal,finance,end-user}.md`.

## Real-inbox measurements (2 000 messages, Galaxy S24)

Tracked with `tool/replay_inbox.dart` (offline, re-parses raw messages with current code — the source of truth) and `tool/measure_inbox.py` (checks a pulled DB).

| Metric | Start of session | Now |
|---|---:|---:|
| "Other" share of spend | 71.7 % | **0.7 %** |
| Spam/offer rows counted | 1 | **0** |
| Spend rows with no money verb | 4 | **0** |
| Duplicate groups (10 min) | 3 | **0** |
| Counted rows | 275 | 269 |

Fixture corpus: **108/109 transactions** (H07 is a documented bad fixture), **77/77 classification**.

## Open todos (priority order)

- [ ] **Wire the doors**: `SmsInboxScreen` route, Settings "undo learned rule" list, review badge on Home (`HomeData.needsReviewCount` is exposed but unused).
- [ ] **Money-in taxonomy**: salary / refund / cardPayment / selfTransfer / redemption / cashback / walletLoad. `Came in` and the savings rate must count only real income. Home currently prints "Came in ₹0" when the inbox has no salary.
- [ ] **Bill notices from informational SMS**: `billNotice()` only runs for transactions, so `card_bills` is empty and a due bill can never show. Expose reported / live / projected utilisation with a basis label.
- [ ] **Card identity**: gate `cardKey`/`_ensureCard` on credit-card instruments (savings accounts currently become cards: 21 cards, 0 limits, 126 non-card rows). Add `deleteCard`.
- [ ] **Dedupe regression**: same-sender + same-amount + same-card to *different merchants* merges and deletes the loser (SWIGGY ₹500 + ZOMATO ₹500, 60 s). Require merchant agreement.
- [ ] **Fraud precision**: 151 flags / 2 000 messages, 0/14 sampled true; 37 HDFC OTPs flagged. Demote link+CTA to promo; `_kycLure` must not match "complete your"; require a real credential ask.
- [ ] **Reparse on upgrade**: DB holds stale rows (₹7.05 L vs ₹3.37 L from current code). `reparseAll()` keyed on `parser_version`.
- [ ] **Copy**: "bill due in 1 days" / "in 0 days"; "Came in ₹0" when no income messages exist.
- [ ] **Schema drift**: `schemaVersion` is 9 with no v9 migration block (harmless today, a trap later).
- [ ] **Device migration test** for v7→v8 (FFI native-assets build hung; proven only by a recording-database contract test).
- [ ] Two outlier days flatten the Home pace chart on real data — bucket weekly, or use a log scale.
- [ ] Onboarding screen not captured on device (needs clearing the owner's data).
- [ ] On-device AI "copy as prompt → paste answer" round trip (`docs/research/06-on-device-llm.md`), only after the money-in taxonomy is honest.

## Commands

```powershell
flutter analyze lib                          # must be zero issues
flutter test                                 # 238 pass / 2 known parser failures
$env:JAVA_HOME = "C:\Users\amart\.jdks\jbr-17.0.12"
flutter build apk --debug                    # the only supported build
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s RZCY10WA89M install -r build\app\outputs\flutter-apk\app-debug.apk

powershell -File tool/device_shots.ps1       # four tabs + settings -> docs/shots/device-*.png
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

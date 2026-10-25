# Architecture & decisions

This supersedes the notes written when the repo was first cloned. That version described the original MVP; almost nothing of it survives.

## Shape

```
SMS inbox (Telephony API)  ──┐
                             ├──► sms_messages (raw, append-only)
SMS_RECEIVED receiver ───────┘
                                      │
                                      ▼
                        SmsClassifier (weighted signals)
                                      │
              ┌───────────────────────┼────────────────────────┐
              ▼                       ▼                        ▼
        transaction             informational / promo      phishing
              │                                                │
              ▼                                                ▼
   TransactionExtractor ──► Categorizer ──► transactions    quarantine (SMS kept, never counted)
                                      │
                                      ▼
                          engines: summary, cards, dedupe,
                          recurring, insights (pure Dart)
                                      │
                                      ▼
                        AppState (ChangeNotifier) ──► views
```

## Decisions worth defending

### 1. One parser, in Dart

The original code had a Kotlin parser (`NativeSmsParser`) and a Dart parser implementing the same rules, plus two copies of the schema and dedupe logic writing to one SQLite file. They had already drifted (different confidence weights, different debit-verb lists, one sent `-` prefixed hex ids).

Now the receiver's only job is to append the raw message to `sms_messages`. Dart classifies, extracts, categorises and writes `transactions`. Trade-off: a notification cannot wait for the Flutter engine, so Kotlin keeps a *preview* parse used only for the notification text — it never writes financial data.

### 2. Content-hash identity

An SMS transaction's dedupe key is `sms:<fnv1a64(sender|timestamp|body)>`, identical on both sides (Dart `BigInt` FNV-1a; Kotlin `ULong` FNV-1a). The inbox row id is *not* used for identity, because the receiver and the inbox scan see different ids for the same message. Signed 64-bit arithmetic was a real bug in the original: half of all hashes came out with a leading `-`, so the two paths never matched.

### 3. Transfers are a first-class kind, not negative spends

`TxnKind` is `spend | cash | income | transfer`. Card-bill payments, self-transfers, wallet/UPI-Lite loads, SIPs and EMIs are `transfer`; ATM withdrawals are `cash` (real cashflow, not consumption). Spend totals and category breakdowns only include `spend`, so a ₹22,000 card bill payment cannot double-count the ₹22,000 of purchases it settles.

### 4. Money is integer paise

`Paise` is an extension type over `int`, with Indian grouping at the formatting edge (`en_IN`). Amounts are parsed from text once (`parseAmountToPaise`) and never round-tripped through `double` for arithmetic.

### 5. Explainability over cleverness

Classification keeps every weighted signal (`SmsSignal`), so the UI can answer "why was this flagged?" and the transaction sheet can show the parse confidence and the original message. A heuristic the user cannot interrogate is indistinguishable from a bug.

### 6. Conservative dedupe and conservative merging

Cross-alert merge requires: same amount, ≤3 minutes apart, *different* sender, and either the same card `issuer|last4` or similar merchant text. Two alerts from the *same* sender are treated as two real events (a genuine double charge), because silently swallowing one would hide exactly the bug the user needs to see. The loser is marked `duplicate_of`, never deleted.

### 7. Nothing is silently dropped

A message classified as an unrecognised transaction still produces a row with `needsReview = true`; the dashboard surfaces a "to confirm" banner and the user assigns a category. This is why the parser can be imperfect without the totals being wrong in a hidden way.

### 8. Demo mode is a feature, not a test fixture

`DemoFinanceRepository` generates four months of realistic Indian spend (three cards, rent, SIP, subscriptions, a duplicate charge, a phishing SMS) and is reachable from onboarding, settings and the empty state. It is the fastest way for someone to evaluate the product, and it makes every screen reviewable in a headless build.

## Data model

`transactions` (paise ints, `dedupe_key` unique), `cards` (limit, statement day, due day), `card_bills` (total/min due, due date), `categories`, `sms_messages` (raw + classification), `pending_categories` (notification quick-classify queue), `app_meta`. Additive migrations, WAL journal mode.

## Failure modes handled

| Failure | Handling |
|---|---|
| SMS permission denied | Onboarding explains before asking; the app stays usable in demo mode |
| Receiver captures an SMS the scan also sees | Same content hash → one transaction |
| Card limit unknown | `UtilizationBand.unknown` with copy that asks for the limit, instead of a fake 0% |
| Statement day unknown | Cycle defaults to the 1st and the UI says so |
| Receipt from a merchant-side system | Sender trust is `plausible`/`suspicious`; booking still requires a debit verb + amount |
| UPI collect request ("has requested money") | Explicit signal → informational, never a debit |
| OTP that contains an amount and a merchant | OTP wording outweighs the amount signal |

## Performance

Parsing runs once per new message (bounded batch of 3 000 per scan) and everything else is in-memory over the last 400 days of rows. Engines are pure functions, so widgets rebuild from a single `HomeData` snapshot rather than re-querying. Charts are custom painters (no chart dependency).

## Deliberately not built

Budgets, net-worth aggregation, credit-score reproduction, lending offers, cloud sync, ads. Each would either require data the app cannot legitimately see or compromise the offline privacy promise.

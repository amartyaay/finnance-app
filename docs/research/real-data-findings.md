# Real-inbox findings (anonymised)

From a 2 000-message scan on the owner's device (Galaxy S24). Long digit runs redacted.
286 transactions were produced; 89 (₹8.44 L) landed in **Other**.

Purpose: the fixture corpus is generic. These are the *actual* templates that fail, and
they should become fixtures.

## A. Extraction failures (merchant missing) — 40 of 89 rows

| Observed template (redacted) | Parsed | Correct |
|---|---|---|
| `Spent INR … Axis Bank Card no. XX#### 16-06-26 12:34:47 IST WWW AMAZON Avl Limit: INR …` | merchant `null` | `Amazon` (merchant appears after the timestamp, no `at/to` anchor — card alerts often use `WWW X` or `X` bare) |
| `Dear Customer, Your A/C XXXXX###### has a debit by transfer of Rs … Avl Bal Rs 0.00.-SBI` | merchant `null`, kind `spend` | `transfer` (no counterparty named; bank-internal/own-account move) |
| `Your A/C … Debited INR … -Transferred to Mr. AMARTYAAYUSHI. Avl Balance INR …` | merchant `null` | P2P transfer to a person → `transfer`, merchant = payee name |
| `Dear UPI user A/C X#### debited by … on date 17Jul26 trf to PhonePe Refno ####` | merchant `PhonePe Refno` | `transfer`, merchant `PhonePe` |

## B. Merchant present but not categorised — 49 rows

| Merchant string | Rows | ₹ | Should be |
|---|---:|---:|---|
| `JW MARRIOTT` (Amex Corp Card) | 1 | 1,11,510 | Travel (hotel brand) |
| `PhonePe Refno` | 1 | 72,570 | Transfers (junk suffix `Refno` must be stripped) |
| `ICICI Prudential Asset Managem UMR` | 3 | 9,000 | Investments (AMC / SIP) |
| `Pluxee Meal` | 24 | 7,831 | Food & dining (meal-benefit card) |
| `CWT INDIA` | 1 | 11,109 | Travel (corporate travel) |
| `takeUforward` | 1 | 6,049 | Education |
| `NAV 52` / `NAV 51` / `NAV 50` | 3 | 8,997 | junk merchant → should be rejected, and the row classified Investments (AMC purchase confirmation) |
| `download your Smart` | 2 | 5,999 | junk from a promo → reject |
| `Debit` | 4 | 12,000 | not a merchant → reject, falls back to transfer/spend inference |

Notes on `NAV 52`: a bare word plus a 1–3 digit number is almost never a merchant.
`Pluxee Meal` ×24 suggests benefit-card spends dominate small-ticket food — worth a rule.

## C. Classifier precision — the flagged "phishing" is mostly wrong

141 of 2 000 messages were flagged phishing. Sampled 8, **6 were not fraud**:

| Sender | Message (redacted) | Actual | Why it misfired |
|---|---|---|---|
| `AD-HDFCBK-T` | `###### is your OTP for service - Login request on HDFC Bank MyCards. Valid for 2 mins. Never share OTP @mycards` | informational (OTP) | the "never share OTP" phrasing matches the credential-ask rule |
| `JZ-JIONET-S` | `###### is your One Time Password (OTP) for JioBusiness…` | informational (OTP) | same |
| `AD-NSESMS-S` | `Beware while dealing based on unsolicited tips through Whatsapp/telegram…` | informational | "beware"/"unsolicited" reads as a warning to us, not a lure |
| `AD-AIRBNK-S` | `As per RBI guidelines,your A/c has been blocked due to KYC overdue. Update: https://i.airtel.in/AIRBNK/…` | caution, not fraud | link is the issuer's own domain; needs domain-vs-entity trust |
| `AD-TRAYAH-P` (×3) | `Your cart is pending. Please complete your purchase. http://u3.mnge.co/…` | promo | marketing link, not credential theft |
| `JK-ZESTMN-P` | `Get up to Rs 2 Lakh* credit facility with ZestMoney…` | promo | offer wording, no fraud intent |

### Rules this implies
1. **Credential asks must be imperative and second-person**: `(share|send|tell|confirm|enter|provide) (your )?(otp|pin|cvv|password)` — and explicitly *not* `never/do not share … otp`.
2. **OTP wording wins over everything else** except a genuine debit verb.
3. **Phishing needs fraud intent**, not just a link: KYC/block pressure **and** a link on a domain that does not match the sender's brand; or an imperative credential ask; or "pay to this UPI / scan this QR" from a non-registered sender.
4. **Domain trust**: if the link's registrable domain matches the sender's entity (e.g. `airtel.in`, `hdfcbank.com`, `icicibank.com`, `onlinesbi.sbi`, `axisbank.com`), it supports the message, it does not condemn it.
5. **Promo vs phishing**: cart reminders, download-the-app, loan offers, credit-line offers are `promo`; they contain links but no credential ask and no payment instruction.
6. Senders with a `-P` DLT suffix cannot be the source of a *transaction*, but they can still be phishing — the suffix alone must not force either outcome.

## D. Structural gaps found while debugging

- `transactions` has no `sender` column, so the app cannot show or filter by which bank alerted, and diagnostics cannot attribute failures to a template.
- `needs_review` only fires for missing merchants on spends (20 rows), while 40 rows have no merchant at all — the review queue is under-populated.
- No `merchant_rules` learning yet: a user fixing `Pluxee Meal → Food` once should apply to all 24.

## D2. Sender registry gaps (36 senders observed, many unresolved)

DLT prefixes seen but missing from `SenderRegistry.dltPrefixes`: `JX`, `JM`, `TX`, `BT`,
`JA`, `AV`, `CD`. They survive into the normalised id (`JXHDFCBK`, `JMCBSSBI`,
`JXSBIUPI`, `JMAXISBK`), so the entity lookup misses and trust falls back to
`plausible` instead of `known` — which lowers every downstream classification score.

Entity codes seen on this device but absent from `SenderRegistry.entities`:
`CBSSBI` (30 txns — State Bank of India), `PLUXEE` (25 — meal-benefit card),
`SWIGGY` (10), `ZEPTON` (6, Zepto), `WOCAMC` (4, AMC), `IPRUMF` (4, ICICI Pru MF),
`BNDNMF` (4, Bandhan MF), `SBIPSG` (2), `CDMILK` (2, Country Delight),
`KFINMF` (1), `MOAMCL` (1), `JIOHTT` (1, JioHotstar), `FLPKRT` (1, Flipkart),
`BLNKIT` (1, Blinkit), `ETCLUB` (1), `JIOPAY` (1), `GOVTAP` (1).

Important distinction: **merchant-side senders** (`SWIGGY`, `ZEPTON`, `FLPKRT`,
`BLNKIT`, `JIOHTT`, `CDMILK`) send order/receipt notices, not bank debits. They must
resolve to a known *merchant* kind that does **not** receive the bank trust bonus,
otherwise every "your order is confirmed" becomes a spend.

## F. Measured on the owner's inbox (317 transactions) — the two priorities

### P1 — spam counted as spend
Only 1 of 317 rows carries obvious offer wording (`Flipkart Order Received … e-Gift
Voucher`), so the current rule set is not yet spraying loan offers into spending. But
the guard is accidental, not designed: it survives because the amount scorer penalises
`available`/`limit`. A message shaped `Loan of INR 36,000 available for you` has a
debit-less frame, a currency-marked amount and a known sender, which is enough to pass
the `tx >= 4 && hasAmount` fallback. **Needed: a hard gate** — a row can only be a
transaction if the message contains a *money-moved* verb (debited/spent/paid/sent/
withdrawn/charged/credited/refunded) **or** an explicit balance/limit delta. Offers,
eligibility, limits, cashback estimates and "available" amounts can never qualify, no
matter how confident the amount parse is.

### P1b — money-verb-less rows that are currently wrong
| Rows | Message shape | Currently | Should be |
|---|---|---|---|
| 4 | `PAYMENT ALERT! INR 3000.00 deducted … towards ICICI Prudential Asset M…` | spend | **transfer** (SIP/investment) |
| 2 | `Recharge of INR 361.00 is successful for your Airtel Mobile` | spend (no verb) | spend ✔ (allow receipt-style recharge wording) |

### P2 — double counting
Confirmed cases in a single inbox:

| Case | Evidence | Cause |
|---|---|---|
| Same amount as **income and spend** 3 s apart (`CBSSBI`, ₹10,012) | `income,spend` in one 10-minute bucket | one event parsed twice with opposite directions (TD closure / transfer) |
| `Closure of TD` ₹23,023 + ₹22,022 + ₹15,019 | same sender, 2–5 s apart | principal and interest legs of a term-deposit closure booked as spend/income |
| Merchant receipts (`SWIGGY` ₹30 ×1 pair, `ZEPTON` ₹49 ×1 pair, `PLUXEE` ₹408 ×2, `SBIUPI` GROWW ₹300 ×2) | same sender, same amount, seconds apart | order/receipt notifications from merchant senders becoming spends alongside the real bank alert |

Three mechanisms are needed:
1. **Merchant-receipt senders** (`SWIGGY`, `ZEPTON`, `FLPKRT`, `BLNKIT`, `JIOHTT`,
   `CDMILK`) never create a transaction on their own — they are corroboration only.
2. **Same-sender, same-amount, opposite-direction pairs within 120 s** collapse to one
   row (a debit and credit of the same amount is a transfer, not a spend plus income).
3. **Paired-leg messages** (`Closure of TD`, `principal … interest`) merge into one
   transfer rather than two rows.

Current duplicate-merge rules cannot catch any of these: same-sender pairs are
explicitly excluded, and direction mismatch is not considered.

## E. What "good" looks like after the fix

- "Other" < 10 % of money and < 15 % of rows.
- Merchant present on ≥ 85 % of spend rows.
- Phishing precision ≥ 90 % on the sampled set (better to miss a scam than to cry wolf on an OTP).
- Every row attributable to a sender, so a bad template can be found from the app.

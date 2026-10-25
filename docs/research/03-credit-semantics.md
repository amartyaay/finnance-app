# 03 — Credit semantics for an SMS-only, offline PFM (India)

**Status:** implementable domain specification, v1.0 (25 Oct 2026)
**Audience:** product, Android, data/ML, compliance
**Scope:** offline Android app that reads bank/card SMS alerts on the phone and computes credit and cashflow metrics from SMS + user-entered settings. No bureau API. No bank API. No server.
**Non-goals:** credit scoring, lending, credit-line origination, personalised investment advice, underwriting.

---

## 0. How to read this document

- **MUST** = required for correctness or compliance.
- **SHOULD** = strongly recommended; deviations need a documented reason.
- **MAY** = optional.
- Formula IDs (`F-…`), rule IDs (`R-…`), metric IDs (`M-…`), anomaly IDs (`AN-…`) and test IDs (`T-…`) are stable references for code review and QA.
- All amounts are in **paise** (integer). ₹1 = 100 paise. All dates are **Asia/Kolkata** (IST) local dates unless explicitly marked as instants.
- “Statement date” means the card’s billing-cycle closing date. “Due date” means the payment due date printed on that statement. “Reported utilisation” means the utilisation a credit bureau is likely to compute from the issuer’s periodic report — not the user’s live balance.
- “Spend” means economic consumption (goods/services, rent, utilities, insurance, fees, interest, taxes). “Transfer” means a movement between the user’s own accounts or a settlement of a card/loan balance. A card purchase is spend **at purchase time**; the later card-bill payment is a **transfer**. This single distinction prevents the most common double-count in Indian PFM apps.

**The one invariant.** Every money movement is classified exactly once into one `flow_class`:

`SPEND | INCOME | TRANSFER | FINANCING | REFUND | REWARD | CASH | UNKNOWN`

and only `SPEND` (net of `REFUND`) enters consumption; only `INCOME` enters income; `TRANSFER`, `FINANCING`, `REWARD` and `CASH` never enter either. If a movement is not confidently classifiable, it stays `UNKNOWN` and is excluded from headline metrics with a visible “needs review” count. Never guess silently.

---

## 1. Domain model

### 1.1 Entities

| Entity | Key fields | Why it exists |
|---|---|---|
| `CardAccount` | `id`, `issuer`, `network`, `last4`, `parent_account_id`, `sanctioned_limit_paise`, `statement_day`, `due_day_offset`, `status` | A credit-card **account** is the unit of limit and bureau reporting. Add-on plastics share the parent account. |
| `Plastic` | `id`, `account_id`, `last4`, `kind` (`primary`/`add-on`/`virtual`), `status` | The card number the user sees in SMS may be an add-on or a reissued card. Never treat a plastic as a separate limit. |
| `LimitEvent` | `account_id`, `kind` (`sanction`/`enhance`/`reduce`/`temp`/`temp_expiry`), `amount_paise`, `effective_from`, `effective_to`, `source_event_id` | Limit changes must not rewrite history. Utilisation at an old statement date uses the limit in force then. |
| `Statement` | `account_id`, `statement_date`, `due_date`, `total_due_paise`, `min_due_paise`, `previous_balance_paise`, `purchases_paise`, `payments_paise`, `credits_paise`, `finance_charge_paise`, `late_fee_paise`, `annual_fee_paise`, `emi_principal_paise`, `emi_interest_paise`, `available_limit_paise`, `total_limit_paise`, `source_event_id`, `confidence` | The bill record. TAD is the best available anchor for the balance at statement date. |
| `TxnEvent` | `id`, `ts_utc`, `local_date`, `amount_paise`, `direction` (`debit`/`credit`), `instrument` (`card`/`upi`/`neft`/`imps`/`bbps`/`wallet`/`cash`/`account`), `account_id`, `card_last4`, `merchant_raw`, `merchant_norm`, `category`, `flow_class`, `source`, `confidence`, `ref`, `raw_sms_id` | Atomic parsed event. |
| `TransferLink` | `debit_event_id`, `credit_event_id`, `kind` (`self`/`card_bill`/`investment`/`loan_principal`/`wallet`/`cash`), `confidence` | Pairs the two sides of an internal movement. |
| `RecurringSeries` | `merchant_key`, `instrument`, `base_amount_paise`, `cadence`, `anchor_dom`, `occurrences`, `confidence`, `next_due_date`, `status` | Subscriptions, mandates, EMIs, rent, bills. |
| `IncomeEvent` | `type` (`salary`/`business`/`interest`/`dividend`/`rent`/`gift`/`other`), `amount_paise`, `employer`, `payday`, `confidence` | Salary and other income, separated from transfers. |
| `UserSettings` | cards, own accounts, employer aliases, statement days, APR assumptions, reporting basis, target utilisation, retention | The app cannot know these from SMS; ask once, visibly, and allow edits. |
| `RawSms` | `sender`, `body_hash`, `received_at`, `processed`, `deleted_at` | Raw SMS is sensitive. Prefer storing only a hash + derived events; if raw is stored, encrypt and expire it. |

### 1.2 Event taxonomy (the classification contract)

| Event | `flow_class` | Counts as spend? | Counts as income? | Affects cashflow? | Affects card outstanding? |
|---|---|---|---|---|---|
| Card purchase / POS / e-com | `SPEND` | Yes | No | Yes | + |
| Card annual fee, late fee, finance charge, forex markup, cash-advance fee | `SPEND` (fee/interest category) | Yes | No | Yes | + |
| Card cash advance | `FINANCING` (principal) + `SPEND` (fee/interest) | Fee/interest only | No | Fee/interest only | + |
| Credit-card bill payment from bank/UPI/BBPS/NEFT | `TRANSFER` (`card_bill`) | **No** | **No** | No (internal) | − |
| Refund / reversal / chargeback on card or UPI | `REFUND` | Negative spend | No | Inflow in refund month | − |
| Cashback / reward points credited | `REWARD` | No | No | No | − (if statement credit) |
| Fuel-surcharge waiver, annual-fee waiver, interest reversal | `REFUND` (fee waiver) | Negative fee | No | No | − |
| Salary / business receipt | `INCOME` | No | Yes | Yes | — |
| Interest / dividend / rent received | `INCOME` (`other`) | No | Yes | Yes | — |
| Self-transfer between own accounts | `TRANSFER` (`self`) | No | No | No | — |
| SIP / mutual fund / demat / PPF / EPF / NPS | `TRANSFER` (`investment`) | No | No | No (savings allocation) | — |
| Loan EMI | `TRANSFER` (`loan_principal`) + `SPEND` (interest) | Interest only | No | Interest only | — |
| Loan disbursement / credit-line draw | `FINANCING` | No | **No** | Inflow but liability | — |
| Wallet load / UPI Lite top-up | `TRANSFER` (`wallet`) | No | No | No | — |
| Wallet / UPI Lite payment | `SPEND` if seen | Yes | No | Yes | — |
| ATM withdrawal | `CASH` | **No** | No | No (cash holding) | — |
| Cash spending entered by user | `SPEND` | Yes | No | Yes | — |
| Utility / mobile / broadband bill | `SPEND` | Yes | No | Yes | — |
| Insurance premium | `SPEND` (protection) | Yes | No | Yes | — |
| Tax / advance tax | `SPEND` | Yes | No | Yes | — |
| P2P to friend/family | `TRANSFER` | No | No | No | — |
| P2P to landlord (tagged rent) | `SPEND` | Yes | No | Yes | — |
| P2M merchant goods/services | `SPEND` | Yes | No | Yes | — |
| P2M credit-card bill / loan EMI / mutual fund / broker | `TRANSFER` / split | No (except interest) | No | No | — |
| P2M insurance premium | `SPEND` | Yes | No | Yes | — |
| Gift received | `INCOME` (`gift`) or `TRANSFER` if from own account | No | Separate from regular income | Yes | — |
| Failed / declined / OTP / collect request / pre-debit notice | `UNKNOWN` or no event | **No** | No | No | — |

**Composite debits MUST be split.** A loan EMI, a card EMI or a cash advance is one bank debit with two economic components. Split it into child events — principal (`TRANSFER`) and interest/fee (`SPEND`) — so each child has exactly one `flow_class`. Do not assign two classes to one event; that breaks the invariant and double-counts in reports.

### 1.3 Money representation and rounding

- Store `amount_paise` as `int64`. Never use `double` for money.
- Parse Indian grouping: `1,23,456.78`, `123,456.78`, `₹1,23,456`, `Rs. 1,234/-`, `INR 5000`. Accept `.` decimal and optional paise.
- Arithmetic in paise; convert to rupees only at the display boundary.
- Display rupees with Indian grouping and **no decimals unless paise are non-zero**; for statement totals, show exact paise when the bank does.
- Percentages: compute from paise, round half-up to one decimal at display. Never compare rounded values; compare paise.
- `round_half_up(x)` for INR display. Do not use banker’s rounding for user-facing rupees; use it only if a bank statement explicitly does.
- Do not sum already-rounded display values. A “₹1,23,456” tile and a “₹1,23,457” total can both be correct if the underlying paise differ; show a reconciliation tooltip.

### 1.4 Time

- SMS timestamps are epoch milliseconds; convert to `Asia/Kolkata` for `local_date`. Store both `ts_utc` and `local_date`.
- Due dates and statement dates are **date-only** values. Never represent them as UTC midnight instants; a date-only value shifted by a timezone becomes the previous day.
- Countdown: `days = due_date − today` using IST calendar dates. `0` = due today; negative = overdue.
- “Due today” remains true until 23:59:59 IST, but bank payment cut-offs can be earlier. Copy: “Due today (check your bank’s cut-off time).”
- If the user travels, keep IST for Indian cards by default. Offer a “use device timezone” override only if the user explicitly asks.
- Statement/due dates can move for weekends/holidays. Store the **printed** dates; do not auto-shift. Show a ±2-day payment window only when the bank itself says so.

### 1.5 Confidence and provenance

Every derived event carries:

- `source` (`sms_bank`, `sms_card`, `notification`, `csv`, `manual`, `inferred`)
- `confidence` in `[0,1]`
- `provenance` (raw SMS hash / CSV row / notification package)
- `needs_review` boolean if confidence < 0.6 or classification is `UNKNOWN`

Rules of thumb:

| Confidence | Meaning | UI treatment |
|---|---|---|
| ≥ 0.90 | Bank/card SMS with reference + amount + last4 | Auto-post; no review badge |
| 0.70–0.89 | Bank SMS with amount + one identifier | Auto-post; small “check” affordance |
| 0.50–0.69 | Inferred from merchant/limit/pattern | Show with “estimated” label; exclude from headline if material |
| < 0.50 | Ambiguous | `UNKNOWN`; do not count; add to review inbox |

---

## 2. Credit utilisation

### 2.1 What the bureau actually sees

A credit bureau does not see the user’s live balance. It sees a periodic report from the issuer. In India, the reported balance is **typically the balance at statement generation**; TransUnion CIBIL’s CEO has said: “The figure that gets reported depends on the balance at the time of statement generation. If your statement reflects zero balance because you paid off early, the high utilisation may not be recorded.” ([Moneycontrol, 31 Oct 2025](https://www.moneycontrol.com/news/business/personal-finance/exceeding-credit-card-limit-but-clearing-it-before-statement-date-will-it-still-show-high-utilisation-13644242.html))

That is why:

- **Paying before the statement date** lowers the balance the issuer is likely to report, even if the due date is weeks later.
- **Paying after the statement date but before the due date** avoids interest (if paid in full) but does **not** change the statement that has already been generated. It lowers the *next* report.
- **Paying after the due date** risks late-payment charges, interest from the transaction date, and adverse bureau reporting.

Caveats the app must display:

1. Issuers vary. Some report at statement date, some at month-end, some on another fixed date. The app cannot know without the user’s bureau report.
2. Some issuers report the **billed** balance; others report **billed + unbilled**. The app should default to “statement balance” and offer a “billed + unbilled” estimate.
3. Reporting is periodic and can lag. A payment made yesterday may not appear in the bureau data for weeks.
4. The app must never claim to know the exact reported figure. It estimates, labels the estimate, and shows the basis.

### 2.2 The 30% guidance, the 10% target, and 1–9% (AZEO)

**30% is bureau guidance, not an RBI rule.** TransUnion CIBIL’s own consumer education says: “A credit utilisation ratio above 30% can start to drag down your scores. So, the lower it is, the better.” ([CIBIL blog](https://www.cibil.com/blog/some-of-the-common-credit-mistakes-to-avoid)) Use 30% as a caution line, not a legal threshold. Do **not** write “RBI says keep utilisation below 30%” — RBI’s card directions do not prescribe a utilisation target.

**10%** is a common practitioner target (“keep it under 10% for the best profile”). No Indian bureau publishes a 10% cut-off. Label it “common target, not a bureau rule”.

**1–9% and AZEO.** AZEO means “All Zero Except One”: let every card report zero, except one card that reports a small balance — conventionally 1–9% of its limit — then pay that balance in full by the due date. It comes from US credit-repair/mortgage practice and FICO-style “amounts owed” modelling: some models treat an all-zero revolving profile as “no recent revolving activity” and score a small non-zero balance slightly better than zero. It is **not** an RBI or CIBIL rule, and CIBIL/Experian India do not publish their exact scoring formulas or utilisation buckets. Treat AZEO as an optional optimisation for users who already pay in full:

- It never justifies carrying a balance or paying interest.
- It never justifies missing a due date.
- It can conflict with reward optimisation; do not push it.
- If the user has cash-flow stress, do not mention it.

**What the app may show:** a utilisation gauge, the 30% caution line, an optional 10% target line, and a plain-English note that lower is generally better and the bureau formula is not public. It must **not** show a credit score, a score delta, or “paying ₹X will raise your score by Y points”.

### 2.3 Formulas

Define, for card account `i` at time `t`:

- `L_sanctioned_i(t)` — sanctioned limit in force (permanent).
- `L_temp_i(t)` — temporary limit in force, else 0.
- `L_report_i(t)` — limit used for the reported-utilisation denominator. Default `L_sanctioned_i(t)`; optionally `+ L_temp_i(t)` if the issuer reports the temporary limit as part of the credit limit (user setting).
- `O_i(t)` — total outstanding principal (positive = owed).
- `B_i(t)` — unpaid EMI principal included in the card balance (Model A) or reported as a separate loan (Model B).
- `A_i(t)` — available limit as printed by the issuer.
- `P_i`, `R_i`, `C_i`, `F_i`, `S_i` — payments, refunds/reversals, cashback credits, fees/interest, purchases/cash advances between `t0` and `t`.

**F-UT-1 — per-card reported utilisation**

```
U_card_i(t) = 100 × max(0, O_i(t)) / L_report_i(t)      if L_report_i(t) > 0
U_card_i(t) = null                                     if L_report_i(t) = 0
```

If `O_i(t) < 0`, show `U = 0%` and a separate “credit balance ₹X” badge. Do not show a negative percentage.

**F-UT-2 — aggregate reported utilisation (weighted, never averaged)**

```
U_agg(t) = 100 × Σ_i max(0, O_i(t)) / Σ_i L_report_i(t)
```

Include only accounts with `L_report_i > 0`. Add-on plastics are not separate rows: aggregate their spend into the parent account and count the parent limit once. Closed cards are excluded from the live aggregate but kept in history.

Do **not** compute the arithmetic mean of per-card ratios. Example: card A ₹80,000 / ₹1,00,000 = 80%; card B ₹10,000 / ₹4,00,000 = 2.5%. Aggregate = ₹90,000 / ₹5,00,000 = **18%**; the mean of ratios would be 41.25% — wrong and alarmist.

**F-UT-3 — live utilisation (what the user might report if the statement closed today)**

```
U_live_i(t) = 100 × max(0, O_est_i(t)) / L_report_i(t)
```

`O_est_i(t)` comes from the best available signal (§2.4). Show the source and confidence.

**F-UT-4 — projected utilisation at the next statement date**

```
d_elapsed   = max(1, date(t) − date(cycle_start) + 1)
d_remaining = max(0, date(statement_date) − date(t))

S_run_rate  = S_discretionary_cycle / d_elapsed
S_proj      = S_recurring_known + S_run_rate × d_remaining

O_proj      = max(0, O_est(t) + S_proj − P_sched(t, statement_date))
U_proj      = 100 × O_proj / L_report(statement_date)
```

Where:

- `cycle_start` = the day after the previous statement date.
- `S_discretionary_cycle` = spend in the current cycle **excluding** known recurring items (to avoid double counting).
- `S_recurring_known` = sum of known recurring debits expected before the statement date (from §6), plus known EMIs/rent with a due date before the statement.
- `P_sched` = payments the user has scheduled or told the app about before the statement date; usually 0.
- If the user’s limit changes before the statement date, use the limit in force **on** the statement date.
- Cap `S_proj` at `A_eff(t)` (available limit) so the projection never exceeds what the card can actually spend. If `A_eff ≤ 0`, show “over limit / no headroom” and do not project further spend.

**F-UT-5 — effective available limit and headroom**

```
A_eff_i(t) = max(0, L_sanctioned_i + L_temp_i − O_est_i − B_i)   [Model B: EMI separate]
A_eff_i(t) = max(0, L_sanctioned_i + L_temp_i − O_est_i)         [Model A: EMI inside O]
Headroom_to_30_i = max(0, 0.30 × L_report_i − O_est_i)
```

Use `A_eff` for “can I spend?” and `Headroom_to_30` for “how far to the caution line?” They are not the same number.

**F-UT-6 — limit history**

```
L_report_i(t) = L_sanctioned_i(effective at t) + L_temp_i(t) × temp_reported_flag
```

Store `LimitEvent` rows with `effective_from` / `effective_to`. Never recompute a historical statement’s utilisation with a later limit.

### 2.4 Deriving utilisation from SMS-only signals

There are four independent signals. Use them in this order; reconcile explicitly.

**S1 — Available limit + total limit (strongest single SMS signal)**

If an SMS says “Avl Lmt: ₹48,500” and the user’s total limit is ₹2,00,000:

```
O = L_sanctioned + L_temp − A_issuer
U = 100 × O / L_report
```

Why not simply `L − A`? Because temporary limits and EMI blocking change `A`. Use `L_sanctioned + L_temp` if the temporary limit is active; otherwise `L_sanctioned`. If the SMS’s available limit excludes cash limit or includes pending authorisations, the estimate is noisy — label it “estimated from available limit”.

**S2 — Statement TAD anchor + ledger (best for a cycle)**

If the latest statement says “Total Amount Due ₹42,000” on 12 Oct:

```
O(t) = TAD + Σ debits after statement_date − Σ credits after statement_date
```

Credits include payments, refunds, reversals and cashback statement credits. Debits include purchases, fees, interest and cash advances. This is the most explainable method: every term is a transaction the user can inspect. Use it when a statement SMS has been parsed.

**S3 — “Spent X, limit Y” or “total outstanding X”**

If the SMS says “Total outstanding ₹52,500” — use it directly as `O`. If it says “spent ₹5,000, limit ₹2,00,000” — that is a **transaction**, not the outstanding. Do not set `O = 5,000`. Only use “spent” as a transaction event.

**S4 — Inference from spend since statement**

If no statement and no available limit:

```
O_est = opening_balance + Σ debits − Σ credits
```

`opening_balance` may be unknown. In that case, do not invent it. Show “utilisation unavailable — add your statement or limit” rather than a made-up percentage. If the user has entered a limit and the app has seen every transaction since card setup, it may estimate from zero with a clear “since setup” label.

**Reconciliation and confidence**

- If S1 and S2 agree within ₹100 or 0.5% (whichever is larger), confidence 0.95.
- If they disagree, prefer S2 if the statement is within the current cycle; otherwise S1. Show both in a “why?” sheet.
- If S1, S2, S3 disagree by more than ₹1,000, set `needs_review` and show a range, not a point.
- Never silently overwrite a statement anchor with an available-limit estimate.

| Signal | Formula | Best when | Main error sources |
|---|---|---|---|
| S1 available limit | `O = L + temp − A` | No statement parsed; live check | Temp limit, EMI block, pending auth, cash limit |
| S2 TAD + ledger | `O = TAD + debits − credits` | Statement parsed; current cycle | Missed SMS, duplicate alerts, refunds, fees |
| S3 direct outstanding | `O = printed outstanding` | SMS explicitly says total outstanding | Rare; wording ambiguous |
| S4 inference | `O = opening + debits − credits` | Full history since setup | Unknown opening, missing channels (UPI Lite, wallet) |

### 2.5 Special cases (must-handle list)

| Case | What changes | Correct treatment | Wrong treatment to avoid |
|---|---|---|---|
| **Limit enhancement** | `L_sanctioned` increases; effective date | Add `LimitEvent`; use new limit from effective date. Historical statements keep old limit. | Recomputing old utilisation with the new limit (makes old high utilisation disappear). |
| **Temporary limit** | `L_temp` active until expiry | Use for `A_eff`; for `L_report`, use only if issuer reports it. Show “temp limit expires 31 Dec”. | Treating temp as permanent; using it for historical statements. |
| **Add-on card** | Shares parent limit and liability | Map plastic → parent account; sum spend into parent `O`; one `L`. | Counting a separate limit for the add-on (double counts limit, halves utilisation). |
| **EMI principal blocked** | `B` is owed but carved out of available limit | Model A: `B ⊂ O`; `O = L + temp − A`. Model B: `B` separate; `O_card = L + temp − A − B`. Ask which model the issuer uses. | Subtracting `B` twice; ignoring `B` and understating utilisation. |
| **Refund** | Credit reduces `O` | Link to original debit; reduce spend in original category/month; reduce `O` when posted. | Counting refund as income; not reducing spend (user sees phantom spend). |
| **Fuel surcharge** | Debit includes surcharge; later waiver credit | Net fuel spend = fuel + surcharge − waiver. Waiver is a fee refund, not income. | Counting waiver as income; counting surcharge twice. |
| **Forex markup** | Debit may be in foreign currency; markup + GST added | Use INR amount if printed; else convert and add markup + GST as fee. Show effective INR cost. | Adding markup again when the SMS already shows INR; ignoring GST. |
| **Annual fee** | Fee + GST debit; possible waiver | Fee = `SPEND` (fees); waiver = `REFUND` (fee). Net zero if waived. | Treating fee as purchase (rewards); treating waiver as income. |
| **Cash advance** | Principal + fee + interest | Principal = `FINANCING`; fee/interest = `SPEND`; not consumption. | Counting cash advance as spend (inflates spend and savings rate distortion). |
| **Overlimit** | `O > L`; overlimit fee | `U > 100%`; flag; show overlimit amount; fee = spend. | Clamping to 100% silently (hides a real risk). |
| **Credit balance** | `O < 0` | `U = 0`; show credit balance; not income. | Showing negative utilisation or negative spend. |
| **Balance transfer** | Card A credit, card B debit | Both `TRANSFER`; fees/interest = spend; link the two cards. | Counting the transfer as spend or income. |
| **Reversal** | Credit cancels a debit | Cancel the original event; reduce spend/`O`; no income. | Treating as refund of a different purchase. |
| **Cashback** | Statement credit or points | `REWARD`; reduces `O` if statement credit, but not spend; not income. | Treating cashback as refund (reduces category spend incorrectly) or income. |

### 2.6 Worked examples

**E-1 — statement anchor and projection**

HDFC card, `L = ₹2,00,000`. Statement 12 Oct: `TAD = ₹42,000`, due 1 Nov. On 22 Oct: purchases since statement `₹12,000`; refund `₹1,500`; no payment.

```
O_est = 42,000 + 12,000 − 1,500 = ₹52,500
U_live = 52,500 / 2,00,000 = 26.25%
```

Cycle: 13 Oct–12 Nov. `d_elapsed = 10`, `d_remaining = 21`. Discretionary spend = ₹12,000 (refund is not spend), run-rate = ₹1,200/day. Known recurring before statement = ₹2,500.

```
S_proj = 2,500 + 1,200 × 21 = ₹27,700
O_proj = 52,500 + 27,700 = ₹80,200
U_proj = 80,200 / 2,00,000 = 40.1%
```

If the user pays ₹20,000 on 5 Nov (before the statement):

```
O_proj = 80,200 − 20,000 = ₹60,200
U_proj = 30.1%
```

If the user pays ₹20,000 on 20 Nov (after the statement, before the 1 Dec due date), the 12 Nov report still shows ₹80,200; the next report shows the lower balance. Copy must make that distinction.

**E-2 — available limit with temporary limit and EMI**

Card `L = ₹3,00,000`; temporary limit `₹50,000`; available limit SMS `₹2,10,000`; EMI principal outstanding `₹40,000` (Model A, inside the card balance).

```
O = 3,00,000 + 50,000 − 2,10,000 = ₹1,40,000
O_retail = 1,40,000 − 40,000 = ₹1,00,000
U (temp not reported) = 1,40,000 / 3,00,000 = 46.7%
U (temp reported)     = 1,40,000 / 3,50,000 = 40.0%
```

If an analyst ignores EMI and uses only retail spend, they get `1,00,000 / 3,00,000 = 33.3%` — a 13.4-point understatement. If they subtract `B` from `O` again, they get `1,00,000 / 3,00,000 = 33.3%` — also wrong for Model A.

**E-3 — refund after the statement**

Statement 5 Oct: `TAD = ₹60,000`; `L = ₹2,00,000`; reported `U = 30%`. Refund `₹10,000` on 20 Oct.

```
O = 60,000 − 10,000 = ₹50,000
U_live = 25%
```

The 5 Oct reported figure remains 30%; the refund affects the 5 Nov statement and the live gauge. Analytics: reduce the original purchase’s category/month by ₹10,000 (accrual), and show the cash inflow in October. Do both, with labels.

**E-4 — limit enhancement mid-cycle**

5 Oct: `L = ₹1,00,000`, `O = ₹45,000` → 45%. On 20 Oct the limit is enhanced to ₹2,00,000.

- 5 Oct utilisation stays **45%**. Do not recompute it as 22.5%.
- 5 Nov: `O = ₹50,000`, `L = ₹2,00,000` → **25%**.
- Show the limit history on the card detail screen.

**E-5 — aggregate is weighted, not average**

Card A: ₹80,000 / ₹1,00,000 = 80%. Card B: ₹10,000 / ₹4,00,000 = 2.5%.

```
U_agg = 90,000 / 5,00,000 = 18%
Mean of ratios = (80 + 2.5) / 2 = 41.25%   ← wrong
```

### 2.7 Acceptance tests

| ID | Given | Expected |
|---|---|---|
| T-UT-01 | Statement TAD ₹42,000, spend ₹12,000, refund ₹1,500, limit ₹2,00,000 | Live 26.25%; projected 40.1% with the E-1 inputs |
| T-UT-02 | Available ₹2,10,000, L ₹3,00,000, temp ₹50,000, EMI ₹40,000 (Model A) | O ₹1,40,000; U 46.7% (or 40.0% if temp reported); not 33.3% |
| T-UT-03 | Limit enhanced 1 Oct, statement 5 Oct | 5 Oct uses the new limit if effective before the statement; prior statements unchanged |
| T-UT-04 | Add-on card with ₹20,000 spend, parent L ₹2,00,000 | Parent O increases by ₹20,000; limit counted once |
| T-UT-05 | Refund ₹10,000 after statement | Live U falls; prior reported U unchanged; spend reduced in original month |
| T-UT-06 | Two cards, 80% and 2.5% | Aggregate 18%, not 41.25% |
| T-UT-07 | `O < 0` | U = 0%; credit balance badge; no negative spend |
| T-UT-08 | Limit = 0 / missing | U = null; “add your limit” state; no divide-by-zero |

---

## 3. Bill payments

### 3.1 What a bill payment is — and is not

A credit-card bill payment is a **transfer** from a deposit account (or wallet/another card) to a card account. It settles spend that was already counted when the purchase happened. It is **not** spend, **not** income, and **not** a new purchase.

Misclassifying it as spend is the single most damaging bug in an SMS-only PFM:

- It inflates monthly spend by the bill amount.
- It lowers the savings rate by the same amount.
- It double-counts purchases (once at purchase, once at bill payment).
- It can make utilisation move the wrong way (a payment should reduce `O`; treating it as a purchase increases `O`).

A payment to **someone else’s** card is also not consumption; it is a transfer/gift. Default to transfer, allow the user to tag “gift”, and never count it as spend.

### 3.2 How a card bill payment appears in SMS

Banks use registered DLT sender headers (e.g., `VM-HDFCBK`, `AD-ICICIB`) and templates. Parse **fields**, not exact strings: amount, card last4, account last4, channel, reference, date. Sender headers are a trust signal, not proof — SMS can be spoofed, and users can forward messages.

**Representative templates (actual bank wording varies):**

| Scenario | Representative SMS | Key fields |
|---|---|---|
| (a) Same bank card + savings | “Rs.15,000 debited from A/c XX1234 on 10-May-24 towards HDFC Bank Credit Card XX5678. Ref 123456.” | amount, acct4, card4, date, ref |
| (a) Card side | “Payment of Rs.15,000 received towards your HDFC Bank Credit Card ending 5678 on 10-May-24. Thank you.” | amount, card4, date |
| (b) Another bank via BBPS/CRED/Cheq/Paytm | “Rs.12,000 debited from A/c XX1234 on 10-May-24 to BBPS/CRED for Credit Card XX5678. UPI Ref 998877.” | amount, acct4, card4, channel, ref |
| (b) BillDesk / aggregator | “INR 8,500 paid to BILLDESK via UPI from A/c XX1234 for card bill. Ref 445566.” | amount, acct4, channel |
| (c) NEFT to card account | “NEFT DR: Rs.7,500 from A/c XX1234 to ICICI Bank Credit Card A/c XX5678, UTR NEFT123456789.” | amount, acct4, card4, UTR |
| (d) Auto-debit / SI | “Rs.5,000 auto-debited from A/c XX1234 on 05-May-24 for HDFC Credit Card XX5678 (SI).” | amount, acct4, card4, SI |
| (e) Cheque / cash deposit | “Cheque no. 123456 for Rs.10,000 cleared; credited to Credit Card XX5678.” | amount, card4, cheque no. |
| Bill reminder | “Total Amount Due: Rs.12,345.00; Minimum Due: Rs.620.00; Due Date: 15-May-24.” | TAD, MAD, due date |
| Statement reminder | “Your HDFC Credit Card XX5678 statement for 01-Apr-24 to 30-Apr-24 is generated. Total due Rs.12,345, minimum due Rs.620, due 15-May-24.” | period, TAD, MAD, due |
| Payment due reminder | “Payment of Rs.12,345 is due on 15-May-24. Minimum due Rs.620. Pay now to avoid late fee.” | TAD, MAD, due |

The parser MUST distinguish:

- **Debit on a deposit account** (outflow) vs **credit on a card** (inflow to the card).
- **Payment** wording (`payment received`, `payment of`, `bill paid`, `autopay`, `credit received`) vs **spend** wording (`spent`, `debited`, `transaction`, `purchase`).
- **Refund/reversal** wording (`refund`, `reversed`, `chargeback`) vs **payment** wording.
- **Cashback** wording (`cashback`, `reward`, `points`) vs **payment**.
- **Pre-debit notification** (`will be debited`, `intimation`, `mandate`) vs the actual debit.

### 3.3 Parsing bill reminders into a bill record

A bill reminder becomes a `Statement` only if it contains at least `TAD` and `due_date`, or `MAD` and `due_date` with a card identifier. If it contains only “bill generated” with no amount, create an “expected bill” placeholder, not a statement.

**Fields to parse**

| Field | Pattern (illustrative) | Validation |
|---|---|---|
| Card last4 | `(?:card|cc).{0,20}?(?:ending|xx|\*+)?\s*(\d{4})` | 4 digits; if multiple, split into multiple statements |
| Account last4 | `(?:a/c|acct|account).{0,20}?(?:xx|\*+)?\s*(\d{4})` | 4 digits |
| Statement date | `(?:statement|bill)\s*(?:date|dated|generated)\s*:?\s*([0-9]{1,2}[-/][0-9]{1,2}[-/][0-9]{2,4})` | If absent, use SMS date; mark `inferred` |
| Due date | `(?:due\s*(?:date|on)|payment\s*due)\s*:?\s*([0-9]{1,2}[-/][0-9]{1,2}[-/][0-9]{2,4})` | MUST be ≥ statement date + 14 days (RBI one-fortnight rule). If not, flag “unusual — check SMS” and do not suppress the reminder. |
| Total amount due | `(?:total\s*(?:amount\s*)?due|total\s*due|tad)\s*:?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{1,2})?)` | ≥ 0; if negative, credit balance |
| Minimum due | `(?:minimum\s*(?:amount\s*)?due|min\.?\s*due|mad)\s*:?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{1,2})?)` | `0 ≤ MAD ≤ TAD`; if violated, mark `needs_review` |
| Bill period | `(\d{1,2}\s*[A-Za-z]{3,9})\s*[-–]\s*(\d{1,2}\s*[A-Za-z]{3,9})` | Optional; used to dedupe reminders |
| Available limit | `(?:avl|available|avail)\s*(?:lmt|limit)\.?\s*:?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{1,2})?)` | Optional; cross-check |
| Total limit | `(?:total|sanctioned|credit)\s*limit\s*:?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{1,2})?)` | Optional; update `LimitEvent` only with user confirmation |

**Dedupe rules for reminders**

- Same card + same `TAD` + same due date within 30 days → one statement; update `last_reminder_at`.
- Same card + same cycle + newer TAD → new statement (could be a revised bill); keep both with `supersedes` link.
- Different cards in one SMS → split into separate statements.
- A “payment due” reminder after a statement already parsed → update the reminder, do not create a second bill.
- A “bill generated” SMS with no TAD → create `Statement(expected=true)`, fill when the detailed SMS arrives.

**Bill-record semantics**

- `TAD` is the statement balance, not the current outstanding. The current outstanding may be higher (unbilled spends) or lower (payments after the statement).
- `MAD` is issuer-defined. Do not compute it. If missing, an estimate of `5% × TAD` (with the issuer’s floor if known) may be shown only with an explicit “estimated” label and a note that the issuer’s figure controls. Do not assume a ₹500 floor for every issuer.
- `previous_balance`, `purchases`, `payments`, `credits`, `finance_charge`, `late_fee`, `annual_fee`, `emi_principal`, `emi_interest` are optional; parse when itemised, otherwise leave null (do not fill zeros, which would look like facts).
- If `TAD` is net of credits during the cycle (RBI definition), do not subtract those credits again.

### 3.4 Rules table for bill-payment detection

Confidence is a starting point; adjust with sender trust and reference presence.

| Rule | Signal | Classification | Confidence | Guards / notes |
|---|---|---|---|---|
| **R-BP-01** | Card-side credit with “payment received / payment of / bill paid / autopay” + card last4 | `CARD_PAYMENT` (transfer) | 0.95 | Not income; link to card; if source unknown, leave unmatched but still transfer |
| **R-BP-02** | Deposit-account debit with “credit card / card bill / cc bill” + card last4 | `CARD_PAYMENT_OUT` (transfer) | 0.90 | If card last4 matches own card, link; else `UNTRACKED` |
| **R-BP-03** | Two events (debit + card credit) same amount ±₹1 within T+3 days | `TRANSFER_PAIR` (`card_bill`) | 0.98 | Strongest; mark both; no spend/income |
| **R-BP-04** | Narration contains `BBPS`, `BILLDESK`, `CRED`, `CHEQ`, `PAYTM`, `BILLPAY`, `BILL PAY` | Boost to `CARD_PAYMENT_OUT` | 0.90 | BBPS is a strong signal after RBI’s July 2024 mandate; still require card/payment wording |
| **R-BP-05** | `NEFT`/`IMPS`/`RTGS` to beneficiary containing `CREDIT CARD`, `CARD A/C`, or card last4 | `CARD_PAYMENT_OUT` | 0.85 | NEFT may post T+1; allow T+3 matching window |
| **R-BP-06** | `AUTO DEBIT`, `SI`, `ECS`, `MANDATE`, `STANDING INSTRUCTION` + card-side credit | `CARD_PAYMENT` | 0.90 | Pre-debit notice is not the debit; wait for actual |
| **R-BP-07** | Same-bank wording “from A/c … to card …” | `TRANSFER_PAIR` | 0.95 | Often both sides in one SMS; split into two events |
| **R-BP-08** | UPI debit to VPA containing `ccbill`, `creditcard`, `cred`, `cheq`, `billpay` | `CARD_PAYMENT_OUT` | 0.80 | VPA can be a wallet/aggregator; require card credit or user confirmation |
| **R-BP-09** | Cheque/cash deposit credited to a card account | `CARD_PAYMENT` | 0.70 | Cash deposit may be from a third party; allow “gift/other” tag |
| **R-BP-10** | Card credit with “refund / reversed / chargeback” | `REFUND` / `REVERSAL` | 0.90 | Not a bill payment; link to original |
| **R-BP-11** | Card credit with “cashback / reward / points” | `REWARD` | 0.90 | Not a bill payment; not income |
| **R-BP-12** | Deposit debit says “bill payment” but no card identifier and merchant not in bill-pay list | `CARD_PAYMENT_UNKNOWN` (transfer) | 0.50 | Do not count as spend; ask user “was this your card bill?” |
| **R-BP-13** | Payment amount > TAD | `CARD_PAYMENT_OVERPAY` | 0.95 | Credit balance; not income |
| **R-BP-14** | Payment amount < MAD | `CARD_PAYMENT_SHORTFALL` | 0.95 | Late-fee risk if past due > 3 days; not a “partial payment” success |
| **R-BP-15** | `MAD ≤ payment < TAD` | `CARD_PAYMENT_PARTIAL` | 0.95 | Interest applies; user is a revolver this cycle |
| **R-BP-16** | Payment to a card last4 not in the user’s accounts | `CARD_PAYMENT_EXTERNAL` (transfer/gift) | 0.70 | Not spend; ask user to tag gift/loan |
| **R-BP-17** | A pre-debit notice (“will be debited on …”) | `MANDATE_NOTICE` (no event) | 0.90 | Schedule only; never count as spend |
| **R-BP-18** | “Payment failed / declined / not processed” | `FAILED` (no event) | 0.95 | Do not count; do not reduce `O` |

**Refund/reversal/reward rules (R-RF)**

Refunds are **not income**. A refund reduces spend only when it is matched to a debit; an unmatched credit is a credit balance / review item, never negative spend. A reversal cancels the original event; a chargeback is provisional; a cashback is a reward, not a refund.

| Rule | Signal | Classification | Confidence | Guard / action |
|---|---|---|---|---|
| **R-RF-01** | Card credit “refund” matched to a card debit: same card, merchant/VPA, amount ≤ original, within 120 days | `REFUND_MATCHED` | 0.95 | Reduce original spend/category and `O`; keep the link |
| **R-RF-02** | Card credit “reversal / reversed / reversed txn” matched to a debit | `REVERSAL` | 0.95 | Cancel original; if original never posted, ignore |
| **R-RF-03** | Card credit “chargeback / dispute credit” | `CHARGEBACK` | 0.85 | Provisional refund; hold; re-add spend if later debited back |
| **R-RF-04** | Card credit “cashback / reward / points” | `REWARD` | 0.95 | Not refund/income; if statement credit, reduce `O` only |
| **R-RF-05** | Credit “fuel surcharge waiver” | `FEE_WAIVER_FUEL` | 0.95 | Reduce fuel category; not income |
| **R-RF-06** | Credit “annual fee waiver / fee reversal” | `FEE_WAIVER_FEE` | 0.95 | Reduce fees; not income |
| **R-RF-07** | Credit “interest reversal” | `FEE_WAIVER_INTEREST` | 0.95 | Reduce interest; not income |
| **R-RF-08** | Refund > original, or no matching debit | `REFUND_UNMATCHED` | 0.50 | Credit balance; not income; review |
| **R-RF-09** | Refund arrives after the bill was paid, and amount > 1% of limit or ₹5,000 (whichever lower) | `REFUND_MAYBE_TO_BANK` | 0.70 | Do not assume card `O` fell; issuer may credit the bank account (RBI 2025 para 31) |
| **R-RF-10** | Refund posted after the statement date | `REFUND_POST_STATEMENT` | 0.90 | Reduce current `O`; prior reported utilisation unchanged; accrue to original month |
| **R-RF-11** | UPI/P2M refund credit matched by VPA/merchant/amount/time | `REFUND_UPI` | 0.85 | Reduce original spend; not income |
| **R-RF-12** | P2P credit “refund / reimbursement” from a person | `REIMBURSEMENT` | 0.60 | Reduce matched split spend; not income; if unmatched, transfer |
| **R-RF-13** | Partial refund, or multiple refunds for one purchase | `REFUND_PARTIAL` | 0.90 | Reduce by each credit; cap total at original |
| **R-RF-14** | Refund in a foreign currency | `REFUND_FX` | 0.80 | Use the INR amount credited; do not recompute markup |
| **R-RF-15** | Credit labelled “reversal of fee / interest” | `FEE_WAIVER` | 0.90 | Reduce the matching fee/interest; not income |
| **R-RF-16** | “Refund failed / reversal failed / not processed” | no event | 0.90 | Do not count; do not change `O` |

**Why the card-side credit is authoritative:** it is the issuer confirming that the card account was credited. A bank debit alone could be a transfer to someone else’s card, a wallet load, or a failed payment. The card-side credit is the strongest evidence that the user’s own card was paid.

### 3.5 Payment vs spend on the same card — decision procedure

1. **Direction.** Credit on the card account = payment/refund/reward. Debit = spend/fee/cash advance. If the SMS is a deposit-account debit, it is not by itself card spend.
2. **Wording.** `payment received`, `payment of`, `bill paid`, `autopay`, `thank you` → payment. `spent`, `debited`, `purchase`, `transaction at` → spend. `refund`, `reversed` → refund. `cashback` → reward.
3. **Counterparty.** `BBPS`, `BILLDESK`, `CRED`, `CHEQ`, `PAYTM`, a card account number, or a card VPA → bill payment. A merchant name → spend.
4. **Last4 semantics.** In a payment SMS, the last4 is the **beneficiary card**, not the source account. In a spend SMS, the last4 is the card used.
5. **Pairing.** If a deposit debit and a card credit match in amount and time, classify both as one `TRANSFER_PAIR`. If only one side is visible, classify that side as a transfer, not spend.
6. **User confirmation.** If the card is not in the user’s wallet, ask once: “Was this a payment to your card?” If yes, add the card; if no, tag gift/other. Never default to spend.

### 3.6 Partial payment, overpayment, late fee, interest, EMI, balance transfer

**Partial payment**

- `paid < TAD` but `paid ≥ MAD`: not past due; no late fee (assuming paid by due date); but the interest-free period is lost and interest applies from the transaction date on the unpaid amount. The user is a “revolver” this cycle.
- `paid < MAD`: past due. Late fee and adverse bureau reporting can follow if the account remains past due for more than three days (2025 Directions; the 2026 amendment effective 1 Apr 2027 modifies the same para).
- Copy: “You paid ₹5,000 of ₹25,000. The ₹20,000 balance will attract interest from the transaction date; the minimum due was ₹1,250.”

**Overpayment / credit balance**

- `paid > TAD`: `O` becomes negative; utilisation 0%; show “₹5,000 credit balance”.
- Not income. Not spend. Do not reduce next month’s spend by the overpayment; it is a card credit that will offset future purchases.
- If the credit balance is large, the issuer may refund it to the bank account on request (RBI 2025 Directions, para 31, for refund credits; overpayment treatment is issuer-specific). Copy: “You have a ₹5,000 credit balance. Use it for future spends or ask the issuer to refund it.”

**Late payment fee**

- Applies only if the account is “past due” for more than three days, per the 2025 Directions. The fee is computed on the **outstanding amount after the due date**, not the total amount due.
- Do not tell the user “you will be charged ₹X” unless the issuer’s fee schedule is known. Say “a late fee may apply; the issuer computes it on the overdue amount.”
- If the user paid at least the minimum by the due date, do not show a late-fee warning; show an interest warning instead.

**Interest on revolving credit**

- If `paid < TAD` by the due date, interest is levied on the outstanding amount, adjusted for payments/refunds/reversals, from the transaction date — not from the due date. The interest-free period is lost.
- Estimate: `Interest_est = O_unpaid × (APR/100) × days/365`. If the user knows the monthly rate `r_m`, use `O_unpaid × (r_m/100) × days/30`. Label the APR as an assumption.
- Example: ₹20,000 unpaid at 42% APR for 30 days ≈ ₹690; at 3.5%/month ≈ ₹700. GST/cess may apply; issuer method may differ.

**EMI conversion**

- The purchase is counted **once** at purchase. Conversion to EMI is a reclassification, not new spend. The monthly EMI debit is `principal` (transfer) + `interest` (spend) + processing fee/GST (spend). The unpaid EMI principal is part of `O` (Model A) or a separate loan (Model B).
- Do not count the EMI debit as spend; do not count the original purchase again.
- If the EMI is “no-cost”, check for processing fee/GST and merchant discount; do not assume zero cost.
- Copy: “₹60,000 purchase converted to 6 EMIs. The purchase is already in your spend; the monthly ₹10,000 is principal + interest, not new spend.”

**Balance transfer**

- Card A credit (reduces A’s `O`), Card B debit (increases B’s `O`). Both are transfers. Fees/interest are spend. Link the two cards; show the promo expiry if known.
- Do not count the BT amount as spend or income; it is debt refinancing.
- Copy: “₹50,000 moved from Card A to Card B. This is a balance transfer, not a new purchase; the fee is ₹1,500.”

### 3.7 Worked examples

**E-6 — the cost of misclassifying a bill payment**

Monthly salary ₹1,00,000; other consumption ₹40,000; card bill payment ₹30,000 (settling last month’s purchases, already counted then).

- Correct: consumption ₹40,000; savings ₹60,000; savings rate **60%**.
- Wrong (bill counted as spend): consumption ₹70,000; savings ₹30,000; savings rate **30%**.
- Error: 30 percentage points, plus a phantom ₹30,000 of “spend”.

**E-7 — same-bank pair**

Savings A/c XX1234 debit ₹15,000 “towards credit card XX5678”; card credit ₹15,000 “payment received”. Pair within T+0. `O_card` decreases by ₹15,000; savings cash decreases by ₹15,000; **no spend, no income**. If only the debit is seen, classify `CARD_PAYMENT_OUT` and leave it unmatched until the card credit arrives.

**E-8 — BBPS/third-party**

Savings debit ₹12,000 “BBPS/CRED for Credit Card XX5678”; card credit ₹12,000. Pair. If the card is not in the app, `CARD_PAYMENT_UNTRACKED`: still a transfer; ask “Which card did this pay?” Do not count as spend.

**E-9 — NEFT to card account**

“NEFT DR ₹7,500 from A/c XX1234 to ICICI Credit Card A/c XX5678, UTR …”; card credit ₹7,500 next day. Pair within T+3. If the NEFT is to a card account the user does not track, still transfer; ask.

**E-10 — partial payment and interest**

Statement: TAD ₹25,000; MAD ₹1,250; due 15 May. User pays ₹5,000 on 10 May.

- `O_after_due = ₹20,000`; no late fee if paid ≥ MAD by 15 May; interest applies from transaction dates.
- Approx interest for 30 days at 3.5%/month: `20,000 × 0.035 = ₹700` (illustrative).
- Next statement: TAD ≈ ₹20,700 + new purchases; the user is revolving.
- If the user pays ₹1,000 (< MAD) on 20 May: past due > 3 days → late fee may apply on the overdue amount; adverse CIC reporting risk; interest on ₹24,000 ≈ ₹840 + fee. Copy must not say “minimum due is enough”.

**E-11 — overpayment**

TAD ₹25,000; user pays ₹30,000. `O = −₹5,000`; utilisation 0%; credit balance ₹5,000. Do not count ₹5,000 as income or spend. Next statement may show a credit; the user can spend against it or request a refund.

### 3.8 Acceptance tests

| ID | Given | Expected |
|---|---|---|
| T-BP-01 | Card credit “payment received ₹15,000” | `CARD_PAYMENT`; `O` −15,000; not income |
| T-BP-02 | Savings debit “BBPS credit card ₹12,000” + card credit | `TRANSFER_PAIR`; no spend |
| T-BP-03 | Savings debit only, card unknown | `CARD_PAYMENT_UNTRACKED`; no spend; review prompt |
| T-BP-04 | NEFT to card, card credit T+2 | Pair within T+3 |
| T-BP-05 | “Payment failed” SMS | No event; `O` unchanged |
| T-BP-06 | Bill reminder TAD 12,345, MAD 620, due 15 May | Statement created; MAD ≤ TAD; due ≥ statement+14 |
| T-BP-07 | Reminder 7 days later with same TAD | No duplicate statement |
| T-BP-08 | Payment ₹30,000 vs TAD ₹25,000 | Credit balance; not income |
| T-BP-09 | Payment ₹5,000 vs TAD ₹25,000, MAD ₹1,250 | Partial; interest warning; no late-fee warning |
| T-BP-10 | Payment ₹1,000 vs MAD ₹1,250, 4 days late | Late-fee risk; past due > 3 days |
| T-BP-11 | Card credit “refund ₹1,500” | Refund; reduce original spend; not bill payment |
| T-BP-12 | Card credit “cashback ₹500” | Reward; not refund/income |

---

## 4. UPI-specific semantics

UPI is not one thing. The same “debited from A/c” SMS can be a merchant purchase, a person-to-person transfer, a credit-card bill payment, a wallet load, an investment, or a loan repayment. The app MUST classify by counterparty type and user intent, not by the word “UPI”.

### 4.1 P2P vs P2M

- **P2P** (person-to-person): the counterparty is a person, usually a VPA like `name@bank` with no merchant registration. In PFM terms it is **not consumption** by default. It may be rent, salary to domestic help, tuition, a gift, a loan to a friend, or a settlement. Allow the user to tag a recurring P2P as rent/education/household; only then does it become spend.
- **P2M** (person-to-merchant): the counterparty is a merchant. It is **spend** if the merchant sells goods/services. It is **not spend** if the merchant is a financial counterparty: credit-card bill, mutual fund, broker, insurer, lender/EMI, wallet load. Classify by merchant category, not by “P2M” alone.

NPCI data shows why this matters: in June 2026, 63.5% of UPI transactions by volume were P2M, but P2P was about 70% of value. Groceries were the top merchant category by volume; debt collection and securities brokers were among the top by value. Average ticket sizes ranged from ₹120 for fast food to ₹8,211 for securities brokers. ([CNBC-TV18, 11 Aug 2026](https://www.cnbctv18.com/photos/india/upi-june-2026-india-payment-habits-top-categories-apps-19965982.htm)) A “UPI spend” number that includes broker transfers and debt collection is meaningless; a number that excludes rent because it is P2P is also wrong. The app needs both the rail and the economic substance.

**Rule:** `UPI + merchant` = spend candidate; `UPI + person` = transfer candidate; `UPI + financial merchant` = transfer/investment/loan; user tag overrides.

### 4.2 Collect / request — never a debit

A UPI **collect request** (“₹2,000 requested by X; approve?”) is not a payment. The money moves only when the payer approves and the debit succeeds.

- Do not create an event for the request.
- Do not count “request received”, “collect request”, “approve request”, “pending” as spend.
- Count only the success message/notification: “paid ₹2,000 to X” or the bank debit.
- If a request is followed by a debit, dedupe the request and the debit.
- A “request declined/failed” is not a spend; optionally show it in a “requests” inbox, never in spend.

### 4.3 Autopay / mandate — recurring, but only the debit is spend

Under RBI’s consolidated e-mandate framework (April 2026), issuers must send a **pre-transaction notification at least 24 hours before** the debit, with merchant, amount, date/time, mandate reference and reason; the customer can opt out or cancel. Recurring transactions up to ₹15,000 do not require additional authentication; certain categories (insurance, mutual funds, credit-card bills) have a higher ₹1 lakh limit. ([ETBFSI, 21 Apr 2026](https://bfsi.economictimes.indiatimes.com/articles/rbi-unveils-comprehensive-e-mandate-rules-for-seamless-recurring-payments/130419072))

Semantics:

- The **pre-debit notice** creates/updates a `RecurringSeries` and a predicted debit. It is **not** spend.
- The **actual debit** is spend (or transfer, for a card bill/investment).
- Do not double count notice + debit.
- If the notice arrives but no debit follows, mark “mandate fired, no debit” — useful for failed autopay/insufficient funds.
- Mandate registration may produce a ₹1/₹2 verification debit; treat it as verification, not spend (or refund it if the merchant refunds).

### 4.4 UPI Lite — on-device, often invisible to SMS

UPI Lite is a small-value on-device wallet: no PIN for each payment, top-up from the bank account. NPCI raised the limits in February 2025 to **₹1,000 per transaction and ₹5,000 total wallet balance**; replenishment is online with AFA. ([Outlook Money, 3 Mar 2025](https://www.outlookmoney.com/banking/upi-lite-is-here-with-enhanced-featurescan-you-use-it-online-know-the-details))

PFM consequences:

- The **top-up** from the bank is a transfer (`TRANSFER_WALLET`), not spend.
- Each **Lite payment** is spend, but many banks do not send an SMS for it. The app may see only the top-up and none of the spends.
- Do not claim completeness. Show “UPI Lite spend may be missing” when a top-up is detected but no matching Lite payments; offer manual entry/statement import.
- If the user imports a UPI Lite statement, dedupe the top-up (transfer) and the individual payments (spend).
- The same logic applies to wallet loads (Paytm/PhonePe/Amazon Pay) and FASTag top-ups: load = transfer; usage = spend if visible.

### 4.5 Splits / group payments

- The payer’s full debit is spend at the merchant.
- Incoming shares from friends are **reimbursements**, not income. Net them against the original spend/category when matched.
- If the app sees only the payer side, show the gross spend; if incoming P2P credits match within 7 days and the user tags “split”, reduce the net spend and show “₹800 reimbursed”.
- Do not count reimbursements as income; that would inflate savings.

### 4.6 Refunds

- A UPI refund credit should link to the original P2M debit by VPA/merchant, amount ≤ original, within 120 days.
- Reduce the original category spend; show the cash inflow in the refund month.
- If the refund is partial, reduce by the refunded amount.
- If the refund is from a person (P2P), treat it as a reimbursement/transfer, not a merchant refund, unless the user says it is a refund.

### 4.7 UPI credit lines (Paytm Postpaid, Amazon Pay Later, Slice, OneCard EMI, bank credit lines on UPI)

- RBI enabled **pre-sanctioned credit lines at banks through UPI** in September 2023 (updated February 2025): the credit line is a funding account, with prior customer consent; terms (limit, period, rate) are set by the bank. ([RBI circular](https://rbi.org.in/Scripts/BS_CircularIndexDisplay.aspx?Id=12532))
- A purchase/draw on a credit line is **spend** (consumption) if it buys goods/services; it is **FINANCING** if it is a cash draw/loan.
- Repayment is a **transfer** (principal) + **spend** (interest/fees).
- The credit line is a liability, not income; its limit is not a bank balance.
- BNPL/UPI credit lines are reported to credit bureaus and form part of credit history (per TransUnion CIBIL’s CEO in the Moneycontrol article above). Do not say “this doesn’t affect your credit”.
- EMI conversion on a credit line follows the EMI rules: purchase counted once; monthly payment = principal transfer + interest spend.

### 4.8 What counts as spend vs transfer

| UPI event | Flow class | Spend? | Why |
|---|---|---|---|
| P2M grocery, food, fuel, pharmacy, quick-commerce | `SPEND` | Yes | Goods/services |
| P2M utility/mobile/broadband | `SPEND` | Yes | Service consumed |
| P2M insurance premium | `SPEND` | Yes | Protection consumed |
| P2M credit-card bill | `TRANSFER` | No | Settles prior card spend |
| P2M mutual fund / broker / demat | `TRANSFER` (`investment`) | No | Asset swap |
| P2M loan EMI / debt collection | `TRANSFER` (principal) + `SPEND` (interest) | Interest only | Debt service |
| P2M wallet load / UPI Lite top-up | `TRANSFER` (`wallet`) | No | Stored value |
| P2M gold purchase (digital gold) | `TRANSFER` (`investment`) or `SPEND` if jewellery | Depends | Ask/merchant category |
| P2P to friend/family | `TRANSFER` | No | Person-to-person |
| P2P to landlord, tagged rent | `SPEND` | Yes | Economic rent |
| P2P to domestic help/tuition, tagged | `SPEND` | Yes | Service |
| P2P to self (own VPA) | `TRANSFER` (`self`) | No | Internal |
| P2P incoming reimbursement for a split | `TRANSFER` (refund of spend) | Negative spend | Not income |
| Collect request / pre-debit notice | No event | No | Money has not moved |
| Failed/declined UPI | No event | No | No money moved |
| UPI Lite payment (if seen) | `SPEND` | Yes | Goods/services |
| Credit-line draw for purchase | `SPEND` | Yes | Consumption on credit |
| Credit-line cash draw | `FINANCING` | No | Loan principal |
| Credit-line repayment | `TRANSFER` + `SPEND` (interest) | Interest only | Debt service |
| Cashback to UPI | `REWARD` | No | Reward |

### 4.9 Worked examples

**E-12 — P2P rent**

Monthly UPI transfer ₹25,000 to `landlord@okhdfcbank`, same amount, same day each month. Default `TRANSFER`; the app detects the monthly cadence and asks “Is this rent?”. If yes, reclassify as `SPEND` (rent) for all occurrences, and include it in rent/income burden. Do not count it as P2P “transfer” forever — that would understate housing cost.

**E-13 — collect request**

“₹2,000 requested by Sharma Store” at 10:00; “Paid ₹2,000 to Sharma Store” at 10:05. Count one spend of ₹2,000. If the user declines, count zero. Never count the request.

**E-14 — UPI Lite gap**

Bank SMS: “₹2,000 added to UPI Lite.” No Lite payment SMS. The app sees a ₹2,000 transfer and no spend. It must show “₹2,000 moved to UPI Lite; Lite spends are not visible in SMS” and not count the top-up as spend or savings.

### 4.10 Acceptance tests

| ID | Given | Expected |
|---|---|---|
| T-UPI-01 | P2M grocery ₹450 | Spend |
| T-UPI-02 | P2M credit-card bill ₹12,000 | Transfer; not spend |
| T-UPI-03 | P2P ₹25,000 monthly to same VPA | Transfer; rent prompt; reclassify on confirm |
| T-UPI-04 | Collect request ₹2,000, declined | No event |
| T-UPI-05 | Pre-debit notice ₹649, debit next day | One spend; notice not counted |
| T-UPI-06 | UPI Lite top-up ₹2,000, no payments | Transfer; data-gap message |
| T-UPI-07 | Split ₹1,200, friend sends ₹800 | Spend ₹1,200; reimbursement ₹800; net ₹400 |
| T-UPI-08 | Credit-line purchase ₹3,000 | Spend; repayment later transfer + interest |
| T-UPI-09 | Failed UPI ₹500 | No event |
| T-UPI-10 | Cashback ₹100 | Reward; not income |

---

## 5. Income, transfers and a trustworthy net cashflow

### 5.1 Income taxonomy

| Income type | Examples | Included in “regular income” for savings rate? |
|---|---|---|
| Salary | Employer credit, “SAL”, “SALARY”, “PAYROLL” | Yes |
| Business/professional receipts | Client payments, “PROFESSIONAL FEES” | Yes, if recurring/identifiable |
| Interest | FD/RD/savings interest | Yes (other income) |
| Dividend | Stocks/MF dividends | Yes (other income) |
| Rent received | Tenant credit | Yes (other income) |
| Gift | Family transfer | No — show separately |
| Refund | Merchant refund | No — negative spend |
| Cashback | Card/UPI reward | No — reward |
| Loan disbursement | Personal loan, gold loan, credit-line draw | No — financing inflow |
| Asset sale / redemption | Mutual fund redemption, property sale | No — transfer/capital |
| Salary advance | Employer advance | No — financing |
| Reimbursement | Employer expense reimbursement | Net against the expense if matched; else other income |

### 5.2 Salary detection

Score a credit event as salary if most of the following hold:

1. Credit to a savings/current account (not a card/wallet).
2. Narration contains `SAL`, `SALARY`, `PAYROLL`, `WAGES`, or a user-entered employer alias.
3. Amount within ±20% of the previous salary (or within ±10% if 3+ prior salaries).
4. Monthly cadence: interval 28–31 days, or same day-of-month ±3 days.
5. Payday near the user’s learned payday (last 3 salary dates).
6. Not from a known own account, investment platform, or lender.

Decision:

- **2+ occurrences + strong narration** → auto-classify salary, confidence 0.9.
- **First occurrence + strong narration + amount plausible** → candidate salary, ask once.
- **Bonus/arrears** (same employer, different amount, off-cadence) → `INCOME_OTHER`, not salary; do not reset the salary baseline.
- **Multiple employers** → keep the largest regular stream as primary; label others “secondary income”.
- **Freelancer/irregular** → use a 3-month rolling median; label “average monthly income”, not “salary”.

Exclusions: reimbursements, refunds, cashback, reversals, loan disbursements, self-transfers, asset redemptions, gifts (unless user tags as regular).

### 5.3 Self-transfer and own-account graph

Build a graph of the user’s own accounts:

- Bank accounts: `bank + last4 + type` (savings/current), optional IFSC.
- Cards: `issuer + last4` (primary/add-on).
- Wallets/UPI Lite: provider + last4/identifier.
- UPI VPAs: user’s own handles, if entered.

Match a debit on own account A to a credit on own account B when:

- Amount equal (±₹1) or fee-adjusted (amount − known fee).
- Time within T+2 (NEFT/IMPS may take a day).
- Narration/VPA indicates self/own/transfer, or the pair is exact and no other explanation.
- Neither side is a card bill payment (those are `CARD_PAYMENT`, a distinct transfer subtype).

Outcomes:

- Both sides matched → `TRANSFER_SELF`; exclude from income and spend.
- One side only → `TRANSFER_SELF_UNMATCHED`; exclude from spend/income; show “₹20,000 moved out — destination not seen”; do not count as spend.
- If the user says it was a gift to a family member, reclassify as `TRANSFER` (gift), not spend.

### 5.4 Card bills, investments, debt service

- **Card bill payment:** `TRANSFER` (`card_bill`); never spend. The purchases were already counted.
- **Investment:** SIP, lump sum, demat, PPF, EPF, NPS, gold scheme → `TRANSFER` (`investment`); part of savings, not consumption.
- **Debt service:** EMI = principal transfer + interest spend. Card EMI = same. Loan disbursement = financing inflow, not income.
- **Insurance:** premium = spend (protection); do not treat as investment unless the user explicitly tags a ULIP/endowment savings component (and even then, show it separately).
- **Tax:** spend (category tax), not a transfer.

### 5.5 Formulas

Let, for a period (calendar month or rolling 30 days):

```
RegularIncome = Σ INCOME(salary, business, interest, dividend, rent)
NetSpend      = Σ SPEND − Σ REFUND
Savings       = RegularIncome − NetSpend
SavingsRate   = 100 × Savings / RegularIncome          if RegularIncome > 0
Investments   = Σ TRANSFER(investment)
DebtPrincipal = Σ TRANSFER(loan_principal) + Σ TRANSFER(card_emi_principal)
CashWithdrawn = Σ CASH(atm)
FreeCash      = RegularIncome − NetSpend − Investments − DebtPrincipal − CashWithdrawn
```

Notes:

- `NetSpend` includes fees, interest, insurance and taxes. It excludes card-bill payments, investments, debt principal, self-transfers, wallet loads and ATM cash.
- `Savings` includes money invested (because it was not consumed). `Investments` is a subset; show “includes ₹X invested”.
- `FreeCash` is what remains in the bank after consumption, investing, debt principal and cash withdrawals. It can be negative if the user funds life from existing savings or borrows; show “drawdown”, not “negative savings”.
- If `RegularIncome ≤ 0`, return `null` for savings rate; do not divide by zero or show −∞.
- For irregular income, use a 3-month rolling median and label “average”.
- If a refund is received in a later month, use **accrual** for `SavingsRate` and category spend (reduce the original month) and **cash** for `FreeCash` (inflow in the refund month). Show both in the “why?” sheet; never let a late refund inflate the current month’s savings rate.

### 5.6 Reconciliation the user can trust

The app should show:

1. **Money in** (regular income + other inflows), **money out** (net spend), **saved** (difference), and **invested** (subset).
2. An “Excluded from spend/income” list with amounts: card bill payments, self-transfers, investments, debt principal, ATM cash, wallet loads.
3. An “Unmatched / needs review” list: one-sided transfers, unknown merchants, failed parses.
4. A “Why is this different from my bank balance?” explainer: the app tracks flows, not balances; it does not know every account; it may miss UPI Lite/cash/wallet spends; transfers are excluded by design.
5. A monthly reconciliation: `opening bank balance + inflows − outflows ± transfers = closing balance` only if the user enters balances; otherwise do not claim it.

Copy example: “September: ₹1,20,000 in, ₹66,500 spent, ₹53,500 saved (44.6%). Excluded: ₹35,000 card bill, ₹10,000 SIP, ₹11,000 loan principal, ₹20,000 self-transfer, ₹5,000 ATM cash.”

### 5.7 Worked example

Salary ₹1,20,000; rent ₹25,000; groceries ₹18,000; dining ₹6,000; fuel ₹4,000; utilities ₹5,000; subscriptions ₹1,500; insurance ₹3,000; card bill ₹35,000; SIP ₹10,000; loan EMI ₹15,000 (interest ₹4,000, principal ₹11,000); self-transfer ₹20,000; ATM ₹5,000.

```
NetSpend = 25,000 + 18,000 + 6,000 + 4,000 + 5,000 + 1,500 + 3,000 + 4,000 = ₹66,500
Savings  = 1,20,000 − 66,500 = ₹53,500
SavingsRate = 44.58%
Investments = ₹10,000
DebtPrincipal = ₹11,000
CashWithdrawn = ₹5,000
FreeCash = 1,20,000 − 66,500 − 10,000 − 11,000 − 5,000 = ₹27,500
```

The ₹35,000 card bill and ₹20,000 self-transfer are excluded; the ₹4,000 loan interest is included in spend; the ₹11,000 principal is a transfer. If the card bill were counted as spend, the savings rate would fall to 15.4% — a catastrophic error.

### 5.8 Acceptance tests

| ID | Given | Expected |
|---|---|---|
| T-IN-01 | Salary ₹1,20,000 credit, “SAL” | Income; savings rate uses it |
| T-IN-02 | Self-transfer ₹20,000 to own account | Excluded from both sides |
| T-IN-03 | Credit-card bill ₹35,000 | Transfer; not spend |
| T-IN-04 | SIP ₹10,000 | Investment; part of savings; not spend |
| T-IN-05 | Loan EMI ₹15,000 (₹4,000 interest) | ₹4,000 spend; ₹11,000 transfer |
| T-IN-06 | ATM ₹5,000 | Cash; not spend/savings |
| T-IN-07 | Refund ₹1,500 for September purchase received October | September spend reduced; October cash inflow |
| T-IN-08 | Loan disbursement ₹2,00,000 | Financing inflow; not income |
| T-IN-09 | Gift ₹11,000 from family | Other inflow; excluded from savings rate |
| T-IN-10 | No income detected | Savings rate null; prompt to add salary |

---

## 6. Recurring detection from SMS alone

### 6.1 Algorithm sketch

1. **Collect candidate debits.** Exclude failed/declined, refunds, reversals, one-off transfers to self, and ATM cash.
2. **Normalize the merchant key.** Lowercase; strip punctuation; remove channel tokens (`UPI`, `POS`, `NEFT`, `IMPS`, `ACH`, `ECS`, `SI`, `BBPS`, `PAYMENT`, `PVT`, `LTD`, `INDIA`, city names); remove reference numbers; use the VPA if present; map aliases (e.g., `NETFLIX`, `NFLX`; `AMAZON`, `AMZN`; `GOOGLE`, `GOOGLEPLAY`).
3. **Group** by merchant key + instrument (card/account/UPI) + currency.
4. **Amount cluster.** Base = median of the first 3 amounts. Match tolerance = `max(₹10, 5% × base)`. Amounts outside tolerance are price-change candidates, not new series.
5. **Cadence.** Compute intervals; classify:
   - weekly: median 7 ± 1 day
   - monthly: median 28–31 ± 2 days
   - quarterly: 90 ± 7 days
   - half-yearly: 182 ± 10 days
   - yearly: 365 ± 14 days
6. **Occurrences.** 3+ = recurring; 2 = tentative; 1 = not recurring. Do not project from one occurrence.
7. **Confidence.**
   ```
   conf = 0.30 × min(n/6, 1)
        + 0.25 × cadence_stability
        + 0.20 × amount_stability
        + 0.15 × merchant_exactness
        + 0.10 × mandate_signal
   cadence_stability = clamp(1 − MADev(intervals)/median(intervals), 0, 1)
   amount_stability  = clamp(1 − MADev(amounts)/median(amounts), 0, 1)
   ```
   Auto-show at ≥ 0.60; tentative at 0.40–0.59; hide below 0.40.
8. **Next due.** For monthly series, anchor to the dominant day-of-month:
   ```
   D_next = add_months_clamped(D_last, 1, anchor_dom)
   ```
   For weekly/quarterly/yearly:
   ```
   D_next = D_last + median_interval_days
   ```
   `add_months_clamped` uses the anchor DOM, clamped to the last day of the month (e.g., 31st → 28/29 Feb). If the predicted date falls on a weekend/bank holiday, show a window `[D_next, D_next + 2]` and say “expected around”, not a guaranteed date.
9. **Status.** `active`, `tentative`, `paused` (user), `possibly_stopped` (missed one cycle + grace), `cancelled` (user).
10. **Dedupe/merge.** Same merchant + amount within 10% + same cadence + overlapping dates → one series. Two profiles on the same streaming service may be two series if amounts differ; ask.

### 6.2 Price-change detection

```
expected = base_amount
delta    = new_amount − expected
pct      = 100 × delta / expected
flag     = abs(delta) > max(₹10, 5% × expected)
annual   = delta × cycles_per_year
```

- If `flag` and the merchant/cadence are unchanged → **price change** event; do not silently update the base.
- After 2 consecutive new amounts, update `base_amount` and show “new price”.
- If the amount changes because of tax/GST, show the gross change and note “may include tax”.
- If the amount drops and the narration says “offer/discount/promo”, tag “discount”, not a permanent price cut.
- EMIs: do not flag price changes unless the bank announces a rate reset; EMI amount changes are usually floating-rate resets.
- Variable bills (electricity, mobile postpaid): a change is not a subscription price change; label “bill amount varies”.

### 6.3 Worked examples

**E-15 — Netflix**

Occurrences: 5 Jan ₹649, 5 Feb ₹649, 5 Mar ₹649, 5 Apr ₹699.

- Base ₹649; tolerance `max(10, 32.45) = ₹32.45`; delta ₹50 → price change; pct 7.7%; annual impact ₹600.
- Next due 5 May; if 5 May is a Sunday, show “expected around 5–7 May”.
- After 5 May at ₹699, update base to ₹699 and keep the price-change history.

**E-16 — gym**

₹1,500 on the 1st for 3 months; next 1st; if the bank debits on the 2nd because of a holiday, the interval MADev is still small; next due anchored to the 1st, with a ±2-day window.

**E-17 — electricity bill**

Amounts ₹1,200, ₹1,450, ₹1,100; same merchant, monthly. It is a recurring **bill**, not a fixed subscription. Show “monthly bill, amount varies”; predict next due; do not show a “price change” alert every month.

### 6.4 Acceptance tests

| ID | Given | Expected |
|---|---|---|
| T-RC-01 | 3 monthly ₹649 Netflix debits | Recurring; next due +1 month; confidence ≥ 0.8 |
| T-RC-02 | 2 occurrences | Tentative; no projection |
| T-RC-03 | 3 monthly debits, amount changes ₹649→₹699 | Price change; not a new series |
| T-RC-04 | Monthly ₹1,500 on 31st | Feb due clamped to 28/29 |
| T-RC-05 | Pre-debit notice + debit | One series; notice not spend |
| T-RC-06 | Missed one cycle | `possibly_stopped`, not auto-cancelled |
| T-RC-07 | Electricity amounts vary ±20% | Recurring bill; no price-change spam |
| T-RC-08 | Two Netflix profiles, different amounts | Two series or user merge; do not average |

---

## 7. Anomaly / insight rules that are useful in India

### 7.1 Guardrails (apply to every rule)

- **Minimum sample.** No category anomaly without at least 3 baseline months (or 4 for robust z).
- **Rupee floor.** No alert for a delta below ₹500 (category) or ₹1,000 (monthly total); no duplicate alert below ₹100.
- **Same-window comparison.** Compare month-to-date with the same day-of-month window in prior months, not a full month. Otherwise every alert on the 5th is false.
- **One alert per merchant/category per week.** No notification storms.
- **Explain the number.** Every alert opens a “why?” sheet with the baseline, the current value, and the transactions.
- **No advice.** Say “this is 2.4× your median”, not “stop eating out”.
- **One-off tags.** Festivals (Diwali, weddings), travel, annual insurance, school fees, medical events should be taggable and excluded from the next baseline.
- **Festival-aware.** October–November and wedding season have genuine spikes; do not call them anomalies if the user tags them.
- **No shaming.** No “you’re spending too much”; no red for normal variation.

### 7.2 Rules table

| ID | Rule | Formula / trigger | Default threshold | User-facing sentence | Common false positives |
|---|---|---|---|---|---|
| **AN-01** | Category month-over-month | `ratio = x_mtd / median(same_window_prev_3)` | ratio ≥ 1.8 and delta ≥ ₹1,000 and n ≥ 3 | “{category} is ₹{x}, {ratio}× your 3-month median of ₹{median}.” | Festival, travel, annual fee, one-off purchase |
| **AN-02** | Robust z-score | `z = 0.6745 × (x − median)/MADev` | abs(z) ≥ 2.5, x ≥ ₹500, n ≥ 4 | “{category} is unusually high for you (z = {z}).” | Small MADev; one-off; new merchant |
| **AN-03** | Total spend vs median | `x_mtd / median(same_window_prev_3)` | ratio ≥ 1.5 and delta ≥ ₹2,000 | “You’ve spent ₹{x} so far, {ratio}× your usual pace.” | Salary timing, festival, rent/EMI |
| **AN-04** | Payday-relative spend | `share = spend_first_7_days / total_spend_month` | share ≥ 0.45 and month ≥ 60% elapsed | “{share}% of this month’s spend happened in the 7 days after payday.” | Salary date change, bonus, travel |
| **AN-05** | Week-1 vs week-4 | compare first 7 days after payday vs last 7 days before next payday | ratio ≥ 2.0 and delta ≥ ₹2,000 | “You spent {ratio}× more in the first week after payday than in the last week.” | Payday shift, festival |
| **AN-06** | Duplicate charge | same merchant, amount diff ≤ max(₹1, 0.5%), time diff ≤ 10 min, both debits, different refs | flag | “Two ₹{x} charges at {merchant} {minutes} minutes apart — possible duplicate.” | Genuine two purchases; split bill; retry |
| **AN-07** | Unused-card subscription | recurring series on card; no other card spend in 90 days | flag | “{merchant} ₹{x}/month is charged to {card}, which has no other spends in 90 days.” | User deliberately keeps the card for this subscription |
| **AN-08** | Rent + EMI burden | `(rent + loan_emi + card_emi) / net_income` | display always; caution ≥ 40%, high ≥ 50% | “Rent and EMIs are {pct}% of your take-home.” | Irregular income; joint household; rent via P2P not tagged |
| **AN-09** | Savings rate | `(regular_income − net_spend)/regular_income` | display; alert on 3-month decline | “You saved {pct}% in {month}, down from {prev}%.” | One-off income/expense; refund timing |
| **AN-10** | Utilisation spike | `U_proj ≥ 80%` or `U_stmt ≥ 30%` | flag | “You’re projected to report {u}% on {date}.” | Large one-off; limit enhancement pending |
| **AN-11** | Minimum-due revolver | `paid < TAD` for 2 consecutive statements | flag | “You’ve paid less than the total due for 2 statements; interest is compounding.” | Refund/credit adjustment; payment in transit |
| **AN-12** | Annual-fee risk | fee posted; no waiver within 30 days; or idle card with fee date known | flag | “Annual fee ₹{fee} posted on {card}; waiver may need ₹{spend} spend.” | Fee already reversed; lifetime-free card |
| **AN-13** | Refund lag | refund expected from merchant; not credited within 7 days | flag | “₹{x} refund from {merchant} hasn’t appeared after {days} days.” | Store credit; chargeback; partial refund |
| **AN-14** | Bill shortfall | `paid < MAD` and due date passed by > 3 days | flag | “You paid ₹{paid}; the minimum was ₹{mad}. A late fee may apply.” | Payment not yet posted; bank holiday |
| **AN-15** | Cash leakage | ATM withdrawals > 20% of spend, or no cash spending recorded | display | “You withdrew ₹{x} cash; cash spending isn’t tracked.” | User records cash manually |

### 7.3 Worked examples

**E-18 — food anomaly**

Baseline monthly food: ₹3,200, ₹3,500, ₹3,800; current month-to-date (same window) ₹8,400.

```
median = 3,500
ratio = 8,400 / 3,500 = 2.4
delta = 4,900
```

Flag AN-01: “Food is ₹8,400, 2.4× your 3-month median of ₹3,500.” The why-sheet lists the ₹4,800 “party order” and lets the user tag “one-off”.

Robust z (if 4 baseline points included): median ₹3,650; MADev ₹300; `z = 0.6745 × 4,750 / 300 = 10.68` — very strong, but with only 4 points the ratio is more interpretable; show the ratio, keep z internal.

**E-19 — duplicate**

Zomato ₹499 at 13:02 and ₹499 at 13:08; different refs; both debits. Flag AN-06. If the first was “failed” and the second “success”, do not flag; count one.

**E-20 — payday share**

Salary on 1st; by 25th, ₹70,000 spent, of which ₹34,000 in the first 7 days. `share = 48.6%`; flag AN-04: “49% of this month’s spend happened in the 7 days after payday.”

**E-21 — rent + EMI**

Rent ₹25,000 + loan EMI ₹15,000 + card EMI ₹5,000 = ₹45,000; net income ₹1,20,000 → 37.5%. Display; caution line at 40%. Do not say “you can’t afford”; say “fixed obligations are 37.5% of take-home”.

**E-22 — unused-card subscription**

Netflix ₹649 on ICICI card; no other ICICI spend in 90 days. Flag AN-07: “Netflix ₹649/month is charged to your ICICI card, which has no other spends in 90 days.” The user may say “keep it”; suppress for 6 months.

### 7.4 Acceptance tests

| ID | Given | Expected |
|---|---|---|
| T-AN-01 | Food 2.4× median, delta ₹4,900 | Alert with ratio and median |
| T-AN-02 | Food 1.2× median | No alert |
| T-AN-03 | Duplicate ₹499 6 min apart | Alert; dismissible |
| T-AN-04 | Failed + success same amount | No duplicate alert |
| T-AN-05 | Rent+EMI 37.5% | Display; no “high” unless ≥ 50% |
| T-AN-06 | Idle card + subscription | Alert; snooze option |
| T-AN-07 | Payment in transit on due date | No late-fee alert until T+1 |
| T-AN-08 | Festival-tagged spend | Excluded from baseline |

---

## 8. Product spec: what the app shows

### 8.1 Screen map

- **Home:** net cashflow, savings rate, top categories, upcoming bills, “needs review”, one insight card.
- **Cards:** per-card carousel with utilisation gauge, statement/due dates, projected utilisation, idle/fee risk, reward reminder.
- **Card detail:** limit history, statement history, transactions, EMI, fees/interest, refunds, bill payments, utilisation chart with statement markers.
- **Bills:** due calendar, total vs minimum, payment status, recurring commitments, price changes.
- **Insights:** anomalies, subscriptions, duplicates, refunds, rent/EMI burden, payday pattern.
- **Settings:** cards, limits, statement days, own accounts, employer, APR assumptions, reporting basis, privacy/retention, export/delete.
- **Onboarding:** SMS permission disclosure, card setup, salary account, own accounts, statement day, first scan.

### 8.2 Credit metrics

| ID | Metric | Formula | Inputs | Edge cases | Display sentence |
|---|---|---|---|---|---|
| **M-01** | Statement utilisation per card | `100 × TAD / L_at_statement`; if no TAD, `100 × max(0,O_stmt)/L` | Latest statement, limit at statement | No statement; limit change; add-on; EMI separate; credit balance | “{card}: {u}% of your limit was on the {stmt_date} statement (₹{tad} of ₹{limit}).” |
| **M-02** | Live utilisation per card | `100 × max(0,O_est)/L_report_now` | Ledger/available limit, limit now | Stale available limit; pending; refunds; EMI | “Right now: about {u}% used (₹{o} of ₹{limit}), based on {source}.” |
| **M-03** | Projected statement utilisation | F-UT-4 | O_est, run-rate, recurring, payments, limit at statement | Unknown statement date; limit change; one-off; refund | “At your current pace you’d report about {u}% on {stmt_date} (₹{o_proj} of ₹{limit}).” |
| **M-04** | Aggregate utilisation | `100 × Σ max(0,O_i) / Σ L_report_i` | All cards | Add-ons; closed cards; negative balances | “Across {n} cards: {u}% (₹{o_total} of ₹{l_total}).” |
| **M-05** | Headroom to 30% | `max(0, 0.30×L_report − O_est)` | Limit, O_est | Limit unknown; temp; EMI | “You have ₹{headroom} of headroom before 30% on this card.” |
| **M-06** | Due-date countdown | `due_date − today` (IST) | Due date, TAD, MAD | Due today; overdue; weekend; partial payment | “{card}: ₹{tad} due in {d} days (by {due_date}). Minimum due ₹{mad}.” |
| **M-07** | Minimum-due gap | `gap = TAD − paid`; `min_gap = MAD − paid` | TAD, MAD, payments since statement | Overpayment; refund; payment in transit | “You’ve paid ₹{paid}; ₹{gap} remains. Paying ₹{min_gap} more clears the minimum, but interest applies to the rest.” |
| **M-08** | Payment status | Classify `PAID_FULL / PAID_MIN / PARTIAL / UNPAID / OVERDUE / OVERPAID` | TAD, MAD, payments, due date | Payment in transit; refund adjusted; multiple payments | “Paid in full on {date}.” / “₹{gap} still due; {days} days left.” |
| **M-09** | Spend-to-statement projection | `S_proj` from F-UT-4 | Cycle spend, recurring, days | Month-end; salary; recurring | “On pace for ₹{s_proj} more by {stmt_date}.” |
| **M-10** | Idle card / fee risk | `days_since_last_txn`; idle if ≥ 90 and O=0; fee date if known | Transactions, fee date | Subscription-only card; add-on; lifetime free | “No spends on {card} in {days} days; annual fee ₹{fee} may post on {date}.” |
| **M-11** | Reward-category reminder | Top category spend this cycle + user-entered reward rule | Card rule, spend | Caps; excluded merchants; no rule | “You’ve spent ₹{x} on {category}; {card} gives {rate} on {category}.” |
| **M-12** | Monthly spend by category | `Σ SPEND − Σ REFUND` by category, calendar month | Classified events | Card bill; EMI; cash; refunds; splits | “{category}: ₹{x} this month ({delta}% vs last month).” |
| **M-13** | Net cashflow | `RegularIncome − NetSpend` | Income, spend, refunds | Transfers; investments; ATM; loan | “{month}: ₹{in} in, ₹{out} out, ₹{net} left ({rate}%).” |
| **M-14** | Savings rate | `100 × Savings / RegularIncome` | Income, net spend | Irregular income; negative; one-off; refunds | “You saved {rate}% of income (₹{amount}); includes ₹{invest} invested.” |
| **M-15** | Income detected | Salary score + cadence | Credits, narration, payday | Reimbursements; multiple employers; freelance | “Salary: ₹{amount} from {employer} on {date}.” |
| **M-16** | Recurring commitments | Sum of active series + next due | Recurring series | Variable bills; paused; price change | “Recurring: ₹{monthly} a month; next {merchant} ₹{amount} on {date}.” |
| **M-17** | Price change | `(new−old)/old` | Series amounts | Tax; one-off; currency; plan change | “{merchant} increased from ₹{old} to ₹{new} (+{pct}%), about ₹{annual} a year.” |
| **M-18** | Category anomaly | Ratio/robust z | Category spend, baseline | Partial month; festival; one-off | “{category} is ₹{x}, {ratio}× your 3-month median of ₹{median}.” |
| **M-19** | Duplicate charge | Same merchant/amount/time | Two debits | Split bill; retry; recurring | “Two ₹{x} charges at {merchant} {minutes} minutes apart — possible duplicate.” |
| **M-20** | Unused-card subscription | Recurring on card with no other spend in 90 days | Series, card spend | Intentional keep; fee | “{merchant} ₹{x}/month is charged to {card}, which has no other spends in 90 days.” |
| **M-21** | Rent + EMI burden | `(rent + loan_emi + card_emi)/net_income` | Rent, EMIs, income | Joint; irregular; P2P rent | “Rent and EMIs are {pct}% of your take-home.” |
| **M-22** | Payday-relative spend | First-7-days share | Salary date, spend | Salary shift; festival | “You spent {pct}% of this month’s spend in the 7 days after payday.” |
| **M-23** | Refund pending | Expected refund not matched in 7 days | Refund SMS, credits | Store credit; chargeback | “₹{x} refund from {merchant} hasn’t appeared after {days} days.” |
| **M-24** | Credit balance | `O < 0` | Card ledger | Overpayment; refund after payment | “{card} has a ₹{x} credit balance — use it or ask the bank to refund it.” |
| **M-25** | Data completeness | `% of spend with source SMS`; unparsed count; UPI Lite detected | Events, sources | No SMS; notification only; CSV | “We classified {pct}% of this month’s alerts; {n} need review.” |
| **M-26** | Bill payment reconciliation | Matched pairs / total card payments | Transfer links | Third-party; NEFT delay; cash | “{n} of {m} card payments matched to a bank debit; {k} unmatched.” |

### 8.2.1 Indian category taxonomy (for M-12 and reward reminders)

Use a fixed top-level taxonomy; free-text merchant names are noisy. Keep “transfer” categories out of spend. Average ticket sizes from NPCI’s June 2026 UPI data are a useful calibration prior: fast food ≈ ₹120, restaurants ≈ ₹173, groceries ≈ ₹213, pharmacy ≈ ₹423, fuel ≈ ₹658, electronics ≈ ₹1,367. ([CNBC-TV18](https://www.cnbctv18.com/photos/india/upi-june-2026-india-payment-habits-top-categories-apps-19965982.htm))

| Category | Indian examples | Default flow class | Notes |
|---|---|---|---|
| Rent / housing | Landlord VPA, housing society, rent merchant | `SPEND` if tagged rent; else `TRANSFER` | P2P rent is common; prompt on monthly same-amount VPA |
| Groceries / quick-commerce | Blinkit, Zepto, Instamart, BigBasket, DMart, kirana | `SPEND` | High-frequency, low-ticket; do not merge with dining |
| Food delivery / dining | Swiggy, Zomato, restaurants, cafes, cloud kitchens | `SPEND` | Separate delivery vs dine-in if the merchant string allows |
| Fuel / EV charging | HP, BP, IOC, Shell, ChargeZone, Statiq | `SPEND` | Net of surcharge waiver; fuel is a distinct reward category |
| Transport | Uber, Ola, auto, metro, bus, FASTag, parking | `SPEND` | FASTag top-up is `TRANSFER`; toll usage is spend if seen |
| Utilities | Electricity, water, gas, broadband, mobile postpaid | `SPEND` | Variable amounts; recurring bill, not subscription |
| Subscriptions | Netflix, Prime, Hotstar, Spotify, YouTube, iCloud, Google One | `SPEND` | Fixed amount + monthly cadence; detect price changes |
| Shopping | Amazon, Flipkart, Myntra, Ajio, Nykaa, Tata Cliq | `SPEND` | Returns/refunds are common; link refunds |
| Health | Pharmacy, hospital, diagnostics, health insurance | `SPEND` | Insurance premium separate from medical spend |
| Education | School fees, tuition, edtech, exam fees | `SPEND` | Often annual/quarterly; large one-offs |
| Travel | IRCTC, airlines, hotels, MakeMyTrip, Cleartrip | `SPEND` | Seasonal; tag one-offs |
| Entertainment | PVR, BookMyShow, gaming, events | `SPEND` | Distinct from subscriptions |
| Personal care | Salon, spa, grooming | `SPEND` | Often UPI P2M micro-spend |
| Household help | Maid, cook, driver, gardener | `SPEND` if tagged; else `TRANSFER` | Often P2P; monthly same-amount prompt |
| UPI micro-spends | Chai, auto, kirana, temple, street vendor | `SPEND` | Small tickets; aggregate, don’t spam alerts |
| Fees / interest | Card fee, late fee, finance charge, forex markup, cash-advance fee | `SPEND` (fee/interest) | Never merge into the purchase category |
| Investments | SIP, demat, PPF, EPF, NPS, gold scheme | `TRANSFER` (`investment`) | Not spend; part of savings |
| Insurance | Life, health, motor, travel | `SPEND` | Protection, not investment (unless user tags ULIP) |
| Taxes | Income tax, advance tax, professional tax | `SPEND` | Separate from fees |
| Gifts / donations | Family gifts, charity, religious donations | `SPEND` or `TRANSFER` | Ask if large/one-off |
| Cash | ATM withdrawal, cash spending | `CASH` / `SPEND` if entered | Do not infer cash spending from withdrawal |

**Rules:** a merchant can map to only one top-level category per user; user overrides win; do not reclassify historical months silently when a mapping changes (show “category updated from {date}”). Quick-commerce and food delivery are separate because users budget them differently. Rent via UPI is spend only after the user confirms; otherwise it stays a transfer and the rent/income metric is understated (show a prompt).

### 8.3 Nudges and copy rules

- **Statement-cycle nudge:** “Utilisation is reported on {12th}; you’re at {42}%.” Show 3 days before the statement if projected > 30%: “Your statement closes in 3 days. You’re at 38%; paying ₹16,000 before {date} would bring the reported balance to 30%.” This is a factual option, not advice.
- **Due-date nudge:** T-7, T-3, T-1, due day. Always show total vs minimum. “Pay ₹12,345 to avoid interest; the minimum ₹620 keeps you current but interest applies to the rest.”
- **Projection nudge:** “At your current pace you’ll spend ₹68,500 by the statement date (34% of limit).”
- **Idle card:** “No spends on {card} in 187 days; annual fee ₹590 may post on 1 Dec.”
- **Reward reminder:** only if the user entered the card’s reward rule; never invent rates. “You’ve spent ₹4,200 on dining this month; your card gives 5X on dining on weekends.”
- **Category nudge:** “Food delivery ₹4,800 this month, 2.4× your 3-month median.”
- **Duplicate:** “Two ₹499 charges at Zomato 8 minutes apart — possible duplicate. [Not a duplicate] [Dispute].”
- **Unused-card subscription:** “Netflix ₹649 is charged to your ICICI card, which has no other spends in 90 days.”
- **Rent/EMI:** “Rent + EMIs are 37% of your take-home.”
- **Savings:** “You saved ₹53,500 (44.6%) in September, including ₹10,000 invested.”
- **Refund:** “₹1,500 refund from Amazon hasn’t appeared after 8 days.”
- **Data gap:** “We haven’t seen any UPI Lite payments. If you use UPI Lite, import its statement or add spends manually.”

**Copy rules**

- No “act now”, no countdown timers, no “last chance”, no “guaranteed”, no “best card”.
- No shaming; no “you’re spending too much”.
- No advice on securities/investments.
- Always say “based on alerts on this phone” when the data may be incomplete.
- Always distinguish “statement date” from “today”.
- Use “estimated” for any number derived from available limit or inference.
- Use “reported” only when quoting a statement figure; otherwise “estimated reported”.
- Notifications: max 1 card nudge/day, quiet hours 21:00–08:00, user controls, separate channels for transaction vs marketing (if any).

### 8.4 Empty and data-quality states

| State | What to show |
|---|---|
| No cards | “Add a card to see utilisation, due dates and bill payments.” |
| No limit | “Add your credit limit; we can’t compute utilisation without it.” |
| No statement | “We haven’t seen a statement SMS yet. Add your statement date.” |
| No salary | “We haven’t identified a salary credit; add it to see savings rate.” |
| UPI Lite detected, no payments | “UPI Lite spends may be missing; import or add manually.” |
| Unparsed alerts | “{n} alerts need review; they’re excluded from totals.” |
| CSV-only user | “CSV import works, but card due dates and limits need manual setup.” |
| Low confidence | “Estimated; check the source.” |

### 8.5 Notification budget and dark-pattern guardrails

- Max 1 card/credit nudge per day; max 1 insight per day; no repeat within 7 days for the same merchant.
- No notifications between 21:00 and 08:00 IST unless the user opts in for due-date alerts.
- No “your score dropped” (the app doesn’t know).
- No “you’re pre-approved” unless the issuer has said so and the user consented.
- No pre-ticked consent; no bundled consent; no “continue” button that hides a data use.
- No fake urgency; no “pay now or your card will be blocked” (the app cannot know).
- No ads inside transaction review; if card offers exist, label “Ad” and separate from metrics.

---

## 9. Risk and compliance

### 9.1 What the app must not do or claim

| Must not | Why | Allowed alternative |
|---|---|---|
| Reproduce a CIBIL/Experian/CRIF score, or show a 300–900 number | Bureau scores are proprietary; the app has no bureau data or formula | Show utilisation, payment punctuality, fee/interest history, and “credit habits, not a score” |
| Say “this will raise your score by X points” | No public formula; outcomes depend on the full bureau file | “Lower statement utilisation may help; bureaus don’t publish exact formulas.” |
| Lend, originate a credit line, or arrange credit | RBI licensing/regulatory perimeter | Display issuer offers as ads with issuer name, APR, fees, “eligibility subject to issuer” |
| Say “guaranteed approval”, “instant approval”, “100% approved” | Misleading; RBI/consumer-protection risk | “Check eligibility with the issuer.” |
| Give unsolicited personalised financial/investment advice | SEBI IA regime for securities; consumer-protection risk | Education, comparisons, “here’s what you spent”; no “invest in X” |
| Store full card number, CVV, expiry, PIN or OTP | RBI CoF tokenisation rules; DPDP; security | Store last4 + issuer only; never parse/store OTPs |
| Upload SMS/financial data to a server or ad SDK | DPDP purpose limitation; Play data policy; trust | On-device parsing; optional encrypted export only at user request |
| Use AccessibilityService to scrape banking apps | Play policy restricts non-accessibility use | Notification listener with disclosure, CSV/PDF import, AA (if online) |
| Say “RBI-approved” or imply affiliation with CIBIL/RBI | Misrepresentation | “We follow applicable RBI card-conduct rules where relevant; we are not a lender or bureau.” |
| Say “bank-grade security” without evidence | Unsubstantiated claim | Describe concrete controls: local encryption, no network, app lock |
| Count a card bill payment as spend | Wrong economics; inflates spend | Transfer; show separately |
| Say “P2P is always spending” or “UPI is spending” | P2P/credit line/financial P2M are not consumption | Classify by counterparty + user tag |
| Say “we see all your spending” | SMS misses UPI Lite, cash, wallets, some merchants | “Based on alerts on this phone; some spends may be missing.” |

### 9.2 RBI credit-card rules that constrain copy and calculations

The RBI’s **Credit Card and Debit Card — Issuance and Conduct Directions** (2022, updated 2024; commercial-bank Directions 2025) matter for any screen that explains bills, minimum due, late fees or refunds. Key points the app must reflect accurately:

1. **Statement timing.** Card issuers must give the customer at least a fortnight between the statement and the due date before interest starts. The app should flag a parsed due date that is less than 14 days after the statement date. ([RBI 2025 Directions, para 24](https://www.rbi.org.in/Scripts/BS_ViewMasDirections.aspx?id=13155))
2. **Minimum amount due.** RBI defines MAD as the amount a cardholder must pay to avoid being treated as overdue, and requires the terms to avoid negative amortisation; it does **not** prescribe a single 5% formula. The app must parse the printed MAD and must not claim “RBI says 5%”. ([RBI 2025 Directions, paras 5(17), 23(2)](https://www.rbi.org.in/Scripts/BS_ViewMasDirections.aspx?id=13155))
3. **Late payment charges.** Card accounts can be reported past due or charged late fees only when past due for more than three days; late fees are computed on the outstanding amount after the due date, not the total amount due. The 2026 amendment (effective 1 April 2027) modifies para 23(5) and ties the >3-day rule to the 2026 asset-classification framework; check the current text after that date. ([RBI 2025 Directions, para 23(5)](https://www.rbi.org.in/Scripts/BS_ViewMasDirections.aspx?id=13155); [2026 Amendment](https://rbidocs.rbi.org.in/rdocs/Notification/PDFs/NOTI29250DAA33E8FD4FB0B7680453870F9447.PDF))
4. **Interest.** Interest is levied only on the outstanding amount, adjusted for payments/refunds/reversals. If the cardholder pays less than the total due, the interest-free period is lost and interest may run from the transaction date. ([RBI 2025 Directions, para 23(6)](https://www.rbi.org.in/Scripts/BS_ViewMasDirections.aspx?id=13155))
5. **Refund adjustment.** Refunds/failed/reversed transactions before the due date are adjusted against the payment due; after payment, the issuer may need explicit consent to adjust beyond a cut-off of 1% of the credit limit or ₹5,000, whichever is lower, and may instead credit the bank account. The app must not assume every refund reduces the card balance. ([RBI 2025 Directions, paras 30–31](https://www.rbi.org.in/Scripts/BS_ViewMasDirections.aspx?id=13155))
6. **Billing-cycle choice.** Cardholders can change the billing cycle at least once. The app’s statement-day setting must be editable, and historical statements keep their original dates. ([RBI 2025 Directions, para 29](https://www.rbi.org.in/Scripts/BS_ViewMasDirections.aspx?id=13155))
7. **Limit increases.** Issuers must not unilaterally enhance credit limits; explicit consent is required. If the app sees a limit increase SMS, it should ask the user to confirm before changing the limit. ([RBI 2025 Directions, para 34](https://www.rbi.org.in/Scripts/BS_ViewMasDirections.aspx?id=13155))
8. **EMI transparency.** EMI conversion must clearly show principal, interest and any upfront discount; interest-bearing EMI must not be camouflaged as no-cost. The app should show the interest component as spend and the principal as transfer. ([RBI 2025 Directions, para 12(3)](https://www.rbi.org.in/Scripts/BS_ViewMasDirections.aspx?id=13155))
9. **Add-on cards.** Add-on cards are issued within the primary cardholder’s credit limit and liability; the app must map them to the parent account, not create a second limit. ([RBI 2025 Directions, para 5(1)](https://www.rbi.org.in/Scripts/BS_ViewMasDirections.aspx?id=13155))
10. **Unused cards.** If a card has not been used for more than one year, the issuer is required to initiate closure after intimation; the app’s “idle card” metric is a useful prompt, not a closure instruction. ([RBI 2025 Directions, para 20](https://www.rbi.org.in/Scripts/BS_ViewMasDirections.aspx?id=13155))
11. **APR disclosure.** Issuers must quote APR for purchases, balance transfers, cash advances, minimum-due non-payment and late payment, with examples. The app should use the user-entered APR and label assumptions; it must not invent an APR. ([RBI 2025 Directions, para 23(1)](https://www.rbi.org.in/Scripts/BS_ViewMasDirections.aspx?id=13155))

**2026 amendment caveat.** The amendment is effective 1 April 2027. If the app ships before that, use the 2025 text; if it ships after, verify the current text. Do not tell users a rule is “new” unless the effective date has passed.

### 9.3 Card data and tokenisation

RBI’s card-on-file (CoF) rules are directly relevant to “don’t store card numbers”:

- With effect from **1 October 2022**, no entity in the card transaction/payment chain other than card issuers and/or card networks may store CoF data; previously stored data must be purged. ([RBI notification, 28 Jul 2022](https://www.rbi.org.in/Scripts/NotificationUser.aspx?Id=12363&Mode=0))
- Therefore the app must store only **last4 + issuer + network + nickname**; never the full PAN, expiry, CVV, PIN, OTP, or a scan of the card.
- If the app ever needs card data for a payment, it must use a token issued by the issuer/network, not store the PAN.
- SMS bodies may contain masked card numbers; that is fine. If an SMS contains a full card number (rare, usually a phishing red flag), redact it before storage and warn the user.

### 9.4 DPDP Act 2023 and DPDP Rules 2025

The Digital Personal Data Protection Act, 2023 (Act 22 of 2023) and the DPDP Rules, 2025 (notified 14 November 2025, with an 18-month phased compliance timeline) apply to the app’s processing of SMS-derived personal data. ([PIB, 14 Nov 2025](https://www.pib.gov.in/PressReleaseIframePage.aspx?PRID=2190014); [Act text](https://www.indiacode.nic.in/bitstream/123456789/22037/2/a2023-22.pdf))

Practical obligations for an offline app:

| Obligation | What it means here |
|---|---|
| **Notice** | A standalone, plain-language notice before SMS access: what data (SMS sender/body/amount/merchant), why (PFM), how long, who to contact, how to withdraw. |
| **Consent** | Free, specific, informed, unconditional, unambiguous, clear affirmative action. Do not bundle SMS consent with terms; do not pre-tick; allow withdrawal as easily as giving. |
| **Purpose limitation** | Use SMS only for PFM features the user sees. No ads, no credit underwriting, no model training, no sharing with lenders/insurers, no “improve our services” blanket. |
| **Data minimisation** | Parse on-device; store derived events, not full SMS; if raw SMS is kept, encrypt and expire it; don’t collect contacts, location, other apps, or call logs. |
| **Storage limitation** | Define retention (e.g., transactions 24 months, raw SMS 30 days, review queue 90 days); delete on request; delete on uninstall. |
| **Accuracy** | Let users correct merchant/category/card; show “based on SMS” and “estimated” labels. |
| **Security** | Encryption at rest (SQLCipher/Keystore), app lock, no backups of the SMS DB, no plaintext logs, no analytics SDK reading SMS. |
| **Breach** | Notify the Data Protection Board and affected users promptly if a breach occurs; keep an incident response runbook. |
| **Grievance** | Named contact/DPO; respond within 90 days under the Rules; in-app grievance flow. |
| **Children** | Do not target children; if a child uses the app, verifiable parental consent is required (unlikely for this product). |
| **SDF** | If the app becomes a Significant Data Fiduciary (volume/sensitivity), additional obligations: DPIA, audit, algorithm due diligence, restrictions on certain data. Plan for it if scale grows. |
| **Cross-border** | Keep data in India; on-device means no transfer. If a cloud feature is added, review DPDP transfer rules and consent. |
| **Penalties** | Up to ₹250 crore for certain violations (security safeguards, breach notification); treat compliance as product-critical, not legal boilerplate. |

**Do not** use “consent” as a blanket shield. DPDP requires purpose limitation and minimisation even with consent. An offline app that parses SMS on-device is in a stronger position than a server-based one, but it still needs notice, consent, retention and grievance.

### 9.5 Google Play SMS policy and alternatives

Google Play restricts SMS and Call Log permissions to default handlers and a narrow set of exceptions. The policy page lists permitted uses and exceptions; “SMS-based financial transactions” and “SMS-based money management” appear as possible exceptions subject to Google Play review and the Permissions Declaration Form, but approval is not guaranteed. Apps that fail to meet policy or lack a declaration may be removed. ([Google Play policy](https://support.google.com/googleplay/android-developer/answer/10208820?hl=en))

What this means:

- **Do not assume `READ_SMS` is available** just because the app is a budget/PFM app. The current repo declares `READ_SMS` and `RECEIVE_SMS`; that is a distribution risk, not a detail.
- If you request SMS access, you must:
  - declare it in Play Console (Permissions Declaration Form);
  - show a prominent disclosure and get affirmative consent;
  - make SMS parsing the core functionality, not a side feature;
  - not exfiltrate non-financial/personal SMS;
  - keep the privacy policy and in-app disclosure accurate.
- **Alternatives** (ranked for this product):
  1. **Notification listener** (`NotificationListenerService`): user grants notification access in Settings; the app reads bank/UPI notifications. It is not a runtime dangerous permission, but Play’s sensitive-data rules and disclosure still apply. It misses SMS-only banks and can miss notifications when the user clears them.
  2. **Default SMS handler:** technically gives SMS access, but it would make the app the user’s SMS app. Not appropriate for a finance app; do not pursue.
  3. **Manual CSV/PDF import:** user-initiated, robust, works for any bank; the repo already has CSV import. Add credit-card statement PDF/CSV parsing.
  4. **Screenshot/OCR import:** user-initiated, on-device; useful for statement summaries; less reliable for line items.
  5. **Account Aggregator (AA):** RBI’s consented data-sharing framework; real-time bank/card data without SMS. It requires network, FIU/AA partnerships and consent artefacts; not compatible with a fully offline app, but a good optional path for a future online mode. ([RBI AA Directions 2025](http://rbidocs.rbi.org.in/rdocs/notification/PDFs/30ACCOUNTAGGREGATOR101020254590C4F91CB3460580538AD3F79BA557.PDF))
  6. **SMS Retriever API:** OTP verification only; not transaction data.
- **Do not** use `AccessibilityService` to scrape banking apps; Play restricts it to accessibility use cases, and it is a security/privacy red flag.
- The policy is changing (effective 27 January 2027 for some call-log verification use cases). Re-check before each release.

### 9.6 Security architecture (minimum)

- No `INTERNET` permission in the offline build (or network only for an explicit optional AA/export feature, behind a separate build/consent).
- SQLCipher-encrypted local DB; key in Android Keystore; no plaintext export by default.
- App lock (biometric/PIN) optional but recommended; `FLAG_SECURE` on screens showing amounts.
- No raw SMS in logs/crash reports; redact amounts/merchants in analytics (if any).
- No backups of the SMS DB (`android:allowBackup="false"` or exclude the DB).
- Export: user-initiated, redacted, password-protected or share-sheet only; warn that CSV is sensitive.
- Delete-all-data flow that removes DB, preferences, exports and review queue.
- Threat model: lost/stolen phone, malicious app with notification access, SMS spoofing, phishing SMS with fake amounts, exported CSV leakage.

### 9.7 Claims register (copy review)

| Don’t write | Write instead | Why |
|---|---|---|
| “Your credit score is 780” | “We can’t see your CIBIL score; here’s your statement utilisation.” | No bureau access; score is proprietary |
| “Guaranteed approval” | “Eligibility is decided by the issuer.” | Misleading; RBI/consumer-protection risk |
| “Increase your score by 40 points” | “Lower statement utilisation may help; bureaus don’t publish exact formulas.” | No guarantee; no public formula |
| “Best credit card” | “Cards you asked to compare, with fees and APR.” | Subjective/misleading |
| “RBI-approved” | “We follow applicable RBI card-conduct rules where relevant; we are not a lender or bureau.” | No approval/affiliation |
| “Bank-grade security” | “Your data stays on your phone; the local database is encrypted.” | Only claim what you do |
| “Free credit score” | “Free utilisation and bill tracker; not a credit score.” | Avoid implying a bureau product |
| “Pay only the minimum” | “The minimum keeps you current; interest applies to the rest.” | Minimum due is not full payment |
| “RBI says 30% utilisation” | “Bureau guidance suggests keeping utilisation below 30%; lower is generally better.” | 30% is CIBIL guidance, not RBI |
| “Your card is inactive” | “No spends seen in 90 days.” | You only see SMS, not all usage |
| “You spent ₹X” | “We saw ₹X in alerts; cash/UPI Lite may be missing.” | Data completeness |
| “This is a transfer, not spend” (without explanation) | “This pays your card bill; the purchases were counted when you made them.” | Trust |

### 9.8 Compliance review checklist

- [ ] No credit score, score band, or score delta anywhere.
- [ ] No lending/credit-line origination; offers are labelled ads with issuer/APR/fees.
- [ ] No “guaranteed approval” or “pre-approved” without issuer evidence.
- [ ] No full card number/CVV/expiry/PIN/OTP stored; last4 only.
- [ ] DPDP notice, consent, purpose limitation, retention, grievance, deletion.
- [ ] Play SMS declaration/exception (if SMS) or notification/CSV alternative.
- [ ] No AccessibilityService scraping.
- [ ] No server upload of SMS/financial data; no ad SDK access.
- [ ] RBI copy checked: 30% is not RBI; minimum due is issuer-set; late fee >3 days; interest from transaction date.
- [ ] Security: encrypted DB, no backups, redacted logs, app lock.
- [ ] Claims register reviewed by legal/compliance.

---

## 10. Correctness pitfalls (implementation checklist)

| Pitfall | Why it breaks | Rule | Test |
|---|---|---|---|
| **Rounding** | Summing rounded rupees loses paise; percentages drift | Store paise; compute in paise; round once at display | T-CP-01 |
| **Statement cycle vs calendar month** | “This month” spend ≠ statement amount; users compare apples to oranges | Label “month” vs “statement cycle”; never mix | T-CP-02 |
| **Timezone** | UTC midnight shifts an IST due date to the previous day | Date-only values in IST; countdown uses IST dates | T-CP-03 |
| **Duplicated alerts** | Bank SMS + UPI notification + merchant SMS → triple count | Dedupe by ref; then amount+last4+time; keep bank SMS authoritative | T-CP-04 |
| **Refund in a later cycle** | Prior statement’s reported utilisation is already fixed | Reduce current `O`; adjust original month for analytics; don’t rewrite prior report | T-CP-05 |
| **Cashback vs reversal** | Cashback is a reward; reversal cancels a charge | Separate `REWARD` vs `REFUND`; never treat cashback as income | T-CP-06 |
| **ATM withdrawal** | Cash is not consumption; cash spending may be untracked | `CASH`; exclude from spend/savings; show “cash spending unknown” | T-CP-07 |
| **Fuel surcharge waived** | Surcharge debit + waiver credit; net fuel | Net fuel spend; waiver not income | T-CP-08 |
| **Forex markup** | INR amount may already include markup | Use printed INR; else convert + markup + GST; don’t double add | T-CP-09 |
| **Annual fee** | Fee is spend; waiver is refund | Fee category; net if waived; not purchase/reward | T-CP-10 |
| **EMI** | Purchase counted once; EMI payment is not new spend | Purchase `SPEND`; EMI principal `TRANSFER`; interest `SPEND` | T-CP-11 |
| **Add-on cards** | Shared limit; separate rows double-count | Parent account; one limit | T-CP-12 |
| **Limit enhancement** | Old statements must keep old limit | `LimitEvent` with effective dates | T-CP-13 |
| **Temporary limit** | Expiry; may not be reported | Use for `A_eff`; `L_report` only if reported | T-CP-14 |
| **Credit balance** | `O < 0`; negative utilisation | U=0; credit badge; not income | T-CP-15 |
| **Minimum due** | Issuer-set; not 5% universally | Parse; label estimate only if missing | T-CP-16 |
| **Late fee** | Only after >3 days past due; on overdue amount | Don’t warn before day 4; don’t compute on TAD | T-CP-17 |
| **Bill payment** | Transfer, not spend | `CARD_PAYMENT`; pair both sides | T-CP-18 |
| **Failed/declined** | No money moved | No event; don’t reduce `O` | T-CP-19 |
| **OTP** | Not a transaction | Reject; never store | T-CP-20 |
| **Collect request** | Not a debit | No event | T-CP-21 |
| **Pre-debit notice** | Not a debit | Schedule only | T-CP-22 |
| **UPI Lite silence** | Top-up seen, spends missing | Transfer top-up; data-gap message | T-CP-23 |
| **P2P vs P2M** | P2P isn’t consumption by default | Transfer; rent tag | T-CP-24 |
| **Self-transfer** | Must not count as income/spend | Own-account graph; exclude both sides | T-CP-25 |
| **Investment** | Transfer, not spend | Savings allocation; not consumption | T-CP-26 |
| **Loan disbursement** | Inflow but liability | `FINANCING`; not income | T-CP-27 |
| **Split bill** | Payer’s gross spend vs reimbursements | Net only matched reimbursements; not income | T-CP-28 |
| **Chargeback** | Provisional credit; may reverse | `REFUND` pending; re-add if reversed | T-CP-29 |
| **Multiple cards same last4** | Different issuers can share last4 | Key on issuer+last4+type | T-CP-30 |
| **Masked accounts** | Same last4 across accounts | Issuer + last4 + type; user confirm | T-CP-31 |
| **Date formats** | `dd-mm-yy`, `dd/mm/yyyy`, `05-May-24` | Parse all; validate; IST | T-CP-32 |
| **Month-end** | 31st → Feb 28/29 | `add_months_clamped` | T-CP-33 |
| **Weekend due date** | Bank may extend; app must not assume | Show printed date + “check bank” | T-CP-34 |
| **SMS truncation/multipart** | Amount/card may split across parts | Join multipart; parse joined body | T-CP-35 |
| **Sender spoofing** | Fake SMS with a bank header | Treat sender as signal; cross-check ref/amount; warn on phishing patterns | T-CP-36 |
| **Language** | Hindi/regional SMS | Support English + Hindi tokens; fall back to amount/verb | T-CP-37 |
| **Merchant descriptors** | `AMZN`, `AMAZON`, `AMAZON PAY` | Alias map; don’t merge unrelated merchants | T-CP-38 |
| **Refund > original** | Could be credit balance or error | Credit balance; not income; review | T-CP-39 |
| **Negative amounts** | Credits shown as negative | Direction + wording; not absolute value | T-CP-40 |

---

## 11. Open questions to verify before ship

1. **Issuer reporting date.** Does each target issuer report at statement date or month-end? Verify with a real bureau report; make “reporting basis” a setting.
2. **Billed vs billed+unbilled.** Which issuers include unbilled transactions in the reported balance? Default to billed, show a range.
3. **Temporary limit reporting.** Is the temp limit included in the reported credit limit? Ask the user / test.
4. **EMI reporting.** Is card EMI principal inside the card balance or a separate loan? Model A/B setting.
5. **BBPS coverage.** After the July 2024 mandate, which issuers/aggregators route card bills via BBPS? Treat BBPS as a strong signal, not a hard rule.
6. **UPI Lite limits.** Current NPCI limits (₹1,000/₹5,000 as of Feb 2025) may change; fetch before each release.
7. **E-mandate limits.** The April 2026 framework’s ₹15,000/₹1 lakh thresholds may change; fetch the current RBI text.
8. **Play policy.** The SMS/Call Log policy is being updated (some changes effective 27 Jan 2027); re-check before release.
9. **RBI 2026 amendment.** Effective 1 April 2027; update late-fee/CIC copy then.
10. **Account Aggregator.** If adding an online mode, confirm FIU/AA partnership, consent artefact, and data-localisation posture.
11. **State-level professional tax / stamp duty** not relevant to card semantics; don’t model.
12. **Credit-card rewards rules.** Do not hard-code issuer reward rates; make them user-entered or issuer-provided with a date.

---

## Appendix A — Formula sheet (quick reference)

```
# Utilisation
U_card   = 100 × max(0,O) / L_report                  (L_report > 0)
U_agg    = 100 × Σ max(0,O_i) / Σ L_report_i
U_live   = 100 × max(0,O_est) / L_report
U_proj   = 100 × max(0, O_est + S_proj − P_sched) / L_report(statement_date)

# Outstanding
O        = TAD + debits_after_stmt − credits_after_stmt        (S2)
O        = L_sanctioned + L_temp − A_issuer                    (S1, Model A)
O_card   = L_sanctioned + L_temp − A_issuer − B_blocked        (S1, Model B)

# Projection
d_elapsed   = max(1, date(t) − date(cycle_start) + 1)
d_remaining = max(0, date(statement_date) − date(t))
S_run_rate  = S_discretionary_cycle / d_elapsed
S_proj      = S_recurring_known + S_run_rate × d_remaining

# Headroom
A_eff        = max(0, L_sanctioned + L_temp − O_est − B)       [Model B]
Headroom_30  = max(0, 0.30 × L_report − O_est)

# Late fee / interest
LateFeeApplies = (today > due_date + 3) AND (paid < MAD)
Interest_est   = O_unpaid × (APR/100) × days/365
Interest_est   = O_unpaid × (r_month/100) × days/30            (if monthly rate known)

# Cashflow
RegularIncome = Σ INCOME(salary, business, interest, dividend, rent)
NetSpend      = Σ SPEND − Σ REFUND
Savings       = RegularIncome − NetSpend
SavingsRate   = 100 × Savings / RegularIncome                  (RegularIncome > 0)
Investments   = Σ TRANSFER(investment)
DebtPrincipal = Σ TRANSFER(loan_principal) + Σ TRANSFER(card_emi_principal)
CashWithdrawn = Σ CASH(atm)
FreeCash      = RegularIncome − NetSpend − Investments − DebtPrincipal − CashWithdrawn

# Recurring
base        = median(first_3_amounts)
tolerance   = max(₹10, 0.05 × base)
conf        = 0.30×min(n/6,1) + 0.25×cadence_stability + 0.20×amount_stability
            + 0.15×merchant_exactness + 0.10×mandate_signal
D_next      = add_months_clamped(D_last, 1, anchor_dom)        (monthly)
D_next      = D_last + median_interval_days                    (other cadences)

# Anomaly
ratio       = x / median(same_window_prev_3)
robust_z    = 0.6745 × (x − median) / MADev
MADev       = median({abs(b − median)})       # median absolute deviation; not Minimum Amount Due

# Duplicate
same_merchant AND abs(a1 − a2) ≤ max(100, 0.005 × max(a1,a2))
AND abs(t1 − t2) ≤ 10 minutes AND both debits AND different refs

# Countdown
days_due = due_date − today                                    (IST dates)
```

## Appendix B — SMS parsing grammar (illustrative, not exhaustive)

```
amount      := (Rs|INR|₹)\.?\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?
             | [0-9][0-9,]*(?:\.[0-9]{1,2})?\s*(Rs|INR|₹)
             | (Rs|INR|₹)\.?\s*[0-9][0-9,]*\s*/-
card4       := (card|cc).{0,25}?(ending|xx|\*+)?\s*([0-9]{4})
acct4       := (a/c|acct|account).{0,25}?(xx|\*+)?\s*([0-9]{4})
avl         := (avl|available|avail)\s*(lmt|limit)\.?\s*:?\s*(amount)
total_limit := (total|sanctioned|credit)\s*limit\s*:?\s*(amount)
tad         := (total\s*(amount\s*)?due|total\s*due|tad)\s*:?\s*(amount)
mad         := (minimum\s*(amount\s*)?due|min\.?\s*due|mad)\s*:?\s*(amount)
due_date    := (due\s*(date|on)|payment\s*due)\s*:?\s*(date)
stmt_date   := (statement|bill)\s*(date|dated|generated)\s*:?\s*(date)
date        := [0-9]{1,2}[-/][0-9]{1,2}[-/][0-9]{2,4}
             | [0-9]{1,2}\s*[A-Za-z]{3,9}\s*[0-9]{2,4}
vpa         := [A-Za-z0-9._-]{2,}@[A-Za-z]{2,}
ref         := (ref|rrn|txn|utr|chq|cheque)\s*(no\.?|id)?\s*:?\s*([A-Z0-9]{6,})
foreign_amt := (USD|EUR|GBP|AED|SGD|JPY|AUD|CAD)\s*([0-9][0-9,.]*)
```

**Pre-parse reject list:** OTP/one-time password/verification code; promotional (“offer”, “win”, “apply now”, “limited period”, “cashback up to”) without a transaction verb; failed/declined/not processed; collect request/approve request; “will be debited” (schedule, not event); balance-only messages; “your card is blocked” (service, not transaction).

**Post-parse validation:** amount > 0; amount ≤ ₹10 crore; card4/account4 plausible; date within ±400 days for imports; due date ≥ statement + 14 days else flag; `0 ≤ MAD ≤ TAD`; currency INR unless foreign_amt present.

## Appendix C — Consolidated worked examples (₹)

| Example | Scenario | Correct answer | Common wrong answer |
|---|---|---|---|
| E-1 | Statement ₹42,000; spend ₹12,000; refund ₹1,500; limit ₹2,00,000; 10/21 days; recurring ₹2,500 | Live 26.25%; projected 40.1%; with ₹20,000 pre-statement payment 30.1% | Ignoring refund; adding refund as spend; using 30 days instead of 21 |
| E-2 | Available ₹2,10,000; L ₹3,00,000; temp ₹50,000; EMI ₹40,000 | O ₹1,40,000; 46.7% (or 40.0%) | 33.3% by ignoring EMI; 46.7% vs 40.0% temp confusion |
| E-3 | Refund ₹10,000 after statement ₹60,000 | Live 25%; prior 30% unchanged | Changing prior statement to 25% |
| E-4 | Limit ₹1,00,000→₹2,00,000 mid-cycle | Old statement 45%; new 25% | Recomputing old as 22.5% |
| E-5 | 80% card + 2.5% card | Aggregate 18% | Average 41.25% |
| E-6 | ₹30,000 card bill counted as spend | Savings 60% | Savings 30% |
| E-7 | Same-bank ₹15,000 pair | Transfer | Spend ₹15,000 |
| E-8 | BBPS ₹12,000 pair | Transfer | Spend ₹12,000 |
| E-9 | NEFT ₹7,500 pair | Transfer | Spend ₹7,500 |
| E-10 | TAD ₹25,000; pay ₹5,000; MAD ₹1,250 | Interest on ₹20,000; no late fee | “Paid, no issue” |
| E-11 | TAD ₹25,000; pay ₹30,000 | Credit balance ₹5,000; U=0 | Income ₹5,000; negative spend |
| E-12 | P2P rent ₹25,000 | Spend if tagged rent | Transfer forever (understates housing) |
| E-13 | Collect ₹2,000 then paid | One spend | Two spends |
| E-14 | UPI Lite top-up ₹2,000 | Transfer + data gap | Spend ₹2,000 |
| E-15 | Netflix ₹649→₹699 | Price +7.7%; ₹600/yr | New series; no alert |
| E-16 | Gym on 1st, holiday | Next due 1st ±2 days | 2nd permanently |
| E-17 | Electricity varies | Recurring bill; no price-change spam | Price change every month |
| E-18 | Food ₹8,400 vs ₹3,500 | 2.4× alert | Compare full prior month; false |
| E-19 | Two ₹499 6 min apart | Duplicate alert | Count both silently |
| E-20 | 49% spend in first 7 days | Payday alert | No insight |
| E-21 | Rent+EMI 37.5% | Display; no “high” | “You can’t afford” |
| E-22 | Netflix on idle card | Unused-card subscription | Miss fee risk |
| E-23 | Salary ₹1,20,000; spend ₹66,500 | Savings 44.6%; free cash ₹27,500 | Count card bill; savings 15.4% |
| E-24 | Fuel ₹2,000 + ₹20 surcharge − ₹20 waiver | Net ₹2,000 | ₹2,020 + income ₹20 |
| E-25 | USD 100 at ₹83, 3.5% + 18% GST | ₹8,642.79 | ₹8,300 or ₹8,590.50 |

## Appendix D — Glossary

- **TAD** — Total Amount Due on the statement.
- **MAD** — Minimum Amount Due; issuer-defined amount to avoid being treated as overdue. Do not confuse it with **MADev**.
- **MADev** — Median absolute deviation; a robust dispersion measure used in anomaly detection (AN-02). Not the same as Minimum Amount Due.
- **AZEO** — All Zero Except One; a statement-date optimisation heuristic (not an Indian bureau rule).
- **BBPS** — Bharat Bill Payment System; RBI-regulated interoperable bill-payment network operated by NPCI BharatBillPay.
- **CoF** — Card-on-File; stored card credentials. Only issuers/networks may store actual card data in India since 1 Oct 2022.
- **DLT** — TRAI’s Distributed Ledger Technology for registered commercial SMS headers/templates.
- **DPDP** — Digital Personal Data Protection Act, 2023; Rules 2025.
- **EMI** — Equated Monthly Instalment.
- **P2P / P2M** — Person-to-person / person-to-merchant UPI payments.
- **UPI Lite** — On-device small-value UPI wallet (₹1,000/txn, ₹5,000 balance as of Feb 2025).
- **Revolver** — A cardholder who pays less than the total amount due and carries a balance.
- **Reported utilisation** — The utilisation a bureau is likely to compute from the issuer’s periodic report; typically based on the statement balance.
- **Statement cycle** — The period between two statement dates (e.g., 13th to 12th).
- **Grace period / interest-free period** — The period from transaction date to due date during which payment in full avoids interest; lost if any previous balance is carried.

## Appendix E — Sources

Accessed 25 Oct 2026. Primary regulators first; secondary sources are used only where the primary page is not machine-readable or for market context.

| # | Source | Used for |
|---|---|---|
| 1 | [RBI — Commercial Banks: Credit Cards and Debit Cards — Issuance and Conduct Directions, 2025](https://www.rbi.org.in/Scripts/BS_ViewMasDirections.aspx?id=13155) | Billing, MAD, late fee, interest, refunds, limit changes, add-on, EMI, APR, unused cards |
| 2 | [RBI — Credit Card and Debit Card — Issuance and Conduct Directions, 2022 (updated 2024)](https://www.rbi.org.in/Scripts/BS_ViewMasDirections.aspx?id=12300) | Predecessor rules; continuity |
| 3 | [RBI — Amendment Directions, 2026 (effective 1 Apr 2027)](https://rbidocs.rbi.org.in/rdocs/Notification/PDFs/NOTI29250DAA33E8FD4FB0B7680453870F9447.PDF) | >3-day past-due/CIC reporting; late fee on overdue amount |
| 4 | [RBI — Restriction on Storage of Actual Card Data (CoF), 28 Jul 2022](https://www.rbi.org.in/Scripts/NotificationUser.aspx?Id=12363&Mode=0) | No full card storage after 1 Oct 2022 |
| 5 | [RBI — Operation of Pre-Sanctioned Credit Lines at Banks through UPI (updated 12 Feb 2025)](https://rbi.org.in/Scripts/BS_CircularIndexDisplay.aspx?Id=12532) | UPI credit lines |
| 6 | [RBI — Digital Lending Directions, 2025](https://website.rbi.org.in/en/web/rbi/-/notifications/reserve-bank-of-india-digital-lending-directions-2025) | Lending-adjacent compliance, KFS/APR, no automatic limit increase |
| 7 | [RBI — Account Aggregator Directions, 2025](http://rbidocs.rbi.org.in/rdocs/notification/PDFs/30ACCOUNTAGGREGATOR101020254590C4F91CB3460580538AD3F79BA557.PDF) | Consented data-sharing alternative |
| 8 | [RBI e-mandate framework, Apr 2026 — ETBFSI](https://bfsi.economictimes.indiatimes.com/articles/rbi-unveils-comprehensive-e-mandate-rules-for-seamless-recurring-payments/130419072) | 24-hour pre-debit notice; ₹15,000/₹1 lakh limits |
| 9 | [TransUnion CIBIL — Common credit mistakes](https://www.cibil.com/blog/some-of-the-common-credit-mistakes-to-avoid) | 30% utilisation guidance |
| 10 | [Moneycontrol — CIBIL CEO on statement-date reporting](https://www.moneycontrol.com/news/business/personal-finance/exceeding-credit-card-limit-but-clearing-it-before-statement-date-will-it-still-show-high-utilisation-13644242.html) | Reported balance depends on statement generation; BNPL/UPI credit lines reported |
| 11 | [CNBC-TV18 — RBI BBPS mandate for card bills, Jul 2024](https://www.cnbctv18.com/personal-finance/credit-cards-payments-news-rules-impact-july-1-rbi-bills-cred-phonepe-bharat-bill-19432820.htm) | BBPS routing as a detection signal |
| 12 | [Outlook Money — UPI Lite limits, Feb 2025](https://www.outlookmoney.com/banking/upi-lite-is-here-with-enhanced-featurescan-you-use-it-online-know-the-details) | ₹1,000/txn, ₹5,000 wallet, no PIN |
| 13 | [CNBC-TV18 — UPI June 2026 statistics](https://www.cnbctv18.com/photos/india/upi-june-2026-india-payment-habits-top-categories-apps-19965982.htm) | P2M/P2P mix; Indian category ticket sizes |
| 14 | [Google Play — SMS/Call Log permission policy](https://support.google.com/googleplay/android-developer/answer/10208820?hl=en) | SMS restriction; exceptions; alternatives |
| 15 | [Android — NotificationListenerService](https://developer.android.com/reference/android/service/notification/NotificationListenerService) | Notification-listener alternative |
| 16 | [DPDP Act, 2023 (India Code)](https://www.indiacode.nic.in/bitstream/123456789/22037/2/a2023-22.pdf) | Consent, purpose limitation, minimisation, breach, penalties |
| 17 | [PIB — DPDP Rules notified, 14 Nov 2025](https://www.pib.gov.in/PressReleaseIframePage.aspx?PRID=2190014) | 18-month phased compliance; consent notices; breach; 90-day rights |
| 18 | [TRAI — DLT](https://trai.gov.in/) | Registered SMS headers/templates |
| 19 | [NPCI — UPI products](https://www.npci.org.in/product/upi) | UPI rails, P2P/P2M, Lite, AutoPay |
| 20 | [NPCI BharatBillPay](https://www.bharat-connect.com/) | BBPS biller categories |
| 21 | [Outlook Money — RBI rounding and late-fee explainer](https://www.outlookmoney.com/explainer/rbi-rules-on-rounding-off-and-credit-card-late-fees) | Rounding, 3-day past-due, fee on outstanding |
| 22 | [TaxGuru — RBI 2026 amendment summary](https://taxguru.in/rbi/rbi-commercial-banks-credit-cards-debit-cards-issuance-conduct-amendment-directions-2026.html) | Effective date and amendment text |
| 23 | [CIBIL — Understanding your CIBIL score (PDF)](https://www.cibil.com/content/dam/cibil/consumer/CIBIL-Report-Understanding.pdf) | Bureau education; score vs report |
| 24 | [RBI — Master Directions index](https://www.rbi.org.in/Scripts/BS_ViewMasterDirections.aspx) | Locating current directions |

> **Source hygiene.** RBI pages change; the 2026 amendment is effective 1 April 2027, and the e-mandate/UPI limits may change. Re-fetch the primary text before each release. Where a secondary source is cited for a rule, the primary RBI text controls.

## Appendix F — Implementation checklist for the current repo

Based on `docs/ARCHITECTURE.md` (the current app drops credits/refunds and has no income/limit/statement model), the minimum changes are:

1. **Stop dropping credits.** Parse `credited`, `refund`, `reversed`, `cashback` as first-class events; the current parser’s rejection of credit wording (`ARCHITECTURE.md` §SMS parsing, step 2) is the root cause of phantom spend.
2. **Add `CardAccount`, `Plastic`, `LimitEvent`, `Statement`.** The current `card_issuer + card_last_digits` grouping is not enough for limits, add-ons, statement cycles or utilisation.
3. **Add `flow_class` + `TransferLink`.** The current `expense`/`transfer` dichotomy cannot distinguish card bill (transfer), investment (transfer), loan principal (transfer) and interest (spend).
4. **Add bill-reminder parsing.** The current parser treats a statement SMS as noise; parse TAD/MAD/due date into a `Statement`.
5. **Add own-account graph.** The current app has no way to exclude self-transfers or match card bill payments.
6. **Add recurring series.** No subscription/EMI detection today; implement §6.
7. **Fix dedupe.** The current ±2-minute same-amount/different-sender rule can merge genuine transactions; prefer reference ID, then amount+last4+time, and never silently drop when a ref exists.
8. **Unify the Dart/Kotlin parsers.** The current dual parser has already drifted; use one source of truth and a golden SMS corpus with expected events.
9. **Plan the Play distribution path.** `READ_SMS`/`RECEIVE_SMS` are restricted; build the notification-listener and CSV/PDF import paths now, not after rejection.
10. **Add a data-quality screen.** “Based on {n} alerts; {m} unclassified; UPI Lite may be missing” is a trust feature, not a nice-to-have.
11. **Add a privacy/retention screen.** DPDP notice, consent withdrawal, delete-all-data, raw-SMS retention, export redaction.
12. **Add a compliance copy test.** Snapshot-test forbidden strings (“credit score”, “guaranteed”, “RBI says 30%”, “pre-approved”) in UI copy.

---

*End of spec.*

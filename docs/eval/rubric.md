# Evaluation rubric — four independent reviewers

Each reviewer scores the build out of 10 and must return: **score**, **five strongest things**, **everything that blocks a 9.5**, and **the three changes with the highest score-per-hour**. Reviewers work independently; a review is only valid if it names specific files, screens or behaviours.

A build is shippable at the target bar when **all four scores are ≥ 9.5**.

---

## 1. Frontend app developer (weighted /100)

| # | Criterion | Weight |
|---|---|---|
| F1 | Visual craft: hierarchy, spacing rhythm, type scale, colour discipline, no raw hex outside tokens | 20 |
| F2 | Motion & feedback: transitions, loading skeletons, empty states, optimistic updates, haptics | 15 |
| F3 | Layout robustness: 360 dp at 1.0× and 1.3× text, no overflow, long merchant names, RTL-safe | 20 |
| F4 | Component reuse and code quality: one kit, no duplication, sensible widget decomposition, no `setState` spaghetti | 15 |
| F5 | Accessibility: contrast, semantics labels, 48 dp targets, screen-reader sentences for charts | 15 |
| F6 | Performance: rebuild scope, const usage, painters vs images, list virtualisation | 15 |

Automatic fail: visible layout overflow; a screen that cannot show an empty state; any screen where money formatting is inconsistent.

## 2. Principal engineer (weighted /100)

| # | Criterion | Weight |
|---|---|---|
| E1 | Architecture: one source of truth per concern, no duplicated business logic, clean layering | 20 |
| E2 | Correctness of the money maths: paise integers, transfers vs spend, dedupe, statement cycles | 20 |
| E3 | Testability: pure functions, injected clocks, corpus-based tests with real pass rates | 15 |
| E4 | Failure handling: permission denied, unsupported platform, empty inbox, partial parse, corrupt row | 15 |
| E5 | Data safety: migration path, no destructive writes, offline by construction, no PII in logs | 15 |
| E6 | Operability: build reproducibility, analyse clean, documented trade-offs, realistic roadmap | 15 |

Automatic fail: duplicated parser/business logic across languages; `double` money; a test suite that passes by asserting nothing; an unrecoverable migration.

## 3. India financial expert (weighted /100)

| # | Criterion | Weight |
|---|---|---|
| M1 | Correct financial semantics: UPI P2P vs P2M, transfers, refunds, EMI, bill payments, cash | 20 |
| M2 | Credit-card intelligence: utilisation basis, statement date vs due date, minimum due, projection | 20 |
| M3 | SMS reality: bank templates, DLT headers, amount traps, duplicate alerts, OTP handling | 20 |
| M4 | Insight quality: useful, non-obvious, honest, no false precision, no advice that could harm | 15 |
| M5 | Compliance & claims: no score reproduction, no lending, RBI/CIBIL framing, DPDP-safe by design | 15 |
| M6 | India-specific usefulness: categories that match how Indians actually pay, ₹ formatting, festivals/salary cycles | 10 |

Automatic fail: counting a card-bill payment as spend; calling 30 % an RBI rule; presenting a credit score; recommending a financial product.

## 4. Ordinary end user (weighted /100)

| # | Criterion | Weight |
|---|---|---|
| U1 | First-run clarity: can I tell what this does and why it wants SMS access in 15 seconds? | 20 |
| U2 | Daily glance: do I get my answer (how much, is anything wrong) without scrolling or tapping? | 25 |
| U3 | Trust: does it explain itself, and do the numbers look right for my life? | 20 |
| U4 | Effort: how many taps to categorise, scan, fix a mistake? Any dead end? | 15 |
| U5 | Tone & language: plain English, no jargon, no guilt, no fear-mongering, Indian context | 10 |
| U6 | Would I keep it installed after a month? Would I show it to a friend? | 10 |

Automatic fail: any screen where I cannot tell what a number means; a scary number with no explanation; a permission request with no reason.

---

## Scoring anchors

| Score | Means |
|---|---|
| 9.5–10 | Better than the best app I have used for this job; nothing I would change before shipping |
| 8.5–9.4 | Genuinely good, a handful of visible rough edges |
| 7–8.4 | Works, but feels like a first version |
| 5–6.9 | Functional prototype with real gaps |
| < 5 | Not usable as a product |

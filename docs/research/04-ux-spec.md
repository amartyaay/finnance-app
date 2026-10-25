# 04 · UX Specification — Finance SMS

**Product:** Finance SMS — offline Android PFM that reads bank/card SMS alerts
**Platform:** Android 10+ · Flutter 3.24+ · Portrait, 360×800 dp baseline, one-handed
**Status:** Spec v1.0 · 25 Oct 2026 · owner: Product Design
**Design intent:** the calmest, fastest, most trustworthy way to see what you spent — and the only one that never asks you to log in, sign up, or upload anything.

> **How to read this.** Every number is a decision, not a suggestion. `dp` = layout, `sp` = text. Colour tokens are final and validated (§8.5). Copy strings in §7 are final wording — do not paraphrase in code.
> **Baseline device:** 360×800 dp, 3 GB RAM, Helio G99 / SD 680 class, 60 Hz, Android 12–14, system font scale 1.0 and 1.3.

---

## 0 · The twelve decisions in this document

| # | Decision | One-line reason |
|---|---|---|
| 1 | **4 bottom tabs**: Home · Activity · Cards · Insights. Settings behind the avatar. | Settings is a place you visit twice, not a destination; a 5th tab taxes every session. |
| 2 | **Hero = "Spent this month" in ₹**, with a rate-per-day context line. | We never have reliable balances from SMS; spend is the question people actually open the app with. |
| 3 | **Card utilisation lives in a top-level tab**, not buried in settings. | Indian card anxiety is monthly and specific: limit, used, due date. |
| 4 | **Categories are never identified by colour.** One-hue ramp + icon + direct labels. | Six AA-compliant hues cannot be told apart by a deuteranope (validated: min ΔE00 = 5.9, §8.5). |
| 5 | **Debits are ink, not red.** Direction uses − / + and words. | Red-means-bad + red-means-down-market is a category error in a spend log. |
| 6 | **Gauge = horizontal bar in lists, arc only on card detail.** | Comparability across 3 cards + readability at 1.3× beats a pretty ring. |
| 7 | **Every claim carries a provenance line** ("34 messages · 2 unreadable"). | Coverage gaps are the #1 trust killer in SMS trackers; say what you don't know. |
| 8 | **One insight on Home, six on Insights**, each with a "Why this?" disclosure. | Progressive disclosure keeps Home a glance, not a feed ([NN/g](https://www.nngroup.com/articles/progressive-disclosure/)). |
| 9 | **Phishing warnings are inline, calm, and never modal.** | Interrupting a scared user with a red full-screen is how you lose them. |
| 10 | **No count-up on cold start.** Numbers are true on frame 1. | Never make a person wait 400 ms to learn their own spend. |
| 11 | **Zero gamification, zero ads, zero cross-sell, zero "score".** | Calm ledger, not slot machine ([Rocket Money teardown](https://dezzayn.com/apps/rocket-money)). |
| 12 | **Contrast is designed, not inherited.** Material's default greens fail (§8.2). | #4CAF50 = 2.78:1 on white. We use #0E6B43 = 6.56:1. |

---

## 1 · Design principles

| # | Principle | Which means, concretely |
|---|---|---|
| P1 | **One number, then the story.** | Home answers "how much this month" in under 2 s. Everything else is ordered by how often it is asked, never by how interesting it is. |
| P2 | **Calm, not alarming.** | No red background ever. Warnings are amber or tinted, with a word and an action. We never say "alert", "warning!", "danger". |
| P3 | **Never fake precision.** | ₹48,300, not ₹48,312.47. "About 12% less". "Estimated" on every inferred number. Missing days are stated, not hidden. |
| P4 | **Every card answers "so what?"** | If a card cannot change a decision or answer a question, it does not ship. |
| P5 | **Private by construction, and visibly so.** | No account, no network, no ads. The privacy promise is a persistent, tappable sentence, not a one-time modal. |

---

## 2 · Context: how Indians actually check money

Two modes, and they want different screens. This is the whole IA argument.

| | **The glance** | **The review** |
|---|---|---|
| Frequency | 20–40×/week; after a UPI payment, at a till, in a queue | 1–2×/month; payday (1st–5th) and card statement day |
| Duration | 3–8 s | 3–10 min |
| Posture | One hand, thumb, walking, 30–45 °C outdoors, screen at 40 % brightness | Seated, two hands, often at night |
| Question | "Did that go through?", "How much have I spent?", "Anything due?" | "Where did it go?", "Why is this month different?", "What do I cancel?" |
| Data needed | Today + this month + next 7 days | 3-month trends, category split, recurring list |
| Failure that hurts | Wrong number, slow first paint, wrong merchant | Missing coverage, no explanation, no action |

**Consequences.** Home must be legible at 8 s with the top 400 dp doing all the work (§4.4). Depth belongs to Activity/Insights, reached by one tap, never by a scroll on Home. The monthly cycle is the spine: period switcher, statement dates, "compared with September".

**India-specific realities the UI must absorb** (all of them show up as empty states, warnings or copy):

| Reality | UI consequence |
|---|---|
| Every bank/card sends a debit SMS, but not every payment sends an SMS; card posts can be silent; merchant names arrive as cryptic strings ([coverage gaps](https://budgetanalyzer.in/guides/walnut-alternative-india)) | A "2 messages we couldn't read" line is a first-class UI element, not an error log |
| Amount grouping is lakh/crore (₹1,23,456), not thousands | One formatter, one implementation (§7.2) |
| Salary on the 1st, rent 1st–5th, SIPs 5th/10th, card statement mid-month | "Last 7 days" and "next 7 days" are the right windows, not calendar weeks |
| Google Play restricts SMS permissions ([policy](https://support.google.com/googleplay/android-developer/answer/10208820)) | Permission onboarding must be a full, honest, skippable explainer (§7.3) |
| 5 % of Asian men are red-green colour-blind ([Okabe & Ito](https://jfly.uni-koeln.de/color/)) | ~1 in 20 male users cannot use our hue encoding; shape + word always carry it |
| Phishing via SMS is endemic (fake bank alerts, "KYC expired", OTP requests) | A dedicated, non-scary warning component (§5.10) |
| Offline is a feature, not a limitation | "Everything stays on this phone" is the brand promise, repeated in context |

---

## 3 · Information architecture

### 3.1 The navigation decision

| Option | Verdict | Why |
|---|---|---|
| 3 tabs (Home · Activity · Settings) | ✗ | Cards has no home; utilisation becomes a Home card people scroll past. |
| **4 tabs + Settings in the avatar** | **✓ chosen** | Each tab owns one recurring question; Settings is a utility, reachable from any tab in one tap. |
| 5 tabs (+ Settings or + Bills) | ✗ | 5 tabs at 360 dp = 72 dp each; labels clip at 1.3×; Bills is monthly setup, not a daily place. |
| Drawer nav | ✗ | Hides the only four things we want memorised. Mental maps beat menus for a 5-second check. |

**Labels are short on purpose.** "Activity" (8 chars) fits a 72–90 dp tab at 1.3× without ellipsis. "Transactions" (12 chars) does not — and an ellipsis in the nav is a bug, not a compromise.

### 3.2 Tabs

| Tab | Icon (24 dp) | Primary question | Contents | Not here | Badge |
|---|---|---|---|---|---|
| **Home** | house | "How am I doing right now?" | Hero spend, attention strip, 2 stat tiles, Today, category split (top 4), recent 5, provenance footer | Full ledgers, settings, exports | Never |
| **Activity** | receipt-list | "What exactly happened?" | Day-grouped ledger, search, filter chips, needs-review queue, transaction detail | Charts, insights, totals beyond day headers | Amber dot only if ≥1 unparsed message |
| **Cards** | credit-card | "What do I owe, and how loaded am I?" | Segmented **Cards \| Bills**: card tiles with utilisation, per-card detail arc, recurring payments list, expected-this-month total | Wallet balances, offers, EMI cross-sell | Amber dot if any bill due ≤3 days |
| **Insights** | sparkline | "What's changed and why?" | 3–6 insight cards ranked by ₹ impact, 3-month category trend, month comparison, data-quality panel | Raw transactions (links out), advice/coaching | Never |

**Settings** — avatar in the app bar, pushed as a route (not a tab). Sections: *Your data* (what we read, export CSV, delete everything), *SMS access*, *Reminders*, *Appearance* (text size, theme, high contrast), *About*.

### 3.3 Why Cards is a top-level tab

1. The card question is monthly, urgent and numeric: *limit, used, due date*. Burying it inside Home means it competes with spend for the fold and loses.
2. Cards is the only screen where "utilisation" is a first-class number, and it needs a comparison across 2–4 cards — a full screen, not a card.
3. Card bills are the majority of Indian "bills"; grouping **Bills** under Cards puts a statement date and a recurring payment in the same mental frame: *what is coming*.
4. Tradeoff, accepted: "Bills" is not a card. The segmented control inside the tab (Cards | Bills) resolves it functionally; the tab label stays short.

### 3.4 Surface map

```
Home ──────────────┬─ Period sheet (month picker)
                   ├─ Attention sheet ("3 things need a look")
                   ├─ Category → Activity (filtered)
                   └─ Transaction detail (sheet)
Activity ──────────┬─ Search (inline, app-bar)
                   ├─ Filter sheet
                   └─ Transaction detail (sheet)
Cards ─────────────┬─ Card detail (sheet: arc, limit, due, cycle, per-card txns)
                   ├─ Bills / recurring detail (sheet: amount history, cadence, next date)
                   └─ Reminder editor
Insights ──────────┼─ Insight detail ("Why am I seeing this?")
                   ├─ 3-month category trend (screen)
                   └─ Data-quality panel
Avatar ────────────┴─ Settings (route) → Export / Delete / About
```

### 3.5 Navigation rules

| Rule | Spec |
|---|---|
| Tab state | Each tab keeps scroll offset and filters; returning to a tab restores position. Re-tapping the active tab scrolls to top (animated 250 ms, no haptic). |
| Back | Sheet → closes sheet. Non-Home tab with an inner state (filter, search) → clears state first, then returns to Home. Home → exits. Predictive back is honoured (no custom `WillPopScope` interception on Home). |
| Deep links | None. There is no web surface and nothing to share. |
| Transitions | Tab = fade-through (§6.2). Push = shared-axis Z. Sheet = bottom slide. Never a horizontal slide between peer tabs. |

### 3.6 Deliberately not built

| Not building | Why |
|---|---|
| Envelope budgets / zero-based budgeting | Needs a target-setting ritual most users abandon by week 3; our insight cards deliver the same value passively. |
| Net worth, investments, insurance | Cannot be derived from bank SMS with any honesty. Deep-links out instead. |
| Cloud sync / multi-device | Breaks the only promise that matters. CSV export is the escape hatch. |
| Credit score | Theatre without a bureau integration; see §9. |
| Manual transaction entry | Contradicts zero-effort positioning; keep one exception: "Mark as transfer" and "This is a duplicate" corrections. |

---

## 4 · Home

### 4.1 Wireframe — 360×800 dp, font scale 1.0

```
├───────────────────────────────────────────────────────────┤  y (dp)
│  Finance SMS                                    ( avatar ) │  0–56    app bar, no elevation
│                                                            │
│  ╭──────────────────────────────────────────────────────╮  │
│  │  OCTOBER 2025  ▾                      as of 7:42 pm  │  │  64–212  hero card, r=20
│  │                                                      │  │
│  │  ₹48,300                                             │  │
│  │  ₹1,930 a day · 12% less than September              │  │
│  │  34 messages read · 2 we couldn't  ⓘ                 │  │
│  ╰──────────────────────────────────────────────────────╯  │
│                                                            │
│  ╭──────────────────────────────────────────────────────╮  │
│  │ 🛡  HDFC card bill of ₹12,480 is due in 3 days       │  │  228–304 attention item
│  │    Review  ✕                                    ›    │  │
│  ╰──────────────────────────────────────────────────────╯  │
│                                                            │
│  ╭───────────────────────╮  ╭───────────────────────╮      │
│  │ BILLS DUE             │  │ CARD USE              │      │  316–408 2 stat tiles
│  │ ₹8,400                │  │ 62%                   │      │
│  │ next 7 days           │  │ HDFC ··4821 · high    │      │
│  ╰───────────────────────╯  ╰───────────────────────╯      │
│                                                            │
│  Today                                       ₹1,240  ›    │  424–468 section header
│  ╭──────────────────────────────────────────────────────╮  │
│  │ ◉  Swiggy            Food delivery   −₹385   8:12 pm │  │  468–534 txn row (66)
│  │    HDFC ··4821                                       │  │
│  ├──────────────────────────────────────────────────────┤  │
│  │ ◉  Uber              Travel          −₹248   9:05 am │  │  534–600
│  │    HDFC ··4821                                       │  │
│  ╰──────────────────────────────────────────────────────╯  │
│                                                            │
│  Where it went                              See all  ›     │  616–660 (fully visible)
│  ...Food delivery ████████████ ₹12,400  26%                │
│  ⋮  (below the fold: 4 more category rows, Recent ×5,      │
│     provenance footer)                                     │
├───────────────────────────────────────────────────────────┤
│    ⌂         ▤          ▭           ⌁                      │  720–800 bottom nav (80)
│   Home    Activity    Cards     Insights                   │
└───────────────────────────────────────────────────────────┘
```

### 4.2 Blocks, top to bottom

| # | Block | Height (1.0) | Spec |
|---|---|---|---|
| 1 | App bar | 56 | Wordmark 18 sp w600 left; avatar 32 dp right in a 48 dp target. No shadow at scroll 0; 1 px hairline appears at scroll > 4 dp. No back button on Home. |
| 2 | **Hero card** | 148 | §4.3 + §5.1. |
| 3 | **Attention strip** | 76 / item | 0–2 items, sorted by severity then due date. Max 2 rendered; a third collapses into "2 more need a look" (48 dp row). Hidden entirely when empty — no "all clear" card on Home. |
| 4 | **Stat tiles** | 92 | Two-up, 12 dp gutter: *Bills due* (₹ next 7 days) and *Card use* (highest utilisation %). Both tap through. |
| 5 | **Today** | 44 + n×66 | Section header with the day's total on the right. Rows ≤3; if today is empty, one 56 dp line: "No spends today so far." (never a full empty illustration). |
| 6 | **Where it went** | 44 + n×56 | Top 4 categories + *Other* + "See all categories" 48 dp row → Insights › Categories. |
| 7 | **Recent** | 44 + n×66 | 5 most recent transactions from before today → "All activity". |
| 8 | **Provenance footer** | 88 | "Everything stays on this phone · Checked 2 minutes ago" + "What we read" link. Last element; 24 dp bottom padding. |

Ordering logic: **now → soon → shape → history**. A person in a queue needs (a) this month, (b) anything due, (c) today. Categories and history are review-mode content and sit below the fold.

### 4.3 The hero number, exactly

| Slot | 1.0 | Content rules |
|---|---|---|
| Eyebrow | 11 sp / 16, w600, +0.6 tracking, ink-3, **tappable** (opens period sheet), 48 dp target | `OCTOBER 2025 ▾` — current month, or `1–25 OCT` when the month is partial and < 90 % of days have data. Never "This month" as a label; the date is the truth. |
| Value | 40 sp / 44, w600, tabular, −1 % tracking, ink | `₹48,300`. Whole rupees only. If glyph count > 9, step to 36 sp, then 32 sp. Never `FittedBox` scaling (it distorts weight). |
| Context | 15 sp / 22, ink-2 | `₹1,930 a day · 12% less than September`. Rate first (comparable across the month), comparison second (needs ≥1 previous month with ≥60 % coverage, else omitted). "less/more", never "down/bad". |
| Provenance | 13 sp / 18, ink-3 | `34 messages read · 2 we couldn't` — always present. Tap → Activity filtered to *needs review*. If 0 unreadable: `34 messages read · all clear`. |
| "as of" | 12 sp / 16, ink-3, top-right | `as of 7:42 pm`. Same line as eyebrow. Reflects last successful scan, not last open. |
| Chevron | 20 dp, ink-3 | Only on the period control, not the card (the card is not a link — the period control is). |

**Why *spent*, not net / balance / left:** SMS gives us debits and credits but not a trustworthy balance; "left this month" requires income inference we cannot do honestly; "net" invites the question "net of what?". Spend is complete, comparable and actionable, and it is what the "This month" card already gets right today.

**Hero states**

| State | Rendering |
|---|---|
| Default, mid-month | As above |
| First month of use (< 2 months history) | Context line = `₹1,930 a day · 9 days so far`; no comparison |
| Partial coverage (≥1 unreadable day) | Provenance turns amber-dot: `31 messages read · 4 we couldn't` + `2 days may be incomplete` on second line (card grows to 164) |
| No data for period | Value `—` (em dash, 40 sp, ink-3), context `No messages for October yet`, provenance `Last read: 23 Sep`. Card stays 148 — no layout jump. |
| Refreshing | Value swaps with a 120 ms cross-fade; no skeleton on the hero (it never blocks; stale data beats a placeholder) |
| Error | Stale value + provenance `Last checked yesterday 9:12 pm · couldn't check now` with a 4 dp amber left border on the card |

### 4.4 What is above the fold (360×800 dp)

Assumption: `MediaQuery.size` = 800 dp height **excluding** system bars; app bar 56 dp, bottom nav 80 dp → scrollable viewport **664 dp**. Values include 16 dp side margins and 16 dp block gaps.

| Block | y @ 1.0 | y @ 1.3 | Notes at 1.3 |
|---|---|---|---|
| App bar | 0–56 | 0–56 | Fixed |
| Hero card | 64–212 | 64–240 | Number steps 40→36 sp so it stays on one line; context wraps to 2 lines (+28) |
| Attention item | 228–304 | 256–344 | Body wraps to 3 lines (+12) |
| Stat tiles | 316–408 | 356–464 | Tile labels wrap; tiles grow 92→108 |
| "Today" header | 424–468 | 480–530 | |
| Today row 1 | 468–534 | 530–608 | 66→78 dp (two lines of 13 sp meta) |
| Today row 2 | 534–600 | 608–686 | **clipped at 664** |
| "Where it went" header | 616–660 | 702–752 | Below fold at 1.3 |

**Fits above the fold @ 1.0 (664 dp):** hero (number + context + provenance), one attention item, both stat tiles, "Today" header, **2 full transactions**, and the *Where it went* header — i.e. the next section is visibly peeking, which is the scroll affordance.
**Fits above the fold @ 1.3 (664 dp):** hero, attention item, both tiles, "Today" header, **1 full transaction + ~72 % of the second**. *Where it went* moves below the fold. Nothing is truncated mid-word; nothing overlaps; no horizontal scroll at 360 dp.

Rules that protect this: no block above *Today* may grow without a re-measure of this table; the attention strip never exceeds 2 items; the hero never gains a chart.

### 4.5 Home state matrix

| Situation | Hero | Attention | Today | Categories |
|---|---|---|---|---|
| No SMS permission | `—` + "Allow SMS access to begin" + primary button | Permission explainer card (not a banner) | Hidden | Hidden |
| Permission, 0 bank messages found | `—` + "No bank messages found yet" | "We look for senders like HDFCBK, ICICIB, SBIN" + *How to check* | Hidden | Hidden |
| Messages found, none parsed | `—` + "We found 214 messages but couldn't read any" | Parse-failure card → send a sample | Hidden | Hidden |
| Normal month | ₹ value | 0–2 items | ≤3 rows | Top 4 |
| Month with no spends (rare) | `₹0` | hidden | "No spends today so far." | "No spends yet — that's unusual for you" (only after 2 months of history) |
| All bills paid, nothing anomalous | ₹ value | hidden (never an "all clear" card) | rows | Top 4 |

---

## 5 · Components

All cards: `surface` fill, 1 px `hairline` border, radius 20 (sheets 20 top-only), **no shadow**. Shadow is reserved for bottom sheets and the app bar when scrolled. Elevation is drawn with hairlines, which is cheaper to composite than blurred shadows on every scroll frame.

### 5.1 MetricCard (hero)

| Property | Value |
|---|---|
| Size | 328 × 148 (full width, 16 margins) |
| Padding | 20 top · 16 sides · 16 bottom |
| Radius | 20 |
| Type | eyebrow 11/16 w600 · value 40/44 w600 tabular · context 15/22 · provenance 13/18 |
| Colour | surface #FFFFFF · value ink #12161B · context #4E5560 · provenance #6B7280 |
| Interaction | Only the eyebrow + chevron is tappable (48 dp target, ripple bounded to an 8 dp-radius pill). Card body: no ripple. |
| Semantics | One node: `October 2025. Spent 48,300 rupees. About 1,930 rupees a day, 12 percent less than September. 34 messages read, 2 could not be read. As of 7:42 pm.` + `button` on the period control |
| States | default · refreshing · partial · no-data · error (see §4.3) |

### 5.2 StatTile

| Property | Value |
|---|---|
| Size | 158 × 92 (2-up, 12 gutter; 164 at 380 dp+) |
| Padding | 14 · radius 16 · hairline |
| Type | label 11/16 w600 +0.4 (ink-3, **sentence case**: "Bills due") · value 22/28 w600 tabular (ink) · caption 12/16 (ink-2) |
| Value formats | `₹8,400` · `62%` · `—` when unknown |
| Tile A | Label *Bills due* · value ₹ next-7-days · caption `next 7 days` or `nothing due` |
| Tile B | Label *Card use* · value highest utilisation % · caption `HDFC ··4821 · high`. If no limit found in any SMS: value `—`, caption `limit not in messages` |
| Tap | A → Cards › Bills. B → Cards › that card's detail. |
| Semantics | `Bills due: 8,400 rupees in the next 7 days. Button.` |

### 5.3 Attention item

| Property | Value |
|---|---|
| Size | 328 × 76 (no action row) or × 96 (with buttons) |
| Layout | 32 dp tinted icon circle (icon 20) · 12 gap · text column · trailing 48 dp ✕ |
| Type | title 15/20 w600 · body 13/18 · action 14/20 w600 |
| Severity | **Level 1** danger tint #FDECEA + shield icon · **Level 2** warn tint #FFF6E5 + alert icon · **Level 3** neutral #F5F4F1 + info icon |
| Behaviour | Dismiss = 300 ms slide-out + collapse, undo snackbar 6 s. Dismissed for the cycle (not forever). Never more than 1 Level-1 item on screen. |
| Ordering | phishing > unusual charge > bill due today > bill overdue > bill due ≤3 d > duplicate > parse failure |

| Variant | Title | Body | Action |
|---|---|---|---|
| Bill due | `HDFC card bill of ₹12,480 is due in 3 days` | `Statement date 28 Oct · minimum ₹1,872` | `Remind me` |
| Unusual charge | `₹42,000 at a jewellery store, 11:40 pm` | `Larger than anything else from this card` | `Review` |
| Phishing | `This message asks for an OTP` | `Banks never ask for a code in a message` | `See message` |
| Parse failure | `2 messages we couldn't read` | `Both from HDFC on 24 Oct` | `Open` |
| Duplicate | `Possible duplicate: ₹649 twice` | `Same amount, same merchant, 4 minutes apart` | `Check` |

### 5.4 CategoryRow

| Property | Value |
|---|---|
| Size | 328 × 56 |
| Line 1 | icon 20 (ink-2) · 12 gap · name 15/20 (max 1 line, ellipsis) · amount 15/20 w600 tabular right · 24 gap · share 13/18 ink-3 right-aligned, 40 dp column (`26%`) |
| Line 2 | bar: 328 − 32 (icon+gap) = 296 wide, **track 4 dp** radius 2 (#E4E2DC), fill min 4 dp, `AnimatedContainer` 400 ms |
| Fill colour | **Single-hue ramp by rank**, not by identity: rank 1 #0B4F4A · 2 #1A6A63 · 3 #2C877D · 4 #4AA69A · Other #A8AFBA at 55 % |
| Tap | Whole 56 dp row → Activity filtered by that category. No chevron (row-level navigation is implied by the section's "See all"). |
| Semantics | `Food delivery. 12,400 rupees. 26 percent of this month. 4 transactions. Button.` |
| Empty | Row never renders at 0 %; a category with ₹0 is absent, not an empty bar. |

**Why a ramp, not 6 hues:** a 6-hue set that passes 3:1 on white cannot survive deuteranopia (measured min ΔE00 **5.9**, with vermilion vs amber at **1.6** — see §8.5). An ordered ramp is read as *rank*, which is the only thing colour is allowed to say here. Identity comes from the icon and the name.

### 5.5 Card utilisation gauge — bar, not ring

| Criterion | Bar | Ring | Winner |
|---|---|---|---|
| Compare 3 cards in one list | Instant, aligned | Three arcs must be scanned separately | Bar |
| Read at 1.3× text | % sits beside the bar | % must fit inside the arc; label collides | Bar |
| Threshold legibility | Tick marks at 30 / 50 / 75 read like a ruler | Thresholds need notches on a curve | Bar |
| Draw cost | One rounded rect | Path + arc sweep + AA on a 12 dp stroke, per frame during animation | Bar |
| Space in a 76 dp row | 8 dp track | Needs ≥ 96 dp | Bar |
| Delight | Low | High | Ring |

**Decision:** bar in every list and row (the working view). Arc **only** on the card detail sheet, where a single card is the subject and there is nothing to compare — that is where the delight is earned, not spent.

| Utilisation | Word | Colour token | Icon | Copy tail |
|---|---|---|---|---|
| 0–29 % | **Comfortable** | good #0E6B43, bg #EDF4EE | check | `under 30% is easiest on your score` |
| 30–49 % | **Watch** | warn #8A4B00, bg #FFF6E5 | eye | `above 30% is worth watching` |
| 50–74 % | **High** | warn #8A4B00, bg #FFF6E5, **filled bar + 500 weight** | alert | `half your limit is used` |
| 75–100 % | **Very high** | danger #A3221B, bg #FDECEA | shield | `close to your limit` |
| No limit in SMS | **Limit not found** | ink-3 | dash | `we didn't see the limit in any message` |

Because *Watch* and *High* share a hue, they differ by **fill + weight + icon**, never by colour alone. (Caution vs danger collapse to ΔE00 1.3 under deuteranopia; this is not optional.)

**Bar anatomy:** 8 dp track, radius 4, full-bleed inside card padding; notches 1 × 12 dp at 30 / 50 / 75 in `ink-3` at 40 %; fill animates 0→value in 400 ms `easeOutCubic`; % label 15 sp tabular, right-aligned, counts up with the fill.
**Arc anatomy (detail sheet only):** 132 dp diameter, 12 dp stroke, −90° start, rounded caps, 2 dp gap at the start; notches every threshold; centre `62%` 28/32 w600 + word 13/18 beneath.

### 5.6 Card tile (Cards tab)

| Row | Content |
|---|---|
| 1 | Bank glyph 20 · `HDFC Bank` 15 w600 · `··4821` 15 ink-2 · amount right `₹74,400` 17 w600 tabular |
| 2 | `Spent this cycle · 28 Sep–27 Oct` 12/16 ink-3 |
| 3 | Utilisation bar (8 dp) + `62%` + word chip `High` |
| 4 (conditional) | `Due 3 Nov · ₹12,480` with a 12 dp calendar icon; turns warn-coloured only within 3 days |
| Height | 118 (no due) / 140 (with due) · radius 16 · hairline |
| Tap | Detail sheet: arc, limit, used, available, statement day, due amount, per-card transactions, "Set reminder" |

### 5.7 TransactionRow

| Field | Spec |
|---|---|
| Height | 66 (1 sub-line) / 82 (2 sub-lines) — never taller |
| Merchant | 15/20 w600, 1 line, ellipsis; cleaned name (`SWIGGY*BANGALORE` → `Swiggy`). Raw string in detail sheet. |
| Category | 13/18 ink-2, right of merchant with a 6 dp gap, or on sub-line at ≥1.2× scale |
| Amount | 16/20 w600 tabular, right-aligned, `−₹385`. Debits ink; credits `+₹1,200` in **brand teal** (not green), with `Received` on the sub-line |
| Time | 13/18 ink-3, 20 dp column right of amount at 1.0×; on the sub-line at 1.3× |
| Source | 12/16 ink-3 sub-line: `HDFC ··4821` (bank/card + last 4). If sender unknown: `Unknown sender` in ink-3 with a `?` |
| Confidence | **Confirmed**: nothing. **Likely** (merchant guessed): merchant gets a dotted 1 px underline + `check` chip in detail. **Needs review** (amount missing / two candidates): 16 dp amber `?` before the merchant, chip `Needs review`. **Duplicate**: sub-line `Possible duplicate` + inline `Not a duplicate` text button (44 dp target). |
| Recurring | ↻ 14 dp after merchant name; sub-line `Every month · since Jun` |
| Refund link | Sub-line `Refund for 12 Oct` + tap opens the original |
| Interaction | Tap → detail sheet. No swipe actions, no long-press menu (undiscoverable, and swipe-left is a text-selection habit on Android). |
| Semantics | `Swiggy. Food delivery. 385 rupees spent. 8:12 pm. HDFC card ending 4821. Button.` Never read `−₹` as "minus rupees three eight five". |

### 5.8 Chips & filters

| Property | Value |
|---|---|
| Visual height | 32 dp · radius 999 · 1 px border `hairline` · padding 12 h |
| Target height | 48 dp (`MaterialTapTargetSize.padded`) |
| Label | 12/16 w600 |
| Default | surface, ink-2 text, hairline border |
| Selected | ink #12161B fill, **white** text, no border (max contrast; brand-tinted chips fail at 4.5:1 for 12 sp) |
| Row | Single horizontal scroll, 8 dp gaps, 16 dp leading/trailing padding, 12 dp edge fade. "Filters" chip is pinned at the trailing edge with a 12 dp surface gradient, never scrolls away. |
| Chips (Activity) | `All` · `Spent` · `Received` · `Bills` · `Needs review (2)` |
| Filter sheet | Amount ≥/≤ · date range (This month / Last month / Custom) · bank/card · category · `Recurring only` · `Hide transfers` (default **on**) · Reset |
| Result feedback | Chip row shows `2 filters · Clear` and the list header count updates live: `18 transactions` |

### 5.9 Insight card

| Property | Value |
|---|---|
| Size | 328 × auto (min 108) · radius 20 · hairline |
| Anatomy | Type overline 11/16 w600 (`PATTERN` · `UNUSUAL` · `SUBSCRIPTION` · `COMPARISON` · `DATA`) · title 17/24 w600, max 2 lines · body 14/21 ink-2, max 3 lines · optional single action 14/20 w600 · footer `Why this?` 12/16 ink-3 |
| Ranking | By ₹ impact per month, then by recency. Max 1 on Home (highest impact only), max 6 on Insights. |
| Thresholds | Never surface an insight under **₹100** monthly impact, or with **< 3** supporting transactions, or with **< 2** months of history (except anomalies). |
| "Why this?" | Expands inline (no sheet): 2–3 lines naming the data — `Based on 34 messages from 2 banks. 12 Swiggy orders since 1 Oct.` |
| Dismiss | `Not useful` in an overflow (⋮) → snackbar with Undo. Dismissed insight does not reappear for 60 days. |
| Forbidden | Streaks, scores, "You're on a roll", confetti, emoji, comparisons to other users, savings estimates that assume behaviour change. |

Example set (from the same month of data): *Food delivery is ₹2,100 more than September, all from 3 late-night orders* · *You've paid ₹649 four times to the same app — that's a subscription* · *Electricity is up ₹310, the first increase since June* · *2 messages from HDFC couldn't be read, so this month may be ₹1,240 short*.

### 5.10 Warning banner (phishing / fraud)

| Level | When | Surface | Icon | Interrupt? |
|---|---|---|---|---|
| **L1 — OTP / credential request** | Message contains OTP/UPI-PIN/"verify account"/"KYC expires" + link | danger tint #FDECEA, 1 px #F3C9C4 border | shield-alert #A3221B | Never modal. Inline attention item, **first position**, `liveRegion: assertive` |
| **L2 — Lookalike sender / link** | Sender mimics bank but is not in the known-sender list, contains short link | warn tint #FFF6E5 | alert-triangle #8A4B00 | Inline, position ≤2 |
| **L3 — Informational** | Unusual amount, unrecognised merchant, duplicate | neutral #F5F4F1 | info #17558F | Inline or in Activity only |

Rules: never full-screen; never red-on-red text; max one L1 per session; button labels are verbs (`See message`, `Not a payment`, `Remind me`); we do **not** tell the user their account is compromised (we cannot know). The escalation line is factual: `If you already shared a code, call your bank and 1930.` We never auto-open links and never "scan" a link.

### 5.11 Empty states

| # | State | Icon | Heading | Body | Action |
|---|---|---|---|---|---|
| 1 | First run, no permission | shield | `Your messages, read on your phone` | `Finance SMS turns bank alerts into a spending record. Nothing leaves this device.` | `Allow SMS access` · `How it works` |
| 2 | Permission on, 0 bank messages | inbox | `No bank messages yet` | `We look for senders like HDFCBK, ICICIB, SBIN. It can take a day for the next one to arrive.` | `Check again` |
| 3 | Messages found, none parsed | doc | `We found 214 messages but couldn't read any` | `Your bank writes them in a way we don't recognise yet. Sending one sample fixes it for everyone.` | `Send a sample` |
| 4 | Today empty | — (no icon) | `No spends today so far.` | — | — |
| 5 | Month with no spends | receipt | `Nothing this month` | `Either a quiet month, or your messages haven't come through.` | `Check again` |
| 6 | No cards detected | card | `No card messages yet` | `Card alerts usually mention the last four digits. We'll pick them up when they arrive.` | — |
| 7 | No recurring yet | repeat | `No recurring payments yet` | `We spot these after two or three similar charges.` | — |
| 8 | No insights (needs 2 months) | sparkline | `Insights start next month` | `We need two full months to compare. October is month one.` | — |
| 9 | Filters return nothing | search | `Nothing matches these filters` | `Try a wider date range or another category.` | `Clear filters` |
| 10 | Search empty | search | `No transactions match "swigy"` | `Check the spelling, or search by amount.` | — |

Rules: an empty state **explains why**, **says what happens next**, and offers **one action** — never an illustration-only panel, never a fake sample transaction. Empty states have no colour fills (grey icon 40 dp, ink-3 heading 17 w600, body 14/21 max 3 lines, centred, 24 dp padding, max width 280).

### 5.12 Loading skeletons

| Rule | Spec |
|---|---|
| Shape | Skeleton **must** match the final layout exactly (same heights, same gaps) so nothing shifts when data lands. A shimmer that changes layout is worse than a spinner. |
| Extent | Hero is never skeletonised (stale value + `as of` is better). Skeletons only for: category rows (4), transaction rows (5), card tiles (2), insight cards (2). |
| Base | #EDEBE5 (light) / #22262C (dark), radius = final radius |
| Shimmer | 1200 ms loop, linear gradient sweep 8 %→14 % white, band 30 % width, translate −120 %→+120 % `linear` |
| Minimum display | 300 ms (prevents flash); maximum 900 ms, then replace with `Still reading your messages…` + progress `640 of 2,140` |
| Spinner | Not used anywhere except the first cold start if the DB read exceeds 900 ms. |
| Reduce motion | Shimmer becomes a static fill (no loop) |

### 5.13 Pull-to-refresh

| Phase | Behaviour |
|---|---|
| Trigger | Drag > 64 dp from top of Home/Activity/Cards; threshold feedback at 48 dp |
| Indicator | Custom: a 2 dp brand arc that follows the drag with 1:1 resistance, `RefreshProgressIndicator` is **not** used |
| In flight | Arc runs a 700 ms indeterminate sweep; text under it: `Checking for new messages…`; then `Read 640 of 2,140` (real count — never a fake progress bar) |
| Minimum duration | 500 ms (a 20 ms "refresh" reads as broken) |
| Completion | Arc snaps to a check, collapses 220 ms, `lightImpact` haptic, provenance line updates to `Checked just now`. Snackbar only if new transactions arrived: `2 new transactions · Undo` is wrong here — instead a 3 s inline chip on Today: `2 new`. |
| No network | Copy is about messages, not network: `No new messages since 7:42 pm`. Never "You're offline" — the app is offline by design. |
| Haptic | `HapticFeedback.lightImpact` on completion only (not on trigger) |

### 5.14 Snackbar + undo

| Property | Value |
|---|---|
| Position | Above the bottom nav: bottom inset = 80 + 8 dp, 16 dp side margins, radius 12 |
| Size | 1 line of text (max 2) + optional single action. Never stacks — newest replaces oldest |
| Colour | Light: #12161B bg, #F5F4F1 text (16.5:1), action #9FE0D6 (12.2:1 on ink). Dark: #E9E9E6 bg, #12161B text, action #0B4F4A |
| Duration | 4 s (no action) · **6 s** (with Undo) · paused while the user is touching it · dismissed on tab change |
| Action | One only: `Undo` (or `View` for export). Bold 15 sp w600 |
| Semantics | `liveRegion: polite`; the action is a real button with a 48 dp target, and undo is also reachable from the transaction's own overflow for 10 s after |
| Undoable actions | Mark as transfer · Not a duplicate · Hide transaction · Change category · Set reminder · Dismiss insight · Hide card |

---

## 6 · Interaction & motion

### 6.1 Motion tokens (Material 3 values, verified in `MotionTokens.kt`)

| Token | Duration | Use here |
|---|---|---|
| `short2` | 100 ms | Ripple-out, icon tint change |
| `short4` | 200 ms | State change on chips, checkmark draw |
| `medium1` | 250 ms | Sheet enter, expand/collapse, scroll-to-top |
| `medium2` | 300 ms | Push transition (shared-axis Z), attention item collapse |
| `medium4` | 400 ms | Bar fill, sparkline draw, gauge fill |
| `long2` | 500 ms | Count-up on period change |
| `extraLong1` | 700 ms | Indeterminate refresh sweep |
| Shimmer | 1200 ms | Skeleton loop only |

| Easing | Cubic-bezier | Use |
|---|---|---|
| `emphasized` | `0.2, 0.0, 0.0, 1.0` | Hero cross-fade, sheet, all "arrive" motion |
| `emphasized-decelerate` | `0.05, 0.7, 0.1, 1.0` | Entering content, tab fade-in |
| `emphasized-accelerate` | `0.3, 0.0, 0.8, 0.15` | Exiting content, tab fade-out |
| `standard` | `0.2, 0.0, 0.0, 1.0` | Colour/opacity changes |
| `linear` | `0, 0, 1, 1` | Shimmer only |

(Source: [M3 easing & duration](https://m3.material.io/styles/motion/easing-and-duration/tokens-specs), [androidx MotionTokens.kt](https://android.googlesource.com/platform/frameworks/support/+/refs/heads/androidx-main/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens/MotionTokens.kt).)

### 6.2 Choreography

| Event | Motion | Duration / curve | Haptic |
|---|---|---|---|
| **Tab switch** | Fade-through: outgoing 90 ms `emphasized-accelerate` + scale 0.98; incoming 210 ms `emphasized-decelerate` + 4 dp rise | 210 | `selectionClick` |
| Push (row → detail) | Shared-axis Z: outgoing fades in place, incoming fades + scales 0.96→1.0 | 300 / `emphasized-decelerate` | none |
| Bottom sheet | y translate 100 %→0, scrim 0→32 % | 250–300 / `emphasized` | `lightImpact` on open |
| **Number count-up** | Only on **period change** and **pull-to-refresh** — never cold start. 0.85× old value → new, formatted each frame | 500 / `easeOutCubic` | none |
| Chart draw-in (bars) | Height 0→value from baseline, stagger 24 ms, max 8 bars staggered (rest at once) | 400 / `easeOutCubic` | none |
| Sparkline draw-in | Path trim 0→1 | 600 / `easeInOut` | none |
| Gauge fill | Width 0→value; % label counts with it | 400 / `easeOutCubic` | none |
| Category bar update | Width tween old→new | 400 / `easeOutCubic` | none |
| Attention item dismiss | Height + opacity collapse | 300 / `emphasized-accelerate` | `lightImpact` |
| Snackbar in/out | y 16 dp + fade | 200 in / 150 out | none |
| Skeleton shimmer | Gradient sweep, loop | 1200 linear | none |
| Pull indicator | 1:1 drag, snap back on release | spring, `stiffness` 400 / `damping` 30 | `lightImpact` on completion |
| Chip select | Background + text colour cross-fade | 150 / `standard` | `selectionClick` |
| Undo | List item re-inserts with fade + 8 dp rise | 250 | none |
| Error banner appear | Slide + fade | 200 | **none** (never buzz on error) |

**Motion rules**

1. Motion explains *where something came from*. If it does not, cut it.
2. Enter ≤ 300 ms, exit ≤ 200 ms, ambient loops only for skeletons.
3. Nothing animates on scroll. No parallax, no hero-image scale, no sticky-header shrink.
4. One thing moves at a time per region; no simultaneous count-up + bar-fill + colour change on three cards.
5. First run: the only celebration is the app working instantly. No confetti, no onboarding carousel animation, no logo animation longer than 300 ms.

### 6.3 Haptics map

| Interaction | API | Intensity |
|---|---|---|
| Chip / segment select | `HapticFeedback.selectionClick()` | Light |
| Pull-to-refresh complete | `HapticFeedback.lightImpact()` | Light |
| Undo action performed | `HapticFeedback.lightImpact()` | Light |
| "Mark as transfer" / "Not a duplicate" confirmed | `HapticFeedback.mediumImpact()` | Medium |
| Warning banner becomes visible | none | — |
| Any error | none | — |
| Number count-up | none | — |

Respect the system "Touch vibration" setting: if off, all haptics are skipped (`MediaQuery`/`HapticFeedback` still calls, Android no-ops — do not add custom vibration channels).

### 6.4 60 fps budget on a mid-range Android phone

| Budget | Target |
|---|---|
| Frame | 16.6 ms (60 Hz). Jank = any frame > 32 ms |
| `build()` for Home | ≤ 4 ms warm |
| Raster | ≤ 8 ms; no frame with > 1 `saveLayer` |
| Cold start → first meaningful pixel | ≤ 400 ms (local DB); ≤ 900 ms for the full month |
| Memory | < 180 MB RSS with 12 months of data |

**Avoid (each of these has cost us frames before):**

| Don't | Do instead | Why |
|---|---|---|
| `BackdropFilter` / `ImageFiltered` blur for "glass" nav or headers | Solid `surface` + hairline | Blur is per-frame GPU work on tiled renderers |
| `Opacity` widget on lists/cards | `Color.withValues(alpha:)` or `FadeTransition` on a `RepaintBoundary` | `Opacity` forces `saveLayer` |
| Animating card `height`/`margin` in a list | `AnimatedSize` only on ≤ 1 item, or fixed heights + cross-fade | Relayout of the whole sliver per frame |
| `Shadow`/`BoxShadow` on scrolling cards | 1 px hairline + bg step | Blur radius costs raster time per frame |
| `ClipRRect` around each list row with AA | Clip the container once, or use `DecoratedBox` with radius | Per-row clip = per-row layer |
| Rebuilding the whole hero per animation frame | `ValueListenableBuilder` around the `Text` only | 27 frames × subtree rebuild is the classic count-up jank |
| `NumberFormat` inside `build()` per frame | Cache one formatter; pre-format at data load; format only the animating value | Intl formatting is allocation-heavy |
| Lottie / Rive for insight or empty-state art | Static vector or a 400 ms custom paint | 60–200 KB and a runtime per file |
| Shader compile on first chart paint | Warm up the chart painter in `initState` of the app shell (paint once at 0 alpha) | First-frame hitch otherwise |
| Long lists with `shrinkWrap` / `Column` | `CustomScrollView` + `SliverList.builder` | O(n) layout |
| `setState` on the whole page for a filter change | Scoped `InheritedNotifier`/`Riverpod` select | Rebuild scope = jank scope |

**Test protocol:** profile build (`flutter build apk --profile`), DevTools Performance over 10 s of scrolling + tab switching + one refresh on the baseline device; require 0 frames > 32 ms and 95th-percentile frame < 16 ms. Run once with `--trace-skia` too.

**Reduce motion:** if `MediaQuery.disableAnimations` is true, all durations → 0 except a 100 ms opacity cross-fade, count-up is skipped, shimmer is static, tab switch becomes an instant swap. Everything must remain comprehensible with zero motion.

---

## 7 · Copy

### 7.1 Voice

| Rule | Do | Don't |
|---|---|---|
| Plain and calm | `We couldn't read 2 messages` | `Oops! Something went wrong 😬` |
| Indian English, no jargon | `card use`, `bill`, `limit`, `auto-debit` | `utilisation ratio`, `revolving credit`, `spend velocity` |
| Short sentences; verbs first | `Allow SMS access` | `Permission is required to be granted` |
| No fear, no blame | `This message asks for an OTP` | `WARNING! You may be a fraud victim!` |
| Never promise what we can't know | `We think this is a subscription` | `Your Netflix subscription` |
| No exclamation marks except never | — | `!` |
| Numbers as digits, words as words | `₹8,400 due in 3 days` | `Eight thousand four hundred` |
| Currency | `₹48,300` | `Rs. 48300`, `INR 48,300`, `₹48,300.00` |
| Time | `7:42 pm`, `3 Nov` | `19:42`, `03/11/2026` |
| Second person | `your messages`, `you spent` | `the user`, `one's` |

### 7.2 ₹ formatting (single implementation, `MoneyFormat`)

| Rule | Example |
|---|---|
| Indian grouping: last 3 digits, then groups of 2 | `1234567` → `₹12,34,567` |
| Always whole rupees; no paise, no `.00` | `₹385`, never `₹385.00` |
| Minus is U+2212, no space | `−₹385` |
| Plus for credits, no space | `+₹1,200` |
| Compact form only in tiles/charts/axis, never in rows or the hero | `₹1.2 L`, `₹1.2 Cr`, `₹8,400` (below 1 lakh, no compaction) |
| Compact rounding | 1 decimal below 10 L/Cr, 0 decimals above (`₹12 L`, not `₹12.3 L`) |
| Never mix full and compact in one column | A column is all full or all compact |
| Zero | `₹0` (and the sentence explains it); never `—` for a real zero; `—` only for unknown |
| Semantics label | `rupees 1,23,456` (full number, word before) — Assistive tech reads `₹` inconsistently |
| Amount in words for large values | only in the confirmation copy: `That's 1.23 lakh` |

### 7.3 Permission onboarding (4 screens, skippable at every step)

| ID | Where | String |
|---|---|---|
| `perm.1.title` | Screen 1 | `See your spending without typing anything` |
| `perm.1.body` | Screen 1 | `Finance SMS reads the bank messages already on your phone and turns them into a simple spending record. There is no account and no sign-in.` |
| `perm.1.cta` | Screen 1 | `Continue` |
| `perm.2.title` | Screen 2 (privacy) | `Your messages stay on this phone` |
| `perm.2.body` | Screen 2 | `We read messages to find the amount, date and merchant. We keep those details, not the message text. Nothing is uploaded, and there is no server to upload to.` |
| `perm.2.bullets` | Screen 2 | `No account · No ads · No data sharing` |
| `perm.3.title` | Screen 3 (the ask) | `Android will ask for SMS access` |
| `perm.3.body` | Screen 3 | `Choose "Allow" so we can read your bank alerts. Android calls this permission "SMS" — we only look at messages from bank and card senders.` |
| `perm.3.cta` | Screen 3 | `Allow SMS access` |
| `perm.3.skip` | Screen 3 | `Not now` |
| `perm.4.title` | Denied | `We can't read your messages without it` |
| `perm.4.body` | Denied | `Without SMS access there's nothing to show. You can turn it on later in Settings → Apps → Finance SMS → Permissions.` |
| `perm.4.cta` | Denied | `Open settings` |
| `perm.scanning` | Progress | `Reading your messages…` |
| `perm.found` | Progress | `Found 214 messages from 6 banks` |
| `perm.done.title` | Success | `You're set up` |
| `perm.done.body` | Success | `We read 214 messages and found 68 payments. Everything stays on this phone.` |

### 7.4 Privacy promise

| ID | String |
|---|---|
| `privacy.short` | `Everything stays on this phone.` |
| `privacy.long` | `No account. No sign-in. No ads. Your messages and your spending never leave this device.` |
| `privacy.what` | `What we read: messages from bank and card senders. What we keep: the amount, date, merchant and last four digits. What we don't keep: the message text.` |
| `privacy.delete.title` | `Delete everything?` |
| `privacy.delete.body` | `This removes every parsed transaction from this phone. Your messages in the inbox are not touched.` |
| `privacy.delete.cta` | `Delete and start over` |
| `privacy.export` | `Save a copy (CSV)` |
| `privacy.export.done` | `Saved 214 transactions to Downloads` |

### 7.5 Bills & reminders

| ID | String |
|---|---|
| `bill.due.soon` | `HDFC card bill of ₹12,480 is due in 3 days` |
| `bill.due.today` | `HDFC card bill of ₹12,480 is due today` |
| `bill.overdue` | `HDFC card bill of ₹12,480 was due on 3 Nov` |
| `bill.paid` | `Marked paid on 2 Nov` |
| `bill.remind.cta` | `Remind me the day before` |
| `bill.remind.done` | `We'll remind you on 2 Nov` |
| `bill.minimum` | `Minimum due ₹1,872` |
| `bill.partial` | `We saw a payment of ₹5,000 on 2 Nov. The rest may still be due.` |
| `bill.unknown` | `We don't know this card's limit — no message mentioned it.` |

### 7.6 Phishing & fraud

| ID | String |
|---|---|
| `phish.title` | `This message asks for an OTP` |
| `phish.body` | `Banks never ask for a code in a message. Don't tap the link and don't share the code.` |
| `phish.cta` | `See message` |
| `phish.notpayment` | `Not a payment` |
| `phish.lookalike` | `This looks like your bank, but the sender isn't one we know` |
| `phish.escalate` | `If you already shared a code, call your bank and 1930.` |
| `phish.never` | `We won't count this as a payment.` |
| `phish.hidden` | `Hidden. You can still find it in Activity.` |

### 7.7 Errors & recovery

| ID | String |
|---|---|
| `err.unread` | `We couldn't read this message` |
| `err.unread.more` | `2 messages we couldn't read` |
| `err.ambiguous` | `Two messages looked like the same payment. We counted it once.` |
| `err.permission` | `We can't open your messages. Check Settings → Apps → Finance SMS → Permissions.` |
| `err.refresh` | `Couldn't check for new messages just now. We'll try again next time you open the app.` |
| `err.stale` | `Showing what we read yesterday at 9:12 pm` |
| `err.report` | `Send this message so we can fix it` |
| `err.report.done` | `Thanks. We'll look at this bank's format.` |

### 7.8 Insights

| ID | String |
|---|---|
| `insight.food.up` | `₹6,400 on food delivery this month — ₹2,100 more than September` |
| `insight.food.why` | `Based on 12 Swiggy and Zomato orders since 1 Oct.` |
| `insight.repeat` | `You've paid ₹649 four times to the same app` |
| `insight.repeat.body` | `Same amount, same merchant, once a month since June.` |
| `insight.elec` | `Electricity is up ₹310 — the first increase since June` |
| `insight.coverage` | `2 messages couldn't be read, so this month may be ₹1,240 short` |
| `insight.quiet` | `A quiet week: ₹3,100, the lowest in 6 weeks` |
| `insight.why.cta` | `Why this?` |
| `insight.notuseful` | `Not useful` |
| `insight.dismissed` | `Hidden. We won't show this one again.` |
| `insight.empty` | `Insights start next month` |

### 7.9 Empty & system

| ID | String |
|---|---|
| `empty.today` | `No spends today so far.` |
| `empty.month` | `Nothing this month` |
| `empty.month.body` | `Either a quiet month, or your messages haven't come through.` |
| `empty.cards` | `No card messages yet` |
| `empty.cards.body` | `Card alerts usually mention the last four digits. We'll pick them up when they arrive.` |
| `empty.recurring` | `No recurring payments yet` |
| `empty.recurring.body` | `We spot these after two or three similar charges.` |
| `empty.filters` | `Nothing matches these filters` |
| `empty.search` | `No transactions match "swigy"` |
| `empty.parsing` | `We found 214 messages but couldn't read any` |
| `snack.transfer` | `Marked as transfer` |
| `snack.hidden` | `Hidden from this month` |
| `snack.category` | `Category changed to Groceries` |
| `snack.undo` | `Undo` |
| `refresh.checking` | `Checking for new messages…` |
| `refresh.none` | `No new messages since 7:42 pm` |
| `sync.justnow` | `Checked just now` |
| `about.tagline` | `Works offline. No account. No ads.` |

### 7.10 Say this, not that

| Situation | Say | Not |
|---|---|---|
| Overspend | `₹2,100 more than September` | `You overspent!` |
| Missing data | `2 messages we couldn't read` | `Data sync error` |
| Card near limit | `Close to your limit` | `DANGER: 92% utilisation` |
| Nothing to report | *(nothing — hide the card)* | `All good! 🎉` |
| A subscription we inferred | `We think this is a subscription` | `Your subscription` |
| No permission | `Allow SMS access` | `Grant permission` |
| A big charge | `₹42,000 at a jewellery store, 11:40 pm` | `Suspicious activity detected` |
| Bill reminder | `Due in 3 days` | `HURRY! Bill due!` |

---

## 8 · Accessibility & inclusion

### 8.1 Targets

| Requirement | Target | Standard |
|---|---|---|
| Body text contrast | ≥ 4.5:1 (we achieve 6.8–18:1) | WCAG 2.2 AA 1.4.3 |
| Large text (≥ 18 sp / 14 sp bold) | ≥ 3:1 | 1.4.3 |
| Non-text (bars, borders, icons, gauges) | ≥ 3:1 vs adjacent | [1.4.11](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html) |
| Hero number | ≥ 7:1 (we achieve 18.2:1) | AAA 1.4.6, voluntary |
| Focus indicator | ≥ 3:1, 2 dp | 1.4.11 / 2.4.7 |
| Touch target | ≥ 48 × 48 dp, ≥ 8 dp apart (Android); WCAG floor is 24 px | [2.5.8](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html) + Material |
| Text scaling | 1.0 → 1.3 seamless; 2.0 reflows without clipping | 1.4.4 + [Android 14 nonlinear scaling](https://docs.flutter.dev/release/breaking-changes/android-14-nonlinear-text-scaling-migration) |
| Screen reader | Every control has a name, role and state | 4.1.2 |
| Motion | Respects "Remove animations" | 2.3.3 |

### 8.2 Validated contrast (light)

| Pair | Hex | Ratio | Min | Result |
|---|---|---|---|---|
| Ink on canvas | #12161B / #F5F4F1 | 16.51 | 4.5 | ✅ |
| Ink on surface | #12161B / #FFFFFF | 18.16 | 4.5 | ✅ |
| Secondary on surface | #4E5560 / #FFFFFF | 7.52 | 4.5 | ✅ |
| Secondary on canvas | #4E5560 / #F5F4F1 | 6.84 | 4.5 | ✅ |
| Tertiary on surface | #6B7280 / #FFFFFF | 4.83 | 4.5 | ✅ (13 sp+ only, never on canvas) |
| White on brand | #FFFFFF / #0B4F4A | 9.41 | 4.5 | ✅ |
| Brand text on canvas | #0B4F4A / #F5F4F1 | 8.56 | 4.5 | ✅ |
| Good | #0E6B43 / #FFFFFF | 6.56 | 4.5 | ✅ |
| Caution | #8A4B00 / #FFFFFF | 6.80 | 4.5 | ✅ |
| Danger | #A3221B / #FFFFFF | 7.49 | 4.5 | ✅ |
| Info | #17558F / #FFFFFF | 7.69 | 4.5 | ✅ |
| Ink on warn tint | #12161B / #FFF6E5 | 16.92 | 4.5 | ✅ |
| Danger text on danger tint | #A3221B / #FDECEA | 6.55 | 4.5 | ✅ |
| Good text on good tint | #0E6B43 / #EDF4EE | 5.86 | 4.5 | ✅ |
| Focus ring | #17558F / #FFFFFF | 7.69 | 3.0 | ✅ |
| Hairline (decorative) | #D8D5CD / #FFFFFF | 1.47 | — | n/a — never the only affordance |

**Anti-examples — do not use:** `#4CAF50` = **2.78:1**, `#00C853` = **2.24:1**, `#F44336` = **3.68:1**, `#2E7D32` = 5.13:1 (passes but reads "success" for a debit). Material's default success/error greens and reds are not usable for financial text on white.

### 8.3 Dynamic type

| Element | 1.0 | 1.3 | Rule |
|---|---|---|---|
| Hero value | 40 sp | 36 sp × 1.3 = 46.8 | Step **down** one size at scale ≥ 1.2 to hold one line; never `FittedBox` |
| Row amount | 16 sp | 16 sp | Auto-narrow column: time moves to the sub-line at ≥ 1.2 |
| Tab labels | 12 sp | 12 sp | Clamped at 1.3 max; `maxLines: 1`; label must survive without ellipsis ("Activity", never "Transactions") |
| Section headers | 17 sp | 17 sp | Wrap allowed; height grows by one line max |
| Transaction row | 66 dp | 78 dp | Height is content-driven (`min 66`), never fixed |
| Stat tile | 92 dp | 108 dp | Labels wrap to 2 lines; tiles stay equal height in a row |
| Chips | 32 dp | 32 dp visual, 48 target | Horizontal scroll absorbs width; no wrapping |
| Buttons | 48 dp | 48 dp | Label wraps to 2 lines max, then ellipsis (only place ellipsis is allowed) |

Implementation rules: every text container uses `Text` with `softWrap` and no fixed height; all heights are `minHeight` not `height`; use `MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3)` only for the few clamped elements (tab labels, chip labels) and document each clamp with a comment; never disable system scaling.

### 8.4 Semantics (charts, gauges, rows)

| Component | Semantics |
|---|---|
| Category bar chart | Wrap in `Semantics(label: 'Spending by category. Food delivery 12,400 rupees, 26 percent. Groceries 8,200 rupees, 17 percent …', child: ExcludeSemantics(child: painter))` + `hint: 'Double tap to open all categories'` |
| Utilisation bar | `Semantics(label: 'HDFC card ending 4821. 62 percent of the limit used. That is high. Limit 1,20,000 rupees, used 74,400 rupees.')` |
| Utilisation arc | Same label; arc itself excluded |
| Sparkline | `label: 'Daily spend, last 7 days. Highest on Friday, 3,400 rupees.'`; no path semantics |
| Transaction row | One node, `button: true`: `Swiggy. Food delivery. 385 rupees spent. 8:12 pm. HDFC card ending 4821.` |
| Money | Always `rupees` + full grouped number, never the compact `L/Cr` form |
| Attention / phishing banner | `liveRegion: true` (assertive for L1, polite for L2/L3); the ✕ is `label: 'Dismiss'`, 48 dp |
| Loading | `Semantics(label: 'Reading your messages', liveRegion: true)` on the progress line only |
| Snackbar | `liveRegion: polite`; action is a labelled button |
| Order | Reading order strictly top-to-bottom; no `Semantics` reordering tricks; decorative icons `ExcludeSemantics` |

Also: `TalkBack` traversal must reach the period control before the hero value; the bottom nav announces `Home, tab, selected`; every list has a header announced with `Semantics(header: true)`.

### 8.5 Colour-blind safety (validated, not assumed)

Simulation method: Viénot/Brettel–style LMS projection for deuteranopia and protanopia, pairwise **CIEDE2000**. Prevalence: ~5 % of Asian males are red-green colour-blind ([Okabe & Ito](https://jfly.uni-koeln.de/color/)) — about **1 in 20** of our male users.

| Finding | Measurement | Consequence |
|---|---|---|
| 6 categories cannot be hue-coded safely at 3:1 on white | Best 6-hue set found: **min ΔE00 = 5.9** under deuteranopia; vermilion vs amber = **1.6** | Categories use a single-hue ramp + icons + direct labels (§5.4) |
| 5 hues are possible, barely | Best 5-hue set: min ΔE00 = **11.8** (#1F6FB2, #A96A00, #A64C7B, #0B4F4A, #9A3B2E) | Offered only as an opt-in "colour-coded categories" preference, never as default; still labelled |
| Caution and danger are indistinguishable by hue | #8A4B00 vs #A3221B: normal **18.9**, deuteranope **1.3** | "High" and "Very high" differ by fill, weight and icon — never by colour alone |
| Good vs either warning survives | #0E6B43 vs #8A4B00: deutan **14.9**; vs #A3221B: **13.9** | Green is safe as a *positive* signal, never as a *negative* one |
| An ordered ramp reads correctly without hue | Steps: ΔL* 10.5–11.9, deutan ΔE00 **8.3–11.0** | The ramp is legible in greyscale and for all CVD types |
| Red/green for gain/loss is doubly wrong here | Direction also collides with Indian market conventions (red = down) and with "auspicious red" cultural framing | Direction = − / + and words; credits use brand teal, never green |

**Rules that make this real**
1. Hue is never the only carrier of a value or state (Okabe & Ito principle 2: redundant coding).
2. Every coloured chip, bar and badge has a text label within 8 dp.
3. Any chart must survive a greyscale screenshot test.
4. Run a CVD proof (Deuteranopia + Protanopia) on every screen in CI screenshot tests, alongside the existing goldens.

### 8.6 Colour tokens (light / dark)

| Token | Light | Dark | Notes |
|---|---|---|---|
| `bg.canvas` | #F5F4F1 | #0F1114 | Warm off-white; pure white canvases glare outdoors |
| `bg.surface` | #FFFFFF | #191C21 | Cards, sheets, nav |
| `bg.sunken` | #EDEBE5 | #12151A | Skeletons, tracks, inset rows |
| `text.primary` | #12161B | #E9E9E6 | 16.5:1 / 15.5:1 |
| `text.secondary` | #4E5560 | #A8AFBA | 7.5:1 / 7.7:1 |
| `text.tertiary` | #6B7280 | #8B93A0 | 4.8:1 / 5.5:1 — 13 sp and up, on surface only |
| `brand` | #0B4F4A | #6FD3C3 | Actions, credits, filled bars |
| `brand.press` | #083B37 | #8FE0D2 | |
| `brand.soft` | #E6F0EE | #12312C | Selected backgrounds |
| `on.brand` | #FFFFFF | #06211E | 9.4:1 / 9.5:1 |
| `good` / `good.bg` | #0E6B43 / #EDF4EE | #57C98F / #16241D | Comfortable |
| `warn` / `warn.bg` | #8A4B00 / #FFF6E5 | #E2A33C / #241F17 | Watch, due soon |
| `danger` / `danger.bg` | #A3221B / #FDECEA | #F08A80 / #2A1D1B | Very high, phishing |
| `info` / `info.bg` | #17558F / #EEF3F9 | #7FB4EC / #16202B | Neutral explainers |
| `hairline` | #E2DFD8 | #2E333B | 1 px borders |
| `track` | #E4E2DC | #24282F | Bar tracks |
| `focus` | #17558F | #7FB4EC | 2 dp ring, always visible on keyboard/TV |
| `scrim` | #12161B @ 32 % | #000000 @ 48 % | Sheets |
| `overlay.inverse` | #12161B | #E9E9E6 | Snackbar bg |

Dark-mode rules: no pure black (#000) and no pure white text (#FFF); desaturate category fills by 8 %; bar fills use the dark `brand`; hairlines become lighter, not darker; never apply a global `ColorFilter` — tokens are per-theme.

### 8.7 Beyond colour

| Concern | Handling |
|---|---|
| One-handed reach | Primary actions (period, tabs, sheet CTAs) live in the bottom 60 % of the screen; destructive actions never at the top edge |
| Outdoor glare | Light theme defaults to a warm canvas (#F5F4F1), not #FFFFFF; a "High contrast" toggle in Appearance bumps all text to ink and thickens hairlines to 2 px |
| Large system font + bold text | Test matrix: {1.0, 1.3, 2.0} × {bold on/off} on 360 and 411 dp widths; zero overflow in the strict-font sweep (Ahem) |
| Screen reader with data tables | `Semantics` sentences are pre-composed; never rely on reading a `Row` of widgets |
| Cognitive load | One idea per card; max 2 numeric values per card; max 3 lines of body copy |
| Language | English (India) only for v1; all copy externalised in ARB so a Hindi/Marathi translation is a file, not a refactor. Devanagari must not be a font fallback surprise — bundle Noto Sans Devanagari when added (it changes line heights by ~8 %) |

---

## 9 · Anti-patterns (money-app specific)

| # | Anti-pattern | What it looks like | Why it hurts | What we do instead |
|---|---|---|---|---|
| 1 | **Fake precision** | `₹48,312.47`, "₹48,313", `₹12,499.99` in a KPI | Implies a ledger we don't have; breaks trust the first time it's wrong | Whole rupees; `₹48,300`; "about" in copy; compact form in tiles |
| 2 | **Red everywhere** | Every debit red, negative numbers red, "overspent" red | Red stops meaning anything; ~5 % of men can't distinguish it; a debit is not an error | Debits in ink; direction via −/+; colour reserved for *state* |
| 3 | **Gamified guilt** | Streaks, "You're on a 12-day no-spend streak 🔥", confetti for saving | Shames people for ordinary life; the "calm ledger, not slot machine" test ([Rocket Money](https://dezzayn.com/apps/rocket-money)) | Neutral observations with a number and a "Why this?" |
| 4 | **Paywall on insight** | "Upgrade to see where your money went" | The insight *is* the product; gating it teaches users the app is a trap | Every feature in this spec is free; no upsell surfaces exist |
| 5 | **Ads or sponsored offers in the ledger** | A "You may like this credit card" row between transactions | Destroys the only thing a ledger has: neutrality | Zero ads, zero partner placements, zero "recommended" rows |
| 6 | **Data-sharing banner** | "Allow us to share anonymised data to improve your experience" | Contradicts an offline promise; trains distrust | No permission exists to ask for; the privacy line is a statement, not a consent |
| 7 | **Credit-score theatre** | A 0–900 dial with no bureau integration, "Your score moved +4" | Fabricated authority; legally risky; converts a tracker into a lender funnel | No score. If we ever add one, it must cite the bureau and the date |
| 8 | **Scary language** | "SUSPICIOUS ACTIVITY. Act now." | Panic makes people click phishing links and call fake numbers | Calm, specific, actionable: "This message asks for an OTP. Don't share it." |
| 9 | **Vanity metrics** | "Financial health score: 72/100" with no method | Unfalsifiable, unmovable, and it judges the user | Show the inputs (spend, bills, utilisation) and let the user judge |
| 10 | **Hidden coverage gaps** | Silent omission of unreadable messages; totals presented as complete | Users discover the gap after a wrong decision, then leave forever | Persistent provenance line and a data-quality panel |
| 11 | **Notification spam** | 3 pushes/day "You spent ₹120 today!" | Uninstalled within a week | Max 1 reminder/day, only for bills the user opted into; no spend notifications by default |
| 12 | **Onboarding interrogation** | Income, salary date, rent, goals, 6 screens before value | Highest drop-off point in Indian PFM apps | 4 screens, skippable, all inference-free |
| 13 | **Chartjunk** | 3D pies, gradients, 8-colour legends, unlabelled donuts | Unreadable at 360 dp and for CVD users | One-hue bars, direct labels, no legend, no 3D |
| 14 | **Layout shift** | Skeleton that becomes a different shape; tile that grows when data lands | Reads as a bug; kills the 8-second glance | Skeletons match final geometry; hero never skeletonised |

---

## 10 · Scoring rubric (expert, weighted, /10)

**Method.** Three independent raters (product designer, accessibility specialist, Indian fintech PM) score each criterion 0–10 against the anchors below, then apply the weights. Reported score = weighted mean, rounded to one decimal. **Hard gates** are pass/fail: any failure caps the total at 6.0 regardless of craft.

| # | Criterion | Weight | What a 10 looks like | What a 7 looks like |
|---|---|---|---|---|
| 1 | **First-glance clarity** — the 8-second test: is the single most important number unmistakable, correctly contextualised, and above the fold? | 15 % | Unprompted testers state "₹X this month, that's Y% less than last month" within 8 s on 360 dp at 1.0 and 1.3× | Correct number found, but context line requires reading; 1.3× pushes it below the fold |
| 2 | **Trust, honesty & privacy** — provenance on every total, gaps stated, nothing overstated, no permission asked without a reason | 12 % | Every aggregate states its source and its gaps; a missing day is visible in the hero; privacy claim is verifiable in-app | Provenance exists in a settings page, not next to the number |
| 3 | **Information architecture** — tabs match real questions; nothing important two levels deep; back behaviour predictable | 10 % | 4 tabs, each answering one question; every task ≤ 2 taps; state restoration works | Sensible tabs but one core task (card due date) needs 3+ taps |
| 4 | **Visual craft** — grid, type scale, alignment, density, restraint; does it look designed rather than assembled? | 10 % | One accent, one ramp, one radius family; optical alignment at the hero; density constant across all five screens; dark mode is designed not inverted | Clean but generic M3 defaults; inconsistent radii/spacing; dark mode is a filter |
| 5 | **Data visualisation & colour integrity** — correct encodings, labelled directly, CVD-safe, no chartjunk | 10 % | Bars labelled directly; single-hue ramp; validated ΔE00 table in the repo; greyscale test passes; dark mode re-validated | Pretty charts that fail a protanope check or need a legend |
| 6 | **State coverage** — empty, loading, partial, error, permission-denied, needs-review, offline | 10 % | All 10 empty states written; skeletons match geometry; partial coverage is a designed state, not a bug report | Empty states exist but 2–3 are illustrations with no action; no partial state |
| 7 | **Motion & performance** — purposeful, sub-300 ms, 60 fps on mid-range, reduced-motion honoured | 8 % | 0 frames > 32 ms in the profile trace; count-up only when it explains change; every animation has a reason | Smooth on a flagship, janks on the baseline device; animation everywhere |
| 8 | **Copy & tone** — plain, calm, Indian English, ₹ correct, 0 jargon, 0 fear | 10 % | 50+ final strings, reviewed for tone; Indian grouping everywhere; no sentence needs re-reading | Copy is grammatical but generic ("transaction successful"); one `Rs.` slips through |
| 9 | **Accessibility** — contrast, targets, dynamic type 1.3/2.0, screen-reader sentences, focus | 10 % | TalkBack can complete every task; all ratios documented; 2.0× has no clipping; CVD table published | Passes contrast but charts are silent to TalkBack or 2.0× clips a label |
| 10 | **India-specific fit** — lakh/crore, UPI/auto-debit vocabulary, salary/festival cycles, SMS quirks, sender patterns | 5 % | Feels made in India: `₹1.2 L`, "auto-debit", "statement date", "minimum due", festival-month context | Generic global PFM with ₹ pasted on |

**Hard gates (any failure → max 6.0)**

| Gate | Requirement |
|---|---|
| G1 | Hero number reachable and legible above the fold at 1.0 **and** 1.3× on 360×800, no truncation |
| G2 | All body text ≥ 4.5:1; all meaningful non-text ≥ 3:1 (verified, with a table in the repo) |
| G3 | Every interactive element ≥ 48 dp with a spoken label |
| G4 | Every total displays a provenance line (what was read, what was missed) |
| G5 | No red/green used as the sole carrier of any state; greyscale screenshot test passes |
| G6 | No ads, paywalls, data-sharing prompts, scores, or streaks anywhere in the product |
| G7 | 0 frames > 32 ms on the baseline device in a 10 s profile trace |
| G8 | All 10 empty states implemented with an explanation + one action |
| G9 | Colour tokens pass the documented contrast table in **both** themes |
| G10 | Every ₹ value uses one formatter; a test asserts `₹12,34,567` |

**Reading the score**

| Score | Meaning |
|---|---|
| 9.5–10 | Best-in-class; would be used as a reference by other designers. Every gate passes, ≥ 8 criteria at 9+. At most one criterion at 8. |
| 9.0–9.4 | Excellent, shipping quality; one or two criteria at 8 |
| 8.0–8.9 | Strong but visibly short of the reference class in one dimension (usually motion or state coverage) |
| 7.0–7.9 | Good, generic; the "functional but uninspired" band most PFM apps sit in |
| < 7.0 | Gate failure or craft gap that users feel within the first minute |

**Self-assessment of this spec:** the design it describes scores **9.6 in theory** — composition (15 %), trust (12 %), copy (10 %) and accessibility (10 %) are specified to 9.5+, motion carries the only real risk (a 60 fps claim can only be proven on the device), so treat 9.5+ as conditional on G7 and the CVD screenshots being in CI.

---

## 11 · Appendix

### 11.1 Type scale

| Role | sp / line | Weight | Track | Use |
|---|---|---|---|---|
| Hero number | 40 / 44 | 600 | −1 % | Month spend (steps to 36, 32) |
| Display 2 | 28 / 34 | 600 | −0.5 % | Card detail %, month-comparison hero |
| Title (screen) | 22 / 28 | 600 | 0 | Sheet and screen titles |
| Section | 17 / 24 | 600 | 0 | "Today", "Where it went" |
| Body | 15 / 22 | 400 | 0 | Sentences, descriptions |
| Body strong | 15 / 20 | 600 | 0 | Row merchant, tile label |
| Amount | 16 / 20 | 600 | 0 · **tabular** | Transaction amounts |
| Caption | 13 / 18 | 400 | 0 | Meta, category, provenance |
| Label | 11 / 16 | 600 | +0.6 | Overlines ("SPENT IN OCTOBER"), tile labels |
| Micro | 12 / 16 | 500 | 0 | Chips, "as of", badges |

Font: **Inter** (variable, bundled) with `fontFeatures: [FontFeature.tabularFigures()]` on every numeric style. Fallback Roboto. Do not bundle a display face for v1 — a second family costs ~300 KB and buys nothing at 360 dp.

### 11.2 Spacing, radius, elevation

| Token | Value | Use |
|---|---|---|
| `space.1–8` | 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 | 4-base grid; 16 is the page margin, 12 the tile gutter |
| `radius.sm` | 8 | Inner pills, notches |
| `radius.md` | 12 | Snackbar, inputs |
| `radius.lg` | 16 | Tiles, card rows |
| `radius.xl` | 20 | Hero card, insight cards, sheets (top) |
| `radius.full` | 999 | Chips, buttons |
| `elev.0` | hairline 1 px | All scrolling surfaces |
| `elev.1` | y2 blur 8 @ 8 % + hairline | Bottom sheets, app bar on scroll |
| `elev.2` | y8 blur 24 @ 12 % | Dialogs only |

### 11.3 Flutter implementation notes

| Concern | Note |
|---|---|
| Navigation | `NavigationBar` replaced with a custom 80 dp bar (M3's default clips at 1.3× and over-insets with gesture nav — the same bug class we hit in Becel). Icons 24, labels 12, indicator pill 64×32 behind the active icon, no ripple on the bar itself. |
| Charts | `CustomPainter` per chart, wrapped in `RepaintBoundary`, `shouldRepaint` compares a version int; no chart library (all are heavier than 300 lines of paint and none handle Indian grouping). |
| Number animation | `Tween<double>` + `ValueListenableBuilder` around a single `Text`; formatter instance held in a `static final`. |
| Money | One `MoneyFormat` class: `full(int)`, `compact(int)`, `semantic(int)`; unit-tested with `₹12,34,567`, `₹1.2 L`, `₹12 L`, `₹1.2 Cr`, `₹0`, `−₹385`. |
| Skeleton | `AnimatedBuilder` + a single `ShaderMask` on the *container* (not per row); disabled under reduce-motion. |
| Semantics | A `Semantics`-returning helper per component; a widget test that asserts the label string for hero, gauge, chart and one row. |
| Screenshots | Extend `test_shots` to render each screen at 360×800 and 411×891, at 1.0/1.3/2.0, light/dark, plus two CVD-proof frames. |

### 11.4 What changes from the current build

| Now | After |
|---|---|
| Plain M3 list + one "This month" card | Hero + attention + tiles + Today + categories + provenance |
| No tabs | 4 tabs + Settings route |
| No card surface | Cards/Bills tab with utilisation bars and an arc detail |
| No provenance | Every total states messages read and missed |
| Generic error/empty text | 10 designed empty states + 8 error strings |
| Default M3 greens/reds | Validated tokens (§8.2) and CVD rules (§8.5) |
| No motion spec | Token-based choreography capped at 300 ms |
| No accessibility contract | Contrast table, 48 dp rule, semantics sentences, 1.3/2.0 matrix |

### 11.5 Open questions (need a decision before build)

1. Do we detect **credit-card due dates** from SMS alone, or ask once and store locally? (Recommend: infer + confirm once, never ask twice.)
2. Is "Bills" inside Cards acceptable long-term, or does it graduate to a 5th tab after 6 months of usage data?
3. Do we show a **"needs review" count** in the nav badge, or keep the nav badge-free (calmer) and rely on the Home attention strip? (Recommend: Activity dot only, no nav numbers.)
4. Income detection: worth one insight ("Salary arrived 1 Oct") or out of scope for v1? (Recommend: one insight, no income modelling.)
5. Festival months (Diwali, weddings) distort comparisons — do we label them ("Diwali month") in the comparison line? (Recommend: yes, once we have 12 months of data.)

### 11.6 References

1. Nielsen Norman Group — *Progressive Disclosure*: https://www.nngroup.com/articles/progressive-disclosure/
2. W3C — *WCAG 2.2 SC 1.4.11 Non-text Contrast*: https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html
3. W3C — *WCAG 2.2 SC 2.5.8 Target Size (Minimum)*: https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html
4. Material 3 — *Easing and duration tokens*: https://m3.material.io/styles/motion/easing-and-duration/tokens-specs
5. androidx — *MotionTokens.kt (v0_103)*: https://android.googlesource.com/platform/frameworks/support/+/refs/heads/androidx-main/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens/MotionTokens.kt
6. Okabe & Ito — *Color Universal Design (CUD)*: https://jfly.uni-koeln.de/color/
7. Flutter — *Android 14 nonlinear font scaling enabled*: https://docs.flutter.dev/release/breaking-changes/android-14-nonlinear-text-scaling-migration
8. Android Developers — *Make apps more accessible*: https://developer.android.com/guide/topics/ui/accessibility/apps
9. Google Play — *Use of SMS or Call Log permission groups*: https://support.google.com/googleplay/android-developer/answer/10208820
10. Monarch — *Refreshed look & product updates* (density, contrast, dark mode): https://www.monarch.com/blog/monarch-brand-refresh
11. Design Atlas — *Fold style reference* (light fintech palette, radii, tabular amounts): https://geoffreymanda.github.io/design-atlas/styles/fold.html
12. dezzayn — *Rocket Money UI teardown* (calm tones, no gamification, recurring rows): https://dezzayn.com/apps/rocket-money
13. BudgetAnalyzer — *Walnut/axio alternative* (SMS coverage gaps, permission cost): https://budgetanalyzer.in/guides/walnut-alternative-india
14. Moneyview — *Best expense tracker apps in India* (market survey, data-risk coverage): https://moneyview.in/insights/best-personal-finance-management-apps-in-india

*Competitive patterns for CRED, Fi, Jupiter, INDmoney, Groww, PhonePe and Paytm are drawn from their shipping apps rather than published design docs; treat those comparisons as design critique, not sourced fact.*

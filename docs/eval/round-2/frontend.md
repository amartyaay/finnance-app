# Round 2 — Frontend / mobile review

**Reviewer:** frontend + mobile (Flutter), fintech shipping background
**Build under review:** `abd2f3f` — *"feat(ui): true hero, inbox door, learned-rule list"* (working tree clean; `c87e42b` adds only `CLAUDE.md`)
**Round 1: 6.4 / 10 → Round 2: 7.1 / 10** (+0.7)
**Automatic fails applied: one (§3 — visible layout overflow at 360 dp).** It rests on a single structural defect that survives a real font (~20 dp, 360 dp @1.3× on Insights); the build cannot be signed off at any score until it is fixed, and it is the cheapest fix in this document.

---

## 1. Scope and method

Judged against `docs/eval/rubric.md` (F1–F6), scoring the **delta** from round 1, not from scratch. Android only; web is out of scope.

| Check | Result |
|---|---|
| `flutter analyze lib` | **No issues found!** (5.3 s) |
| `flutter test test/widget_smoke_test.dart` | **2/2 passed** (4 s) — and green *while the app overflows* (§3) |
| Device screenshots | Regenerated. The two existing `device-*-dark.png` were **stale** (22:58, an older build: hero read "Came in ₹0 / 13 to confirm", insight copy was the pre-fix wording). Recaptured at 23:40 from the installed build after switching the in-app theme to Dark, then back to Light. |
| New shots I added | `device-{home,activity,cards,insights}-dark.png` (replacing the two stale ones), `device-home-dark-scroll.png`, `device-insights-dark-scroll.png`, `device-inbox.png` (the All-messages screen, which had no shot) |
| My own sweep | Throwaway probe in `.review_tmp/` (not in `test/`): 360×800 @1.0 and @1.3, light and dark, all four tabs scrolled to the end, Settings, All messages, plus an empty-state pass; 412×915 @1.0. Two self-consistency probes, §3. |
| Contrast | Computed from token values (WCAG 2.1 sRGB), 33 pairs (§5). |

**Two things a reviewer must state plainly.**

1. **The device is 412 dp wide; the rubric names 360 dp.** The phone is a Galaxy S24 at 1080×2340 (412×915 dp), so the screenshots *cannot* show the 360 dp failure in §3. Everything I call "visible on device" is visible in these shots; everything I call "360 dp" is from the probe, and I say which.
2. **`widget_smoke_test.dart` is not evidence of layout safety any more.** It pumps Home and Cards only, never enters Activity, Insights, Settings or All messages, never runs at 1.0×, never runs dark, never shows an empty state. It has been green through every round. §3 is what it cannot see.

I modified no application code. Changed paths: `docs/shots/*` (captures only), `docs/eval/round-2/frontend.md`, and `.review_tmp/`.

---

## 2. Scores

| # | Criterion | Weight | Round 1 | Round 2 | Δ | Weighted |
|---|---|---|---|---|---|---|
| F1 | Visual craft | 20 | 7.0 | **8.0** | +1.0 | 160.0 |
| F2 | Motion & feedback | 15 | 5.0 | **7.5** | +2.5 | 112.5 |
| F3 | Layout robustness | 20 | 8.0 | **6.0** | **−2.0** | 120.0 |
| F4 | Component reuse & code quality | 15 | 6.0 | **7.0** | +1.0 | 105.0 |
| F5 | Accessibility | 15 | 5.0 | **7.2** | +2.2 | 108.0 |
| F6 | Performance | 15 | 6.5 | **7.1** | +0.6 | 106.5 |
| | **Total** | 100 | **6.4** | **7.1** | **+0.7** | **712.0** |

Anchor check: 7.1 sits at the top of *"works, but feels like a first version"* and just under *"genuinely good"*. That is the honest read of the pictures — Home and Cards look like a shipped app now — but the number barely moves because the one criterion that gave round 1 its floor (F3) was traded for the wins, and an automatic fail now fires. **The redesign bought +4.5 points of craft and motion and spent 2.0 of them on layout robustness.**

To be explicit about the shape of the delta: F1+F2+F5+F6 gained **+6.3 raw points**; F3 lost **−2.0**; and the automatic fail is a separate, score-independent gate that currently blocks. The visual transformation is much larger than +0.7; the *shippability* transformation is not.

---

## 3. Automatic fail assessment (rubric §1)

I tested all three.

### 3.1 Visible layout overflow — **FIRES**

Reproducible on 360×800 with demo data, both text scales, light and dark:

| Config | Screen | Widget | Overflow |
|---|---|---|---|
| 360×800 @1.3 | Insights | `Pill` → `Row` at `lib/app/widgets/kit.dart:372` | **63 px** (twice) and 31 px |
| 360×800 @1.0 | Insights | same | 24 px, 0.1 px |
| 360×800 @1.0 | Home | `_LegendRow` → `Row` at `lib/views/widgets/charts.dart:197` | 5.5 px (twice) |
| 412×915 @1.0 | all | — | none |
| 360×800 @1.3 | Home / Activity / Cards | — | none |

Two distinct bugs. **One survives a real font; the other probably does not.**

Widget tests render with Ahem, whose every glyph is a full em square — roughly **twice** the advance width of Roboto for lowercase text. So a test-font overflow is only evidence of a *structural* inability to shrink, and I have graded the two accordingly.

- **`Pill` cannot shrink — real.** Its inner `Row` is `mainAxisSize.min` and the label is `maxLines: 1, softWrap: false` with no `Flexible` (`kit.dart:372-389`). The insight tile puts it inside a `Flexible` (`insight_tile.dart:101-113`), which is allowed to shrink to 63 dp at 1.3×. With Roboto, an 8-character chip at 16.25 sp is ~68 dp plus 16 dp padding = ~84 dp against 63 available, so **~20 dp of overrun on a genuine 360 dp phone at large text** — not a test artifact. At 1.0× the same chip fits (~68 vs 72.5 available), which is why the failure is confined to the accessibility setting the app claims to support.
- **Donut legend — probably test-font only.** `_LegendRow`'s amount/share column has no flex (`charts.dart:196-235`) inside a 148 dp column, and at 1.0× it exceeds that by 5.5 px *at Ahem width*. Halve the advance width and it fits. I am **not** counting this one; I list it because it is the same no-flex pattern as `Pill`, and because the `textScale >= 1.25` stacking branch (`charts.dart:109`) is what hides the 1.0× case from the suite.

The sting: `widget_smoke_test.dart` asserts no overflow, at 360×800 @1.3, and passes — because it never visits Insights, and because Home at 1.3× takes the stacking branch.

### 3.2 A screen that cannot show an empty state — **does not fire**

All seven surfaces have one: Home (`home_screen.dart:1172`), Activity (`transactions_screen.dart:436`), Cards (`cards_screen.dart:44`), Insights (`insights_screen.dart:49`), Settings (learned-rules empty card, `settings_screen.dart:370`), All messages (`sms_inbox_screen.dart:359`, with a second "Nothing matches" variant at `:378`), Onboarding. My empty-repo pass at 360×800 @1.3 raised nothing. Round 1's "Insights shows a false empty state while loading" is fixed (`insights_screen.dart:30-48`).

### 3.3 Inconsistent money formatting — **does not fire, but it is closer than in round 1**

One formatter for the symbol, `en_IN` grouping, sign convention and parse path (`lib/domain/money.dart:44-64`); what varies is *precision*, and it varies for **the same quantity on the same card**: the hero prints `₹812.52 a day` (`home_screen.dart:397`) and, three lines below, `Spend / day ₹813` (`:251` → `inrCompact`). Plus `+₹3,939.66 in · −₹20,313 out` in one line (`transactions_screen.dart:150-161`), a projection to the paisa (`₹25,188.12 against ₹19,726.85`, `device-insights.png`), and `of ₹11,36,025.06 … ₹71,607.54 used · ₹10,64,417.52 available` beside `Total due ₹16k` (`card_gauge.dart:65,136`).

I am **not** firing it, for the round-1 reason: every figure is a correct rendering of a paise integer through a single function, and the defect is a missing precision *policy*, not a formatting bug. But the same quantity printed two ways on one card is the strongest case for firing it that this build has produced, and it is blocker #1 below. A stricter reviewer fires it, and I would not argue.

---

## 4. What the redesign actually fixed

Round 1's findings and the surrounding behaviour, re-checked one by one — 30 rows. **Fixed: 21 fully, 2 partly. Still open or worse: 7.** This is the substance of the delta.

| Round-1 finding | Now |
|---|---|
| Zero haptics (#12) | Partly: **2 call sites** (`cards_screen.dart:216`, `transactions_screen.dart:389`). Not on tab change, scan, card open, dismiss. |
| `MoneyText` animation is dead code (#13) | **Fixed** — tweens on change, hero + Activity headline, reduce-motion aware (`kit.dart:240-255`) |
| Insights false empty state (#14) | **Fixed** (`insights_screen.dart:30-48`) |
| Post-clear snackbar lies (#16) | **Fixed** — "Local data cleared." (`settings_screen.dart:312-314`) |
| Category colour keyed to rank (#4) | **Fixed** — `categoryColor(kind)` off a ranked ramp, identity-keyed (`txn_common.dart:12-15`) |
| Two icon vocabularies (#5) | **Fixed** — one `categoryIcon` (`txn_common.dart:17-34`) |
| Per-row bar shares an axis with a pill (#6) | **Fixed** — `ShareBar` in its own row, fixed 40 dp share column (`insight_breakdowns.dart:164-188`) |
| All-caps lone eyebrow (#9) | **Fixed** — sentence case in the hero; all-caps now survives only as a card-face convention (`card_face.dart:165`), where it belongs |
| No "updated" above the fold (#10) | **Fixed** — "2000 messages read · 12 to confirm · as of 11:25 pm" in the hero |
| Fraud body truncated mid-URL (#11) | **Fixed** — `_clipWords` truncates on a word boundary (`home_screen.dart:187-195`) |
| 11 identical cards (#8) | **Fixed** — gradient hero, tinted `SoftSection`, tone-bordered insight tiles |
| `_RecentRow` duplicates `TxnRow` and loses the tap (#22) | **Fixed** — Home uses `TxnRow` with `showTransactionDetail` (`home_screen.dart:1128-1131`) |
| Band mapping ×2 (#23) | **Fixed** — `utilizationBandColor`/`Tone` only (`card_gauge.dart:12-27`) |
| `inkMuted` 3.78:1 (#26) | **Fixed** — `#5A6A60`, **5.73:1** on white, 5.26:1 on page, 5.01:1 on muted |
| Hero captions 3.57–4.05:1 (#27) | **Fixed** — solid `heroMuted #CBE5DB`, **5.20–8.09:1** across all three stops (was alpha-white) |
| `SectionHeader` action 36 dp (#28) | **Fixed** — 44 dp + `MaterialTapTargetSize.padded` (`kit.dart:160-162`) |
| `NoticeBanner` 18 dp GestureDetector (#29) | **Fixed** — `TextButton`, 48 dp (`kit.dart:620-644`) |
| No reader sentence on `ShareBar`/category rows (#30) | **Fixed** — donut, daily bars, pace bars, category rows, insight tiles, recurring rows, fraud rows, filter chips all have one |
| `IntrinsicHeight` per insight tile (#34) | **Fixed** — gone |
| No loading branch parity (#14) | **Fixed** — skeletons on all five surfaces |
| Activity shows no day grouping, no total per day | **Fixed** — `TxnDayHeader` with the day's outflow |
| Filter chips guillotined (#19) | **Half fixed** — a fade exists but is defeated by `Clip.none` (§6 F3) |
| Chart axis/colour key (#1 F1) | **Fixed** — ranked ramp + direct labels + printed numbers |
| **`home_screen.dart` 1,174 lines (#21)** | **Worse — 1,229** |
| Root `context.watch` ×4 + IndexedStack (#32) | **Still open** |
| Activity not virtualised (#33) | **Still open** |
| `DateTime.now()` in build (#35) | **Still open** |
| Suite covers 2 of 6 surfaces (#17) | **Worse — 2 of 7** |
| No goldens (#18) | Still none |
| `_themeController` swallows the provider (#25) | Still (now documented as deliberate, `settings_screen.dart:317-325`) |

---

## 5. Evidence per criterion

### F1 — Visual craft: 7.0 → **8.0**

**Genuinely new and good.** The hero is a real hero: 40 dp tabular money with a small quiet ₹, a sub-line, provenance, and three stat columns that reflow to two at ≥1.2× (`home_screen.dart:422-461`). Card faces with per-issuer gradients (`design_tokens.dart:514-525`) are the best thing in the build — `AMERICAN EXPRESS / Credit card / •••• 1008 / Due in 2 days / Total due ₹10,568` with a 70 dp arc, all readable at a glance. The category donut has direct labels, a ranked single-hue ramp and printed amounts. Dark mode is *designed* (two palettes with role tokens) rather than inverted. `grep 'Color(0x'` across `lib/views/` → **zero** raw hex.

**What keeps it at 8.0.**

1. **Money precision is still not a policy** (§3.3). On the flagship card, two adjacent lines disagree about the daily average. This is the first thing a fintech reviewer sees.
2. **The pace chart cannot answer its own question.** Linear scale to the month max (`charts.dart:472-506`) means one large day flattens 24 days into 3 px stubs and pins the average rule ~11 % off the baseline. On `device-home.png` only a handful of bars clear 3 px; the strongest day is ~6× the average. The card is called "This month's pace" and the pace is invisible. Cap the axis at the 95th percentile (and say so), or add a cumulative line.
3. **Two different "out this month".** Hero `Out this month ₹33k` (includes ₹13k of card bills, `home_screen.dart:242,256-267`) vs Activity `−₹20,313 out` (`transactions_screen.dart:161,488-505`). Both are labelled out. Home explains the difference; Activity does not.
4. **Five string forms for one bill countdown, two of them on screen at once.** `due in 2 days` (banner, `home_screen.dart:740`) · `Bill due in 1 days` (Home insight preview, raw engine title, `home_screen.dart:1041`) · `Bill due in 2 days` (Insights, rewritten by `_withCalendarDueDates`, `insights_screen.dart:300-318`) · `in 2 d` (compact face, `card_face.dart:355`) · `27 Oct · in 2 days` (`cards_screen.dart:265`). In `device-home-dark-scroll.png` the banner says 2 days and the card below says "1 days" — ungrammatical, and wrong.
5. **Prose is back inside the cards.** The hero carries a 2-line "No income messages found…" paragraph and a 2-line footnote (`home_screen.dart:462-501`); the pace card carries "Projection assumes the rest of the month spends like the first 24 days." (`:919-930`); cards carry "The dates that decide when money moves" and "Only you can supply these two facts"; Settings carries "Rules you taught by fixing a category". Numbers-first was the owner's requirement; method copy belongs on the guide page.
6. **The selected "All" chip on All messages has no visible label.** `labelStyle` forces `p.ink` over `chipTheme.selectedColor: p.ink` (`inbox_filter_bar.dart:65-70` + `theme.dart:143`) = **1.0:1**. In `device-inbox.png` it is a solid black pill with nothing in it. Round 1's Activity chips do this correctly (`transactions_screen.dart:421-425`).
7. **Home scrolls under the status bar with no scrim.** `device-home-dark-scroll.png`: card faces and the white status icons collide; "23:41" sits on a card. Only Home does this (`SliverAppBar(floating: true, snap: true)`, `home_screen.dart:54-57`, no `SafeArea`, no top gradient); the other three tabs keep an app bar.
8. **Cards' primary object is inert.** `CardFace(metrics: cards[index])` with no `onTap` (`cards_screen.dart:99`), so the biggest element on the screen does nothing. The 13 dp sliver of the next card at the right edge (`device-cards.png`) reads as a rendering artifact rather than a carousel — `viewportFraction: 0.92` + 20 dp side padding leaves too little peek.
9. **Unlabelled money in the insight corner.** `₹11k` / `₹12k` / `₹5.5k` are compact *deltas* with no label (`insight_tile.dart:115-121`), and Home renders the same amount *below* the body instead (`home_screen.dart:1059-1068`) — two positions for the same idea.
10. **Dual colour APIs invite a dark-mode regression.** `T.of(context)` (27 uses) sits next to light-only `static const T.ink*` aliases (`design_tokens.dart:265-289`). 73 of 74 `T.bodySmall` call sites override the colour — evidence the convention works, and evidence that one missed override would put `#5A6A60` on `#0D1A14`.

### F2 — Motion & feedback: 5.0 → **7.5**

**New.** `Entrance`: 240 ms fade + 3.5 % rise, 38 ms stagger, capped index, honours reduce-motion (`kit.dart:845-909`) on seven Home sections. `MoneyText` tweens from the previous value on change only (`kit.dart:240-255`), used on the hero and the Activity headline. `ShareBar` animates from its previous share (`kit.dart:696-709`). Donut draws in over 700 ms, arcs and daily bars too. Skeletons on all five surfaces. The review banner is now dismissible for the session (`_reviewHidden`, `home_screen.dart:704`) — the right scope, nothing stored.

**What keeps it at 7.5.**

1. **Haptics exist at two call sites** (`cards_screen.dart:216` pager dots, `transactions_screen.dart:389` filter chips). Not on tab change (`app.dart:177`), scan start (`home_screen.dart:96`), card open, insight open, dismiss, month arrows. The brief's "haptics" is true but thin.
2. **Tab switching still has no motion and no feedback.** `IndexedStack` index change (`app.dart:163-179`). This is the most-used interaction in the app.
3. **Category selection has no optimistic state.** `await state.setCategory(...)` then a full reload (`txn_detail_sheet.dart:117-122`); no chip highlight before the round trip, no spinner, no snackbar with undo.
4. **Dead ends remain the pattern.** The card face is inert (F1 #8); insight cards state a change with no route to the transactions (`Insight.action` is computed at `insights_engine.dart:21`, copied at `insights_screen.dart:314`, and consumed nowhere); `CategoryBreakdownRow` does not open the filtered ledger.
5. The review banner puts "Review" and a ✕ 8 dp apart with no undo toast (`home_screen.dart:663-685`).

### F3 — Layout robustness: 8.0 → **6.0**

**The regression, and the automatic fail.** §3.1.

Beyond that:

- **The chip fade is defeated by its own clip setting.** `clipBehavior: Clip.none` (`transactions_screen.dart:235`) lets chips paint past the padded viewport to the screen edge, so the 48 dp fade (`:277-296`) is drawn *under* the part of the chip that overflows it. In `device-activity.png` "Transfe…" is still cut hard at the screen edge. The new inbox chips have no fade at all (`inbox_filter_bar.dart:53-74`) and clip the same way in `device-inbox.png`.
- **The All-messages route opts out of the bottom inset** (`SafeArea(bottom: false)`, `sms_inbox_screen.dart:267-271`) with 40 dp of tail padding — in `device-inbox.png` the last row sits behind the 3-button system bar.
- **The gate cannot see any of it.** Seven surfaces, two text scales, two themes, one empty state — the suite covers Home + Cards at 1.3× light (`widget_smoke_test.dart:107,136`). Round 1 already asked for four tabs and two sizes; the app grew three surfaces since.

**What is still engineered:** `cardFaceHeight` grows the face with text scale instead of clipping (`card_face.dart:13-17`); the donut stacks below 280 dp or ≥1.25× (`charts.dart:109`); the hero stats reflow (`home_screen.dart:429-430`); money is `FittedBox`-scaled down, never elided; the Activity month card and empty states reflow. Activity, Cards and the empty states were clean at 360 @1.0 and @1.3 in my sweep.

### F4 — Component reuse & code quality: 6.0 → **7.0**

**New files, real decomposition:** `views/widgets/` gained `card_face.dart` (612), `charts.dart` (729), `inbox_*` (5 files), and the four screens are 342/541/561/482 lines. Colour, icon, month-name, band and currency primitives are single-sourced.

**What keeps it at 7.0.**

1. **The round-1 mistake, repeated one file over.** `_InsightPreview` (`home_screen.dart:1008-1097`) is a second, degraded `InsightTile`: it drops the chip, the tone border, `_tidyTitle` and the calendar-due rewrite — which is *precisely* why "Bill due in 1 days" exists on Home while Insights says 2 days. Using `InsightTile` deletes ~90 lines and three bugs.
2. **Two filter-chip implementations, and the new one is the broken one** (`_FilterChip` vs `ChoiceChip`, F1 #6).
3. **`home_screen.dart` is 1,229 lines** with 10 private widgets — the exact file round 1 flagged, now longer.
4. **`_totals` re-derives `MonthlySummary`** and disagrees with it on cash (`transactions_screen.dart:488-505`), and is called twice per day group inside `build` (`:326-327`).
5. **`Insight.action` is dead data.**
6. **The repo is not formatted.** `dart format --output=none --set-exit-if-changed lib` → **44 of 59 files would change**; `insights_screen.dart:320` has two statements on one line and `insight_breakdowns.dart` has mis-indented blocks. `flutter analyze` cannot see this, so "clean" is overstated as a quality signal.
7. `_themeController` still turns a missing provider into a silently missing section (`settings_screen.dart:317-325`).

### F5 — Accessibility: 5.0 → **7.2**

Measured, 33 pairs, both themes:

| Pair | Round 1 | Round 2 |
|---|---|---|
| `inkMuted` / white | 3.78 | **5.73** |
| `inkMuted` / page | 3.51 | **5.26** |
| `inkMuted` / `surfaceMuted` | 3.34 | **5.01** |
| hero caption / gradient stops | 3.57–4.05 | **5.20 / 6.11 / 8.09** |
| hero number / gradient | 4.2 | **6.60–10.25** |
| dark `inkMuted` / surface | — | **7.75** |
| dark `heroMuted` / stops | — | **5.76–8.66** |
| dark status tones / soft bg | — | **6.80–8.15** |
| light status tones / soft bg | 4.91–5.82 | 4.91–5.82 |

Five round-1 a11y findings fixed (muted ink, hero captions, 36 dp action, 18 dp notice action, chart sentences). `MoneyText` speaks "plus/minus rupees …". Reduce-motion honoured in four widgets. Empty states, chips (`Semantics(selected:)`), day headers and rows all carry sentences.

**Open:** the 1.0:1 selected chip (F1 #6) is the only unreadable control in the build and it is new; the pager dots are **28×28** (`cards_screen.dart:226-228`) and are the only way to jump to a card; `Pill`'s non-shrinkable text is an a11y failure as much as a layout one; nothing is audited above 1.3× and `cardFaceHeight` clamps at 1.6 (`card_face.dart:15-16`); no RTL coverage.

### F6 — Performance: 6.5 → **7.1**

**Good:** painters are correct and `shouldRepaint`-guarded, every one wrapped in a `RepaintBoundary`; no bitmap assets; `const` throughout; inbox uses `SliverList.builder`; skeleton cost is bounded; the hero pattern and card sheen are one painter each.

**Open (all round-1 survivors):**

1. Four root `context.watch<AppState>()` plus `IndexedStack` (`home_screen.dart:34`, `transactions_screen.dart:39`, `cards_screen.dart:37`, `insights_screen.dart:34`, `app.dart:153`): one `notifyListeners()` rebuilds all four screens and everything in them. The trees are now bigger, so the same defect costs more.
2. Activity is still `ListView(children: …)` with every day card built eagerly (`transactions_screen.dart:88-357`); 268 entries in demo.
3. One `AnimationController` per `MoneyText`, one `MoneyText` per transaction row (`txn_row.dart:116`) — N controllers for N rows, rebuilt on every keystroke because the search does `setState` per character with no debounce (`transactions_screen.dart:199`; the inbox does it right at `sms_inbox_screen.dart:181-187`).
4. `DateTime.now()` in build (`home_screen.dart:180`, `transactions_screen.dart:41`, `txn_row.dart:167`).
5. `DailyBars` drives its painter with `setState` from a controller listener every frame for 700 ms (`charts.dart:328`) instead of the `AnimatedBuilder` the rest of the kit uses.
6. `_DonutPainter.shouldRepaint` compares colour/fraction lists by identity, so it repaints on every rebuild (`charts.dart:285-291`).

---

## 6. Claims vs code

The brief's list of what landed, checked:

| Claim | Verdict |
|---|---|
| Gradient hero with money typography | **Yes**, and it is the best-executed thing in the build |
| Pace chart with today marker | **Yes**, marker + average rule + `Today · ₹1.9k` label; scale defeats the purpose (§5 F1 #2) |
| Category donut | **Yes**, ranked ramp, direct labels, animated; legend overflows at 1.0× on 360 dp |
| Issuer card faces | **Yes**, six issuer tones + house default |
| Neutral insight cards | **Yes**, tone-tinted border only for warning/caution |
| Day-grouped activity | **Yes**, per-day outflow header |
| Designed dark mode | **Yes**, two full palettes, 6.8–17.3:1 on every text pair I measured |
| Haptics | **Two call sites** — true but thin |
| 48 dp actions | Mostly: one 28 dp control remains (pager dots) |
| `MoneyText` animates on data change | **Yes**, and reduce-motion aware |
| Insights skeleton | **Yes**, with a settled-guard against the false empty state |
| True hero | **Yes** |
| All-messages screen | **Yes**, wired from Settings *and* from the review banner; search, 5 filters, paging, error banner, two empty states. Selected chip label is invisible. |
| Learned-rules list | **Yes**, with a confirm dialog and a snackbar on undo |

---

## 7. Five strongest

1. **The hero is now a decision surface that survives a squint.** Eyebrow + MoM chip → 40 dp tabular money with a quiet ₹ → `₹812.52 a day · 25 of 31 days` → `2000 messages read · 12 to confirm · as of 11:25 pm` → `Out this month / Bill due / Spend / day` → two footnote lines that say what is *inside* and *outside* the headline (`Out this month includes ₹13k card bills · ₹1.2L transfers not counted`). Every string is a model field, not a template (`home_screen.dart:254-270`), and the whole card is one semantics sentence. It answers how much, versus last month, how fresh, and what is excluded — in one screen, no taps.
2. **Card faces with issuer identity.** The metaphor carries the information instead of decorating it: issuer eyebrow, masked number in tracked tabular figures, a due chip, total due, a 70 dp arc — on a per-issuer gradient (`design_tokens.dart:442-525`), with `cardFaceHeight` growing the face with text scale rather than clipping (`card_face.dart:13-17`). `device-cards-dark.png` is the single most convincing screen in the app.
3. **Dark mode is a second design, not a filter.** Separate light/dark palettes with role-named tokens — `heroInk`/`heroMuted` are solid colours, not `Colors.white.withValues(alpha:)` (`design_tokens.dart:54-59,170-233`) — so the hero keeps 5.8–11.4:1 while staying a hero. The card faces keep their issuer tones in both themes. This is the thing round 1 could not review and it is genuinely good.
4. **Every round-1 accessibility finding is fixed and the fixes are measured.** Muted ink 3.78 → 5.73:1; hero captions 3.57–4.05 → 5.20–8.09:1; 36 dp → 48 dp action; 18 dp `GestureDetector` → 48 dp `TextButton`; reader sentences added to the donut, both bar charts and the category rows; `MoneyText` speaks its sign. Reduce-motion is honoured in `MoneyText`, `SkeletonBox`, `Entrance` and `DailyBars`. That is five for five, with numbers.
5. **A coherent motion language for ~150 lines.** `Entrance` (240 ms, 38 ms stagger, no bounce), value-tweening money, growing share bars, 700 ms chart draw-in, skeleton parity on all five surfaces — and it all switches off under reduce-motion. Nothing here is showy, and nothing pops any more.

---

## 8. Every blocker to 9.5

**Correctness of the picture (highest severity)**
1. One money precision policy (§3.3): `inrWhole` for every derived, averaged, projected or aggregated figure — `home_screen.dart:397`, `insights_screen.dart:192` + engine copy, `card_gauge.dart:65,136`, `transactions_screen.dart:150-161`.
2. Hero `Out this month ₹33k` vs Activity `−₹20,313 out` (§5 F1 #3) — reconcile or rename one.
3. One countdown phrase, used everywhere; today there are five, two on screen at once, one ungrammatical (§5 F1 #4).
4. Insights counts all-time entries under a month label: `4 signals from 268 entries` (`insights_screen.dart:490`, `data.transactions.length`) vs Activity's `36 entries` for October.

**F3 / automatic fail**
5. `Pill` cannot shrink → 63 px overflow on Insights at 360 dp @1.3; **~20 dp with Roboto**, so this is real, not a test-font artifact (`kit.dart:372-389`).
6. Donut legend has no flex on its amount column → 5.5 px at 360 dp @1.0 with the test font only; same root cause as #5 (`charts.dart:196-235`).
7. The suite covers 2 of 7 surfaces, one scale, one theme, no empty state (`widget_smoke_test.dart:107,136`) — put the probe in `test/` (four tabs × 360 @1.0/@1.3 × light/dark + Settings + All messages + empty states).
8. `Clip.none` defeats the chip fade (`transactions_screen.dart:235,277-296`); inbox chips clip with no fade.
9. All-messages route leaves the last row behind the system bar (`sms_inbox_screen.dart:267-271`).
10. No goldens; no RTL pass.

**F1**
11. The pace chart's linear scale hides 24 of 25 days and pins the average to the baseline (`charts.dart:472-506`).
12. Prose inside cards (hero 2 paragraphs, pace method sentence, three section subtitles).
13. The 1.0:1 selected chip (`inbox_filter_bar.dart:65-70`).
14. Home content collides with the status bar when scrolled (`home_screen.dart:54-57`).
15. Card face is inert and the carousel peek is too small to read (`cards_screen.dart:99`, `viewportFraction: 0.92`).
16. Unlabelled insight amounts, and the same amount placed two different ways on Home vs Insights (`insight_tile.dart:115-121` vs `home_screen.dart:1059-1068`).
17. `Insight.action` computed and never consumed; `CategoryBreakdownRow` not tappable — two dead ends.

**F2**
18. Haptics at 2 of ~15 interaction points; none on tab change or scan start.
19. Tab change has no transition and no feedback (`app.dart:163-179`).
20. Category selection is not optimistic and gives no confirmation (`txn_detail_sheet.dart:117-122`).
21. Dismissing the review banner has no undo and no toast.

**F4**
22. `_InsightPreview` duplicates `InsightTile` and loses four behaviours (`home_screen.dart:1008-1097`).
23. Two filter-chip implementations; the new one is the broken one.
24. `home_screen.dart` at 1,229 lines.
25. `_totals` re-derives `MonthlySummary` and is called twice per day group inside build.
26. `dart format` would change 44 of 59 files.
27. `_themeController` swallows a missing provider.

**F5**
28. 28×28 pager dots (`cards_screen.dart:226-228`).
29. `Pill`'s non-shrinkable label (same as #5, from the a11y side).
30. No audit above 1.3×; `cardFaceHeight` clamps at 1.6.

**F6**
31. Four root `watch`es + `IndexedStack`.
32. Activity `ListView(children:)` not virtualised.
33. One `AnimationController` per `MoneyText`, one per row; search rebuilds per keystroke with no debounce.
34. `DateTime.now()` in build ×3.
35. `DailyBars` repaints via `setState` per frame instead of `AnimatedBuilder`.
36. `_DonutPainter`/`_ArcPainter` compare lists by identity in `shouldRepaint`.

**Process**
37. The build is signed off on `flutter analyze` + a 2-test smoke suite that has never seen the screens it protects. §3 is the direct cost of that.

---

## 9. Three changes with the best score-per-hour

**A. Make the suite see the app it ships, then fix the two overflows — ~1.5 h, ≈ 7.1 → 7.6.**
Move the probe into `test/` (four tabs × 360×800 @1.0 and @1.3 × light/dark, Settings, All messages, an empty-repo pass). It goes red immediately on the 63 px and 24 px `Pill` overflows. Then: wrap the `Pill` label in `Flexible` with `overflow: ellipsis` (`kit.dart:372-389`) and give `_LegendRow`'s amount column a `Flexible` or a 12 sp variant at 1.0× (`charts.dart:196-235`). F3 6.0 → 8.5 (+50 weighted, +0.5 on the score) **and it clears the automatic fail**, which is worth more than every other line here. No other hour in this document buys a gate *and* a fix.

**B. One money format, one countdown — ~1 h, ≈ 7.6 → 7.75.**
Add `inrWhole()` (or `precision:` on `inr`) and use it for derived figures (#1); single-source the due phrase through `billDuePhrase`/`_tidyTitle` and, while in the file, delete `_InsightPreview` in favour of `InsightTile` (#3, #22). One pass removes the biggest trust defect, the "1 days" grammar bug, the 2-days-vs-1-days contradiction and ~90 lines of duplicate widget. F1 8.0 → 8.6, F4 7.0 → 7.4.

**C. Make the primary objects actionable — ~2 h, ≈ 7.75 → 7.95.**
`CardFace(onTap:)` on Cards → a card sheet (cycle spend, the bill, that card's transactions); consume `Insight.action` in `InsightTile` (→ Activity filtered); make `CategoryBreakdownRow` open Activity filtered; `HapticFeedback.selectionClick()` on tab change and `lightImpact()` on scan start. Four dead ends closed and the haptic surface grows from 2 points to 4. F2 7.5 → 8.3, F5 +0.3.

**Cheapest fourth, if there is half an hour:** `dart format lib test` and delete the light-only `T.ink*` aliases (`design_tokens.dart:265-289`) so dark mode cannot regress by omission. F4 +0.3.

---

## 10. What would make this a 9.5

The craft is close. The hero, the card faces and dark mode are already at the bar, and the a11y debt that capped round 1 is paid. What is missing is the layer that makes the numbers *indistinguishable from a bank's*:

- **one decided money format** (whole rupees everywhere except a single stored amount),
- **one decided countdown string**,
- **one chart scale that shows the month instead of its outlier**,
- **no card whose only affordance is a screenshot**,
- and **a test that walks the app the way the rubric does**.

Those are five single-file-scale changes, not a redesign. The reason this round lands at 7.1 rather than 8.5 is not that the design is short of the bar — it is that the redesign shipped a 360 dp overflow regression while the green suite looked away, and a reviewer cannot promote a build whose only layout gate has never seen three of its seven screens.

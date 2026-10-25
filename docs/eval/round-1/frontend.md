# Round 1 — Frontend / mobile review

**Reviewer:** frontend + mobile (Flutter), fintech shipping background
**Build under review:** commit `8f0765a` — *"feat: rebuild as offline Indian spend app with guarded parsing"*
**Weighted score: 6.4 / 10** (rubric §1, F1–F6)
**Automatic fails applied: none** (reasoning in §5 — three candidates were tested, none fired)

---

## 1. Scope, method, and what I could not verify

I reviewed the revision that the shipped artefacts are actually built from, and I pinned it with
hashes rather than trusting timestamps:

| Artefact | Method | Result |
|---|---|---|
| `docs/shots/{home,activity,cards,insights}.png` | `flutter build web --release` + `powershell -File tool/shots.ps1` inside a clean `git worktree` at `8f0765a` | byte-identical to the shots taken from the working tree (home `e01ce85f…`, activity `f84c0951…`, cards `78d64772…`, insights `f39b8467…`) |
| `flutter analyze lib` | 21:39, on `8f0765a` | `No issues found! (ran in 58.7s)` |
| `flutter test test/widget_smoke_test.dart` | 21:41, on `8f0765a` | `00:12 +2: All tests passed!` |
| 360×800 @1.3×, all four tabs, scrolled to the end | throwaway widget probe (not committed) | `ERRORS: []` at 360×800 @1.3× and 412×915 @1.0× |
| `docs/shots/device-home.png` | real Galaxy S24 capture (1080×2340 ≈ 412×915 dp) | see §3.1 |

**Two things a reviewer has to state plainly.**

1. **The working tree is not buildable while this review is being written.** At 21:53 a concurrent
   rewrite of `lib/app/design_tokens.dart`, `theme.dart`, `kit.dart`, `card_metrics.dart` and nearly
   every screen landed on top of `8f0765a`. `flutter build web` then failed with
   `Error: Member not found: 'surfaceMuted'` / `'surfaceSunken'`, and a test compile failed inside
   `lib/app/widgets/kit.dart:216:16: Error: Undefined name 'widget'.` The rewrite has since moved on
   (`lib/views/widgets/card_tile.dart` is deleted, `charts.dart` and `card_face.dart` are new,
   `home_screen.dart` is 1,104 lines). **None of that is reviewed here** — it does not compile, so it
   cannot be scored. Every file:line below refers to `8f0765a`, i.e. the revision the screenshots show.
   §8 lists which findings the rewrite may have already fixed, so the team does not re-litigate stale ones.
2. **The web artefact and the widget tree disagree about money on the Cards screen** (§7). That is the
   single most damaging finding in this review and it is reproducible byte-for-byte.

I did not modify `lib/`, `test/`, or any doc other than this file. My throwaway probe and contrast
scripts live in `.review_tmp/` (shared scratch, used by other reviewers too); four zoom crops I made
under `docs/shots/` were removed again.

---

## 2. Scores

| # | Criterion | Weight | Score /10 | Weighted |
|---|---|---|---|---|
| F1 | Visual craft: hierarchy, spacing rhythm, type scale, colour discipline, no raw hex outside tokens | 20 | **7.0** | 140.0 |
| F2 | Motion & feedback: transitions, skeletons, empty states, optimistic updates, haptics | 15 | **5.0** | 75.0 |
| F3 | Layout robustness: 360 dp at 1.0× and 1.3×, overflow, long names, RTL-safe | 20 | **8.0** | 160.0 |
| F4 | Component reuse & code quality: one kit, no duplication, decomposition, no `setState` spaghetti | 15 | **6.0** | 90.0 |
| F5 | Accessibility: contrast, semantics, 48 dp targets, screen-reader sentences for charts | 15 | **5.0** | 75.0 |
| F6 | Performance: rebuild scope, const usage, painters vs images, list virtualisation | 15 | **6.5** | 97.5 |
| | **Total** | **100** | | **637.5 → 6.4** |

Anchor check: *7–8.4 = "works, but feels like a first version."* That is exactly where this sits for
visual craft, and the accessibility and motion scores pull it under. It is materially better than a
prototype and materially short of a shipped fintech app.

---

## 3. Evidence per criterion

### F1 — Visual craft (7.0)

**What is right, and it is real.** The token layer is enforced rather than aspirational: outside
`lib/app/theme.dart` there is **no raw `Color(0x…)` in any view** (grep of every Dart file under `lib/`),
spacing is the 4 pt scale (`design_tokens.dart:55-63`), radii are a 5-step scale, money is tabular
everywhere via `fontFeatures: tabularFigures` (`design_tokens.dart:159-174`), and there is exactly one
gradient (`heroGradient`, used once). Status colours always travel with a word — the band pill prints
"High" next to the red bar (`card_tile.dart:77-82`), the insight tone prints a chip
(`insight_tile.dart:54-60`). The page gutter is a constant 20 dp on all four screens.

**Where it loses the point.**

1. **Money precision is not a policy, it is an accident of the data.** On the device shot the hero
   reads `₹32,998` and the very next line reads `On track for about ₹40,917.52 by 31 Oct`
   (`device-home.png`). On the web shot the hero reads `₹1,37,269.37` while the three stats under it
   read `₹1.3L / ₹12k / ₹5.5k` (`home.png`). In one card tile: `₹75,182.52 / ₹1,50,000` on one line and
   `₹60k` two rows later (`card_tile.dart:100` vs `:122`). `inr()` keeps paise when non-zero
   (`money.dart:44-48`) and `inrCompact()` rounds to whole rupees and appends k/L (`money.dart:51-64`);
   nothing decides *which* is correct on a hero or a projection. The projection line
   (`home_screen.dart:268`) is the worst offender: it is derived from an estimate and printed to the
   paisa, which is false precision in a product that is otherwise careful.
2. **Category colour is assigned by rank, not identity.** `home_screen.dart:644` colours the i-th row
   with `T.chart[i % T.chart.length]`; `txn_common.dart:9` colours the same category by
   `kind.index % 8` elsewhere. So Shopping is emerald on Home and something else on Activity, and the
   Home legend re-shuffles every time two categories swap places month to month. Colour stops being a
   key and becomes decoration.
3. **Two icon vocabularies for the same categories.** `home_screen.dart:1068-1085` maps transport to
   `directions_car`, groceries to `shopping_basket`, health to `favorite`; `txn_common.dart:12-29` maps
   the same kinds to `directions_bus`, `local_grocery_store`, `medical_services`. Same data, two
   visual languages, one screen apart.
4. **The per-row bar has no fixed axis.** In `home_screen.dart:697-719` the `ShareBar` sits in the same
   `Row` as the change pill, so the track is ~52 px shorter on rows that have a pill. In `device-home.png`
   the Shopping track ends at x≈831 and the Other/Food tracks end at x≈648: the chart has a different
   scale on every row, so equal shares would draw unequal lengths.
5. **A card per section, eleven times.** Hero, notice, category card, card strip, insight card, recent
   card — all the same white surface, 1 px `outlineVariant`, 16 dp radius. The rhythm is consistent to
   the point of monotony: nothing on Home is visually more urgent than anything else except by tint.
6. **Ambiguous hero labels.** `Came in / Left / Per day` (`home_screen.dart:180-188`, rendered in
   `device-home.png` as `Came in ₹37k · Left ₹4.1k · Per day ₹1.3k`). "Left" reads as "left over" or
   "left the account"; "Per day" does not say *spent* per day. The hero is the one place where a label
   must be unambiguous.
7. All-caps eyebrow `SPENT THIS MONTH` with 1.1 letter-spacing (`home_screen.dart:210-217`) is the only
   all-caps string in the product; the rest of the app is sentence case, so it reads as a borrowed
   template rather than a system.
8. No "updated at" anywhere above the fold. The privacy footer (`smsRead`, `needsReview`) is the last
   element of a long scroll (`home_screen.dart:128-131`), and `lastScanAt` — which exists in the data
   (`finance_repository.dart:37`) — is only surfaced in Settings (`settings_screen.dart:49`).

### F2 — Motion & feedback (5.0)

Skeletons exist and are honest: `SkeletonBox` (`kit.dart:359-401`) with Home (`home_screen.dart:1154`),
Activity (`transactions_screen.dart:300`) and Cards (`cards_screen.dart:121`) variants. Empty states
take a primary and secondary action (`kit.dart:189-246`). `RefreshIndicator` on three screens.

But:

- **Zero haptics.** `HapticFeedback` appears 0 times in `lib/`. Not on scan start, not on category
  selection, not on destructive confirm.
- **No motion at all beyond the skeleton pulse.** A grep for `Animated*|Tween|AnimationController|Hero(`
  across `lib/` returns only the skeleton's controller and the *inert* `MoneyText` builder. The only
  two `MoneyText` call sites pass `animate: false` (`home_screen.dart:259-263`, `insight_tile.dart:75`),
  so `kit.dart:118-128` is dead code. Tab switches are an `IndexedStack` index change with no
  transition (`app.dart:140-151`); numbers never cross-fade, so the screen *pops* on every data change.
- **Insights shows a false empty state while loading.** `insights_screen.dart:26` branches on
  `data.isEmpty` with no `isLoading` guard, while `Home`, `Activity` and `Cards` all check
  `isLoading` first. On cold start `AppState._data` is `HomeData.empty` (`app_state.dart:25,40`), so
  Insights prints "Nothing to analyse yet" until the DB read finishes, then flips to a full list.
- **No optimistic update, no in-flight state on the one write path.** Tapping a category chip awaits
  the repository and a full reload before anything changes (`txn_detail_sheet.dart:118-124` →
  `app_state.dart:132-144`). On a mid-range phone the chip does not highlight for the DB round-trip;
  there is no spinner, no toast, no haptic.
- **Wrong confirmation copy.** After "Clear all data" the snackbar says "Local data stays on this
  phone." (`settings_screen.dart:241-243`). It never says the data was cleared.

### F3 — Layout robustness (8.0)

This is the strongest engineering area, and it is deliberate rather than lucky:

- `flutter analyze lib` → **No issues found** (58.7 s).
- `flutter test test/widget_smoke_test.dart` → **2/2 pass** at 360×800 with `textScaleFactorTestValue = 1.3`
  (`widget_smoke_test.dart:71`).
- My own sweep at 360×800 @1.3× and 412×915 @1.0×, walking all four tabs and scrolling each list,
  produced **no overflow exceptions** in either configuration.
- The reflow logic is real: the hero lays three money columns out as a `Row` below 1.2× and as a
  two-column `Wrap` at or above it, driven by an actual text-scale measurement
  (`home_screen.dart:280-309`); the header uses `Wrap` with `spaceBetween` so the delta pill drops to
  its own run instead of overflowing (`home_screen.dart:203-253`); the card strip is an unbounded
  `Row` inside a horizontal `SingleChildScrollView` rather than a fixed-height `ListView`
  (`home_screen.dart:746-761`); money is never flexed or ellipsized (`home_screen.dart:688-693`).

**Why not 9.5.** The *repo's* test does not cover the claim made in its own header comment. It pumps
Home and Cards only (`widget_smoke_test.dart:107,136`) and scrolls Home just far enough to see
"Where it went" (`:118`). It never enters Activity, Insights, Settings or onboarding, never renders an
empty state, never runs at 1.0×, and never scrolls a long list — so the Activity list (69 rows in demo)
and the whole Insights tree are unverified by the suite that is cited as proof. My probe found no
overflow, but that guarantee currently lives in a throwaway file, not in `test/`.

Visible roughness: the activity filter chips hard-clip mid-chip at the right edge
(`activity.png`) with no fade or trailing gutter, which reads as a bug rather than as "more to the
right". The card mini-stats prefer ellipsis to reflow (`card_tile.dart:199-215`), and at 1.3× the "Due"
value wraps to two lines inside a 13.5 sp tile. And nothing in the suite or the code addresses RTL.

### F4 — Component reuse & code quality (6.0)

The kit is real and it is used: `AppCard`, `SectionHeader`, `Pill`, `EmptyState`, `NoticeBanner`,
`ShareBar`, `SkeletonBox` (`kit.dart`), and screens are `StatelessWidget`s composed of private
widgets — there is no `setState` spaghetti (three `StatefulWidget`s, all with narrow local state).

The problem is that the kit is bypassed exactly where it matters:

1. **Home re-implements the transaction row.** `_RecentRow` (`home_screen.dart:961-1029`) duplicates
   `TxnRow` (`txn_row.dart:12-131`) — same 38-40 dp icon tile, same title/subtitle, same tabular amount,
   minus the semantics and **minus the tap**. So the same merchant row opens a detail sheet on Activity
   and does nothing on Home. Two implementations, one behavioural regression.
2. **Band mapping exists twice**: `home_screen.dart:853-865` and `card_gauge.dart:13-25` are the same
   two switches over `UtilizationBand`.
3. **Icon map exists twice, with different answers** (`home_screen.dart:1068` vs `txn_common.dart:12`).
4. **Month names are hand-written four times** (`home_screen.dart:149-162`, `:330-344`,
   `txn_common.dart:97-110`, `:112-125`) plus a third formatter in Settings.
5. **`_totals` re-derives what `MonthlySummary` already owns** (`transactions_screen.dart:321-339`),
   and disagrees with it on cash — see §5.
6. `home_screen.dart` is **1,174 lines** with ten private widget classes; the hero, the notice, the
   category card, the strip, the insight preview, the recent list and the footer all live in one file.
   Nothing here is wrong, but it is where the duplication above grew.
7. `_themeController` swallows `ProviderNotFoundException` (`settings_screen.dart:248-254`) so a
   dropped provider silently removes a settings section instead of failing loudly.

### F5 — Accessibility (5.0) — measured, not asserted

Contrast computed from the token values (WCAG 2.1, sRGB):

| Pair | Ratio | Verdict |
|---|---|---|
| `inkMuted` `#78877D` on `surface` `#FFFFFF` | **3.78:1** | fails AA 4.5:1 for normal text |
| `inkMuted` on page `bg` `#F6F7F4` | **3.51:1** | fails |
| hero caption at 78 % white on `#0E7A5F` | **3.88:1** | fails (11.5 sp) |
| hero caption at 72 % white | **3.57:1** | fails (12 sp) |
| hero caption at 82 % white | **4.05:1** | fails (13 sp) |
| `inkSecondary` `#4A5A50` on white | 7.32:1 | pass |
| status pills (positive/caution/danger/info) | 4.91–5.82:1 | pass |
| `primary` on white | 5.29:1 | pass |

`inkMuted` is the app's most-used secondary colour — merchant subtitles, timestamps, "statement day not
set", the privacy footer, the demo disclaimer — always at `bodySmall` 12.5 sp
(`design_tokens.dart:144-149`). The hero's three captions are the same class of failure on the one card
that carries the headline number. So the *important* text is fine and the *supporting* text — the text
that makes the numbers trustworthy — is not.

Tap targets:

- `SectionHeader`'s action is `minimumSize: Size(0, 36)` with `MaterialTapTargetSize.shrinkWrap`
  (`kit.dart:80-88`) → **36 dp**, below the 48 dp minimum, on "All categories", "Manage", "All insights",
  "See all" — the most-tapped secondary actions in the app.
- `NoticeBanner`'s action is a bare `GestureDetector` around a 13 sp `Text` (`kit.dart:298-310`): ~18 dp
  tall, no `button: true`, no `Semantics` label. A screen reader reads "View" as plain prose and a thumb
  hits it about half the time.
- Everything else is correct: `FilledButton`/`OutlinedButton` carry `minimumSize: Size(0,48)`
  (`theme.dart:88,97`), `IconButton` is 48 by default, nav labels are always shown.

Charts have no screen-reader sentences. The utilisation ring does (`card_gauge.dart:50-53`), the txn row
does a genuinely good job (`txn_row.dart:47-57`: title, details, amount, merge/review state in one
string), and the change pill does (`home_screen.dart:706-708`). But `ShareBar` (`kit.dart:322-356`) and
the category breakdown rows (`insight_breakdowns.dart:115-133`) expose nothing, so the two most
quantitative visuals in the product — "where the money went" and the per-category share — read as a
list of loose fragments. `transactions_screen.dart` contains **no `Semantics` at all**.

### F6 — Performance (6.5)

Good: 580 `const` usages across `lib/`; tokens are `static const`; no bitmap assets (the icon font is
tree-shaken from 1.6 MB to 16 KB per the build log); the only `CustomPainter` is the ring with a
correct `shouldRepaint` (`card_gauge.dart:131-136`); DB/demo loads are async and off the build path.

Bad:

1. **Rebuild scope is the whole app.** Every screen takes `context.watch<AppState>()` at its root —
   `home_screen.dart:27`, `transactions_screen.dart:37`, `cards_screen.dart:20`,
   `insights_screen.dart:21` — and `AppShell` keeps all four alive in an `IndexedStack`
   (`app.dart:140-151`). One `notifyListeners()` (scan progress ticks, a demo toggle, a single
   category tap) rebuilds four screens and every child in them. There is no `Selector`, no split of
   "data" from "scan state", and no `const` boundary that could short-circuit it.
2. **Activity is not virtualised.** `ListView(children: [...])` builds the entire month eagerly
   (`transactions_screen.dart:77-257`) — 69 rows in the demo, unbounded on a real inbox.
3. **`IntrinsicHeight` per insight tile** (`insight_tile.dart:43`) forces a second layout pass for every
   card in a list of N, purely to make a 4 dp stripe stretch.
4. `DateTime.now()` inside `build` (`home_screen.dart:140`, `:1042`) makes output rebuild-dependent and
   untestable, and will re-render the greeting on any unrelated notify.
5. Three independent `AnimationController`s in the home skeleton (`kit.dart:370`) with no
   `RepaintBoundary` around the skeleton column.

---

## 4. What the screenshots actually show (hierarchy, type, colour, glanceability)

**Home** (`home.png`, `device-home.png`). Hierarchy is correct and it is the best thing in the build:
eyebrow → spend → projection → three stats → exclusion note. The exclusion line ("Excludes ₹94k in card
bills and transfers") is exactly the sentence a spend tracker needs and nobody writes. Numbers are
glanceable: 34-40 sp bold, tabular, white on emerald, ~4.2:1 against the gradient for the headline.
Below the hero the two full-width alert banners (fraud, bill due) occupy ~190 dp before "Where it went"
starts at y≈490 of 915 — on a 360×800 phone the category card is entirely below the fold, so the first
screen answers "how much" but not "where". On the web shot the fraud banner's body is clipped mid-URL
(`…KYC now: htt…`) because `_CompactNotice` truncates at 90 chars in the call site
(`home_screen.dart:499`) rather than at a word boundary.

**Activity** (`activity.png`). The month card is good: "Spent" + one big number + a single dense line of
context (`₹1,25,000 in · ₹1,42,269.37 out · 69 entries`). Day headers with a right-aligned day total are
the right pattern. But: every row repeats `· UPI`, which carries no information, and no row shows a
*time*, so the only temporal resolution in a ledger is the day. Rows are 56 dp with a 40 dp category
tile, amounts right-aligned tabular — scanning works. The chip row clipping is the one visual break.

**Cards** (`cards.png`). The ring is a clean single focal point, the caption is honest about the
denominator ("of ₹8,00,000 limit across 3 cards"), and the 3-up summary is readable. Then the card tiles
are too tall: a warning banner + header + % row + bar + four mini-tiles + an advice sentence each, so one
card fills most of the viewport and the second card's banner is already sliding under the nav bar. And
the numbers on that tile contradict each other — §7.

**Insights** (`insights.png`). This is the most convincing screen: the duplicate-charge card names the
merchant, the amount, the window and the action ("If this was one payment, ask for a refund"); the
utilisation card gives the number, the deadline and a remedy. The "Needs attention" / everything-else
split is right, and the tone is calm. Two nits: every card is the same height-weight rectangle with a
4 dp tone stripe, so urgency is only legible by colour; and the utilisation sentence contradicts itself
in exactly the way §7 describes.

---

## 5. Automatic-fail assessment (rubric §1)

I tested all three and applied **none**:

1. **Visible layout overflow** — not present. Two configurations, four tabs, lists scrolled: zero
   exceptions. The clipped chip row is clipping-by-design (horizontal scroll), not a `RenderFlex`
   overflow, so it is scored under F3, not failed.
2. **A screen that cannot show an empty state** — all five surfaces can (`home_screen.dart:1119`,
   `transactions_screen.dart:270`, `cards_screen.dart:27`, `insights_screen.dart:27`,
   `onboarding_screen.dart`). Insights shows the *wrong* state while loading (F2), which is a different
   bug.
3. **Inconsistent money formatting** — **this is the closest call in the review.** The symbol (₹),
   grouping (`en_IN` lakh/crore via `NumberFormat`), sign convention (`+` income, `−` spend, no sign for
   transfers) and decimal rule are consistent *functions* used everywhere (`money.dart:44-64`). What
   varies is *precision policy* — full paise on some surfaces, whole rupees and k/L on others, `.52` on
   a projection. That is an information-design failure (scored in F1, §3.1) rather than a formatting
   bug, so I did not fire the cap. A stricter reviewer could fire it; the fix is the same either way.

One number does fail a different, unlisted invariant and I want it on the record: Activity's headline
`Spent` excludes cash while the same card's `out` includes it (`transactions_screen.dart:326-337`), so
the card prints `Spent ₹1,37,269.37` directly above `₹1,42,269.37 out` with no explanation of the gap.
That is not a formatting fail; it is a semantics fail, and it belongs to the finance reviewer — but it
is the same trust wound as §7.

---

## 6. Five strongest things

1. **The token layer is real and enforced.** No raw hex in any view; 4 pt spacing; a radius and type
   scale with tabular figures; one gradient used once. The four screens genuinely look like one product,
   which is the thing most rebuilt Flutter apps never achieve.
2. **The hero is a decision surface, not a number.** Spend → projection → came-in/left/per-day →
   "Excludes ₹1.5k/₹94k in card bills and transfers" + "On track for about … by 31 Oct"
   (`home_screen.dart:180-323`). It answers "how much, is anything wrong, and what is *not* in this
   number" without a tap, and it states the exclusion in words rather than a footnote.
3. **Layout robustness is engineered.** The `LayoutBuilder`-driven 3→2 column reflow at ≥1.2× text
   (`home_screen.dart:280-309`), the unbounded `Row` inside a horizontal scroll view instead of a
   fixed-height `ListView` (`:746-761`), and the rule that money never flexes. `flutter analyze` clean,
   smoke test green at 360×800 @1.3×, and my own four-tab sweep found no overflow at either size.
4. **Empty states and failure copy respect the user.** `EmptyState` takes icon/title/body/primary/
   secondary (`kit.dart:189-246`); every screen supplies domain-specific copy plus a demo escape hatch;
   `AppState._friendly` turns permission and platform failures into plain English
   (`app_state.dart:194-204`), including the honest "SMS scanning works on Android only. Try demo data
   instead."
5. **Security posture is visible in the UI, not just in the README.** Phishing messages are quarantined
   with a "Why this was flagged" sheet that ends "It was kept out of your spending totals, and no link
   was opened" (`home_screen.dart:585-599`), and the privacy claim appears on the surfaces where a user
   would worry (Home footer, Settings header, Cards footer). For an app that reads SMS, that instinct is
   exactly right and it is rare.

---

## 7. The Cards / Insights money contradiction (reproducible)

This is the finding I would escalate on day one.

**What the shipped web build prints** (`cards.png`, byte-identical rebuild of `8f0765a`):

> ring: **0 %** used · caption: "of ₹8,00,000 limit across 3 cards"
> HDFC tile: **50 % used** · **₹0 / ₹1,50,000** · This cycle **₹0** · band pill **High**
> advice: "This can affect your score. Clear part of it before the next statement."

**What the same commit prints through the widget tree** (my probe at 360×800 @1.3× and 412×915 @1.0×):

> ring **14 %** · **₹75,182.52 / ₹1,50,000** · This cycle **₹60k**

**And what the engine says** (`dart run tool/cards_check.dart`):

```
totalUtilization=0.1369847375
HDFC Bank •••• 4821
  outstanding=₹75,182.52 limit=₹1,50,000 util=0.5012168 band=high
```

The same contradiction is baked into the Insights copy (`insights.png`): *"HDFC Millennia is at 50 %
utilisation — ₹0 of ₹1,50,000 used … Paying ₹45,000 would bring it under 30 %."* The ₹45,000 is
`headroomTo30` computed from an outstanding of **zero** (`card_metrics.dart:140-145`), which is why the
sentence recommends paying money that is not owed.

So: **50 % used, ₹0 used, and ₹0 spent this cycle cannot all be true of one card**, and the wording
built on top of them is nonsense. Four numbers on one screen, mutually exclusive.

What I can say with confidence:

- The engine is internally consistent on the VM (`tool/cards_check.dart`), and the tile, bar, band and
  caption all read the same `CardMetrics` object (`card_tile.dart:24-26,100,122`) — the code *intends*
  one source of truth and, on the VM, achieves it.
- The web artefact of the same commit does not. I ruled out a stale `build/web` by rebuilding the
  commit in a clean worktree and reproducing the identical PNG hash.
- Therefore either the web build is running a different `card_metrics` path than the VM, or
  `outstandingPaise`/`spentThisCyclePaise` are being lost on the web target. The two fields that print
  zero are exactly the two set through `.clamp(0, 1 << 62)` (`card_metrics.dart:251-253`) while the
  field that stays correct (`utilization`, `:255`) is not. That is where I would bisect first —
  `1 << 62` is 2^62, which is representable but pathological on a double-backed `int` target.

Whatever the mechanism, the reviewable artefact lies about money, and the copy is generated in a way
that lets it lie. Two fixes are needed, not one: find the numeric divergence, **and** make the
contradiction unrepresentable (render the sentence from one record, not three).

---

## 8. Every blocker to 9.5

**Correctness of the picture (highest severity)**
1. The §7 contradiction on Cards and in the Insights copy, plus no test that asserts "% and amount
   agree" — the one invariant a fintech screen must never break.
2. Activity prints `Spent ₹1,37,269.37` above `₹1,42,269.37 out` with no explanation (cash is in `out`,
   not in `Spent`: `transactions_screen.dart:326-337`).
3. Money precision has no policy: `₹32,998` beside `₹40,917.52` (`device-home.png`), `₹75,182.52` beside
   `₹60k` (`card_tile.dart:100` vs `:122`), a projection printed to the paisa (`home_screen.dart:268`).

**F1**
4. Category colour keyed to rank on Home (`home_screen.dart:644`) vs identity elsewhere
   (`txn_common.dart:9`) — hue changes with the ranking and differs between screens.
5. Two icon vocabularies for one taxonomy (`home_screen.dart:1068` vs `txn_common.dart:12`).
6. Per-row bars share a row with a variable-width pill, so the axis is not constant
   (`home_screen.dart:697-719`).
7. Hero labels `Left` / `Per day` are ambiguous (`home_screen.dart:180-188`).
8. Eleven identical bordered cards; no visual weight for urgency beyond tint.
9. Only all-caps string in the product is the hero eyebrow (`home_screen.dart:210-217`).
10. No "updated / synced" timestamp above the fold; `lastScanAt` exists but is buried in Settings.
11. The fraud banner body is truncated at 90 chars mid-URL (`home_screen.dart:499`).

**F2**
12. Zero haptics anywhere (0 hits for `HapticFeedback`).
13. No transitions: tab switch is an `IndexedStack` index change; numbers never animate
    (`MoneyText`'s animation is dead, `kit.dart:118-128`).
14. Insights has no loading branch and shows "Nothing to analyse yet" while the first load runs
    (`insights_screen.dart:26`).
15. Category selection has no optimistic state, no spinner, no confirmation (`txn_detail_sheet.dart:118-124`).
16. "Clear all data" confirms with "Local data stays on this phone." (`settings_screen.dart:241-243`).

**F3**
17. The suite that is cited as proof covers 2 of 6 surfaces, no empty states, no 1.0×, and never scrolls a
    long list (`widget_smoke_test.dart:107,136`).
18. No golden tests in the repo (mine were throwaway), so layout regressions are invisible.
19. Filter chips hard-clip mid-chip at the right edge (`activity.png`).
20. Card mini-stats ellipsize rather than reflow (`card_tile.dart:199-215`); no RTL coverage.

**F4**
21. `home_screen.dart` is 1,174 lines / 10 private widgets.
22. `_RecentRow` duplicates `TxnRow` **and loses the tap** (`home_screen.dart:961` vs `txn_row.dart:12`):
    merchant rows on Home are dead ends.
23. Duplicated band mapping (`home_screen.dart:853` vs `card_gauge.dart:13`) and month tables (×4).
24. `_totals` re-derives `MonthlySummary` and disagrees with it on cash (`transactions_screen.dart:321`).
25. `_themeController` swallows a missing provider (`settings_screen.dart:248-254`).

**F5**
26. `inkMuted` at **3.78:1** (white) / **3.51:1** (page) on 12.5 sp secondary text — the app's most-used
    muted tone (`design_tokens.dart:144-149`).
27. Hero captions at **3.57–4.05:1** on the gradient (`home_screen.dart:213-217,272-275,317-321`).
28. `SectionHeader` action is **36 dp** (`kit.dart:80-88`).
29. `NoticeBanner` action is an 18 dp `GestureDetector` with no button semantics (`kit.dart:298-310`).
30. No screen-reader sentence for `ShareBar` / category rows (`kit.dart:322`, `insight_breakdowns.dart:115`);
    no `Semantics` at all in `transactions_screen.dart`.
31. No audit above 1.3× text, no bold-text or reduce-motion test (reduce-motion is only consulted in the
    in-flight `MoneyText`).

**F6**
32. Four root `context.watch<AppState>()` calls + `IndexedStack` = every notify rebuilds every screen
    (`home_screen.dart:27`, `transactions_screen.dart:37`, `cards_screen.dart:20`, `insights_screen.dart:21`).
33. Activity builds all rows eagerly (`transactions_screen.dart:77`).
34. `IntrinsicHeight` per insight tile (`insight_tile.dart:43`).
35. `DateTime.now()` in `build` (`home_screen.dart:140,1042`).

**Process (blocks a 9.5 regardless of the above)**
36. At the time of review the working tree does not compile (`surfaceMuted` / `surfaceSunken` missing
    from the rewritten tokens; `kit.dart:216` referencing `widget` outside `build`). A revision that
    cannot be built cannot be signed off, and the screenshots and the code will drift apart — which is
    precisely how §7 went unnoticed.
37. **May already be fixed by the in-flight rewrite** (re-check, don't re-litigate): tokens/theme/kit
    (F5 contrast, tap targets), `txn_row.dart` + `txn_common.dart` (F4 duplication), `card_tile.dart`
    → `card_face.dart` and new `charts.dart` (F1 colour/axis, F4 band duplication), and every screen
    file (F5 semantics). `home_screen.dart` at 1,104 lines still holds the hero and `_RecentRow`.

---

## 9. Three changes with the best score-per-hour

Ranked by weighted points gained per engineer-hour. (Item 1 in §8 is not in this list because it is a
*defect*, not a score optimisation — but it must be fixed first regardless of score.)

**A. Kit accessibility pass — ~1 h, ≈ +5 weighted points (6.4 → ~7.1).**
One file plus three token values: raise `inkMuted` to ≈`#5A6A60` (4.6:1 on `#F6F7F4`), add a
`T.inkOnHero`/`inkOnHeroMuted` pair at ≥4.5:1 instead of `Colors.white.withValues(alpha: …)` at 72–82 %
(`home_screen.dart:213-321`), set `SectionHeader`'s action to `minimumSize: Size(48,48)`
(`kit.dart:80-88`), turn `NoticeBanner`'s `GestureDetector` into a `TextButton` with a `Semantics`
label (`kit.dart:298-310`), and add one semantics sentence each to `ShareBar` and the category rows.
F5 goes 5.0 → ~8.0 and F1 gains a little. This is the best ratio in the build by a wide margin because
it is a single-file change with measured outcomes.

**B. Motion, haptics and loading parity — ~1.5 h, ≈ +4 weighted points (F2 5.0 → ~7.5).**
Add `HapticFeedback.selectionClick()` on chip/tab selection and `lightImpact` on scan start; add an
`AnimatedSwitcher`/`TweenAnimationBuilder` around the hero and Activity headline (wiring the already
written `MoneyText` animation, `kit.dart:96-130`); give Insights the same `isLoading` skeleton branch the
other three screens have (`insights_screen.dart:26`); make the category chip optimistically selected
before the round-trip (`txn_detail_sheet.dart:118`); fix the post-clear snackbar copy. Cheap, visible,
and it removes the "false empty state" defect at the same time.

**C. Delete the duplicated row/icon/colour/month primitives — ~2.5 h, ≈ +4 weighted points
(F4 6.0 → ~8.0, F1 +0.5).**
Make Home's Recent list use `TxnRow` with `onTap: () => showTransactionDetail(...)` (fixes the dead-end
rows and deletes ~70 lines); delete `_iconFor` in favour of `txn_common.categoryIcon`; delete
`_bandColor`/`_bandTone` in favour of `card_gauge.utilizationBandColor`/`Tone`; key category colour to
the category kind (or to a stable hash) instead of list position; move the hero, notice, category card
and recent list into `views/widgets/` so `home_screen.dart` drops under ~300 lines. Two of these fix
visible defects (untappable rows, colour drift across screens), so it pays twice.

**Cheapest fourth, if there is an hour left:** put a four-tab, two-size, long-list golden test into
`test/` (the probe I wrote does this in ~120 lines). It converts "no overflow" from a claim into a
regression gate and stops F3 from silently decaying.

---

## 10. What would make this a 9.5

The visual system and the layout engineering are already at the bar. What is missing is the layer that
makes a fintech app trustworthy: **one decided money format, one decided colour/icon key, one decided
loading and motion language, and copy that cannot contradict the numbers it quotes.** All four are
single-file-scale changes. None of them requires a redesign — which is why I would expect the next round
to move 6.4 → 8+ without new screens, provided the build is kept compilable and the screenshots are
regenerated from the commit under review.

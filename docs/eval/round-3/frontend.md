# Round 3 — Frontend / mobile review

**Reviewer:** frontend + mobile (Flutter), fintech shipping background
**Build under review:** `5263c06` (main, clean tree apart from untracked `assets/`, `lib/services/sms/sms_model.dart`, `tool/train_sms_model.py`, which I did not judge)
**Round 2: 7.1 / 10 → Round 3: 7.9 / 10** (+0.8)
**Automatic fails applied: none.** The round-2 overflow is fixed, and the suite now has a layout gate that would have caught it. One new defect is not on the automatic-fail list but is worse than an overflow for a money app: **mojibake (`Ã¢â‚¬â€`, `â€”`, `â€¦`) in four strings users see** (§5 F1 #1).

---

## 1. Scope and method

Scored against `docs/eval/rubric.md` (F1–F6). I scored the change since round 2 (`c87e42b..5263c06`: 87 files, +10,376 / −584, of which `lib/views` + `lib/app` are +2,478 / −496), not the app from scratch.

| Check | Result |
|---|---|
| `flutter analyze lib` | **No issues found** (23.9 s) |
| `flutter test` | **316 / 316 passed** (CLAUDE.md still says "238 pass / 2 known failures" and "240/240", so it is out of date) |
| `dart format --output=none --set-exit-if-changed lib` | **60 of 75 files would change** (round 2: 44 of 59) |
| Device screenshots | **Not regenerated: the phone is not connected.** Everything in `docs/shots/` is from 25 Oct (round 2) and **predates every change reviewed here**. No shot of Salary & statements exists. I did not use any screenshot as evidence for this round. |
| My own probes | `.review_tmp/r3_probe_test.dart`: Statements (full, no salary, empty), cycle detail, row sheet, password sheet (with error, hints open), review sheet (unverified rows, warnings). All at 360×800 × {1.0, 1.3, 2.0} × {light, dark}, with 60-character counterparty names and half the rows unverified, scrolled to the end. Also a card face with no limit set. `.review_tmp/r3_semantics_test.dart`: whether the Home hero links are in the semantics tree. |

I did not change anything in `lib/` or `test/`.

---

## 2. Scores

| # | Criterion | Weight | Round 1 | Round 2 | Round 3 | Δ | Weighted |
|---|---|---|---|---|---|---|---|
| F1 | Visual craft | 20 | 7.0 | 8.0 | **8.2** | +0.2 | 164.0 |
| F2 | Motion & feedback | 15 | 5.0 | 7.5 | **7.9** | +0.4 | 118.5 |
| F3 | Layout robustness | 20 | 8.0 | 6.0 | **8.6** | **+2.6** | 172.0 |
| F4 | Component reuse & code quality | 15 | 6.0 | 7.0 | **7.5** | +0.5 | 112.5 |
| F5 | Accessibility | 15 | 5.0 | 7.2 | **7.6** | +0.4 | 114.0 |
| F6 | Performance | 15 | 6.5 | 7.1 | **7.1** | 0.0 | 106.5 |
| | **Total** | 100 | **6.4** | **7.1** | **7.9** | **+0.8** | **787.5** |

Anchor check: 7.9 means "works, but feels like a first version", near the top of that band. Most of the gain is in F3. The overflow is fixed at its root (`Pill`, `_LegendRow`, `ChipStrip`), and a 20-case layout gate now visits all six main surfaces plus the empty states. F1 would have gained much more if three hand-edited files had not shipped mojibake into visible strings. F6 did not move at all: none of the six round-2 performance findings was addressed.

---

## 3. Automatic-fail assessment

### 3.1 Visible layout overflow: **does not fire**

| Where | 1.0× light | 1.0× dark | 1.3× light | 1.3× dark | 2.0× |
|---|---|---|---|---|---|
| Home, Activity, Cards, Insights, Settings, All messages (suite, `test/layout_overflow_test.dart`) | clean | *not run* | clean | clean | not run |
| Empty app, all four tabs, plus All messages with no inbox (suite) | — | — | clean | clean (inbox) | — |
| Statements: full / no salary / empty (my probe) | clean | clean | clean | clean | clean |
| Salary cycle detail with long names and unverified rows (my probe) | clean | clean | clean | clean | **73 px overflow** ×5, `salary_cycle_screen.dart:227` |
| Password sheet with error and hints open (my probe) | clean | clean | clean | clean | clean |
| Review sheet with unverified rows and warnings (my probe) | clean | clean | clean | clean | clean |
| Row sheet, "Is this your salary?" (my probe) | clean | clean | clean | clean | — |

The rubric sets the bar at 1.0× and 1.3×, so the 2.0× overflow does not fire the fail. It is still a real bug. Android 14+ offers up to 200 % font scale, and `_RowTile`'s amount `Text` (`salary_cycle_screen.dart:257-260`) is the only unshrinkable child in that row. It is the same pattern as round 2's `Pill`.

### 3.2 A screen that cannot show an empty state: **does not fire**

New screens: Statements has `_EmptyImport` (`statements_screen.dart:192-248`). The cycle screen has "This cycle changed" (`salary_cycle_screen.dart:36-45`). No salary gets a `NoticeBanner` (`:349-355`). "No transactions found" is a dialog (`:82-101`). An unreadable PDF gets a snackbar (`:66-70`). All seven older surfaces still have their empty states, and the suite now proves it (`layout_overflow_test.dart:308-363`).

### 3.3 Inconsistent money formatting: **does not fire, and it is much further from firing than in round 2**

`lib/app/money_format.dart` is now the single display rule: whole rupees at ₹1,000 and above, paise only below that, `en_IN` grouping, and `moneyCompact` only above a lakh. `grep` finds **no `inr(` / `inrCompact(` call in `lib/views` or `lib/app`** outside the formatter. The one `toStringAsFixed` (`inbox_detail_sheet.dart:82`) seeds an edit field, which is correct. The round-2 "₹812.52 a day" over "₹813" contradiction is gone (`home_screen.dart:256-262` comment and code).

One residual. The rule also rounds **single stored amounts**, so on the new statement screens a row of ₹1,234.56 prints `−₹1,235` and "Balance after: ₹45,679" (`salary_cycle_screen.dart:220,284,302`). That is on a screen whose whole promise is "All balances check out", and the user is holding a PDF that says ₹45,678.90. This is consistent with the declared policy, so I am not firing the fail. It is blocker #4: a bank-statement row and a running balance should print the paise the bank printed.

---

## 4. Round-2 blockers, re-checked

37 round-2 blockers. **Fixed: 17 fully, 5 partly. Open: 15.**

| # | Round-2 blocker | Now |
|---|---|---|
| 1 | One money precision policy | **Fixed**: `money_format.dart`, used everywhere |
| 2 | Hero "out" vs Activity "out" | **Fixed**: Activity uses `SummaryCalculator.forMonth` → `summary.moneyOut` under the same "Out this month" label (`transactions_screen.dart:113-118,214-219`) |
| 3 | One countdown phrase | **Partly fixed**: Home and Insights both use `billDuePhrase` through `withCalendarDueDates` (`insight_tile.dart:68-91`), so the "2 days vs 1 days" contradiction is gone. Still **five implementations**: `card_face.dart:276`, `insight_breakdowns.dart:26`, `txn_common.dart:161`, `txn_common.dart:186`, `insights_engine.dart:169` |
| 4 | Insights counts all entries under a month label | Not re-verified this round |
| 5 | `Pill` cannot shrink (the auto-fail) | **Fixed**: `Flexible` + ellipsis whenever the width is bounded (`kit.dart:369-409`) |
| 6 | Donut legend no flex | **Fixed**: amount column capped at 52 % (`charts.dart`, `_LegendRow`) |
| 7 | Suite covers 2 of 7 surfaces | **Fixed**: 6 surfaces × 3 configs + 2 empty-state passes (`test/layout_overflow_test.dart`), plus 6 statement cases. Gaps listed in §6 |
| 8 | `Clip.none` defeats the chip fade | **Fixed**: `ChipStrip` clips hard and fades with a `ShaderMask` on whichever side has more chips (`kit.dart:413-525`) |
| 9 | All messages sits under the system bar | **Open**: `SafeArea(bottom: false)` (`sms_inbox_screen.dart:277-279`) |
| 10 | No goldens, no RTL | **Open** |
| 11 | Pace chart linear scale | **Open**: `charts.dart` changed only its formatter calls |
| 12 | Prose inside cards | **Worse on Home**: the hero now carries a 3-line money-in sentence plus up to two underlined links (`home_screen.dart:470-530`) |
| 13 | 1.0:1 selected chip | **Fixed**: one `FilterChipView`, ink fill with canvas text, about 16:1 (`kit.dart:527-588`) |
| 14 | Status-bar collision on Home | **Open**: still `SliverAppBar(floating, snap)` with no scrim (`home_screen.dart:69-72`); not re-verified on device |
| 15 | Card face inert | **Partly fixed**: `onTap` opens the edit sheet with a haptic (`cards_screen.dart:104,202-205`), not a card detail (cycle spend, bill, that card's transactions) |
| 16 | Unlabelled insight amounts, two placements | **Fixed**: one `InsightTile` on both screens |
| 17 | `Insight.action` dead, category row not tappable | **Fixed**: `insight_actions.dart` resolves every action to Activity (filtered by category or merchant), a tab, or recurring |
| 18 | Haptics at 2 points | **Partly fixed**: 6 (`kit.dart:568`, `cards_screen.dart:204,229`, `insight_tile.dart:225,267`, `txn_detail_sheet.dart:262`). Still none on tab change, scan, statement import or marking salary |
| 19 | Tab change no transition | **Open**: `IndexedStack`, `setState` only (`app.dart:174-177,191`) |
| 20 | Category selection not optimistic | Not re-verified |
| 21 | Banner dismiss without undo | **Open, and now joined by** insight dismissal "for good" with no undo (`home_screen.dart:1147`, `insights_screen.dart:261`) |
| 22 | `_InsightPreview` duplicate | **Fixed**: deleted, Home renders `InsightTile` (`home_screen.dart:1103-1138`) |
| 23 | Two chip implementations | **Fixed** |
| 24 | `home_screen.dart` 1,229 lines | **Worse: 1,285** |
| 25 | `_totals` twice per group | **Open** (`transactions_screen.dart`, day-group loop) |
| 26 | `dart format` 44/59 | **Worse: 60/75** |
| 27 | `_themeController` swallows provider | Not re-verified |
| 28 | 28×28 pager dots | **Open** (`cards_screen.dart:238-241`) |
| 29 | Pill a11y | **Fixed** with #5 |
| 30 | No audit above 1.3× | **Open**. My 2.0× probe found the 73 px overflow in §3.1 |
| 31 | Four root watches + `IndexedStack` | **Open**, now 11 `context.watch<AppState>()` sites (most on routes, which is fine; the four tab roots are the problem) |
| 32 | Activity not virtualised | **Open**: `ListView(children:)` (`transactions_screen.dart:166`) |
| 33 | `MoneyText` controller per row, search per keystroke | **Open**: `onChanged: (_) => setState(() {})` (`transactions_screen.dart` search field) |
| 34 | `DateTime.now()` in build | **Worse: 5** (`home_screen.dart:207`, `sms_inbox_screen.dart:288`, `transactions_screen.dart:109`, `txn_common.dart:170`, `txn_row.dart:168`) |
| 35 | `DailyBars` `setState` per frame | Not changed |
| 36 | `shouldRepaint` by identity | Not changed |
| 37 | Signed off on a 2-test smoke suite | **Fixed**: a real gate now exists |

---

## 5. Evidence per criterion

### F1 — Visual craft: 8.0 → **8.2**

**Better.** There is one money rule and every screen uses it. One `InsightTile`, one chip and one chip strip. The Activity header now states the same "Out this month" definition as Home. The new statement surfaces are built from the kit (`AppCard`, `IconBadge`, `Pill`, `NoticeBanner`, `SectionHeader`, `EmptyState`) and from palette tokens only: **zero `Color(0x` in `lib/views`**. The salary-cycle card is a good object. It has a range title with a status pill, a 26 dp headline that switches between "Left so far", "Saved this cycle" and "Spent more than came in", the salary to the right in positive ink, a segmented outflow bar, and a legend in `moneyCompact` (`salary_cycle_card.dart:52-176`).

**What holds it at 8.2.**

1. **Mojibake in visible strings, introduced in `bc9e353`.** I confirmed it from the bytes (`c3 83 c2 a2 …`) and by rendering:
   - `card_face.dart:476`: a card with no limit shows **`Ã¢â‚¬â€` / "not set"** in its utilisation ring. My probe rendered a Pluxee face and got the texts `[PLUXEE, Credit card, •••• 4321, No bill due, Spent this cycle, ₹1,200, Ã¢â‚¬â€, not set]`. This is the card face, which is the best object in the app, and the owner has cards with no limit set.
   - `insights_screen.dart:554`: `_preview` ends every fraud preview over 120 characters with **`â€¦`**. Nearly every phishing SMS is longer than 120 characters, and TalkBack reads the garbage aloud through `:394`.
   - `insights_screen.dart:161` and `:181`: "No insights yet **â€”** a few more…" and "Nothing recurring detected yet **â€”** we need three…".
   - Comments in `insight_actions.dart` and `transactions_screen.dart:52` show the same encoding damage. This is the PowerShell `Get-Content | Set-Content` hazard that CLAUDE.md warns about, and nothing in the suite asserts text, so all 316 tests are green.
2. **The pace chart still cannot show the pace** (round-2 #11, unchanged).
3. **The hero is getting wordier, not tighter.** It has a money-in sentence (3 lines), an "included" line (2 lines), a transfers link and a salary link (2 lines) (`home_screen.dart:470-530`). The owner's brief was numbers first.
4. **Bank-statement rows lose their paise** (§3.3). On a reconciliation screen, `−₹1,235` beside `−₹812.52` reads as two precisions in one list.
5. **The new screens use type-scale escapes.** `fontSize: 26` (`salary_cycle_card.dart:455`), `28` (`salary_cycle_screen.dart:285`), `30` (`transactions_screen.dart`), `15.5` and `12.5` (`insight_tile.dart`), and `fontSize: dense ? 12 : 12` (`kit.dart:375`). `T` has a money-large style; these values should be roles in it.
6. **Category colour breaks on the cycle screen.** Every category bar is `p.accent` on a Material `LinearProgressIndicator` (`salary_cycle_screen.dart:194-202`). Everywhere else a category keeps its `categoryColor(kind)` identity, and `ShareBar` is the kit's bar.
7. The account title renders `'SBI savings '` with a trailing space when there is no mask (`statements_screen.dart:276`). The review sheet formats the same title differently (`:583`).

### F2 — Motion & feedback: 7.5 → **7.9**

**Better.** Haptics went from 2 call sites to 6. Card faces open on tap. Insight tiles now act, with a label and arrow, and can be dismissed. "12 to confirm" lands on the review filter (`SmsInboxScreen(initialFilter:)`). `ChipStrip`'s fade appears only on a side that has more to show. Import confirms with honest counts ("12 new transactions added (3 were already there)") and handles re-imports ("already imported") (`statements_screen.dart:105-114`).

**What holds it at 7.9.**

1. **Insight dismissal is permanent and has no undo** (`home_screen.dart:1147`, `insights_screen.dart:261`). The tile disappears on one tap of a 44 dp ✕. Settings › Learned categories shows the right pattern: confirm, then a snackbar with undo.
2. **Import feedback is a 3 dp bar and nothing else** (`statements_screen.dart:179-185`). PDF parsing takes seconds on a 20-page statement. There is no "Reading statement…" text, no step, and no way to cancel.
3. **The wrong-password loop closes the sheet, shows only the 3 dp bar, then reopens the sheet** with the error (`statements_screen.dart:59-80`). The user sees the sheet vanish and come back. Keep the sheet open, put a spinner on "Open", and set the error in place.
4. **Marking a salary gives no confirmation and can strand the user.** `setSalary` then `Navigator.pop` (`salary_cycle_screen.dart:315-341`) shows no snackbar and no undo. If the cycle boundaries move, the screen they are on becomes "This cycle changed. Go back to see the new cycles." That is a dead end created by the user's own correction.
5. **Statements loads with a centred spinner** (`statements_screen.dart:143-144`). Every other surface has a skeleton.
6. Unhandled import errors: only `PdfNeedsPassword`, `PdfWrongPassword` and `PdfUnreadable` are caught. Any other exception (a storage error in `commit`, a parser throw) clears the bar in `finally` and shows nothing.
7. Still no tab transition or tab haptic (`app.dart:174-177`).

### F3 — Layout robustness: 6.0 → **8.6**

**The regression is fixed at its root.** `Pill` shrinks whenever its width is bounded and keeps its intrinsic width inside a horizontal scroller (`kit.dart:390-405`). The legend's amount column is capped. `ChipStrip` clips. The new screens put `Expanded` / `Flexible` / ellipsis / `FittedBox` in the right places, and 60-character counterparties, partially verified accounts, warnings and the hint-expanded password sheet are all clean at 1.0× and 1.3× in both themes (§3.1). The layout gate is real now: it scrolls each screen to the end, drains every error, and has a non-vacuity anchor per screen (`layout_overflow_test.dart:166-228`).

**What holds it at 8.6.**

1. **The gate does not cover what was just built.** `test/statement/statements_screen_test.dart` runs **1.3× only**. It has no 1.0× case, no password sheet, no review sheet, no wrong-password error, no unverified rows, no long names, no no-salary state and no row sheet. My probe covered all of these and found them clean, but the suite would not catch a regression in any of them. The main gate's `_screens` list (`layout_overflow_test.dart:204-252`) does not include Salary & statements, and it never runs **1.0× dark**.
2. **73 px overflow at 2.0×** in the cycle's transaction rows (`salary_cycle_screen.dart:227-260`). The amount needs `Flexible` + `FittedBox`.
3. **Bottom insets.** All messages still uses `SafeArea(bottom: false)` with tail padding (`sms_inbox_screen.dart:277-279`). The new Statements and cycle `ListView`s use a fixed `T.s8` (40 dp) tail and no `SafeArea` (`statements_screen.dart:149`, `salary_cycle_screen.dart:55`). On a 3-button nav bar with edge-to-edge, the last row sits partly under the bar. This needs a device check.
4. The Home hero's no-income branch (with the salary link) is never rendered by any test, because the demo data has income.
5. No goldens and no RTL.

### F4 — Component reuse & code quality: 7.0 → **7.5**

**Better.** These are now single-sourced: `InsightTile` (Home + Insights), `FilterChipView` + `ChipStrip` (Activity + All messages), `money_format.dart` (display rule), `insight_actions.dart` (one action → destination map), `withCalendarDueDates`, and `cycleSegments` (card + detail). `StatementsController` keeps the statement state out of `AppState`, which is the right boundary.

**What holds it at 7.5.**

1. **The new screens re-implement the kit privately.** There is `_Line` (`salary_cycle_screen.dart:118-160`) and a local `line()` closure in the review sheet (`statements_screen.dart:558-573`), which are the same label/amount row. `_CategoryLine` (`salary_cycle_screen.dart:162-207`) copies `CategoryBreakdownRow`/`ShareBar`. `_Legend` (`salary_cycle_card.dart:172-202`) is a third legend row. `_RowTile` (`salary_cycle_screen.dart:209-267`) is a fourth transaction row next to `TxnRow`.
2. **`home_screen.dart` is now 1,285 lines.** Round 1 flagged it at 1,174.
3. **`dart format` would change 60 of 75 files.**
4. **Encoding damage in four source files** (F1 #1). A pre-commit `grep -P '\xC3[\x80-\xBF]'` would have caught it.
5. The countdown phrase is built in five places (§4 #3).
6. `_totals` still re-folds each day group twice inside build.
7. The import flow is a 70-line `while` loop with nested `try` blocks in a `State` (`statements_screen.dart:49-119`). It belongs in the controller as a small state machine (picking → needs password → wrong password → preview → committing), which would also make it testable.

### F5 — Accessibility: 7.2 → **7.6**

**Better.** The invisible selected chip is fixed (1.0 → ~16:1). `Pill` no longer clips text at large sizes. Insight actions and dismiss have tooltips and labels and haptics. The password field has a show/hide toggle with a changing tooltip, `visiblePassword` keyboard, no suggestions or autocorrect, a 64-character cap, and `errorMaxLines: 2`. The cycle card has a spoken sentence ("Cycle 1 Sep – 30 Sep. Salary … Left …"). The hero links are built at `minHeight: 48`.

**What holds it at 7.6.**

1. **The hero links are invisible to TalkBack (verified).** The hero wraps everything in `Semantics(container: true, excludeSemantics: true, label: spoken)` (`home_screen.dart:322-325`). That removes the descendant `_HeroLink` buttons (`:495-530`), and `spoken` does not mention them. My semantics probe on demo data found the "₹… transfers not counted" link **visible = 1, semantics nodes = 0**. The "Import an SBI statement" link is a child of the same subtree, so a screen-reader user cannot reach the new feature from Home. Settings is the only way in for them.
2. **TalkBack reads the mojibake** on fraud previews (`insights_screen.dart:394`) and on a no-limit card's ring.
3. **The pager dots are still 28×28** (`cards_screen.dart:238-241`).
4. **Insight action and dismiss targets are 44 dp tall** (`minimumSize: Size(48, 44)`, `insight_tile.dart:229,277`). The rubric says 48.
5. **The cycle card is read twice.** It has `Semantics(label:)` with no `excludeSemantics` (`salary_cycle_card.dart:51-55`), so TalkBack reads the sentence and then every child text. The cycle screen's category bars are Material progress indicators and announce as "progress bar, 42 percent" with no category name.
6. `_RowTile` is an `InkWell` with no hint (`salary_cycle_screen.dart:221-222`). Nothing tells a screen-reader user that tapping a credit lets them mark salary. The section subtitle says it, but sighted users only.
7. `_HeroLink` uses a `GestureDetector`, so it gives no pressed state or ripple.

### F6 — Performance: 7.1 → **7.1**

Nothing on the round-2 list moved: the tab-root `watch`es under `IndexedStack`, Activity's eager `ListView(children:)`, the per-keystroke `setState` search, `DateTime.now()` in build (now ×5), `DailyBars`' `setState`-per-frame, and identity `shouldRepaint`.

New costs:

- **`Pill` now wraps every instance in a `LayoutBuilder`** (`kit.dart:390`). A `LayoutBuilder` defers its build to layout and cannot share a relayout boundary cheaply. Pills appear in every insight, card and row chip. The fix could be a `Flexible` with `fit: FlexFit.loose`, decided by the caller (or a `bounded` flag), instead of a builder per chip.
- **The cycle screen builds every row eagerly** inside one `Column` in one `AppCard` (`salary_cycle_screen.dart:103-111`). A salary cycle on a busy SBI account is 150–300 rows. It also re-sorts on every build (`:50`) and calls `cycle.salaryRows.contains(row)` (a list scan) per row.
- `StatementsScreen` and `SalaryCycleScreen` both `watch` the whole controller at the root.

These new costs are offset by the cheaper single chip implementation and the deleted `_InsightPreview` tree, so the score holds.

---

## 6. Do the project's layout gates cover the new screens?

The owner asked this directly.

| State | `layout_overflow_test.dart` | `statements_screen_test.dart` | My probe |
|---|---|---|---|
| Statements, empty | — | 1.3× light + dark | 1.0 / 1.3 / 2.0 × both: clean |
| Statements, full with cycles | — | 1.3× light + dark | clean |
| Statements, **no salary found** | — | **no** | clean |
| Statements, **unverified rows** (caution pill) | — | **no** | clean |
| **Long counterparty / payer names** | — | **no** | clean at 1.0 / 1.3; **2.0× overflows** |
| Cycle detail | — | 1.3× light + dark | clean at 1.0 / 1.3 |
| **Password sheet** (plain, error, hints expanded) | — | **no** | clean |
| **Wrong-password flow** (sheet → error → sheet) | — | **no** (only `pdf_reader_test` asserts the exception type) | not exercised end-to-end |
| **Review sheet** (all verified / partial / warnings) | — | **no** | clean |
| Row sheet, "Is this your salary?" | — | **no** | clean |
| **1.0×** anything in statements | — | **no** | clean |
| Dark | 1.3× only | yes | yes |
| Home hero no-income branch (salary link) | **no** (demo has income) | — | layout not probed; semantics broken (F5 #1) |
| Reached through the app (Home link / Settings) | **no** (`_screens` omits it) | no (pumped directly) | no |

**Verdict:** the gate covers the two happy paths at one text scale. Everything I listed as bold is untested. It all passes today, and nothing would catch a regression in it tomorrow.

---

## 7. Five strongest things

1. **One money rule, enforced by construction.** `lib/app/money_format.dart` documents the rule in four lines: whole rupees ≥ ₹1,000, paise below that only when there are paise, one format per value per screen, lakh/crore grouping. Every view calls `money`/`moneyCompact`/`moneySpoken`, and no view calls the low-level `inr*`. This closes round 2's top blocker, and the doc comment names the defect it prevents.
2. **The overflow was fixed where it started, and a real gate now guards it.** `Pill` shrinks only when the width is bounded, so it never asserts inside a scroller. `ChipStrip` clips and fades over the chips instead of under them. `layout_overflow_test.dart` visits six surfaces at three configs, scrolls to the end, drains every error, and anchors each screen so an empty render cannot pass. Round 2's main process complaint is fixed.
3. **Dead ends turned into routes.** `insight_actions.dart` maps every `Insight.action` to a concrete destination (Activity filtered by category kind or merchant, Cards, recurring), and both screens share the mapping. Card faces open on tap. "To confirm" lands on the review filter. The hero's transfers line opens Activity filtered to transfers. Four round-2 dead ends are closed.
4. **The password sheet is careful, and it is the most sensitive input in the app.** It uses an obscured `visiblePassword` field with no suggestions or autocorrect, a 64-character cap, and a show/hide toggle with a tooltip that changes. The controller is cleared before dispose. A one-line "never saved or sent" promise sits under the field. The bank-specific hints (e-statement email, YONO, OnlineSBI, ESTMT) are folded into an expander. Cancel and Open are full-width 48 dp buttons. The review step that follows shows the balance-reconciliation verdict in words and tone before anything is written.
5. **The salary-cycle card is a good new object.** The status pill reads "In progress · 12 days" or "Before first salary". The headline label changes with the truth ("Left so far" vs "Saved this cycle" vs "Spent more than came in", red only in that last case). A segmented outflow bar with a compact legend and a "Most went to …" line follow. It gives one spoken sentence and holds at 1.0×, 1.3× and 2.0×.

---

## 8. Every blocker to 9.5

**Correctness of the picture (highest severity)**
1. **Mojibake in visible strings**: `card_face.dart:476` (`Ã¢â‚¬â€` on every card with no limit), `insights_screen.dart:554` (`â€¦` on fraud previews), `insights_screen.dart:161,181` (`â€”`), plus comments in `insight_actions.dart` and `transactions_screen.dart:52`. Add a test that walks every screen and fails on `RegExp(r'[ÃÂâ]€|Ã[\x80-\xBF]')` in any `Text`, and a pre-commit byte check.
2. **Hero links missing from the semantics tree** (`home_screen.dart:322-325` vs `:495-530`). The new statements door and the transfers door are unreachable with TalkBack.
3. **Insight dismissal is permanent with no undo** (`home_screen.dart:1147`, `insights_screen.dart:261`).
4. **Statement rows and balances round to the rupee** (`salary_cycle_screen.dart:220,284,302`). Stored single amounts should print exactly. Keep rounding for derived figures.
5. Countdown phrase in five places (`card_face.dart:276`, `insight_breakdowns.dart:26`, `txn_common.dart:161,186`, `insights_engine.dart:169`).

**F3**
6. Add Salary & statements to `_screens` in `layout_overflow_test.dart`, reached via Settings and via the Home link. Add 1.0× and 1.0×-dark configs. Add the password sheet (with error), the review sheet (partial verification + warnings), no-salary, long names and the row sheet to `statements_screen.test`.
7. 73 px overflow at 2.0× (`salary_cycle_screen.dart:257-260`). Add a 2.0× smoke pass.
8. Bottom insets: All messages (`sms_inbox_screen.dart:277-279`), Statements and the cycle `ListView`s (fixed 40 dp tail).
9. No goldens and no RTL pass.

**F1**
10. Pace chart scale (`charts.dart` `DailyBars`/pace painter). Cap at p95 or add a cumulative line.
11. Hero prose: up to 7 lines of footnote and links under the numbers (`home_screen.dart:470-530`). Collapse to one "Money in ₹… · Transfers ₹… ›" line and move explanations to a sheet.
12. Type-scale escapes (`fontSize: 26/28/30/15.5/12.5`, `dense ? 12 : 12`). Make them `T` roles.
13. Cycle category bars: accent-only Material progress bars instead of `ShareBar` + `categoryColor`.
14. Home status-bar collision (`home_screen.dart:69-72`). Needs a device re-check.
15. Card tap opens the edit sheet, not a card detail (`cards_screen.dart:202-205`).

**F2**
16. Import progress: 3 dp bar, no text, no cancel (`statements_screen.dart:179-185`).
17. The wrong-password sheet closes and reopens. Validate in place with a busy state on "Open".
18. Marking salary gives no confirmation or undo and can land on "This cycle changed" (`salary_cycle_screen.dart:36-45,315-341`).
19. Statements loads with a spinner, not a skeleton (`statements_screen.dart:143-144`).
20. Uncaught import exceptions fail silently (`statements_screen.dart:59-118`).
21. No tab transition and no tab haptic (`app.dart:174-191`). Banner dismiss has no undo.

**F4**
22. `_Line`, `line()`, `_CategoryLine`, `_Legend` and `_RowTile` duplicate kit rows (statements + cycle screens).
23. `home_screen.dart` is 1,285 lines.
24. `dart format` would change 60 of 75 files.
25. The import flow is a `while`/`try` loop in a `State`. Move it into `StatementsController` as a state machine and test it.
26. `_totals` folds twice per day group.

**F5**
27. Pager dots are 28×28 (`cards_screen.dart:238-241`).
28. Insight action and dismiss are 44 dp tall (`insight_tile.dart:229,277`).
29. The cycle card is read twice (no `excludeSemantics`). Cycle category bars announce as unnamed progress bars.
30. `_RowTile` has no semantic hint for "mark as salary". `_HeroLink` has no pressed state.

**F6**
31. Tab-root `watch`es under `IndexedStack`.
32. Activity, and now the cycle transaction list, are not virtualised. The cycle list re-sorts and does `List.contains` per row in build.
33. Per-keystroke search rebuild with no debounce, and one `AnimationController` per `MoneyText` row.
34. `DateTime.now()` in build ×5.
35. `DailyBars` uses `setState` per frame, and `shouldRepaint` compares by identity.
36. A `LayoutBuilder` per `Pill`.

**Process**
37. The documented screenshots predate the build (25 Oct), and no screenshot of the new feature exists. `tool/device_shots.ps1` does not visit Salary & statements. Extend it before round 4.
38. CLAUDE.md test counts are stale ("238 pass / 2 known failures" and "240/240"; actual 316/316).

---

## 9. Three changes with the best score-per-hour

**A. Encoding sweep + a "no mojibake, all reachable" test: ~45 min, ≈ 7.9 → 8.2.**
Fix the four strings (`card_face.dart:476` → `'—'`, `insights_screen.dart:161,181,554`) and the two comments with the Edit tool (not PowerShell). Add a widget test that pumps every surface used by `layout_overflow_test` and fails if any `Text`/semantics label matches the mojibake pattern. In the same file, assert that `find.bySemanticsLabel(RegExp('transfers'))` exists on Home, then fix the hero by putting the two `_HeroLink`s *outside* the `excludeSemantics` subtree, or give them their own `Semantics(container: true)` siblings. That fixes F1 #1, F5 #1 and F5 #2 in one pass. F1 8.2 → 8.6, F5 7.6 → 8.1.

**B. Finish the statements UX loop: ~2 h, ≈ 8.2 → 8.5.**
Move the import flow into `StatementsController` as explicit states. Keep the password sheet open with a busy "Open" and an inline error. Show a "Reading page 3 of 12…" status card instead of the 3 dp bar. Add a snackbar with undo after "My salary" / "Not salary", and on boundary change navigate to the new cycle containing that row instead of showing "This cycle changed". Print statement rows and balances exactly (`inr` for stored single amounts). Make insight dismissal undoable with the same snackbar. Use `ShareBar` + `categoryColor` for cycle categories, put `Flexible` on the row amount (fixes 2.0×), and replace `_Line`/`line()`/`_RowTile` with kit rows. F2 7.9 → 8.5, F4 7.5 → 7.9, F1 +0.2.

**C. Make the gate see the new feature, then do the perf debt you already know about: ~2.5 h, ≈ 8.5 → 8.8.**
Add Salary & statements (via Settings and via the Home link, with a no-income repository) to `_screens`. Add 1.0×-dark and a 2.0× smoke config. Port my `.review_tmp/r3_probe_test.dart` states (password sheet with error, review sheet partial + warnings, no-salary, long names, row sheet) into `test/statement/`. Then turn Activity and the cycle list into `SliverList.builder`, pass `now` from `AppState` instead of `DateTime.now()` in build, debounce search (copy `sms_inbox_screen.dart`), and swap the tab roots to `context.select`. F3 8.6 → 9.2, F6 7.1 → 8.0.

**Cheapest fourth, if there is half an hour:** `dart format lib test` in its own commit, 48 dp pager dots and insight buttons, and `excludeSemantics: true` on the cycle card.

---

## 10. What would make this a 9.5

The structure is now in place: one money rule, one insight tile, one chip, a real layout gate, and a careful password sheet. What is missing is mostly finish:

- **No byte of the UI is garbage.** Four strings are, today.
- **Every visible door is a semantic door.** Two hero links are not, today.
- **Every user action is reversible and acknowledged:** insight dismiss, banner dismiss, mark salary.
- **The newest feature is inside the gate:** 1.0×, dark, sheets, error states, long names, and reached the way a user reaches it.
- **The four performance items carried over from round 1** (tab-root watches, eager lists, `now()` in build, per-keystroke rebuilds).

None of these is a redesign, and A + B + C together are about five hours of work.

# Round 3 — ordinary end user

**Who I am:** the same 28-year-old salaried person (Bengaluru/Hyderabad), UPI for everything, two
credit cards, an SBI salary account, not technical, no patience for anything that wants a bank
login. The phone was disconnected, so there are **no fresh device captures**. I did not use
`docs/shots/*` as evidence: they are from round 2 and predate the statements feature. Instead I
read the copy in `onboarding_screen.dart`, `home_screen.dart`, `transactions_screen.dart`,
`insights_screen.dart`, `settings_screen.dart`, `statements_screen.dart`,
`salary_cycle_screen.dart`, `widgets/salary_cycle_card.dart`, `widgets/card_face.dart`,
`engine/salary_cycles.dart`, and `TransactionNotificationHelper.kt`. I also rendered the
statements screen, a cycle detail, the password sheet (with the wrong-password error and the hints
expanded) and the import review sheet. For that I used a throwaway widget test
(`.review_tmp/enduser_r3_test.dart`, gitignored) on the layout-B SBI fixture, and I quote its
visible text below.

**Score: 7.1 / 10** (round 1: 5.3, round 2: 6.8). Salary to salary is the first feature in this
app that answers the question I installed it for: "did I save anything this month?" The password
sheet is the most trustworthy screen in the app. Most of my round-2 complaints were fixed
properly. What keeps this from 7.5+ is new, and it is avoidable:

- **Garbled characters reached three screens.** The card face shows `Ã¢â‚¬â€` where the
  percentage should be.
- **The statement's salary never reaches Home.** Home keeps saying "No salary in your SMS"
  after I've imported one.
- **"Spent" now means two different things** depending on the screen.

> **Automatic-fail flag (rubric §4: "any screen where I cannot tell what a number means").**
> `lib/views/widgets/card_face.dart:476` prints `'Ã¢â‚¬â€'` as the gauge value of every card with
> no limit set. That is 3 of the 4 cards on the owner's phone ("1 of 4 limits set"). Activity's
> caption also prints `Â·` between figures (`transactions_screen.dart:499, 505`), and Insights
> prints `â€”` / `Â·` (`insights_screen.dart:161, 181, 299, 573`). All of them came from commit
> `bc9e353` ("finance app"): an encoding round-trip of exactly the kind CLAUDE.md warns about.
> Round 2's `c87e42b` had a clean `'—'`. Fixing it takes minutes, but as shipped it is a visible
> defect on the Cards tab.

| # | Criterion | R2 → R3 | Honest reason |
|---|---|---|---|
| U1 | First-run clarity (20%) | 7.5 → **7.5/10** | Onboarding is unchanged and still good: "Your money, without the paperwork.", "reads the bank and UPI alerts already on your phone", and three chips (On-device / No sign-up / No upload). The same 2.5 is still off. The small print says "Android asks for the SMS permission once". Then `PermissionHandlerGate.request` (`app_state.dart:291`) fires `Permission.notification.request()` straight after SMS, with no sentence anywhere saying what I'll be notified about. Statements are not mentioned at first run, which is right: it's an optional extra and should stay out of onboarding. |
| U2 | Daily glance (25%) | 7 → **7.5/10** | Real fixes. The duplicate per-day number is gone (only "Spend / day" remains). The pill now reads "On pace for ₹X", which agrees with Insights. "₹1.2L transfers not counted" is now an underlined, chevroned link to the transfers list. "12 to confirm › Review" opens the inbox on **Unreviewed**. Off 2.5: the hero is still the longest card on the screen. It has the number, "25 of 31 days", the provenance line, three stats, "Out this month includes…", the transfers link, a "Money in: … · Salary: none found" line and now a two-line "No salary in your SMS. Import an SBI statement…" link. That's eight lines of small print before "Where it went". And it still can't answer "am I okay this month?" on Home, even when the statements screen can. |
| U3 | Trust (20%) | 6.5 → **6.5/10** | Up: Activity's stat is now "Out this month" from the same `summary.moneyOut` as Home, so round 2's ₹33k-vs-₹20,313 clash is gone. Measured accuracy is far better (spend recall 98.7 % on held-out messages, 0 non-money rows counted, 1 phishing false alarm in 3,274). The statement import checks every row against SBI's printed running balance and says so: "All 15 balances check out — Every row was checked against the running balance the bank printed." Down, by the same amount: (1) the garbled `Ã¢â‚¬â€` on card faces and `Â·` in Activity's caption; (2) the statement found "Salary ₹1,12,450 from ACME SOFTWARE PV T", but Home, Activity ("Income ₹0") and the hero ("Salary: none found") never hear about it; (3) "Spent" on Home includes my credit-card swipes, while "Spent" in a salary cycle excludes them ("the purchases themselves are on the Cards tab"); (4) the cycle's "In and out" list doesn't add up as written (below); (5) Settings › "Clear all data" doesn't delete imported statements; (6) Insights still says "N signals from **268** entries" (all time) under a month heading; (7) the forecast still prints paise ("At ₹812.52 a day you will finish around ₹25,188.12"). |
| U4 | Effort (15%) | 6.5 → **7/10** | Round-2 dead ends are mostly fixed. Review goes to the queue. Insight tiles now have actions ("See entries", category filter, Cards) through one `insightActionHandler` and can be dismissed. The transfers line opens the transfers. Statement import from Home is short: tap the hero link, "Choose statement PDF", pick the file in the system picker, enter the password, "Check before importing", "Import". Marking salary is one tap on a credit, then "My salary" / "Not salary" / "Let the app decide again". Off 3: in a cycle, **tapping a debit is a dead end** (a sheet with no action), even though `StatementsController.setCategory` exists and nothing calls it. With two SBI accounts I can only ever see the first (`select()` is never called from the UI). On a payment row in Activity, changing a category still fixes only that row. "Every payment from X" lives only in the SMS-inbox flow. |
| U5 | Tone & language (10%) | 7.5 → **7/10** | The password copy is the best writing in the app: "Used once to open the file on this phone. Never saved or sent anywhere." The hints ("SBI e-statement email — Last 5 digits of your registered mobile + date of birth as DDMMYY. Example: 98765150890") answer the question every SBI customer has. "Card bills are what you paid your card company this cycle; the purchases themselves are on the Cards tab." is exactly the right sentence. Down for what the statement feature puts on screen. Raw bank narrations appear as row titles: "DEBIT-ACHDr NACH00000000012345 ICCL MUT UAL FUND SIP--", "TO TRANSFER-INB IMPS/P2A/624812345603/XXXXX XX9876/HDFC/Self--", "by debit card-OTHPG 625512 345605AMAZON PAY INDIA PRI bengaluru", "CREDIT INTEREST--". PDF line-wrap scars appear in names: "ACME SOFTWARE PV T", "BIGBASKE T", "CRED CLU B", "UBER IND IA", "AMAZON S ELLER", including the salary headline itself. Grammar: "In progress · 1 days". Leftovers: "READ_SMS is used only to read bank alerts", "Parsed with 82% confidence", "How parsing works — Sender trust, amount scoring, duplicate merge", two "Coming soon" CSV rows. "All balances check out" is fine inside the review sheet, which explains it. On the account header it is unexplained, and "balance not checked" on a row reads like a warning about *my* balance. Plus the mojibake. |
| U6 | Keep it a month (10%) | 5.5 → **6.5/10** | Salary to salary is the reason I'd keep this. "1 Sep – 30 Sep · Saved this cycle ₹47,102 · Salary ₹1,12,450", with a coloured bar and "Spent ₹22,446 · Card bills ₹38,214 · Cash ₹5,000 · Invested ₹5,000", is what I'd show a friend. But it's a monthly chore (download a PDF, find a password) living in a side room. Home, the screen I see daily, keeps telling me it found no salary. My friend would see "Ã¢â‚¬â€" on my card within ten seconds. |
| | **Total** | **7.1/10** | Weighted 20/25/20/15/10/10 = 1.50 + 1.875 + 1.30 + 1.05 + 0.70 + 0.65 = 7.08. Subject to the automatic-fail flag above until the card-face glyph is fixed. |

---

## The questions I was asked to judge

**Would I trust the password field?** Yes, more than anything else in the app. The sheet's
title is "This statement is locked", with the file name under it, so I know which file is
asking. Directly under the field: "Used once to open the file on this phone. Never saved or sent
anywhere." Under every imported statement: "Read on this phone only. The file and its password
never leave the device, and the password is not saved." The code backs it up: the controller
passes the password to the PDF engine once, the field is cleared on dispose,
`discardPickedFiles()` runs in a `finally`, and the "Remove imported statements" dialog says
"Your SMS and the PDF itself are not touched." The "How do I find my password?" panel is
genuinely useful.

Three gaps:
- On a wrong password the error says "Check the hints below", but the hints stay collapsed. Expand them when the error is set.
- Nothing says *why* the app needs the PDF at all once I'm at the password step. The empty state did say "most SBI debits never send an alert", but I've scrolled past it by then.
- "Clear all data" in Settings promises to remove "parsed alerts, card settings and demo data". It silently leaves my full bank statement and salary in the database: `clearAll()` deletes from 7 tables, not `statements` or `statement_rows`. For a feature I was trusted with a password for, that is the wrong place to be incomplete.

**Is it clear what "Saved this cycle", "Card bills", "Spent" mean?**
- **"Card bills" — yes**, because the cycle detail says so in plain words.
- **"Saved this cycle" — almost.** The detail lists Salary ₹1,12,450, Interest and other credits ₹312, then Spent ₹22,446, Card bills ₹38,214, Cash ₹5,000, **Invested ₹5,000**, then a rule and **"Saved (incl. invested) ₹47,102"**. If I do what everyone does and subtract down the column, I get ₹42,102, which is ₹5,000 short. The label explains it, but the layout invites the wrong sum. Put Invested *below* the line as "of which invested ₹5,000", or don't list it among the outflows. On the summary card it's just "Saved this cycle". The legend there lists Invested among the outflows too, and gives the grey "saved" part of the bar no label.
- **"Spent" — no.** On Home, "Spent this month" includes the ₹1,499 I swiped on my HDFC card. In a cycle, "Spent" means bank-account debits only, and card swipes show up a month later as "Card bills". Same word, two definitions, no bridge. Also "Most went to Sent to people, Groceries, Bills & utilities" sits under a bar whose biggest segment is Card bills ₹38,214. The sentence and the picture disagree about where most of it went.

**Is the flow from Home to importing obvious?** Yes, when you have no SMS salary, which is every
SBI customer. The underlined hero line "No salary in your SMS. Import an SBI statement to see each
month salary to salary ›" opens a clear empty state ("See every month, salary to salary", "Where
to get it: YONO › Accounts › Statement › Download PDF …") with one button. Settings › Data ›
"Salary & statements" is the second door. **But the door never closes.** After a successful
import, Home still says "No salary in your SMS. Import an SBI statement…" and "Salary: none
found", because `HomeData` never reads the statement store. Home should become "Salary ₹1,12,450
on 1 Oct (from your SBI statement) · see this cycle ›".

**Dead ends?** Fixed since round 2: the review banner, insight tiles and the transfers line all
lead somewhere. New ones:
- Tapping a debit in a cycle opens a sheet with nothing to do.
- No way to recategorise a statement row ("Sent to people ₹18,000" is my rent, and I can't say so).
- No account switcher if I import two accounts.
- The newest cycle card at the top of the list after import is "1 Oct – 1 Oct · In progress · 1 days · Left so far ₹1,12,450". The first thing I see after all that effort is a cycle that's one day old and has all of my salary "left". The latest *complete* cycle should come first, or the running one should be framed as "Day 1 of this cycle".

**Jargon?** "transfers not counted" is now a link to a list, so it explains itself. That's fine.
"balances check out" is fine in the review sheet, which explains it, and unexplained on the
account header. "balance not checked" on a row is ambiguous. The worst jargon is the bank's own:
SBI narrations shown verbatim as titles ("DEBIT-ACHDr NACH…ICCL MUT UAL FUND SIP--"). The app
already knows these are "SIP" and "Self transfer to HDFC", because the row subtitles say
"Investment" and "Between your accounts", so use that as the title.

**Do the numbers agree across screens?**
- Home and Activity "Out this month": **yes, now**.
- Pace pill and Insights: **yes, now**.
- Statement salary and Home income: **no** (₹1,12,450 vs "none found" / "Income ₹0").
- "Spent" on Home vs "Spent" in a cycle: **different definitions under one word**.
- Insights "signals from 268 entries" vs Activity "36 entries": **still no**.
- Cards gauge: **unreadable** (`Ã¢â‚¬â€`).
- Review sheet "Money in ₹2,27,561 / Money out ₹97,159" vs the cycle's "In and out": these are statement totals including self-transfers, a refund and a friend's ₹850. They don't need to match, but nothing says why they don't.

---

## The five things I liked

1. **Salary to salary, with a reason.** "Salary ₹1,12,450 from ACME SOFTWARE PV T. A similar
   credit from ACME SOFTWARE PV T arrived in 2 different months. Not right? Open a cycle and tap
   the credit." It doesn't just claim it found my salary; it says why and how to correct it. The
   override has three honest states, including "Let the app decide again". This is the "came in /
   went out / left" answer I asked for in rounds 1 and 2, delivered for the first time.
2. **The password sheet.** It is a model of how to ask for something sensitive. It says what it
   is for, says it isn't kept, tells me where to find it for each SBI channel with examples, has
   a show/hide toggle, sets `enableSuggestions: false` and `autocorrect: false`, and offers a
   Cancel that really cancels.
3. **"Check before importing."** A review sheet before anything is written, with "All 15 balances
   check out — Every row was checked against the running balance the bank printed", plus
   opening/closing balance. Re-importing says "This statement was already imported", and overlaps
   say "N new transactions added (M were already there)". That's how you earn trust with a bank
   file.
4. **Round 2's dead ends are wired.** "Review" opens Unreviewed. Insight tiles have real actions
   and a dismiss. "transfers not counted" opens the transfers. The per-day duplicate is gone.
   "On pace for" agrees with Insights. Home and Activity agree on "Out this month". Five of my
   ten round-2 complaints are closed in code I could read.
5. **The SMS reading got trustworthy where it matters.** 0 non-money rows counted, 0 card bills
   counted on both legs, spend recall from 81.5 % to 98.7 % on 3,274 unseen messages, and phishing
   false alarms from 172 to 1. I can't see these as a user, but I can feel them: the wrong number
   is now much rarer than the confusing label.

---

## Round 2's ten delete-reasons, checked one by one

| R2 complaint | Verdict now |
|---|---|
| 1. Two "out this month" totals (Home ₹33k vs Activity ₹20,313) | **Fixed.** Activity's stat is "Out this month" = `summary.moneyOut`, the same as Home, with "Out this month includes ₹X card bills · ₹Y cash" under it. (The `·` in that line currently renders as `Â·`, see blocker 1.) |
| 2. Can't find my salary; transfers line is dead text | **Half fixed.** The transfers line is a link. The salary is found, but only inside Salary & statements, and Home never learns it. |
| 3. Insights are posters | **Fixed.** `insightActionHandler` routes every action, and tiles dismiss. |
| 4. "12 to confirm" lands on all 2,000 messages | **Fixed.** `initialFilter: InboxFilter.unreviewed`. |
| 5. Notifications unchanged | **Not fixed.** Same silent prompt; `formatAmount` still prints "₹105590"; actions are still Food / Travel / Shopping; no Settings switch. |
| 6. Three counts for one month | **Not fixed.** "${insights} signals from ${data.transactions.length} entries" is still all time. |
| 7. "3% vs last month" vs "on track to spend more" | **Fixed.** The pill is now "On pace for ₹X", the same projection Insights uses. |
| 8. Same per-day number twice | **Fixed.** Only "Spend / day" remains. |
| 9. Two "due" numbers | **Improved.** The banner quotes `data.stillDue`, the same sum as the hero's "Still due". I couldn't re-check the Cards tab's "Total due" without a device. |
| 10. Developer words | **Not fixed, and new ones added.** READ_SMS, "Parsed with 82% confidence", "Coming soon" ×2, plus raw SBI narrations and the mojibake. |

---

## Everything that blocks a 9.5

1. **Mojibake on three screens (automatic-fail risk).** Cards: `'Ã¢â‚¬â€'` as the gauge value
   for every card without a limit (`card_face.dart:476`). Activity: `Â·` in "Out this month
   includes … Â· …" and "Money in: … Â· Salary: none found" (`transactions_screen.dart:499,
   505`). Insights: "No insights yet â€” …", "Nothing recurring detected yet â€” …", the fraud
   date line "26 Oct 2026 Â· 21:14", and a word list joined with `Â·`
   (`insights_screen.dart:161, 181, 299, 573`). The tests didn't catch it, so add a test that
   fails on `Ã`/`Â`/`â€` in `lib/`.
2. **The salary lives in a side room.** The statements screen knows "Salary ₹1,12,450 from
   ACME"; Home says "Salary: none found" and invites me to import again, and Activity shows
   "Income ₹0". Until Home reads the imported salary (or the latest cycle) and replaces the
   import link with "This cycle: ₹X saved so far", the app gives two answers to its own
   headline question.
3. **"Spent" has two definitions.** Home's "Spent" includes card swipes. The cycle's "Spent" excludes them and counts the card *bill* instead. Rename the cycle line ("Spent from your account") or add one line on the cycle card ("Card purchases this cycle: ₹X, paid next cycle").
4. **The cycle's "In and out" doesn't subtract to its total.** It lists Invested ₹5,000 as an outflow, then shows "Saved (incl. invested) ₹47,102", ₹5,000 more than the column gives. Also, "Most went to Sent to people…" contradicts a bar whose biggest segment is Card bills.
5. **"Clear all data" leaves my bank statement behind.** `clearAll()` doesn't touch `statements` / `statement_rows`, and the dialog doesn't say so. Either clear them or say "Imported statements are kept; remove them from Salary & statements."
6. **Statement rows read like a bank printout.** Raw narrations as titles ("DEBIT-ACHDr NACH…", "TO TRANSFER-INB IMPS/P2A/…/Self--", "by debit card-OTHPG … AMAZON PAY INDIA PRI bengaluru") and wrap-split names ("ACME SOFTWARE PV T", "BIGBASKE T", "CRED CLU B", "AMAZON S ELLER") right in the salary headline.
7. **Statement dead ends.** Debit rows have no action. `setCategory` exists and nothing calls it. There's no account switcher. The first cycle shown is "1 Oct – 1 Oct · In progress · 1 days · Left so far ₹1,12,450".
8. **Notifications are still round 1's.** A silent permission prompt, one buzz per payment, "₹105590", three fixed categories, and no off switch in Settings.
9. **Period labels and precision.** "signals from 268 entries" (all time) under a month heading, and the forecast still in paise ("₹812.52 … ₹25,188.12 … ₹19,726.85").
10. **Payment-row corrections don't learn.** "Every payment from X" is still only in the SMS-inbox sheet. Fixing a category from Home/Activity fixes one row.
11. **Developer words.** "READ_SMS is used only to read bank alerts", "Parsed with 82% confidence" with a progress bar, "Sender trust, amount scoring, duplicate merge", "Coming soon" ×2, and "balance not checked" on rows.
12. **The hero is a wall of small print.** Eight lines under the number. Fold "Money in" and the salary link into one line once the salary is known (blocker 2), and the hero gets shorter *and* answers more.

---

## The three changes with the highest score-per-hour

1. **Fix the encoding and guard it (≈30 min, +0.3 and removes the auto-fail).** Restore `—` and `·`
   in `card_face.dart`, `transactions_screen.dart` and `insights_screen.dart` (and the comments in
   `insight_actions.dart`) with the Edit tool. Add a test that greps `lib/**/*.dart` for
   `Ã|Â|â€|â‚` and fails.
2. **Bring the imported salary to Home (≈half a day, +0.5).** When an imported statement has a
   salary, have `HomeData` expose the latest cycle. The hero's link then becomes "This cycle (from
   1 Oct): salary ₹1,12,450 · saved so far ₹X ›" instead of "No salary in your SMS. Import…".
   Activity's "Income" can say "Salary from statement ₹1,12,450". In the same pass, add "Imported
   statements" to "Clear all data" (both the code and the dialog copy).
3. **Make a cycle read like my life, not SBI's printout (≈half a day, +0.4).**
   - Title rows by what the app already knows ("SIP · ICCL mutual fund", "To your HDFC account", "Card bill via CRED"), and keep the narration in the detail sheet.
   - Join wrap-split words in names before display.
   - Move Invested below the line as "of which invested".
   - Rename the cycle's "Spent" to "Spent from account".
   - Wire `setCategory` to the debit sheet.
   - Show the latest complete cycle first.
   - Fix "1 days".

**Would I recommend it?** Closer than ever. With salary to salary I'd tell a friend "import your
SBI statement once a month and it tells you what you saved". I'd say that only after the card
stops showing `Ã¢â‚¬â€` and Home stops telling me it never found my salary.

# Round 2 — ordinary end user

**Who I am:** the same 28-year-old salaried Bengaluru user from round 1. UPI for everything,
HDFC + ICICI cards, not technical, no patience for an app that wants my bank login. I read
the five device captures taken tonight at 23:36 on the real phone (`docs/shots/device-home.png`,
`device-activity.png`, `device-cards.png`, `device-insights.png`, `device-settings.png`) and the
copy in `onboarding_screen.dart`, `home_screen.dart`, `transactions_screen.dart`,
`insights_screen.dart`, `settings_screen.dart`, `sms_inbox_screen.dart`,
`inbox_detail_sheet.dart`, `txn_detail_sheet.dart`, `monthly_summary.dart`,
`insights_engine.dart`, `card_metrics.dart` and `TransactionNotificationHelper.kt`. The shots
were fresh, so I did not regenerate them.

**Score: 6.8 / 10** (round 1: 5.3). The hero no longer lies to me in its own card, the bills
are real, the cards are cards, and a correction now sticks — that is worth a lot. What stops it
being a 7.5+ is that the same class of bug moved one tab sideways: Home and Activity now print
two different "out this month" totals, and the app still cannot tell me whether I came out ahead,
because it could not find my salary.

| # | Criterion | R1 → R2 | Honest reason |
|---|---|---|---|
| U1 | First-run clarity (20%) | 7 → **7.5/10** | Cleaner than round 1: "Your money, without the paperwork", one line of what it does, three chips (On-device / No sign-up / No upload), one Allow button, one demo button, and the old "Card utilisation, done right" jargon bullet is gone. Off 2.5 for the same thing that annoyed me last time: the small print says "Android asks for the SMS permission **once**", and the moment I tap Allow a **notifications** prompt appears too (`app_state.dart` `PermissionHandlerGate.request` asks for `Permission.notification` right after SMS). Nothing on the screen or in Settings ever says what it will notify me about. That is a permission with no reason, which is the exact thing I flagged. |
| U2 | Daily glance (25%) | 6.5 → **7/10** | Everything I need is above the fold at 412 dp: spend, three stats, the bill notice, the confirm notice, even the start of the pace chart. And the answer is no longer a lie. But (a) the app still doesn't answer "am I okay?" — "No income messages found this month" on a phone where 2000 messages were read and ₹1.2L moved as transfers; (b) the per-day number is printed twice in one card — "₹812.52 a day · 25 of 31 days" four lines above "Spend / day ₹813" (both from `summary.dailyAverage`); (c) the hero is now long: five small-print lines inside it, and "Where it went" has been pushed off the screen. It's honest, it's not yet a glance. |
| U3 | Trust (20%) | 3 → **6.5/10** | Huge single-screen recovery: "Out this month includes ₹13k card bills · ₹1.2L transfers not counted" is exactly the receipt I asked for, "Left" is correctly withheld instead of faked, the Cards ring says 6% with "1 of 4 limits set" and an honest "not set" instead of 0%, and there is no more "₹0 used, 106% projected, pay ₹45,000". Then I change tab and: Home says "**Out this month ₹33k**", Activity says "Spent ₹20,313 / +₹3,939.66 in / **−₹20,313 out**"; Home says "**3% vs last month**", Insights says "**On track to spend more than last month** ... ₹25,188.12 against ₹19,726.85"; Activity says "**36 entries**", Insights says "**4 signals from 268 entries**" under the same "October 2026" heading. Trust is built out of numbers agreeing, and these four pairs don't. |
| U4 | Effort (15%) | 5 → **6.5/10** | The "every payment from X" flow is genuinely good and it is the round-1 ask delivered: "Every payment from Swiggy — also updates every earlier payment from this merchant and remembers the choice for new ones", a snackbar that says "39 earlier payments ... updated", and Settings › Learned categories listing it as "Swiggy · Food & dining · 39 uses" with a delete that explains itself ("New payments from Swiggy will go back to the automatic category. Payments already categorised stay as they are."). Costing it 3.5: the 12 that need me still aren't reachable — "Review" on Home calls `SmsInboxScreen.open(context)`, which lands on "All" with 2000 messages and the "Unreviewed" chip unselected; changing a category on a payment row (Home recent, Activity) only fixes that row, with no "every payment from X" there; and the insight tiles are still completely inert. |
| U5 | Tone & language (10%) | 6 → **7.5/10** | Much better. "Out this month includes…", "transfers not counted", "Paying in full avoids interest", "No income messages found this month, so there is no 'left over' figure" — that last sentence is the most adult line in the app. Off 2.5 for the leftovers: "READ_SMS is used only to read bank alerts" (a permission name, not a sentence), "Parsed with 82% confidence" on a payment I'm looking at, "Utilisation is only accurate when we know the limit", and "Bill due in 2 days" is good but "Bill due ₹11k" vs "Total due ₹16k" is the app talking to itself again. |
| U6 | Keep it a month (10%) | 3 → **5.5/10** | I'd now open it in week one for the bill banner alone, and correcting a merchant finally feels worth doing. But when I show a friend, the first thing they'll do is check the total against their bank app, and I still can't tell them why "out" is ₹33k here and ₹20,313 there. Week three, the bank SMS still wins because the bank knows my salary arrived. |
| | **Total** | **6.8/10** | Weighted 20/25/20/15/10/10 = 6.8. |

---

## The five things I liked

1. **The receipt under the total.** "Out this month includes ₹13k card bills · ₹1.2L transfers
   not counted" is the first time the app has told me what is *inside* the number and what is
   deliberately not. Round 1's "is the card bill I just paid in there?" is answered in one line.
   Both halves are built from the model (`monthly_summary.dart`), not hand-written, so they
   can't drift.
2. **It stopped inventing a "Left".** "No income messages found this month, so there is no
   'left over' figure." I hate the reason, but I respect the sentence. Removing a wrong answer
   is worth more than a nicer wrong answer, and the same is true of the Cards ring reading
   "— not set" instead of "0% used".
3. **Bills became a real thing.** "American Express bill due in 2 days · ₹10,568 total due · Paying
   in full avoids interest · See card" on Home, "Due in 2 days" on the card art, and "27 Oct ·
   in 2 days" in Bills. Read-only from SMS, and still the most useful object in the app. The
   "0 days" bug is dead too (`billDuePhrase` handles today/tomorrow).
4. **Learning that actually learns, with an undo.** "Every payment from Swiggy" plus 39 earlier
   payments updated, plus a Settings list with use counts and a delete that says exactly what
   will and won't change. This is the round-1 complaint I most wanted fixed and it is fixed
   properly, on the path that exists.
5. **The cards look like cards and the numbers on them agree.** Dark Amex art, real last-4,
   due chip on the face, "6% used / Excellent / 1 of 4 limits set / ₹71,607.54 used ·
   ₹10,64,417.52 available". No more ring-and-tile contradiction, and the `1 << 62` clamp is
   gone (`0x1FFFFFFFFFFFFF` in `card_metrics.dart`).

---

## Round 1's ten delete-reasons, checked one by one

| R1 complaint | Verdict now |
|---|---|
| 1. "Left" ignores the ₹94k that also left | **Fixed.** When income exists, `left = income − (spend + cash + card-bill payments)`; when it doesn't, there is no Left at all. The number is gone; the *cause* (no income found) is now visible instead. |
| 2. "Excludes ₹94k" bigger than the total | **Half fixed.** The line is now "includes / not counted" and is accurate. But ₹1.2L is still bigger than the ₹20,313 above it, still not tappable, and Activity contradicts the word "out". |
| 3. Ring 0% and tile 50% at once | **Fixed.** `0x1FFFFFFFFFFFFF` clamp; unknown limits show "not set" and drop out of the aggregate's denominator ("across 1 card with a limit"). |
| 4. Insights writing nonsense; "Bill due in 0 days" | **Fixed.** No utilisation insight without a limit; the bill insight reads ₹10,568, "Paying the full amount avoids interest"; 0/1 days handled. |
| 5. False fraud alarms (OTPs/marketing) | **Looks fixed, I couldn't test it.** No red banner on tonight's phone. The classifier now has an OTP-shape gate, an email-style-handle guard (`Never share OTP @mycards.hdfc.bank.in`) and demotes ordinary bank links (`sms_classifier.dart`). I have no flagged message to judge, so I'm taking the code's word for it — which is not the same as trusting it. |
| 6. "Other" swallowing spend, never learning | **Half fixed.** Learning works now (see #4 liked). But Home still never says how many rupees of the month it couldn't name — the donut just rolls the tail into an "Other" slice (`charts.dart`), and the only disclosure is the "12 to confirm" count, not a share. |
| 7. A notification for every payment, wrong choices, broken amounts | **Not fixed.** Same `TransactionNotificationHelper`: one notification per expense, actions **Food / Travel / Shopping** only, `formatAmount` with no Indian grouping ("₹105590"), requested silently after SMS, and no switch in Settings. |
| 8. Paise on a forecast | **Not fixed.** "At ₹812.52 a day you will finish around ₹25,188.12, against ₹19,726.85 last month." |
| 9. Jargon and fear ("utilisation", "your score") | **Mostly fixed.** "This can affect your score" and the onboarding jargon bullet are gone; "utilisation" survives only in Cards copy and insight titles. "READ_SMS" and "Parsed with 82% confidence" survive. |
| 10. Dead ends | **Half fixed.** Banners dismiss, rows are tappable, the inbox has a recoverable error banner instead of the old dead "Something went wrong. Try again." But the insight tiles and the 12-item queue are still dead ends (below). |

---

## Everything that would still make me delete it

**1. Two tabs, two "out this month" totals.** Home: "Out this month **₹33k**". Activity:
"Spent ₹20,313 · +₹3,939.66 in · **−₹20,313 out** · 36 entries". One word, one month, ₹13k
apart, and no line anywhere reconciles them. The cause is definitional — `moneyOut = spend +
cash + card bills` in `monthly_summary.dart`, while Activity's `_totals` adds spend + cash and
skips `TxnKind.transfer` — but I don't read Dart, I read two screens. This is the round-1
complaint, reborn between screens. It is the single reason this is still not a 7.5.

**2. It can't find my salary, and the biggest flow on the card is a dead sentence.** "No income
messages found this month" after "2000 messages read" is not believable for a salaried person —
and the app's own Activity tab shows "+₹3,939.66 in" while the hero says there was no income.
The likely home of my salary is the other line: "₹1.2L transfers not counted", which is plain
text with no tap, no list, no "was this your salary?" — so I can neither confirm nor correct it.
Until the app knows money came in, it cannot answer "am I okay?", and that is the only reason
I installed a second app that reads my SMS.

**3. Insights are posters: nothing on them is tappable.** "Shopping is 4.4× your usual — worth a
look" and "On track to spend more than last month". Look where? There is no tap, no dismiss, no
"show me the 4 charges", no "mark this bill paid". `Insight` even carries an `action` field
(`InsightAction.categories/cards/transactions`) that `InsightTile` never reads. Three of the
four things on the Insights page are dead ends, and one of them is a bill.

**4. "12 to confirm" doesn't take me to the 12.** The banner's Review button calls
`SmsInboxScreen.open(context)`, which pushes the inbox on `InboxFilter.all` — 2000 messages —
with the "Unreviewed" chip unselected. I have to know to tap it. Then each of the 12 is a sheet,
a chip and a Save. The app has the machinery to do this in one tap per merchant; the entry point
doesn't use it.

**5. Notifications are unchanged, which is the one thing that would have made me uninstall.**
SMS permission, then a silent notifications prompt; then one buzz per UPI payment with three
wrong categories and "₹105590". No Settings switch, no daily digest, no "only bills and unusual
amounts". It duplicates the bank SMS I already get.

**6. Three counts for one month.** "2000 messages read" (Home), "36 entries" (Activity),
"268 entries" (Insights, under "October 2026"). The last one is `data.transactions.length` —
all time — under a month heading. Once I notice the count is wrong, I assume the money is too.

**7. "3% vs last month" versus "on track to spend more than last month".** The hero compares 25
days with a full previous month (+3%, trending-up arrow); Insights compares the projection with
the same full month (+28%). Both are labelled "last month". One says "about the same", the
other says "you're up", and the honest answer is the second one. A pace-adjusted pill ("on pace
for ₹25.2k, about 28% more") would have been the fix.

**8. The same per-day number twice in one card.** "₹812.52 a day · 25 of 31 days" and "Spend /
day ₹813", four lines apart, two formats. It reads like two different numbers that happen to be
close, which is the worst possible impression for this app.

**9. Two "due" numbers that don't reconcile.** Home "Bill due **₹11k**" (sum of `billDuePaise`
after payments) versus Cards "Total due **₹16k**" (sum of `totalDuePaise` on the latest bills)
versus the Bills row "₹10,568 **total due**". I cannot tell whether I owe 11k, 16k, or 10.5k,
and one of them is on a screen called Cards, which is where I go to pay.

**10. Developer words on the money screen.** "READ_SMS is used only to read bank alerts",
"Parsed with **82% confidence**" (with a progress bar), "Utilisation is only accurate when we
know the limit", and two "Coming soon" CSV rows in Settings. Not fatal, but each one reminds me
this is a build, not a product.

---

## The three changes that would make me keep it

1. **One "went out" number, used by every tab, that opens.** Pick one definition — spend + cash +
   card bills — and make Activity say "₹33k out, ₹13k of it card bills", Cards say the same,
   and the hero keep the receipt. Let "₹1.2L transfers not counted" tap through to those
   entries, and delete the duplicate per-day line (keep "Spend / day ₹813", drop "₹812.52 a
   day"). This is a labelling-and-one-actual-change job, not a rewrite: `moneyOut` already
   exists and Activity already has the rows.
2. **Find my salary, or let me point at it.** Parse the NEFT/IMPS credit that is my employer, or
   let me tap the ₹1.2L line and mark one entry "this is my salary". Then the hero can say "Came
   in ₹X · Went out ₹Y · Left ₹Z / Over ₹Z" — and because "Left" already subtracts card bills,
   it would be the first number in this app I could actually act on. Round 1 asked for the truth
   about Left; this is how it becomes possible.
3. **Make the correction stick where I actually am, and make the queue one tap.** Add "every
   payment from X" to the payment detail sheet (the SMS-batch flow already has it), have Home's
   "12 to confirm" open the inbox with **Unreviewed** preselected, and give every insight tile
   a real action and a dismiss ("See the 4 charges", "Mark bill paid", "Not a duplicate"). The
   models and store methods already exist; today they're wired to nothing.

**Would I recommend it?** Not yet. The one change that would flip it: **give me one "went out"
number and a real "came in" — the same three figures on Home, Activity and Cards** — because
then the ₹40k-a-month question has an answer that survives me checking it against my bank app,
and that's the only reason this earns a place next to the SMS it already duplicates.

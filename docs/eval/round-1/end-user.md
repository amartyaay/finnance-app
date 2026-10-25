# Round 1 — ordinary end user

**Who I am:** 28, salaried in Bengaluru, paid by NEFT, pay for everything by UPI, carry two
credit cards (one HDFC, one ICICI), not technical, no patience for another app that wants
my bank login. I gave this ten minutes on a phone and also poked at the browser demo.

**What I actually looked at:** the four demo tabs (Home, Activity, Cards, Insights) at
412×915, the real-phone captures in `docs/shots/` (`device-home.png` 21:44,
`device-scan.png` 20:52, `device-err.png`), and the exact strings in
`onboarding_screen.dart`, `settings_screen.dart`, `home_screen.dart`,
`cards_screen.dart`, `insights_screen.dart`, `txn_detail_sheet.dart`.

**Score: 5.3 / 10.** It looks like a finished product and reads like a first draft of the
truth. I would not leave it on my phone, and the reason is not polish — it is that the
app states numbers that contradict each other and then expects me to trust the next one.

| # | Criterion | Score | Honest reason |
|---|---|---|---|
| U1 | First-run clarity (20%) | **7/10** | Best part of the app. One screen, no carousel, no sign-up: "Finance SMS reads the bank and UPI alerts already on your phone", "No bank login, no account, no cloud", a button to allow SMS, a button to try demo, and a promise the permission is revocable. In 15 seconds I know what it does and why it wants my messages. Loses 3 points for: the third bullet is "**Card utilisation, done right**" — I don't know that word on screen one; and the moment I tap Allow, Android asks for **notifications** too, which nothing on that screen mentions. I don't know what it will notify me about, so I hesitate. (It notifies me about every single payment — see below.) |
| U2 | Daily glance (25%) | **6.5/10** | The total is right there, big, above the fold, with the month and a vs-last-month pill, then "is anything wrong" as banners, then "where it went". No scrolling on my phone — good. But the answer I actually get is the wrong answer: "Spent ₹32,998 ... **Left ₹4.1k** ... **Per day ₹1.3k**". ₹4.1k left and ₹1.3k a day is three days of money and there are six days in October — the two numbers side by side mean opposite things. And "Left" ignores the ₹94k that also left my account this month, printed in the same card. So I *see* an answer instantly; I just can't use it. |
| U3 | Trust (20%) | **3/10** | This is where it dies, and it dies in at least six separate places — each one an automatic fail under the rubric ("a number I cannot tell the meaning of", "a scary number with no explanation"). Details in the next section. |
| U4 | Effort (15%) | **5/10** | Fixing a category is tap-the-row → bottom sheet → tap-the-chip: two taps, acceptable. But it **does not stick to the merchant**: `assignCategory` writes the one transaction, and `Categorizer` only knows its hardcoded brand list, so the same kirana/chemist comes back as "Other" every month. On a real inbox I saw "**20 payments to confirm**" — that's 40 taps and next month it starts again. Dead ends: the duplicate-charge insight has no "no, that was two coffees" button; insight tiles have no dismiss at all (`AppState.dismissInsight` exists but nothing calls it); the fraud sheet ends in "Got it"; "Bill due in 0 days" cannot become "paid". |
| U5 | Tone & language (10%) | **6/10** | Mostly plain and never guilt-trippy — "Paying the full amount avoids interest" is exactly right, and spending is never painted red. But "**utilisation**" is on the first screen and in every card insight, "statement date" is assumed knowledge, "This can affect your **score**" never says which score, and Settings shows me "**READ_SMS** is used only to read bank alerts" — that's a permission name, not a sentence. "We parsed these but could not name the merchant with confidence" is developer talk. |
| U6 | Keep it a month (10%) | **3/10** | Week one I'd open it, week two I'd open the bank SMS instead, week three I'd uninstall. The one thing that could keep it — catching a scam — is the one thing I ended up not believing (false positives). |
| | **Total** | **5.3/10** | Weighted 20/25/20/15/10/10. |

---

## The five things I liked

1. **The onboarding deal.** One screen, no sign-up, no bank credentials, "Explore with demo
   data" sitting there before I grant anything. I could judge the app in ten seconds without
   handing over my inbox. Very few Indian finance apps let me do that.
2. **Home is one glance.** "SPENT THIS MONTH", the number, "on track for about …", three
   stats, then the alerts, then "Where it went" — all visible without scrolling on a
   412-wide phone. That is the shape I want.
3. **The fraud card is the best thing in the app.** It quotes the sender (`AD-KYCVERIFY`),
   shows me the actual URL, says "Your bank never asks you to confirm details or share an
   OTP through a link", and closes with "It was kept out of your spending totals, and no
   link was opened." That's the one place the app treats me like an adult instead of
   hiding behind a score.
4. **Activity reads like a statement, not a dashboard.** Today / Yesterday / 23 Oct, with a
   per-day total on each header, search, category chips, "₹480 Food & dining · UPI", and
   amounts that are never red. The "Needs review" chip and the "This is a duplicate. It was
   merged into the original alert so your spend counts the payment once." note are exactly
   the right level of confession.
5. **It admits uncertainty in words.** "1 payment to confirm — we parsed these but could not
   name the merchant with confidence." "Nothing recurring detected yet (needs 3 similar
   charges)." "Add the card limit for utilisation." These lines bought the app a lot of
   credit — which is precisely why the places where it *doesn't* admit uncertainty (below)
   feel like a bait and switch.

---

## Everything that would make me delete it

**1. "Left" ignores the ₹94k that also left my account.** On the phone the hero reads
"Came in ₹37k · **Left ₹4.1k** · Per day ₹1.3k" and, two lines below, "Excludes **₹94k** in
card bills and transfers". So this month ₹37k came in, ₹33k was counted as spending, and
₹94k more left in card bills and transfers — and the app tells me I have ₹4.1k left.
`net = income − spend`, nothing else. The Cards tab (demo) separately says "Total due ₹28k
· Next due 25 Oct" and the hero never subtracts that either. "Left" is the one number I
read and close the app on, and by the app's own numbers my account went down about ₹90k
this month.

**2. "Excludes ₹94k in card bills and transfers" — bigger than the number it's under.**
On the phone: "₹32,998 spent … Excludes ₹94k in card bills and transfers". Three times more
money excluded than shown, in 11 px grey type, and I cannot work out whether the card bill
I just paid is inside the ₹33k or not. (It isn't — but I only know that because I read the
code.) The same footnote never mentions cash: the demo's Activity tab says "Spent
₹1,37,269.37 · ₹1,25,000 in · ₹1,42,269.37 out · 69 entries" — a ₹5,000 gap with no label,
which is exactly the ATM withdrawal sitting in the list. Two totals on one screen that
don't match, and nothing explains the difference.

**3. The Cards screen contradicts itself three ways on one card.** Ring: "**0% used**".
Caption: "of ₹8,00,000 limit across 3 cards". HDFC tile: "**50% used**", "**₹0 /
₹1,50,000**", "This cycle **₹0**". This is not a demo-data accident: `card_metrics.dart`
clamps with `1 << 62`, and under dart2js that constant evaluates to **0** (I compiled the
expression and ran it: `cap=0`, `clamped=0`), so in the browser build every card amount
clamps to zero while the percentage comes from the un-clamped value. On the phone the
arithmetic is 64-bit and the amounts are right, but this is the build a curious user or a
reviewer opens first, and it is the screen that tells me the app's maths is broken. *Fix
the clamp (`1 << 62` → `0x7FFFFFFFFFFFFFFF`, or a platform max instead of a shifted
literal).*

**4. Insights writes sentences that are nonsense.** "HDFC Millennia is at 50%
utilisation — **₹0 of ₹1,50,000 used**, 17 days before the statement date. On this pace
you would end the cycle at **106%**. **Paying ₹45,000** would bring it under 30%." Zero
used, 106% projected, pay ₹45,000. Same screen: "Bill due in **0 days**" (should be
"today"). A sentence I can't parse is worse than no insight, because now I don't know
which of the other nine are also wrong.

**5. False fraud alarms.** On the demo inbox 2 of 7 messages are flagged. The repo's own
`docs/research/real-data-findings.md` says the real classifier flagged 141 of 2,000 and
that **6 of 8 sampled flags were OTPs and marketing**, not fraud. If my own bank's OTP
turns up as a red "Possible fraud message", I stop reading the red banners — and the app
has lost the one feature that could have justified keeping it.

**6. "Other" swallowing the spend, then never learning.** On the phone at 20:52:
"**Other ₹90,035.85**" out of "₹1,05,590.85 spent" — 85% of my money in a bucket with no
meaning, and `docs/research/real-data-findings.md` says the same (89 rows, ₹8.44L). It was
better by 21:44 (Other ₹4,000), but nothing in the app tells me how much of my total it
couldn't name, and fixing one doesn't teach the merchant. A "Where it went" screen that is
mostly "Other" is a screen I stop opening.

**7. A notification for every payment, unexplained, with three wrong choices and broken
amounts.** The permission is requested silently right after SMS. Each alert says "Spent
₹576.37" with actions **Food / Travel / Shopping** only — no Groceries, no Transport, no
Bills — and amounts over a lakh print ungrouped ("₹105590") because
`TransactionNotificationHelper.formatAmount` doesn't use the app's Indian grouping. This
duplicates the bank SMS I already get, one notification per UPI payment.

**8. Fake precision on a forecast.** "On track for about **₹40,917.52** by 31 Oct" and
"₹1,30,932.65" — paise on a straight-line extrapolation that also swallows one-off buys (in
the demo, a ₹44,990 Croma purchase is why Shopping shows "▲339%"). A projection to the
rupee is a promise the app can't keep.

**9. Jargon and fear in place of a sentence.** "utilisation" on screen one and in every card
insight; "**This can affect your score**" — which score? The app never says CIBIL, never
says it doesn't show a score, and gives me nothing to do except "clear part of it". That is
fear without information, on the money screen.

**10. Dead ends.** The duplicate-charge insight can't be dismissed as a false alarm. No
insight tile has any action. The fraud dialog ends at "Got it". "20 payments to confirm" is
a queue with no bulk fix. And once, opening the app gave me "**Something went wrong reading
your messages. Try again.**" with a Scan button that kept failing (`device-home.png`,
20:27; the debug build showed a raw SQLite exception, `device-err.png`) — I have no way to
tell whether my permission is wrong or the app is broken, so I'd uninstall rather than
retry.

---

## The three changes that would make me keep it

1. **Make "Left" true, or delete it.** The honest version of the phone's hero is "Came in
   ₹37k · Went out ₹1.27L (₹33k spending + ₹94k card bills and transfers) · **Down ₹90k**",
   with the bills still due on the same card. If that is too blunt, at least
   stop calling `income − part-of-the-outflow` "Left": say "Salary left before bills", and
   never print it in the same type size as the total. One number on Home that the Cards tab
   can never contradict.
2. **One "spent" number with a receipt.** Under the total, a single tappable line — *"Not
   counted: ₹94k card bills · ₹5k cash · other items"* — that opens the actual entries, and
   make Activity's "Spent / out" gap self-explaining. Then fix the `1 << 62` clamp so the
   Cards ring and tile can never print 0% and 50% at once, and drop the paise from
   forecasts ("about ₹40,900").
3. **Make a correction stick.** When I name a merchant's category, save it as a merchant
   rule and apply it to every past and future charge from that shop; give me "12 payments
   from 4 shops — fix in 4 taps" instead of 20 individual ones. Then a line on "Where it
   went": *"₹4,000 (12%) we couldn't name — help us label it."* Without this, the app asks
   me to do the same work every month and I won't.

**Would I recommend it?** No, not yet. The one change that would flip that: **get "Other"
under 10% and make the "Left" number the truth** — because then the ₹40k-a-month question
("am I okay?") gets an answer I can act on, and that's the only reason I'd tell a friend to
install a second app that reads my SMS.

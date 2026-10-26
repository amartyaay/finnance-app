# Budget page and the 10 pm daily summary

Owner request (27 Oct 2026): a budget page where a user sets a monthly budget
and tracks savings and spending, and a notification every day at 10 pm local
time saying how much was spent and how the month's budget looks. "Research how
these should work and make them useful."

## What the research says

Sources are mostly product pages, vendor blogs and app reviews; there is no
controlled study on, say, the best hour for a daily recap. Treat the points as
established patterns, not measured truths.

**One number beats a spreadsheet.** A growing group of apps reduce budgeting to
a single "safe to spend today" figure: what is left, spread across the days
until the period ends, updating as money is spent. Founders report that people
abandon category-heavy budgets within days; the daily number removes the
mental arithmetic. ([Safe To Spend][sts], [IndieHackers: "how much can I safely
spend today"][ih1], [IndieHackers: budgeting apps abandoned after a day][ih2],
[MoneyFlow][mf])

**Pace, not just totals.** A month-to-date total alone does not tell you if you
are fine on the 10th. Apps compare spend to an even pace (or a trailing
average) and label it. ([Safe To Spend][sts]; Spending Pulse's burn-rate card
as described in the same search.)

**Suggested amounts from history.** Monarch suggests budgets from the user's
six-month average; YNAB asks for a target per category and tracks spending
against it; both support carrying the unspent remainder forward (rollover).
([Monarch rollovers][mon], [YNAB vs Monarch, iPhoneLife][ipl],
[Copilot vs Monarch vs YNAB][bc])

**Few categories, not all.** Category budgets are most useful for the few
categories a person wants to control; whole-budget-by-category (zero-based) is
the heavy end of the spectrum. Copilot is described as "more observational
than prescriptive". ([beancount forum][bc])

**Indian SMS apps.** Walnut/Axio and Jupiter categorise SMS and show spend
breakdowns; reviews call Walnut "very good at tracking, budgeting and providing
detailed breakdown". Nothing found on salary-cycle budgets in these apps.
([Jupiter][jup], [Outlook Money][om], [Digit][dig])

**Notifications.** Finance apps have unusually high push opt-in (85 % of bank
customers in one report; up to 96 % on Android in another), evenings and
afternoons are the peak engagement window, and a summary tied to a money moment
performs better than generic nudges. Guidance on frequency varies; a single
useful daily message is within every recommendation, promotional pushes are
not. ([Larky / CU Insight][larky], [CleverTap][ct], [Plotline][pl],
[Pushwoosh][pw])

**Android mechanics.** Exact alarms need `SCHEDULE_EXACT_ALARM` on Android 12+
(restricted for non-alarm apps on 14); WorkManager cannot promise a clock time
(15-minute floor, deferred in Doze). A daily recap does not need the exact
minute. ([gurubase][gb], [flutter_workmanager][wm])

## What we built, and why

### Budget tab (between Activity and Cards)

| Piece | Behaviour | Why |
|---|---|---|
| Monthly budget | One amount for all spending in the calendar month. First run shows the last three months and offers their median, rounded up to ₹1,000. | One number; suggestion from history (Monarch). |
| What counts | Home's "Spent": purchases, card purchases when made. Never card-bill payments, investments, FDs, transfers. | Paying a card bill must not "blow" a budget twice. |
| Hero | "₹X left" (or over), spent of limit, a pace bar with a tick where an even pace would be today, and a status: Under pace / On track (±10 %) / Spending fast / Over budget. | Pace, not totals. |
| Tiles | Safe per day (left ÷ days left, today included), spent today, days left. | The single daily number. |
| Category limits | Optional, added one at a time; the biggest categories this month are offered with a suggestion (3-month average, rounded to ₹500). Bar turns amber when ahead of pace, red when over. | Few categories, not all. |
| Savings | Came in − went out (Home's definitions), projection to month-end at the current pace, optional monthly savings goal. A salary from the 25th counts for the next month. | "Track savings" with numbers that agree with Home. |
| History | The last six months against today's limit. | Shows whether the limit is realistic. |

Not built (deliberately, for now): rollover of unspent budget, salary-cycle
budgets instead of calendar months, budgets per card. Rollover is easy to add
once someone has a month of use; salary-cycle budgets already exist as the
statement's cycle view.

### 10 pm summary

- **Content.** Title: "You spent ₹1,240 today · mostly Food & dining" (or "No
  spending today"). Body with a budget: "₹18,400 left of ₹50,000 (on track).
  ₹1,840 a day for the next 10 days." Over budget: by how much. Without a
  budget: month to date, the pace projection, and a pointer to set one.
  Tapping opens the Budget tab.
- **Same numbers as the app.** The text is composed from `BudgetStatus`, the
  object the Budget tab renders.
- **How it runs.** An inexact `AlarmManager` alarm at 22:00 (allowed while
  idle; no exact-alarm permission; may arrive a few minutes late) wakes
  `DailyDigestReceiver`, which starts a headless Flutter engine on
  `digestMain`. Dart parses the alerts the SMS receiver stored today
  (`processStored`, no inbox read needed), loads the ledger with the statement
  merge, measures the month and hands the text back to Kotlin to post. The
  alarm is re-armed on every run, after reboot and after an app update.
- **Control.** On by default (the owner asked for it), a switch on the Budget
  tab, and "Preview it now", which runs the real background job immediately.
- **Privacy.** Computed on the phone; nothing leaves it.

[sts]: https://apps.apple.com/us/app/-/id6758524287
[ih1]: https://www.indiehackers.com/post/launched-a-simpler-money-app-built-around-how-much-can-i-safely-spend-today-874382689f
[ih2]: https://www.indiehackers.com/post/building-a-money-app-for-people-who-stop-using-budgeting-apps-after-1-day-8bb68e7629
[mf]: https://www.producthunt.com/p/moneyflow-daily-spending/moneyflow
[mon]: https://www.monarch.com/blog/rollovers-and-referral-rewards
[ipl]: https://www.iphonelife.com/content/comparing-budgeting-apps-iphone
[bc]: https://beancount.io/forum/t/copilot-vs-monarch-vs-ynab-which-premium-budget-app-is-worth-it/98
[jup]: https://jupiter.money/blog/best-expense-tracker-app
[om]: https://outlookmoney.com/technology/best-money-management-apps-available-today-4233
[dig]: https://www.digit.in/features/apps/the-geeks-guide-to-money-management-apps-29801.html/amp/
[larky]: https://www.cuinsight.com/press-release/85-of-fi-customers-opt-into-push-notifications-according-to-inaugural-larky-lowdown-report/
[ct]: https://clevertap.com/blog/how-to-boost-fintech-push-notification-ctrs/
[pl]: https://www.plotline.so/blog/push-notification-best-practices-fintech-apps
[pw]: https://www.pushwoosh.com/blog/push-notifications-fintech/
[gb]: https://gurubase.io/g/flutter/scheduling-task-flutter-android
[wm]: https://docs.page/fluttercommunity/flutter_workmanager/quickstart

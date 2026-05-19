# Finance SMS Design Log

## 2026-05-19 MVP screen

Goal: a minimal Android-first screen for Indian UPI/card/account SMS spending.

Design decisions:
- First screen is the working dashboard, not a landing page.
- Primary information is this month's parsed spend, scan status, last scan time, and recent transactions.
- Permission state stays in context on the same screen so the user can grant SMS access without navigating.
- Empty, denied, unsupported, scanning, and error states all render inside the main screen.
- Visual tone is utility-first: warm off-white background, green financial emphasis, restrained card surfaces, and 8 px radius.
- Icon use is functional: SMS for scan/permission, bank/card/wallet/UPI icons for transaction rows, refresh/settings in the app bar.
- Text remains compact and operational. Privacy copy is visible because SMS access is sensitive: raw SMS is not stored or uploaded.

Current components:
- Header panel: monthly spend, scan inbox button, last scan, latest scan counts.
- Permission panel: READ_SMS consent state, allow/open settings action, Android-only unsupported state.
- Recent transaction list: merchant/payee fallback, sender, account/card hint, amount, timestamp, and instrument icon.
- Empty/error panels: same-screen recovery without extra navigation.

Future design notes:
- Add filters only after the parser has enough real-world samples.
- Add review/edit transaction flows before adding charts.
- Add export only if local-only users need backup.

## 2026-05-19 Continuous SMS classification

Goal: turn new transaction SMS into categorized expenses with as little friction as possible.

Design decisions:
- New transaction SMS are stored as uncategorized expenses first.
- Android notification actions show only two fast choices: Food and Travel.
- The third notification action is Other, which opens the app for the full category list.
- Default categories are Food, Travel, Lifestyle, Education, and Bills.
- Users can add a custom category from the in-app classification panel and immediately apply it.
- Uncategorized expenses appear above the recent transaction list so notification misses are still recoverable.
- Export CSV sits beside Scan inbox because it is a utility action on the current local ledger.
- Transaction rows show the assigned category as a compact chip.

# Finance SMS System Design

## MVP Architecture

Pattern: MVVM with local-only storage.

Flow:
1. `HomeScreen` renders state and user actions.
2. `HomeViewModel` owns permission, scan, summary, and error state.
3. `TransactionRepository` coordinates SMS reads, parsing, dedupe, and summary reads.
4. `SmsReaderService` reads Android inbox SMS through a Kotlin `MethodChannel`.
5. `SmsParserService` turns transaction alert SMS into `ParsedTransaction` objects.
6. `TransactionStore` persists parsed transactions through SQLite.
7. `TransactionSmsReceiver` handles new Android SMS broadcasts, parses transaction alerts natively, stores them in the same SQLite database, and posts category notifications.

No backend, network upload, analytics, contact access, or SEND_SMS exists in the MVP.

## Android SMS Access

Permissions:
- Inbox import uses `android.permission.READ_SMS`.
- Continuous scan adds `android.permission.RECEIVE_SMS`.
- Classification notifications add `android.permission.POST_NOTIFICATIONS`.
- Runtime permission is requested through `permission_handler`.
- Native code checks READ_SMS before querying `Telephony.Sms.Inbox`.
- Inbox scan defaults to the latest 1000 messages.
- New incoming SMS are handled through Android's `SMS_RECEIVED` broadcast receiver.

Google Play stance:
- READ_SMS and RECEIVE_SMS are restricted permissions.
- This app is designed for the SMS-based money management use case.
- User consent text must remain prominent.
- Play Console declaration should state that SMS is processed locally to detect financial transaction alerts and raw SMS is not stored or uploaded.

Source:
- Google Play SMS/Call Log policy: https://support.google.com/googleplay/android-developer/answer/10208820
- Android notification permission: https://developer.android.com/develop/ui/views/notifications/notification-permission
- Android notification actions: https://developer.android.com/develop/ui/views/notifications/build-notification#Actions

## Storage Contract

Stored transaction fields:
- `source_sms_id` unique key for SMS dedupe.
- `sender` and `normalized_sender`.
- `timestamp_millis`.
- `amount_paise`.
- `direction`: `expense` for real spending and `transfer` for non-expense money movement such as credit-card bill repayment, wallet/UPI Lite top-up, self-transfer, and investment movement.
- `instrument`: `upi`, `debitCard`, `creditCard`, `account`, `wallet`, or `unknown`.
- `account_hint` and `merchant` when safely inferred.
- `reference_id` when a UPI/UTR/RRN/transaction/reference ID is safely inferred.
- `confidence`.
- `category_id`, `category_name`, and `classified_at_millis`.
- `created_at_millis`.

Raw SMS body is not persisted.

Categories:
- Default list: Food, Travel, Lifestyle, Education, Bills.
- Users can add custom categories.
- Notification quick actions classify as Food or Travel.
- The Other notification action opens the app so the user can pick any category or add a new one.
- Only `expense` transactions appear in the uncategorized classification queue.

## Duplicate And Non-Expense Transfer Strategy

Monthly spend is intended to mean consumption spend, not every cash outflow. Some SMS pairs describe the same economic event from two sides, and some debit SMS are liability or stored-value movements rather than new expenses.

Handled now:
- Credit card bill repayment is stored as `transfer`, not `expense`, so a Rs.5,000 card purchase plus a later Rs.5,000 UPI card bill payment remains Rs.5,000 of monthly spend.
- Card issuer "payment received" / credit acknowledgement messages stay excluded because they are the receiving side of the repayment.
- Wallet and UPI Lite loads are stored as `transfer`, because the later wallet/UPI Lite payment is the spend event when an alert exists.
- Self-transfers between own accounts are `transfer`.
- Mutual funds, SIPs, demat/broker transfers, fixed deposits, recurring deposits, NPS, and PPF are `transfer`.
- Paired bank and payment-app alerts are deduped first by `reference_id + amount`, then by amount + two-minute time window + similar merchant across different senders.

Known ambiguous cases:
- EMI and loan repayments can be either bills/cashflow or principal repayment. The MVP does not auto-exclude every EMI because users often expect EMIs in monthly bills, and SMS rarely splits principal from interest.
- ATM withdrawals are cash movement. If the app has no manual cash expense tracking, counting withdrawal can be useful; if manual cash tracking is added later, withdrawals should become transfer-to-cash to avoid duplicates.
- FASTag, transit card, and prepaid recharge can be top-ups or final travel spend depending on whether later usage alerts are available.
- Refunds, reversals, chargebacks, and cashback are currently excluded from gross spend. A later net-spend mode should store them as adjustments and subtract them from matching expenses.
- Split bills and reimbursements cannot be fully resolved from SMS alone; user review or merchant/contact context will be needed.

Research notes:
- UPI, BBPS/Bharat Connect, UPI Lite, and RuPay credit-card-on-UPI make it normal for one real-world payment to produce multiple bank/payment/biller messages.
- Credit-card bill payment is a repayment of a prior card liability, so counting both the original card spend SMS and the repayment debit SMS doubles consumption.
- Transaction/reference IDs are the strongest duplicate signal when present; sender IDs remain weaker because Indian DLT headers vary by operator and route.

Sources:
- NPCI UPI: https://www.npci.org.in/what-we-do/upi/product-overview
- NPCI RuPay credit card on UPI: https://www.npci.org.in/what-we-do/rupay/rupay-credit-card-on-upi
- NPCI Bharat BillPay / Bharat Connect: https://www.npci.org.in/who-we-are/group-companies/npci-bharat-billpay-ltd/bharat-connect-overview/
- NPCI UPI Lite: https://www.npci.org.in/what-we-do/upi-lite/product-overview
- RBI credit/debit card directions: https://www.rbi.org.in/Scripts/NotificationUser.aspx?Id=12300&Mode=0

## Parser Rules

Primary rule: transaction wording is stronger than sender ID.

Included as expenses:
- Debit messages: debited, spent, paid, purchase, charged, withdrawn, sent, transferred, used, billed.
- UPI spends and wallet/card/account debit alerts with a rupee amount.

Stored as transfers, excluded from monthly spend:
- Credit-card bill payment/repayment/dues/outstanding messages.
- BBPS/Bharat BillPay/BillDesk/CRED/Cheq card bill payments.
- Wallet and UPI Lite top-ups or loads.
- Self-transfers between own accounts.
- Investments and deposits such as mutual funds, SIP, demat/broker transfers, FD/RD, NPS, and PPF.

Excluded:
- OTP or verification messages.
- Credits, refunds, reversals, deposits, cashback, failed/declined transaction messages.
- Marketing, loan, offer, statement, balance-only, or unverifiable promotional SMS.

Amount handling:
- Currency-first Indian formats such as `Rs.500`, `INR 1,234.50`, and rupee-symbol amounts.
- When multiple amounts exist, the parser prefers the amount nearest debit/card/UPI wording and avoids balance-like windows.

## Sender ID Research

Indian finance SMS sender IDs are useful hints, not stable identifiers. Headers can vary by operator, circle, bank product, aggregator, DLT registration, and category suffix. The parser therefore normalizes the sender and still requires transaction wording.

Normalization:
- Strip operator/circle prefixes such as `VM-`, `AX-`, `AD-`, `VK-`, or other two-letter prefixes.
- Strip DLT category suffixes such as `-T`, `-S`, `-P`, and `-G`.
- Keep the remaining uppercase sender token as the lookup key.

Starter catalog groups:
- HDFC Bank: `HDFCBK`, `HDFCIN`.
- ICICI Bank/cards: `ICICIB`, `ICICIC`.
- Axis Bank: `AXISBK`, `AXISIN`.
- SBI and SBI Card: `SBIUPI`, `SBIINB`, `SBICRD`.
- Kotak: `KOTAKB`, `KOTAKC`.
- IDFC FIRST, Canara, PNB, Bank of Baroda, Union, Yes, IndusInd, Federal, RBL, AU, DBS.
- Payments/wallets: `PAYTMB`, `PHONEP`, `GPAY`, `GOOGLEP`, `AMZNPAY`, `AMAZON`.
- Generic category hints: `UPI`, `CCARD`, `DEBITC`.

Research sources and ongoing validation:
- TRAI SMS header portal: https://smsheader.trai.gov.in/
- TRAI SMS header list reference: https://www.trai.gov.in/node/7411
- DLT header/category background: https://www.messagecentral.com/ar/sms-guideline/india
- Sender catalog should be expanded from real user samples only after removing personally identifiable details.

## Packages

Runtime:
- `provider`: view model injection and listening.
- `permission_handler`: runtime SMS permission flow.
- `sqflite`: local parsed transaction database.
- `intl`: Indian currency and date formatting.
- `path`: database path composition.

Native Android:
- `TransactionSmsReceiver`: receives new SMS and stores pending transactions.
- `CategoryActionReceiver`: handles Food/Travel notification actions.
- `NativeFinanceDatabase`: keeps native inserts aligned with the Flutter SQLite schema.
- `MainActivity` export channel: writes CSV to Downloads/Finance SMS on Android 10+ and app documents on older Android versions.
- Food/Travel notification actions use a broadcast `PendingIntent`, so choosing them does not open the app. The transaction is already stored by `TransactionSmsReceiver`; `CategoryActionReceiver` only updates `category_id`, `category_name`, and `classified_at_millis` on that existing row.
- Manual inbox scans use the same source fingerprint/reference/merchant-window dedupe path, so a transaction classified from notification is not inserted again when the user later opens the app and scans.

Theme and UI state:
- `ThemeViewModel` persists `system`, `light`, and `dark` mode through `shared_preferences`.
- `MaterialApp.themeMode` is driven by the theme view model, and both light/dark themes are built from Material 3 seed colors.
- The dashboard is themed entirely from `Theme.of(context).colorScheme`, so the same widgets render correctly in both modes.

Credit card model:
- Parsed transactions can carry masked card metadata: `card_issuer` and `card_last_digits`.
- Credit-card summaries are derived from stored transactions and grouped by `issuer + last digits`.
- Card summaries only count rows where both issuer and masked digits exist.
- Monthly card spend includes only expense rows, so repayments and transfer-style messages do not inflate the card total.

References:
- Flutter architecture guide: https://docs.flutter.dev/app-architecture/guide
- Pub packages: https://pub.dev/packages/provider, https://pub.dev/packages/permission_handler, https://pub.dev/packages/sqflite, https://pub.dev/packages/intl

## Testing Strategy

Unit tests:
- Sender normalization.
- Amount parsing.
- Debit/card/UPI/account classification.
- Credit/refund/OTP/marketing exclusion.
- Repository duplicate handling with fake SMS reader and fake store.

Widget tests:
- Permission-required screen.
- Empty screen.
- Populated transaction list after scan.
- Error state.

Manual Android acceptance:
- Install debug APK.
- Grant SMS permission.
- Tap scan.
- Confirm recent expenses are shown and non-transaction SMS are not persisted.

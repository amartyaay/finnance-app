# Gold labelling guide — SMS ground truth

The gold set is the answer key the accuracy auditor (`tool/audit_accuracy.dart`) and the
on-device classifier are measured against. It is labelled by reading each real message,
**never by running the app's parser** — a label copied from the parser can only agree with it.

Raw messages and labels live in `.local/gold/` (gitignored: they are the owner's real SMS).
Only this guide and aggregate numbers are committed.

## Output format

One JSON object per line (`labels_N.jsonl`), one line for **every** message in the chunk:

```json
{"id":"sms:…","label":"debit","kind":"spend","amount":349.00,"instrument":"HDFC card 1234","dup_of":null,"note":""}
```

| Field | Values |
|---|---|
| `label` | `debit` · `credit` · `bill_notice` · `otp` · `promo` · `phishing` · `info` |
| `kind` | only for `debit`/`credit`, see below; otherwise `null` |
| `amount` | rupees as a number (two decimals allowed) for `debit`/`credit`/`bill_notice` (the total due); otherwise `null` |
| `instrument` | the account/card/wallet money moved on, as printed (`"SBI a/c 1234"`, `"Amex card 1005"`, `"Paytm wallet"`); `null` if not stated |
| `dup_of` | the `id` of an **earlier** message describing the **same money movement** (bank alert + UPI app alert, two SMS for one card swipe, debit leg + credit leg of a self-transfer). `null` otherwise |
| `note` | a few words when the call was hard; empty otherwise |

## Labels

- **`debit`** — money has **already left** one of the owner's accounts, cards or wallets. Past tense or
  present-perfect: *debited, spent, paid, withdrawn, sent, transferred, auto-debited, charged*.
- **`credit`** — money has **already arrived**: *credited, received, refunded, reversed, cashback credited*.
- **`bill_notice`** — a card statement or bill/due reminder: *total due, minimum due, statement generated,
  payment due on*. No money moved.
- **`otp`** — one-time passwords and verification codes, including "never share this OTP".
- **`promo`** — offers, pre-approved loans/cards, "eligible for", "upto", cashback *offers*,
  "get ₹X", insurance/investment pitches, cart reminders, EMI conversion offers — **even when sent by the owner's
  own bank and even when they contain an amount and words like "payment of"**.
- **`phishing`** — tries to get the owner to click/call/pay/share credentials under false pretence:
  fake KYC block, fake electricity disconnection, lottery, "your account will be suspended", unknown
  sender with a link asking to update details. The owner's genuine bank saying "never share your OTP" is **not** phishing.
- **`info`** — everything else: balance-only alerts, failed/declined transactions, UPI collect
  **requests** (money not moved), mandate/autopay *registered* or *scheduled* ("will be debited on"),
  payment *reminders*, delivery updates, login alerts, card blocked/unblocked confirmations, personal SMS.

When in doubt between `debit` and anything else: **if you cannot tell that money already moved, it is not `debit`.**
A failed payment, a scheduled debit, a request, or a "you can pay" is `info`/`promo`.

## Kinds (for `debit` / `credit`)

| kind | meaning |
|---|---|
| `spend` | paid a merchant or bought something (UPI to a merchant, card swipe/online, POS, bill payment to a utility/telecom, subscription) |
| `p2p` | sent to / received from a person (UPI to a named individual), not obviously self |
| `transfer_self` | between the owner's own accounts, wallet top-up from own bank, own UPI Lite load |
| `card_bill_payment` | paying a credit-card bill (debit side), or the card's "payment received" (credit side) |
| `investment` | SIP, mutual fund, stocks, FD/RD/TD booking or closure proceeds, NPS, PPF |
| `emi_loan` | EMI, loan repayment, loan disbursal (credit) |
| `cash` | ATM / cash withdrawal |
| `refund` | refund, reversal, chargeback, failed-transaction money returned |
| `cashback` | cashback or reward actually **credited** |
| `salary` | salary/payroll credit from an employer |
| `interest` | interest credited, dividend |
| `other` | money moved but none of the above fits — say why in `note` |

## Worked edge cases

1. "Rs.2,000 debited from A/c XX1234 … UPI Ref … to SWIGGY" → `debit/spend/2000`.
2. "You've received a payment request of Rs 500 from X" → `info`.
3. "Txn of Rs 1,200 on HDFC Card xx1234 at AMAZON declined" → `info`.
4. "Get a personal loan of Rs 36,000 instantly" (even from the bank) → `promo`.
5. "Payment of Rs 15,000 received towards your credit card xx1234" (from the card issuer) → `credit/card_bill_payment`.
   The matching SBI debit "Rs 15,000 debited … to CRED/BillDesk/HDFC Card" → `debit/card_bill_payment`, and
   **not** `dup_of` the credit (they are two legs of one movement, but on different instruments; mark the later one's
   `dup_of` = the earlier one **only** if both describe the same instrument's money).
6. Self-transfer from SBI to HDFC: SBI debit and HDFC credit are two legs → label both `transfer_self`;
   set the later leg's `dup_of` to the earlier one.
7. Bank alert + PhonePe/GPay/Paytm alert for the same UPI payment → second one `dup_of` the first.
8. "Your SIP of Rs 5,000 will be debited on 5th" → `info`. "SIP of Rs 5,000 processed/debited" → `debit/investment`.
9. "Statement for card xx1234: Total due Rs 13,402, Min due Rs 670, due 12 Nov" → `bill_notice`, amount 13402.
10. "Rs 105 cashback credited to your Amazon Pay balance" → `credit/cashback`.

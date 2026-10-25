# 07 — Importing an SBI savings-account statement PDF, fully on-device

**Status:** decision memo plus engineering reference. Not a spec.
**Date:** 2026-10-26 (IST). Every web claim was fetched today. Package versions come from `pub.dev/api` and Maven Central today.
**Decision needed:** (1) which library opens the owner's encrypted SBI PDF and returns positioned text on Android; (2) how to rebuild the table and prove each row is right; (3) how to tell salary apart from other credits and slice spend into salary-to-salary cycles.
**Grounding:** code in `lib/domain/statement.dart` (`StatementKind`, `StatementRow`) and `lib/engine/salary_cycles.dart` (`SalaryDetector`, `SalaryCycle`). This memo adds to that code and does not replace it. Also `docs/research/01-sms-corpus.md` §SBI and `03-credit-semantics.md`.
**Toolchain checked:** `flutter --version` → **Flutter 3.41.9, Dart 3.11.5**. Note: `CLAUDE.md` says Dart 3.12, but this machine reports 3.11.5. `minSdk = flutter.minSdkVersion`, which is **24** in this Flutter (`FlutterExtension.kt`). The main `AndroidManifest.xml` has **no `INTERNET` permission**. Only the debug and profile manifests add it.

---

## 0. The decision in one page

**Library: `pdfrx: 2.4.8`, pinned exactly.** It wraps PDFium, which Chrome uses as its PDF engine. PDFium opens Standard-security-handler files at V1–V5 and R2–R6: RC4 40–128 and AES-128/256. That covers the owner's **V2 R3 RC4-128** file. `PdfPage.loadText()` returns every character with its rectangle, which is what we need to split columns. The licence is MIT. On arm64 it adds about **3.3 MB** (`libpdfium.so`, `chromium/7811`). Why pin 2.4.8: **every pdfrx release from 2.5.0 on needs Flutter ≥ 3.47**, and we are on 3.41.9.
The fallback is `syncfusion_flutter_pdf 35.1.41`. It is pure Dart, needs no native build, and also handles passwords and text lines with bounds. It is not first choice because its licence is not open source (community licence: under $1M revenue and under 5 developers). Section 5 has the full comparison.

**Picker: `file_picker: ^13.2.0`.** On Android it launches `ACTION_OPEN_DOCUMENT` through the Storage Access Framework, needs **no storage permission**, and copies the picked file into `cacheDir/file_picker/`. Section 6 covers it.

**Password: the user types it, and it is never stored.** The app *suggests* the formula. For a statement SBI emails, sources most often give **last 5 digits of the registered mobile + date of birth as DDMMYY**, e.g. `98765150890`. The exact rule depends on the channel: OnlineSBI downloads use the **account number**, YONO uses **DOB as DDMMYYYY**, and `ESTMT` SMS requests use a **4-digit code the user chose**. SBI publishes no single rule. Third-party guides disagree, and at least one says the covering email states the rule. Section 2 lists every variant with its source. The app can safely try at most 3 candidates it builds locally from the DOB, mobile and account number the user enters for that one attempt.

**Layout: never hard-code columns.** We have seen **four** different SBI table layouts, and SBI changed its export format again in July 2026 ([GnuCash list](https://lists.gnucash.org/pipermail/gnucash-user/2026-July/121136.html)). Columns come from header words, located by x position. Amounts are right-aligned, so each figure goes to the column whose header *right edge* is nearest. **Every row must satisfy `prev − debit + credit = balance` in integer paise.** A statement where any row fails that check does not go into the ledger silently. Section 7 has the algorithm.

**Salary needs no keyword.** Salary is the largest stream of credits from **one payer**: in at least 2 different months, gaps of 24–38 days, amounts within ±25 % of the stream median, arriving by NEFT/RTGS/BULK POSTING/CEMTEX/NEFT-from-treasury, and **not** a self-transfer, refund, reversal, interest, redemption or UPI P2P. The payer key is the remitter field of the NEFT narration (`NEFT*<IFSC>*<UTR>*<REMITTER>`), **not** the UTR. A narration saying `SALARY`/`SAL`/`BY SALARY` is enough on its own. `lib/engine/salary_cycles.dart` already does most of this. Section 4 lists what to add: the channel weight, the remitter key, bonus/arrears handling, a job switch, and two salaries.

**The one thing to do first:** open the owner's real PDF once with pdfrx and dump a **masked layout**: each word reduced to `DATE@x`, `NUM@x` or `TXT@x`, as `kharchalens/scripts/dump_sbi_pdf.py` does ([source](https://github.com/aakraj/kharchalens)). That shows which of the four layouts SBI sent this owner before any parser code is written. It takes 30 minutes, and the output holds no personal data, so it can be committed as a fixture.

**Effort:** extraction and table rebuild, 2 days. Narration classifier, 2 days. Salary cycles on top of the existing detector, 1 day. Import UI (pick → password → review → confirm), 2 days. **About 7 days**, plus 0.5 day if the native-assets build misbehaves (§5.4).

---

## 1. The SBI statement formats found in the wild

SBI issues a savings-account statement through at least five channels, and the table layout differs between them. These are the four layouts confirmed from real documents. Personal data is masked; the structure and vocabulary are verbatim.

| | **A. CBS e-statement** (emailed monthly / on request) | **B. OnlineSBI "Account Statement" PDF** | **B′. OnlineSBI print view** (`retail.onlinesbi.sbi/retail/printstatement.htm`, saved as PDF) | **C. 2025–26 YONO / new-web export** |
|---|---|---|---|---|
| Title line | `STATEMENT OF ACCOUNT … STATE BANK OF INDIA` | none; header block of `Key : value` lines | `State Bank of India` + URL + browser timestamp | `STATE BANK OF INDIA` / `Account Statement` (exact wording unconfirmed) |
| Columns, in order | `Post Date` · `Value Date` · `Details` · `Chq.No` · `Debit` · `Credit` · `Balance` | `Txn Date` · `Value Date` · `Description` · `Ref No./Cheque No.` · `Debit` · `Credit` · `Balance` | `Date (Value Date)` · `Narration` · `Ref/Cheque No.` · `Debit` · `Credit` · `Balance` | XLSX: `Date` · `Details` · `Ref No/Cheque No` · Debit · Credit · Balance ([script](https://github.com/abhijit86k/gnucash_statement_preprocessors)). PDF: `Txn Date` · `Value Date` · `Description` · `Debit` · `Credit` · `Balance` ([fixture](https://github.com/harshsingh-io/indian-bank-statement-parser/blob/main/tests/fixtures/sbi-basic.txt)). Kharchalens also handles `Post Date`/`Details`/`₹ Debit`/`₹ Credit` |
| Date format | `dd/mm/yy` (`07/11/20`) | `d Mon yyyy` (`1 Jul 2023`). **The year often wraps onto the next line** (`25 Jun` / `2023`) | `dd-Mon-yy` + `(dd-Mon-yyyy)` on the next line | `dd/mm/yyyy` |
| Amounts | plain `5000.00` in rows; Indian grouping `26,18,550.00` in carried-forward and summary lines | Indian grouping `1,75,532.00` | Indian grouping | Indian grouping; blank shown as `-` (YONO) or empty |
| Balance | **`Cr` / `Dr` suffix**: `2618072.00Cr` | unsigned; a loan account prints negative `-1,11,111.00` | unsigned | unsigned |
| Empty Debit/Credit cell | blank (nothing printed) | blank; in the `.xls` export a single space | blank | `-` or blank |
| Opening balance | `BROUGHT FORWARD : … 0.00` row; repeated at the top of each page | `Balance as on 1 Apr 2022 : 4,62,965.00` in the header block | `Balance as on01/01/2024 1,45,226.80` (no space after "on") | `Opening Balance` in summary (unconfirmed) |
| Page break | `CARRIED FORWARD : 26,18,550.00Cr`, then the full header block again | the full header block repeats on every page | `n of N` and URL footer, header row not always repeated | unknown |
| Closing / summary | `Statement Summary` / `Dr. Count 3  Cr. Count 7  40,250.00 26,58,800.00` | last row's balance | last row's balance | `Statement Summary` row ([script](https://github.com/abhijit86k/gnucash_statement_preprocessors/blob/main/SBIXLS2Gnucash.py) stops at it) |
| Narration style | terse CBS codes on line 1 (`DEP TFR`, `WDL TFR`, `POS ATM PURCH`), detail on lines 2–3, branch line `AT 70155 <BRANCH>` | `TO TRANSFER-…` / `BY TRANSFER-…` / `CREDIT INTEREST--`, wrapped at ~25 chars | same vocabulary as B, prefix and detail on separate lines | `UPI/DR/…` without the `TO TRANSFER-` prefix |
| Footer junk | `In Case Your Account Is Operated By A Letter Of Authority/Power Of Attorney Holder, Please Check The Transaction With Extra Care.` | `Please do not share your ATM, Debit/Credit card number, PIN (Personal Identification Number) and OTP (One Time Password) …` and `**This is a computer generated statement and does not require a signature` | `**This is a computer generated statement …`, `Print Back` | `********* End of Statement **********` |
| Seen in | [public SBI e-statement PDF, Thodupuzha, 2020](https://joselect.com/photos/files/mrls_20201129100826_39734820704_15-10-2020_24-11-2020.pdf); a 2023 statement filed in court ([Allahabad HC](https://dc.allahabadhighcourt.in/assets/documents/request/request1709820201.pdf)) | court filings 2021–23 ([1](https://dc.allahabadhighcourt.in/assets/documents/request/request_document16892614585.pdf), [2](https://dc.allahabadhighcourt.in/assets/documents/property/property1722531040.pdf), [3](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document17065950211.pdf)); [pf_dashboard fixtures](https://github.com/hstejas/pf_dashboard/tree/main/test/plugins) | court filings 2022 and 2024 ([1](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document16608202404.pdf), [2](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document17052286160.pdf)) | [gnucash preprocessors, July 2026 commit](https://github.com/abhijit86k/gnucash_statement_preprocessors); [indian-bank-statement-parser](https://github.com/harshsingh-io/indian-bank-statement-parser); [kharchalens](https://github.com/aakraj/kharchalens) |
| Confidence | **High** (two independent real files, 2020 and 2023) | **High** (five real files, two open-source parsers) | **High** (two real files) | **Medium**: column names come from parser code and a hand-written fixture, not from a real file we saw |

**Which one the owner has.** The brief calls it the "e-statement" with RC4-128. Kharchalens' SBI PDF parser describes SBI e-statement PDFs as "`Post Date`/`Value Date`/`Details` and single-amount columns `₹ Debit` / `₹ Credit`" ([source](https://github.com/aakraj/kharchalens/blob/main/kharchalens/parser/sbi_pdf.py)). That is layout A, possibly with a `₹` added to the headers. **The parser is header-driven, so it handles all four; we just need to know which one to write fixtures for first.**

### 1.1 Verbatim rows, masked

**A. CBS e-statement** (2020, the first rows of a page; this is pdfplumber word output with x ranges, which shows the geometry):

```
Post Date Value Date                   Details          Chq.No        Debit      Credit             Balance
15/10/20@57-88  15/10/20@107-138  CHQ TRFR FROM@162-230  5504xx@284-311          10000.00@414-447  10000.00Cr@506-548
                                  3918xxxxxxx OF Mr. V
                                  AT 7xxxx <BRANCH>
02/11/20        02/11/20          CAS CHQ XFER WD        1747xx  30000.00@352-385            2526248.00Cr@497-547
                                  CHEQUE TRANSFER TO
                                  3118xxxxxxx OF Mr. S
06/11/20        06/11/20          WDL TFR                         5000.00@356-385             2515998.00Cr
                                  UPI/DR/0311xxxxxxxx/
                                  4897xxxxx2093
07/11/20        07/11/20          BY CLEARING            0080xx            97073.00@414-447  2613071.00Cr
                                  SIB BY CLEARING CH
07/11/20        07/11/20          DEP TFR                                      5000.00@419-448  2618072.00Cr
                                  UPI/CR/0312xxxxxxxx/
                                  5099xxxxx2096
                                  CARRIED FORWARD :                                         26,18,550.00Cr
Statement Summary
Dr. Count 3               Cr. Count 7                           40,250.00 26,58,800.00
```

Geometry facts from that file: Debit right edge ≈ 385 pt, Credit right edge ≈ 447 pt, Balance right edge ≈ 547 pt. Every amount is **right-aligned**: `5000.00` starts at 356 and `30000.00` at 352, but both end at 385. **Use `x1`, not `x0`, to assign amounts.**

A 2023 CBS file has the same layout with modern narrations ([source](https://dc.allahabadhighcourt.in/assets/documents/request/request1709820201.pdf)):

```
15/12/23      15/12/23      WDL TFR                            3415.00                    81.54Cr
                            INB IMPS/P2A/3349xxx…
                            POS ATM PURCH                                   1009.00     2033.30Cr
                            ATM WDL
                            ATM CASH 1364 <LOCATION>
                            DEP TFR
                            NEFT RBI3552xxxxxxxx
23/12/23 23/12/23           NEFT UTR NO: SBIN423…            500.00                     365897.26Cr
                            INTEREST CREDIT
```

**`pdftotext -layout` scrambles this format.** In the layout output, a row's amounts float several lines away from its narration. A line-based text parser cannot recover it. Grouping words by their `top` coordinate can. This is the main reason we need character positions, not plain text.

**B. OnlineSBI Account Statement PDF** (2023, [source](https://dc.allahabadhighcourt.in/assets/documents/request/request_document16892614585.pdf)):

```
Interest Rate(% p.a.)      :2.7
MOD Balance                :0.00
Balance as on 7 Dec 2022 :20,86,xxx.40
Txn Date Value             Description                Ref No./Cheque      Debit     Credit                  Balance
      18 Dec    18 Dec ATM WDL-ATM CASH 7824                                     72,821.00              21,53,776.40
      25 Dec    25 Dec CREDIT INTEREST--                                                                22,15,827.28
2 Jan 2023 2 Jan 2023 BY TRANSFER-                    TRANSFER
                           NEFT*RBIS0GOUPEP*RBI002 FROM
      22 Feb    22 Feb TO CLEARING-HDF KESCO 4762xx                   12,663.00
7 May 2023 7 May 2023 TO TRANSFER-INB                     IMPS0022xxxxxxx
                      IMPS/P2A/3127xxxxxxxx/XXX 8MOAHTRCOL1
                      XXXX569HDFC-                        TRANSFER T
24 May   24 May TO TRANSFER-INB Central                   2305241800xxxxx
```

Also seen in B-format files: `DEBIT-ACHDr`, `CASH CHEQUE-CASH  1422xx  50,000.00`, `CHEQUE WDL--1422xx`, `TO TRANSFER-Renewal` (FD renewal), `TRANSFER CREDIT-SWEEP FROM`, `TAX DEDUCTION`, `BY TRANSFER-Excess TDS deducted on 31-Mar-2021`, `DEBIT INTEREST-Credited to`, `by debit card-OTHPG 4683xx 393.85`, `BULK POSTING-BY SALARY-  TRANSFER T  98,364.40`, `BY TRANSFER-INB Reversal IMPS0019xxxxxx`, `TO TRANSFER-INB Billpay ~ IB8803xxxx`, `To ATM ANNUAL CHARGES FOR (3685xx)`, `PROCESSING FEES`, `FEE DEBIT TO SAVING …`, and the zero-amount informational row `CR RT CHG 7.100` (credit-rate change, not a charge). Sources by string: ACHDr / CASH CHEQUE / CHEQUE WDL / Renewal ([1](https://dc.allahabadhighcourt.in/assets/documents/property/property1722531040.pdf)); SWEEP / TAX DEDUCTION / Excess TDS / DEBIT INTEREST ([2](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document17065950211.pdf)); OTHPG ([3](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document17097070092.pdf)); BULK POSTING-BY SALARY, REIMB, Billpay ([4](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document16379959663.pdf)); Reversal IMPS ([5](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document16860445632.pdf)); CR RT CHG ([6](https://dc.allahabadhighcourt.in/assets/documents/property/objection_document17160229910.pdf)).

**B as the `.xls` "Excel" download** is not a spreadsheet. It is **tab-separated text with an `.xls` extension**, needs no password, and begins with a `Key :\tvalue` block ([gnucash README](https://github.com/abhijit86k/gnucash_statement_preprocessors); [pf_dashboard fixture](https://github.com/hstejas/pf_dashboard/blob/main/test/plugins/test_sbi_good_case1.txt)). Tabs are shown here as `⇥`:

```
Start Date          :⇥1 Apr 2021
End Date            :⇥31 Aug 2021
Txn Date⇥Value Date⇥Description⇥Ref No./Cheque No.⇥        Debit⇥Credit⇥Balance⇥
5 Apr 2021⇥5 Apr 2021⇥   DEPOSIT TRANSFER---⇥TRANSFER FROM 1234                         ⇥ ⇥10,000.00⇥1,92,226.00
**This is a computer generated statement and does not require a signature
```

Quirks: the header literally reads `        Debit`, with 8 leading spaces ([SBICSV2Gnucash.py](https://github.com/abhijit86k/gnucash_statement_preprocessors/blob/main/SBICSV2Gnucash.py) renames `'        Debit'`). Each line ends with a trailing tab. An empty amount cell is a single space. Narration and Ref cells are padded with spaces. **Row order can be newest-first**: the second pf_dashboard fixture runs 30 Nov → 1 Nov. Use the balance arithmetic to detect order (§7.6).

**B′. OnlineSBI print view** (January 2024, [source](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document17052286160.pdf)):

```
Balance as on01/01/2024      1,45,226.80
Date (Value Date) Narration                             Ref/Cheque No.       Debit           Credit       Balance
01-Jan-24              by debit card                                         800.00                       1,44,524.80
(01-Jan-2024)          OTHPG 4001xxxxxxxxPaytm M
                       umbai
02-Jan-24              BY TRANSFER                      TRANSFER FROM 4697                   1,09,682.00  2,54,206.80
(02-Jan-2024)          NEFT*RBIS0GOUPEP*RBI0032         1790xxxxx
                       4869xxxxx*<DISTRICT> TREA
                       SU
13-Jan-24              ATM WDL                                               8,000.00              1,69,294.07
(13-Jan-2024)          ATM CASH 40131 2 83 <LOCATION>
12-Jan-24              by debit card                                         698.74                1,77,294.07
(12-Jan-2024)          SBIPG 5000xxxxxxxxwww.zom
                       ato.com Gurugram
14-Jan-24              TO TRANSFER                          TRANSFER TO 4897696  1,999.00
(14-Jan-2024)          UPI/DR/4014xxxxxxxx/Bhim Sin 162090
                       gh/PYTM/97xxxxxxxx/Pay
```

From a 2021 file in the same layout ([source](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document16608202404.pdf)), these are the two credit-card bill shapes we have seen:

```
05-Apr-21   TO TRANSFER                VSBI98852999xxIGAKW 45,622.00
(05-Apr-2021) INB SBICARD FOR BILLDESK   ZASS2 TRANSFER TO
              SBICARD Payments
21-Apr-21   DEBIT                                          66,861.56
(21-Apr-2021) 000000 SBI 0000002054 SBI C
              REDIT CARD PAYMENT
27-Apr-21   BULK POSTING
(27-Apr-2021) CR_PETROL DISCOUNT UP02…
10-Apr-21   DEBIT SWEEP                SWEEP TO 4012xxxxxx 15,000.00
21-Apr-21   TRANSFER CREDIT            SWEEP FROM 3839xxxxx            20,178.00
```

Notes on this layout. The print view's balance column drifts: in text output, balances stack up apart from their rows. A word ends mid-token at the wrap point (`SBI C` / `REDIT CARD PAYMENT`, `TREA` / `SU`). **Join continuation lines with no separator when the first line fills the column width; otherwise join with a space.** The simplest correct approach is to keep two versions, `descJoined` (no separator) and `descSpaced`, and run keyword matching on `descJoined` with spaces removed.

**C. 2026 PDF export** (hand-written fixture that reproduces SBI geometry with invented rows, [source](https://github.com/harshsingh-io/indian-bank-statement-parser/blob/main/tests/fixtures/sbi-basic.txt)):

```
STATE BANK OF INDIA
Account Statement from 01/04/2026 to 06/04/2026
  Txn Date        Value Date                 Description                  Debit                                                Credit               Balance
  01/04/2026                                 UPI/CR/100000000001/A PAYEE/EXBANK                                                 95.00              11542.55
  02/04/2026                                 UPI/DR/100000000002/EXAMPL1,250.00PRIVATE                                                             10292.55
                                             LIMITED/EXBANK/Payment from phone
```

Note `EXAMPL1,250.00PRIVATE`: in plain-text extraction **the debit amount can run into the narration text**. Positioned characters separate them, because the amount's characters sit in the Debit column's x range.

Two observations from the same author, measured on a real SBI account ([README](https://github.com/harshsingh-io/indian-bank-statement-parser)):

> "On one SBI statement the balance column drifted between character 129 and 153, and position alone read a quarter of the balances as credits."
> "a ₹17,000 withdrawal was printed far enough right to read as a deposit — a ₹34,000 error in one row of 146 … The running balance now overrules position."

Also from that README: **"141 transactions (90%) appear only in the statement; 16 (10%) produced an SMS"**, over six months of one SBI account. This is the strongest argument for this feature. SMS alone misses most of an SBI account.

### 1.2 Header-block keys to skip

From [atul0016/bank-statement-parser](https://github.com/atul0016/bank-statement-parser/blob/main/parsers/sbi_bank.py) and [kharchalens](https://github.com/aakraj/kharchalens/blob/main/kharchalens/parser/sbi_pdf.py), confirmed against the files above, matched case-insensitively:
`Account Name`, `Address`, `Account Number`, `Account Description`, `Account Type`, `Branch`, `Drawing Power`, `Interest Rate`, `MOD Balance`/`+MOD Bal`, `CIF No`, `CKYCR`, `IFS Code`/`IFSC`/`Indian Financial System`, `MICR`/`Magnetic Ink`, `Nomination`, `Balance as on`, `Account Statement`, `Statement From`, `Cleared Balance`, `Uncleared Amount`, `Monthly Average Balance`, `Limit`, `Product`, `Currency`, `Page No`, `n of N`, `Please do not share`, `computer generated`, `Power Of Attorney`, `Print Back`, `End of Statement`, `Statement Summary`, `Dr. Count`, `BROUGHT FORWARD` (yields the opening balance), `CARRIED FORWARD` (yields a checkpoint balance).

Keep for metadata: `Account Number` (store only the last 4), `IFS Code` (must start `SBIN`, which also identifies the bank), the period (`Statement From : … to …` / `Account Statement from … to …` / `for the period01/04/2021to31/03/2022`), and the opening balance.

---

## 2. Passwords

**Nothing on sbi.co.in states one rule for savings-account statements.** The rule differs by channel, and third-party guides contradict one another. The table separates the claims and gives each one's evidence.

| Channel | Claimed password | Example (DOB 15-08-1990, mobile …98765, a/c 31234567890) | Evidence |
|---|---|---|---|
| **Emailed e-statement** (monthly, or automatic) | **last 5 digits of the registered mobile + DOB `DDMMYY`** (11 characters) | `98765150890` | [ClearTax](https://cleartax.in/s/sbi-statement-password) (page now 410 Gone; claim quoted in search snippets), [WPS](https://www.wps.com/blog/how-to-open-sbi-bank-statement-pdf-password/), [TrulyInvoice](https://www.trulyinvoice.com/blog/sbi-bank-statement-pdf-password-unlock), [mybankstatementanalysis](https://mybankstatementanalysis.com/blog/sbi-bank-statement-password) ("WhatsApp and auto-emailed statements … reported by customers") |
| Emailed e-statement, legacy | DOB `DDMMYYYY` | `15081990` | [mybankstatementanalysis](https://mybankstatementanalysis.com/blog/sbi-bank-statement-password) |
| `ESTMT <acct> <code>` SMS request | the **4-digit code the user chose** | `4821` | [mybankstatementanalysis](https://mybankstatementanalysis.com/blog/sbi-bank-statement-password) quotes SBI: "any 4 digit number of your choice which will be used to encrypt the PDF attachment"; [SBI Quick page](https://sbi.co.in/portal/web/services/sbi-quick-missed-call-banking) describes the service |
| **OnlineSBI** download | the **account number** (11 digits; try again without leading zeros) | `31234567890` | [Univik](https://univik.com/blog/sbi-bank-statement-password.html), [mybankstatementanalysis](https://mybankstatementanalysis.com/blog/sbi-bank-statement-password); an open-source parser hints "usually your account number + date of birth, DDMMYY" ([source](https://github.com/harshsingh-io/indian-bank-statement-parser/blob/main/indian_bank_statements/pdf.py)) |
| OnlineSBI XLS | none (it is TSV text) | — | [gnucash README](https://github.com/abhijit86k/gnucash_statement_preprocessors) |
| **New web / YONO XLSX** (2025–26) | `NNNNNDDMMYY` = last 5 digits of the mobile + DOB | `98765150890` | [gnucash README](https://github.com/abhijit86k/gnucash_statement_preprocessors) (the README contradicts itself on DDMM vs MMDD; the script assumes the bank's file opens) |
| **YONO app** PDF | DOB `DDMMYYYY` (most sources). Variants reported: `DDMM@<last 4 of mobile>`, first 5 letters of name + `DDMMYYYY` | `15081990` | [Univik](https://univik.com/blog/sbi-bank-statement-password.html), [mybankstatementanalysis](https://mybankstatementanalysis.com/blog/sbi-bank-statement-password), [ClearTax snippet](https://cleartax.in/s/sbi-statement-password) |
| SBI **Card** statement (different issuer, not in scope) | first 4 letters of name, lowercase + DOB `DDMM` | `rahu1508` | [Adobe](https://www.adobe.com/in/acrobat/roc/blog/credit-card-statement-password-guide.html), [Bajaj Finserv](https://www.bajajfinservmarkets.in/discover/managing-credit-cards-e-statements) |

**Product rules:**

1. The password field is the only required input. Under it, a collapsed "How do I find it?" lists the formulas for the channel the user says the PDF came from, using the example above. The covering email or SMS usually states the rule, so tell the user to look there first ([Univik](https://univik.com/blog/sbi-bank-statement-password.html)).
2. **Optional assisted unlock.** If the user enters DOB, mobile last-5 and account number, try at most these candidates in order: `last5+DDMMYY`, `DDMMYYYY`, the account number, the account number without leading zeros. Hold them in memory only, for that single attempt, and **never write them to disk, preferences or logs**. All attempts are local. Opening a PDF is a key derivation (MD5 × 50 rounds for R3) taking well under a millisecond, so trying candidates offline costs nothing.
3. Never put the password in an exception message or log. **Syncfusion embeds the wrong password in its exception**: `ArgumentError.value(password, 'password', 'Cannot open an encrypted document. The password is invalid.')` (`pdf_document.dart:1523`), so `e.toString()` prints the password. pdfrx's `PdfPasswordException` does not include it.
4. The statement password cannot be changed by the user, because it is derived from DOB and mobile ([indian-bank-statement-parser README](https://github.com/harshsingh-io/indian-bank-statement-parser): "derived, not issued … cannot be rotated once it leaks"). That is one more reason never to store it.

---

## 3. Narration vocabulary → `StatementKind`

The app's kinds are already defined in `lib/domain/statement.dart`: `spend`, `toPerson`, `fromPerson`, `selfTransfer`, `cardBill`, `investment`, `redemption`, `loan`, `cash`, `salary`, `interest`, `refund`, `cashback`, `charges`, `otherCredit`, `otherDebit`.

**How to read a narration.** First normalise it: join the wrapped lines (§1.1), uppercase it, and collapse whitespace. The B/B′ prefix (`TO TRANSFER-`, `BY TRANSFER-`, `DEBIT-`, `by debit card-`) or the A line-1 code (`WDL TFR`, `DEP TFR`) gives **the channel family**. The Debit or Credit column gives **the direction**, and it always wins over a `TO`/`BY` prefix that disagrees. The body gives **the counterparty**.

Each row below says whether the string was **seen** in a real SBI document (the evidence column links to it) or is **inferred**, meaning a standard Indian banking code that we did not see in an SBI file. Write fixtures for seen rows first.

### 3.1 Prefix / channel codes

| Pattern (regex-ish, on normalised text) | Meaning | Seen? | Default kind |
|---|---|---|---|
| `^TO TRANSFER-` / `^TO TRANSFER$` + next line | Debit by transfer: UPI, INB, IMPS, NEFT | seen (B, B′) | decided by the body (§3.2) |
| `^BY TRANSFER-` / `^BY TRANSFER$` | Credit by transfer | seen | decided by the body |
| `^WDL TFR` (A) | "Withdrawal transfer" = debit by transfer. The next line holds the detail | seen (A) | decided by the body |
| `^DEP TFR` (A) | "Deposit transfer" = credit by transfer | seen (A) | decided by the body |
| `UPI/DR/<12-digit RRN>/<name ≤ ~10 ch>/<BANK4>/<vpa, truncated>/<note>` | UPI payment out. The RRN equals the `Refno` in SBI's UPI SMS, so it is an exact join key with the SMS ledger | seen (A, B′, C) | `spend` or `toPerson` or `cardBill`/`investment`/`selfTransfer` by payee (§3.2) |
| `UPI/CR/<RRN>/<name>/<BANK4>/<vpa>/<note>` | UPI money in | seen (A, C) | `fromPerson`, unless the payee or note says refund/cashback/self |
| `UPI/REV/…`, `REV-UPI`, `UPI…REVERSAL` | UPI reversal of a failed debit | **inferred** | `refund` (match to the original by amount within 3 days) |
| `INB IMPS/P2A/<RRN>/XXXXXXX<last4>/<BANK>/<remark>` and `IMPS/P2A/…` | IMPS out from OnlineSBI/YONO to account + IFSC ("P2A") | seen (A, B, B′) | `selfTransfer` if last4 is one of the user's own accounts or the remark says `SELF`/`OWN`; otherwise `toPerson` |
| `TO TRANSFER-INB <free text>` (e.g. `INB For expenses`, `INB Personal`, `INB Gift to relatives / Friends`) | Intra-SBI internet-banking transfer. The remark is the purpose the user typed | seen | `toPerson` (or `selfTransfer` if the Ref shows an own account) |
| `INB NEFT UTR NO: SBIN…` | NEFT out via OnlineSBI | seen (A) | `toPerson` / `selfTransfer` |
| `TO TRANSFER-INB Billpay ~ IB…` / `INB Billpay` | OnlineSBI bill pay (utilities, card, insurance) | seen | `spend` (bills) unless the biller is a card → `cardBill` |
| `BY TRANSFER-INB Reversal IMPS…` | IMPS reversal | seen | `refund` |
| `NEFT*<IFSC>*<UTR>*<REMITTER>` and A: `NEFT <UTR>` | NEFT in. **Field 2 = remitter's IFSC, field 4 = remitter name (truncated ~20 chars)** | seen (B, B′, A) | salary candidate (§4), else `fromPerson`/`otherCredit` |
| `NEFT*RBIS0GOUPEP*…*<DISTRICT> TREASU…` | NEFT from the **Reserve Bank (government account)**: state-government salary or pension paid via the district treasury | seen | strong salary/pension candidate |
| `RTGS*…`, `RTGS-…`, `BY TRANSFER-RTGS` | RTGS in or out (≥ ₹2 lakh) | inferred | as NEFT |
| `BULK POSTING-…` | Bulk credit file loaded by the bank. Seen carrying `BY SALARY`, `Salary of Mar 2024`, `REIMB 0318HRMS` (reimbursement), `ITD TAX REFUND AY 21-22`, `CR_PETROL DISCOUNT`, IMPS reversals | seen | `salary` if the text says salary; `refund` for `ITD`/`TAX REFUND`; `cashback` for `CR_…DISCOUNT`/`CASHBACK`; otherwise a salary candidate |
| `CEMTEX DEP…` | "Central Magnetic Tape Exchange" bulk deposit. Used for government salary, allowances, subsidies, scholarships, PF. A consumer-court case quotes `CEMTEX DEP BY SALARY` ([casemine](https://www.casemine.com/judgement/in/661a246c066d194da41250be)) | seen in a court record, not in our sample files | salary candidate; `otherCredit` if one-off |
| `CREDIT-ACHCr …` / `ACH CR` / `NACH CR` | NACH credit: dividend, MF redemption, subsidy, sometimes salary | inferred | `interest` if `DIV`; `redemption` if MF/AMC; else `otherCredit` |
| `DEBIT-ACHDr <UMRN/ref> <ENTITY>` / passbook print: `ACHDr CITI0000…37 BD-<AMC> MF` / `NACH0000…<entity>` | NACH mandate debit | seen | by entity: MF/AMC/`ICCL`/`BSE`/`SIP` → `investment`; `LOAN`/`FINANCE`/`EMI`/NBFC → `loan`; insurer (`LIC`, `…LIFE`, `…GIC`) → `spend` (insurance); card issuer → `cardBill`; else `otherDebit` |
| `SI-…`, `TO SI…`, `S.I.` | Standing instruction (SBI's own glossary: "SI/So/SORD = Standing Instruction") | glossary seen | RD/PPF/own → `investment`; else by payee |
| `ATM WDL-ATM CASH <id> <loc>` / A: `ATM WDL` + `ATM CASH …` | ATM cash withdrawal | seen | `cash` |
| `CASH WITHDRAWAL BY CHQ`, `CASH CHEQUE-CASH`, `CHEQUE WDL--<chq>` | Cash over the counter by cheque | seen | `cash` |
| `CASH DEPOSIT-…`, `CASH DEPOSIT SELF`, `CSH DEP`, `CDM` | Cash deposited (branch / cash-deposit machine) | seen (`CASH DEPOSIT SELF`) | `selfTransfer` (own cash moving into the bank: not income) |
| `by debit card-OTHPG <ref><MERCHANT>` | Online debit-card payment through **another bank's payment gateway** ("OTH" + "PG") | seen | `spend`; the merchant is the text after the 12-digit ref |
| `by debit card-SBIPG <ref><MERCHANT>` | Online debit-card payment through **SBI's gateway** | seen | `spend` |
| `by debit card-OTHPOS<ref><MERCHANT>` / `SBIPOS<ref><MERCHANT>` | Debit-card swipe at a POS terminal of another bank / of SBI | seen | `spend` |
| A: `POS ATM PURCH` | Debit-card purchase (POS or online) | seen | `spend` |
| `BY CLEARING`, `TO CLEARING-Chq No. <n>`, `CLG` | Cheque cleared in / out | seen | out: `toPerson` (or `cardBill` if the payee is a card, e.g. `TO CLEARING-HDF…`); in: `fromPerson` |
| `CHQ TRFR FROM`, `CAS CHQ XFER WD`/`CHEQUE TRANSFER TO <acct> OF Mr. X` | Cheque transfer between SBI accounts | seen (A) | `fromPerson` / `toPerson` |
| `CREDIT INTEREST--` (B) / `INTEREST CREDIT` (A) | Savings-account interest | seen | `interest`. Several savings files show it around the **25th of Mar/Jun/Sep/Dec**. FD/MOD-linked interest posts on other dates, so **do not classify by date** |
| `DEBIT INTEREST`, `TAX DEDUCTION`, `TAX ON PREVIOUS INT-` | TDS on deposit interest | seen | `charges` (tax) |
| `TRANSFER CREDIT-SWEEP FROM`, `SWEEP TRF CREDT`, `DEBIT SWEEP`/`SWEEP TO` | MOD (Multi Option Deposit) auto-sweep between savings and a linked FD | seen | debit → `investment`, credit → `redemption` (both outside spend and income) |
| `TO TRANSFER-Renewal` | FD renewal | seen | `investment` |
| `ATM ANNUAL CHARGES`, `PROCESSING FEES`, `FEE DEBIT`; also `SMS CHGS`, `SMS CHARGES`, `DEBIT CARD ANNUAL FEE`, `ANNUAL MAINT`, `AMC`, `MIN BAL CHGS`, `NON MAINT`, `CHGS`, `CHARGES`, `GST` | Bank fees and the GST on them | first three **seen**; the rest **inferred** | `charges`. Match on the keyword set, not on exact strings |
| `CR RT CHG <rate>` (e.g. `CR RT CHG 7.100 -`) | **Credit-rate change**: an informational row recording a new interest rate. It has no amount | seen | **not a transaction**: skip it. It must not trip the "row without an amount" check |

### 3.2 Body → counterparty → kind (for UPI/IMPS/NEFT/INB)

Take the counterparty in this order: the UPI name field, then the VPA, then the NEFT remitter, then the INB remark. Then:

| Test (first match wins) | Kind |
|---|---|
| Counterparty name ≈ account holder's name (token overlap ≥ 2 tokens, or initials + surname), **or** the account last4 is a known own account, **or** the remark is `SELF`/`OWN`/`TRANSFER TO SELF` | `selfTransfer` |
| **Card bill**: `CRED` (VPA `cred.club@…`), `CHEQ`, `SBICARD`/`SBI CARD`, `SBI CREDIT CARD`, `CREDIT CARD`, `CC PAYMENT`, `CCPAY`, `BILLDESK` + an issuer word, `AMEX`/`AMERICAN EXPRESS`, `HDFC CREDIT`, `ICICI CREDIT`, `AXIS CREDIT`, `ONECARD`, `SCAPIA`, `UNI CARDS`, `SLICE` | `cardBill` |
| **Cross-check with the SMS ledger** (decisive when available): a card-side SMS "payment of ₹X received" for the same amount within ±3 days | `cardBill`, whatever the narration says |
| `ZERODHA`, `GROWW`, `UPSTOX`, `ICCL`, `BSE`, `NSE CLEARING`, `MUTUAL FUND`, `MF`, `AMC`, `KUVERA`, `PPF`, `NPS`, `SIP`, `INDIAN CLEARING`, `ANGEL ONE` | `investment` (debit) / `redemption` (credit) |
| `PAYTM WALLET`, `AMAZON PAY` load, `PHONEPE WALLET`, `MOBIKWIK` with `ADD MONEY`/`WALLET` | `selfTransfer` (wallet load; matches `TransferReason.walletLoad` in the SMS ledger) |
| Note or name contains `REFUND`, `REVERSAL`, `REV`, `RETURN`, `CHARGEBACK` | `refund` |
| `CASHBACK`, `REWARD`, `GPAY REWARDS`, `CR_` prefix | `cashback` |
| **Merchant vs person** for UPI: a merchant if the VPA has a merchant handle or pattern (`.stor`, `@ybl` with a `Q`-prefixed numeric id, `@paytm` + `pay`, `razorpay`, `bharatpe`, `@hdfcbank`/`@icici`/`@axisbank` with a corporate local part, `billdesk`, `payu`, `cashfree`), or the name has a company token (`PVT`, `LTD`, `LLP`, `INDIA`, `TECHNOLOGIES`, `STORE`, `MART`, `ENTERPRISES`, `TRADERS`, `MEDICAL`, `FUEL`); a person if it is 1–3 alphabetic tokens and the VPA is a personal handle (`@oksbi`, `@okhdfcbank`, `@okicici`, `@okaxis`, `@ibl`, phone-number local part) | merchant → `spend`; person → `toPerson` / `fromPerson` |
| Otherwise | debit → `otherDebit`; credit → `otherCredit` (never income) |

Re-use the code that exists: the SMS side already has VPA-handle tables and `TransferReason` logic (`docs/research/01-sms-corpus.md` §UPI handles; `lib/services/sms/transaction_extractor.dart`). The statement classifier should call the same merchant-signature and learned-rule code (`MerchantSignature`, `merchant_learning`). That way a category the user sets in the SMS inbox also applies to statement rows, and the reverse.

### 3.3 Joining statement rows with SMS rows

Statement rows and SMS rows describe the same money, so the import must dedupe them; that is priority P2 (never double count). Join keys, strongest first:

1. **UPI RRN**: the 12 digits in `UPI/DR/<RRN>/` equal the `Refno`/`Ref No` in SBI's UPI debit SMS.
2. **IMPS RRN** in `IMPS/P2A/<RRN>`; **NEFT UTR** (`N2442600…`, `SBIN4…`).
3. Otherwise: same direction, same amount in paise, |date difference| ≤ 2 days, account last4 matches. Merge only if exactly one candidate matches; if several match, keep both and flag the pair for review.

The statement row wins on date and amount, because it is the bank's ledger. The SMS row wins on merchant name when the statement text is truncated.

---

## 4. Salary detection without the word "salary"

### 4.1 What salary looks like in SBI statements

Seen in real SBI files:

- `BY TRANSFER-NEFT*<employer bank IFSC>*<UTR>*<EMPLOYER NAME (truncated)>--`: a private employer paying by NEFT. Shape confirmed by the B-format NEFT rows; the employer-name example is the one in `salary_cycles.dart`: `BY TRANSFER-NEFT*HDFC0000001*N2930…*DELOITTE C`.
- `BY TRANSFER-NEFT*RBIS0GOUPEP*RBI0032…*<DISTRICT> TREASU`: state government pay or pension via the RBI and the district treasury, credited on the 1st–2nd ([source](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document17052286160.pdf)).
- `BULK POSTING-BY SALARY-` (25 Jul 2018, ₹98,364.40) and `BULK POSTING-` / `CTD7441xxxxxxxxxSalary of` / `August 2018-`, which wraps over three lines and puts the salary month after a reference with no space ([source](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document16379959663.pdf)). Also `BULK POSTING-Salary of Mar 2024-` ([source](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document17143659241.pdf)). This is a bulk salary file from an employer that banks with SBI. It is often an intra-SBI credit, so no IFSC appears. **Match `SALARY` on `descJoined` without word boundaries** (`…100Salary of` has no boundary before `Salary`).
- `CEMTEX DEP BY SALARY`: the same, through the CEMTEX bulk channel ([casemine](https://www.casemine.com/judgement/in/661a246c066d194da41250be)). The bank itself told the court the narration covers "multiple credits/debits", so **CEMTEX alone does not mean salary**.
- `BULK POSTING-… REIMB 0318HRMS`: an HR-system reimbursement from the same employer. **Same payer, not salary.** It must not anchor a new cycle (§4.3).

Not salary, but these look like it: `BULK POSTING-… ITD TAX REFUND` (income-tax refund), `CR_PETROL DISCOUNT` (cashback), `TRANSFER CREDIT-SWEEP FROM` (own FD), `NEFT` from the user's own account at another bank (self), and a large `UPI/CR` from a parent or spouse (a person).

### 4.2 Algorithm

This builds on `SalaryDetector._recurrenceScore`, which already checks ≥ 2 distinct months, 24–38-day gaps and ±25 % of the median.

1. **Candidates.** Credits ≥ ₹5,000 (`minimumPaise`), with kind ∈ {`salary`, `otherCredit`, `fromPerson`} *and* channel ∈ {NEFT, RTGS, BULK POSTING, CEMTEX, ACH CR, intra-SBI `BY TRANSFER-INB`, IMPS}. **Exclude**: `selfTransfer`, `refund`, `cashback`, `interest`, `redemption`, cash deposits, and UPI/CR from a personal VPA. **UPI is never a salary channel in practice.** Allow it only through a user override.
2. **Payer key.** For NEFT/RTGS use the normalised remitter field (field 4 of `NEFT*…*…*NAME`; drop `PVT`, `LTD`, `LIMITED`, punctuation, and the truncated last token), plus the IFSC bank code (the first 4 letters of field 2). For BULK POSTING/CEMTEX use the first token after the code if there is one, otherwise the literal `BULK`/`CEMTEX` (one SBI-side employer per account is the common case). **Never** key on the UTR or ref; it differs every month. Today's code keys on `MerchantSignature.of(row.counterparty)`. Make sure `counterparty` is filled from the remitter field and not from the whole narration.
3. **Score each payer stream** (the existing months × cadence × steadiness), then add:
   - **+1** if the channel is NEFT/RTGS/BULK/CEMTEX/ACH CR (bulk and payroll channels; Plaid's income model also treats the channel as a feature: [engineering blog](https://engineering.plaid.com/how-we-use-machine-learning-to-power-accurate-real-time-income-verification-404c64fd75b6)).
   - **+1** if the day of month is stable: all credits fall within a ±5-day window (circular, so 30th–2nd is one window). Weekend or holiday shifts move pay by 1–3 days.
   - **+0.5** if the median is the largest of all credit streams.
   - **Accept** at score ≥ 2 **and** ≥ 2 occurrences. With exactly 2, show the verdict as "looks like salary — confirm?". Plaid treats a recurring stream as mature after **3** occurrences ([Plaid](https://plaid.com/blog/recurring-transactions/)); with only 2 we ask the user rather than assert.
4. **The keyword path still wins**: `SALARY|SAL\b|SAL[ /-]|PAYROLL|WAGES|STIPEND|PENSION` → salary on its own (already `SalaryDetector.mentionsSalary`; **add `PENSION`**, since the treasury rows are often pension). **Bug in the current regex:** `\b(salary|…)` does **not** match `CTD74413970014100Salary of`, because a digit followed by a letter is not a word boundary. Match `SALARY` with no leading `\b` on the joined, uppercased narration. Keep the boundary only for the short `SAL` form (preceded by a non-letter: `(?<![A-Z])SAL(?![A-Z])`). A keyword match with an amount < 30 % of the stream median is **arrears or reimbursement**: it counts as salary-type income but does not open a new cycle.
5. **User overrides win** (`isSalaryOverride`), as today.

### 4.3 Edge cases

| Case | Rule |
|---|---|
| **Bonus month** (one credit 1.3–3× the median) | Still salary: it belongs to the same payer and arrives in the usual window. Keep it **out of the median** (use the median, never the mean) and show "includes ₹X above usual". |
| **Separate bonus/arrears credit** from the same payer within 10 days of a salary | Same cycle; it does **not** anchor a new one (the existing code skips gaps under 10 days; keep that). Label it "Extra from <payer>". |
| **Joining mid-month** (first credit 30–90 % of the later median) | Accept it as salary if the next two are steady. The first cycle is `isPartial` (already modelled). |
| **Salary paid early** (e.g. 28 Feb for March) | A cycle is "salary date → day before next salary", not a calendar month, so early pay just makes one cycle shorter and the next longer. Name the cycle by the month in which the *majority* of its days fall. |
| **Two salaries at once** (two employers, or salary + pension) | Up to two streams may each pass the test. Anchor cycles on the **larger** stream; the second stream's credits count as income inside those cycles. |
| **Job change** (stream A stops, stream B starts within 45 days, B's median within ±40 % of A's) | Treat as one continuous salary series for cycles. Show "Salary source changed: A → B". |
| **Missing month** (no salary for 40–70 days) | Do not invent a boundary. That cycle is simply long, flagged "No salary found between X and Y". |
| **Salary to another bank** | No salary here. `SalaryVerdict.none` already says so honestly. Offer "mark a credit as salary" (the owner's inbox has **no salary SMS**: CLAUDE.md, open todo). |
| **Reversal of a salary** (`…REV…` same amount, same payer within 5 days) | Net to zero. Neither row counts. |

**Prior art** (none of it can be used as-is, but each one confirms the approach):

- Plaid's recurring-transactions endpoint: streams grouped by description, amount and cadence; mature at 3 occurrences; frequencies weekly, biweekly, semi-monthly and monthly ([blog](https://plaid.com/blog/recurring-transactions/)).
- Plaid's income pipeline: filter out non-income, cluster into source streams, detect frequency, score, categorise ([engineering](https://engineering.plaid.com/how-we-use-machine-learning-to-power-accurate-real-time-income-verification-404c64fd75b6)).
- Patent US8380590B1, "Method and system for detecting recurring income from financial transaction data" ([Google Patents](https://patents.google.com/patent/US8380590)).
- Open-source projects: [recur-scan](https://github.com/EbenezerOladipupoBankole/recur-scan) (Apache-2.0, a recurring/non-recurring classifier) and [SalaryLens](https://github.com/altafpasha/SalaryLens) (rules plus an LLM; not usable offline).
- Indian open-source parsers detect salary **only by keyword**, e.g. `"salary" in narration` plus a start/end-of-month window ([Banking-Statement-Analyzer](https://github.com/Shivapande25/Banking-Statement-Analyzer/blob/main/SBI_bank_statement_parcer.py)), or `'SALARY' in desc or 'SAL' in desc` ([atul0016](https://github.com/atul0016/bank-statement-parser/blob/main/parsers/sbi_bank.py)). Both miss `NEFT*…*DELOITTE C`, which is why the behaviour path above matters.

### 4.4 What a cycle reports

This extends `SalaryCycle`. **Spent** = `spend` + `toPerson` + `charges` + `otherDebit` − `refund`, where refunds net against spend in the same cycle (`StatementKind.isSpend` already includes `toPerson`; keep it, because rent is usually a UPI to a person). **Not spent, shown separately**: `cardBill`, which points at the Cards tab, where the purchases were counted from the card side; `selfTransfer`, `investment` and `cash` (cash is "withdrawn", not "spent", following the SMS ledger's `TxnKind.cash`). **Money in**: salary, then interest, `fromPerson` and `otherCredit`, each with its own label. Nothing that is not salary is ever called "income".

---

## 5. Libraries: open an encrypted PDF and get positioned text, offline, on Android

### 5.1 Comparison

| Option | Latest (today) | Works on our toolchain? | Password / encryption | Text with coordinates | APK cost (arm64) | Licence | Maintenance |
|---|---|---|---|---|---|---|---|
| **pdfrx** (PDFium via FFI) | 2.10.1 (2026-10-23) — **2.4.8 (2026-08-26) is the newest that resolves** | 2.4.8: `sdk ^3.10`, `flutter >=3.41.0` ✅. 2.5.0+: `flutter >=3.47.0` ❌ | `passwordProvider`; PDFium security handler: RC4 key 5–16 bytes (V1/V2, R2–R4), AES-128/256 via `AESV2`/`AESV3` (V4/V5, R5/R6) ([source](https://pdfium.googlesource.com/pdfium/+/refs/heads/main/core/fpdfapi/parser/cpdf_security_handler.cpp)). Wrong or no password → `PdfPasswordException` | `PdfPage.loadText()` → `PdfPageRawText(fullText, charRects)`, one `PdfRect` per char in PDF points (origin bottom-left). `loadStructuredText()` adds fragments | `libpdfium.so` from `bblanchon/pdfium-binaries` `chromium/7811`: **arm64 tgz 3.31 MB**; armv7 2.77, x86_64 3.42, x86 3.23 ([release](https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium%2F7811)). Fat debug APK ≈ +12.7 MB | MIT (PDFium: BSD-3) | very active: 14 releases in October 2026 |
| **syncfusion_flutter_pdf** (pure Dart) | 35.1.41 (2026-10-20) | `sdk ^3.7`, `flutter >=3.35.1` ✅ | `PdfDocument(inputBytes:, password:)`; RC4-40/128, AES-128/256, AES-256 R6 ([pub](https://pub.dev/packages/syncfusion_flutter_pdf)). Wrong password → `ArgumentError` **containing the password** | `PdfTextExtractor(doc).extractTextLines()` → `TextLine{bounds: Rect, wordCollection: [TextWord{bounds,text}]}` (top-left origin) | Dart AOT only; `lib/` is 4.9 MB of source. Estimate +2–4 MB AOT (**not measured**) | **Commercial or Community licence**: "gross revenue of less than one (1) million U.S. dollars … and less than five (5) developers", and "Under no circumstances can you use this product without (1) either a Community License or a commercial license" ([LICENSE](https://pub.dev/packages/syncfusion_flutter_pdf/license)). You must claim a free community licence on syncfusion.com. **No runtime key**: "license key registration is no longer required for Syncfusion Flutter from version 18.3.0.x … No license warnings will be displayed" ([Syncfusion forum](https://www.syncfusion.com/forums/169276/how-to-apply-community-license-on-a-flutter-project)). No watermark is reported for *reading* | weekly releases |
| **Android `PdfRenderer`** (platform) | API 35: `PdfRenderer(fd, LoadParams)` with password; `Page.getTextContents()`. `PdfRendererPreV` back-ports to API 30–34 ([guide](https://developer.android.com/media/grow/pdf-viewer)) | needs a Kotlin channel; works only on devices with API 35, or the SDK extension for PreV | password ✅ (wrong → `SecurityException`); algorithm list unspecified (PDFium inside the platform) | text plus **coarse** bounds per content block, granularity **not verified** | 0 MB | AOSP | platform |
| **PDFBox-Android** `com.tom-roush:pdfbox-android` via a platform channel | **2.0.27.0 (2023-01-02)**: no release in 3¾ years ([Maven](https://search.maven.org/artifact/com.tom-roush/pdfbox-android)) | needs Kotlin + a channel | full Standard security handler: RC4-40/128, AES-128/256 (PDFBox 2.0 core) | `PDFTextStripper.writeString(text, List<TextPosition>)` → `xDirAdj`, `yDirAdj` per glyph | AAR **3.25 MB** + BouncyCastle 1.72 (`bcprov`, `bcpkix`, `bcutil`; several MB before R8) | Apache-2.0 | stale |
| **flutter_pdf_text** | 0.9.0 (2025-02-13) | ✅ | password ✅ (via PDFBox-Android 2.0.27.0) | **plain text only**, no positions | as PDFBox | MIT | slow |
| **read_pdf_text** | 0.3.1 (2025-04-27) | ✅ | **no password parameter** | plain text only | as PDFBox | MIT | slow |
| **pdf_text** | 0.5.0 (2021-03-14) | ❌ `sdk <3.0.0` | — | — | — | MIT | abandoned |
| **pdfium_bindings** | 3.2.0 (2026-01-08) | ✅ (pure FFI) | whatever PDFium does, but you write the FFI calls and **ship `libpdfium.so` yourself** | yes, via raw `FPDFText_*` | as pdfrx | MIT | pdfrx already does this work |

### 5.2 Recommendation: pdfrx 2.4.8

Why pdfrx:

- It is the only option that combines **char-level coordinates**, **every encryption the owner's file could use**, an **MIT licence**, active maintenance, and no Kotlin to write.
- Syncfusion has all the capabilities but a licence with conditions (revenue and team size, attested by the developer) and the password-leaking exception. Keep it as the documented fallback if §5.4 fails.
- PdfRenderer would cost 0 MB, but its bounds granularity is unverified and it needs a channel plus API-level gating.
- PDFBox has not had a release since January 2023 and is heavier.

```yaml
# pubspec.yaml
dependencies:
  pdfrx: 2.4.8          # exact pin: 2.5.0+ requires Flutter >= 3.47 (we are on 3.41.9)
  file_picker: ^13.2.0
```

```xml
<!-- android/app/src/main/AndroidManifest.xml: make "no network" an OS-level guarantee
     even if a plugin's manifest tries to merge INTERNET in. pdfrx_engine depends on
     package:http (for PdfDocument.openUri), which we never call. -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
          xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.INTERNET" tools:node="remove"/>
```

(Add the `tools:node="remove"` line to the **main** manifest only. The debug and profile manifests need `INTERNET` for hot reload. That merges correctly, because build-type manifests have higher priority than main. Check `build/app/intermediates/merged_manifests/release/.../AndroidManifest.xml` after the first release build.)

```dart
// lib/services/statement/pdf_words.dart (sketch: 20 lines that matter)
import 'package:pdfrx/pdfrx.dart';

class PdfWord { const PdfWord(this.page, this.x0, this.x1, this.top, this.text);
  final int page; final double x0, x1, top; final String text; }       // top: points from page top
sealed class PdfOpenError implements Exception { const PdfOpenError(); }
class NeedsPassword extends PdfOpenError { const NeedsPassword(); }
class WrongPassword extends PdfOpenError { const WrongPassword(); }

Future<List<PdfWord>> readWords(String path, {String? password}) async {
  await pdfrxFlutterInitialize();                              // idempotent; bundled PDFium, no network
  final PdfDocument doc;
  try {   // tries the empty password first, then `password` once, then throws
    doc = await PdfDocument.openFile(path, passwordProvider: createSimplePasswordProvider(password));
  } on PdfPasswordException {
    throw password == null ? const NeedsPassword() : const WrongPassword();
  }
  try {
    final words = <PdfWord>[];
    for (final page in doc.pages) {
      final raw = await page.loadText();                        // chars + one PdfRect per char
      if (raw == null) continue;
      var buf = StringBuffer(); PdfRect? box;
      void flush() { if (box != null) words.add(PdfWord(page.pageNumber, box!.left, box!.right, page.height - box!.top, '$buf')); buf = StringBuffer(); box = null; }
      for (var i = 0; i < raw.fullText.length && i < raw.charRects.length; i++) {
        final c = raw.fullText[i], r = raw.charRects[i];
        if (c.trim().isEmpty || r.isEmpty) { flush(); continue; }   // spaces / CR-LF end a word
        final gap = box == null ? 0 : r.left - box!.right;
        if (box != null && (gap > r.height * 0.5 || (r.bottom - box!.bottom).abs() > r.height * 0.5)) flush();
        box = box?.merge(r) ?? r; buf.write(c);
      }
      flush();
    }
    return words;
  } finally { await doc.dispose(); }
}
```

Behaviour verified in `pdfrx_engine-0.4.7/lib/src/native/pdfrx_pdfium.dart`:

- `_openByFunc` first tries an empty password when `firstAttemptByEmptyPassword` is true. If PDFium returns `FPDF_ERR_PASSWORD`, it calls the provider. `createSimplePasswordProvider` returns the password once and then `null`, and a `null` makes the loop throw `PdfPasswordException('No password supplied by PasswordProvider.')`.
- So: an encrypted file opened without a password and a wrong password raise **the same exception**. We tell them apart by whether we passed a password, as the sketch does.
- A corrupt file raises `PdfException` (not the password subclass). Show "This file is not a readable PDF".
- On Windows, pdfrx treats every open error as a password error (a `FIXME` in the source). That does not matter on Android, but host-side `flutter test` runs on Windows here, so **unit tests should not depend on the PDF layer**. Test the pure table builder on word-list fixtures (§8).
- `loadText()` writes `FPDFText_GetUnicode` with `writeCharCode`. A character outside the BMP would shift `fullText` against `charRects`. SBI statements are ASCII, so the `i < charRects.length` guard is enough, but log a warning if the lengths differ.

### 5.3 APK size

- Debug builds carry all four ABIs, about **+12.7 MB**.
- For release, use `flutter build apk --split-per-abi` or `ndk { abiFilters += listOf("arm64-v8a") }`, which brings it to about **+3.3 MB** for the S24's arm64. The rest of pdfrx (viewer widgets, `rxdart`, `url_launcher`) is tree-shaken if we only import the engine API.
- Measure before and after with `flutter build apk --analyze-size --target-platform android-arm64`.

### 5.4 Native-assets risk (do this first)

PDFium arrives through Dart **build hooks**: `pdfium_dart-0.2.5/hook/build.dart` downloads `pdfium-android-<arch>.tgz` from GitHub **at build time** and caches it. The app still makes no network calls at runtime; only the build does. However, `CLAUDE.md` records that an "FFI native-assets build hung" on this machine (in the v7→v8 migration test).

- **Day-1 check:** add the dependency and run `flutter build apk --debug`. If the hook stalls, pre-seed the cache from the four tgz files, or switch to Syncfusion.
- **Do not upgrade the toolchain just for pdfrx 2.10.** The 2.5–2.10 changes are viewer and font features we do not use.

---

## 6. Picking the file on Android 14/15

**`file_picker: ^13.2.0`** (13.2.0, 2026-10-24; 13.0.0 shipped 2026-09-14; `flutter >=3.38` ✅). Its Android implementation (`android_file_picker 2.1.2`):

- Launches **`Intent.ACTION_OPEN_DOCUMENT`** for non-media types (`FileUtils.kt:224`). That is the Storage Access Framework, which grants per-URI read access and **requires no storage permission** on any API level ([Android docs](https://developer.android.com/training/data-storage/shared/documents-files)). Nothing to add to the manifest; the plugin only declares `<queries>` for the intents.
- Copies the picked document to `context.cacheDir/file_picker/<timestamp>/<name>` and returns a `file://` path (`FileUtils.kt:670–708`). That path works directly with `PdfDocument.openFile`.
- The v12/v13 API: `FilePicker.pickFile(...)` returns `PlatformFile?` (null on cancel). `withData` was removed; read bytes with `file.xFile.readAsBytes()` if `path` is ever null, and open them with `PdfDocument.openData(bytes, passwordProvider: …)`.

```dart
final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
if (f == null) return;                       // user cancelled
try {
  final words = await readWords(f.path!, password: typedPassword);
  // … build table, verify, show review screen …
} finally {
  await FilePicker.clearTemporaryFiles();    // the cached copy is the user's bank statement
}
```

The alternative is a hand-rolled `ACTION_OPEN_DOCUMENT` plus a `ContentResolver` stream over a method channel: about 60 lines of Kotlin, the same permissions, no dependency. Not worth it while file_picker works. Also worth adding later: an **"Open with / Share → Finance"** intent filter for `application/pdf`. Most users will have the statement as a Gmail attachment, and sharing it straight from Gmail skips the picker.

---

## 7. Rebuilding the table and proving it

### 7.1 Pipeline

```
words (page, x0, x1, top, text)
  → lines: per page, cluster words by `top` within 0.5 × median glyph height (≈ 3–4 pt);
           sort each line by x0
  → drop furniture: lines matching §1.2, above the header, below a terminator
  → header: find the line(s) with {date label} ∧ {description label} ∧ ≥2 of {Debit, Credit, Balance}
  → column model per page (fallback: the previous page's model)
  → rows: a new row starts at a line whose date-band word parses as a date;
          other lines are continuations
  → cells: amounts by right edge, text by band
  → parse: dates, amounts (paise), balance sign
  → verify: running balance, order, summary totals
  → classify (§3) → salary (§4) → cycles
```

### 7.2 Header → column model

- **Labels** (case-insensitive, after removing `₹`, `.` and `/`): date = `txn date` | `post date` | `date` (`date (value date)` counts as date); value date = `value date` | `value dt` | `value` + `date` on the next line; description = `description` | `details` | `narration` | `particulars`; ref = `ref no` | `cheque` | `chq` | `ref/cheque`; debit = `debit` | `withdrawal` | `dr`; credit = `credit` | `deposit` | `cr`; balance = `balance` | `closing balance`.
- **Two-line headers**: B prints `Txn Date Value` / `Date` and `Ref No./Cheque` / `No.`, so merge header fragments within 1.5 line-heights.
- **Text columns** (date, value date, description, ref) take the half-open band `[header.x0 − 2, nextHeader.x0 − 2)`.
- **Amount columns** (debit, credit, balance) store `anchor = header.x1`. A numeric token belongs to the amount column whose `anchor` is nearest its `x1`, within **max(15 pt, 0.6 × column gap)**. Beyond that it is narration text: the `EXAMPL1,250.00PRIVATE` case cannot happen with positions, but numbers inside narrations (`RBI0032…`) still have to stay text.
- **Headerless pages**: kharchalens notes some SBI e-statements have continuation pages with no header row. Reuse the last model. If the first page has none either, use the geometric fallback: two date x-clusters on the left, then three right-aligned numeric x-clusters (debit < credit < balance) ([kharchalens `_geometric_columns`](https://github.com/aakraj/kharchalens/blob/main/kharchalens/parser/sbi_pdf.py)).

### 7.3 Dates

Accept, in this order:

- `^\d{1,2} [A-Z][a-z]{2} \d{4}$`
- `^\d{1,2} [A-Z][a-z]{2}$`, **with the year taken from a bare `^\d{4}$` in the date band on the next one or two lines**, or else carried from the previous row (B prints `25 Jun` / `2023`; atul0016's parser carries `last_year` across pages for the same reason)
- `^\d{2}/\d{2}/\d{2}$` (A) and `^\d{2}/\d{2}/\d{4}$` (C)
- `^\d{2}-[A-Z][a-z]{2}-\d{2}$` (B′), with the `(dd-Mon-yyyy)` on the next line as the value date

Use the **Txn/Post date** for cycles; keep the value date for display. Two-digit years: `yy < 70 → 20yy`. Validate that every date falls inside the declared statement period ±3 days. A date outside it means a misread row.

### 7.4 Amounts → paise

`^-?[\d,]+\.\d{2}(Cr|CR|Dr|DR)?$` → remove commas and the suffix, then do integer arithmetic on the string (`"1,12,450.00"` → `11245000`). **Never parse money as `double`** (CLAUDE.md: money is integer paise).

- `-`, an empty cell, or a single space → 0.
- A balance suffix `Dr` or a leading `-` → negative (overdraft or loan).
- Indian grouping (`1,00,000.00`) and plain (`100000.00`) both appear, sometimes in the same file (A rows vs A carried-forward), so **ignore comma positions**.
- A Debit/Credit cell holding `0.00` counts as empty.

### 7.5 Multi-line descriptions

A row runs from its date line to the line before the next date line, or to a terminator.

- Continuation lines contribute text **only from the description and ref bands**.
- A continuation line that carries an amount in the balance band (B′'s drifting balances) attaches that amount to the row if the row has none; otherwise it is suspect, and §7.6 decides.
- Build `descSpaced` (lines joined with a space) and `descJoined` (lines joined directly). SBI wraps at a fixed width and splits words (`SBI C`/`REDIT CARD`, `TREA`/`SU`, `swiggy.stor`/`…`). Match keywords on `descJoined.replaceAll(' ', '')`. Show `descSpaced` to the user.
- In layout A, the line-1 code (`WDL TFR`) and line 2 (`UPI/DR/…`) are both needed. Do not drop line 1. Drop the `AT 70155 <BRANCH>` trailer, which is the posting branch, not a counterparty.

### 7.6 Arithmetic: the check that makes it trustworthy

Integer paise throughout: `bal[i] == bal[i−1] − debit[i] + credit[i]`, with `bal[−1]` = the opening balance (`Balance as on` / `BROUGHT FORWARD` / `Opening Balance`).

| Situation | Action |
|---|---|
| Holds | `balanceVerified = true` (the field already exists on `StatementRow`). |
| Fails, but holds with debit and credit swapped | Swap them, count it as "direction corrected by balance". harsh's parser needed this on a real SBI file ([README](https://github.com/harshsingh-io/indian-bank-statement-parser)). |
| Row has an amount but no balance (B′ drift) | Derive the balance; mark the row "derived". The next printed balance must then reconcile. |
| Fails only in reverse order | The file is newest-first (pf_dashboard case 2). Reverse all rows and re-check. |
| `CARRIED FORWARD`/`BROUGHT FORWARD` balance on a page boundary | Must equal the running balance at that point. This is a free checkpoint per page. |
| Summary line present (`Dr. Count n  Cr. Count m  ΣDr ΣCr`, or YONO `Statement Summary`) | Counts and totals must match. A count mismatch means a row was dropped or split. |
| Still fails | The statement is **not imported silently**. Show "k of N rows didn't add up" with those rows, and let the user import the verified rows only, or cancel. Never "fix" a balance. |

These checks catch the known failure modes:

- A dropped row breaks the chain at that row.
- A merged row (two rows read as one) breaks the chain and the Dr/Cr count.
- A debit misread as a credit is caught by the direction swap.
- A wrapped number glued into a narration leaves a row without an amount.
- A misread year is caught by the period check.

Arithmetic **cannot** catch a wrong narration attached to a correct amount. Classification has to be reviewed for that (§8 expected outputs).

### 7.7 Identity and re-import

Use `stmt:<fnv1a64(accountLast4|txnDate|debit|credit|balance|seq)>`, where `seq` = the 0-based position among rows with the same date. Including the balance makes two identical ₹486 Swiggy orders on the same day distinct, which is correct because they are two real charges. Re-importing an overlapping statement then de-duplicates exactly. Store `sourceFile = sha256(pdf bytes)` so "already imported" can be shown before any parsing.

---

## 8. Synthetic test fixtures (fake people, fake numbers)

All three describe **the same 15 transactions** in three layouts, so one expected-output table covers all of them. Opening balance ₹42,315.60; closing ₹1,72,717.70; 10 debits totalling ₹97,158.90; 5 credits totalling ₹2,27,561.00. **Every row reconciles**; these numbers were generated and checked by a script.

Expected classification and salary cycles:

| # | Date | Debit | Credit | Expected kind | Notes |
|---|---|---:|---:|---|---|
| 1 | 01-09-2026 | | 1,12,450.00 | `salary` | NEFT from `ACME SOFTWARE PVT`; no keyword; detected by recurrence with row 15 |
| 2 | 02-09-2026 | 486.00 | | `spend` (food) | UPI to `swiggy.stor` |
| 3 | 03-09-2026 | 38,214.00 | | `cardBill` | UPI to `cred.club@axisb` |
| 4 | 05-09-2026 | 25,000.00 | | `selfTransfer` | IMPS to own HDFC `XXXXXXX9876`, remark `Self` |
| 5 | 06-09-2026 | 5,000.00 | | `cash` | ATM |
| 6 | 08-09-2026 | 2,318.40 | | `spend` (groceries) | UPI BigBasket |
| 7 | 10-09-2026 | 5,000.00 | | `investment` | NACH, ICCL mutual-fund SIP |
| 8 | 12-09-2026 | 1,499.00 | | `spend` (shopping) | debit card, OTHPG Amazon Pay |
| 9 | 14-09-2026 | | 1,499.00 | `refund` | UPI/CR, note `Refund`; nets row 8 |
| 10 | 15-09-2026 | 18,000.00 | | `toPerson` (rent) | UPI to a person, note `rent sept` |
| 11 | 18-09-2026 | | 850.00 | `fromPerson` | UPI from a person, `dinner` |
| 12 | 22-09-2026 | 342.50 | | `spend` (transport) | UPI Uber |
| 13 | 25-09-2026 | | 312.00 | `interest` | |
| 14 | 28-09-2026 | 1,299.00 | | `spend` (bills) | INB Billpay BESCOM |
| 15 | 01-10-2026 | | 1,12,450.00 | `salary` | same payer, 30 days later |

**Cycle 1 (1 Sep → 30 Sep, complete):**

- Salary ₹1,12,450.00.
- Spent ₹22,445.90: merchant spend ₹5,944.90 + rent ₹18,000.00 − refund ₹1,499.00.
- Not spending: card bill ₹38,214.00, own accounts ₹25,000.00, invested ₹5,000.00, cash ₹5,000.00.
- Other money in: interest ₹312.00, from a person ₹850.00.

**Cycle 2 (from 1 Oct)** is `isPartial`.

### 8.1 Layout A: CBS e-statement

```
STATEMENT OF ACCOUNT                                        STATE BANK OF INDIA
Name : RAHUL VERMA                                          MG ROAD BENGALURU
FLAT 12, 4TH CROSS                                          Branch Code :04321
INDIRANAGAR                                                 IFSC : SBIN0004321
BENGALURU 560038                                            MICR : 560002099
                                                            Account No.:31234567890
                                                            Product : SB-GEN-PUB-IND-NONRURAL-INR
                                                            Currency : INR
Date : 03/10/2026          Time : 09:12:44   E-mail : r*****a@example.com
Cleared Balance : 1,72,717.70Cr                    Uncleared Amount : 0.00
+MOD Bal : 0.00                                   Monthly Average Balance: 0
Statement From : 01/09/2026 to 03/10/2026          Page No. : 1
____________________________________________________________________________________________________
Post Date Value Date Details                      Chq.No        Debit      Credit        Balance
____________________________________________________________________________________________________
01/09/26  01/09/26  BROUGHT FORWARD :                                                42315.60Cr
01/09/26  01/09/26  DEP TFR                                            112450.00    154765.60Cr
                    NEFT*HDFC0001234*N2442600123
                    45678*ACME SOFTWARE PVT
                    AT 04321 MG ROAD BENGALURU
02/09/26  02/09/26  WDL TFR                                   486.00                154279.60Cr
                    UPI/DR/624512345601/
                    SWIGGY
                    AT 04321 MG ROAD BENGALURU
03/09/26  03/09/26  WDL TFR                                 38214.00                116065.60Cr
                    UPI/DR/624612345602/
                    CRED CLUB
                    AT 04321 MG ROAD BENGALURU
05/09/26  05/09/26  WDL TFR                                 25000.00                 91065.60Cr
                    INB IMPS/P2A/624812345603/
                    XXXXXXX9876 HDFC SELF
                    AT 04321 MG ROAD BENGALURU
06/09/26  06/09/26  ATM WDL                                  5000.00                 86065.60Cr
                    ATM CASH 1234 MG ROAD
                    BENGALURU
08/09/26  08/09/26  WDL TFR                                  2318.40                 83747.20Cr
                    UPI/DR/625112345604/
                    BIGBASKET
                    AT 04321 MG ROAD BENGALURU
10/09/26  10/09/26  ACHDr NACH00000000012345                 5000.00                 78747.20Cr
                    ICCL MUTUAL FUND SIP
12/09/26  12/09/26  POS ATM PURCH                            1499.00                 77248.20Cr
                    OTHPG 625512345605
                    AMAZON PAY INDIA
14/09/26  14/09/26  DEP TFR                                              1499.00     78747.20Cr
                    UPI/CR/625712345606/
                    AMAZON SELLER REFUND
                    AT 04321 MG ROAD BENGALURU
15/09/26  15/09/26  WDL TFR                                 18000.00                 60747.20Cr
                    UPI/DR/625812345607/
                    RAMESH K
                    AT 04321 MG ROAD BENGALURU
18/09/26  18/09/26  DEP TFR                                               850.00     61597.20Cr
                    UPI/CR/626112345608/
                    PRIYA S
                    AT 04321 MG ROAD BENGALURU
22/09/26  22/09/26  WDL TFR                                   342.50                 61254.70Cr
                    UPI/DR/626512345609/
                    UBER INDIA
                    AT 04321 MG ROAD BENGALURU
25/09/26  25/09/26  INTEREST CREDIT                                       312.00     61566.70Cr
28/09/26  28/09/26  WDL TFR                                  1299.00                 60267.70Cr
                    INB Billpay IB2809261234
                    BESCOM
01/10/26  01/10/26  DEP TFR                                            112450.00    172717.70Cr
                    NEFT*HDFC0001234*N2742600543
                    21987*ACME SOFTWARE PVT
                    AT 04321 MG ROAD BENGALURU
                    CARRIED FORWARD :                                             1,72,717.70Cr
____________________________________________________________________________________________________
Statement Summary
Dr. Count 10      Cr. Count 5                                97,158.90 2,27,561.00
In Case Your Account Is Operated By A Letter Of Authority/Power Of Attorney Holder, Please Check The
Transaction With Extra Care.
```

### 8.2 Layout B: OnlineSBI Account Statement PDF (year wraps; Ref wraps)

```
Account Name           :  Mr. RAHUL VERMA
Address                :  FLAT 12, 4TH CROSS
                          INDIRANAGAR, BENGALURU-560038
Date                   :  3 Oct 2026
Account Number         :  _00000031234567890
Account Description    :  REGULAR SB CHQ-INDIVIDUALS
Branch                 :  MG ROAD BENGALURU
Drawing Power          :  0.00
Interest Rate(% p.a.)  :  2.5
MOD Balance            :  0.00
CIF No.                :  _89123456789
CKYCR Number           :  XXXXXXXXXX1234
IFS Code               :  SBIN0004321
(Indian Financial System)
MICR Code              :  560002099
(Magnetic Ink Character Recognition)
Nomination Registered  :  Yes
Balance as on 1 Sep 2026 :  42,315.60

Account Statement from 1 Sep 2026 to 3 Oct 2026

Txn Date  Value     Description                   Ref No./Cheque          Debit       Credit       Balance
          Date                                    No.
1 Sep     1 Sep     BY TRANSFER-                  TRANSFER FROM 46               1,12,450.00   1,54,765.60
2026      2026      NEFT*HDFC0001234*N244260      97xxxx044302
                    012345678*ACME SOFTWARE PV
                    T--
2 Sep     2 Sep     TO TRANSFER-                  TRANSFER TO 4897       486.00                1,54,279.60
2026      2026      UPI/DR/624512345601/SWIGGY/   xxxx162092
                    YESB/swiggy.stor/UPI--
3 Sep     3 Sep     TO TRANSFER-                  TRANSFER TO 4897    38,214.00                1,16,065.60
2026      2026      UPI/DR/624612345602/CRED Clu  xxxx162092
                    b/AXIS/cred.club@axisb/payme
                    nt o--
5 Sep     5 Sep     TO TRANSFER-INB               IMPS00248123456     25,000.00                  91,065.60
2026      2026      IMPS/P2A/624812345603/XXXXX   TRANSFER TO 4897
                    XX9876/HDFC/Self--            xxxx162093
6 Sep     6 Sep     ATM WDL-ATM CASH 1234 SBI MG                       5,000.00                  86,065.60
2026      2026      ROAD BENGALURU
8 Sep     8 Sep     TO TRANSFER-                  TRANSFER TO 4897     2,318.40                  83,747.20
2026      2026      UPI/DR/625112345604/BIGBASKE  xxxx162092
                    T/ICIC/bigbasket@icici/UPI--
10 Sep    10 Sep    DEBIT-ACHDr                                        5,000.00                  78,747.20
2026      2026      NACH00000000012345 ICCL MUT
                    UAL FUND SIP--
12 Sep    12 Sep    by debit card-OTHPG 625512                         1,499.00                  77,248.20
2026      2026      345605AMAZON PAY INDIA PRI
                    bengaluru
14 Sep    14 Sep    BY TRANSFER-                  TRANSFER FROM 48                  1,499.00     78,747.20
2026      2026      UPI/CR/625712345606/AMAZON S  97xxxx162092
                    ELLER/UTIB/amazonrefund@axi
                    /Refund--
15 Sep    15 Sep    TO TRANSFER-                  TRANSFER TO 4897    18,000.00                  60,747.20
2026      2026      UPI/DR/625812345607/RAMESH K  xxxx162092
                    /SBIN/ramesh.k@oksbi/rent s
                    ept--
18 Sep    18 Sep    BY TRANSFER-                  TRANSFER FROM 48                    850.00     61,597.20
2026      2026      UPI/CR/626112345608/PRIYA S/  97xxxx162092
                    HDFC/priya.s@okhdfcbank/din
                    ner--
22 Sep    22 Sep    TO TRANSFER-                  TRANSFER TO 4897       342.50                  61,254.70
2026      2026      UPI/DR/626512345609/UBER IND  xxxx162092
                    IA/HDFC/uber.rides@hdfcban/U
                    PI--
25 Sep    25 Sep    CREDIT INTEREST--                                                 312.00     61,566.70
2026      2026
28 Sep    28 Sep    TO TRANSFER-INB Billpay ~     IB2809261234 TRA     1,299.00                  60,267.70
2026      2026      IB2809261234 BESCOM--         NSFER TO 4897xxx
                                                  x162094
1 Oct     1 Oct     BY TRANSFER-                  TRANSFER FROM 46               1,12,450.00   1,72,717.70
2026      2026      NEFT*HDFC0001234*N274260      97xxxx044302
                    054321987*ACME SOFTWARE PV
                    T--

Please do not share your ATM, Debit/Credit card number, PIN (Personal Identification Number) and OTP (One Time
Password) with anyone over mail, SMS, phone call or any other media. Bank never asks for such information.
**This is a computer generated statement and does not require a signature
```

### 8.3 Layout C: 2026 YONO / new-web export (`dd/mm/yyyy`, `-` for empty)

```
STATE BANK OF INDIA
Account Statement
Account Name     : RAHUL VERMA
Account Number   : XXXXXXX7890
IFSC Code        : SBIN0004321
Statement From   : 01/09/2026 to 03/10/2026

Date        Details                                Ref No/Cheque No         Debit      Credit     Balance
01/09/2026  NEFT*HDFC0001234*N24426001234          N244260012345678             - 1,12,450.00 1,54,765.60
            5678*ACME SOFTWARE PVT LTD
02/09/2026  UPI/DR/624512345601/SWIGGY/YESB/       624512345601            486.00           - 1,54,279.60
            swiggy.stor@ybl/UPI
03/09/2026  UPI/DR/624612345602/CRED Club/AXIS/    624612345602         38,214.00           - 1,16,065.60
            cred.club@axisb/payment on CRED
05/09/2026  IMPS/P2A/624812345603/XXXXXXX9876/     IMPS00248123456      25,000.00           -   91,065.60
            HDFC/Self
06/09/2026  ATM WDL-ATM CASH 1234 SBI MG ROAD                            5,000.00           -   86,065.60
            BENGALURU
08/09/2026  UPI/DR/625112345604/BIGBASKET/ICIC/    625112345604          2,318.40           -   83,747.20
            bigbasket@icici/UPI
10/09/2026  ACH DR NACH00000000012345 ICCL MUTUAL  NACH00000000012345    5,000.00           -   78,747.20
            FUND SIP
12/09/2026  by debit card-OTHPG 625512345605AMAZON 625512345605          1,499.00           -   77,248.20
            PAY INDIA PRI bengaluru
14/09/2026  UPI/CR/625712345606/AMAZON SELLER/     625712345606                 -    1,499.00   78,747.20
            UTIB/amazonrefund@axisbank/Refund
15/09/2026  UPI/DR/625812345607/RAMESH K/SBIN/     625812345607         18,000.00           -   60,747.20
            ramesh.k@oksbi/rent sept
18/09/2026  UPI/CR/626112345608/PRIYA S/HDFC/      626112345608                 -      850.00   61,597.20
            priya.s@okhdfcbank/dinner
22/09/2026  UPI/DR/626512345609/UBER INDIA/HDFC/   626512345609            342.50           -   61,254.70
            uber.rides@hdfcbank/UPI
25/09/2026  CREDIT INTEREST                                                     -      312.00   61,566.70
28/09/2026  INB Billpay ~ IB2809261234 BESCOM      IB2809261234          1,299.00           -   60,267.70
01/10/2026  NEFT*HDFC0001234*N27426005432          N274260054321987             - 1,12,450.00 1,72,717.70
            1987*ACME SOFTWARE PVT LTD

Statement Summary  Opening Balance 42,315.60  Debits 97,158.90 (10)  Credits 2,27,561.00 (5)  Closing Balance 1,72,717.70
********* End of Statement *********
```

**How to turn these into tests without a PDF.** Fixtures are **word lists**, not PDFs. This is the same reasoning as [indian-bank-statement-parser](https://github.com/harshsingh-io/indian-bank-statement-parser): "A fixture is a `.txt` file … the bank's column geometry with invented rows". A tiny helper turns each monospace line into `PdfWord`s with `x0 = col × 6.0`, `x1 = (col + len) × 6.0`, and `top = line × 10.0`. That converts the blocks above into the exact input `readWords` produces. The table builder, the verifier, the classifier and the salary engine are then tested in plain `flutter test`, with no PDFium, on Windows too.

Negative fixtures to add next to these:

- (a) Layout A with one debit moved into the Credit band. Expected: 1 direction correction, all rows verified.
- (b) Layout B with row 7 deleted. Expected: a chain break at row 8, plus a Dr count mismatch.
- (c) Layout B in newest-first order. Expected: reversed, all rows verified.
- (d) Layout B′ with balances drifted one line down.
- (e) A salary of ₹1,12,450 → ₹1,48,000 (bonus) → ₹1,12,450, plus a ₹6,200 `BULK POSTING … REIMB` from the same payer five days later. Expected: 3 cycles; the reimbursement does not anchor a cycle.

---

## 9. Open questions and what to measure

1. **The owner's real file** (§0): run the masked layout dump and record which layout it is (A/B/B′/C), whether the headers carry `₹`, and whether continuation pages repeat the header. Commit the dump, not the PDF. `.local/` is already gitignored for exactly this.
2. **Native-assets build** with pdfrx 2.4.8 on this machine (§5.4). Pass/fail decides pdfrx vs Syncfusion. Takes one hour.
3. **SMS overlap.** Of the statement's rows for one month, how many already exist in the SMS ledger (by RRN, then by amount±date)? This is the cross-check of the "90 % appear only in the statement" claim on this owner's data. It decides whether the statement becomes the ledger of record for the SBI account, which I expect, or just a top-up.
4. **Charges vocabulary** (`SMS CHGS`, `ATM AMC`, GST): no verified SBI strings in our samples. Use the keyword set and add exact strings from the owner's file.
5. **Encrypted XLSX** (2025–26 web/YONO): out of scope for v1. Decrypting OOXML agile encryption in Dart is extra work with no maintained package, while the PDF covers the same data. The legacy `.xls` (TSV) costs about 40 lines; it is worth supporting because it is the cleanest source of all.

---

## Sources

- SBI statement samples (public court filings and a public PDF): [joselect.com e-statement 2020](https://joselect.com/photos/files/mrls_20201129100826_39734820704_15-10-2020_24-11-2020.pdf); Allahabad High Court filings [request1709820201](https://dc.allahabadhighcourt.in/assets/documents/request/request1709820201.pdf), [request_document16892614585](https://dc.allahabadhighcourt.in/assets/documents/request/request_document16892614585.pdf), [request1697699269](https://dc.allahabadhighcourt.in/assets/documents/request/request1697699269.pdf), [objection_document17065950211](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document17065950211.pdf), [objection_document16608202404](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document16608202404.pdf), [objection_document17052286160](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document17052286160.pdf), [objection_document17143659241](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document17143659241.pdf), [objection_document16379959663](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document16379959663.pdf), [objection_document17097070092](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document17097070092.pdf), [objection_document16860445632](https://dc.allahabadhighcourt.in/assets/documents/request/objection_document16860445632.pdf), [property1722531040](https://dc.allahabadhighcourt.in/assets/documents/property/property1722531040.pdf), [property/objection_document17160229910](https://dc.allahabadhighcourt.in/assets/documents/property/objection_document17160229910.pdf)
- Open-source SBI parsers: [abhijit86k/gnucash_statement_preprocessors](https://github.com/abhijit86k/gnucash_statement_preprocessors) (and the [July 2026 list post](https://lists.gnucash.org/pipermail/gnucash-user/2026-July/121136.html)), [harshsingh-io/indian-bank-statement-parser](https://github.com/harshsingh-io/indian-bank-statement-parser), [aakraj/kharchalens](https://github.com/aakraj/kharchalens), [atul0016/bank-statement-parser](https://github.com/atul0016/bank-statement-parser), [hstejas/pf_dashboard](https://github.com/hstejas/pf_dashboard), [adi-g15/kharcha](https://github.com/adi-g15/kharcha), [Shivapande25/Banking-Statement-Analyzer](https://github.com/Shivapande25/Banking-Statement-Analyzer), [iharshlalakiya/statementparser](https://github.com/iharshlalakiya/statementparser) (its SBI column list `Narration/Withdrawals/Deposits` matches no SBI file we found; low trust)
- Passwords: [ClearTax](https://cleartax.in/s/sbi-statement-password), [WPS](https://www.wps.com/blog/how-to-open-sbi-bank-statement-pdf-password/), [Univik](https://univik.com/blog/sbi-bank-statement-password.html), [mybankstatementanalysis](https://mybankstatementanalysis.com/blog/sbi-bank-statement-password), [TrulyInvoice](https://www.trulyinvoice.com/blog/sbi-bank-statement-pdf-password-unlock), [SBI Quick](https://sbi.co.in/portal/web/services/sbi-quick-missed-call-banking), [BankConv](https://bankconv.helpscoutdocs.com/article/15-sbi-statement-password)
- Narrations: [CEMTEX consumer case (casemine)](https://www.casemine.com/judgement/in/661a246c066d194da41250be), [Juspay NACH statement references](https://juspay.io/in/docs/lotuspay/web/nach-debit-flow/ach-debit-customer-bank-statement-references)
- Salary / recurring: [Plaid recurring transactions](https://plaid.com/blog/recurring-transactions/), [Plaid income ML](https://engineering.plaid.com/how-we-use-machine-learning-to-power-accurate-real-time-income-verification-404c64fd75b6), [US8380590B1](https://patents.google.com/patent/US8380590), [recur-scan](https://github.com/EbenezerOladipupoBankole/recur-scan), [SalaryLens](https://github.com/altafpasha/SalaryLens)
- Libraries: [pdfrx](https://pub.dev/packages/pdfrx) and [versions](https://pub.dev/packages/pdfrx/versions), [pdfrx_engine API](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/), [password-provider doc](https://github.com/espresso3389/pdfrx/blob/master/doc/Deal-with-Password-Protected-PDF-Files-using-PasswordProvider.md), [PDFium security handler](https://pdfium.googlesource.com/pdfium/+/refs/heads/main/core/fpdfapi/parser/cpdf_security_handler.cpp), [pdfium-binaries chromium/7811](https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium%2F7811), [syncfusion_flutter_pdf](https://pub.dev/packages/syncfusion_flutter_pdf) and [licence](https://pub.dev/packages/syncfusion_flutter_pdf/license), [Syncfusion forum on Flutter licence keys](https://www.syncfusion.com/forums/169276/how-to-apply-community-license-on-a-flutter-project), [Android PDF viewer / PdfRenderer V APIs](https://developer.android.com/media/grow/pdf-viewer), [PdfRendererPreV](https://developer.android.com/reference/android/graphics/pdf/PdfRendererPreV), [PDFBox-Android on Maven](https://search.maven.org/artifact/com.tom-roush/pdfbox-android), [read_pdf_text](https://pub.dev/packages/read_pdf_text), [flutter_pdf_text](https://pub.dev/packages/flutter_pdf_text), [pdf_text](https://pub.dev/packages/pdf_text), [pdfium_bindings](https://pub.dev/packages/pdfium_bindings)
- File picking: [file_picker](https://pub.dev/packages/file_picker), [android_file_picker](https://pub.dev/packages/android_file_picker), [Android SAF](https://developer.android.com/training/data-storage/shared/documents-files)

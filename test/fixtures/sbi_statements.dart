// Synthetic SBI statements (fake people, fake numbers) from
// docs/research/07-sbi-statement.md §8: the same 15 transactions printed in
// three real SBI layouts. Every row reconciles: opening ₹42,315.60, closing
// ₹1,72,717.70, 10 debits ₹97,158.90, 5 credits ₹2,27,561.00.
// Generated from the doc; edit the doc, not this file.

/// Layout A: CBS e-statement (dd/mm/yy, Cr suffix, BROUGHT/CARRIED FORWARD).
const String sbiLayoutA = r'''
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
''';

/// Layout B: OnlineSBI Account Statement PDF (year and Ref wrap a line).
const String sbiLayoutB = r'''
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
''';

/// Layout C: 2025–26 YONO / new-web export (dd/mm/yyyy, '-' for empty).
const String sbiLayoutC = r'''
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
''';

"""Measures the two guarantees on a real inbox database.

Usage:
  python tool/measure_inbox.py [path-to-finance_sms.db]

Pull the DB off a debug build with:
  adb -s <serial> exec-out run-as com.amartyaay.finnance_app cat databases/finance_sms.db > db.sqlite
  (use cmd.exe redirection; PowerShell `>` corrupts the binary)

Checks:
  P1  rows whose own SMS reads like an offer
  P1b rows with no money-moved verb
  P2  same amount+merchant+sender within 10 minutes
  P2b same amount+sender within 3 minutes (double-count candidates)
"""
import sys
import os
import re
import sqlite3

_db = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["TEMP"], "finance_sms.db")
con = sqlite3.connect(_db)
con.text_factory = lambda b: b.decode('utf-8', 'replace')

OFFER = re.compile(
    r'pre-?approved|pre-?qualified|loan|credit\s*line|available\s+limit of|'
    r'eligible|offer|apply\s+now|get\s+up\s+to|instant|disburs|sanction|'
    r'upgrade|reward|voucher|cashback\s+offer|win\b|unlimited',
    re.I,
)

print('=== P1: transactions whose own message reads like an offer ===')
rows = con.execute(
    "select kind, amount_paise/100, merchant, raw_body from transactions"
).fetchall()
suspects = [r for r in rows if r[3] and OFFER.search(r[3])]
print(f'total transactions: {len(rows)}   with offer wording: {len(suspects)}')
for kind, amount, merchant, body in suspects[:10]:
    print(f'  {kind:9} Rs {amount:>9}  {str(merchant)[:22]:24} | {body[:95]}')

print('\n=== P1b: spend rows with no debit/credit verb in their message ===')
VERB = re.compile(r'debit|credit|spent|paid|sent|withdraw|purchase|charged|txn|transferred', re.I)
noverb = [r for r in rows if r[0] == 'spend' and r[3] and not VERB.search(r[3])]
print(f'spend rows with no money verb: {len(noverb)}')
for kind, amount, merchant, body in noverb[:8]:
    print(f'  Rs {amount:>9}  {str(merchant)[:22]:24} | {body[:95]}')

print('\n=== P2: possible double counts (same amount+merchant+sender within 10 min) ===')
dupes = con.execute(
    """
    select t1.amount_paise/100, t1.merchant, t1.sender,
           count(*) as n, group_concat(distinct t1.kind) as kinds
    from transactions t1
    group by t1.amount_paise, lower(coalesce(t1.merchant,'')), t1.sender,
             cast(t1.occurred_at / 600000 as integer)
    having n > 1
    order by n desc, 1 desc
    limit 15
    """
).fetchall()
print(f'groups with >1 row in the same 10-minute bucket: {len(dupes)}')
for amount, merchant, sender, n, kinds in dupes:
    print(f'  x{n}  Rs {amount:>8}  {str(merchant)[:24]:26} {sender:12} {kinds}')

print('\n=== P2b: same amount + same sender + different merchant within 3 min ===')
pairs = con.execute(
    """
    select a.amount_paise/100, a.merchant, b.merchant, a.sender,
           (b.occurred_at - a.occurred_at)/1000 as gap_s
    from transactions a join transactions b
      on a.sender = b.sender
     and a.amount_paise = b.amount_paise
     and b.occurred_at > a.occurred_at
     and b.occurred_at - a.occurred_at < 180000
     and a.id < b.id
    limit 12
    """
).fetchall()
print(f'candidate same-sender lookalike pairs: {len(pairs)}')
for amount, m1, m2, sender, gap in pairs:
    print(f'  Rs {amount:>8}  {sender:12} {gap:>4}s  {str(m1)[:20]:22} | {str(m2)[:20]}')

print('\n=== overall kind mix ===')
for row in con.execute(
    "select kind, count(*), sum(amount_paise)/100 from transactions group by kind order by 3 desc"
):
    print(f'  {row[0]:10} {row[1]:4}  Rs {row[2]}')

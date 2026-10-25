"""Read-only verification of a device database (defects 1-4).

Usage: python .review_tmp/verify_db.py <db>
"""
import sqlite3
import sys
import os

path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ['TEMP'], 'finance_sms.db')
con = sqlite3.connect(path)
con.text_factory = lambda b: b.decode('utf-8', 'replace')


def q(sql, *args):
    return con.execute(sql, args).fetchall()


print('=== meta ===')
for row in q("select key, value from app_meta where key in "
             "('parser_version','schema_version','last_scan_at') order by key"):
    print(' ', row)

print('\n=== cards (defect 3: plastics only) ===')
cards = q('select issuer, last4, credit_limit, statement_day from cards order by issuer')
print(' count:', len(cards))
for row in cards:
    print(' ', row)
savings_like = [c for c in cards if c[0] in ('HDFC Bank', 'State Bank of India', 'ICICI Bank',
                                            'Card') and c[2] is None and c[0] == 'Card']
print('  cards with the old generic "Card" issuer:', len(savings_like))

print('\n=== card_bills (defect 2) ===')
bills = q('select card_key, total_due, min_due, due_date, statement_date from card_bills')
print(' count:', len(bills))
for row in bills:
    print(' ', row)

print('\n=== transactions ===')
print(' total:', q('select count(*) from transactions')[0][0])
for row in q('select kind, count(*), sum(amount_paise)/100 from transactions group by kind order by 2 desc'):
    print(' ', row)
print(' by money_in_kind:')
for row in q('select money_in_kind, count(*), sum(amount_paise)/100 from transactions '
             "where money_in_kind != 'none' group by money_in_kind order by 3 desc"):
    print(' ', row)
true_income = q("select count(*), coalesce(sum(amount_paise),0)/100 from transactions "
                "where money_in_kind in ('salary','interest','other')")[0]
print(' TRUE income rows (salary/interest/other):', true_income)

print('\n=== current month (latest txn month) ===')
month = q("select strftime('%Y-%m', max(occurred_at)/1000, 'unixepoch') from transactions")[0][0]
print(' latest month:', month)
for row in q(
    "select "
    " coalesce(sum(case when kind='spend' then amount_paise else 0 end),0)/100 as spend,"
    " coalesce(sum(case when kind='income' and money_in_kind in ('salary','interest','other') then amount_paise else 0 end),0)/100 as true_income,"
    " coalesce(sum(case when money_in_kind='refund' then amount_paise else 0 end),0)/100 as refunds,"
    " coalesce(sum(case when transfer_reason='creditCardBill' then amount_paise else 0 end),0)/100 as card_bills,"
    " coalesce(sum(case when kind='cash' then amount_paise else 0 end),0)/100 as cash "
    "from transactions where strftime('%Y-%m', occurred_at/1000, 'unixepoch') = ?", month):
    print(' ', row)

print('\n=== suspicious rows that must not exist ===')
for label, sql in {
    'card-bill credit booked as income':
        "select count(*) from transactions where money_in_kind='none' and kind='income'",
    'SIP mandate still a spend':
        "select count(*) from transactions where kind='spend' and raw_body like '%Debit Mandate%'",
    'promo wallet credits':
        "select count(*) from transactions where raw_body like '%wallet credit%' or raw_body like '%wallet credits%'",
    'savings account used as a card key':
        "select count(*) from transactions where card_key like 'HDFC Bank|3619' "
        "or card_key like 'State Bank of India|4642' or card_key like 'Card|4642'",
}.items():
    print(f'  {label}: {q(sql)[0][0]}')

print('\n=== the 2,999.85 SIP purchase ===')
for row in q("select count(*), coalesce(sum(amount_paise),0)/100 from transactions "
             "where raw_body like '%2,999.85%'"):
    print('  rows / total:', row)
for row in q("select kind, transfer_reason, money_in_kind, amount_paise/100, substr(raw_body,1,70) "
             "from transactions where raw_body like '%2,999.85%' limit 3"):
    print(' ', row)

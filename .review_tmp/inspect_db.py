import sqlite3, sys, os
path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ['TEMP'], 'finance_sms_final.db')
con = sqlite3.connect(path)
con.text_factory = lambda b: b.decode('utf-8', 'replace')

def q(sql, *args):
    return con.execute(sql, args).fetchall()

print('cards:', q('select count(*) from cards')[0][0])
print('card_bills:', q('select count(*) from card_bills')[0][0])
print('txns:', q('select count(*) from transactions')[0][0])
print('app_meta:', q('select * from app_meta'))
print()
for r in q('select issuer,last4,credit_limit from cards order by issuer'):
    print(' CARD', r)
print()
for r in q('select kind, count(*), sum(amount_paise)/100 from transactions group by kind'):
    print(' KIND', r)
print()
print('--- income rows ---')
for r in q("select amount_paise/100, merchant, substr(raw_body,1,110) from transactions where kind='income' order by amount_paise desc"):
    print(' IN', r)
print()
print('--- investment/emi rows ---')
for r in q("select kind, category_name, amount_paise/100, merchant, substr(raw_body,1,110) from transactions where raw_body like '%Debit Mandate%' or raw_body like '%EMI%' or category_name='Investments' limit 12"):
    print(' X', r)

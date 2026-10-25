import sqlite3, os, sys, datetime
path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ['TEMP'], 'finance_device2.db')
con = sqlite3.connect(path)
con.text_factory = lambda b: b.decode('utf-8', 'replace')
rows = con.execute(
    "select occurred_at, sender, amount_paise, kind, transfer_reason, merchant, reference_id, raw_body "
    "from transactions where amount_paise = 299985 order by occurred_at"
).fetchall()
for r in rows:
    ts = datetime.datetime.fromtimestamp(r[0] / 1000).strftime('%Y-%m-%d %H:%M:%S')
    print(ts, r[1], r[2], r[3], r[4], r[5], r[6])
    print('   ', (r[7] or '')[:160])

import json, os, re, sys
rows = json.load(open(os.path.join(os.environ['TEMP'], 'inbox_final.json'), encoding='utf-8'))
want = sys.argv[1] if len(sys.argv) > 1 else 'SIP Purchase'
for r in rows:
    if re.search(want, r['body'], re.I):
        print(r['sender'], '|', re.sub(r'\s+', ' ', r['body']))
        print()

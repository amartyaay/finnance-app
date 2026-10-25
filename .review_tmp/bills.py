import json, os, re, sys
rows = json.load(open(os.path.join(os.environ['TEMP'], 'inbox_final.json'), encoding='utf-8'))
pat = re.compile(r'total\s*(amt|amount|payment|due)|minimum\s*(amt|amount|due)|min\s*amt', re.I)
n = 0
for r in rows:
    b = re.sub(r'\s+', ' ', r['body'])
    if pat.search(b):
        n += 1
        print(r['sender'], '|', b[:230])
print('candidates:', n)

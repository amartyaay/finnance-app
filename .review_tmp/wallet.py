import json, os, re, sys
rows = json.load(open(os.path.join(os.environ['TEMP'], 'inbox_final.json'), encoding='utf-8'))
for r in rows:
    b = re.sub(r'\s+', ' ', r['body'])
    if re.search(r'credited to your wallet|Salary credited|wallet credits', b, re.I):
        print(repr(r['sender']), '|', b[:150])

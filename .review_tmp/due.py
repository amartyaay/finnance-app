import json, os, re, sys, collections
rows = json.load(open(os.path.join(os.environ['TEMP'], 'inbox_final.json'), encoding='utf-8'))
pat = sys.argv[1] if len(sys.argv) > 1 else r'\bdue\b|outstanding|statement'
limit = int(sys.argv[2]) if len(sys.argv) > 2 else 25
n = 0
seen = collections.Counter()
for r in rows:
    b = re.sub(r'\s+', ' ', r['body'])
    if re.search(pat, b, re.I):
        key = re.sub(r'\d', '#', b)[:60]
        seen[key] += 1
        if seen[key] <= 1 and n < limit:
            n += 1
            print(r['sender'], '|', b[:210])
print('total matching:', sum(seen.values()), 'distinct shapes:', len(seen))

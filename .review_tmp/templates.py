import json, os, re, sys, collections
path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ['TEMP'], 'inbox_final.json')
rows = json.load(open(path, encoding='utf-8'))
print('total', len(rows))

pats = {
 'cardcredited': r'credited to your card',
 'refund': r'refund',
 'closure': r'closure of td',
 'pluxee_credit': r'pluxee card .{0,40}credited',
 'walletcredit': r'wallet credit|credited to (?:your )?wallet|credits?\.',
 'mandate': r'debit mandate|nippon',
 'emi': r'\bemi\b',
 'statement': r'total amount due|total due|minimum due',
 'sip': r'sip purchase',
 'otp': r'\botp\b',
}
seen = collections.defaultdict(list)
for r in rows:
    b = r['body']
    for k, p in pats.items():
        if re.search(p, b, re.I):
            if len(seen[k]) < 6:
                seen[k].append((r['sender'], re.sub(r'\s+', ' ', b)[:190]))
for k, v in seen.items():
    print('\n==', k, '==')
    for s, b in v:
        print(' ', s, '|', b)

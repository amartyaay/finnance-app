"""Exports raw SMS rows from a pulled database as JSON for tool/replay_inbox.dart.

Usage:
  python tool/export_inbox.py <path-to-finance_sms.db> > inbox.json

The export contains sender/body/timestamp only (what the parser needs). Treat the
output as sensitive: it is the user's real messages.
"""

import json
import sqlite3
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'finance_sms.db'
con = sqlite3.connect(path)
con.text_factory = lambda b: b.decode('utf-8', 'replace')

rows = con.execute(
    'select id, sender, body, received_at from sms_messages order by received_at'
).fetchall()

out = sys.argv[2] if len(sys.argv) > 2 else 'inbox.json'
with open(out, 'w', encoding='utf-8') as fh:
    json.dump(
        [{'id': r[0], 'sender': r[1], 'body': r[2], 'received_at': r[3]} for r in rows],
        fh,
        ensure_ascii=False,
    )
print(f'wrote {out} ({len(rows)} messages)')

"""Trains the on-device SMS second-opinion model (logistic regression).

Usage:
  python -I tool/train_sms_model.py .local/inbox_full.json .local/gold assets/models/sms_lr.json

Design (docs/research/08-classifier-budget.md): a tiny linear model over hashed
word features, trained here once on the hand-labelled gold set and shipped as
weights that lib/services/sms/sms_model.dart evaluates in pure Dart. $0/year,
no network, ~0.1 ms per SMS. It is a *second opinion*: the rule engine stays
the gate, disagreements go to the review queue.

The featuriser below is a spec that the Dart side implements bit for bit
(tool/check_sms_model_parity.dart checks it on real messages):
  * text = body lowercased; URLs -> " __url__ "; every run of ASCII digits -> "0"
  * tokens = regex [a-z_0]+ and the rupee sign
  * features = "w:"+token, "b:"+token+" "+next_token, "dlt:"+DLT category letter
  * index = fnv1a32(utf8(feature)) % 2**18
Only features seen in >= 3 training messages are kept, so a name that appears in
one or two of the owner's messages can never be recovered from the shipped file.

Split: by TIME, never random. Train on the older messages, test on the newer
ones, exactly how the model will be used (trained once, run on future SMS).
"""
import json
import re
import sys
from collections import Counter, defaultdict

import numpy as np
from scipy.sparse import csr_matrix
from sklearn.linear_model import LogisticRegression

DIM = 2 ** 18
CLASSES = ['debit', 'credit', 'otp', 'promo', 'info']
URL = re.compile(r'https?://\S+|www\.\S+')
DIGITS = re.compile(r'[0-9]+')
TOKEN = re.compile(r'[a-z_0]+|₹')


def fnv1a32(text):
    h = 0x811C9DC5
    for byte in text.encode('utf-8'):
        h ^= byte
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def dlt_category(sender):
    parts = sender.split('-')
    if len(parts) >= 3 and len(parts[-1]) == 1:
        return parts[-1].upper()
    return 'none'


def features(sender, body):
    text = URL.sub(' __url__ ', body.lower())
    text = DIGITS.sub('0', text)
    tokens = TOKEN.findall(text)
    feats = ['w:' + t for t in tokens]
    feats += ['b:' + a + ' ' + b for a, b in zip(tokens, tokens[1:])]
    feats.append('dlt:' + dlt_category(sender))
    return feats


def label_class(label):
    return {'debit': 'debit', 'credit': 'credit', 'otp': 'otp', 'promo': 'promo'}.get(label, 'info')


def main(inbox_path, gold_dir, out_path):
    import glob
    msgs = {m['id']: m for m in json.load(open(inbox_path, encoding='utf-8'))}
    gold = {}
    for f in sorted(glob.glob(gold_dir + '/labels_*.jsonl')):
        for line in open(f, encoding='utf-8'):
            if line.strip():
                r = json.loads(line)
                gold[r['id']] = r
    rows = [(msgs[i], label_class(g['label'])) for i, g in gold.items() if i in msgs]
    rows.sort(key=lambda r: r[0]['received_at'])
    cut = int(len(rows) * 0.7)
    train, test = rows[:cut], rows[cut:]

    feats_train = [features(m['sender'], m['body']) for m, _ in train]
    df = Counter()
    for fs in feats_train:
        df.update({fnv1a32(f) % DIM for f in fs})
    keep = {i for i, c in df.items() if c >= 3}

    def matrix(feat_lists):
        data, ri, ci = [], [], []
        for r, fs in enumerate(feat_lists):
            counts = Counter(fnv1a32(f) % DIM for f in fs)
            for idx, c in counts.items():
                if idx in keep:
                    data.append(1.0)  # presence, not counts: robust to repeats
                    ri.append(r)
                    ci.append(idx)
        return csr_matrix((data, (ri, ci)), shape=(len(feat_lists), DIM))

    y_train = np.array([CLASSES.index(c) for _, c in train])
    y_test = np.array([CLASSES.index(c) for _, c in test])
    x_train = matrix(feats_train)
    x_test = matrix([features(m['sender'], m['body']) for m, _ in test])

    model = LogisticRegression(C=4.0, max_iter=3000, class_weight='balanced')
    model.fit(x_train, y_train)
    pred = model.predict(x_test)
    acc = (pred == y_test).mean()
    money = lambda ys: np.isin(ys, [0, 1])
    money_acc = (money(pred) == money(y_test)).mean()
    promo_as_money = int(((y_test == 3) & money(pred)).sum())
    money_missed = int((money(y_test) & ~money(pred)).sum())
    print(f'train {len(train)} (to {train[-1][0]["received_at"]}) test {len(test)}')
    print(f'held-out by time: accuracy {acc:.3f}  money/no-money {money_acc:.3f}  '
          f'promo->money {promo_as_money}  money missed {money_missed}')
    confusion = defaultdict(int)
    for t, p in zip(y_test, pred):
        confusion[(CLASSES[t], CLASSES[p])] += 1
    print('confusion (gold->model, errors only):',
          {f'{a}->{b}': n for (a, b), n in sorted(confusion.items()) if a != b})

    # The 70 % model and the test ids, for measuring disagreements honestly
    # (tool/audit_accuracy.dart --model … on .local/gold_timetest). Local only.
    import os
    os.makedirs('.local/gold_timetest', exist_ok=True)
    test_ids = {m['id'] for m, _ in test}
    with open('.local/gold_timetest/labels_99.jsonl', 'w', encoding='utf-8') as fh:
        for i, g in gold.items():
            if i in test_ids:
                fh.write(json.dumps(g, ensure_ascii=False) + chr(10))
    w70 = {str(i): [round(float(v), 4) for v in model.coef_[:, i]]
           for i in sorted(keep) if np.abs(model.coef_[:, i]).max() >= 1e-3}
    with open('.local/sms_lr_train70.json', 'w', encoding='utf-8') as fh:
        json.dump({'version': 1, 'dim': DIM, 'classes': CLASSES,
                   'bias': [round(float(v), 4) for v in model.intercept_],
                   'weights': w70}, fh, separators=(',', ':'))

    # Ship a model trained on everything, with the held-out numbers recorded.
    all_feats = feats_train + [features(m['sender'], m['body']) for m, _ in test]
    df = Counter()
    for fs in all_feats:
        df.update({fnv1a32(f) % DIM for f in fs})
    keep = {i for i, c in df.items() if c >= 3}
    y_all = np.concatenate([y_train, y_test])
    model.fit(matrix(all_feats), y_all)
    coef = model.coef_
    weights = {}
    for idx in sorted(keep):
        col = coef[:, idx]
        if np.abs(col).max() >= 1e-3:
            weights[str(idx)] = [round(float(v), 4) for v in col]
    out = {
        'version': 1,
        'dim': DIM,
        'classes': CLASSES,
        'bias': [round(float(v), 4) for v in model.intercept_],
        'weights': weights,
        'heldout': {
            'split': 'time, oldest 70 % train / newest 30 % test',
            'test_messages': len(test),
            'accuracy': round(float(acc), 4),
            'money_agreement': round(float(money_acc), 4),
            'promo_as_money': promo_as_money,
            'money_missed': money_missed,
        },
    }
    with open(out_path, 'w', encoding='utf-8') as fh:
        json.dump(out, fh, separators=(',', ':'))
    print(f'wrote {out_path}: {len(weights)} features')

    # Parity file (local only: it names real message ids): what the shipped
    # weights predict for 300 real messages, for the Dart port to reproduce.
    sample = [m for m, _ in (train + test)][::max(1, len(train + test) // 300)][:300]
    bias = np.array(out['bias'])
    w = {int(k): np.array(v) for k, v in weights.items()}
    parity = {}
    for m in sample:
        idxs = {fnv1a32(f) % DIM for f in features(m['sender'], m['body'])}
        scores = bias + sum((w[i] for i in idxs if i in w), np.zeros(len(CLASSES)))
        e = np.exp(scores - scores.max())
        parity[m['id']] = [float(v) for v in e / e.sum()]
    with open('.local/model_parity.json', 'w', encoding='utf-8') as fh:
        json.dump(parity, fh)


if __name__ == '__main__':
    main(*sys.argv[1:4])

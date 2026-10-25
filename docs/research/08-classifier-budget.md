# 08 — Classifier on a US$2–3/year budget: what to ship on a Galaxy S24 FE

**Status:** decision memo. Updates (does not repeat) [`05-classifier-options.md`](05-classifier-options.md) and [`06-on-device-llm.md`](06-on-device-llm.md).
**Date checked:** every web figure below was fetched **2026-10-26** (IST); the page's own "last updated" date is given where it publishes one.
**Device of record:** Galaxy S24 FE **SM-S721B**, Exynos 2400e, 8 GB RAM, Android 16 / SDK 36. (06 said "Android 14 shipped, upgradable"; the owner's phone is on 16. That does not change the Gemini Nano answer, because Nano availability depends on a device allowlist, not on the OS version.)
**Volume:** about 2,000 SMS in 4.5 months, so about 5,300 a year. Roughly 15 % are financial, and 10–20 % of those are ambiguous. That gives **about 1,000 second-opinion calls a year** at most.
**Grounding:** `.local/inbox.json` (2,000 real messages, 2026-06-12 → 2026-10-25) and `.local/gold/labels_2.jsonl` (370 hand labels so far). Only aggregate counts are quoted from them.

---

## 0. Decision

**I confirm the owner's working hypothesis, with three amendments.**

1. **Ship now: an on-device logistic regression in pure Dart. It costs US$0 a year.** Train it offline in Python on the hand-labelled inbox. Its inputs are hashed word and character n-grams with digits masked, plus about 40 hand features. Ship it as a JSON asset of about 50–150 KB that Dart evaluates in well under 1 ms per SMS. No native code, no plugin, and `flutter test` still covers it.
2. **Use it as a second opinion, not the gate.** The rule engine and `SmsGuards.moneyMoved` stay the admission gate. When the rules and the model disagree, the message goes to the review queue, and **an unconfirmed debit is left out of totals until the owner reviews it.** There is one exception: arithmetic confirmation (the balance or limit delta the SMS prints) beats the model.
3. **Optional: a bring-your-own-key cloud fallback, off by default, started by the user, for queue items only.** It is US$0/year on **Cloudflare Workers AI's free allocation** (no training on customer content) or **Groq's free tier** (no retention by default). The **Gemini API free tier is excluded**: Google's terms say free-tier content is used for training, may be read by human reviewers, and must not include personal information.

**Amendments to the hypothesis:**
- **"LR / NB ensemble" → one model, LR.** Train multinomial NB only as a baseline row in the evaluation. An NB+LR ensemble adds a calibration problem and buys about nothing at 2,000 labels (05 §2.c reasons still hold for NB on its own). Hashed n-grams *are* now justified, which reverses 05 §2.c: there are now real labels from the owner's own banks, and masking digits stops the model from memorising templates.
- **The model learns only 5 classes**: `debit`, `credit`, `otp`, `promo`, `info`. `bill_notice` (2/370 so far) and `phishing` (0/370) are too rare to learn and stay rule-only. A model cannot learn a class from about 10 examples.
- **The real annual cost is set by billing minimums, not by tokens.** At this volume every paid API costs **US$0.02–0.35 a year in tokens** (§2). However, OpenAI, Anthropic and (by default) Gemini all sell **prepaid credit with a US$5 minimum that expires after 12 months**, so the real cost is **≥ US$5/year**, which is over budget. Only the free tiers fit the budget, and only two of those are acceptable for privacy.

**Bottom line: US$0/year.** The shipped path is fully on-device. The optional cloud second opinion is also US$0 on Cloudflare or Groq free tiers with the user's own key.

---

## 1. Options table

Prices and limits are as of 2026-10-26. Accuracy figures are **estimates unless marked measured**. "Acct" means the user must hold an account or API key; the app has no backend, so every cloud row is bring-your-own-key.

| # | Option | $/year | Expected accuracy on this task | Size / RAM | Latency on S24 FE | Privacy | Effort |
|---|---|---:|---|---|---|---|---|
| A | **Hashed n-gram + hand-feature LR, JSON, pure Dart** | **0** | 5-class acc. **95–98 %**, macro-F1 0.90–0.95 (est.) | **50–150 KB** asset, <1 MB RAM | **<0.1 ms** | On-device | **~4 days** (labels in progress) |
| A′ | Multinomial NB, same features | 0 | 93–97 % (est.); UCI spam 98.4–98.6 % (lit.) | ~same | <0.1 ms | On-device | +0.5 day (baseline only) |
| B1 | MediaPipe / LiteRT text classifier, Average Word Embedding | 0 | ≈ A or worse at 2k labels (est.) | ~1 MB model (from memory, page lists none) + TFLite runtime ~1–3 MB/ABI | 0.14 ms on a Pixel 6 CPU (Google) | On-device | 3–4 days; `tflite_flutter` 0.12.1 is 12 months old, API ≥ 26; no host tests |
| B2 | Same, MobileBERT classifier | 0 | ties A at 2k labels; needs 5–10k to win (05 §2.e) | ~25 MB (from memory) | 57.7 ms on a Pixel 6 CPU (Google) | On-device | 4–5 days, same tax |
| C1 | Gemma 3 270M via LiteRT-LM (`flutter_edge_ai` 2.5.3) zero-shot | 0 | **poor**: IFEval 51.2 %; zero-shot 7-way likely 55–75 % (est.) | 289 MB download, ~0.5 GB RAM | ~2 s/msg (06 derating) | On-device | 10–14 days; minSdk 30; arm64 only; CPU only on Exynos |
| C2 | Gemma 3 270M **fine-tuned** on our labels | 0 | could reach A's level; no published classification number exists | 289 MB | ~0.3–0.5 s for a 1-token label (est.) | On-device | +3–5 days on top of C1 |
| C3 | Gemma 3 1B / Qwen2.5-0.5B zero-shot | 0 | 75–88 % (est.) | 1.0 GB / 0.52 GB download, 1.2–1.6 GB peak RAM | 8–13 s/msg (06) | On-device | 10–14 days |
| D | Gemini Nano (AICore / ML Kit Prompt API) | — | — | — | — | — | **Unavailable**: SM-S721B is not on either list (page updated 2026-10-23) |
| E | ML Kit Entity Extraction (Money, Payment card) | 0 | does not classify; duplicates `AmountFinder` | model download | ms | On-device | not worth it |
| F1 | Gemini 2.5 Flash-Lite **free tier** | 0 | ~95–98 % zero-shot (est.) | — | network | **Excluded**: used for training, human review, "do not submit … personal information" | 1 day |
| F2 | Gemini 2.5 Flash-Lite paid | tokens **$0.03** (batch $0.016); real **$5/yr** prepay floor unless the account is eligible for postpay | ~95–98 % (est.) | — | network | Not used for training | 1 day + Cloud billing account |
| F3 | Claude Haiku 5.5 | tokens **$0.035** (batch $0.018); real **≥$5/yr** (credits expire after 1 year) | ~96–98 % (est.) | — | network | Not trained by default | 1 day + Console account |
| F4 | OpenAI gpt-5-nano | tokens **$0.022**; real **$5/yr** (minimum $5, expires after 1 year) | ~94–97 % (est.) | — | network | API not trained by default | 1 day + account |
| F5 | **Cloudflare Workers AI** free (10,000 neurons/day) | **0** (about 1,000–4,600 neurons a *year*) | Llama 3.2 1B ~80 % (est.); Qwen3-30B-A3B / Gemma-4-26B ~94–97 % (est.) | — | network | **No training on customer content**; not stored unless you use a storage product | 1 day + CF account + API token |
| F6 | **Groq** free (llama-3.1-8b: 14,400 RPD, 500k TPD, third-party figures) | **0** | ~90–95 % (est.) | — | network | No retention by default; self-serve ZDR | 1 day + account |
| F7 | OpenRouter `:free` models | 0 | varies | — | network | 50 req/day without credits; training depends on the provider, set by an account toggle | 1 day + account |
| F8 | Cerebras | 0 for 30 days, then paid | — | — | network | — | Trial credits ($5) expire after 30 days and need a card. **Not a free tier.** |

### Notes on the table
- **Token cost formula.** 1,000 calls × 200 input + 30 output tokens = **0.2 M input + 0.03 M output tokens a year.** A real prompt with instructions and 5 few-shot examples is closer to 600 in / 60 out, which is about 3× the token cost. That is still **≤ US$0.11/year** on F2–F4 and still free on F5–F6.
  - Gemini 2.5 Flash-Lite: $0.10 / $0.40 per M tokens (3.1 Flash-Lite $0.25 / $1.50; 3.5 Flash-Lite $0.30 / $2.50).
  - Haiku 5.5: $0.10 / $0.50 for prompts under 100k tokens (Haiku 4.5: $1 / $5, which is $0.35/yr).
  - gpt-5-nano: $0.05 / $0.40 (gpt-4.1-nano $0.10 / $0.40; gpt-6-luna $0.10 / $0.50).
  - Cloudflare Llama 3.2 1B: 2,457 / 18,252 neurons per M tokens, so 0.2 × 2,457 + 0.03 × 18,252 ≈ **1,040 neurons a year**. Qwen3-30B-A3B at 4,625 / 30,475 is about 1,840 a year at 200/30, or about 4,600 a year at 600/60. Either is a fraction of **one day's** free 10,000. Overage is $0.011 per 1,000 neurons.
- **Accuracy for the cloud models is an estimate.** No vendor publishes Indian-bank-SMS numbers, and I found no public benchmark for that 3–7-way task (searched 2026-10-26). The only way to know is to run each candidate on the gold set (§4).
- **The billing floor is the finding that decides this.** Gemini's billing page says "New users default to the Prepay billing plan … The minimum purchase is $5 … credits expire 12 months after their purchase date". OpenAI sets a $5 minimum and credits expire after 1 year. Anthropic credits expire one year from purchase and are non-refundable. So **"a few cents of tokens" becomes US$5/year in cash** unless you are eligible for Gemini postpay.

---

## 2. What changed since memos 05 and 06

| Topic | 05/06 said | Checked 2026-10-26 |
|---|---|---|
| Gemini Nano on S24 FE | Not on either list | **Still not on either list.** Samsung models on the lists are only S25 / S26 / Z Fold7 / Z Fold8 / Z Flip8 / Z TriFold (ML Kit GenAI, updated 2026-10-23). |
| `flutter_edge_ai` | 2.5.2 | **2.5.3**, 16 likes, 8.78k downloads, one maintainer. NPU/GPU backends are listed for Qualcomm, Tensor and MediaTek only, **not Exynos**, so the S24 FE would run C1–C3 on CPU. |
| `tflite_flutter` | 0.12.1, stale | Unchanged: 0.12.1, 12 months, API ≥ 26. |
| MediaPipe text classifier | not costed | Average word embedding **0.14 ms**, BERT **57.68 ms** on a Pixel 6 CPU (page updated 2026-10-01). |
| Hashed n-grams | Rejected (05 §2.c) | **Reversed for LR.** We now have real labels from the owner's own banks, and digit masking turns templates into shared n-grams. The calibration objection applied to NB, not to LR. |
| Cloud | "E not built" (06 §5.2) | Still off by default. It is now **costed** (§1), with two US$0 options that do not train on the data. |
| DLT suffix | header parsed (`SenderRegistry.dltCategory`) | **Measured on the real inbox (§3.1).** It is the strongest single feature, but it does not separate debit from info. |

---

## 3. Feature design: what a linear model needs in order to beat the rules

### 3.1 What the real inbox says (aggregate counts, 2026-10-26)

**DLT suffix on all 2,000 messages:**

| Suffix | Count | Share |
|---|---:|---:|
| `-S` | 1,082 | 54 % |
| `-P` | 704 | 35 % |
| `-T` | 81 | 4 % |
| `-G` | 70 | 3.5 % |
| Phone number | 61 | 3 % |
| None | 2 | 0.1 % |

TRAI's suffix rule (TCCCPR amendment, effective 2025-05-06; operators append it) is **live on 99.9 % of this inbox**.

**Suffix × gold label (370 labelled):**

| Suffix | debit | credit | bill | otp | promo | info |
|---|---:|---:|---:|---:|---:|---:|
| `-S` | 47 | 13 | 2 | 63 | **1** | 87 |
| `-P` | 2 | 2 | 0 | 0 | **118** | 9 |
| `-T` | 0 | 0 | 0 | 8 | 0 | 0 |
| `-G` | 0 | 0 | 0 | 0 | 0 | 13 |
| Phone number | 0 | 0 | 0 | 4 | 0 | 1 |

What this shows:
- **`-P` alone predicts promo at 118/131 = 90 %, and `-S` predicts not-promo at 212/213.** A one-feature model already solves most of the promo problem.
- **Banks send debit/credit alerts as `-S`, not `-T`.** In this inbox `-T` was only OTPs. **The hard boundary is debit/credit vs info inside `-S`** (60 money rows vs 87 info rows). That is where the model must earn its keep, and where the rules already work hardest.
- **The four `-P` debit/credit rows must be reviewed.** They are either label errors or merchants sending receipts on a promotional header. Either way, `-P` must stay a feature, never a veto.

### 3.2 Feature list

Each feature is a sparse binary or a bucketed count. Hash with FNV-1a-32 over UTF-8 so Python and Dart agree bit for bit. The repo already has `fnv1a64`; use 32-bit here to avoid `BigInt`.

**Before computing n-grams, normalise the text:**
- lowercase it;
- replace every digit run with a shape token (`0`, `00`, `0000`, …), so `Rs.2,000.00` becomes `rs.0,000.00` and `XX1234` becomes `xx0000`;
- map `₹`, `Rs`, `INR` and `Rs.` to one `<cur>` token;
- reduce each URL to `<url:domain>`.

| Group | Features | Why |
|---|---|---|
| **Sender** | DLT suffix one-hot (S/T/P/G/none/phone); **entity class** from `SenderRegistry` (known bank, card issuer, wallet/UPI app, merchant, govt, unknown); crosses **entity × suffix** (bank+P = bank cross-sell; unknown+phone = personal or phishing) | The strongest prior (§3.1). The cross is what a linear model can't build itself. |
| **Assertion (past)** | `debited`, `credited`, `spent`, `paid`, `withdrawn`, `sent`, `received`, `transferred`, `refunded`, `reversed`, `charged`, `deducted`, each with `has been` / `is` / `was` | Money moved. |
| **Mood: future / conditional** | `will be`, `shall be`, `would be`, `scheduled`, `due on`, `due by`, `is due`, `by dd-mmm`, `auto-debit on`, `mandate`, `reminder` | Separates info from debit: "will be debited" is info. |
| **Mood: availability / offer** | `eligible`, `pre-approved`, `upto` / `up to`, `get`, `avail`, `apply`, `offer`, `instant`, `sanctioned`, `limit of`, `cashback of … on`, `%`, `off`, `T&C` | Separates promo from debit. This is the "loan of ₹36,000 available" family. |
| **Failure / request** | `failed`, `declined`, `unsuccessful`, `not processed`, `requested`, `collect request`, `has requested money` | Info, even when an amount and a verb appear. |
| **OTP** | `otp`, `one time password`, `verification code`, a standalone 4–8 digit run, `do not share`, `valid for N min` | Separates OTP from everything else. |
| **Amounts** | Amount count bucket (0 / 1 / 2 / 3+); **labelled balance/limit present** (`avl bal`, `avbl lmt`, `available balance`, `bal:`); a cashback/percent next to the amount | A balance next to an amount is the strongest debit/credit signal and the base for arithmetic confirmation. |
| **Instrument and ref** | Account mask (`xx0000`, `*0000`, `ending 0000`, `a/c no. xx`); card mask; VPA (`@ybl`, `@okaxis`, `@paytm`, `@axl`); UPI ref / RRN (12-digit), `ref no`, `txn id`; date-time stamp | Real alerts carry the instrument and the reference; promos don't. |
| **Fraud footer** | `not you?`, `if not done by you`, `call 1800…`, `sms block`, `report` | Genuine debit alerts carry it, and it is a strong debit cue. Phishing copies it, so cross it with the sender class. |
| **URL** | Count; shortener (`bit.ly`, `tinyurl`, `cutt.ly`, `rb.gy`); **domain matches the entity's known domain**; unusual TLD (`.xyz`, `.top`, `.click`); IP literal; `http:` | Phishing (rule-only label), but URLs also lower debit odds. |
| **Shape** | Length bucket, digit ratio, uppercase ratio, Devanagari present, bare phone number in body | Cheap priors. |
| **Text** | Hashed word unigrams + bigrams, char 3–5-grams inside word boundaries, on normalised text, into **2¹⁶ buckets** | Catches the vocabulary the hand list misses. |

**Do not give the model the rule engine's final class as a feature.** The model may reuse the same *primitive* predicates (`SmsGuards.moneyMoved` as a boolean, for example), but if it sees the rules' verdict, it learns to copy it. Then rules and model fail together, and "disagreement" stops meaning anything.

**The `kind` field** (spend, p2p, card_bill_payment, …) stays with the rules in v1. If the evaluation shows the rules mis-kinding more than 5 % of money rows, train a second LR on the debit/credit rows only (12 kinds) with the same features plus merchant/VPA tokens.

---

## 4. Measuring accuracy honestly

1. **Labels come from reading, never from the parser** (`docs/eval/gold-labelling.md`). A big LLM may *pre-label*, but a human confirms every row.
   - Measure the LLM against the human on the first 300 rows and report the agreement. If the LLM is used as an oracle later, that number is its error bar.
   - If the pre-labelling runs on a cloud API, the call must be paid-tier or no-training (F5/F6), for the same reason F1 is excluded.
2. **Split by time, not at random.** Train on 2026-06-12 → ~09-10 (about 70 %). Test on ~09-11 → 10-25 (about 30 %, about 600 messages).
   - Bank templates repeat almost word for word. A random split puts copies of the same template in train and test, which inflates scores by several points.
   - Also report **leave-one-sender-entity-out** results. That is the number that predicts how the model behaves when the owner gets a new bank.
3. **Deduplicate templates across the split.** Mask digits and names. If a masked test message is identical to a training message, report it separately as "seen template". The headline number is on **unseen templates**.
4. **Product metrics come before macro-F1.** Three comparisons decide whether the model ships:
   - (a) **spam-as-spend**: promo or info predicted as debit. The target is **0**.
   - (b) **debit recall**.
   - (c) **review-queue size per month**. The target is **≤ 25**, about one a day.

   Compare **rules alone vs model alone vs combined** with a paired McNemar test on the same test messages.
5. **Be clear about what ~600 test messages can show.** At about 90 debits, a perfect observed recall still means only **≥ 96.7 %** at 95 % confidence (rule of three: 3/90). One error moves accuracy by 0.17 pp, and the 95 % interval on accuracy is about ±1.2 pp. So "96 % vs 97 %" cannot be told apart. **Decide on the error counts in the product-critical cells, not on headline accuracy.**
6. **Ship rule:** the combined system must have spam-as-spend = 0, debit recall ≥ the rules' recall, and a queue ≤ 25/month on the time-split test. Otherwise the model stays in shadow mode, logging disagreements only.
7. **Expected result (estimate, to be replaced by the measurement):**
   - LR alone: **95–98 %** 5-class accuracy on unseen templates.
   - Disagreement with the rules: **2–5 % of all messages**, which is 40–100 per 2,000, or 10–25 a month.
   - Most disagreements will be `-S` info vs debit edge cases: scheduled mandates, failed transactions, collect requests.

---

## 5. Recommended design

```
SMS ─► SenderRegistry + features ─┬─► rule engine + SmsGuards (gate) ─► rules_class
                                  └─► LR (assets/sms_lr_v1.json) ────► model_class, p
combine:
  agree                                   → accept
  rules=debit/credit AND balance/limit
    arithmetic confirms                   → accept (hard evidence beats the model)
  rules=debit/credit, model≠ with p≥0.7   → "unconfirmed": NOT in totals, review queue
  rules≠money, model=debit/credit p≥0.9   → review queue, NOT in totals
  otherwise                               → rules win, disagreement logged
review queue item ─► [Ask cloud] (off by default, BYO key, redacted) ─► suggestion only;
                     the owner's tap is the label; the label feeds the next training run
```

### Components

| Piece | Where | Detail |
|---|---|---|
| Training | `tool/train_sms_lr.py` | scikit-learn `LogisticRegression(multinomial, class_weight='balanced')`, L1 or elastic-net to prune buckets, then isotonic calibration on a time-later fold. Exports `{schemaVersion, hash:"fnv1a32", buckets:65536, classes, features, w:{idx:[int8×5]}, scale, b}`. |
| Golden vectors | `test/fixtures/lr_golden.json` | Python writes feature indices and probabilities for 200 messages. The Dart test asserts identical indices and probabilities within 1e-6. **This parity test is the only native-code-free guarantee that the shipped model is the trained model.** |
| Inference | `lib/engine/sms_model.dart` | Pure Dart: normalise, hash, sparse dot product, softmax. Expected about 300 active features × 5 classes, which is about 0.02–0.1 ms. |
| Asset | `assets/sms_lr_v1.json` | About 3–10k non-zero buckets after pruning: **50–150 KB** raw, less in the APK. |
| Storage | `sms_messages` | Add `model_class`, `model_p`, `model_ver` columns so a retrained model can be replayed with `tool/replay_inbox.dart`. |
| Queue | existing `review_queue` + `SmsInboxScreen` | New filter "Rules and model disagree". The owner's choice is written back as a gold label (local only). |
| Retraining | developer laptop | Pull the DB, merge new labels, retrain, bump `model_ver`. No on-device training. |
| Cloud (optional) | Settings › Advanced › "Second opinion" | Off by default. Provider is Cloudflare Workers AI (`@cf/qwen/qwen3-30b-a3b-fp8`) or Groq, with the user's own account id and token kept in Android Keystore-backed storage. |

**Cloud fallback rules:**
- One message per tap.
- Mask account and card numbers, VPAs and names before sending.
- Use JSON-schema output.
- The answer is a suggestion only and never posts to the ledger.
- The `INTERNET` permission already exists for Flutter debug. A release build must declare it explicitly, and the Play Data safety form must then disclose it.

### Effort

| Task | Days |
|---|---:|
| Finish the 2,000 gold labels (370 done) | ongoing |
| Training script and export | 1 |
| Dart features, inference and parity tests | 1.5 |
| Combine policy, DB columns and queue filter | 1 |
| Time-split evaluation write-up | 0.5 |
| **Total for the shipped path** | **~4 days** |
| Optional cloud second opinion | +1–1.5 days |

### What would change this
- **The model loses to the rules on the time split.** Then keep it in shadow mode and spend the effort on rules. 05 §7.4 still applies.
- **Labels pass 10k (more phones).** Then reconsider C2 (fine-tuned 270M) or B2. Not before.
- **The owner's next phone is on the ML Kit Prompt API list** (Samsung: S26 / Z Fold7 / Z Fold8 / Z Flip8 / Z TriFold; **not** the S25). Then Nano replaces the cloud fallback at US$0, using the same prompt and schema.
- **Gemini offers postpay to this account.** Then F2 becomes a ~US$0.03–0.10/year *paid, no-training* option with the strongest cheap model, and it replaces F5 as the default suggestion.

---

## 6. Sources (all fetched 2026-10-26)

- Gemini API pricing — https://ai.google.dev/gemini-api/docs/pricing (updated 2026-10-22): 2.5 Flash-Lite $0.10 / $0.40, batch $0.05 / $0.20; 3.1 Flash-Lite $0.25 / $1.50; 3.5 Flash-Lite $0.30 / $2.50. "Used to improve our products": free **Yes**, paid **No**.
- Gemini API terms — https://ai.google.dev/gemini-api/terms (updated 2026-04-28): for unpaid services, content is used to "improve, and develop Google products … and machine learning technologies"; "human reviewers may read, annotate, and process your API input and output"; "Do not submit sensitive, confidential, or personal information to the Unpaid Services."
- Gemini rate limits — https://ai.google.dev/gemini-api/docs/rate-limits (updated 2026-10-15): no published free-tier table; limits are per project in AI Studio. Third-party sources give about 15 RPM / 1,000 RPD for Flash-Lite, unverified: https://pricepertoken.com/endpoints/google-ai-studio/free
- Gemini billing — https://ai.google.dev/gemini-api/docs/billing (updated 2026-09-28): new users default to Prepay, $5 minimum, credits expire 12 months after purchase.
- Claude pricing — https://platform.claude.com/docs/en/about-claude/pricing: Haiku 5.5 $0.10 / $0.50 (≤100k prompt), batch $0.05 / $0.25; Haiku 4.5 $1 / $5. Credit expiry: https://support.claude.com/en/articles/8977456-how-do-i-purchase-credits-for-the-claude-api
- OpenAI pricing — https://developers.openai.com/api/docs/pricing: gpt-5-nano $0.05 / $0.40 (batch $0.025 / $0.20); gpt-4.1-nano $0.10 / $0.40; gpt-6-luna $0.10 / $0.50. Prepaid minimum and expiry: https://help.openai.com/en/articles/8264644-setting-up-and-managing-prepaid-api-billing
- Cloudflare Workers AI pricing — https://developers.cloudflare.com/workers-ai/platform/pricing/ (updated 2026-10-20): 10,000 neurons/day free; $0.011 per 1k neurons over that; per-model neuron rates as quoted. Privacy: https://developers.cloudflare.com/workers-ai/platform/privacy/
- Groq — https://console.groq.com/docs/rate-limits (exact free limits are only shown in the console); 14,400 RPD / 500k TPD for llama-3.1-8b are third-party figures (https://eesel.ai/blog/groq-pricing). Data: https://console.groq.com/docs/your-data
- OpenRouter — https://openrouter.ai/docs/api/reference/limits (`:free`: 20 RPM; 50 RPD under 10 credits, 1,000 RPD at 10 or more); https://openrouter.ai/docs/guides/privacy/logging
- Cerebras — https://inference-docs.cerebras.ai/support/rate-limits ($5 trial credits, 30-day expiry, payment method required)
- ML Kit GenAI device lists — https://developers.google.com/ml-kit/genai (updated 2026-10-23)
- `flutter_edge_ai` 2.5.3 — https://pub.dev/packages/flutter_edge_ai; `tflite_flutter` 0.12.1 — https://pub.dev/packages/tflite_flutter
- MediaPipe text classifier — https://developers.google.com/edge/mediapipe/solutions/text/text_classifier (updated 2026-10-01)
- ML Kit Entity Extraction — https://developers.google.com/ml-kit/language/entity-extraction (updated 2024-07-10, beta)
- Gemma 3 270M — https://developers.googleblog.com/en/introducing-gemma-3-270m/ (IFEval 51.2 %, built for task fine-tuning; no classification benchmark published)
- SMS spam literature (UCI corpus, lexically disjoint, so an upper bound and not a prediction for this task):
  - NB 98.39 % vs LR 95.52 %: https://issuu.com/irjet/docs/comparative_analysis_of_naive_bayes_and_logistic_r
  - MNB + TF-IDF 98.50 %: https://www.preprints.org/manuscript/202109.0251
  - MNB 98.6 %, 10-fold: https://www.academia.edu/129460280/Smart_Spam_Detection_of_SMS_Using_Ensemble_Methods_of_Machine_Learning
- TRAI header suffixes (-P / -S / -T / -G, from 2025-05-06): https://www.medianama.com/2025/05/223-suffixes-commercial-sms-headers-spam/, https://www.tanla.com/udayreddy/trai-mandates-new-message-suffixes-heres-what-you-need-to-know
- No public labelled Indian bank-SMS benchmark found. The closest is a rules + small-LLM pipeline with no metric, where rules cover 70–80 %: https://huggingface.co/SahilGoel/indian-txn-classifier

*Every accuracy figure in §1 not attributed to a source is an estimate. §4 is the procedure that replaces them with measurements.*

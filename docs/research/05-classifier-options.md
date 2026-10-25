# 05 — Classifier options: what actually stops spam counting as spend

**Status:** decision memo. Not a spec.
**Date:** 2026-10-25 (IST)
**Decision needed:** what replaces (or wraps) `SmsClassifier`'s 25 weighted signals, and what we ship in the next two releases.
**Grounding:** `docs/research/01-sms-corpus.md` (2566 lines), `02-spam-and-phishing.md`, `03-credit-semantics.md`, `parser-gap-report.md` (HEAD `43ae964`), `real-data-findings.md`, and the code in `lib/services/sms/`, `lib/engine/txn_guards.dart`, `lib/engine/dedupe_engine.dart`.

---

## 0. The decision in one page

**Recommendation: no learned model in v1, and logistic regression over the existing signals in v2. Nothing else survives contact with the constraints.**

The instinct in the brief — "strong data parser *or* a small in-house model" — is a false choice, and the framing hides the actual bug. Both of the owner's priorities are **admission** problems and **identity** problems, not discrimination problems:

| Owner's goal | What actually achieves it | What does not |
|---|---|---|
| **1. Never count spam as spend** | A gate that requires *positive evidence that money moved*, with a tier for "asserted but unconfirmed" that stays out of totals. Plus — decisively — **arithmetic confirmation from the balance/limit field the SMS already prints**. | A better spam classifier. The promo that leaks today (`Get up to 5% cashback on your next payment of Rs 2,000`) contains the words *payment of*. Any lexical model, including a transformer, sees a payment. A ₹2,000 debit alert and an offer *about* a ₹2,000 payment differ by one word of mood, not by vocabulary. |
| **2. Never double count** | One dedupe implementation (you currently have two), plus a per-account balance ledger that makes "two alerts, one ₹" arithmetically impossible, plus monthly reconciliation against `card_bills.total_due` — free ground truth you already store. | Any text classifier at all. Zero of the seven options in §2 touch identity. |

So the split is roughly:

- **80 % of the value is deterministic** and lives in one new module (`assertion.dart`) plus arithmetic reconciliation. Five working days.
- **15 % needs a learned arbiter** for the genuinely ambiguous middle ("debited by transfer", "trf to PhonePe", "reversal of", a bank cross-sell inside a real alert). Logistic regression on ~45 features, weights as a 1.2 KB JSON, 10 µs per SMS, and — the reason it wins — the model's output *is* the explanation (`Σ wᵢxᵢ` per feature, which maps 1:1 onto the `SmsSignal` list the UI already renders). Twelve more days, of which three are labelling.
- **5 % is fashion** and should not be built: transformers on-device, LLM on-device, gradient boosting, character n-grams. §2 says why each one loses *on this task*, not in general.

**The single most valuable thing to do on day one** is a measurement, not a model: over the owner's 2,000-message inbox, what fraction of genuine debit/credit alerts print an available balance or available limit? The parser already extracts both (`AmountFinder.balanceAfter`, `.availableLimit`). If that number is ≥80 %, arithmetic confirmation can adjudicate most of the ledger with ~zero false positives, and the model becomes a nicety. If it is 40 %, the probabilistic tier carries more weight. **Nobody should choose an architecture before that query runs.** Call it the *balance-coverage number*; everything in §4 is sized around it.

---

## 1. Where the engine fails, measured

Not opinions — these are the repo's own numbers from `parser-gap-report.md` (same HEAD) and `real-data-findings.md`.

### 1.1 Fixture pass rates

| Suite | Passed | Rate |
|---|---:|---:|
| Transaction corpus (103 fixtures + 6 dedupe checks) | 47 / 109 | **43.1 %** |
| Classifier corpus (77 fixtures) | 52 / 77 | **67.5 %** |
| Combined | 98 / 180 | **54.4 %** |

Classifier corpus by research class:

| Class | Fixtures | Passed | Rate |
|---|---:|---:|---:|
| transaction | 19 | 17 | 89.5 % |
| informational | 13 | 1 | **7.7 %** |
| otp | 9 | 5 | 55.6 % |
| promo | 14 | 13 | 92.9 % |
| fraud | 22 | 16 | 72.7 % |
| **negatives (J+K, transaction corpus)** | **25** | **20** | **80.0 %** |

### 1.2 What those numbers say

**(a) The false-spend leak is real and quantified: 5 of 25 negative fixtures still produce a ledger row.** A 20 % leak rate on the adversarial slice is the exact failure the owner keeps seeing. This is not noise at the margins; it is the headline defect.

**(b) Precision on promos (92.9 %) and transactions (89.5 %) is already good. Recall on informational is catastrophic (7.7 %).** That asymmetry matters enormously for architecture choice: the classifier does not need better *discrimination*, it needs a **veto** — a rule that says "no money has moved yet" and wins over a perfect debit template. `parser-gap-report.md` §RC-05 and §SC-01 both trace to this. A logistic regression can learn that veto only if you hand it the feature; once you hand it the feature, the feature is the fix.

**(c) Chasing the leak with vocabulary is a treadmill.** The suggestion-level structure is:
```
known_sender(+3) + dlt_transactional(+1) + amount(+2) = 6
genuineTransaction := tx >= 6 && hasAmount && trust != suspicious   → class = transaction
```
That is six points reachable by *sender + suffix + any rupee figure*, with no verb required. Add a promo with a money verb ("...on your next payment of Rs 2,000") and `_debitVerb` fires (+4) and the gate's own `_moneyMoved` whitelist contains `payment of`, so it is counted. Every word you add to the promo regex is a word a bank will legitimately use in an alert ("offer" appears in real cashback credits — fixture G06/G07 exist precisely for this). This is a structural problem: **the class boundary is being drawn on mood and modality, and the scorer has no representation of mood.**

**(d) Phishing is not a classification problem, it is a security property.** 141 of 2,000 real messages were flagged (7 %); of a sample of 8, **6 were wrong** — OTPs with "never share", the issuer's own KYC link, a cart reminder, a credit-line offer. That is roughly 5 false accusations per 100 messages, several banners a day on a real phone. The mechanism is precise and worth staring at, because a naive reading ("the rules need better words") is wrong:

- The negation guard **already exists and works** for the credential ask: `SmsGuards.shareIsNegated` gates `_credentialAsk` (`sms_classifier.dart:309`). But `_phishCta` independently contains the literal alternative `share (?:the )?otp`, with no negation check — so "**Never share** OTP" still adds +3 to the phishing score from a second, ungated regex.
- Worse, a phishing verdict is reachable with **no intent predicate at all**: `_kycLure` (+4) alone reaches the `phish >= 4` branch. That is how the genuine RBI "your account has been blocked, update KYC on `i.airtel.in`" advisory (SC-03) is accused by its own issuer.
- Domain-vs-entity trust exists (`_isSuspiciousUrl`) but only as a *penalty* for odd TLDs, shorteners and IP hosts; a matching domain does not *raise* trust, so it never offsets the pressure words.

No trained model fixes this better than two predicates: (i) a credential ask is imperative, second-person, and not negated — checked in **one** place, used by every rule that mentions credentials; (ii) a phishing verdict requires fraud **intent** (pressure *and* domain mismatch, or a payment instruction to an unregistered sender), not a link and not urgency alone. Both are already sketched in `real-data-findings.md` §C; they are under-weighted and, critically, evaluated in the wrong order.

**(e) You already have two dedupe engines, and that is how double counting comes back.** `DedupeEngine` (3-minute window, deliberately *allows* same-sender merges, persists `duplicate_of`) runs in the repository path; `DuplicateResolver` (2-minute window, *requires* same-sender for a duplicate notification, also collapses debit/credit pairs, **not persisted, recomputed on every `HomeData.build`**) runs at display time in `finance_repository.dart:182`. Two implementations, two windows, opposite same-sender policies, one persisted and one ephemeral. That is the same class of defect the architecture doc §1 says was fixed for the Kotlin/Dart parser drift. Any classifier work done before this is merged into one engine is wasted.

**(f) The gate is right but silent, and the review queue is miscounted.** `TxnGuards.isCountable` drops rows from `counted`; nothing anywhere records *that* a row was dropped or why. Architecture decision #7 ("nothing is silently dropped") is therefore violated by the one module whose whole job is to drop things. Meanwhile `needsReview` rows **do** count toward totals (no filter on `needs_review` in `build`), and the review queue is under-populated (20 rows vs 40 merchant-less rows in the real inbox). So an unconfirmed row can be counted, and a rejected row can be invisible.

---

## 2. The option space, costed

Sizes and latencies are estimates for a mid-range 2024–25 Android device unless marked; accuracies are *expected ranges for this task*, not measurements, and §5 says how to get the real number. "Explains itself" means: can the app show the user a human-acceptable reason drawn from the model itself, without a separate explainer.

| | Option | Effort | Artefact | Latency/SMS | Explains itself | Goal 1 | Goal 2 | Verdict |
|---|---|---:|---|---:|---|---|---|---|
| a | Rules + DLT registry (status quo) | 0 to keep, **5 d** to fix | 0 KB | <1 ms | Yes, but post-hoc | Partly (20 % leak on negatives) | No | **Keep as the gate** |
| b | Rules-as-features → logistic regression / linear SVM, weights as JSON, dot product in Dart | **4 d** + 3 d labels | **~1.2 KB** | **~10 µs** | **Best available** (`wᵢxᵢ`) | Indirectly, via the ambiguous middle | No | **Recommended for v2** |
| c | Naive Bayes / hashed 3–5-grams | 4 d | 40–400 KB | ~0.3 ms | Poor (per-gram ε) | Marginally | No | Reject |
| d | Small GBDT (XGBoost/LightGBM → JSON/Dart) | 5 d | 20–80 KB | ~30 µs | Weak (tree paths) | Marginally | No | Defer with a trigger (§7) |
| e | MiniLM/fastText/TFLite or ONNX | 10–15 d | **~23 MB** (MiniLM int8) + tokenizer | 20–80 ms | Poor | No | No | Reject |
| f | On-device LLM (Gemini Nano, or bundled 1–2 B) | 15 d+, or blocked | 0.3–1.5 GB | 2–8 s | Fluent, unverifiable, non-deterministic | No | No | **Never, for this** |
| g | Hybrid gate → arbiter → review, + on-device learning | 5 d + 12 d | as b | as b | Yes | **Yes** | Yes (with §6 ledger) | **The plan** |

### 2.a Pure rules + DLT sender registry (status quo)

**Where it fails:** §1.2. Specifically, three structural gaps rather than missing words:

1. **No assertion semantics.** "Money moved" is a bag of verbs; there is no distinction between an event, an availability ("loan available"), a conditional ("on your next payment of"), a future ("will be debited on 5 Nov"), and a request ("has requested ₹"). Every one of those can satisfy the current scorer.
2. **Trust is a scalar, not a posterior.** `SenderRegistry` returns `known | plausible | suspicious` from a hand list. 36 senders were observed on the real device; 7 DLT prefixes and ~20 entity codes were missing, so real bank alerts fall to `plausible` and *lose* 2–3 points — the registry is a silent accuracy tax on the very messages that matter. It also conflates merchant-side senders (`SWIGGY`, `ZEPTON`, `FLPKRT`) with banks, which is how "your order is confirmed" becomes a spend.
3. **Nothing is versioned or measurable.** The signal weights are literals in Dart; there is no held-out set, no per-family scoreboard, and no way to answer "is this release better than last?" other than the fixture count.

**What it is genuinely good at:** DLT structure is a real, offline, hard-to-spoof signal (§1 of `02-spam-and-phishing.md`), the parse of amounts is well-tested, and the weighted-signal architecture is *already the right shape* for an explainable model. Do not throw it away; make it the feature extractor.

**Cost to fix the parts that matter: 5 days.** That is the v1 in §4.

### 2.b Rules as features → logistic regression / linear SVM, JSON weights, Dart inference

**What it is.** Take the ~45 features the classifier already computes (signal booleans, sender trust one-hot, DLT category one-hot, amount presence and magnitude, link count, domain-matches-entity, imperative credential ask, negation of "share", availability/conditional mood markers, balance/limit presence, OTP present, digit-run length, reference present, VPA present) and fit a multinomial logistic regression offline. Ship `w` and `b` as JSON. Inference is `argmax_c (b_c + Σ w_cf x_f)` and a softmax.

- **Accuracy.** At ~2,000 real labelled messages over ~45 mostly high-precision features, expect macro-F1 **0.88–0.94** on a real held-out inbox (estimate). The ceiling is *not* model capacity: it is label noise plus upstream parser errors — a message whose amount is mis-parsed is wrong regardless of its class. This is the reason to expect the LR to plateau early, and the reason a bigger model buys little.
- **Why linear and not an SVM.** A linear SVM gives a decision function, not a calibrated probability, and the entire design in §3.4 depends on thresholds over probabilities with an asymmetric cost matrix. Use `LogisticRegression` with `class_weight='balanced'` plus Platt/isotonic calibration, and keep `LinearSVC` only as a comparison row.
- **Size.** 45 features × 6 classes + 6 biases ≈ 276 float64 → **~1.2 KB** of JSON, or ~600 B compacted. This is not a rounding error in the APK; it is nothing.
- **Latency.** 276 multiply-adds plus a softmax: **~10 µs**, on top of feature extraction you already do. Per-scan: a 3,000-message inbox adds <50 ms.
- **Explainability.** Best of any option, and it is *free*: `w_f · x_f` is a per-feature contribution in the same currency as the existing `SmsSignal` list, so the UI copy barely changes ("we booked this because *assertion: debited* (+1.8) and *balance present* (+1.1); we did not count it because *availability: loan* (−2.4)"). No SHAP library, no kernel, no approximation.
- **Toolchain.** scikit-learn → `json.dump({"schemaVersion":1,"features":[...],"w":[[...]],"b":[...]})`. No native code, no plugin, no NDK, no FFI. If you ever want the model compiled rather than data, `m2cgen` emits Dart directly from `LogisticRegression`/`LinearSVC`/`LGBMClassifier`/`XGBClassifier` ([m2cgen README](https://github.com/BayesWitnesses/m2cgen)) — but prefer JSON, because it keeps the weights inspectable, diffable in review, and updatable without touching Dart.
- **The real cost is the labels** (§3), not the code.

**Verdict: yes, for v2, as an arbiter — not as the gate.**

### 2.c Naive Bayes / hashed character n-grams

**What it is.** Hash 3–5-grams into 2¹⁶ buckets, count, `argmax` over classes. Tiny, fast, no feature engineering, famously strong on the UCI SMS Spam Collection ([UCI 228](https://archive.ics.uci.edu/dataset/228/sms+spam+collection), 5,574 messages, CC BY 4.0) where ham and spam are *lexically disjoint* (one says "claim your reward", the other "see you at 6").

**Why the UCI numbers do not transfer.** Our classes are not disjoint. Compare `Your a/c XX1234 debited by Rs 2,000. Avl Bal Rs 41,220` with `Get up to ₹2,000 cashback on your next payment`. They share the amount, the verb, the sender, the length. The discriminative signal is *mood and completeness* (does it state a balance? is the figure an upper bound?), which is nearly absent from n-gram counts and is exactly what a hand-built feature captures.

**Why it is worse than LR here, specifically:**
1. **Calibration.** NB's independence assumption is badly violated by templated SMS; posterior probabilities saturate near 0/1 and are unusable for a cost matrix. You then calibrate — and calibrated n-gram NB ≈ an LR over n-gram features, i.e. option (b) with 20,000 features instead of 45 and 2,000 labels instead of 20,000. At this label count it overfits to each bank's rendering.
2. **Explainability.** "The 4-gram `ebit` contributed +0.02" is not a sentence a user accepts as a reason their rent was booked. This product's stated differentiator (architecture §5) is that every decision can be interrogated.
3. **It solves the wrong problem.** Its one real strength — vocabulary it has never seen — is better served by the assertion grammar and a 20-word keyword list, which you can read and audit.

**Expected accuracy:** 0.80–0.90 macro-F1 (estimate). **Artefact:** 2¹⁶ × 6 × float32 = 1.5 MB naive, 40–400 KB quantised; small but 300× the LR. **Effort:** 4 days, of which 2 are calibration and evaluation — the same evaluation burden as (b), for a worse explanation and worse fit.

**Verdict: reject.** Keep hashed n-grams in the back pocket as a *novelty* detector ("this message shares no features with anything the model has seen") — that is a legitimate unsupervised use and costs half a day later if the shadow log shows template drift.

### 2.d Small gradient-boosted trees

**What it is.** ~100 trees, depth 3, JSON export, or Dart codegen via `m2cgen` (which supports `XGBClassifier` and `LGBMClassifier` → Dart).

- **Size/latency:** 100 × 8 leaves × ~4 numbers ≈ 20–80 KB JSON; ~30 µs. Both fine.
- **Where it would win:** interactions the linear model must be *given* — e.g. "a known bank sender AND an imperative credential ask AND the link domain is not the issuer's" is a 3-way interaction. But note: in this codebase those are already hand-written predicates. A GBDT relearns them from data, and with 2,000 rows and 45 features it will mostly relearn the hand rules plus noise.
- **Explainability:** tree paths are readable in principle ("if `dlt_category=P` and `has_amount` then…") — but by the time the user reads a 100-tree path, you have reinvented a rule engine with worse provenance. SHAP over 100 trees in Dart is possible and pointless.
- **Data requirement:** GBDTs want 10⁴–10⁵ rows to beat a well-featured linear model. Expect a gain of ≤1 point of macro-F1 (estimate) at 2,000 labels, and a much harder debugging story when it goes wrong on a new bank.

**Verdict: defer with an explicit trigger (§7). It is the right model for a different phase of this product, not for this one.**

### 2.e Tiny transformer / embedding model

**What it is.** Fine-tune a small encoder (MiniLM-L6 = **22.7 M parameters**, 384-dim — the model card ships a `qint8_arm64` ONNX build, i.e. ~23 MB int8, plus a ~230 KB WordPiece vocab) and run it via TFLite or ONNX Runtime; or train fastText embeddings and classify over them.

**The costs, concretely:**
- **Size:** ~23 MB of model + tokenizer + a 1–3 MB native runtime per ABI. The app currently has **no ML dependency at all** and no `assets/` section in `pubspec.yaml`; the only APK in `build/` is a 155.7 MB *debug* build, so there is no measured release baseline to grow from — but adding 25 MB for a 4-class decision over a 160-character string is a 10–100× artefact increase for a task where the discriminative tokens are hand-known.
- **Latency:** ~20–80 ms per short sequence on a mid-range ARM with int8 (estimate), plus tokenisation. A 3,000-message scan becomes 1–4 minutes. The SMS-received path wants <10 ms. You would have to background it, which reintroduces the "notification shows a guess, ledger settles later" split that architecture §1 deliberately removed.
- **Toolchain pain, measured:** `tflite_flutter` is at **0.12.1, published 12 months ago**, its README still describes the project as "a work-in-progress", the helper library is **deprecated**, and Android needs **API ≥ 26** plus a bundled TFLite C library and `IsolateInterpreter` for non-blocking inference ([pub.dev](https://pub.dev/packages/tflite_flutter)). ONNX Runtime Flutter packages are community-maintained and thinner. That is a permanent maintenance tax on a 3-person team, for a dependency that your `flutter test` suite cannot exercise without native binaries — i.e. **host-side unit tests of the classifier would stop working**, which is a real regression against the repo's current "engines are pure functions, unit tested" discipline.
- **Accuracy:** at 2,000 labels you will *tie* with the 45-feature LR; it needs ~5–10 k labels to beat it (estimate), and you do not have 5–10 k labels. Frozen-encoder + LR needs fewer labels but brings its own problem: MiniLM's vocabulary is general English, so `Avl Lmt`, `trf to`, `UPI Refno`, `XX742` get shredded into word-pieces — destroying precisely the tokens that carry this task's signal.
- **Explainability:** you would need SHAP over 384 embedding dims, or attention weights (unavailable after TFLite/ONNX export). For an explainability-first product this is a downgrade, not an upgrade.

**Verdict: reject.** This is fashion for this task. It is the right call when the input is natural language with open vocabulary and you have ≥10 k labels; ours is templated, closed-vocabulary, and has 2 k labels at best.

### 2.f LLM on-device

**Gemini Nano via ML Kit GenAI / AICore.** Three facts from Google's own support table ([ML Kit GenAI overview](https://developers.google.com/ml-kit/genai), fetched 2026-10-25) kill it for this app:

1. **The device list contains no mid-range Indian phone.** It is Pixel 9/10/11, Galaxy S25/S26/Z, OnePlus 13/15, Find X8/X9, Xiaomi 14T Pro/15/17, iQOO 13/15, realme GT 7 Pro/7T, POCO F7 Ultra/F8/X7 Pro. No Redmi Note, no Realme Narzo/C-series, no Poco M, no Galaxy A/M, no Moto G — i.e. none of the volume segment this product must serve. The app's own test device is a Galaxy S24, which is not on the Prompt API list either (S25 and up).
2. **Inference is permitted only while the app is the top foreground application** — "using a foreground service" is explicitly not allowed, and the API returns `BACKGROUND_USE_BLOCKED`. The product's core event is an SMS arriving in the background. Fatal on its own.
3. **AICore enforces a per-app inference quota** (`BUSY`, `PER_APP_BATTERY_USE_QUOTA_EXCEEDED`). A one-time 2,000-message inbox scan is exactly the workload that trips it.

**Bundled 1–2 B model (Gemma-class, int4).** 0.3–1.5 GB of weights, 0.5–1 GB of RAM, 5–20 tok/s on a mid-range phone. One message with a ~300-token prompt and a 20-token answer is **2–8 s** (arithmetic from the token rate, not a measurement). A 2,000-message scan is *hours* and a flat battery. Play's size limits force Play Asset Delivery for anything in this class ([Play size limits](https://support.google.com/googleplay/android-developer/answer/9859372), [App Bundles](https://developer.android.com/guide/app-bundle)), which means a download — the opposite of "ships in the APK, no network". And an LLM's output is non-deterministic by nature: it cannot be pinned by a golden test, which means it cannot be the thing that decides whether ₹1,11,510 is booked.

**Where an LLM genuinely belongs in this project: on the laptop, offline, once.** Use a frontier model to (i) pre-label the 2,000-message corpus for human review (huge time saver — cut the 3-day labelling budget to ~1.5), (ii) generate *hard negatives* ("write 200 Indian bank promo SMS that contain a rupee amount and a debit verb but no money movement"), (iii) mine candidate rules from misclassifications. Zero runtime cost, zero privacy surface, and it attacks the actual bottleneck, which is labels. **This is the only LLM recommendation in this memo.**

**Verdict: never, at runtime.** Not "not yet" — the foreground-only constraint is architectural, not a temporary limitation.

### 2.g Hybrid: rules gate → model arbiter → review queue, with on-device learning

This is the recommendation, and it is not a compromise. Each layer is doing a job the others cannot:

```
SMS ──► hard gates (deterministic, auditable, zero false positives by construction)
        ├─ OTP / credential-ask family        → informational (never booked, never "phishing")
        ├─ explicit promo / availability / conditional / future  → promo (never booked)
        ├─ UPI collect request                → informational
        └─ assertion + arithmetic confirmation → CONFIRMED (counted, no review)
                    │
                    ▼
        arbiter (logistic regression over the same features) → p(class), thresholded by cost
                    │
        ┌───────────┴────────────┐
        ▼                        ▼
  ASSERTED (0.5≤p<0.95)     REJECTED (p<0.5)
  row created, NOT counted   no row; shown in diagnostics
  until the user confirms    with the vetoing reason
```

The gate is fast, boring, and safe. The arbiter earns its keep only on the residual — the messages where the grammar is silent and the wording is genuinely ambiguous. And the third layer is the loop, which is where this design beats every alternative in §2: **a correction is a label, and a label that never leaves the phone is free data.** §3.3 designs that loop concretely, and it is the only "learning" that is feasible offline (no trainer ships in an APK).

---

## 3. The data question

This decides everything, so it gets the bluntest answer in the memo.

### 3.1 Is there a usable labelled corpus? No.

| Corpus | Licence | Size | Label schema | Transactional bank SMS? |
|---|---|---:|---|---|
| [`gandharvbakshi/SMS-dataset-sample-10k`](https://huggingface.co/datasets/gandharvbakshi/SMS-dataset-sample-10k) | MIT (dataset card) | 10,000 rows, CSV, ~1 MB | `predicted_is_otp` (bool), `predicted_otp_intent` (9 values), `is_phishing_original` (bool), `classification_status`, `sender` (often null) | **Text: yes, genuinely.** **Labels: no.** There is no amount, direction, kind or instrument field at all. |
| [`gandharvbakshi/SMS-dataset-OTP-OTP_INTENT_Phishing`](https://huggingface.co/datasets/gandharvbakshi/SMS-dataset-OTP-OTP_INTENT_Phishing) | MIT, **gated (manual approval)** | 73,470 rows | same | Same gap, at 7× the size. Still no transaction labels. |
| [UCI SMS Spam Collection](https://archive.ics.uci.edu/dataset/228/sms+spam+collection) | **CC BY 4.0** | 5,574 (4,827 ham, 747 spam) | `ham` / `spam` | **No.** UK Grumbletext spam + NUS/Singapore student ham + Caroline Tagg's thesis. Zero Indian bank alerts. |
| Kaggle mirrors of the above | varies, often unstated | 1–20 k | `spam`/`ham` | Re-uploads of the same inbox dump with the same missing labels; licence cannot be verified per-file, so do not build on them. |
| Vendor parser demos (Dibba et al.) | vendor terms | ~5 samples | none | Useful as *templates* (already cited as tier V in `01-sms-corpus.md`), not as data. |

**Verdict: there is no public labelled corpus of Indian transactional bank SMS, and there is unlikely to be one, because the labels are the private part.** Labelling "did ₹2,000 move" requires reading someone's actual bank alerts, which is exactly what nobody publishes.

But the public data is *not* worthless — it is just not a label source:

1. **Unlabelled text for template mining and hard negatives.** The 10 k dump contains genuine alert text — in the first 100 rows alone I found ICICI card debits, an SBI UPI credit, an Amex `**91009` spend, a FASTag toll debit, an ICICI standing-instruction notice and an Amazon Pay balance alert. Examples: `INR 366.19 spent on ICICI Bank Card XX2815 … Avl Lmt: INR 4,33,288.04`; `Rs 87.38 credited to account XXXXX1710 of SBIN … Info: UPI/P2A/…`; `Alert: You've spent INR 204.35 on your AMEX card **91009 at PAYU ZOMATO`. These are gold for *parsing*, and they are already the source of tier-O rows in `01-sms-corpus.md`.
2. **The `is_phishing_original` column is noise and must not be trusted.** Sampled rows: a Practo appointment reminder = `true`; a real ICICI debit alert (`Acct XXX702 debited with INR42.97 … bhartpe…cred`) = `true`; the string `"girls waiting"` = `true`; a legitimate ICICI credit = `false`. The column appears to encode "not from a recognised sender", not "fraud". Training a phishing head on it would teach the model to flag your bank.
3. **`sender` is null on the majority of rows**, so the single most predictive feature in the real system is unavailable for most of the public text.

**Implication for architecture:** the supervised ceiling is set by how many messages *you* label, not by which model you pick. That is why (b) — 45 hand-built features, 2 k labels — beats (e) — 22.7 M learned parameters, same 2 k labels. It is also why v2's critical path is a labelling sprint, not a modelling sprint.

### 3.2 Synthetic augmentation from the 180 fixtures — useful, and dangerous

The repo has 180 fixtures (`test/fixtures/sms_corpus.dart` 103 + `spam_corpus.dart` 77: fraud 23, tx 18, promo 14, info 14, otp 8).

**As a regression suite: excellent, keep expanding.** Every real-inbox failure in `real-data-findings.md` §A/§B should become a fixture. That is how §1.1's 43.1 % gets fixed.

**As training data: it will produce a model that passes the fixtures and fails the inbox.** Four specific mechanisms:

1. **Template leakage.** 180 fixtures are ~180 template *clusters*, not 180 independent samples. A random row split puts `Spent INR … on 12-06-26 at WWW AMAZON` in train and the same template with a different amount in test → 99 % test accuracy, 70 % in production. **Any split must be grouped by (bank, template family), never by row.**
2. **Provenance tiers.** `01-sms-corpus.md` tags every row O (observed), V (vendor demo), I (inferred). Roughly 40 % of the corpus is tier I — *hypotheses about what banks might say*. Fitting weights on inferred templates is fitting fiction.
3. **The generator's fingerprints become features.** If you synthesise 10 k rows by slot-filling amounts/dates, the model can learn "amount is a round number ⇒ synthetic ⇒ whatever label I gave it". Lexical giveaways (no OCR noise, no truncation at 160 chars, no Devanagari/Tamil mixed in, no missing spaces after `Rs.`) are strong enough to fit.
4. **Balanced synthesis destroys the prior.** Real inboxes are, by estimate, ~55 % OTP/logistics/personal, ~20 % promo, ~10 % informational bank, ~3 % transaction, ~2 % fraud. A synthetic set that is 25 % per class teaches a model whose thresholds are wrong for the real base rate — and the base rate is what makes precision collapse in production.

**Allowed use:** synthetic data may test the **gate's specificity** (does the gate reject 100 % of the 200 promos I generated?) and may generate **hard negatives for human review**, never fitted weights. If a synthetic row is good enough to train on, promote it to a hand-verified fixture with a real inbox message behind it.

**Target corpus for v2: 2,000 hand-labelled real messages** from ≥3 inboxes (owner + 2 consented volunteers), stratified per §5.1, with ≥300 promos, ≥250 informational, ≥150 phishing (or as many as exist), ≥600 genuine movements. That is ~10–15 hours of labelling with a good tool (≈12–15 min per 50 messages), or ~6 hours if a frontier LLM pre-labels and a human corrects.

### 3.3 Active learning in production — what is actually possible offline

A correction is a label. But an APK cannot retrain a model, so be precise about *what can be learned on-device*:

**(i) Merchant/category rules — wire the table that already exists but is never written.** `AppDatabase` creates `merchant_rules(pattern, category_name, category_kind, hits)` and the only reference anywhere in `lib/` is `db.delete('merchant_rules')` in `clearAll`. So the schema exists and nothing uses it. Wire it: a user fixing `Pluxee Meal → Food` upserts the normalised merchant key and applies to all 24 existing rows plus all future ones. **0.5 day, and it is the learning the user can see.** This is also the cheapest possible "active learning" and it has nothing to do with classifiers.

**(ii) Per-sender trust as a Beta posterior — the one real online model.** For each normalised sender: `α = confirmed_txns + 1`, `β = rejected_or_reclassified + 1`, `trust = α/(α+β)`. Update on every user confirmation/rejection and every gate rejection. This replaces the three-valued hand enum with something that starts neutral, converges within ~5 messages, is trivially explainable ("you have confirmed 12 of 12 from `VM-HDFCBK`"), and *cannot* silently drift into accusing a bank — it's a count, not a model. ~1 day. This is the correct answer to "active learning on a phone".

**(iii) Per-user threshold nudges, not per-user weights.** Allow exactly one tuned scalar per install: the confirmed/asserted threshold, bounded to [0.9, 0.99], moved by at most ±0.02 per user correction and stored in `app_meta`. Two parameters, bounded, auditable. Do **not** fit 45 weights on-device: with 50 corrections in 6 months you would fit noise, and you would lose the ability to reproduce any decision.

**(iv) Opt-in export: features, never text. Default off.** If you ever want the corrections off the phone, export `{feature_json, label, app_version, model_version}` — never the SMS body, never the sender, never an amount. The user triggers it through the share sheet; there is no server, no upload, no telemetry SDK. Under DPDP this keeps processing local and avoids any data-fiduciary transfer (`02-spam-and-phishing.md` §DPDP already argues this). **My recommendation: never ship the export.** Ship better global weights in the next APK, fitted on the corpus the team labelled — the install base is small enough that one person's 50 corrections will not move a global weight anyway, and the privacy promise is worth more than 50 rows.

### 3.4 Imbalance, cost matrix, and concrete thresholds

Base rates (per 1,000 messages; **estimates** from the shape of the real-inbox sample, to be replaced by the §5.1 corpus): ~550 OTP/logistics/personal, ~200 promo, ~100 informational bank, ~30 genuine movement, ~20 fraud, rest unclassified. So genuine movement is ~3 % of the inbox and fraud ~2 %. At those priors, a 95 %-accurate classifier is *useless* for the positive class: 5 % of 970 negatives is 48 false positives against 28 true positives.

The costs are asymmetric in the direction that matters to the owner, and the magnitude of the asymmetry is set by **amounts**, not counts:

| Error | Real cost | Weight (relative) |
|---|---|---|
| Promo booked as spend | The month's total is wrong by the offer's nominal amount (₹36,000 loan offer, ₹1,00,000 limit, ₹1,11,510 hotel that was actually corporate-billed). On a ₹60,000 month that is a 60 % misstatement, and the user's trust in every other number dies with it. | **20×** |
| Real spend missed | Understates by the true amount; recoverable via the review queue; visible as "uncertain". | 1× |
| False phishing warning | Directly contradicts the owner's stated trust concern; the repo's own target is "better to miss a scam than to cry wolf" (`real-data-findings.md` §E). | **10×** |
| Missed phishing | Bad, but the loss is the user's own bank app's job to catch, not ours. | 1× |

Bayes thresholds, `p* = c_FN / (c_FP + c_FN)`:

- **Booking:** `p* = 1/(20+1) ≈ 0.048`. Nowhere near usable as a single cut — it would book almost everything. The resolution is **not** to move the threshold but to split the decision into three tiers where the top tier has ~zero error by construction:

| Tier | Rule | Counts toward spend? | UI |
|---|---|---|---|
| **CONFIRMED** | Gate predicate passes **and** arithmetic reconciles (`balance_before − amount == balance_after`, or `limit_before − amount == limit_after`, tolerance ±₹1) | **Yes** | normal row, confidence "confirmed by balance" |
| **CONFIRMED-LEXICAL** | Gate passes, no balance available, `p(spend) ≥ 0.95`, no offer/conditional/availability marker | **Yes** | normal row, confidence "matched bank alert" |
| **ASSERTED** | Gate passes, `0.50 ≤ p(spend) < 0.95` | **No** — shown as "unconfirmed ₹X", `needs_review = 1` | one-tap confirm → becomes CONFIRMED, and updates the sender posterior |
| **REJECTED** | `p(spend) < 0.50` or a veto fires | **No** | only visible in Settings › Diagnostics, with the vetoing reason |

  This is the single change that delivers goal 1. It converts the ambiguous middle from "counted, possibly wrong" into "visible, not counted, one tap to fix" — which is exactly what "never count spam as spend" means in practice, and it costs nothing in modelling.

- **Phishing:** never a bare threshold. Warn only if `p(phish) ≥ 0.80` **and** at least one decisive predicate fires: (i) an *imperative, second-person, non-negated* credential ask; (ii) pressure/urgency AND a link whose registrable domain does not match the sender's entity; (iii) a payment instruction (UPI ID / QR / "pay ₹X to release") from a non-registry sender; (iv) a known scam template. Acceptance bar: **≤1 false warning per 1,000 messages**, precision ≥0.90 on the sampled set (matching §E's target). Today: ~70 flagged per 1,000, of which roughly 50 are false.
- **Informational:** no cost asymmetry (nothing is booked or accused), so optimise F1 and don't be clever. The 7.7 % recall in §1.2 is a bug, not a threshold.

---

## 4. Recommended path, in days

### v1 — this week (5 working days)

The goal is not a model. The goal is **zero promos in the totals and full visibility of what was rejected.**

| Day | Work | Done when |
|---|---|---|
| 0.5 | **Measure balance coverage.** Export `sms_messages` to CSV (a `tool/` CLI), run the existing `AmountFinder` over it, count messages with `balanceAfter` / `availableLimit`, split by (bank, has-debit-verb). Also count how many of the 180 fixture rows would be CONFIRMED by arithmetic. | One number, plus a per-bank breakdown. This number sets the v2 threshold policy. |
| 1.0 | **`lib/services/sms/assertion.dart` — one canonical assertion grammar.** Predicates: `assertsMovement` (event verbs, *past tense / participial*: debited, spent, paid, credited, withdrawn, transferred), `assertsAvailability` (available, eligible, up to, limit of, pre-approved), `assertsConditional` (on your next, if you, when you, valid till, will be debited on, due by), `assertsRequest` (has requested, collect request, approve), `assertsNegation` (`never/do not share`), `assertsCredentialAsk` (imperative + second person, **negation-aware, used by every rule that mentions credentials**). **`SmsClassifier`, `TxnGuards` and `TransactionExtractor` all import this and nothing else.** This deletes *three* independent definitions of "money moved": `SmsClassifier._debitVerb`/`_creditVerb`, `TxnGuards._moneyMoved`, and `SmsGuards._moneyMoved` (plus `TxnGuards._offer`'s verb logic and `_phishCta`'s ungated `share otp`). | One definition of "money moved" in the codebase; a unit test per predicate. |
| 0.5 | **Threshold shape.** `genuineTransaction` requires `assertsMovement && !assertsAvailability && !assertsConditional`. Add the `not_moved_yet` veto ahead of the `genuineTransaction` branch (fixes the 7.7 % informational recall). | The `loan available for ₹36,000` and `get up to 5% cashback on your next payment of Rs 2,000` families cannot be classed `transaction`; the 25 negative fixtures go 25/25. |
| 1.0 | **DLT registry refresh** from `real-data-findings.md` §D2: 7 missing prefixes, ~20 missing entities, and a new `entityKind` distinction so merchant-side senders (`SWIGGY`, `ZEPTON`, `FLPKRT`, `BLNKIT`, `JIOHTT`, `CDMILK`) resolve to a *merchant* kind that does **not** get the bank trust bonus. | Every sender in the real-inbox list resolves to `known` with the right kind; `CBSSBI` (30 txns!) no longer scores `plausible`. |
| 1.0 | **Tiered admission + review accounting.** CONFIRMED / CONFIRMED-LEXICAL / ASSERTED / REJECTED from §3.4. `needsReview` rows excluded from `spend` totals (shown as "unconfirmed ₹X"); `TxnGuards` writes a `classifier_diagnostics` row (sms_id, gate, reason, feature contributions) instead of silently dropping. | A rejected promo is visible in Settings › Diagnostics; an asserted row never moves the month's total until confirmed. |
| 1.0 | **Phishing predicates.** Route `_phishCta` through `assertsCredentialAsk` so "never share OTP" cannot score as a lure from a second regex; make domain-vs-entity trust *supportive* when the host matches the sender's entity, not only a penalty when it doesn't; require an intent predicate before the `phish >= 4` branch can fire. One unit test per fraud family. | The 4 OTP fixtures and the RBI-KYC advisory stop being flagged; fraud recall does not regress below 20/22. |

**v1.1 (days 6–7, not this week):** balance-delta reconciliation (a `balance_ledger` in `app_meta`, per account/card, updated from every confirmed alert) and a **statement reconciliation report**: `Σ spend(card, cycle)` vs `card_bills.total_due`. That report is the only offline ground truth you will ever get for free, and it measures exactly what the owner cares about — rupees, not F1.

### v2 — this month (12 working days)

| Days | Work |
|---|---|
| 3.0 | **Label 2,000 real messages** from 3 inboxes (§5.1). LLM pre-labels, human corrects. This is the critical path; start it on day 1 of v2 because it blocks everything. |
| 1.0 | **`tool/label.dart`** — a CLI that renders one message at a time, shows the current prediction + gate reason, and writes a CSV. Labelling speed is the whole game; a bad tool doubles the 3 days. |
| 1.5 | **Features + LR.** Export the ~45 features from the Dart classifier so train and serve share one definition (a CSV dump from a Dart test, not a re-implementation in Python — this is where train/serve drift is born). Fit `LogisticRegression` with `class_weight='balanced'`, calibrate (isotonic, cross-fitted), and run the ablation: which of the 45 features earn their place. |
| 1.5 | **Dart model + golden tests.** `admission_model.dart`, JSON weights, softmax, thresholds; golden file generated by the Python trainer, asserted to 1e-9 on 380 messages (§6.3). |
| 2.0 | **Shadow mode + diagnostics UI + CSV export** (§6.4). |
| 1.0 | **Evaluation on the locked holdout**, against the acceptance bars in §5.4. Written report; ship only if it clears. |
| 2.0 | Buffer. There is always a bank that breaks something. |

### Explicitly not building (with the reason, so it stays closed)

| Not building | Why | Revisit when |
|---|---|---|
| On-device LLM (Nano or bundled) | Foreground-only inference, absent from the target device list, per-app quota, 0.3–1.5 GB, non-deterministic (§2.f) | Never for per-message classification. |
| Transformer / TFLite / ONNX | 25 MB and a deprecated plugin to tie with a 1.2 KB LR; kills host-side unit tests (§2.e) | ≥10 k labels **and** a maintained Flutter runtime under 10 MB. |
| GBDT | ≤1 point over LR at this label count, worse explanations (§2.d) | ≥20 k labels, or ablation shows the residual error is interaction-shaped. |
| Character n-grams / NB | Uncalibrated, unexplainable, solves the wrong problem (§2.c) | As a *novelty* detector only, if the shadow log shows template drift. |
| On-device training / federated learning | No trainer in an APK; 50 corrections cannot fit 45 weights; loses reproducibility | Never at this scale. |
| Uploading corrections to a server | Contradicts the offline privacy promise for ~50 rows of marginal value | Never without an explicit product decision to become a data fiduciary. |
| Per-user model weights | Unfalsifiable, unsupportable, and a support nightmare ("why did it book my rent?") | Never. Per-user *thresholds* and *sender posteriors* only. |

---

## 5. Evaluation protocol

### 5.1 The held-out set

- **Source:** 3 real inboxes (owner + 2 consented volunteers on different handsets/banks), 1,500–2,000 messages each, exported through the app's own CSV path so the pipeline is identical to production.
- **Sampling:** take **100 % of messages from `-T`/`-S` DLT headers and all numeric senders**, plus a **random 20 %** of everything else. Do not sample uniformly: promos and personal messages dominate by volume and would swamp the classes that matter.
- **Stratification target:** ≥600 genuine movements (spend/transfer/income, with ≥100 transfers and ≥60 income), ≥300 promos, ≥250 informational, ≥150 phishing if it exists (top up with the 22 fraud fixtures and public scam corpora, clearly tagged `synthetic`), ≥300 hard negatives that contain an amount but no movement.
- **Lock three slices before fitting anything** and never train on them: (i) 300 messages from a fourth phone (different banks — the generalisation test), (ii) all 60 "promo with a rupee amount and a debit verb" cases (the false-positive engine), (iii) 40 OTPs and 40 legitimate warnings (`never share`, `beware of`, RBI advisories).
- **Fixtures are a regression suite, not a validation set.** Rule: no tuning against fixture IDs. If a fixture and the holdout disagree, the holdout wins and the fixture is corrected — otherwise you are optimising the test.

### 5.2 Metrics that match the two goals

Per class (transaction/spend, transfer, income, informational, promo, phishing): precision, recall, F1, plus **PR-AUC for spend** (accuracy is meaningless at a 3 % base rate).

Then the three that actually decide the ship:

1. **Spend-weighted precision (SWP)** — the headline number:
   ```
   SWP = Σ_{i ∈ correctly booked spend} amount_i  /  Σ_{i ∈ all booked spend} amount_i
   ```
   Rupee-weighted, not row-weighted. A wrong ₹1,11,510 costs 2,800× a wrong ₹40; row-counting hides that exactly. Target **≥ 0.99** (≤1 % of booked rupees are false).
2. **Rupee error per month (RWE)** — `|Σ counted − Σ true| / Σ true`, computed from the labelled month and, independently, from statement reconciliation (`card_bills.total_due`). Target **≤ 2 %**, and **≤1 % for two consecutive statement cycles** on real data.
3. **Double-count rate (DCR)** — rupees present in more than one counted row / total counted rupees, measured by paired fixtures *and* by the balance ledger (two rows cannot both explain the same balance delta). Target **0**.

Plus two UX numbers that are really trust metrics:
- **False phishing warnings per 1,000 messages**, target **≤ 1** (today ~70 flags per 1,000, of which roughly 50 are false).
- **"Other"-category share of rupees**, target <10 % (today 31 % of rows, ₹8.44 L — `real-data-findings.md`).

### 5.3 Preventing overfitting to the fixtures

1. **Group splits by (bank × template family)**, computed by clustering message skeletons (digits/punct masked) — never a random row split. Report the group count so the split can be audited.
2. **Template-family coverage curve:** accuracy as a function of *number of unseen families*, on the fourth-phone slice. A model that scores 0.95 at 0 unseen families and 0.62 at 20 has learned templates, not transactions. Publish this curve, not just one number.
3. **Provenance masking:** strip tier-I synthetic rows from training entirely; keep them in the gate-specificity test only.
4. **One model, one number, one file.** The trainer writes `test/fixtures/model_golden.json` (message id → expected probabilities) and CI asserts the Dart implementation reproduces it. If someone tweaks a feature definition, the golden test fails — which is the point.
5. **Report confidence intervals.** With 300 promos, a 3 % false-positive rate is ±2 points; do not write "99 % accurate" anywhere.

### 5.4 Acceptance bars for shipping the arbiter

Ship only if, on the locked holdout: SWP ≥ 0.99 · spend recall ≥ 0.90 rows and ≥ 0.95 rupees · informational F1 ≥ 0.85 · phishing precision ≥ 0.90 with ≤1 false warning/1,000 · DCR = 0 · and **no regression on the 180 fixtures**. If the LR fails but the v1 gate passes, ship v1 and keep the LR in shadow — that is a perfectly good outcome and it is why the gate comes first.

---

## 6. Dart-side engineering (for the recommended option)

### 6.1 Where things live

```
lib/services/sms/
  assertion.dart          # predicates: movement | availability | conditional | request | negation
  admission.dart          # gate: tier decision (confirmed | asserted | rejected) + reasons
  admission_model.dart    # NEW: LR weights, dot product, softmax, thresholds  (~120 lines, pure Dart)
  sms_classifier.dart     # orchestrates: signals → gate → model → SmsAssessment
lib/engine/
  txn_guards.dart         # becomes a thin caller of assertion.dart; keeps the display-time backstop
  balance_ledger.dart     # NEW: per-account last-known balance, arithmetic confirmation
assets/model/
  admission.v1.json       # ~1.2 KB, no assets section exists today
```

Everything stays **pure Dart with no plugins**, so `flutter test` keeps running on the host and the classifier keeps the same testing discipline as the engines. This is a hard constraint, not a preference: an FFI/TFLite path would make the model untestable in CI, and an untestable admitter is a bug factory.

### 6.2 The weights file and loading

```jsonc
{
  "schemaVersion": 1,
  "trainedAt": "2026-11-14",
  "corpus": { "rows": 2000, "inboxes": 3 },
  "features": ["has_asserted_movement", "has_availability", "..."],   // ORDER IS THE CONTRACT
  "classes":   ["spend", "transfer", "income", "informational", "promo", "phishing"],
  "w": [[0.0, 2.31, -1.04, "..."], ["..."]],   // classes × features
  "b": [0.0, -0.42, "..."],
  "thresholds": { "confirm": 0.95, "assert": 0.50, "phish": 0.80 }
}
```

- Load once, before `runApp`, in `AppState.init`: `AdmissionModel.load()` from `rootBundle`. Cache the parsed object.
- **Fail closed, not open:** if the asset is missing, the schema version is unknown, or the feature-list hash does not match the compiled `FeatureVector` order, log to diagnostics and run **rules-only with everything unconfirmed going to ASSERTED**. Never fall back to "book it". A missing model must never silently start counting things.
- Pin the asset's SHA-256 in a Dart constant and assert it in a test. It is 1.2 KB; there is no reason not to.

### 6.3 Determinism and testability

- **No `hashCode`, no `Map` iteration order, no locale, no `DateTime.now()`** inside the model. Feature vector is a `List<double>` built in the declared order.
- **Train/serve parity by construction:** the training CSV is generated *by a Dart test* that walks the corpus and emits the feature vector, so the Python fitter never re-implements a feature. If a feature changes, the golden file changes in the same commit and the diff is reviewable.
- **Golden test:** `test/fixtures/model_golden.json` holds 380 (message id → [p_spend, p_transfer, …, p_phish]) produced by scikit-learn; the Dart test asserts max abs error **< 1e-9**. Also assert the *tier* for all 180 fixtures and the 25 negatives.
- **Explanation string from the model itself:** sort `w_f·x_f` descending, take the top 2 positive and top 1 negative, render as the existing `SmsSignal` chips. That is why `SmsAssessment.signals` does not need to change shape.

### 6.4 A/B on-device, with no backend

Be honest about what is possible: **with no telemetry you cannot run a statistically meaningful A/B.** What you can do is a deterministic split plus a paired shadow log, and compare by hand or by exported CSV on a handful of phones.

- **Flag:** `app_meta['classifier_mode'] ∈ {rules, shadow, model}`, assigned once at first launch from `fnv1a64(installId) % 100` (reuse `lib/domain/hashing.dart`), so assignment is stable, local, and reproducible. Settings › Diagnostics can override it (debug builds only).
- **Shadow log — features, not text.** Never store the body a second time:

```sql
CREATE TABLE classifier_shadow (
  sms_id        TEXT PRIMARY KEY,
  sender_norm   TEXT,
  received_at   INTEGER NOT NULL,
  rules_class   TEXT,
  model_class   TEXT,
  p_spend       REAL,
  p_phish       REAL,
  gate          TEXT,     -- confirmed | confirmed_lexical | asserted | rejected
  gate_reason   TEXT,     -- 'availability:loan' | 'no_balance' | 'negated_share' | ...
  decided       TEXT,     -- what the ledger actually did
  user_label    TEXT,     -- correction, if the user made one
  feature_json  TEXT,     -- the feature vector; NOT the message
  updated_at    INTEGER NOT NULL
);
CREATE INDEX classifier_shadow_at ON classifier_shadow(received_at DESC);
```

  Cap at 5,000 rows (delete oldest on insert) so the DB cannot grow unbounded on a 20 k-message inbox.
- **User-inspectable:** Settings › "Why was this flagged?" lists every row where `rules_class != model_class` or `gate == rejected`, with the reason string and the top-3 features. One screen, no graph. The owner asked for explainability; this is what it looks like when it is real rather than promised.
- **Export:** CSV via the existing share sheet, for the developer only. No upload code path exists, and none should be added.

### 6.5 Size and cost budget

| | v1 (gate only) | v2 (gate + LR) | Transformer (rejected) | LLM (rejected) |
|---|---:|---:|---:|---:|
| APK/AAB delta | ~0 (Dart code only) | **~1.2 KB** JSON + ~4 KB code | ~23 MB model + 1–3 MB runtime/ABI + 0.2 MB vocab | 0.3–1.5 GB (+ asset delivery) |
| Native deps | 0 | 0 | tflite_flutter 0.12.1 (12 months stale, self-described WIP, API ≥26) | AICore or ORT |
| Per-SMS CPU | ~400 µs (regex + amount scan, already paid today) | **+ ~10 µs** | +20–80 ms | +2–8 s |
| 3,000-message scan | baseline | **+ <50 ms** | +1–4 min | hours |
| Host-side unit tests | Yes | **Yes** | No | No |

There is no measured release APK to compare against (only a 155.7 MB debug build in `build/`); the delta column is what matters and it is 1.2 KB versus 23 MB.

---

## 7. What would change my mind

Pre-commit to these triggers so the decision does not get relitigated by vibes:

1. **GBDT** if, after v2, the LR's residual errors are demonstrably interaction-shaped (ablation: add all pairwise products and the held-out error drops >3 points) **and** labels ≥20 k.
2. **Transformer** if a real Flutter runtime under 10 MB, maintained within the last 6 months, runs in `flutter test` via FFI **and** labels ≥10 k. Both conditions, not either.
3. **On-device LLM** if Google makes AICore callable from a background receiver *and* the feature-API device list includes the sub-₹25 k segment. Not before.
4. **Drop the arbiter entirely** if the gate + arithmetic reaches SWP ≥ 0.995 and spend recall ≥ 0.95 on the holdout. That is a real possibility given the balance-coverage number, and it would make v2 a two-day job instead of twelve. **This is the outcome to hope for.**

---

## 8. Sources

**Repo (internal evidence):** `parser-gap-report.md` (43.1 % / 67.5 % / 98/180, RC-01…15, SC-01…06) · `real-data-findings.md` (141 flagged, 6/8 wrong, 89 Other rows, ₹8.44 L, D2 registry gaps) · `01-sms-corpus.md` §0 provenance tiers · `02-spam-and-phishing.md` §5 scoring, §6 sender trust, DPDP · `03-credit-semantics.md` · `ARCHITECTURE.md` §1/§3/§5/§7 · `lib/services/sms/sms_classifier.dart`, `sender_registry.dart`, `sms_guards.dart`, `lib/engine/txn_guards.dart`, `dedupe_engine.dart`, `lib/data/app_database.dart`, `finance_repository.dart`.

**External:**
- [gandharvbakshi/SMS-dataset-sample-10k](https://huggingface.co/datasets/gandharvbakshi/SMS-dataset-sample-10k) — MIT, 10 k CSV; schema verified via the datasets-server rows API: `original_index, sms_text, predicted_is_otp, predicted_otp_intent, classification_status, batch_number, is_phishing_original, sender`. No amount/direction/kind fields.
- [gandharvbakshi/SMS-dataset-OTP-OTP_INTENT_Phishing](https://huggingface.co/datasets/gandharvbakshi/SMS-dataset-OTP-OTP_INTENT_Phishing) — MIT, 73,470 rows, gated (manual approval), same label schema.
- [UCI SMS Spam Collection (id 228)](https://archive.ics.uci.edu/dataset/228/sms+spam+collection) — 5,574 messages, **CC BY 4.0**, `ham`/`spam` only.
- [m2cgen](https://github.com/BayesWitnesses/m2cgen) — model→native code for Dart, including `LogisticRegression`, `LinearSVC`, `LGBMClassifier`, `XGBClassifier`.
- [tflite_flutter 0.12.1](https://pub.dev/packages/tflite_flutter) — Apache-2.0, published 12 months ago, self-described work-in-progress, helper deprecated, Android needs API ≥ 26, `IsolateInterpreter` for off-thread inference.
- [sentence-transformers/all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) — 22.71 M parameters, 384-dim, Apache-2.0; card ships `onnx/model_qint8_arm64.onnx` (~23 MB int8).
- [ML Kit GenAI overview](https://developers.google.com/ml-kit/genai) — Gemini Nano via AICore: device support list (feature-specific and Prompt API), foreground-only inference (`BACKGROUND_USE_BLOCKED`), per-app quota (`BUSY`, `PER_APP_BATTERY_USE_QUOTA_EXCEEDED`). Fetched 2026-10-25.
- [fastText docs](https://fasttext.cc/docs/en/cheatsheet.html) — model quantisation (`.ftz`) for mobile.
- [Play app size limits](https://support.google.com/googleplay/android-developer/answer/9859372) · [Android App Bundles](https://developer.android.com/guide/app-bundle) — base-module download limits vs Play Asset Delivery.
- [Use of SMS or Call Log permission groups](https://support.google.com/googleplay/android-developer/answer/10208820) — the restricted-permission regime this app already lives under; any new dependency that widens permissions narrows the declaration story.
- [Exotel DLT guide](https://developer.exotel.com/docs/faqs/dlt-compliance.md) — header anatomy, used throughout `01-sms-corpus.md`.

*Estimates are labelled as such; no accuracy figure in §2 was measured for this corpus. §5 exists to replace them with numbers.*

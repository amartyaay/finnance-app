# 06 — On-device LLM classification: what is actually possible on a Galaxy S24 FE

**Status:** decision memo. Not a spec.
**Date:** 2026-10-25 (IST). All web claims re-fetched today; each source carries its own "last updated" date where the site publishes one.
**Device of record:** Samsung Galaxy S24 FE, **SM-S721B** (Indian unit), Exynos 2400e, 8 GB RAM, Xclipse 940, Android 14 shipped / upgradable to Android 17 + One UI 9.
**Decision needed:** whether an LLM — on-device or via the assistant — may participate in classifying the ~700 / 2 000 messages that land in `SmsClass.unknown`, and in what shape.
**Supersedes:** §2.f of [`05-classifier-options.md`](05-classifier-options.md). Supersedes it in *conclusion*, not just in date — see §1.4.
**Grounding:** `docs/research/01-sms-corpus.md`, `02-spam-and-phishing.md`, `03-credit-semantics.md`, `04-ux-spec.md`, `05-classifier-options.md`, `parser-gap-report.md`, `real-data-findings.md`, and the code in `lib/services/sms/`, `lib/domain/enums.dart`, `lib/domain/category_catalog.dart`, `lib/data/app_database.dart`.

---

## 0. The decision in one page

**The S24 FE cannot run Gemini Nano. Not "not yet" — not on any list Google publishes, and no preview programme reaches it.** `SM-S721B` appears in neither the ML Kit GenAI *feature-specific* device list nor the *Prompt API* device list. The AICore Developer Preview is restricted to devices that already support the Prompt API, so there is no side door. (§1)

**That is the only thing that kills Option B.** The earlier memo's objection — "inference is foreground-only, and SMS arrives in the background" — is **no longer relevant**, because the owner has changed the trigger to a user-initiated "Explain & fix" action. It is worth being precise about this, because it changes what we learn from the rejection: on a phone that *is* on the list, a user-triggered classifier would be architecturally legal today. On this phone it is simply impossible.

**Recommendation: ship Option D — the manual "Explain & fix" round trip — in 2–3 days.** Not as a consolation prize. D is the only option that (a) works on the phone the owner actually holds, (b) uses a model good enough to read Indian bank SMS correctly, (c) adds zero APK weight and zero cold-start, and (d) — the part that matters for sequencing — **generates the human-labelled data that any future bundled model would need to be evaluated at all.** D is the labelling pipeline for C, not a substitute for it.

**Then, and only then, Option C at the 270 M end** (≈289 MB, ~2–3 s/message, offline, private) as a gated experiment, 10–14 days, with its acceptance bar set from D's data. C at the 1 B end is not worth it on 8 GB of RAM and 35 % of a corpus.

**Option E (cloud, opt-in) is not built.** It is the same privacy exposure as D with none of the user's control, plus a permanent Data Fiduciary obligation and a per-request cost. The one thing E offers that D does not is automation, and automation is the wrong goal here: the product's promise is that the ledger is right and the user can see why.

**The one thing that could invalidate all of this:** if the 700 unknowns are *mostly not transactions at all* — bank promos, balance notices, delivery updates — then semantic labelling adds nothing, and the correct fix is a "Not a transaction" action and a "hide from review" affordance, costing one day. **This must be measured before D is built.** §9 gives the one-hour query that settles it. It is the single highest-value thing in this document.

**Effort:** A = 0 days (status quo). B = 0 days (impossible on this device). C = 10–14 days. **D = 2–3 days.** E = 4–6 days + ongoing.

---

## 1. Q1 — Does SM-S721B have Gemini Nano / AICore?

### 1.1 What Google publishes, as of 2026-10-25

Google splits device support into two lists, and they are **not** the same list. Both were fetched today from [`developers.google.com/ml-kit/genai`](https://developers.google.com/ml-kit/genai) (page "Last updated 2026-10-23 UTC").

**Feature-specific APIs** — Summarization, Proofreading, Rewriting, Image Description ([source](https://developers.google.com/ml-kit/genai)):

| Vendor | Devices on the list |
|---|---|
| Google | Pixel 9 / 9 Pro / 9 Pro XL / 9 Pro Fold, Pixel 10 (all four), Pixel 11 (all four) |
| Samsung | **Galaxy S25, S25+, S25 Ultra, S26, S26+, S26 Ultra, Z Flip8, Z Fold8, Z Fold8 Ultra, Z Fold7, Z TriFold** |
| Others | Honor 400 Pro / Magic 7 / 7 Pro / 8 Pro / V5, iQOO 13 / 15, Lenovo Idea Tab Pro Gen 2 / Legion Tab Gen 5, Motorola Razr 60 Ultra / Razr Ultra 2025 / Signature, OnePlus 15 / 15R / 13 / 13s, OPPO Find N5 / X9 / X9 Pro / X8 / X8 Pro / Reno 14–15 Pro, POCO F7 Ultra / F8 Pro / F8 Ultra / X7 Pro / X8 Pro, realme GT 7 Pro / 7T, Sharp AQUOS R11, Sony Xperia 1 VIII, vivo X200T / X200 FE / X200 / X200 Pro / X300 / X300 Pro / X Fold3 Pro / X Fold5 / T4 Ultra, Xiaomi 14T Pro / 15 / 15T / 15T Pro / 15 Ultra / 17 / 17 Ultra / Pad Mini |

**Prompt API** — the only API that accepts a *custom prompt*, i.e. the only one that could classify an SMS ([source](https://developers.google.com/ml-kit/genai#prompt-device), same page):

| Gemini Nano build | Devices |
|---|---|
| `nano-v2` | Honor Magic V5 / 7 / 7 Pro, iQOO 13, Motorola Razr 60 Ultra / Razr Ultra 2025, OnePlus 13 / 13s, OPPO Find N5, POCO F7 Ultra / F8 Pro / F8 Ultra / X7 Pro / X8 Pro, realme GT 7 Pro, **Samsung Galaxy Z Fold7, Galaxy Z TriFold**, vivo X200 FE / T4 Ultra, Xiaomi 14T Pro / 15 / 15T / 15T Pro / 15 Ultra / 17 / 17 Ultra / Pad Mini |
| `nano-v3` | Pixel 9 (all four), Pixel 10 (all four), Honor Magic 8 Pro, iQOO 15, Lenovo Idea Tab Pro Gen 2 / Legion Tab Gen 5, Motorola Signature, OnePlus 15 / 15R, OPPO Find X9 / X9 Pro / X8 / X8 Pro / Reno 14–15 Pro, realme GT 7T, **Samsung Galaxy S26, S26+, S26 Ultra**, Sharp AQUOS R11, Sony Xperia 1 VIII, vivo X200T / X200 / X200 Pro / X300 / X300 Pro |
| `nano-v4` | Pixel 11 (all four), **Samsung Galaxy Z Flip8, Z Fold8, Z Fold8 Ultra** |

**Verdict: `SM-S721B` is on neither list.** No Galaxy S24 variant of any kind appears — not S24, S24+, S24 Ultra, and not S24 FE. No FE device of any generation appears, on either list, for either API. There is no "S24 FE" row anywhere in Google's GenAI documentation.

### 1.2 There is no preview escape hatch

The [AICore Developer Preview programme](https://developers.google.com/ml-kit/genai/aicore-dev-preview) — which lets you download pre-production Nano builds and *bypass the per-app quota* — states its prerequisite plainly: it is "available for devices that support the Prompt API" (page last updated 2026-10-25 UTC, i.e. today). Quote-bypass is further restricted: "only available on Pixel devices".

So there is no combination of Play Services version, AICore APK, Google account, tester track, or region that puts Nano on this handset. The gate is a device allowlist enforced by AICore, not a version check we can satisfy.

### 1.3 What happens if you call the API anyway

`GenerativeModel.checkFeatureStatus()` returns `FeatureStatus.UNAVAILABLE` on an unsupported device, and `generateContent()` fails. A defensive implementation is therefore cheap — but a defensive implementation is all we would ever have on this phone. That is Option B in one sentence: **three days of work to display an "unavailable" banner.**

Samsung's own marketing does not rescue this. The S24 FE is widely described as Samsung's first mid-range device to carry "Galaxy AI" ([PCMag, 2024](https://www.pcmag.com/news/galaxy-s24-fe-is-samsungs-first-midrange-phone-to-include-galaxy-ai)), but the FE's Galaxy AI features are Samsung's own composites, and the generative ones explicitly require the network and a Samsung account — Samsung's own product footnote for the S24 FE says the Portrait Studio / Photo Assist feature "requires a network connection and Samsung account login" ([samsung.com/ch_fr, S24 FE spec sheet](https://www.samsung.com/ch_fr/smartphones/galaxy-s/galaxy-s24-fe-blue-256gb-sm-s721blbgeue/)). Samsung publishes **no third-party API** to any Galaxy AI on-device model; there is no entry for it in Samsung's developer portal as of today.

### 1.4 Why the earlier memo's reasoning was right but its reason was wrong

`05-classifier-options.md` §2.f rejected on-device LLMs and gave three reasons. Re-checked against today's pages:

| Reason in 05 | Status today (2026-10-25) |
|---|---|
| "Device list contains no mid-range Indian phone" | **Still true, and stronger.** The list has no S24-class Samsung at all. |
| "Inference is permitted only while the app is the top foreground application … `BACKGROUND_USE_BLOCKED`" | **Still true** ([genai overview](https://developers.google.com/ml-kit/genai)). **But no longer decisive**, because the trigger is now user-initiated and the app is by definition in the foreground. |
| "AICore enforces a per-app inference quota (`BUSY`, `PER_APP_BATTERY_USE_QUOTA_EXCEEDED`)" | **Still true.** This one *does* still bind: a 700-message batch would trip the long-duration quota. It caps Option B at a batch of ~10–20 per session. |

So: the foreground constraint — the one that made B "architecturally impossible" — has been designed away by the owner's change of trigger. What remains is hardware. If the owner upgrades to a **Galaxy S26 / Z Fold8 / Z Flip8**, Option B becomes viable with the same prompt/schema we build for D, in about three days. See §9 for the check to run on any candidate device.

**Note for any future hardware purchase:** the Galaxy **S25** slab is on the *feature-specific* list but **not** on the Prompt API list. Buying an S25 to get custom-prompt classification would fail. On Samsung, Prompt API currently means S26, Z Fold7/Fold8, Z Flip8, or Z TriFold. Check [`ml-kit/genai#prompt-device`](https://developers.google.com/ml-kit/genai#prompt-device) before spending money.

### 1.5 Fallbacks available on this device

1. **Option D** — hand the text to the Gemini app (cloud, user-mediated). Works today. §3.
2. **Option C** — bundle a 270 M–1 B model via LiteRT-LM. Works today. §2.4, §8.
3. **Option A+** — no model: better merchant rules, a "Not a transaction" action, and an embedding-based N-way labeler at 165 MB (§2.4a) if only category assignment is wanted.

---

## 2. Q2 — What APIs exist for an app to call an on-device model

Summary table first; detail below. "Custom prompt?" is the column that matters — three of the six rows can only do their own fixed task.

| Path | Status 2026-10-25 | Custom prompt? | On S24 FE? | Gating |
|---|---|---|---|---|
| **AICore / ML Kit GenAI *Prompt* API** | Beta, "not subject to any SLA or deprecation policy" | **Yes**, + structured output (Alpha) | **No** (§1) | device allowlist; foreground only; per-app quota |
| **ML Kit GenAI feature APIs** (Summarize / Proofread / Rewrite / Image describe) | Beta | **No** — fixed fine-tune, fixed output shape | **No** | same allowlist |
| **Firebase AI Logic Hybrid** (`PREFER_ON_DEVICE` …) | GA-ish; Android-first | Yes, but on-device half needs Nano | On-device **No**; cloud half **Yes** | needs Firebase project, App Check, billing |
| **LiteRT-LM** (`.litertlm`) | **Stable** (supersedes MediaPipe LLM Inference) | **Yes** | **Yes** | your own weights; minSdk 30; arm64 |
| **MediaPipe LLM Inference** (`.task`) | **Maintenance-only**, "migrate to LiteRT-LM" | Yes | Yes | same |
| **llama.cpp / GGUF via Flutter** | Community, works | **Yes** | **Yes** | your own weights; no Play Services |
| **Samsung Galaxy AI SDK** | **Does not exist for third parties** | — | — | — |
| **AppFunctions (Android 16)** | Experimental, private preview | n/a (assistant calls *you*) | Yes (Android 16+) | EAP, `EXECUTE_APP_FUNCTIONS` |

### 2.1 AICore / `com.google.android.aicore` + GenerativeModel

AICore is an Android **system service** (a Play-updated APK, `com.google.android.aicore`) that hosts Gemini Nano and exposes it through the ML Kit GenAI SDK. Your app does not ship the model, does not download it, and does not pay for it — it shares the device's copy ([overview](https://developers.google.com/ml-kit/genai)).

Hard constraints, all from that page, all quoted:

- **"GenAI API inference is permitted only when the app is the top foreground application. Using the API when the app is not in the foreground, including using a foreground service, will result in an `ErrorCode.BACKGROUND_USE_BLOCKED` response."**
- **Per-app quota**: too many requests in a short window → `ErrorCode.BUSY`; long-duration (daily) overrun → `ErrorCode.PER_APP_BATTERY_USE_QUOTA_EXCEEDED`. Recommended handling is exponential backoff.
- **Model identity varies**: `getBaseModelName()` returns which Nano build is present, and "different versions of Gemini Nano may return different output from the same prompt". For us: a prompt tuned on `nano-v3` may behave differently on `nano-v2`, which is exactly the sort of variance a ledger cannot absorb silently.
- **No memory between calls**: AICore "doesn't retain any data after a request is processed", so every prompt must be self-contained.

**Structured output is available** (Alpha), which matters a lot for §6: the Prompt API can be given a response schema rather than being trusted to emit clean JSON ([Generate structured output (Alpha)](https://developers.google.com/ml-kit/genai/prompt/android/structured-output)).

**Verdict for this device: N/A.** For a future S26-class device, this is the best option available — zero APK cost, zero download, best quality-per-watt — and the prompt/schema work in §6 transfers unchanged.

### 2.2 ML Kit GenAI feature APIs

Summarization, Proofreading, Rewriting, Image description (all Beta), Speech recognition (Alpha). They are genuinely on-device, and they are genuinely useless here:

- **Summarization** produces "1–3 bullet points". A bank SMS summarised to three bullets is not a classification.
- **Rewriting** supports "predefined styles" only.
- **Proofreading** fixes grammar.
- **Image description** describes images.

The comparison table Google publishes is explicit that the feature-specific APIs have "fixed fine-tuning and a built-in prompt" and "less flexibility", while Prompt API is the one requiring prompt engineering ([Prompt API overview](https://developers.google.com/ml-kit/genai/prompt/android)). **None of them accepts a custom prompt, so none can be repurposed into a classifier.** They are also absent from the S24 FE's device list anyway.

### 2.3 Firebase AI Logic, on-device and hybrid

Firebase AI Logic wraps both cloud Gemini and on-device Nano behind one `generativeModel(...)` call, with a four-way routing mode ([Android hybrid inference](https://developer.android.com/ai/hybrid)):

| Mode | Behaviour |
|---|---|
| `PREFER_ON_DEVICE` | try Nano, silently fall back to cloud if unavailable |
| `PREFER_IN_CLOUD` | cloud when online, Nano only when offline |
| `ONLY_ON_DEVICE` | **throws** if Nano unavailable |
| `ONLY_IN_CLOUD` | cloud only |

Two useful properties: **App Check** (so the cloud key is not sitting in the APK) and **spend caps**. Two disqualifiers for us: the on-device half is *still Nano* — Google's own framing is "cloud models serve as a critical fallback when on-device models, such as Gemini Nano, are unavailable due to device hardware or OS constraints" — so on the S24 FE `PREFER_ON_DEVICE` silently becomes `ONLY_IN_CLOUD`. Which means: **the moment we adopt this SDK on this phone, we are shipping Option E with extra steps**, and the "it's on-device, honest" claim in the UI becomes false. If E is ever built, this is the right SDK to build it with; it is not a way to get B.

The Flutter package is `firebase_ai`. Its Dart surface has historically lagged the Kotlin one; before betting on `onDeviceConfig` from Dart, verify it is exposed in the version you pin, or plan a thin platform channel. On this device it is moot.

### 2.4 LiteRT-LM (the current, supported successor to MediaPipe LLM Inference)

**MediaPipe LLM Inference is now in "maintenance-only mode"** — Google's own banner: "New features and optimizations will be focused on LiteRT-LM. We recommend migrating your projects to LiteRT-LM" ([LLM Inference guide](https://developers.google.com/edge/mediapipe/solutions/genai/llm_inference)). Any 2024-era tutorial you find that says "MediaPipe LLM Inference" is describing a frozen API. The `.task` bundle format still works; `.litertlm` is the format to build on.

LiteRT-LM is "production-ready", cross-platform, with **CPU, GPU and NPU backends on Android**, and supports Gemma, Qwen, Phi, Llama ([overview](https://developers.google.com/edge/litert-lm/overview), last updated 2026-10-06).

**Model sizes and speeds** (Google's own table, measured on a **Galaxy S24 Ultra** — Snapdragon 8 Gen 3, 12 GB — not on an FE):

| Model | Size (MB) | CPU prefill (tk/s) | CPU decode (tk/s) | GPU prefill | GPU decode |
|---|---:|---:|---:|---:|---:|
| FunctionGemma (270 M, mobile-actions FT) | **289** | 2238 | **154** | — | — |
| Qwen2.5-0.5B | **521** | 251 | 30 | — | — |
| Qwen3-0.6B | 586 | 165 | 9 | 580 | 21 |
| Gemma3-1B | **1005** | 177 | 33 | 1191 | 24 |
| Qwen2.5-1.5B | 1598 | 298 | 34 | 1668 | 31 |
| Gemma-3n-E2B | 2965 | 111 | 16 | 816 | 16 |
| Gemma-3n-E4B | 4235 | 74 | 9 | 548 | 9 |
| Gemma-4-E2B | 2583 | 557 | 47 | 3808 | 52 |

**Derating to Exynos 2400e — an estimate, labelled as such.** The 2400e has 1×3.1 GHz + 2×2.9 + 3×2.6 + 4×1.95 cores against the 8 Gen 3's 1×3.3 + 3×3.15 + 2×2.96 + 2×2.27, a weaker Xclipse 940 against Adreno 750, and a much smaller thermal budget in a 213 g chassis with no vapour chamber class cooling. **Apply 0.55–0.70× to decode and 0.55–0.70× to prefill.** Everything below is derived from that multiplier and is arithmetic, not measurement:

| Model | Est. prefill | Est. decode | 400-token prompt, ~110-token JSON reply |
|---|---:|---:|---|
| FunctionGemma 270 M (289 MB) | ~1250 tk/s | ~85–105 tk/s | **~1.7–2.5 s** |
| Qwen2.5-0.5B (521 MB) | ~140–175 tk/s | ~17–21 tk/s | ~8–11 s |
| Gemma3-1B (1005 MB) | ~100–125 tk/s | ~18–23 tk/s | ~9–13 s |
| Gemma-3n-E2B (2965 MB) | ~60–75 tk/s | ~9–11 tk/s | ~18–25 s, and 3 GB of storage |

The 270 M row is the only one that looks like a product. The 1 B row looks like a wait. The 3 GB row is not a phone feature.

**Memory.** 8 GB total on the FE, of which One UI 7/8 keeps a large share resident; expect roughly 2.5–3.5 GB actually available to a foreground app. A 1 B q4 model peaks near 1.2–1.6 GB (Google reports **1733 MB peak CPU memory** for the 2.58 GB Gemma-4-E2B on an S26 Ultra — i.e. peak ≈ 0.6–0.7× model size plus context). That fits, but it fits *alone*: the model load will evict most of the app's own caches, and under pressure the low-memory killer takes the process. A 270 M model at ~450–550 MB peak is comfortable; a 1 B model is a coin-flip on a phone that also runs the SMS pipeline.

**Storage and distribution.** A weight file of 289 MB–2.6 GB cannot ride in the base module of a Play bundle; it needs **Play Asset Delivery** (install-time/fast-follow/on-demand) or a first-run download ([Play size limits](https://support.google.com/googleplay/android-developer/answer/9859372), [App Bundles](https://developer.android.com/guide/app-bundle), [Asset Delivery](https://developer.android.com/guide/playcore/asset-delivery)). Either way it is a network event on first use, which weakens the "works offline" promise to "works offline after one download".

**minSdk 30 and arm64 only.** The Flutter wrapper documents that "anything backed by LiteRT — `.litertlm`, LiteRT embeddings, speech — needs `minSdk 30` and is `arm64-v8a` only" ([flutter_edge_ai](https://pub.dev/packages/flutter_edge_ai)). This app currently uses `minSdk = flutter.minSdkVersion` (24) with no ABI filter, so **adopting C forces a minSdk bump from 24 to 30**, dropping every Android 7–10 device, and adding an `abiFilters` split. That is a product decision, not a build tweak, and it belongs in the C estimate.

### 2.4a The option nobody lists: embeddings + a decider (165 MB)

`flutter_edge_ai` exposes an experimental **`Decider`**: pick one of N options for an input, **or abstain**, using an embedding model. Options are given with example utterances; each option is the centroid of its examples; it abstains when the best cosine similarity falls below a threshold cross-fitted on the options themselves ([flutter_edge_ai](https://pub.dev/packages/flutter_edge_ai)).

Cost: **EmbeddingGemma 2 Text 270 M is 165 MB** and its text embedding latency is **27.1 ms on the S26 Ultra CPU** ([LiteRT-LM overview](https://developers.google.com/edge/litert-lm/overview)). Derated for the FE: ~40–60 ms. Seven hundred messages in **30–45 seconds**, on a model small enough to install without a Wi-Fi prompt and idle at under 300 MB.

What it can do: assign one of the app's 14 existing category labels, and possibly "is this a transaction at all / promo / informational" with per-class examples. What it cannot do: extract a merchant name it has never seen, explain itself in words, or read a novel sentence pattern. It is a **discriminative** tool — closer in spirit to the logistic regression in `05` §2.b than to an LLM, but with far better generalisation and essentially no prompt engineering.

This is the strongest "small model" option for this app, and it is not on the brief's list. It belongs behind a flag in v2, evaluated with the same protocol as everything else (§7).

### 2.5 llama.cpp / GGUF via FFI in Flutter

Two roads, both real:

- **`llama_cpp_dart`** — direct FFI bindings, you own the native build, the memory management, and the tokenizer. Maximum control, maximum maintenance.
- **`flutter_gemma` → `flutter_edge_ai`** — the actively maintained wrapper. Note the rename: `flutter_gemma` is **discontinued**; "`flutter_gemma` has moved to `flutter_edge_ai` … This is the final release under the old name; new versions, features and fixes ship as `flutter_edge_ai`" ([pub.dev/packages/flutter_gemma](https://pub.dev/packages/flutter_gemma), last `flutter_gemma` release 1.11.4 ≈ 2026-10-05). `flutter_edge_ai` is at **2.5.2, published ≈2026-10-23** — two days old, 16 likes, 8.8 k downloads, one maintainer. Treat it as a fast-moving dependency: pin exact versions and keep the model layer behind our own interface so swapping engines is a day, not a rewrite.

`flutter_edge_ai` registers pluggable engines — LiteRT-LM (`.litertlm`), MediaPipe (`.task`), ONNX, **llama.cpp (`.gguf`)**, and "the OS's own models (Gemini Nano, Apple Foundation Models…)" via `flutter_edge_ai_builtin_ai`. That last one is worth noting: **the same Dart interface can serve Option B on a supported phone and Option C on this one.** One abstraction, two backends, chooser at runtime. That is the shape §8 recommends even if only D ships now.

GGUF advantages over `.litertlm`: you can quantise to Q4_K_M yourself, add a grammar (GBNF) to force JSON — which is the single most valuable guardrail for a money app — and run any community model. Disadvantages: you own the tokenizer chat template, and `flutter_edge_ai`'s llama.cpp path is "through llamadart" with CI covering "the CPU lifecycle" only ([platform matrix](https://pub.dev/packages/flutter_edge_ai)).

### 2.6 Samsung's own on-device AI SDK, Bixby, App Actions

- **No public on-device AI SDK.** Samsung ships Galaxy AI (Gauss-derived on-device components for some features), but there is no documented, supported API for a third-party app to run inference on Samsung's model. Searches of `developer.samsung.com` turn up nothing in this class. Do not plan around it.
- **Bixby:** routines and voice commands can *invoke* app actions (deep links / `Bixby Capsule` or app actions), but there is **no supported path to hand Bixby a blob of text and receive structured text back**. Bixby is a command router, not an inference endpoint.
- **App Actions / intents:** one-way. You can be invoked with text; you cannot call an assistant and get a result object back in-process.
- **Samsung keyboard "Writing tools"** exists on the device, but it operates on text selected in an editable field and returns *rewritten text* — not JSON, not addressable from our app.

**Conclusion:** there is no Samsung-side integration point that returns a classification. The only assistant integration that returns anything structured is AppFunctions (§2.7), and it is the assistant calling us, not the other way round.

### 2.7 Android 16 / One UI 8: AppFunctions — "Android MCP"

This is the most interesting long-term item in the whole document, and the most important thing to get the direction right on ([AppFunctions overview](https://developer.android.com/ai/appfunctions), page text as of the May 2026 revision):

- AppFunctions is an **Android platform API + Jetpack library** that lets an app "behave like on device MCP servers, contributing functions that act as tools for use by proactive features along with agents and assistants, like Google Gemini."
- **"AppFunctions is available on devices running Android 16 or higher."** The S24 FE is on the Android 16/17 path, so the device qualifies.
- Status: **experimental**. "As of May 2026, AppFunctions integration with Gemini is in a private preview with trusted testers." Callers need `EXECUTE_APP_FUNCTIONS`; "only a limited number of apps and system agents can access the entire pipeline."
- You declare `@AppFunction`-annotated suspend functions; the annotation processor emits an XML schema; the OS indexes it; an agent discovers and invokes them.

**Why this matters here.** It inverts Option D. Instead of *we* copying text into Gemini, the user says to Gemini "fix the unknown transactions in my finance app", and Gemini calls our `@AppFunction getUnexplainedTransactions(limit)` and then `@AppFunction proposeLabel(msgId, class, category, reason)`. The round trip becomes invisible, and — crucially — **it still lands as a suggestion our app validates and the user confirms**, because the guardrail lives in our code, not in the assistant's.

**Design implication, today:** define the AppFunction surface now, in KDocs, even though we cannot ship it. Expose **`explainTransaction(msgId)` → the existing `SmsSignal` list** — not `classify(text)`. The first is a read of our deterministic reasoning; the second invites an agent to write money. Getting this boundary right while nothing depends on it is free; getting it wrong later is not.

---

## 3. Q3 — The manual route: least friction, and what cannot be automated

The owner's suggestion — paste the SMS into Gemini, paste the answer back — is correct in principle and has three implementable variants. Ranked by taps per message.

### 3.1 The three variants

| Variant | Mechanism | Taps / batch of 10 | Returns data to app? | Notes |
|---|---|---:|---|---|
| **D1. Copy-as-prompt + share** | `Clipboard.setData` a bundled JSON-schema prompt, then `ACTION_SEND` `text/plain` to the Gemini app | ~8–10 total | No — user pastes back | Recommended. Batches 10 messages into one prompt. |
| **D2. `ACTION_PROCESS_TEXT` provider (inbound)** | We register as a text-selection provider; user selects the SMS in Messages → "Log with Finnance" | 3 per message | **Yes** — text arrives in our Activity | Best *capture* channel. Not an outbound route. |
| **D3. Share **to** us** | User shares the SMS from Messages to our app | 3 per message | **Yes** | Same effect as D2, works where D2 does not. |

**D1 is the answer to "least friction"**, and the reason is batching: one prompt carrying ten messages costs the same four taps as one message. The `reason` field then does double duty — it is the explanation the user reads *in Gemini's answer*, before pasting anything back.

`ACTION_SEND` targeting: prefer an explicit intent to the Gemini package with a chooser fallback. Be aware the package is `com.google.android.apps.bard` — a Bard-era identifier kept after the rebrand — which is precisely why it must be a *tried-and-fallen-back* constant, never a hard dependency. There is **no documented public deep link** to prefill a Gemini prompt; do not build on one.

### 3.2 Variant D2 inverts the direction, and it is the sleeper

`ACTION_PROCESS_TEXT` ([Intent reference](https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT)) is Android's "act on selected text" contract, API 23+. An app declares an activity with `<intent-filter><action android:name="android.intent.action.PROCESS_TEXT"/><category android:name="android.intent.category.DEFAULT"/><data android:mimeType="text/plain"/></intent-filter>`, the OS shows it in the text-selection menu, and the selected text arrives as `Intent.EXTRA_PROCESS_TEXT`. If the activity is launched for result it can return replacement text via `EXTRA_PROCESS_TEXT` on the result intent.

Used as an **inbound** channel this is excellent: the user is reading an SMS in Messages, long-presses it, taps **"Log with Finnance"**, and the message text lands in our parser — no clipboard, no share sheet, no permission beyond the existing SMS role. For messages that arrived before install, or that the background receiver missed, it is the fastest possible repair path. Three taps, and it is fully supported.

Used as an **outbound** channel — expecting Gemini to appear in the selection menu and return JSON — it does not work: the assistant is not a `PROCESS_TEXT` provider, and even if it were, there is no contract by which it would return a schema-valid object.

### 3.3 Can the answer come back automatically? No. Three candidate mechanisms, all closed:

- **Clipboard listener.** Dead since Android 10: clipboard access is restricted to "the app that has focus, or the default input method". A background service cannot read what Gemini copied. ([Android 10 privacy changes — clipboard](https://developer.android.com/about/versions/10/privacy/changes#clipboard-data)). Do not ship a clipboard-polling loop; it will be both non-functional and policy-hostile.
- **A share-target *from* the assistant.** Gemini's share sheet shares its answer as text — but it shares to *apps*, and it will share to us only if we register a receiver. That is a real 2-tap path ("Share response → Finnance") and worth implementing **in addition to** paste-back: it is strictly less error-prone than copy/paste, and it drops the user straight into the validation screen. It is still user-mediated — the OS mediates, not the network.
- **OCR of the response.** Possible (ML Kit text recognition on a screenshot) and strictly worse than both. Screenshots of Gemini answers wrap lines, lose digits, and cost the user more taps than pasting. **Do not build.**

Conclusion: the return leg is either **paste** or **share-to-us**. Both are ~2 taps. Neither is automatic. That is acceptable precisely because the trigger is manual.

---

## 4. Q4 — Privacy, Play, DPDP

### 4.1 On-device vs cloud, stated in one line each

- **On-device (C, B):** the SMS never leaves the phone. No Data Processor, no cross-border transfer, no new consent surface. The disclosure obligation is essentially **zero**, and this is the honest reason to prefer C when it works.
- **Cloud (E):** every message is transferred to a third party. Requires consent, a purpose limitation, a retention story, a Data Processing Agreement, and a Data Safety declaration. **Do not build.**
- **Manual (D):** the user moves their own text, in their own assistant app, on their own initiative. The app transmits nothing. This is a materially different act from E and should be described that way in the UI — but it is still a **privacy-relevant action that the app asked the user to take**, so it needs a one-line disclosure and a redaction step.

### 4.2 The disclosure D needs (and the redaction that makes it honest)

Before the clipboard write, show, once, with a "don't show again":

> **This copies the message text so you can paste it into Gemini.**
> Gemini runs in the cloud — Google will receive the text. Nothing is sent by this app.
> Account numbers and OTPs are removed before copying.

That last line must be **true**, which means a real redactor, not a promise:
- strip any digit run ≥ 9 with optional spaces/dashes (account numbers),
- strip `` masked-card patterns (`****1234`, `XX1234`),
- strip 4–8 digit standalone tokens adjacent to OTP/verification/valid-for words,
- **keep** the VPA/merchant handle (`swiggy@axl`) — it is the merchant signal, and it is not a credential,
- keep the amount, the balance, and the bank name — without them the task is impossible.

Ship this as `lib/services/ai/redactor.dart` with unit tests over the 180 fixtures: every redaction is a regex with a test, and the test asserts both "removed" and "not removed" cases.

### 4.3 Google Play

The relevant policy is **AI-Generated Content** ([Developer Policy Center](https://play.google/developer-content-policy/), linked page [`support.google.com/.../13985936`](https://support.google.com/googleplay/android-developer/answer/13985936)). Two obligations that apply to us if we ever display free-text model output:

1. AI-generated content must not be offensive, illegal, or misleading — for a finance app, the operative risk is **a confident wrong label**, not profanity.
2. Apps must give users a way to **report or flag** offensive AI-generated content in-app.

Honesty note: the policy page is JS-rendered and returned only its title to my fetcher twice today. The two items above are the policy's stable core, but **treat the exact wording as unverified until checked in Play Console** — it is a 10-minute check and it gates submission, not design.

For this app the requirement is cheap anyway: the "explain" sheet already needs a **"This is wrong"** affordance for product reasons (it is the label that feeds the merchant-rule learning loop). That same button satisfies the policy. One control, two purposes.

The **Financial Services** policy is also in scope (same Policy Center) — it constrains claims, not inference. Our UI must never say "guaranteed", "verified", or imply the AI's label is authoritative. Copy rule: *"Suggested. You confirm."*

### 4.4 DPDP Act 2023 — where the app actually stands

Timeline, per [Legal 500, 14 Aug 2026](https://www.legal500.com/intelligence/india/privacy/dpdp-act-and-rules-2025-the-2026-compliance-milestones-businesses-cant-afford-to-miss):

- **13 Nov 2025** — DPDP Rules, 2025 notified; Data Protection Board of India established.
- **13 Nov 2026** — Rule 4 (Consent Manager framework) comes into force.
- **13 May 2027** — substantive obligations for Data Fiduciaries commence.
- Penalties up to **₹250 crore** per instance; no grace period indicated.

Where each option sits:

| Option | App's role | Exposure |
|---|---|---|
| A (rules) | Data Fiduciary for data it stores on-device; nothing leaves | Minimal. No Processor, no transfer. |
| B / C (on-device) | Same as A | **Unchanged by adding a model.** This is the strongest compliance argument for C. |
| **D (manual)** | App performs no transfer; it hands the user a string in *their* assistant | Low, **provided** (a) the disclosure in §4.2 exists, (b) redaction is real, (c) we do not log the copied text or the pasted answer beyond the local DB. |
| E (cloud) | Becomes a Data Fiduciary transmitting financial data to a Processor abroad | Full consent + notice + DPA + Data Safety + breach-notification readiness. Not justified. |

One more: SMS bodies containing bank/UPI detail are **"financial information"** under the SPDI Rules, 2011 — still in force during the DPDP transition — which is a "sensitive personal data or information" category. SPDI's consent-and-purpose requirements are stricter than DPDP's default posture. Practically: **keep the "no network for message bodies" invariant**, and make any exception a deliberate, documented, user-visible act. D does that; E does not.

---

## 5. Q5 — Decision table

| | **A. Rules only (status quo)** | **B. AICore / Gemini Nano** | **C. Bundled 270 M–1 B** | **D. Manual share-to-assistant** | **E. Cloud, opt-in** |
|---|---|---|---|---|---|
| **Available on SM-S721B** | ✅ today | ❌ **never** (§1) | ✅ with caveats | ✅ today | ✅ technically |
| **Custom prompt** | n/a | (would be ✅) | ✅ | ✅ (frontier model) | ✅ |
| **APK / download cost** | 0 | **0** (shared system model) | **289 MB** (270 M) · 521 MB (0.5 B) · 1005 MB (1 B) | **0** | 0 |
| **RAM at inference** | ~0 | (system-managed) | ~450–550 MB (270 M) · ~0.7–0.9 GB (0.5 B) · ~1.2–1.6 GB (1 B) | ~0 | ~0 |
| **Latency per message** | **~2 ms** | ~1–3 s | **~2 s** (270 M) · ~9 s (1 B) | **~15–25 s** (human-bound) | ~1–3 s |
| **Batch of 20** | instant | ~40–60 s, may trip quota | ~45 s (270 M) · ~3 min (1 B) | ~4–6 min of user time | ~40 s |
| **Batch of 700** | instant | **infeasible** (quota) | ~25 min (270 M) · ~1.5 h (1 B) + heat | infeasible (human) | ~20 min, 700 requests |
| **Marginal cost** | 0 | 0 | 0 | 0 (user's Gemini quota) | per-request |
| **Explainability** | **exact** — `SmsSignal` list | good (free text) | **weak** — 270 M rationales are confabulated | **good** | good |
| **Privacy** | **best** — nothing moves | best | **best** | **cloud, user-initiated, disclosed** | worst |
| **Determinism / testability** | **golden-testable** | no | no (temperature 0 helps, does not fix) | no | no |
| **Quality on Indian bank SMS** | 99 % on fixtures, 65 % unknown-resolve on real | good | **unproven, probably poor at 270 M** | **best available** | best |
| **Risk of confidently wrong ₹** | low | medium | **high at 270 M** | low | medium |
| **Effort** | 0 d | **0 d (impossible)** · 3 d on a supported phone | **10–14 d** | **2–3 d** | 4–6 d + ongoing |
| **Blocks other work?** | no | no | minSdk 24→30; arm64 split; +289 MB-1 GB | no | Data Safety, DPAs |

### 5.1 Why not C first

Not because it is bad — the 270 M row is genuinely competitive on latency and unbeatable on privacy. Because of three things:

1. **We cannot measure it.** There is no held-out labelled set. Building C without one means shipping a model whose accuracy we cannot state, into an app whose entire selling point is "the numbers are right and here is why".
2. **Its failure mode is the worst one.** A 270 M model that hallucinates a merchant is annoying; one that hallucinates `amount_paise: 11151` for `₹1,11,510` is a ledger bug the user has to catch. The guardrail in §6 contains it, but only if we have measured how often it fires.
3. **It costs 5× the effort of D and cannot be validated until D's data exists.** D produces exactly the labels C needs.

### 5.2 Why not E

Because **D already does what E would do, with the user holding the steering wheel and the app holding no data.** The only thing E adds is automation, and automation of a step the user currently performs deliberately is a downgrade in this product: it converts a user-reviewed suggestion into a silent background mutation of a financial ledger. The 99 %-on-fixtures deterministic engine is the source of truth precisely because it is auditable. If the owner ever wants automatic cloud classification, the honest version is "classification suggestions land in a review queue, nothing is booked until confirmed" — which is D, automated, at a cost of ~₹0.05–0.20/message and a permanent compliance surface.

---

## 6. Q6 — The schema, and the guardrails that make it safe

### 6.1 The contract

Design constraints, from the existing code: `SmsClass {transaction, informational, promo, phishing, unknown}` and `TxnKind {spend, cash, income, transfer}` in `lib/domain/enums.dart`; **14 fixed category names** in `lib/domain/category_catalog.dart` (Groceries, Transport, Shopping, Rent, Entertainment, Health, Education, Travel, Fuel, Investments, Transfers, Income, Cash, Other). The model must emit **only** values that already exist — no new vocabularies, or the app has to map and can silently mis-map.

```json
{
  "v": 1,
  "results": [
    {
      "msg_id": "inbox:48213",
      "class": "transaction",
      "kind": "spend",
      "instrument": "upi",
      "direction": "debit",
      "amount_paise": 24900,
      "merchant": "Swiggy",
      "category": "Other",
      "reason": "says 'debited Rs 249' to SWIGGY; no conditional or offer language",
      "confidence": 0.86
    }
  ]
}
```

Field rules:

| Field | Type | Rule |
|---|---|---|
| `v` | int | must equal 1; unknown version → reject whole payload |
| `results[].msg_id` | string | **must already exist** in `sms_messages`; unknown id → drop that result |
| `class` | enum | one of the five `SmsClass` names |
| `kind` | enum? | `spend`/`cash`/`income`/`transfer`/null; null allowed when `class != transaction` |
| `instrument` | enum? | one of `Instrument` names, or null |
| `direction` | `"debit"\|"credit"`? | null allowed |
| `amount_paise` | int? | **integer paise**, never a float, never a string, never `"₹1,234"` |
| `merchant` | string? | ≤ 40 chars, display-cased; matched case-insensitively against the rule table |
| `category` | enum | **exactly** one of the 14 names |
| `reason` | string | ≤ 160 chars, must quote at least one substring that actually occurs in the SMS (checked) |
| `confidence` | float | 0.0–1.0, clamped |

Two design notes that will save a week:

- **`amount_paise` as an int is non-negotiable.** The single most common LLM failure on Indian money text is `1,11,510` → `111510` vs `11151` (lakh/comma grouping). Ints in paise make the error visible in a diff instead of invisible in a float.
- **The `reason` substring check is a cheap hallucination detector.** If the model says "says 'debited'" and the word `debited` does not appear in the message, the suggestion is demoted to `unverified` with no user-facing prompt. It catches a surprising fraction of confabulation for about fifteen lines of Dart.

### 6.2 The guardrails (the part that actually matters)

**G1 — The model never creates money movement.** It returns a `Suggestion` keyed to an existing `msg_id`. It cannot insert a row, cannot change a balance, cannot alter a confirmed transaction. The only table it writes to is `ai_suggestions`, and only with `status = 'proposed'`.

```
transactions  ← only ← (a) the deterministic parser, (b) an explicit user action
ai_suggestions ← only ← the model
```

**G2 — Amount changes are diffs, never assignments.** If `amount_paise != transactions.amount_paise`, the UI *must* render:

```
Amount    ₹1,234.00  →  ₹12,340.00     [ Keep ₹1,234.00 ]  [ Use ₹12,340.00 ]
```

with the AI value visually distinct (not the primary button, not the accent colour) and the rules value still actionable. There is no code path in which an AI amount is applied without this screen.

**G3 — Arithmetic confirmation outranks the model.** If the message prints a balance and `prev_balance ± amount == printed_balance`, that identity wins. It is deterministically checkable, it is not a guess, and it is exactly the mechanism `05` §0 identified as the highest-value thing in the whole project. A model suggestion that contradicts a satisfied arithmetic identity is **rejected**, not merely flagged — and the contradiction is logged as a prompt-bug signal.

**G4 — Confidence is a routing signal, not a probability.** Buckets: `< 0.5` → not shown; `0.5–0.8` → review queue, low emphasis; `≥ 0.8` → review queue, sorted first. Nothing auto-applies at any confidence. The word "confidence" must never appear in the UI — 0.86 does not mean 86 % correct, and users will read it that way.

**G5 — Every suggestion is reversible in one tap, and the merchant rule it creates is editable.** Confirming a suggestion writes a `merchant_rules` row (`CategorySource.user`, which already outranks `rule`/`heuristic` in `enums.dart`). That is the whole point: **one confirmation fixes every future occurrence.** Un-confirming removes the rule and the label.

**G6 — Idempotence.** `UNIQUE(msg_id, model_id, prompt_hash)` on `ai_suggestions`. Re-running the same prompt cannot duplicate or oscillate. Re-running with a changed prompt creates a new row, and the old one is superseded rather than deleted (audit trail).

**G7 — Deterministic where it can be.** `temperature = 0` / `topK = 1` (greedy) wherever the runtime allows it, and grammar/schema-constrained decoding where available (llama.cpp GBNF; LiteRT-LM advertises "constrained decoding"; ML Kit Prompt API has structured output). Greedy decoding makes the same input produce the same output on the same model build — not portable across builds, but reproducible enough to debug.

**G8 — No AI on the SMS-receive path. Ever.** Not a flag, not a fallback, not "just for unknown". The receiver writes the row and stops. Any AI call is inside a user-initiated flow, in the foreground, with a visible spinner. This is a one-line lint-able rule and it should be written in the module header.

### 6.3 The unglamorous finding: the category catalog has no dining bucket

`category_catalog.dart` has Groceries, Transport, Shopping, Rent, Entertainment, Health, Education, Travel, Fuel, Investments, Transfers, Income, Cash, Other — **and no Food/Dining**. Swiggy and Zomato therefore land in `Other` or `Groceries`, which is wrong in both directions: `Other` makes the biggest discretionary category invisible; `Groceries` inflates grocery spend.

For a *merchant-name*-driven categoriser this is the single highest-value product fix in the app, it has nothing to do with LLMs, and it costs a few hours plus a `SpendCategoryKind` migration. **Do this regardless of what happens to this memo.** Any AI labelling bolted on top of a catalog without a dining bucket will produce confident nonsense.

---

## 7. Q7 — How to evaluate it honestly

### 7.1 The set

- **Do not evaluate on the 180 fixtures.** They are the development set for the deterministic engine, they are already memorised in a real sense (the rules were tuned against them), and they are synthetic-adjacent. Any number measured on them is a number about our own tuning, not about the world.
- **Build a 300-message held-out set from the 2 000 real messages.** Stratify: 150 from `unknown` (the population of interest), 75 `promo`/`informational` (the false-positive risk), 75 `transaction` (the false-negative risk), sampled by spend-weight so the big debits are represented. Owner hand-labels in one sitting, ~2 hours. Freeze it, hash it, commit the hash — not the messages — and never look at it while tuning prompts.
- **Also freeze a 100-message prompt-development slice**, disjoint from the 300. All prompt iteration happens there. This is the discipline that separates "we measured it" from "we measured our own overfitting".

### 7.2 Metrics — and the one that is the product metric

| Metric | Definition | Why |
|---|---|---|
| **Spend-weighted precision** | Σ₹ of correctly booked debits ÷ Σ₹ of booked debits | **The product metric.** A 2 % error rate on 400 messages each ₹50 is noise; one error on a ₹1,11,510 credit-card bill is a disaster. Count money, not messages. |
| Spend-weighted recall | Σ₹ of correctly booked ÷ Σ₹ of truly booked | Catches the opposite failure |
| Unknown-resolution rate @ bar | % of held-out `unknown` resolved to the right class, at precision ≥ the bar | The gap the owner sees |
| **Harm** | Σ₹ of accepted-and-wrong ÷ Σ₹ total | The number that would stop the ship |
| Suggestion acceptance | user-approved ÷ shown | Is the feature even wanted? |
| Model–human κ | Cohen's κ vs the owner's labels | Diagnostic only |

**Set the bars before looking at the results** (this is the part that keeps it honest):

- Pipeline **spend-weighted precision ≥ 0.995**. Below that, the AI path does not ship, regardless of how good the model is — the deterministic engine already clears it.
- **Harm = ₹0** across the 300. Non-negotiable.
- **Unknown-resolution ≥ 30 %** of the held-out unknowns, else the feature does not justify its UI.
- **Acceptance ≥ 40 %** of shown suggestions, measured over ≥ 100 suggestions, else the friction thesis in §3 is wrong and D should be withdrawn.

### 7.3 The acceptance rule (the sentence that makes this defensible)

> **A model suggestion is accepted only when it agrees with the arithmetic check on the message's balance delta, or when the user explicitly confirms it.**

Formally, for each suggestion: `accepted = arithmetic_confirms(s) XOR user_confirms(s)`, where `arithmetic_confirms` requires the printed balance to move exactly by the amount and direction the model claims. Everything else stays `proposed`.

This does two things at once. It gives a **hard, non-ML adjudicator** veto power over the ML — which is what makes a non-deterministic component admissible in a financial ledger at all — and it means the number we report is *pipeline* accuracy, not model accuracy. Reporting model-vs-human agreement as if it were product precision is the most common way these projects lie to themselves.

### 7.4 What "honestly" forbids

- Comparing model accuracy on the *unknown* bucket to 99 % on the *fixtures*. Different populations, different metrics. The comparison is to the **rules-only baseline on the same 300**, per bucket.
- Reporting message-weighted precision as if it were spend-weighted.
- Hiding the `proposed-but-not-accepted` bucket. Report it: it is the cost of the design.
- Claiming a model is "99 % accurate" when the guardrail rejected its amount and the amount came from the parser. The parser got it right; say so.

---

## 8. Flutter integration, concretely

### 8.1 Module boundary

New code, nothing existing modified except a navigation entry point and the DB schema version:

```
lib/services/ai/
  ai_types.dart            // AiSuggestion, AiStatus (pure data, no IO)
  ai_prompt.dart           // builds the batch prompt; the ONE place prompt text lives
  ai_schema.dart           // parse + validate + clamp (pure Dart, fully unit-tested)
  ai_redactor.dart         // strips account numbers / OTPs before any export
  ai_export.dart           // D: clipboard + ACTION_SEND + share-target receiver
  ai_suggestion_store.dart // sqlite: ai_suggestions, status transitions
  ai_engine.dart           // interface: Future<List<AiSuggestion>> classify(batch)
    ├── manual_engine.dart   // D — returns [] ; user pastes the answer back
    ├── aicore_engine.dart   // B — MethodChannel; status() == unavailable on S24 FE
    └── lite_engine.dart     // C — flutter_edge_ai, lazy load, close on background
```

`ai_engine.dart` is the whole trick: the UI and the guardrails never know which engine produced a suggestion, and the S24 FE simply registers `ManualEngine` + an `AicoreEngine` whose `status()` is `unavailable`. Swapping to a real Nano path on an S26 is one constructor.

### 8.2 Option D — no native code at all

D is pure Dart + the Android intent plumbing you already have via `share_plus` / `android_intent_plus` (both would be new dependencies; `Clipboard` is in `services.dart`, no dependency).

1. `ai_prompt.dart` builds one prompt for N messages with the schema embedded verbatim, the 14 category names listed explicitly, and the instruction *"Return only JSON. No prose. No markdown."*
2. `Clipboard.setData(prompt)` then a chooser `ACTION_SEND`/`text/plain` (try Gemini's package, fall back to the chooser).
3. User pastes into Gemini, reads the answer (this is where the `reason` field earns its keep), copies it, returns to the app.
4. Paste box → `ai_schema.dart` → tolerant parse (find the first balanced `{…}`, ignore leading prose and ```json fences) → validate → `ai_suggestion_store.dart` with `status='proposed'`.
5. Review screen: each suggestion as a card with the rules' current value beside it, the `reason`, and Accept / Keep-rules / Not-a-transaction.

Failure handling that matters: **a near-miss must fail loudly and specifically.** "Gemini's answer had 3 problems: category 'Food' is not one of the 14; amount is a string, not paise; msg_id 48214 is not in the app." A generic "invalid response" teaches the user nothing and they will retry the same way.

### 8.3 Option B — the channel shape, for the day a supported device appears

Kotlin side, `com.google.mlkit:genai-prompt`:

```kotlin
private val channel = MethodChannel(flutterView, "finnance/ai")

// methods:
//   "status"  -> "ready" | "downloadable" | "unavailable" | "error:<code>"
//   "classify"-> { "prompt": String, "schemaJson": String } -> String (raw JSON)
```

- `checkFeatureStatus()` on `GenerativeModel` → map to `status`; call it once at screen open, cache for the session, never on app start (it can trigger a model availability check and is not free).
- `GenerationConfig` with `responseMimeType = "application/json"` + `responseSchema` (Alpha) — this removes most malformed-output handling.
- Wrap `BUSY` / `PER_APP_BATTERY_USE_QUOTA_EXCEEDED` in exponential backoff; surface quota exhaustion as *"Gemini Nano is busy — try again in a few minutes"*, never as a crash.
- Foreground: the sheet keeps the Activity resumed; if the user backgrounds mid-call, expect `BACKGROUND_USE_BLOCKED` and retry on resume.
- Cap the batch at **10–15 messages per call** to stay clear of the quota; a 700-message run is not a supported workload and should not be offered.

### 8.4 Option C — weights, cold start, and what to do with 8 GB

- **Where the weights live:** `getApplicationSupportDirectory()/models/`, downloaded on first use with an explicit Wi-Fi check and a progress UI. **Not** in `assets/`, not in the base bundle: it would add 289 MB–1 GB to every install for a feature most users may not open, and Play's base-module limits are far below that anyway. Play Asset Delivery is the alternative if the download must be invisible; it still transfers the bytes.
- **Cold start, honestly:** `FlutterEdgeAi.initialize(...)` must **not** be in `main()`. Registering the engine is cheap, but loading a model is not: expect **1.5–3 s to map 289 MB from flash plus allocator warm-up, 3–6 s for a 1 B q4**, before the first token. So first-tap-to-first-token on the FE is roughly **4–6 s (270 M)** and **8–14 s (1 B)**. Show "Loading model…" with a real progress signal, and keep the handle warm for the session.
- **Release the model when the app leaves the foreground.** 8 GB with One UI is not a lot; a resident 1 B model will get the app killed while it is in the background and then the user returns to a cold start anyway. `close()` in `didChangeAppLifecycleState(AppLifecycleState.paused)`.
- **Check free RAM before loading** and refuse politely below ~1.2 GB for 270 M / ~2 GB for 1 B. Failing to load is fine; being killed mid-inference after the user confirmed a label is not.
- **Thermals:** a 20-message batch at 270 M is ~45 s of sustained compute — noticeable but survivable. A 1 B batch of 50 will throttle a 213 g chassis; cap batches, and show elapsed/remaining so the user can stop.
- **Build config:** bump `minSdk` 24 → 30, add `ndk.abiFilters += listOf("arm64-v8a")`, and expect the APK to grow by the size of the LiteRT runtime (single-digit MB) before any weights.

### 8.5 What degrades where — the matrix to implement

| Situation | Behaviour |
|---|---|
| S24 FE (no Nano) | "On-device AI" row hidden entirely, not greyed. A greyed row is a permanent nag about hardware the user cannot change. |
| S26 / Z Fold8 (Nano present) | "On-device AI" available; `AicoreEngine` used; no download |
| No model downloaded yet | "Explain & fix" still works via D; C offered as "Download 289 MB for offline" |
| < 1.2 GB free RAM | C refuses with a specific reason; D unaffected |
| Gemini app not installed | D's share step falls back to chooser; "copy as prompt" still works with any assistant |
| No network | C works; D does not; copy-as-prompt still works (user can paste elsewhere later) |
| Battery < 15 % | C refuses; D unaffected |

**The invariant:** every path degrades to "copy as prompt", and copy-as-prompt degrades to "the rules' explanation, which we already have". **There is no state in which the user is worse off than today.**

---

## 9. What to run in the next three days (before building anything)

### 9.1 The one-hour query that decides whether any of this matters

```sql
SELECT id, sender, body
FROM sms_messages
WHERE class = 'unknown'
ORDER BY RANDOM()
LIMIT 100;
```

Hand-label those 100 into: **real transaction** / **promo or informational** / **genuinely ambiguous** / **phishing-adjacent**.

- If **≥ 70 % are promo/informational** → the unknown bucket is not a classification failure, it is a *labelling* failure. Ship: a "Not a transaction" action, a hidden-from-review state, and two more `_infoIntents` patterns. **~1 day. Stop. Do not build AI.**
- If **≥ 40 % are real transactions** → §5's recommendation stands, with D as step one.
- If **≥ 25 % are genuinely ambiguous** (SIPs, TD closures, order receipts, merchant naming — exactly the owner's list) → D is clearly right, and C becomes worth evaluating because D's data will tell us whether 270 M is good enough.

This is the balance-coverage-number discipline from `05` §0 applied to a different question, and it costs an hour.

### 9.2 The device check to run on any phone before promising on-device AI

```bash
adb shell pm list packages | grep -i aicore
adb shell dumpsys package com.google.android.aicore | grep -i version   # AICore present?
adb shell cmd package query-activities -a android.intent.action.PROCESS_TEXT -t text/plain  # who can act on selected text
```

AICore being *present* is not the same as Nano being *available* — the allowlist can still return `UNAVAILABLE`. The authoritative check is `checkFeatureStatus()` from a 20-line app, or the Google AI Edge Gallery app on the device. **Do not buy a phone for this feature without running that check on the actual unit.**

### 9.3 The measurement that prices Option C

A 30-line Dart harness that loads the candidate model on the actual S24 FE and runs 20 real unknowns, recording: load ms, time-to-first-token, total per message, peak RSS, battery % delta, and whether the JSON parsed. Run it before committing 10–14 days. If time-to-first-token on the FE exceeds ~5 s at 270 M, C is not a product experience and the answer is D-only.

---

## 10. What would change my mind

| Change | Effect |
|---|---|
| §9.1 shows unknowns are mostly promo noise | **D is cancelled.** Fix the labels, not the model. This is the most likely outcome and the most valuable finding. |
| Owner upgrades to S26 / Z Fold8 / Z Flip8 | **B becomes the recommendation** (3 days, no download, best quality). The prompt, schema and guardrails in §6 transfer unchanged. |
| §9.3 shows 270 M at < 2 s and parsing cleanly on real SMS | **C moves ahead of D** for the offline/private story — but D is still needed to produce the eval set. |
| AppFunctions + Gemini go GA | **D becomes automatic** (Gemini calls `explainTransaction` / `proposeLabel`). Design the AppFunction surface now so the guardrail is already in the right place. |
| A dining/Food category is added to the catalog | Labelling becomes worth much more, in every option. Do it anyway. |
| S24 FE gains Nano via a future One UI update | **Very unlikely** — AICore device support is a model/hardware allowlist, not an OS-version gate, and no FE has ever appeared on one. Re-check the page quarterly; do not plan around it. |

---

## 11. Sources (all fetched 2026-10-25, IST)

| Claim | Source | Site's own date |
|---|---|---|
| Feature-specific + Prompt API device lists; no S24/FE anywhere; foreground-only; per-app quota; `getBaseModelName` variance | [ML Kit GenAI overview](https://developers.google.com/ml-kit/genai) | Last updated 2026-10-23 UTC |
| Prompt API is the only custom-prompt API; feature APIs have fixed prompts | [Prompt API overview](https://developers.google.com/ml-kit/genai/prompt/android) | Last updated 2026-07-15 UTC |
| Structured output (Alpha), system instructions, prefix caching, thinking mode | [Prompt API — structured output](https://developers.google.com/ml-kit/genai/prompt/android/structured-output) | — |
| Dev Preview restricted to Prompt-API devices; quota bypass Pixel-only; ~1 min first inference | [AICore Developer Preview](https://developers.google.com/ml-kit/genai/aicore-dev-preview) | Last updated 2026-10-25 UTC |
| MediaPipe LLM Inference is maintenance-only; migrate to LiteRT-LM | [LLM Inference guide](https://developers.google.com/edge/mediapipe/solutions/genai/llm_inference) | — |
| LiteRT-LM stable; model sizes; S24 Ultra tok/s; peak memory; CPU/GPU/NPU on Android | [LiteRT-LM overview](https://developers.google.com/edge/litert-lm/overview) | Last updated 2026-10-06 UTC |
| `PREFER_ON_DEVICE` / `ONLY_ON_DEVICE`; App Check; spend caps; Nano as the only on-device backend | [Android hybrid inference](https://developer.android.com/ai/hybrid) | — |
| AppFunctions: Android 16+, experimental, MCP-equivalent, Gemini private preview (May 2026), `EXECUTE_APP_FUNCTIONS` | [AppFunctions](https://developer.android.com/ai/appfunctions) | May 2026 revision |
| `ACTION_PROCESS_TEXT` contract | [Intent reference](https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT) | — |
| Clipboard read restricted to focused app / default IME | [Android 10 privacy changes](https://developer.android.com/about/versions/10/privacy/changes#clipboard-data) | — |
| AI-Generated Content policy exists; reporting + no-offensive-output obligations | [Policy Center](https://play.google/developer-content-policy/) → [AI-Generated Content](https://support.google.com/googleplay/android-developer/answer/13985936) | Policy page JS-only; **verify in Console** |
| Base-module size limits; Asset Delivery | [Play size limits](https://support.google.com/googleplay/android-developer/answer/9859372) · [Asset Delivery](https://developer.android.com/guide/playcore/asset-delivery) | — |
| DPDP Rules 2025 notified 13 Nov 2025; Consent Managers 13 Nov 2026; substantive obligations 13 May 2027; ₹250 crore penalties | [Legal 500, 14 Aug 2026](https://www.legal500.com/intelligence/india/privacy/dpdp-act-and-rules-2025-the-2026-compliance-milestones-businesses-cant-afford-to-miss) | 14 Aug 2026 |
| SM-S721B: Exynos 2400e, 8 GB, Xclipse 940, Android 14→17, One UI 9, 213 g | [GSMArena](https://www.gsmarena.com/samsung_galaxy_s24_fe-13262.php) | — |
| S24 FE is Samsung's first mid-range device with Galaxy AI; generative features need network + Samsung account | [PCMag](https://www.pcmag.com/news/galaxy-s24-fe-is-samsungs-first-midrange-phone-to-include-galaxy-ai) · [Samsung CH spec sheet](https://www.samsung.com/ch_fr/smartphones/galaxy-s/galaxy-s24-fe-blue-256gb-sm-s721blbgeue/) | — |
| `flutter_gemma` discontinued → `flutter_edge_ai`; 2.5.2; engines; minSdk 30 / arm64; Decider; model install APIs | [flutter_gemma](https://pub.dev/packages/flutter_gemma) · [flutter_edge_ai](https://pub.dev/packages/flutter_edge_ai) | 2.5.2 published ≈2026-10-23 |

**Unverified in this pass, flagged deliberately:** the exact wording of Play's AI-Generated Content policy (JS-only page); the Gemini app's `ACTION_SEND` / `PROCESS_TEXT` registration on a current One UI build (run §9.2's `query-activities`, or test the selection menu by hand); Samsung's complete Galaxy AI feature matrix for SM-S721B (marketing pages enumerate features inconsistently across regions); and every tokens/second figure for the Exynos 2400e in §2.4, which is a **derived estimate** from S24 Ultra numbers and must be replaced by §9.3's measurement before it is quoted anywhere else.

---

*Bottom line: the S24 FE cannot host Gemini Nano, the foreground restriction that killed on-device LLMs in `05` no longer applies now that the trigger is manual, and the correct first move is the two-day manual round trip — because it works on the phone in the owner's hand and because it manufactures the labelled data that any bundled model would need to be judged. But measure the unknown bucket first; there is a real chance the honest answer is that most of those 700 messages are not transactions, and no model, on any device, fixes that.*

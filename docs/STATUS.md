# Nepal Clinical Assistant — Development Status

**Last updated:** 2026-07-16  
**Single source of truth** for what’s shipped, how to run it, and what’s next.  
Long-term design target: [`clinical-llm-technical-architecture.md`](../clinical-llm-technical-architecture.md).  
Venture context: [`clinical-llm-venture-analysis.md`](../clinical-llm-venture-analysis.md).

**Backlog order:** Near-term → Retrieval/RAG → Chat agent → **Consent/scrub pipeline** → **Sync & data flywheel** → LLM packaging / model enhancement → EMR.

---

## Strategic thesis (why the plan looks like this)

**Product wedge (trust):** Offline clinical reference + grounded chat/notes so clinicians actually use the app in Nepal OPD settings.

**Economic moat (later):** Consented, de-identified clinical interaction data from an underserved market → improve retrieval corpus and (later) model adapters → optional **data products** and/or **model products**.

| Priority | Implication |
|---|---|
| Capture every useful local interaction | Instrument sessions/chat/notes early; make logging complete and scrubbed |
| Consent is the asset gate | Default OFF stays; scopes must be explicit |
| Scrubbing is revenue-critical | Weak regex is fine for demo; production flywheel needs high-recall de-id **before** upload |
| RAG/corpus first, fine-tune second | Consented usage mostly improves **Nepal knowledge base + evals** |
| Don’t sell raw PHI | Monetize aggregates / licensed de-id corpora / fine-tuned weights |
| Trust = opt-in rate | Clinicians must believe the free tool helps them |

**Device reality:** Ollama sidecar is a **PC/dev POC**. Majority South Asia Android phones run **FTS/RAG (+ optional tiny GGUF later)** — not Ollama-in-APK.

**Not changed:** Interaction severity stays DB-deterministic. Demo/repo stays synthetic until a real pilot consent path exists.

```text
Clinician use (search / interact / notes / chat)
    → local scrubbed session log
    → opt-in sync (Wi‑Fi, scoped consent)
    → ingest → curated Nepal corpus + gold evals
    → better retrieval (primary) + optional adapter/fine-tune (secondary)
    → OTA improved index/model back to devices
    → later: licensed data / model SKUs (B2B)
```

---

## Where we are now

| Area | Status | Notes |
|---|---|---|
| Flutter clinical reference UI | **Shipped** | Search, Interact, Guidelines, **Chat**, Notes, Consent |
| Offline Nepal fixtures | **Shipped** | **60** drugs / **40** interactions / **24** guidelines / **50** gold evals |
| Deterministic interaction severity | **Shipped** | DB only; never invented |
| Gold eval | **Shipped** | **50/50** pass (`artifacts/eval_gold_report.md`) |
| Interaction catalog integrity | **Shipped** | **40/40** bidirectional |
| Consent default OFF + sync blocked UI | **Shipped** | UI only — no real ingest yet |
| Regex PII scrubber | **Shipped** | ~30% name/place recall — insufficient for production upload |
| Local clinical session log | **Shipped** | All interactions saved on-device; web persists via SharedPreferences |
| Activity history + note save | **Shipped** | Activity tab; full note drafts; sync_queue rows pending consent |
| Shared retrieve API | **Shipped** | `clinical_core_py.retrieve` + Dart `ClinicalRetriever` |
| Guideline citations / unknown-pair retrieval | **Shipped** | FTS + token search |
| Local LLM note-drafter POC | **Shipped (code)** | PC Ollama sidecar; fixture fallback; **not field-phone ready** |
| Chat agent (RAG-first) | **Shipped (v0)** | Retrieve → cite/refuse; optional LLM if Ollama up (ADR-003) |
| CI stub (fixture + gold evals) | **Shipped** | `.github/workflows/qa-fixtures.yml` |
| Consent → scrub → sync → ingest flywheel | **Partial** | Local `sync_queue` stub; upload blocked until consent ON |
| SQLCipher / encrypted DB | **Not started** | |
| Cloud sync / ingest / OTA | **Not started** | |
| On-device JNI llama.cpp | **Not started** | Field path after sidecar POC |
| EMR patient UI | **Not started** | |
| Play Store / closed testing | **Not started** | |

**Working demo URL (typical):** `http://localhost:8080` (or `:8081` if busy).

---

## Guardrails (always)

1. Synthetic Nepal fixtures only in repo/demos until pilot legal path is live  
2. Permanent “not for clinical use” disclaimer until regulatory posture changes  
3. Consent default **OFF**; no clinical upload without explicit scoped opt-in  
4. Interaction severity **only** from local DB  
5. Note/chat = **draft / grounded assist**, not diagnosis or prescribing authority  
6. LLM must not invent interaction severity  
7. No sale or training use of **identifiable** clinical content — scrub + consent + contract first  

---

## How to run

### App (Flutter web)

**Most reliable on this machine (release build — avoids blank debug `web-server` page):**

```powershell
$env:PATH = "C:\Users\UA4\flutter\bin;$env:PATH"
cd c:\Users\UA4\Desktop\clinic-local-llm\apps\clinical_assistant
flutter build web --release
cd build\web
python -m http.server 8090
```

Open **http://localhost:8090** (hard refresh Ctrl+Shift+R).

**Debug (often blank with `web-server`):** prefer Edge if Chrome won’t launch:

```powershell
flutter run -d edge
```

Avoid relying on `flutter run -d web-server --web-port=8080` unless the Dart Debug Chrome extension is connected — it commonly shows a blue bar then a blank page.

### Automated checks

```powershell
cd c:\Users\UA4\Desktop\clinic-local-llm
python data\scripts\seed_nepal_db.py
python qa\run_fixture_evals.py
python qa\run_eval_queries.py
python packages\clinical_core_py\smoke_test.py
python packages\clinical_core_py\retrieve_smoke.py
```

### Spot-check (UI)

1. Banner: not-for-clinical-use + offline  
2. Search: `Paracetamol` / `Nepalol` / `doxycycline`  
3. Interact: Azithromycin + Ciprofloxacin → contraindicated  
4. Chat: `scrub typhus` → citations; nonsense query → refuse  
5. Consent: default OFF  
6. Notes: sample → Generate (fixture or live model on PC)

### Local LLM (optional — PC only)

```powershell
ollama pull qwen2.5:1.5b
ollama serve
python tools\ollama_cors_proxy.py   # web CORS
python packages\clinical_core_py\llm_smoke.py
```

---

## Shipped changelog (condensed)

### Slice A — 8h Nepal MVP (2026-07-14)
- Flutter shell; search / interact / guidelines / consent; PII scrub POC; ADR-001  

### Slice B — Quality + Retrieval + LLM POC (2026-07-15)
- Gold eval 40/40; sessions log; citations; Notes + Ollama sidecar; CORS proxy  

### Docs + flywheel thesis (2026-07-16)
- Master `STATUS.md`; data/model flywheel backlog reorder  

### Slice C — Corpus + retrieve + Chat v0 + CI (2026-07-16)
- Corpus → 60/40/24; gold evals → 50/50  
- Shared retrieve API (Python + Dart)  
- Chat tab (RAG-first, refuse-if-empty, ADR-003)  
- GitHub Actions QA workflow  

---

## Planned next (ordered backlog)

### Near-term (product demo strength)
- [ ] Install/prove live Ollama draft on this machine (PC POC only)
- [x] CI stub: `run_fixture_evals.py` + `run_eval_queries.py` on PR
- [x] Expand formulary / interactions / guidelines + eval suite (60/40/24 / 50 queries)
- [ ] Further corpus growth toward Nepal coverage % (track via eval dashboards)
- [x] Replace Flutter app README; consolidate docs; commit/push Slice B

### Retrieval / RAG (coverage engine → 90% Nepal situations)
- [x] Shared retrieve API for Interact / Guidelines / Chat / future training exports
- [ ] Grow curated local corpus further (NTC/WHO-adapted + OPD vignettes)
- [ ] sqlite-vec or embedding hybrid when FTS plateaus
- [ ] Eval: coverage + recall dashboards (beyond 50 smoke queries)

### Chat agent
- [x] ADR-003 chat scope (cite-or-refuse, no severity invention)
- [x] Chat tab v0 + retrieve-then-answer + citations + refuse path
- [ ] Discuss past scrubbed notes / sessions in context
- [ ] Structured feedback (up/down + reason codes)
- [ ] Stronger grounded LLM prompt path (not note-drafter reuse)
- [ ] Eval smoke on synthetic chat vignettes

### Consent + scrub pipeline (flywheel gate)
- [ ] Consent scopes v2 + production scrubber (>99% recall) + SQLCipher  
- [ ] Reject-to-queue rules; threat-model + lawyer review  

### Sync & data flywheel
- [ ] sync_queue → ingest-api → curated corpus → transparency UI  

### LLM packaging & model enhancement
- [ ] Device-tier detection; optional on-device GGUF for capable phones  
- [ ] Fine-tune/adapters only after consented scrubbed corpora  
- [ ] JNI llama.cpp; signed OTA  

### EMR / distribution (later)
- [ ] Patient registry; Play internal testing; India scale-up  

---

## Doc map

| Doc | Role |
|---|---|
| **This file** | Current status + run + backlog + flywheel thesis |
| [`docs/architecture/ADR-001-stack.md`](architecture/ADR-001-stack.md) | Stack lock |
| [`docs/architecture/ADR-002-local-llm-poc.md`](architecture/ADR-002-local-llm-poc.md) | Local sidecar LLM (PC) |
| [`docs/architecture/ADR-003-chat-rag.md`](architecture/ADR-003-chat-rag.md) | Chat RAG-first |
| [`docs/security/threat-model-v0.1.md`](security/threat-model-v0.1.md) | Offline threats |
| [`qa/test-plan-p0.md`](../qa/test-plan-p0.md) | Detailed test cases |
| [`clinical-llm-technical-architecture.md`](../clinical-llm-technical-architecture.md) | Long-horizon architecture |
| [`clinical-llm-venture-analysis.md`](../clinical-llm-venture-analysis.md) | Venture context |

**Do not recreate** per-sprint checkpoint runbooks — update **this** file instead.

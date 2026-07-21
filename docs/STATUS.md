# Nepal Clinical Assistant — Development Status

**Last updated:** 2026-07-20  
**Single source of truth** for what’s shipped, how to run it, and what’s next.  
Long-term design target: [`clinical-llm-technical-architecture.md`](../clinical-llm-technical-architecture.md).  
Venture context: [`clinical-llm-venture-analysis.md`](../clinical-llm-venture-analysis.md).

**Backlog order (default):** Near-term → Retrieval/RAG → Chat agent → **Consent/scrub pipeline** → **Sync & data flywheel** → LLM packaging / model enhancement → EMR.

**Active continuation (2026-07-20):** **LLM-first** — (1) on-device Qwen GGUF for Chat (hard fail if missing; no Ollama / rules fallback), (2) grow Nepal drug/condition corpus toward ~90% OPD coverage, (3) sync ADR + ingest stub (no production PHI upload).

---

## Strategic thesis (why the plan looks like this)

**Product wedge (trust):** Offline clinical reference + grounded chat/notes so clinicians actually use the app in Nepal OPD settings.

**Economic moat (later):** Consented, de-identified clinical interaction data from an underserved market → improve retrieval corpus and (later) model adapters → optional **data products** and/or **model products**.

| Priority | Implication |
|---|---|
| Capture every useful local interaction | Instrument sessions/chat/notes early; local history unredacted; scrub only sync payloads |
| Consent is the asset gate | **Required first-launch Terms** include sync/data consent (single gate; no separate Consent tab) |
| Scrubbing is revenue-critical | Weak regex is fine for demo; production flywheel needs high-recall de-id **before** upload |
| RAG/corpus first, fine-tune second | Consented usage mostly improves **Nepal knowledge base + evals** |
| Don’t sell raw PHI | Monetize aggregates / licensed de-id corpora / fine-tuned weights |
| Trust = clear legal + useful tool | Clinicians must believe the free tool helps them and understand sync terms |

**Device reality:** Product Chat runs **on-device GGUF** (llama.cpp / `llamadart`) on **Windows + Android**. Ollama is **not** a product path. Flutter **web** Chat returns **no model found** until a later WebGPU path. Notes may still use the in-app SOAP assembler without a GGUF.

**Not changed:** Interaction severity stays DB-deterministic. Demo/repo stays synthetic until a real pilot legal path exists.

```text
Clinician use (search / interact / notes / chat / patients)
    → local session log (clinician-readable, unredacted)
    → scrub copy into sync_queue (authorized by first-launch Terms)
    → ingest → curated Nepal corpus + gold evals
    → better retrieval (primary) + optional adapter/fine-tune (secondary)
    → OTA improved index/model back to devices
    → later: licensed data / model SKUs (B2B)
```

---

## Where we are now

| Area | Status | Notes |
|---|---|---|
| Flutter clinical reference UI | **Shipped** | Search, Interact, Guidelines, Chat, Notes, Patients, Past Notes |
| First-launch Terms + sync consent | **Shipped** | Single gate (`np-terms-1.1`); no separate Consent tab |
| Local patient registry | **Shipped** | Lightweight ID/name/age/condition/notes/history — **not** full EMR |
| Offline Nepal fixtures | **Shipped** | **60** drugs / **40** interactions / **24** guidelines / **50** gold evals |
| Deterministic interaction severity | **Shipped** | DB only; never invented |
| Gold eval | **Shipped** | **50/50** pass (`artifacts/eval_gold_report.md`) |
| Interaction catalog integrity | **Shipped** | **40/40** bidirectional |
| Regex PII scrubber | **Shipped** | Sync-queue only; ~30% name/place recall — insufficient for production upload |
| Local clinical session log | **Shipped** | On-device history unredacted; web persists via SharedPreferences |
| Past Notes + note save | **Shipped** | UI shows **note drafts only**; chat/search/interact still logged + sync-queued |
| Shared retrieve API | **Shipped** | `clinical_core_py.retrieve` + Dart `ClinicalRetriever` |
| Guideline citations / unknown-pair retrieval | **Shipped** | FTS + token search |
| Local LLM note-drafter | **Shipped** | In-app draft default; GGUF when file present |
| Chat agent (RAG + GGUF) | **Shipped (v1)** | Retrieve → cite/refuse → **GGUF only**; hard error if no model |
| CI stub (fixture + gold evals) | **Shipped** | `.github/workflows/qa-fixtures.yml` |
| Production scrubber + SQLCipher | **Not started** | Consent gate shipped; scrub quality / encryption next |
| Cloud sync / ingest / OTA | **Stub** | ADR-004 + local `ingest-api` + `SyncWorker` (default OFF) |
| On-device llama.cpp GGUF | **Shipped (v0)** | `GgufLlamaRuntime` + `llamadart`; manual GGUF placement |
| Full EMR | **Not started** | Beyond local patient cards |
| Play Store / closed testing | **Not started** | |

**Working demo URL:** `http://localhost:8090` after `flutter build web --release` + `python -m http.server 8090` from `build/web`.  
**Note:** Web Chat will show **No local model** by design; use `flutter run -d windows` for neural Chat.

---

## Guardrails (always)

1. Synthetic Nepal fixtures only in repo/demos until pilot legal path is live  
2. Permanent “not for clinical use” disclaimer until regulatory posture changes  
3. **First-launch Terms required** (includes sync/data consent); no clinical upload without that acceptance  
4. Interaction severity **only** from local DB  
5. Note/chat = **draft / grounded assist**, not diagnosis or prescribing authority  
6. LLM must not invent interaction severity  
7. No sale or training use of **identifiable** clinical content — scrub (sync queue only) + Terms + contract first; on-device history stays clinician-readable  
8. **Chat never falls back** to rules engine or Ollama — missing GGUF → explicit error  

---

## How to run

### App (Flutter web)

```powershell
$env:PATH = "C:\Users\UA4\flutter\bin;$env:PATH"
cd c:\Users\UA4\Desktop\clinic-local-llm\apps\clinical_assistant
flutter build web --release
cd build\web
python -m http.server 8090
```

Open **http://localhost:8090** (hard refresh Ctrl+Shift+R). First visit after Terms version bump shows the gate again.  
Chat answers require a native build + GGUF (web → **No local model**).

### App (Windows + on-device GGUF Chat)

1. Download **Qwen2.5-1.5B-Instruct Q4_K_M** GGUF from Hugging Face (not ollama.com), e.g.  
   `qwen2.5-1.5b-instruct-q4_k_m.gguf`
2. Create folder and copy the file:
   ```powershell
   $models = Join-Path $env:USERPROFILE "Documents\nepal_clinical\models"
   New-Item -ItemType Directory -Force -Path $models | Out-Null
   # Copy your .gguf into $models
   ```
   (App documents path may be under the Flutter app container; banner / error text prints the exact path after probe.)
3. Run (Windows desktop requires **Developer Mode** enabled for Flutter plugin symlinks):
   ```powershell
   $env:PATH = "C:\Users\UA4\flutter\bin;$env:PATH"
   cd c:\Users\UA4\Desktop\clinic-local-llm\apps\clinical_assistant
   flutter run -d windows
   ```
4. Banner should show **On-device · qwen…**. Without the file → **No local model** and Chat returns that error (no rules dump).

**Verified without GGUF:** `flutter test test\chat_gguf_required_test.dart` — Chat throws `LocalModelNotFoundException`; Notes still draft via in-app. Web build succeeds; Chat uses the web stub (always **No local model**).

Do **not** use `ollama pull` for product Chat.

### Automated checks

```powershell
cd c:\Users\UA4\Desktop\clinic-local-llm
python data\scripts\seed_nepal_db.py
python qa\run_fixture_evals.py
python qa\run_eval_queries.py
python packages\clinical_core_py\smoke_test.py
python packages\clinical_core_py\retrieve_smoke.py
cd apps\clinical_assistant
flutter test test\chat_gguf_required_test.dart test\in_app_draft_engine_test.dart
```

### Spot-check (UI)

1. Terms gate: must agree (includes sync) before app  
2. Banner: not-for-clinical-use + offline  
3. Search: `Paracetamol` / `Nepalol` / `doxycycline`  
4. Interact: Azithromycin + Ciprofloxacin → contraindicated  
5. Chat (Windows + GGUF): `scrub typhus` → grounded answer; without GGUF → **No local model found**  
6. Patients + Notes: create patient, save note with Patient ID  
7. Past Notes: saved note drafts only (other activity still sync-queued)

### Local draft / Chat LLM

| Surface | Behavior |
|---|---|
| **Chat** | On-device GGUF **required**. Missing/unloadable → error only. |
| **Notes** | GGUF if present; else `InAppDraftEngine` (`in-app-draft-v1`) |
| **Web** | Chat hard-errors (no neural runtime in this slice) |

```powershell
cd apps\clinical_assistant
flutter test test\chat_gguf_required_test.dart
flutter run -d windows   # with GGUF in Documents/nepal_clinical/models/
```

---

## Shipped changelog (condensed)

### Slice A — 8h Nepal MVP (2026-07-14)
- Flutter shell; search / interact / guidelines; PII scrub POC; ADR-001  

### Slice B — Quality + Retrieval + LLM POC (2026-07-15)
- Gold eval; sessions log; citations; Notes + Ollama sidecar; CORS proxy  

### Docs + flywheel thesis (2026-07-16)
- Master `STATUS.md`; data/model flywheel backlog reorder  

### Slice C — Corpus + retrieve + Chat v0 + CI (2026-07-16)
- Corpus → 60/40/24; gold evals → 50/50; Chat RAG-first; CI QA  

### Local persistence + patients + Terms (2026-07-20)
- Durable local activity; readable Activity UI; lightweight Patients  
- Unified first-launch Terms + sync consent; Consent tab removed  

### On-device GGUF Chat (2026-07-20)
- ADR-002: GGUF product path; Chat hard-requires model (no rules/Ollama fallback)  
- `GgufLlamaRuntime` + `llamadart`; Notes keep in-app assembler  

---

## Planned next (ordered backlog)

Work **only in this order**. Newer ideas go into the matching section (or ask if unclear).

### 1. Near-term (product demo strength)
- [x] Install/prove live Ollama draft on this machine (PC POC only) — **superseded**: GGUF Chat + in-app Notes
- [x] CI stub: `run_fixture_evals.py` + `run_eval_queries.py` on PR
- [x] Expand formulary / interactions / guidelines + eval suite (60/40/24 / 50 queries)
- [x] Local activity persistence (web + native) + note save
- [x] Readable Past Notes UI (note drafts only; other sessions still sync-queued)
- [x] Lightweight local patient registry + Patient ID on notes
- [ ] Further corpus growth toward Nepal coverage % (track via eval dashboards)
- [x] Replace Flutter app README; consolidate docs; commit/push Slice B
- [x] LLM status banner + Chat GGUF-required path

### 2. Retrieval / RAG (coverage engine → 90% Nepal situations)
- [x] Shared retrieve API for Interact / Guidelines / Chat / future training exports
- [ ] Grow curated local corpus further (NTC/WHO-adapted + OPD vignettes) — **in progress**
- [ ] sqlite-vec or embedding hybrid when FTS plateaus
- [ ] Eval: coverage + recall dashboards (beyond 50 smoke queries)

### 3. Chat agent
- [x] ADR-003 chat scope (cite-or-refuse, no severity invention)
- [x] Chat tab + retrieve-then-answer + citations + refuse path
- [x] Stronger grounded LLM prompt path (GGUF-only; no rules fallback)
- [x] Discuss past notes / sessions in context (local unredacted history) — unified chat retrieve
- [ ] Structured feedback (up/down + reason codes)
- [ ] Eval smoke on synthetic chat vignettes

### 4. Consent + scrub pipeline (flywheel gate)
- [x] Unified first-launch Terms + data-sync consent (single gate; Consent tab removed)
- [ ] Production scrubber (>99% recall) — regex is demo-only
- [ ] SQLCipher / encrypted local DB
- [ ] Reject-to-queue rules; threat-model update + lawyer review of `np-terms-1.1`

### 5. Sync & data flywheel
- [x] Local `sync_queue` stub (scrubbed payloads after Terms accept)
- [x] ADR-004 + local `services/ingest-api` + `SyncWorker.debugFlushPending` (default OFF)
- [ ] Real sync_queue → ap-south-1 ingest → curated corpus (prod scrub >99% recall)
- [ ] Transparency UI (what left the device / when)

### 6. LLM packaging & model enhancement
- [x] On-device GGUF runtime (Windows/Android) + Chat hard-require  
- [ ] Device-tier detection; smaller default GGUF for low-RAM phones  
- [ ] Fine-tune/adapters only after consented scrubbed corpora  
- [ ] Signed OTA model delivery  

### 7. EMR / distribution (later)
- [ ] Full EMR (visits, prescriptions, facility workflows) — **beyond** current patient cards  
- [ ] Play internal testing; India scale-up  

---

## Doc map

| Doc | Role |
|---|---|
| **This file** | Current status + run + backlog + flywheel thesis |
| [`docs/architecture/ADR-001-stack.md`](architecture/ADR-001-stack.md) | Stack lock |
| [`docs/architecture/ADR-002-local-llm-poc.md`](architecture/ADR-002-local-llm-poc.md) | On-device GGUF; Chat hard-requires model |
| [`docs/architecture/ADR-003-chat-rag.md`](architecture/ADR-003-chat-rag.md) | Chat RAG-first |
| [`docs/architecture/ADR-004-sync-ingest.md`](architecture/ADR-004-sync-ingest.md) | De-id sync → AWS Mumbai ingest (stub) |
| [`docs/security/threat-model-v0.1.md`](security/threat-model-v0.1.md) | Offline threats |
| [`qa/test-plan-p0.md`](../qa/test-plan-p0.md) | Detailed test cases |
| [`clinical-llm-technical-architecture.md`](../clinical-llm-technical-architecture.md) | Long-horizon architecture |
| [`clinical-llm-venture-analysis.md`](../clinical-llm-venture-analysis.md) | Venture context |

**Do not recreate** per-sprint checkpoint runbooks — update **this** file instead.

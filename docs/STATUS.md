# Nepal Clinical Assistant — Development Status

**Last updated:** 2026-07-22  
**Single source of truth** for what’s shipped, how to run it, and what’s next.  
Long-term design target: [`clinical-llm-technical-architecture.md`](../clinical-llm-technical-architecture.md).  
Venture context: [`clinical-llm-venture-analysis.md`](../clinical-llm-venture-analysis.md).

**Backlog order (default):** Near-term → Retrieval/RAG → Chat agent → **Consent/scrub pipeline** → **Sync & data flywheel** → LLM packaging / model enhancement → EMR.

**MVP engineering: closed (2026-07-22).** Signed Play AAB **1.0.0+3** at `apps/clinical_assistant/build/app/outputs/bundle/release/app-release.aab`. Remaining MVP gate is **external** lawyer review of `np-terms-1.2`. Next: upload AAB to Play internal testing; post-MVP corpus pipeline / device-tier GGUF / OTA / full EMR.

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

**Device reality:** Product Chat runs **on-device GGUF** (llama.cpp / `llamadart`) on **Linux + Windows + Android**. Ollama is **not** a product path. Flutter **web** Chat returns **no model found** until a later WebGPU path. Notes may still use the in-app SOAP assembler without a GGUF.

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
| Flutter clinical reference UI | **Shipped** | Search, Interact, Guidelines, Chat, Notes (Draft \| Saved), Patients |
| First-launch Terms + sync consent | **Shipped** | `np-terms-1.2` — sync **required / always on** after accept; no in-app off switch |
| Local patient registry | **Shipped** | Search + phone / WhatsApp / email; lightweight cards — **not** full EMR |
| Offline Nepal fixtures | **Shipped** | **494** drugs (full **NNLEM 2021** catalog) / **40** interactions / **111** guidelines / **120** OPD conditions / **130** gold evals |
| Deterministic interaction severity | **Shipped** | DB only; never invented |
| Gold eval | **Shipped** | **130/130** pass (`artifacts/eval_gold_report.md`) |
| Interaction catalog integrity | **Shipped** | **40/40** bidirectional |
| PII scrubber (production heuristics) | **Shipped** | **100%** recall on 30-case fixture; sync gate ≥99% |
| Reject-to-queue | **Shipped** | Residual PII → `blocked_residual_pii` + `scrub_note`; excluded from flush |
| Local clinical session log | **Shipped** | On-device history unredacted; web persists via SharedPreferences |
| Notes (draft + saved) | **Shipped** | Generate does **not** auto-save; Save locally / Edit saved notes; chat/search/interact still sync-queued |
| Shared retrieve API | **Shipped** | `clinical_core_py.retrieve` + Dart `ClinicalRetriever` |
| Guideline citations / unknown-pair retrieval | **Shipped** | FTS + token search |
| Local LLM note-drafter | **Shipped** | In-app draft default; GGUF when file present |
| Chat agent (RAG + GGUF) | **Shipped (v1)** | Retrieve → cite/refuse → **GGUF only**; hard error if no model |
| CI stub (fixture + gold evals) | **Shipped** | `.github/workflows/qa-fixtures.yml` |
| Production scrubber + field encryption | **Shipped (v1)** | Name/place heuristics + `DbCrypto` patient fields; native SQLCipher deferred |
| Cloud sync / ingest / OTA | **Continuous (invisible)** | After Terms: `SyncCoordinator` flushes on enqueue / 30s / resume; no sync chrome; Supabase Mumbai or local ingest |
| On-device llama.cpp GGUF | **Shipped (v0)** | `GgufLlamaRuntime` + `llamadart`; Linux/Windows/Android; manual GGUF placement |
| Threat model | **Shipped (v0.2)** | [`docs/security/threat-model-v0.2.md`](security/threat-model-v0.2.md) |
| Full EMR | **Not started** | Beyond local patient cards — **post-MVP** |
| Play Store / closed testing | **AAB 1.0.0+3** | `build/app/outputs/bundle/release/app-release.aab` (signed upload keystore); upload to Play internal testing next; lawyer Terms review still external |

**Working demo URL:** `http://localhost:8090` after `flutter build web --release` + `python -m http.server 8090` from `build/web`.  
**Note:** Web Chat will show **No local model** by design; use `flutter run -d linux` (or Windows) for neural Chat.

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

```bash
cd apps/clinical_assistant
flutter build web --release
cd build/web
python -m http.server 8090
```

Open **http://localhost:8090** (hard refresh Ctrl+Shift+R). First visit after Terms version bump shows the gate again.  
Chat answers require a native build + GGUF (web → **No local model**).

### App (Linux + on-device GGUF Chat) — primary on this machine

1. Download **Qwen2.5-1.5B-Instruct Q4_K_M** GGUF from Hugging Face (not ollama.com), e.g.  
   `qwen2.5-1.5b-instruct-q4_k_m.gguf`
2. Place the file:
   ```bash
   mkdir -p "$HOME/Documents/nepal_clinical/models"
   # Copy your .gguf into that directory
   ```
3. Run:
   ```bash
   cd apps/clinical_assistant
   flutter run -d linux
   ```
4. Banner should show **On-device · qwen…**. Without the file → **No local model** and Chat returns that error (no rules dump).

Desktop SQLite uses `sqflite_common_ffi` (Linux/Windows have no native `sqflite` plugin).

**Verified without GGUF:** `flutter test test/chat_gguf_required_test.dart` — Chat throws `LocalModelNotFoundException`; Notes still draft via in-app.  
**Verified with GGUF (Linux):** `flutter test test/gguf_model_resolve_test.dart` — loads Qwen from `~/Documents/nepal_clinical/models/`.

Do **not** use `ollama pull` for product Chat.

### App (Windows + on-device GGUF Chat)

1. Same GGUF into `%USERPROFILE%\Documents\nepal_clinical\models\`
2. Windows desktop requires **Developer Mode** for Flutter plugin symlinks:
   ```powershell
   cd apps\clinical_assistant
   flutter run -d windows
   ```

### App (Android release / Play internal testing)

```bash
export JAVA_HOME="${JAVA_HOME:-$HOME/.local/jdk}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"

cd apps/clinical_assistant/android
# One-time: create upload keystore + key.properties (see key.properties.example)
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias upload
cp key.properties.example key.properties   # fill passwords + storeFile=../upload-keystore.jks

cd ..
# Bump pubspec version build number before each Play upload (e.g. 1.0.0+3 → 1.0.0+4)
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

**Iterate on Play updates (repeat forever):**

1. Ship Flutter code changes as usual  
2. Bump **only** the `+build` in `pubspec.yaml` (`1.0.0+3` → `1.0.0+4`, …). Play requires a strictly increasing `versionCode`. Bump `1.0.x` when you want a new user-visible version name.  
3. `flutter build appbundle --release` from `apps/clinical_assistant`  
4. Upload the new AAB in Play Console → **Internal testing** (same app id `np.clinical.clinical_assistant`, same upload keystore)  
5. Testers already on the internal track get the update via Play — no sideload needed  

**Faster device-only loop (no Play):** `flutter run` / `flutter install --release` on USB — no version bump required until you upload to Play.

**Prod sync in a binary:** pass `--dart-define=INGEST_BASE_URL=…` and `--dart-define=INGEST_ANON_KEY=…` on `flutter run` or `flutter build appbundle`.

**Play Console checklist:** app id `np.clinical.clinical_assistant`; minSdk 29; label “Nepal Clinical Assistant”; not-for-clinical-use store listing + privacy policy URL **https://usmanakhter.github.io/clinic-local-llm/privacy/** (`docs/privacy/index.html` via GitHub Pages); upload AAB to internal testing track; place GGUF on device under app documents `nepal_clinical/models/` (or ship via OTA later). Lawyer review of `np-terms-1.2` remains a pilot gate.

**Upload keystore (local only, never commit):** `android/upload-keystore.jks` + `android/key.properties`. Back these up offline — losing them blocks updates to the same Play listing.### Automated checks

```bash
cd /path/to/clinic-local-llm
python3 data/scripts/build_nnlem_catalog.py
python3 data/scripts/build_nepal_corpus.py
python3 data/scripts/seed_nepal_db.py
python3 qa/run_coverage_report.py
python3 qa/run_eval_queries.py
python3 qa/run_chat_vignette_smoke.py
cd apps/clinical_assistant
flutter test test/chat_gguf_required_test.dart test/chat_vignette_smoke_test.dart test/pii_scrubber_test.dart test/gguf_model_resolve_test.dart
```

### Spot-check (UI)

1. Terms gate: must agree (includes sync) before app  
2. Banner: not-for-clinical-use + offline  
3. Search: full A–Z formulary list; filter via search  
4. Interact: tap Drug A/B → searchable full formulary picker; Azithromycin + Ciprofloxacin → contraindicated  
5. Guides: full OPD condition list; tap condition for linked citations; keyword search also finds chunks  
6. Chat (Linux/Windows + GGUF): `scrub typhus` → grounded answer; without GGUF → **No local model found**  
7. Patients + Notes: create patient, save note with Patient ID  
8. Notes → Saved notes: edit/update saved drafts; generate does not auto-save  
9. Sync: invisible after Terms — interactions enqueue scrubbed rows; uploads run in background (no cloud button)  

### Local draft / Chat LLM

| Surface | Behavior |
|---|---|
| **Chat** | On-device GGUF **required**. Missing/unloadable → error only. |
| **Notes** | GGUF if present; else `InAppDraftEngine` (`in-app-draft-v1`) |
| **Web** | Chat hard-errors (no neural runtime in this slice) |

```bash
cd apps/clinical_assistant
flutter test test/chat_gguf_required_test.dart
flutter run -d linux   # with GGUF in Documents/nepal_clinical/models/
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

### MVP close — Linux + scrub + threat v0.2 (2026-07-21)
- Flutter `linux/` target + `sqflite_common_ffi` desktop DB  
- Reject-to-queue status `blocked_residual_pii` + native `scrub_note`; PI-03 tests  
- Threat model v0.2; ADR-002 Linux; ADR-004 transparency UI marked shipped  

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
- [x] Further corpus growth toward Nepal coverage % (track via eval dashboards)
- [x] Replace Flutter app README; consolidate docs; commit/push Slice B
- [x] LLM status banner + Chat GGUF-required path
- [x] Linux desktop GGUF Chat path

### 2. Retrieval / RAG (coverage engine → 90% Nepal situations)
- [x] Shared retrieve API for Interact / Guidelines / Chat / future training exports
- [x] Grow curated local corpus further (NTC/WHO-adapted + OPD vignettes) — **120 OPD conditions, 494 drugs (NNLEM 2021 full catalog), 111 guides**
- [x] sqlite-vec or embedding hybrid when FTS plateaus — **guidelines_fts + hybrid re-rank in Python/Dart**
- [x] Eval: coverage + recall dashboards (beyond 50 smoke queries) — `qa/run_coverage_report.py`

### 3. Chat agent
- [x] ADR-003 chat scope (cite-or-refuse, no severity invention)
- [x] Chat tab + retrieve-then-answer + citations + refuse path
- [x] Stronger grounded LLM prompt path (GGUF-only; no rules fallback)
- [x] Discuss past notes / sessions in context (local unredacted history) — unified chat retrieve
- [x] Structured feedback (up/down + reason codes)
- [x] Eval smoke on synthetic chat vignettes — `qa/run_chat_vignette_smoke.py`

### 4. Consent + scrub pipeline (flywheel gate)
- [x] Unified first-launch Terms + data-sync consent (single gate; Consent tab removed)
- [x] Production scrubber (>99% recall) — regex + Nepal name/place heuristics
- [x] SQLCipher / encrypted local DB — field-level patient encryption (`DbCrypto`); native SQLCipher deferred
- [x] Reject-to-queue rules + threat-model v0.2
- [ ] Lawyer review of `np-terms-1.2` — **external pilot gate** (not engineering)

### 5. Sync & data flywheel — **post-MVP**
- [x] Local `sync_queue` stub (scrubbed payloads after Terms accept)
- [x] ADR-004 + local `services/ingest-api` + `SyncWorker.flushPending` (**on after Terms**; no off switch)
- [x] Supabase Mumbai scaffold (`sync_ingest` + Edge Function `ingest-batch`)
- [x] Deploy linked Mumbai project + confirmed `sync_ingest` (app via `INGEST_BASE_URL` / `INGEST_ANON_KEY`)
- [x] Continuous invisible sync (`SyncCoordinator`: enqueue wake + 30s + resume; Terms-only disclosure)
- [x] ~~Transparency UI~~ removed — disclosure via Terms only
- [ ] Curated corpus pipeline from `sync_ingest`

### 6. LLM packaging & model enhancement — **post-MVP**
- [x] On-device GGUF runtime (Linux/Windows/Android) + Chat hard-require  
- [ ] Device-tier detection; smaller default GGUF for low-RAM phones  
- [ ] Fine-tune/adapters only after consented scrubbed corpora  
- [ ] Signed OTA model delivery  

### 7. EMR / distribution (later)
- [ ] Full EMR (visits, prescriptions, facility workflows) — **beyond** current patient cards  
- [x] Signed Play AAB `1.0.0+3` (`flutter build appbundle --release`) — artifact under `build/app/outputs/bundle/release/`  
- [ ] Upload AAB to Play Console internal testing; India scale-up  


---

## Doc map

| Doc | Role |
|---|---|
| **This file** | Current status + run + backlog + flywheel thesis |
| [`docs/architecture/ADR-001-stack.md`](architecture/ADR-001-stack.md) | Stack lock |
| [`docs/architecture/ADR-002-local-llm-poc.md`](architecture/ADR-002-local-llm-poc.md) | On-device GGUF; Chat hard-requires model |
| [`docs/architecture/ADR-003-chat-rag.md`](architecture/ADR-003-chat-rag.md) | Chat RAG-first |
| [`docs/architecture/ADR-004-sync-ingest.md`](architecture/ADR-004-sync-ingest.md) | De-id sync → Supabase Mumbai (local stub retained) |
| [`docs/security/threat-model-v0.2.md`](security/threat-model-v0.2.md) | Current threat model (MVP close) |
| [`docs/security/threat-model-v0.1.md`](security/threat-model-v0.1.md) | Historical 8h MVP threat model |
| [`qa/test-plan-p0.md`](../qa/test-plan-p0.md) | Detailed test cases |
| [`clinical-llm-technical-architecture.md`](../clinical-llm-technical-architecture.md) | Long-horizon architecture |
| [`clinical-llm-venture-analysis.md`](../clinical-llm-venture-analysis.md) | Venture context |

**Do not recreate** per-sprint checkpoint runbooks — update **this** file instead.

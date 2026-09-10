# Nepal Clinical Assistant

Offline-first clinical reference for Nepal OPD settings: drug search, interactions, guidelines, grounded Chat, note drafting, and a lightweight patient registry.

**Not for clinical use.** Repo fixtures are synthetic until a real pilot legal path exists.

| | |
|---|---|
| **Product** | Flutter app — Android-first (also Linux / Windows; web UI without neural Chat) |
| **Chat LLM** | On-device **Qwen2.5-1.5B Instruct Q4_K_M** (GGUF / llama.cpp) |
| **Sync** | Scrubbed payloads → **Supabase Mumbai** (`ingest-batch`); local FastAPI stub for dev |
| **Status / runbook** | [`docs/STATUS.md`](docs/STATUS.md) — shipped surface, how to run, backlog |

---

## Repo structure

```text
clinic-local-llm/
├── apps/clinical_assistant/     # Flutter product app (Play AAB target)
│   ├── lib/                     # UI, SQLite, RAG retrieve, GGUF runtime, sync
│   ├── assets/nepal/            # Bundled fixtures (drugs, interactions, guides…)
│   ├── android|linux|windows|web/
│   └── test/
├── packages/clinical_core_py/   # Shared Python retrieve / scrub / domain helpers
├── data/
│   ├── nepal/                   # Source JSON fixtures + eval sets
│   ├── schema/                  # SQLite MVP schema
│   └── scripts/                 # Catalog / corpus / seed builders
├── services/ingest-api/         # Local FastAPI ingest stub (dev)
├── supabase/                    # Mumbai prod: migrations + Edge Function ingest-batch
├── qa/                          # Gold evals, coverage, chat vignette smokes
├── docs/                        # STATUS, ADRs, threat model, Play store assets
├── artifacts/                   # Generated eval / coverage reports
└── .github/workflows/           # Fixture + gold-eval CI
```

Long-horizon design: [`clinical-llm-technical-architecture.md`](clinical-llm-technical-architecture.md).  
Venture context: [`clinical-llm-venture-analysis.md`](clinical-llm-venture-analysis.md).

---

## Major technical decisions

### Flutter app (not React Native / native-only)

- **Why:** One codebase for Android field devices plus Linux/Windows demos; offline SQLite and native FFI for llama.cpp fit Flutter well.
- **Android-first** (minSdk 29 for GGUF). iOS not started.
- **Local store:** SQLite (`sqflite` / FFI on desktop). Interaction **severity is DB-only** — never invented by the LLM.
- **Search / RAG:** FTS + token retrieve first (`ClinicalRetriever` / `clinical_core_py.retrieve`); embeddings deferred until FTS plateaus.
- Details: [`docs/architecture/ADR-001-stack.md`](docs/architecture/ADR-001-stack.md).

### On-device Qwen GGUF (not Ollama, not cloud Chat)

- **Why:** Clinics need offline Chat; phones will not run an Ollama sidecar; product Chat must not fake answers with a rules engine.
- **Runtime:** `llamadart` (llama.cpp) on Linux / Windows / Android. Web Chat → explicit “no model” until a later WebGPU path.
- **Model:** Qwen2.5-1.5B-Instruct Q4_K_M (~1.1 GB). Too large for the Play base AAB; weights stay out of git.
- **Phone delivery:** thin AAB + in-app HTTPS download from Hugging Face into app Documents (`nepal_clinical/models/`), SHA-256 verified, then offline forever. Manual Documents placement still works for desktop/dev.
- **Policy:** Chat **hard-requires** GGUF. Notes may use an in-app SOAP assembler when no model is present.
- Details: [`docs/architecture/ADR-002-local-llm-poc.md`](docs/architecture/ADR-002-local-llm-poc.md), [`ADR-003-chat-rag.md`](docs/architecture/ADR-003-chat-rag.md).

### Supabase Mumbai for sync (not Firebase / not AWS-first)

- **Why:** Early volume is small; Mumbai (ap-south-1) keeps ingest near India for residency posture; Edge Function + Postgres without standing up RDS/App Runner yet.
- **What syncs:** scrubbed `sync_queue` copies only (after first-launch Terms). Local history stays unredacted on device. Patient registry does **not** sync.
- **Gate:** high-recall PII scrub before enqueue; residual PII → `blocked_residual_pii` (not flushed). Server Edge Function re-validates.
- **Dev:** `services/ingest-api` on `127.0.0.1:8787`. **Prod:** `--dart-define=INGEST_BASE_URL=…` + `INGEST_ANON_KEY=…`.
- Explicit non-choice: Firebase. AWS remains an optional later scale path (OTA objects, volume, counsel).
- Details: [`docs/architecture/ADR-004-sync-ingest.md`](docs/architecture/ADR-004-sync-ingest.md), [`supabase/README.md`](supabase/README.md).

### Consent, scrub, and data flywheel

```text
Use (search / chat / notes / …)
  → local session log (unredacted)
  → scrub → sync_queue (Terms-authorized)
  → Supabase ingest → curated Nepal corpus + evals
  → better retrieval (+ later adapters) → OTA back to devices
```

Terms (`np-terms-1.2`) are a **required** first-launch gate; after accept, sync is always on (no in-app off switch). Threat model: [`docs/security/threat-model-v0.2.md`](docs/security/threat-model-v0.2.md).

---

## Quick start

Full runbook (web, Linux+GGUF, Android AAB, tests): **[`docs/STATUS.md`](docs/STATUS.md)**.

```bash
# Web UI demo (Chat has no neural model on web)
cd apps/clinical_assistant && flutter build web --release
cd build/web && python -m http.server 8090

# Linux Chat with on-device Qwen (place GGUF or use in-app Download)
# → ~/Documents/nepal_clinical/models/qwen2.5-1.5b-instruct-q4_k_m.gguf
cd apps/clinical_assistant && flutter run -d linux

# Fixture / gold evals
python3 qa/run_eval_queries.py
cd apps/clinical_assistant && flutter test
```

Play artifact: signed AAB under `apps/clinical_assistant/build/app/outputs/bundle/release/` (see STATUS for current version).

---

## Docs map

| Doc | Role |
|---|---|
| [`docs/STATUS.md`](docs/STATUS.md) | Current status, run commands, ordered backlog |
| [`docs/architecture/ADR-00*.md`](docs/architecture/) | Stack, GGUF Chat, RAG Chat, sync ingest |
| [`docs/security/`](docs/security/) | Threat model |
| [`docs/store/`](docs/store/) | Play listing graphics |
| [`docs/privacy/`](docs/privacy/) | Privacy policy (GitHub Pages) |
| [`qa/`](qa/) | Eval runners and P0 test plan |

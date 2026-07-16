# Nepal Clinical Assistant — Development Status

**Last updated:** 2026-07-16  
**Single source of truth** for what’s shipped, how to run it, and what’s next.  
Long-term design target: [`clinical-llm-technical-architecture.md`](../clinical-llm-technical-architecture.md).

---

## Where we are now

| Area | Status | Notes |
|---|---|---|
| Flutter clinical reference UI | **Shipped** | Search, Interact, Guidelines, Notes, Consent |
| Offline Nepal fixtures (50 drugs / 35 interactions / 18 guidelines) | **Shipped** | `data/nepal/` + app assets |
| Deterministic interaction severity | **Shipped** | DB only; never invented |
| Gold eval (`eval_queries.jsonl`) | **Shipped** | 40/40 pass (`artifacts/eval_gold_report.md`) |
| Interaction catalog integrity | **Shipped** | 35/35 bidirectional (`qa/run_fixture_evals.py`) |
| Consent default OFF + sync blocked UI | **Shipped** | No real network sync |
| Regex PII scrubber (Dart + Python) | **Shipped** | ~30% name/place recall; NER deferred |
| Local clinical session log (scrubbed) | **Shipped** | Web: in-memory; native: SQLite |
| Guideline citations / unknown-pair retrieval | **Shipped** | FTS native + token search |
| Local LLM note-drafter POC | **Shipped (code)** | Ollama sidecar + CORS proxy + fixture fallback; **Ollama not installed on this machine yet** |
| Master status doc | **Shipped** | This file; old sprint checkpoint/demo runbooks removed |
| SQLCipher / encrypted DB | **Not started** | Deprioritized |
| Cloud sync / ingest / OTA | **Not started** | |
| On-device JNI llama.cpp in APK | **Not started** | ADR-002 uses localhost first |
| EMR patient UI | **Not started** | Schema stubs only in SQL seed |
| Play Store / closed testing | **Not started** | |

**Working demo URL (typical):** `http://localhost:8080` (or `:8081` if 8080 is busy).

---

## Guardrails (always)

1. Synthetic Nepal fixtures only — no real PHI in repo or demos  
2. Permanent “not for clinical use” disclaimer  
3. Consent default **OFF**; no clinical upload without opt-in  
4. Interaction severity **only** from local DB  
5. Note drafter = **draft only** (not diagnosis / prescribing authority)  
6. LLM must not invent interaction severity  

---

## How to run

### App (Flutter web)

```powershell
$env:PATH = "C:\Users\UA4\flutter\bin;$env:PATH"
cd c:\Users\UA4\Desktop\clinic-local-llm\apps\clinical_assistant
flutter pub get
flutter run -d web-server --web-port=8080
# open http://localhost:8080
```

### Automated checks

```powershell
cd c:\Users\UA4\Desktop\clinic-local-llm
python qa\run_fixture_evals.py      # interactions + PII report
python qa\run_eval_queries.py       # gold top-k (≥70% gate; currently 100%)
python packages\clinical_core_py\smoke_test.py
```

### Spot-check (UI)

1. Banner: not-for-clinical-use + offline  
2. Search: `Paracetamol` / `प्यारासिटामोल` / `Nepalol`  
3. Interact: Azithromycin + Ciprofloxacin → **contraindicated**  
4. Interact: unrelated pair → no known interaction + **guideline citations**  
5. Guidelines: `diarrhea` / `TB` → citation cards  
6. Consent: default OFF; sync blocked; scrub demo  
7. Notes: sample → Generate (fixture or live model)

### Local LLM (optional live tokens)

```powershell
# Install Ollama: https://ollama.com
ollama pull qwen2.5:1.5b
ollama serve

# Flutter web needs CORS proxy (browser cannot call :11434 directly):
python tools\ollama_cors_proxy.py   # :8765 → Ollama :11434

python packages\clinical_core_py\llm_smoke.py
```

Then **Notes** tab → Generate draft. Amber status = fixture fallback.

---

## Shipped changelog (condensed)

### Slice A — 8h Nepal MVP (2026-07-14)
- Flutter shell + disclaimer; drug search / detail; interaction checker; guidelines; consent  
- Python domain mirror + seed + fixture QA  
- Regex PII scrubber in app + QA; ADR-001 stack lock  

### Slice B — Quality + Retrieval + LLM POC (2026-07-15)
- Multi-token search; gold eval runner (40/40)  
- Clinical sessions log with scrub  
- Guideline FTS + `CitationCard`; unknown-pair retrieval  
- Notes tab + `LocalLlmClient` (ADR-002); CORS proxy tool  
- Eval/reports under `artifacts/`  

### Docs cleanup (2026-07-16)
- Consolidated runbooks/checkpoints into this file  
- Removed `MVP_8H_*` and `SPRINT_QUALITY_LLM_*` docs  
- App README points here; architecture header links here  

---

## Planned next (ordered backlog)

Update checkboxes as work lands. Prefer small vertical slices over parallel open-ended work.

### Near-term (product demo strength)
- [ ] Install/prove live Ollama draft on this machine (web via CORS proxy or Windows device)
- [x] Replace Flutter app README boilerplate with pointer to this file
- [x] Consolidate docs into `docs/STATUS.md`; remove old sprint checkpoint/demo files
- [x] Commit + push Slice B / docs cleanup to `main`
- [ ] Expand formulary / interactions only when eval coverage stays green
- [ ] CI stub: run `run_fixture_evals.py` + `run_eval_queries.py` on PR

### Retrieval / RAG
- [ ] sqlite-vec or embedding hybrid for guidelines (after FTS proves insufficient)
- [ ] Grounded “summarize these citations” path using local LLM (no severity invention)
- [ ] Eval: guideline recall dashboard over time

### Privacy / hardening (was deprioritized)
- [ ] SQLCipher + key management ADR (ADR-003 path)
- [ ] ONNX / NER scrubber toward >99% fixture recall
- [ ] Threat-model refresh when sync exists

### LLM packaging
- [ ] Device-tier detection; model download WiFi-only
- [ ] JNI llama.cpp path for offline Android (post–localhost POC)
- [ ] Signed model manifests / OTA (P4 architecture)

### Sync / backend / EMR (later)
- [ ] Consent-gated sync queue → India-region APIs
- [ ] EMR-ready patient registry UI (schema already stubbed in SQL)
- [ ] Play internal testing track  

---

## Doc map (what to keep reading)

| Doc | Role |
|---|---|
| **This file** | Current status + run + backlog |
| [`docs/architecture/ADR-001-stack.md`](architecture/ADR-001-stack.md) | Stack lock (Flutter, SQLite, FTS-first) |
| [`docs/architecture/ADR-002-local-llm-poc.md`](architecture/ADR-002-local-llm-poc.md) | Local sidecar LLM for notes |
| [`docs/security/threat-model-v0.1.md`](security/threat-model-v0.1.md) | Offline MVP threats |
| [`qa/test-plan-p0.md`](../qa/test-plan-p0.md) | Detailed P0/P1 test cases |
| [`clinical-llm-technical-architecture.md`](../clinical-llm-technical-architecture.md) | Full 36-week / EMR target architecture |
| [`clinical-llm-venture-analysis.md`](../clinical-llm-venture-analysis.md) | Business / venture context |

**Do not recreate** per-sprint checkpoint or duplicate demo runbooks — update **this** file instead.

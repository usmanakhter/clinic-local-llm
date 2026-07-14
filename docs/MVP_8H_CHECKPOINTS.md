# Nepal Clinical AI — 8-Hour MVP Execution Plan

**Date:** 2026-07-14  
**Source:** `clinical-llm-technical-architecture.md` (compressed vertical slice)  
**Pilot data:** `data/nepal/` (synthetic only)

---

## What we are building (today)

A **demo-ready Android-first clinical reference app** for the Nepal pilot:

| In (8h MVP) | Out (defer) |
|---|---|
| Drug search (50 NNLEM-style drugs, FTS) | Full SQLCipher key ceremony / EMR |
| Interaction checker (35 pairs, 100% match target) | On-device LLM / llama.cpp |
| Guideline chunk search (18 WHO/NTC chunks) | Real sync backend / OTA |
| Consent UI default **OFF** (EN + Nepali copy from fixtures) | Lawyer-final privacy policy |
| Regex PII scrubber + fixture eval | ONNX NER model |
| Offline local SQLite from seed script | Play Store / closed testing track |
| Medical disclaimer + “not for clinical use” banner | Market outreach / LOIs |

**Success definition for today:** Installable or runnable app that searches drugs, checks interactions, shows guideline citations, gates sync behind consent, and passes automated fixture checks on seeded pairs + PII cases.

---

## Guardrails (non-negotiable)

1. **Synthetic data only** — never load real patient/clinician PHI into the repo or demos.
2. **Not a diagnostic or prescribing system** — UI must show a permanent disclaimer.
3. **Consent default OFF** — no network egress of clinical content unless explicitly granted.
4. **Deterministic clinical answers** — interaction severity comes from DB only; never invent severity.
5. **No exploit / malware work** — security docs only; no attack tooling.
6. **Medical content is provisional** — dummy formulary until licensed advisor sign-off.
7. **Scope freeze** — if behind schedule, drop note-drafter and polish; keep search + interactions + scrubber + consent.

---

## Parallel workstreams (agents)

| Stream | Owner role | Hours | Deliverable |
|---|---|---|---|
| **S1 Scaffold** | A5 + A6 | 0–2 | Flutter app + packages + CI stub |
| **S2 Data/RAG** | A2 + A7 | 0–3 | Seeded SQLite, FTS search, interaction engine |
| **S3 Privacy** | A3 + A8 | 1–4 | Consent screens + regex scrubber + threat notes |
| **S4 UI** | A4 + A6 | 2–5 | Search, detail, interaction, consent flows |
| **S5 QA** | A9 | 4–8 | Fixture tests, smoke checklist, gate report |

Orchestrator (this session) integrates, unblocks, and runs **CHECK-IN** gates below.

---

## Timeboxed phases

```
H0–H0.5  Align + install Flutter SDK (blocker)
H0.5–H2  Scaffold + DB seed into app assets + domain repos
H2–H5    Drug search + interaction checker (core vertical slice)
H5–H6.5  Consent + PII scrubber + guideline search
H6.5–H8  QA fixtures, polish, demo checklist / APK or web run
```

---

## Check-in gates (you validate)

Reply **APPROVE / CHANGE / BLOCK** at each gate.

### CHECK-IN 1 — Plan & guardrails (now)
- [x] Accept 8h scope table (in/out)
- [x] Accept guardrails
- [x] Accept Flutter as UI (or request web fallback if SDK install fails)

**Status:** `APPROVED` (continue instruction)

### CHECK-IN 2 — Scaffold green (~H2)
- [x] `apps/clinical_assistant` Flutter project exists
- [x] `python data/scripts/seed_nepal_db.py` loads 50/35/18 counts
- [x] App boots to home shell with disclaimer
- [x] Design tokens (EN/Nepali-ready fonts planned)

**Status:** `APPROVED` (continue instruction)

### CHECK-IN 3 — Core clinical slice (~H5)
- [x] Search finds Paracetamol / प्यारासिटामोल / brand “Nepalol”
- [x] Interaction: Azithromycin + Ciprofloxacin → **contraindicated**
- [x] Unknown pair → “no known interaction in local DB” (no invented severity)
- [x] Drug detail shows dose + disclaimer

**Status:** `done` — validated via `clinical_core_py` CLI + Flutter repository parity (2026-07-14)

### CHECK-IN 4 — Privacy slice (~H6.5)
- [x] Consent default OFF; copy from `consent_templates.json`
- [x] Scrubber removes +977 mobiles and sample NMC/HREG/emails (Dart + QA regex); name/place recall residual ~30%
- [x] Sync queue UI shows blocked when consent off; local scrub demo on Consent tab

**Status:** `done` — `lib/privacy/pii_scrubber.dart` + Consent scrub UI

### CHECK-IN 5 — MVP demo (~H8)
- [x] Automated: interaction suite 35/35
- [x] Automated: PII scrubber report on `pii_scrubber_test_cases.json`
- [x] Smoke: offline drug lookup + interaction + guideline hit
- [x] `docs/MVP_8H_DEMO.md` runbook

**Status:** `done` — see `artifacts/qa_fixture_report.md`

---

## Ticket mapping (from Part 13, compressed)

| Ticket | 8h treatment |
|---|---|
| EPIC-P0-S1-A5-001 | Monorepo under `apps/` + `packages/` + ADR stub |
| EPIC-P0-S1-A6-002 | Flutter shell; SQLite first (SQLCipher ADR deferred) |
| EPIC-P0-S1-A2-003 | Ship `data/nepal/` seed as asset bootstrap |
| EPIC-P0-S1-A4-004 | In-code design tokens (skip Figma if time) |
| EPIC-P0-S1-A7-005 | FTS5 first (sqlite-vec later) |
| EPIC-P0-S1-A8-006 | Short threat-model notes |
| EPIC-P0-S1-A9-008 | Fixture-driven tests under `qa/` |
| P1 interaction slice | Included today (35 seeded pairs) |

---

## Blockers log

| ID | Blocker | Mitigation |
|---|---|---|
| B1 | Flutter not on PATH at session start | SDK at `C:\Users\UA4\flutter`; `flutter create` succeeded for `apps/clinical_assistant` |
| B2 | Android emulator may be missing | Prefer `flutter run -d web-server --web-port=8080` for demo |
| B3 | Regex PII scrubber recall 30% | Expected for regex-only; ONNX NER deferred; track as Phase 3 residual |

---

## How to respond

At any check-in, you can say e.g.:

- `APPROVE CI1`
- `CHANGE: prefer web demo over Android for today`
- `BLOCK: do not add any network code`

Orchestrator will not expand scope past the In-table without your OK.

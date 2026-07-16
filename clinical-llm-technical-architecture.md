# Technical Architecture & Sprint Plan: Android-First Clinical AI

**Date:** July 9, 2026  
**Companion to:** `clinical-llm-venture-analysis.md`  
**Current build status (checklist):** [`docs/STATUS.md`](docs/STATUS.md) — use that for shipped work and next backlog; this file is the long-horizon architecture target.  
**Scope:** MVP architecture, EMR expansion path, specialized agent system, daily epic/sprint cycles  
**Pilot market:** Nepal first — **<30 clinicians** before India scale-up  
**Dummy data:** `data/nepal/` (see `data/README.md`)

---

## Part 0: Nepal Pilot — Launch Constraints

### Why Nepal first

| Factor | Nepal pilot advantage |
|---|---|
| Clinician pool | ~12K doctors — small enough for hand-onboarding <30 users |
| Regulatory | Lighter framework than India DPDPA; build consent habits early |
| Language | Nepali + English code-mix — tests multilingual stack before Hindi expansion |
| Disease profile | TB, dengue, malaria (Terai), snakebite, altitude illness — validates RAG corpus |
| Distribution | NMA / medical college networks (Kathmandu, Pokhara, Biratnagar) reachable directly |

### Pilot success criteria (Nepal MVP)

| Metric | Target |
|---|---|
| Clinicians onboarded | **25–30 active** (not 10K) |
| Active = ≥3 sessions/week | ≥20 of onboarded |
| Opt-in data sharing | ≥40% of active (12+ clinicians) |
| Drug lookup latency (T0) | <2s on 4GB Android |
| Interaction checker accuracy | 100% on seeded top-35 pairs |
| PII scrubber recall | >99% on `pii_scrubber_test_cases.json` |
| Clinician "useful" rating | ≥70% on 40 `eval_queries.jsonl` |

### Nepal-specific stack adjustments

| Component | India plan | Nepal pilot |
|---|---|---|
| Formulary | NLEM | **NNLEM-style subset** (50 drugs in dummy data) |
| Consent UI | EN + Hindi | **EN + Nepali (नेपाली)** |
| Guidelines | ICMR-heavy | **WHO + Nepal MoHP / NTC (dummy chunks)** |
| Backend region | AWS Mumbai | AWS Mumbai or **Singapore** (Nepal residency TBD with counsel) |
| PII patterns | ABHA, Aadhaar | **+977 mobile, NMC ID, citizenship format** |
| GTM channel | IMA WhatsApp | **NMA, KU/IOM residents, district hospital chiefs** |

### Dummy data package (`data/`)

```
data/
├── README.md
├── schema/mvp_schema.sql
└── nepal/
    ├── drugs.json              (50 essential medicines)
    ├── interactions.json       (35 pairs)
    ├── guideline_chunks.json   (18 RAG chunks)
    ├── eval_queries.jsonl      (40 QA gold queries)
    ├── pilot_clinicians.json   (28 fictional pilot users)
    ├── clinical_sessions_dummy.json
    ├── sync_queue_dummy.json
    ├── consent_templates.json
    ├── pii_scrubber_test_cases.json
    └── note_drafter_samples.json
```

---

## Part 1: Product Scope Definition

### MVP (Months 0–9): Clinical AI Assistant — Not an EMR

| In scope | Out of scope (MVP) |
|---|---|
| Drug reference + interaction checker (RAG-first) | Full patient records / longitudinal charts |
| Offline NNLEM + WHO + Nepal guideline knowledge base | Billing, insurance claims, lab orders |
| Optional local LLM for note drafting | Multi-user clinic workflows |
| Clinician opt-in consent + on-device PII scrub | ABDM FHIR integration |
| WiFi-only de-identified sync | Appointment scheduling |
| OTA model updates | Prescription printing / e-Rx compliance |

**MVP positioning:** A free, offline clinical reference tool that happens to collect consented, de-identified interaction data. Not marketed as diagnosis or EMR.

### Full Platform (Years 2–4): Lightweight EMR + AI

South Asian EMR replacement is not "copy Epic." It is a **mobile-first, low-friction practice management layer** for solo practitioners and small clinics (80%+ of Indian clinical volume).

| EMR module | South Asia priority | Complexity |
|---|---|---|
| Patient registry (name, age, phone, visit history) | Critical | Medium |
| Visit notes + vitals | Critical | Medium |
| E-prescription (NLEM-aware) | Critical | High (state compliance) |
| Lab/imaging orders (basic) | High | Medium |
| Billing + receipts | High | Medium |
| ABDM/ABHA integration | High (India) | Very High |
| Inventory/pharmacy | Medium | Medium |
| Multi-doctor clinic scheduling | Medium | High |
| Insurance/TPA claims | Low (MVP+) | Very High |

**Verdict:** MVP should **not** be built as EMR. Architecture must **anticipate** EMR modules via a patient-centric data model from day one, but ship only the drug-reference wedge first.

---

## Part 2: MVP Android-First Architecture

### 2.1 High-Level System Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  ANDROID DEVICE (PHI boundary)                               │
│                                                              │
│  ┌─────────────┐    ┌──────────────────┐    ┌─────────────┐ │
│  │ Flutter UI  │───▶│ Feature          │───▶│ Local Store │ │
│  │ Layer       │    │ Orchestrator     │    │ SQLCipher   │ │
│  └─────────────┘    └────────┬─────────┘    └─────────────┘ │
│                              │                               │
│         ┌────────────────────┼────────────────────┐          │
│         ▼                    ▼                    ▼          │
│  ┌─────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │ RAG Engine  │    │ Local LLM    │    │ PII Scrubber │   │
│  │ sqlite-vec  │    │ llama.cpp    │    │ NER + regex  │   │
│  └──────┬──────┘    └──────────────┘    └──────┬───────┘   │
│         ▼                                        ▼           │
│  ┌─────────────┐                        ┌──────────────┐   │
│  │ Knowledge   │                        │ Sync Worker  │   │
│  │ Base (NLEM) │                        │ WorkManager  │   │
│  └─────────────┘                        └──────┬───────┘   │
└────────────────────────────────────────────────┼───────────┘
                                                 │ de-id only
                                                 ▼
┌─────────────────────────────────────────────────────────────┐
│  INDIA-REGION BACKEND (AWS ap-south-1)                       │
│  Consent API │ Ingest API │ OTA CDN │ Fine-tune Pipeline    │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Layered Architecture (On-Device)

```
┌─────────────────────────────────────────────────────────────┐
│  PRESENTATION (Flutter)                                      │
│  - Drug search, interaction checker, note drafter           │
│  - Consent dashboard, data transparency UI                   │
│  - Settings: language, model tier, sync preferences          │
├─────────────────────────────────────────────────────────────┤
│  APPLICATION (Dart + platform channels)                      │
│  - Use-case controllers (DrugLookup, InteractionCheck, etc.) │
│  - Session manager, consent gatekeeper                       │
│  - Capability detector (RAM → model tier selection)          │
├─────────────────────────────────────────────────────────────┤
│  DOMAIN                                                       │
│  - Drug, Interaction, ClinicalQuery, ConsentRecord entities  │
│  - Repository interfaces (no Android/Flutter deps)           │
├─────────────────────────────────────────────────────────────┤
│  INFRASTRUCTURE                                               │
│  - SQLCipher (encrypted local DB)                            │
│  - RAG: sqlite-vec + BM25 hybrid retrieval                   │
│  - LLM: llama.cpp JNI (primary) or MNN fallback              │
│  - PII: ONNX Runtime NER model (~50MB)                       │
│  - Sync: WorkManager + Retrofit/Dio (HTTPS only)             │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 Technology Stack (Locked Decisions)

| Component | Choice | Rationale |
|---|---|---|
| UI | **Flutter 3.x** (Android first) | Large India dev pool; single codebase for iOS later |
| Local DB | **SQLCipher** via `sqflite_sqlcipher` | PHI at rest encryption; required for EMR path |
| Vector search | **sqlite-vec** + FTS5 BM25 | Offline; <100MB index for NLEM |
| LLM runtime | **llama.cpp** (primary), MNN eval on Snapdragon | Battle-tested GGUF; NNAPI acceleration |
| Default model | **Qwen2.5-3B-Instruct Q4_K_M** (~1.8GB) | Hindi/Urdu/Bengali; MIT license |
| Fallback model | **Qwen2.5-1.5B Q4** for 4GB RAM | Graceful degradation |
| PII NER | Fine-tuned **mBERT/XLM-R** → ONNX | Code-mixed Hindi/English |
| Backend | **Kotlin/Spring Boot** or **Go** on AWS Mumbai | India data residency (DPDPA) |
| Auth | Device-bound key + optional phone OTP | No account friction for MVP |
| Analytics | **PostHog** (self-hosted, India) or Plausible | Privacy-respecting; no PHI in events |

### 2.4 MVP Feature Modules

#### Module A: Drug Reference (RAG-only, no LLM required)

```
User query → normalize (brand/generic mapping) → hybrid retrieval
  → ranked NLEM entries + interaction warnings → structured UI cards
```

- Zero hallucination risk if answers are retrieval-only with source citations
- LLM optional for natural-language query parsing on capable devices

#### Module B: Interaction Checker (deterministic + RAG)

```
Drug A + Drug B → local interaction DB lookup → severity classification
  → if ambiguous, RAG over ICMR/WHO guidelines → cited recommendation
```

- Rule engine for known interactions (DrugBank subset + India-specific)
- LLM never invents interaction severity

#### Module C: Clinical Note Drafter (LLM + template)

```
Structured input (symptoms, findings) → prompt template → local LLM
  → editable draft → save locally (encrypted, not synced by default)
```

#### Module D: Consent & Data Transparency

```
Install → bilingual consent screen (EN + Nepali) → default OFF
  → opt-in → scope selection → audit log visible to clinician
  → "delete my data" → server purge + local wipe
```

#### Module E: Sync & Flywheel (opt-in only)

```
Session end → PII scrubber (blocking) → de-id payload
  → WiFi-only WorkManager job → India-region API
  → clinician feedback (thumbs) attached
```

### 2.5 On-Device Data Model (EMR-Ready Foundation)

```sql
-- MVP tables (ship now)
CREATE TABLE drugs (id, generic_name, brand_names_json, nlem_tier, ...);
CREATE TABLE interactions (drug_a_id, drug_b_id, severity, source, ...);
CREATE TABLE clinical_sessions (id, created_at, query_type, input_hash, ...);
CREATE TABLE consent_records (scope, granted_at, version, ...);
CREATE TABLE sync_queue (payload_json, scrubbed_at, status, ...);

-- EMR tables (schema only, empty until Phase 2)
CREATE TABLE patients (id, local_id, display_name_enc, age_decade, sex, ...);
CREATE TABLE visits (id, patient_id, session_id, vitals_json, ...);
CREATE TABLE prescriptions (id, visit_id, drugs_json, ...);
```

**Key principle:** `clinical_sessions` links to optional `patient_id` (nullable in MVP). When EMR ships, sessions attach to patients without schema rewrite.

### 2.6 Device Capability Tiers

| Tier | Detection | Model | Features enabled |
|---|---|---|---|
| T0 (4GB RAM) | `ActivityManager.getMemoryInfo()` | 1.5B or RAG-only | Drug lookup, interactions only |
| T1 (6GB RAM) | Default | 3B Q4_K_M | + note drafting, NL query parsing |
| T2 (8GB+ RAM) | Optional download | 7B Q4 | + richer DDx checklists (Phase 2) |
| T3 (clinic device) | Manual override | Cloud fallback (opt-in) | Heavy tasks via consent |

### 2.7 Backend MVP (Minimal)

```
Services:
  1. consent-api       — register device, consent scope, audit trail
  2. ingest-api        — receive de-id interaction batches (HMAC-signed)
  3. ota-api           — model manifest + differential GGUF patches
  4. admin-dashboard   — internal only; data quality monitoring

Infra:
  - AWS ap-south-1 (Mumbai) — DPDPA data residency
  - RDS PostgreSQL (consent + metadata only, no PHI)
  - S3 (de-id interaction corpus, encrypted at rest)
  - No patient data in cloud until explicit EMR cloud sync (Phase 3)
```

### 2.8 Security Architecture

| Layer | Control |
|---|---|
| At rest (device) | SQLCipher AES-256; Android Keystore for DB key |
| In transit | TLS 1.3; certificate pinning |
| PII scrubbing | Blocking gate — sync API rejects payloads failing scrub validation |
| Consent | Versioned consent text; scope-limited ingestion |
| Model updates | Signed manifests; hash verification before load |
| Logging | No PHI in crash logs; Sentry with scrubbing rules |

### 2.9 MVP Build Phases (9 months)

| Phase | Duration | Deliverable |
|---|---|---|
| **P0: Foundation** | Weeks 1–6 | Flutter shell, SQLCipher, NLEM DB ingest, drug search UI |
| **P1: RAG Core** | Weeks 7–12 | Interaction checker, hybrid retrieval, offline validation |
| **P2: LLM Integration** | Weeks 13–18 | llama.cpp JNI, tier detection, note drafter |
| **P3: Privacy Layer** | Weeks 19–24 | PII NER, consent UI, scrubbing pipeline |
| **P4: Sync + Backend** | Weeks 25–30 | India backend, opt-in sync, data transparency dashboard |
| **P5: Pilot** | Weeks 31–36 | 3 clinic pilots, 10K clinician beta, OTA update v1 |

---

## Part 3: EMR Replacement — Full Platform Assessment

### 3.1 What "EMR Replacement" Means in South Asia

| Western EMR assumption | South Asia reality | Design implication |
|---|---|---|
| Desktop-first, always online | Phone-first, intermittent connectivity | Offline-first CRDT or last-write-wins sync |
| HIPAA drives architecture | DPDPA consent-based | Consent + de-id at every boundary |
| Epic/Cerner interoperability | ABDM FHIR + fragmented state e-Rx | India-first integration, not HL7-first |
| $50K+/year per clinician | Free or ₹500/month max | No per-seat cloud inference cost |
| Structured data entry | Voice + free text + code-mixing | LLM-assisted capture, not forms-heavy |

### 3.2 EMR Feature Roadmap vs. MVP Foundation

| Feature | Depends on MVP | New work | Timeline |
|---|---|---|---|
| Patient registry | SQLCipher, local DB patterns | CRUD UI, search | Phase 2 (M12–18) |
| Visit documentation | Note drafter, clinical_sessions | Patient linkage, vitals forms | Phase 2 |
| E-prescription | Drug DB, interaction checker | State compliance, print/PDF | Phase 2–3 |
| ABDM/ABHA | Backend auth patterns | FHIR gateway, HIP/HRP registration | Phase 3 (M18–30) |
| Multi-device clinic sync | Sync infrastructure | Conflict resolution, roles/RBAC | Phase 3 |
| Lab orders | Patient + visit model | Partner integrations | Phase 3–4 |
| Billing | Patient model | GST invoicing, UPI | Phase 3–4 |
| Insurance/TPA | Full EMR | High complexity; partner or skip | Phase 4+ |

### 3.3 EMR vs. MVP: Strategic Assessment

| Dimension | MVP (AI assistant) | Full EMR |
|---|---|---|
| Time to market | 6–9 months | 24–36 months |
| Regulatory risk | Low (reference tool) | High (e-Rx, ABDM, state medical councils) |
| Competition | Weak (no offline LLM player) | Strong (Healthplix, Practo Ray, Lybrate) |
| Data moat value | Interaction Q&A pairs | Longitudinal treatment pathways ($$$) |
| Switching cost | Low | High (patient data lock-in) |
| Revenue | Data licensing | SaaS + data + enterprise |

**Recommendation:** Pursue EMR as **Phase 2 wedge expansion**, not MVP scope. The MVP builds trust and distribution; EMR builds retention and ARR.

### 3.4 EMR Architecture Principles (Design Now, Build Later)

1. **Patient data never leaves device unencrypted** — cloud sync is opt-in per clinic, E2E encrypted
2. **AI assistant reads patient context locally** — LLM sees visit history on-device only
3. **Modular monolith on mobile** — feature flags enable EMR modules without app fork
4. **ABDM as adapter, not core** — FHIR gateway behind interface; app works without ABDM
5. **Sync protocol abstracted** — start with simple encrypted backup; evolve to CRDT

### 3.5 Competitive Positioning as EMR

| Competitor | Strength | Your differentiation |
|---|---|---|
| Healthplix | Established India EMR | Offline AI, free tier, regional disease tuning |
| Practo Ray | Brand + distribution | Local LLM, no cloud dependency, data moat |
| Eka.care | ABHA integration | Clinician-first (not patient-first), AI-native |
| OpenMRS | Open source EMR | Mobile-native, South Asia tuned, no server required |

**Winning EMR angle:** "The only EMR with a clinician AI co-pilot that works without internet, tuned for TB/dengue/NLEM, free for solo doctors."

---

## Part 4: Specialized Agent System

### 4.1 Agent Roster

| ID | Agent | Primary outputs |
|---|---|---|
| A1 | **Market Researcher** | LOIs, surveys, channel validation |
| A2 | **Medical Expert** | Drug DB, interaction rules, safety policy |
| A3 | **Regulatory & Privacy** | Consent copy, compliance checklists, legal review |
| A4 | **UI/UX Designer** | Figma specs, widget library, accessibility |
| A5 | **Architecture** | ADRs, schemas, API contracts, CI/CD |
| A6 | **Android/Flutter** | Flutter app, JNI, Play Store builds |
| A7 | **ML/LLM** | GGUF builds, RAG tuning, NER models |
| A8 | **Security & Privacy** | Threat models, pen tests, scrubber audits |
| A9 | **QA & Clinical Validation** | Test suites, pilot reports, regression |

### 4.2 Agent Interaction Protocol

Each agent produces **structured artifacts** consumed by downstream agents:

```yaml
artifact_type: clinical_knowledge_pack
version: 1.2.0
contents:
  - nlem_drugs.json
  - interaction_rules.json
  - prompt_templates/
  - safety_policy.md
  - eval_queries.jsonl
downstream_consumers: [ML/LLM Agent, QA Agent, Android Agent]
```

### 4.3 Human Roles (Cannot Be Agent-Only)

| Role | Why human-required |
|---|---|
| Licensed physician advisor | Clinical liability, guideline interpretation |
| Indian privacy lawyer | DPDPA legal sign-off |
| Product lead / orchestrator | Priority calls, ethical tradeoffs |
| Pilot clinic champions | Real-world feedback, trust building |
| Pharma BD | LOI negotiations |

---

## Part 5: Repository Structure

```
clinical-ai/
├── apps/android/                 # Flutter app
│   ├── lib/features/
│   │   ├── drug_reference/
│   │   ├── interactions/
│   │   ├── note_drafter/
│   │   ├── consent/
│   │   └── settings/
│   └── android/                  # JNI llama.cpp, ONNX NER
├── packages/
│   ├── clinical_domain/
│   ├── rag_engine/
│   └── pii_scrubber/
├── services/
│   ├── consent-api/
│   ├── ingest-api/
│   └── ota-api/
├── ml/
│   ├── models/
│   ├── fine_tune/
│   ├── eval/
│   └── pii_ner/
├── knowledge/
│   ├── nlem/
│   ├── who_protocols/
│   └── icmr_guidelines/
├── agents/                       # Agent prompt templates
└── docs/adr/
```

---

## Part 6: Architecture Decision Records

| ADR | Decision | Rationale |
|---|---|---|
| ADR-001 | Flutter over native Android | Speed + iOS path; India talent pool |
| ADR-002 | RAG-first, LLM-second for MVP | Eliminates hallucination in core use case |
| ADR-003 | SQLCipher from day one | EMR path requires encrypted PHI storage |
| ADR-004 | Patient_id nullable in sessions | Avoids migration when EMR ships |
| ADR-005 | India-only cloud for MVP sync | DPDPA data residency |
| ADR-006 | No "diagnosis" in product copy | Clinical safety + regulatory |
| ADR-007 | WiFi-only sync default | Data cost + accidental upload prevention |
| ADR-008 | Qwen2.5-3B default model | Hindi/multilingual + MIT license |
| ADR-009 | Modular monolith, not microservices on mobile | Offline complexity; single APK |
| ADR-010 | FHIR adapter interface (unimplemented) | ABDM readiness without building now |

---

## Part 7: Epic & Sprint Cycle Framework

### 7.1 Cadence Overview

| Rhythm | Duration | Purpose |
|---|---|---|
| **Epic** | 6 weeks (1 phase) | Major capability milestone (P0–P5) |
| **Sprint** | 2 weeks | Shippable increment with demo |
| **Daily cycle** | 1 day | Agent task execution + handoffs |
| **Weekly sync** | 30 min (Mon) | Sprint planning, blockers |
| **Fortnightly demo** | 45 min (Fri, sprint end) | Cross-agent integration review |
| **Epic retro** | 60 min (end of week 6) | Go/no-go for next phase |

```
EPIC (6 weeks = 3 sprints)
├── Sprint 1 (Weeks 1–2)  → vertical slice / spike
├── Sprint 2 (Weeks 3–4)  → core feature complete
└── Sprint 3 (Weeks 5–6)  → harden, test, ship epic milestone
```

### 7.2 Daily Cycle Template

Every working day follows the same five-block rhythm. The **Orchestrator** (product/tech lead) runs the 15-minute morning standup and assigns day tickets.

```
┌──────────────────────────────────────────────────────────────────┐
│  DAILY CYCLE (Mon–Fri)                                            │
├──────────────────────────────────────────────────────────────────┤
│  09:00  STANDUP (15 min)                                          │
│         Each agent: yesterday / today / blockers                  │
│         Orchestrator assigns DAY-XXX tickets                      │
├──────────────────────────────────────────────────────────────────┤
│  09:15–12:00  DEEP WORK BLOCK 1                                   │
│         Primary agent executes assigned epic story                │
│         No cross-agent meetings unless blocker                    │
├──────────────────────────────────────────────────────────────────┤
│  12:00–12:30  HANDOFF WINDOW                                      │
│         Upstream agent publishes artifact to /artifacts/          │
│         Downstream agent acknowledges receipt                       │
├──────────────────────────────────────────────────────────────────┤
│  12:30–16:00  DEEP WORK BLOCK 2                                   │
│         Integration work, reviews, tests                          │
├──────────────────────────────────────────────────────────────────┤
│  16:00–16:30  DAILY CLOSE                                         │
│         Update ticket status; log blockers in BLOCKERS.md         │
│         QA Agent runs smoke checklist if build exists             │
├──────────────────────────────────────────────────────────────────┤
│  16:30+       OPTIONAL PAIRING                                    │
│         Android ↔ ML, Medical ↔ QA, Security ↔ Regulatory         │
└──────────────────────────────────────────────────────────────────┘
```

### 7.3 Ticket Naming Convention

```
EPIC-{phase}-{sprint}-{agent}-{seq}

Examples:
  EPIC-P0-S1-A5-001   Architecture: monorepo scaffold ADR
  EPIC-P0-S1-A6-002   Android: Flutter shell + SQLCipher POC
  EPIC-P0-S1-A2-003   Medical: NLEM ingest spec v0.1
```

**Statuses:** `backlog` → `ready` → `in_progress` → `review` → `done` → `blocked`

### 7.4 Agent Capacity Model

Assume each agent = 1 FTE equivalent (human or AI-assisted). Daily capacity: **6 hours deep work** (remaining time = standup, handoffs, reviews).

| Agent | Typical daily work |
|---|---|
| A1 Market | 2 outreach emails, 1 survey analysis, competitor scan |
| A2 Medical | 50 drug entries reviewed, 1 safety policy section |
| A3 Regulatory | 1 compliance checklist section, consent copy review |
| A4 UI/UX | 1 screen wireframe → hi-fi, 1 component spec |
| A5 Architecture | 1 ADR, 1 API/schema PR review |
| A6 Android | 1–2 PRs (feature or fix), 1 integration test |
| A7 ML/LLM | 1 eval run, 1 model/RAG experiment, metrics log |
| A8 Security | 1 threat review, scrubber test batch (100 sentences) |
| A9 QA | 20 test cases, 1 regression pass, 1 bug report |

### 7.5 Definition of Done (All Agents)

- [ ] Artifact committed to repo or linked in sprint board
- [ ] Downstream consumers notified (handoff YAML updated)
- [ ] No PHI in artifacts unless explicitly encrypted test fixtures
- [ ] Medical Expert sign-off for any clinical content change
- [ ] Security review for any sync/network code change

---

## Part 8: Epic Schedule (36 Weeks to MVP Pilot)

### Epic 0: Pre-Build Validation (Weeks -8 to 0)

**Goal:** De-risk revenue and compliance before code.

| Sprint | Focus | Key deliverables |
|---|---|---|
| S0.1 | Market validation | 2 pharma LOI drafts sent; 200-clinician opt-in survey live |
| S0.2 | Clinical + legal | NLEM source licensed; DPDPA consent flow lawyer review |
| S0.3 | Technical spikes | Qwen 3B on Redmi 4GB latency report; PII NER baseline eval |
| S0.4 | Design foundation | App IA wireframes; monorepo decision finalized |

**Epic exit criteria:** ≥1 pharma meeting scheduled; lawyer green-light on consent approach; <3s drug lookup achievable on T0 device.

---

### Epic P0: Foundation (Weeks 1–6)

**Goal:** Flutter app with encrypted local DB and searchable NLEM drug database.

#### Sprint P0-S1 (Weeks 1–2): Scaffold & Data Ingest

| Day | Agent | Task |
|---|---|---|
| D1 | A5 | ADR-001/003; monorepo init; CI pipeline |
| D1 | A6 | Flutter project + flavor setup (dev/staging/prod) |
| D1 | A4 | Design system tokens (colors, typography, Hindi font) |
| D2 | A2 | NLEM CSV schema spec; brand/generic mapping rules |
| D2 | A6 | SQLCipher integration POC |
| D3 | A5 | Domain entity definitions (`Drug`, `Interaction`) |
| D3 | A7 | Evaluate sqlite-vec vs FTS5 for drug search |
| D4 | A6 | Drug repository + local DB migrations v1 |
| D4 | A2 | First 200 NLEM drugs curated |
| D5 | A9 | Test plan for DB layer; fixture data |
| D6 | A4 | Drug search screen wireframe → hi-fi |
| D7 | A6 | Drug search UI (read-only list) |
| D8 | A1 | Competitor UX audit (Practo, 1mg, Healthplix) |
| D9 | A6 + A4 | Search UI polish; empty/loading states |
| D10 | A5 | Sprint demo; retrospective |

#### Sprint P0-S2 (Weeks 3–4): Full NLEM + Search

| Day | Agent | Task |
|---|---|---|
| D1 | A2 | Complete NLEM ingest (500+ drugs) |
| D2 | A7 | Hybrid BM25 + vector index build pipeline |
| D3 | A6 | Search with autocomplete + brand name fuzzy match |
| D4 | A3 | Privacy policy draft v0.1 |
| D5 | A8 | Threat model v0.1 (on-device data) |
| D6 | A6 | Drug detail screen with NLEM tier, dosage info |
| D7 | A9 | 50-query search accuracy test |
| D8 | A4 | Drug detail card component library |
| D9 | A6 | Offline mode indicator; no-network banner |
| D10 | Sprint demo |

#### Sprint P0-S3 (Weeks 5–6): Harden & Ship P0

| Day | Agent | Task |
|---|---|---|
| D1 | A9 | Full regression on search flows |
| D2 | A8 | SQLCipher key management review |
| D3 | A6 | Performance: <2s search on T0 device |
| D4 | A2 | Medical sign-off on drug data accuracy |
| D5 | A5 | ADR-004 EMR-ready schema (patients table stub) |
| D6 | A1 | Beta tester recruitment list (50 clinicians) |
| D7 | A6 | Internal APK build v0.1.0 |
| D8 | A3 | Regulatory review of data collection (none yet = low risk) |
| D9 | A9 | Sign-off test report |
| D10 | **Epic P0 demo** → go/no-go Epic P1 |

**Epic P0 exit criteria:** 500+ drugs searchable offline; <2s lookup on 4GB device; encrypted DB; internal APK installable.

---

### Epic P1: RAG Core (Weeks 7–12)

**Goal:** Interaction checker with deterministic rules + guideline citations.

#### Sprint P1-S1 (Weeks 7–8): Interaction DB + Rules Engine

| Day | Agent | Task |
|---|---|---|
| D1 | A2 | Interaction severity taxonomy (contraindicated / major / moderate / minor) |
| D2 | A5 | Interaction rule engine architecture ADR |
| D3 | A7 | DrugBank India subset ingest + dedup with NLEM |
| D4 | A6 | Interaction checker UI (two-drug picker) |
| D5 | A2 | Top 100 high-risk pairs for India (metformin, warfarin, etc.) |
| D6 | A6 | Rule engine implementation |
| D7 | A9 | Known-pair test suite (100 pairs, expect 100% match) |
| D8 | A4 | Severity color system (red/amber/green) + accessibility |
| D9 | A6 | Interaction result screen with sources |
| D10 | Sprint demo |

#### Sprint P1-S2 (Weeks 9–10): RAG over Guidelines

| Day | Agent | Task |
|---|---|---|
| D1 | A2 | WHO + ICMR guideline chunks for ambiguous interactions |
| D2 | A7 | Chunking + embedding pipeline for guidelines |
| D3 | A6 | RAG fallback when rule engine returns "unknown" |
| D4 | A2 | Safety policy: never invent severity levels |
| D5 | A8 | Review RAG outputs for PHI leakage in citations |
| D6 | A6 | Citation UI (tap to view source excerpt) |
| D7 | A9 | 50 ambiguous-case eval with Medical Expert rating |
| D8 | A4 | Interaction flow UX refinement (<3 taps) |
| D9 | A6 | APK v0.2.0 |
| D10 | Sprint demo |

#### Sprint P1-S3 (Weeks 11–12): Harden P1

| Day | Agent | Task |
|---|---|---|
| D1–D3 | A9 + A2 | 200-pair interaction validation marathon |
| D4 | A7 | RAG recall/precision metrics report |
| D5 | A1 | Beta feedback survey template |
| D6 | A6 | Bug fix sprint |
| D7 | A8 | Security review of RAG index |
| D8 | A3 | Update privacy policy for local guideline data |
| D9 | A9 | P1 sign-off report |
| D10 | **Epic P1 demo** |

**Epic P1 exit criteria:** 100% accuracy on top 100 known pairs; RAG citations for ambiguous cases; Medical Expert sign-off.

---

### Epic P2: LLM Integration (Weeks 13–18)

**Goal:** On-device Qwen 3B for note drafting; device tier detection.

#### Sprint P2-S1 (Weeks 13–14): llama.cpp JNI

| Day | Agent | Task |
|---|---|---|
| D1 | A5 | ADR: llama.cpp vs MNN; JNI bridge design |
| D2 | A7 | Qwen2.5-3B Q4_K_M GGUF build; benchmark tok/s |
| D3 | A6 | JNI wrapper + Flutter platform channel |
| D4 | A7 | Tier detection logic (RAM → model selection) |
| D5 | A6 | Model download manager (WiFi-only, resumable) |
| D6 | A7 | 1.5B fallback model for T0 devices |
| D7 | A9 | Inference smoke tests on 3 device tiers |
| D8 | A8 | Model file integrity (signed hashes) |
| D9 | A6 | Settings screen: model tier display |
| D10 | Sprint demo: "Hello clinical" inference |

#### Sprint P2-S2 (Weeks 15–16): Note Drafter

| Day | Agent | Task |
|---|---|---|
| D1 | A2 | Note template spec (SOAP variant for India) |
| D2 | A7 | Prompt templates EN + Hindi |
| D3 | A4 | Note drafter UI (structured input → draft output) |
| D4 | A6 | Note drafter feature implementation |
| D5 | A2 | Safety policy: draft only, not diagnostic |
| D6 | A9 | 30 note drafts rated by 3 clinicians |
| D7 | A7 | Prompt iteration based on feedback |
| D8 | A6 | Save draft locally (encrypted, not synced) |
| D9 | A4 | Edit/regenerate UX |
| D10 | Sprint demo |

#### Sprint P2-S3 (Weeks 17–18): Harden P2

| Day | Agent | Task |
|---|---|---|
| D1–D2 | A7 | NNAPI acceleration eval |
| D3 | A6 | Memory management (model unload on background) |
| D4 | A9 | Performance benchmarks across 5 devices |
| D5 | A2 | Clinical sign-off on note quality bar |
| D6 | A8 | Ensure notes not in crash logs |
| D7 | A6 | APK v0.3.0 |
| D8 | A1 | Beta expand to 200 clinicians |
| D9 | A9 | P2 sign-off |
| D10 | **Epic P2 demo** |

**Epic P2 exit criteria:** 3B model runs on 6GB+ devices; note drafter rated "useful" by ≥70% of pilot clinicians.

---

### Epic P3: Privacy Layer (Weeks 19–24)

**Goal:** PII scrubber, consent UI, blocking sync gate.

#### Sprint P3-S1 (Weeks 19–20): PII NER

| Day | Agent | Task |
|---|---|---|
| D1 | A3 | Consent text v1.0 EN + Hindi (lawyer review) |
| D2 | A7 | NER training data: 1000 annotated code-mixed sentences |
| D3 | A7 | Fine-tune XLM-R → ONNX export |
| D4 | A8 | Scrubber spec: fields, age bucketing, regex patterns |
| D5 | A6 | ONNX Runtime integration in Flutter |
| D6 | A7 | Scrubber eval: precision/recall per language |
| D7 | A8 | Adversarial test cases (names in Devanagari, etc.) |
| D8 | A6 | Scrubber runs synchronously pre-sync |
| D9 | A9 | 1000-sentence scrubber validation |
| D10 | Sprint demo |

#### Sprint P3-S2 (Weeks 21–22): Consent UI

| Day | Agent | Task |
|---|---|---|
| D1 | A4 | Consent onboarding flow (visual, bilingual) |
| D2 | A6 | Consent screen implementation; default OFF |
| D3 | A3 | Scope selection UI spec (model improvement vs analytics) |
| D4 | A6 | Consent record storage + version tracking |
| D5 | A4 | Data transparency dashboard wireframes |
| D6 | A6 | "What we collected" + "Delete my data" UI |
| D7 | A3 | Regulatory sign-off on consent flow |
| D8 | A8 | Audit: no data leaves device without consent + scrub |
| D9 | A9 | Consent flow E2E tests |
| D10 | Sprint demo |

#### Sprint P3-S3 (Weeks 23–24): Harden P3

| Day | Agent | Task |
|---|---|---|
| D1 | A8 | **Gate:** >99% PII recall or epic blocked |
| D2 | A7 | NER retrain if recall <99% |
| D3 | A6 | Blocking sync gate implementation |
| D4 | A3 | DPDPA compliance checklist complete |
| D5 | A9 | Full privacy regression suite |
| D6 | A1 | Opt-in rate tracking instrumentation |
| D7 | A6 | APK v0.4.0 |
| D8 | A5 | Sync payload schema (de-id only) |
| D9 | A9 | P3 sign-off |
| D10 | **Epic P3 demo** |

**Epic P3 exit criteria:** >99% PII recall; lawyer-approved consent; zero PHI in sync payloads (validated).

---

### Epic P4: Sync + Backend (Weeks 25–30)

**Goal:** India-region backend, opt-in sync, OTA model update pipeline.

#### Sprint P4-S1 (Weeks 25–26): Backend Services

| Day | Agent | Task |
|---|---|---|
| D1 | A5 | Backend architecture; AWS Mumbai Terraform |
| D2 | A5 | consent-api OpenAPI spec |
| D3 | A6 | Retrofit/Dio client + HMAC signing |
| D4 | A5 | ingest-api with scrubber validation gate |
| D5 | A8 | API auth, rate limiting, cert pinning |
| D6 | A6 | WorkManager WiFi-only sync jobs |
| D7 | A9 | Sync E2E tests (mock server) |
| D8 | A3 | Data processing agreement template |
| D9 | A5 | Deploy staging to ap-south-1 |
| D10 | Sprint demo |

#### Sprint P4-S2 (Weeks 27–28): OTA + Dashboard

| Day | Agent | Task |
|---|---|---|
| D1 | A5 | ota-api manifest + differential patch spec |
| D2 | A7 | GGUF diff pipeline prototype |
| D3 | A6 | OTA download + verify + hot-swap |
| D4 | A5 | Admin dashboard (de-id corpus stats) |
| D5 | A1 | Data buyer spec sheet v1 (for pharma outreach) |
| D6 | A6 | Clinician feedback (thumbs) → sync payload |
| D7 | A8 | Pen test staging APIs |
| D8 | A9 | OTA rollback test |
| D9 | A7 | First fine-tune dataset export (synthetic + beta) |
| D10 | Sprint demo |

#### Sprint P4-S3 (Weeks 29–30): Harden P4

| Day | Agent | Task |
|---|---|---|
| D1–D3 | A8 | Full security audit report |
| D4 | A9 | Load test ingest (10K devices simulated) |
| D5 | A3 | Production compliance sign-off |
| D6 | A6 | APK v0.5.0 (sync enabled) |
| D7 | A1 | Pharma LOI follow-ups with data spec |
| D8 | A5 | Production deploy |
| D9 | A9 | P4 sign-off |
| D10 | **Epic P4 demo** |

**Epic P4 exit criteria:** Staging + prod in Mumbai; opt-in sync works; OTA update tested; pen test passed.

---

### Epic P5: Nepal Pilot Launch (Weeks 31–36)

**Goal:** Onboard **<30 clinicians** in Nepal (Kathmandu, Pokhara, Biratnagar hubs), closed beta track.

#### Sprint P5-S1 (Weeks 31–32): Pilot Prep

| Day | Agent | Task |
|---|---|---|
| D1 | A1 | 3 Nepal pilot site agreements (Kathmandu, Pokhara, Biratnagar) |
| D2 | A4 | Onboarding tutorial EN + Nepali (60-second video + screens) |
| D3 | A6 | Play Store closed testing track setup |
| D4 | A2 | Pilot support playbook (FAQ EN + Nepali) |
| D5 | A9 | Pilot test plan — load `data/nepal/eval_queries.jsonl` |
| D6 | A1 | NMA / medical college WhatsApp outreach (target 30 invites) |
| D7 | A6 | Crash reporting (Sentry, PHI-scrubbed) |
| D8 | A3 | Play Store privacy policy + data safety form |
| D9 | A8 | Final APK security review |
| D10 | Sprint demo |

#### Sprint P5-S2 (Weeks 33–34): Pilot Execution

| Day | Agent | Task |
|---|---|---|
| D1–D5 | A9 + A2 | Daily pilot feedback triage |
| D1–D5 | A6 | P0/P1 bug fixes (<24h turnaround) |
| D3 | A1 | Weekly clinician survey (opt-in rate, NPS) |
| D4 | A7 | First production fine-tune run (if data sufficient) |
| D5 | A6 | OTA v1.1 model deploy to opt-in users |
| D10 | Sprint demo: pilot metrics |

#### Sprint P5-S3 (Weeks 35–36): Scale Beta

| Day | Agent | Task |
|---|---|---|
| D1 | A1 | Hand-onboard remaining invites to reach 30 clinicians |
| D2 | A6 | Performance optimization from Nepal pilot data |
| D3 | A9 | Full MVP regression against `data/nepal/` fixtures |
| D4 | A5 | Nepal pilot retrospective; India scale roadmap |
| D5 | A2 | Clinical safety final review |
| D6 | A3 | Nepal privacy checklist (counsel review) |
| D7 | A1 | KOL debrief — 3 champion clinicians in Nepal |
| D8 | A6 | Play Store Nepal closed beta (or direct APK for pilot) |
| D9 | A9 | Nepal pilot sign-off |
| D10 | **NEPAL PILOT DEMO** |

**Epic P5 exit criteria:** 25–30 active clinicians; ≥40% opt-in; crash-free >99.5%; eval_queries pass rate ≥85%; ready for India Phase 2.

---

## Part 9: Cross-Agent Dependency Matrix

Who must finish before whom (within each sprint):

```
A2 Medical ──────▶ A7 ML ──────▶ A6 Android
     │                 │               │
     └────────▶ A4 UI ─┴───────────────┤
                                       ▼
A3 Regulatory ──▶ A8 Security ──▶ A9 QA ──▶ Ship
     │
A1 Market (parallel track, feeds A3 consent copy + A1 GTM)
A5 Architecture (parallel, unblocks A6 + backend)
```

**Hard gates (epic cannot close without):**
- A2 sign-off on all clinical content
- A8 sign-off on all network/sync code
- A3 sign-off before any user data collection goes live
- A9 sign-off before any APK leaves internal track

---

## Part 10: Sprint Ceremonies Checklist

### Monday (Sprint Day 1 / Week 1 of sprint)

- [ ] Review epic goal and sprint backlog
- [ ] Assign all DAY tickets for the week
- [ ] Identify cross-agent dependencies for the week
- [ ] A5 publishes any new ADRs

### Wednesday (Mid-sprint)

- [ ] 15-min blocker swarm (only if red items in BLOCKERS.md)
- [ ] A9 reports test coverage delta
- [ ] A1 reports market/pilot metrics (if applicable)

### Friday (Sprint Day 10)

- [ ] Sprint demo (working software, not slides)
- [ ] Retro: start/stop/continue (15 min)
- [ ] Carry-over tickets tagged for next sprint
- [ ] Orchestrator updates epic burn-down

### Epic Week 6 Friday

- [ ] Epic demo to stakeholders
- [ ] Go/no-go against epic exit criteria
- [ ] Human advisor reviews (Medical, Legal, Security)
- [ ] Plan next epic sprint backlogs

---

## Part 11: Metrics Dashboard (Track Weekly)

| Metric | Owner | Target (Nepal pilot) |
|---|---|---|
| Drugs in local DB | A2 | 50 (pilot) → 500+ (India) |
| Interaction pair coverage | A2 | 35 (pilot) → 500 (India) |
| PII scrubber recall | A8 | >99% on 30 test cases |
| Drug lookup latency (T0) | A6 | <2s |
| LLM tok/s (T1, 3B) | A7 | >8 tok/s |
| Opt-in rate | A1 | ≥40% of active |
| Crash-free sessions | A9 | >99.5% |
| Active clinicians | A1 | **25–30** |
| Eval query pass rate | A9 | ≥85% (40 queries) |
| Clinician "useful" rating | A2+A9 | ≥70% |

---

## Part 12: Post-MVP Epic Preview (EMR Phase)

| Epic | Weeks | Goal |
|---|---|---|
| **E1: Patient Registry** | 37–42 | Local patient CRUD, link sessions to patients |
| **E2: Visit Documentation** | 43–48 | Vitals, visit notes, patient timeline |
| **E3: E-Prescription** | 49–54 | Rx builder, PDF, interaction check integration |
| **E4: Clinic Sync** | 55–60 | Encrypted backup, multi-device (single clinic) |
| **E5: ABDM Sandbox** | 61–66 | ABHA linking, FHIR adapter prototype |

---

## Part 13: Immediate Week 1 Tickets (Copy-Ready)

| Ticket ID | Agent | Task | Done when |
|---|---|---|---|
| EPIC-P0-S1-A5-001 | Architecture | Init monorepo, CI, ADR-001/003 | Green CI on empty Flutter app |
| EPIC-P0-S1-A6-002 | Android | Flutter shell + SQLCipher POC | Encrypted DB read/write demo |
| EPIC-P0-S1-A2-003 | Medical | NNLEM schema + load `data/nepal/drugs.json` | 50 drugs in local DB |
| EPIC-P0-S1-A4-004 | UI/UX | Design system + search wireframe | Figma link in `/docs` |
| EPIC-P0-S1-A7-005 | ML/LLM | sqlite-vec vs FTS5 benchmark | ADR with benchmark numbers |
| EPIC-P0-S1-A8-006 | Security | Threat model v0.1 | `docs/security/threat-model-v0.1.md` |
| EPIC-P0-S1-A1-007 | Market | Competitor UX audit | 1-page brief in `/docs/market` |
| EPIC-P0-S1-A9-008 | QA | Test plan template + fixtures | `qa/test-plan-p0.md` |
| EPIC-P0-S1-A3-009 | Regulatory | Privacy policy outline | Draft for lawyer review |

---

*Architecture & sprint plan prepared July 9, 2026. Not legal or medical advice.*

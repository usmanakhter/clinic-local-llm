# Nepal Clinical AI MVP — P0/P1 Compressed Test Plan

**QA agent:** A9  
**Region:** NP (synthetic fixtures only)  
**Fixtures:** `data/nepal/`  
**Automation:** `python qa/run_fixture_evals.py` → `artifacts/qa_fixture_report.md`  
**Targets (architecture):** interaction checker **100%** on 35 pairs; PII scrubber recall **>99%** (fixture gate); drug lookup useful rating ≥70% on 40 eval queries

All cases below use **synthetic** drugs, IDs, names, phones, and vignettes. Not for clinical use.

---

## Scope & priority

| Priority | Must pass for pilot gate | Notes |
|---|---|---|
| **P0** | Drug search smoke, all 35 interactions (exact severity, bidirectional), consent default OFF, offline core flows, scrubber regression tracked | Blocks pilot |
| **P1** | Guideline chunk smoke (EN/NE), eval_queries coverage counts, sync-queue scrub rejection path | Improves confidence |

---

## 1. Drug search (P0)

**Fixture:** `data/nepal/drugs.json` (50 NNLEM-style entries)  
**Gold queries:** `data/nepal/eval_queries.jsonl` (`type: drug_lookup`)

| ID | Mode | Input (examples) | Expected | Pass criteria |
|---|---|---|---|---|
| DS-01 | Generic EN | `paracetamol`, `metformin`, `rifampicin` | Correct `drug_id` (e.g. `drug_001`) | Top hit = gold generic; latency target &lt;2s on T0 (manual/device) |
| DS-02 | Nepali (Devanagari) | `प्यारासिटामोल`, `मेटफर्मिन`, `अमोक्सिसिलिन` | Same `drug_id` as EN generic | `generic_name_ne` match; casing/normalization OK |
| DS-03 | Brand | `Nepalol`, `Coartem`, `Augmentin`, `Flagyl` | Maps to parent generic (`drug_001`, `drug_030`, `drug_004`, `drug_008`) | Brand → formulary hit; manufacturer optional |
| DS-04 | Eval smoke | `eval_001`, `eval_021`, `eval_022` | `expected_drug_ids` present in results | ≥1 expected ID in top-k |

**Fail if:** wrong drug returned for brand→generic; empty result for known formulary string; crash on Devanagari.

---

## 2. Interaction checker (P0) — all 35 pairs

**Fixture:** `data/nepal/interactions.json` (`interaction_count: 35`)  
**Gate:** severity must match **exactly** (`minor` \| `moderate` \| `major` \| `contraindicated`). LLM must not invent severity.

| ID | Check | Method | Pass criteria |
|---|---|---|---|
| IX-01 | Catalog integrity | Load JSON; count == 35; unique `id`; unique unordered drug pairs | Matches `interaction_count`; no duplicate (a,b)/(b,a) collisions |
| IX-02 | Forward lookup | For each pair `(drug_a_id, drug_b_id)` → severity | Exact string match to fixture |
| IX-03 | Reverse lookup | For each pair `(drug_b_id, drug_a_id)` → **same** severity | Bidirectional; no order dependency |
| IX-04 | Severity labels | All 35 severities in allowed set | No typos / alternate labels |
| IX-05 | Eval gold | `eval_queries.jsonl` `type: interaction_check` | Returned `expected_interaction_ids` + severity |

**Automation:** `run_fixture_evals.py` builds unordered key `{min(a,b)|max(a,b)}` and verifies a→b and b→a both resolve. Exit **0** only if integrity + bidirectional OK.

**Representative severity spot-checks (manual UI):**

| Pair | Expected severity | Fixture id |
|---|---|---|
| Ibuprofen + Aspirin | `major` | `int_001` |
| Azithromycin + Ciprofloxacin | `contraindicated` | `int_022` |
| Amoxicillin + Metronidazole | `minor` | `int_020` |
| Ceftriaxone + Calcium | `major` | `int_034` |
| Metformin + Omeprazole | `minor` | `int_035` |

**Fail if:** any of 35 pairs missing, wrong severity, or reverse order returns empty/different severity.

---

## 3. Guideline chunk search smoke (P1)

**Fixture:** `data/nepal/guideline_chunks.json` (18 chunks)  
**Gold:** eval rows with `type: guideline_search` (e.g. `eval_006` dengue → `guide_002`)

| ID | Query | Expected chunk | Pass criteria |
|---|---|---|---|
| GL-01 | dengue / avoid aspirin | `guide_002` | Relevant chunk in top-3 |
| GL-02 | snake bite / antivenom | `guide_004` | Top hit mentions antivenom / 20WBCT |
| GL-03 | Nepali: `टाइफाइड` / `डेङ्गु` | `guide_001` / `guide_002` | `chunk_text_ne` / title_ne usable |
| GL-04 | Offline FTS | Airplane mode; same query | Local index hit; no network call |

**Fail if:** empty results for seeded topics; requires online fetch for bundled chunks.

---

## 4. Consent default OFF (P0)

**Fixture:** `data/nepal/consent_templates.json` (onboarding states default OFF; dummy records include `granted: 0`)

| ID | Step | Expected |
|---|---|---|
| CO-01 | Fresh install / new clinician profile | Model-improvement + analytics toggles **OFF** |
| CO-02 | UI copy EN + नेपाली | Matches templates; states “Default is OFF” / “पूर्वनिर्धारित: बन्द” |
| CO-03 | Opt-in path | Sync queue only after explicit grant + scrub |
| CO-04 | Opt-out / never granted (`consent_003`) | No clinical content upload |

**Fail if:** any default `granted: true` on cold start; silent upload without consent.

---

## 5. PII scrubber (P0 tracked / P1 gate for &gt;99%)

**Fixture:** `data/nepal/pii_scrubber_test_cases.json` (30 cases)  
**Automation:** simple regex baseline in `run_fixture_evals.py` (phones +977 / 98xxxxxxxx, emails, NMC-IDs, passport-like, hospital registration). Report recall %; **do not fail process exit on &lt;99%** until production NER landss.

| Pattern class | Examples in fixtures | Expected |
|---|---|---|
| Mobile | `9841234567`, `+977-9801122334`, `9779812345678`, Devanagari digits | Token removed |
| Email | `patient.care@example.com` | Removed |
| NMC ID | `NMC-2019-12345` | Removed |
| Passport-like | `N1234567` | Removed |
| Hospital registration | `HREG-2025-4421` | Removed |
| Names / places / caste | Nepali + EN names, districts | Full scrubber/NER (manual + later model); regex baseline may miss |

| ID | Case ids | Pass (full product) | Pass (fixture script) |
|---|---|---|---|
| PI-01 | `pii_001`, `pii_006`, `pii_008`, `pii_013`, `pii_020`, `pii_027` | All `expected_removed` gone; `expected_retained` kept | Regex recall reported |
| PI-02 | `pii_017`, `pii_024`, `pii_030` (no PHI) | No over-scrub of clinical terms | Retained clinical tokens intact |
| PI-03 | Sync reject path | residual → `blocked_residual_pii` (not legacy `rejected`); excluded from pending flush | Dart: `test/pii_scrubber_test.dart`; fixture `sync_queue_dummy.json` sync_008 |

**Target:** recall **>99%** on all `expected_removed` tokens for production scrubber. Fixture script prints score separately.

---

## 6. Offline behavior (P0)

**Fixtures:** bundled `drugs.json`, `interactions.json`, `guideline_chunks.json`; sync failures in `sync_queue_dummy.json` (`sync_007` Wi-Fi unavailable)

| ID | Scenario | Expected |
|---|---|---|
| OF-01 | Airplane mode: drug search | Works from local formulary |
| OF-02 | Airplane mode: interaction check | All 35 pairs resolve locally |
| OF-03 | Airplane mode: guideline search | Local FTS/vector only |
| OF-04 | Consent OFF + offline | No pending upload of PHI |
| OF-05 | Offline → online | Queue holds de-id payloads; Wi-Fi policy per consent templates |
| OF-06 | Note draft (if enabled) | Saves locally; not synced without consent |

**Fail if:** core reference features require network; unsrubbed PHI enters sync queue.

---

## 7. Compressed execution checklist

| # | Suite | P | Owner | Evidence |
|---|---|---|---|---|
| 1 | Run `python qa/run_fixture_evals.py` | P0 | A9 | `artifacts/qa_fixture_report.md`; exit 0 |
| 2 | Drug search EN / NE / brand smoke | P0 | QA + device | Screenshots or session log ids |
| 3 | Sample 5 interaction UI checks + spot severity | P0 | QA | Match fixture |
| 4 | Guideline smoke EN + 1 NE query | P1 | QA | Top-k includes gold guide id |
| 5 | Consent cold-start OFF | P0 | QA | Toggle state + copy |
| 6 | Offline airplane mode walk | P0 | Device lab | No network in logs |
| 7 | Scrubber: full 30 cases (product NER) | P0→gate | Eng | Recall &gt;99% |

---

## Exit criteria (MVP pilot)

- [ ] Interaction catalog: **35/35** bidirectional, exact severity (script exit 0)
- [ ] Drug search: generic EN, Nepali, and brand smoke all green
- [ ] Consent: default **OFF** verified on fresh profile
- [ ] Offline: drug + interaction + guideline usable without network
- [ ] PII: fixture report published; production scrubber on path to **>99%** recall
- [ ] Guideline + eval coverage smoke completed (P1)

---

## References

- `data/README.md`
- `data/nepal/drugs.json`, `interactions.json`, `guideline_chunks.json`
- `data/nepal/eval_queries.jsonl`, `pii_scrubber_test_cases.json`, `consent_templates.json`, `sync_queue_dummy.json`
- `clinical-llm-technical-architecture.md` (Nepal pilot metrics)

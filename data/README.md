# MVP Dummy Data — Nepal Pilot

**Region:** Nepal (`NP`)  
**Pilot goal:** Onboard **<30 clinicians** before broader South Asia rollout  
**Status:** Synthetic / development fixtures only — not for clinical use

## Directory layout

```
data/
├── schema/
│   ├── mvp_schema.sql      # SQLite tables + seed loader notes
│   └── manifest.json       # Dataset versions and file index
└── nepal/
    ├── drugs.json            # 60 NNLEM-style essential medicines (dummy)
    ├── interactions.json     # 40 drug-drug interaction pairs
    ├── guideline_chunks.json # 24 RAG chunks (WHO + Nepal-relevant)
    ├── eval_queries.jsonl    # 50 gold test queries for QA
    ├── clinical_sessions_dummy.json
    ├── sync_queue_dummy.json # De-identified sync payloads (post-scrub)
    ├── consent_templates.json
    ├── pilot_clinicians.json # 28 fictional pilot participants
    ├── pii_scrubber_test_cases.json
    └── note_drafter_samples.json
```

## Load order (app bootstrap)

1. `schema/mvp_schema.sql` — create tables
2. `nepal/drugs.json` — bulk insert into `drugs`
3. `nepal/interactions.json` — bulk insert into `interactions`
4. `nepal/guideline_chunks.json` — FTS / vector index build
5. Optional dev fixtures: `clinical_sessions_dummy.json`, `pilot_clinicians.json`

## Nepal pilot specifics

| Item | MVP choice |
|---|---|
| Formulary | NNLEM 2021-style subset (60 drugs) |
| Languages | English + Nepali (Devanagari) |
| Consent UI | EN + नेपाली |
| PII patterns | +977 mobiles, Nepali names, fictional NMC IDs |
| Pilot cities | Kathmandu, Lalitpur, Pokhara, Biratnagar, Bharatpur |
| Launch metric | **25–30 active clinicians** (not 10K) |

## Disclaimer

All clinician names, clinic names, phone numbers, and patient vignettes are **fictional**. Drug entries are representative of common essential medicines but must be verified by a licensed Nepal medical advisor before any production use.

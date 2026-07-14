# clinical_core_py

Portable Nepal clinical MVP **domain logic** in Python. The Flutter team can mirror these modules in Dart (same field names, same rules).

**Not for clinical use as-is** — backed by dummy/dev fixtures in `data/nepal/`.

## What it does

| Module | Role |
|---|---|
| `models.py` | `Drug`, `Interaction`, `GuidelineChunk` dataclasses (schema-aligned) |
| `repository.py` | Load `data/nepal_mvp_dev.db` (auto-seed if missing) |
| `search.py` | FTS5 search with LIKE fallback; ranked results |
| `interactions.py` | Bidirectional pair lookup; **never invents severity** |
| `guidelines.py` | Keyword search over `guideline_chunks` |
| `cli_demo.py` | CLI: `search` / `interact` / `guide` |

## Setup

Requires Python 3.10+ and a seeded SQLite DB. From the repo root:

```bash
python data/scripts/seed_nepal_db.py
```

`ClinicalRepository` runs the seed script automatically if `data/nepal_mvp_dev.db` is missing.

## Usage (library)

```python
from clinical_core_py import (
    ClinicalRepository,
    search_drugs,
    lookup_interaction,
    search_guidelines,
)

with ClinicalRepository() as repo:
    hits = search_drugs(repo, "Paracetamol")
    print(hits[0].drug.id)  # drug_001

    ix = lookup_interaction(repo, "drug_005", "drug_006")
    print(ix.severity if ix else None)  # contraindicated

    guides = search_guidelines(repo, "diarrhea")
```

Add the package parent to `PYTHONPATH` (or run from repo with path bootstrap as in the CLI):

```bash
# Windows PowerShell
$env:PYTHONPATH = "packages"
python -c "from clinical_core_py import search_drugs, ClinicalRepository; ..."
```

## CLI

```bash
# From repo root
python packages/clinical_core_py/cli_demo.py search Paracetamol
python packages/clinical_core_py/cli_demo.py search Nepalol
python packages/clinical_core_py/cli_demo.py interact drug_005 drug_006
python packages/clinical_core_py/cli_demo.py interact drug_001 drug_050
python packages/clinical_core_py/cli_demo.py guide typhoid
```

## Smoke test

```bash
python packages/clinical_core_py/smoke_test.py
```

Asserts:

- `search("Paracetamol")` → top hit `drug_001`
- `search("Nepalol")` finds Paracetamol (`drug_001`)
- `interact drug_005 + drug_006` → `contraindicated`
- Unknown pair → `None`

## Flutter/Dart mirror notes

1. Keep JSON field names identical to `mvp_schema.sql` / these dataclasses.
2. Interaction API: check `(a,b)` then `(b,a)`; return null if neither row exists.
3. **Never** invent severity or fabricate interactions in the model layer.
4. Search ranking heuristics in `search.py` are intentionally portable (no SQLite-only rank required after candidate fetch).

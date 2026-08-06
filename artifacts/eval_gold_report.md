# Eval Gold Report — Nepal Clinical AI

- Generated: `2026-08-06 00:24:01 UTC`
- Fixture: `data/nepal/eval_queries.jsonl`
- Top-k: `5`
- Pass threshold: `70.0%` overall

## Overall: **97.7%** (127/130)

## By type

- `drug_lookup`: 120/123 (97.6%)
- `guideline_search`: 1/1 (100.0%)
- `interaction_check`: 6/6 (100.0%)

## Failures

| ID | Type | Expected | Got | Detail |
|---|---|---|---|---|
| `eval_036` | `drug_lookup` | `['drug_040', 'drug_041']` | `['drug_484', 'drug_141', 'drug_485', 'drug_486', 'drug_487']` | miss |
| `eval_053` | `drug_lookup` | `['drug_072']` | `['drug_418', 'drug_459', 'drug_460', 'drug_461', 'drug_419']` | miss |
| `eval_116` | `drug_lookup` | `['drug_037', 'drug_122', 'drug_123']` | `['drug_439', 'drug_440', 'drug_441', 'drug_442', 'drug_443']` | miss |


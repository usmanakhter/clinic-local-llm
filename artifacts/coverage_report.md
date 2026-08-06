# Coverage Dashboard — Nepal Clinical AI

- Generated: `2026-08-06 00:24:00 UTC`
- OPD checklist: `opd_condition_checklist.json` (120 conditions)
- Gold eval: `eval_queries.jsonl` (130 queries)

## Summary

| Metric | Result | Target |
|---|---|---|
| OPD catalog coverage (schema) | **100.0%** | 90.0% |
| OPD retrieval coverage (weighted) | **97.7%** | 90.0% |
| Gold eval pass rate | **97.7%** | 85.0% |

## OPD retrieval misses

| Condition | Drugs OK | Guides OK | Top drug hits | Top guide hits |
|---|---|---|---|---|
| Vitamin D deficiency | False | True | `['drug_484', 'drug_141', 'drug_485']` | `['guide_036', 'guide_031', 'guide_112']` |
| Tetanus prophylaxis | False | True | `['drug_418', 'drug_459', 'drug_460']` | `['guide_053', 'guide_052', 'guide_054']` |
| Epilepsy valproate | False | True | `['drug_439', 'drug_440', 'drug_441']` | `['guide_015']` |

## Gold eval by type

- `drug_lookup`: 120/123 (97.6%)
- `guideline_search`: 1/1 (100.0%)
- `interaction_check`: 6/6 (100.0%)


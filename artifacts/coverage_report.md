# Coverage Dashboard — Nepal Clinical AI

- Generated: `2026-07-21 22:14:34 UTC`
- OPD checklist: `opd_condition_checklist.json` (120 conditions)
- Gold eval: `eval_queries.jsonl` (130 queries)

## Summary

| Metric | Result | Target |
|---|---|---|
| OPD catalog coverage (schema) | **100.0%** | 90.0% |
| OPD retrieval coverage (weighted) | **87.8%** | 90.0% |
| Gold eval pass rate | **88.5%** | 85.0% |

## OPD retrieval misses

| Condition | Drugs OK | Guides OK | Top drug hits | Top guide hits |
|---|---|---|---|---|
| H pylori | True | False | `['drug_003', 'drug_004']` | `['guide_026', 'guide_018', 'guide_028']` |
| Epilepsy | True | False | `['drug_036']` | `[]` |
| Burns | True | False | `['drug_001', 'drug_074', 'drug_093']` | `['guide_056', 'guide_025', 'guide_002']` |
| Acute otitis media | True | False | `['drug_003', 'drug_004']` | `['guide_026', 'guide_018', 'guide_028']` |
| Viral hepatitis A | True | False | `['drug_001', 'drug_074', 'drug_093']` | `['guide_056', 'guide_025', 'guide_002']` |
| Osteoarthritis | True | False | `['drug_001', 'drug_074', 'drug_093']` | `['guide_056', 'guide_025', 'guide_002']` |
| Low back pain | True | False | `['drug_001', 'drug_074', 'drug_093']` | `['guide_056', 'guide_025', 'guide_002']` |
| Dental abscess | True | False | `['drug_003', 'drug_004']` | `['guide_026', 'guide_018', 'guide_028']` |
| Migraine | True | False | `['drug_001', 'drug_074', 'drug_093']` | `['guide_056', 'guide_025', 'guide_002']` |
| Varicella | True | False | `['drug_001', 'drug_074', 'drug_093']` | `['guide_056', 'guide_025', 'guide_002']` |
| Measles | True | False | `['drug_001', 'drug_074', 'drug_093']` | `['guide_056', 'guide_025', 'guide_002']` |
| UTI pregnancy | True | False | `['drug_003', 'drug_004']` | `['guide_026', 'guide_018', 'guide_028']` |
| Diabetic foot infection | True | False | `['drug_003', 'drug_004']` | `['guide_028', 'guide_027', 'guide_054']` |
| Acute bronchitis | True | False | `['drug_001', 'drug_074', 'drug_093']` | `['guide_056', 'guide_025', 'guide_002']` |
| Hepatitis E pregnancy | True | False | `['drug_001', 'drug_074', 'drug_093']` | `['guide_056', 'guide_025', 'guide_002']` |

## Gold eval by type

- `drug_lookup`: 108/123 (87.8%)
- `guideline_search`: 1/1 (100.0%)
- `interaction_check`: 6/6 (100.0%)


# QA Fixture Report — Nepal Clinical AI MVP

- Generated: `2026-07-21 22:14:36 UTC`
- Agent: A9
- Fixtures: `data/nepal/`
- Runner: `qa/run_fixture_evals.py`

## Interaction catalog integrity

- Status: **PASS**
- Loaded pairs: `40` (declared `40`)
- Forward lookups OK: `40/40`
- Reverse (b→a) lookups OK: `40/40`
- Severity distribution: `{'major': 14, 'moderate': 23, 'minor': 2, 'contraindicated': 1}`

All 40 pairs resolve with exact severity in both id orders.

## PII scrubber baseline (simple regex)

> Exit code ignores scrubber score; production target remains >99% recall.

- Cases: `30/30` fully cleared
- Tokens: `40/40` removed
- **Recall: 100.00%**

### Misses by case (expected_removed still present)

_None — all expected_removed tokens scrubbed._

## Eval queries inventory

- Total queries: `130`
- By type: `{'drug_lookup': 123, 'guideline_search': 1, 'interaction_check': 6}`
- By locale: `{'en': 130}`

## Exit policy

- Process exit **0** iff interaction catalog integrity PASS **and** scrubber recall ≥99%.
- Production sync requires scrub gate before upload.


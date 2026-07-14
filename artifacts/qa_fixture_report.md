# QA Fixture Report — Nepal Clinical AI MVP

- Generated: `2026-07-14 14:19:09 UTC`
- Agent: A9
- Fixtures: `data/nepal/`
- Runner: `qa/run_fixture_evals.py`

## Interaction catalog integrity

- Status: **PASS**
- Loaded pairs: `35` (declared `35`)
- Forward lookups OK: `35/35`
- Reverse (b→a) lookups OK: `35/35`
- Severity distribution: `{'major': 12, 'moderate': 20, 'minor': 2, 'contraindicated': 1}`

All 35 pairs resolve with exact severity in both id orders.

## PII scrubber baseline (simple regex)

> Exit code ignores scrubber score; production target remains >99% recall.

- Cases: `12/30` fully cleared
- Tokens: `12/40` removed
- **Recall: 30.00%**

### Misses by case (expected_removed still present)

| Case | Hits | Missed tokens |
|---|---:|---|
| `pii_001` | 1/2 | `Ram Bahadur Thapa` |
| `pii_002` | 0/2 | `सिता शर्मा`, `बानेश्वर` |
| `pii_003` | 0/2 | `Gopal KC`, `15/03/1988` |
| `pii_004` | 1/2 | `Bir Hospital` |
| `pii_005` | 0/2 | `हरि प्रसाद यादव`, `बिराटनगर` |
| `pii_007` | 0/3 | `Pokhara Lakeside`, `ward 9`, `Kaski` |
| `pii_010` | 0/1 | `Anjali Rai` |
| `pii_011` | 0/1 | `Dhading` |
| `pii_012` | 1/2 | `राजेश तामाङ` |
| `pii_014` | 0/1 | `Shyam Sundar` |
| `pii_015` | 0/1 | `मिना देवी` |
| `pii_019` | 0/2 | `Sunita G.`, `Kathmandu valley` |
| `pii_021` | 0/2 | `कुमार श्रेष्ठ`, `ललितपुर पाटन` |
| `pii_023` | 0/1 | `Newar` |
| `pii_025` | 0/2 | `44600`, `Rupandehi` |
| `pii_026` | 0/1 | `अमित गुरुङ` |
| `pii_028` | 0/2 | `Rina`, `Sita` |
| `pii_029` | 0/2 | `John Smith`, `UK` |

## Eval queries inventory

- Total queries: `40`
- By type: `{'drug_lookup': 24, 'guideline_search': 5, 'interaction_check': 11}`
- By locale: `{'en': 33, 'ne': 7}`

## Exit policy

- Process exit **0** iff interaction catalog integrity PASS.
- Scrubber recall is informational until NER/on-device scrub lands.


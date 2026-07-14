# ADR-001 — MVP Stack Lock (8-hour Nepal slice)

**Status:** Accepted  
**Date:** 2026-07-14  
**Owner:** Architecture (A5) + Security (A8) for privacy-adjacent constraints  
**Context:** Vertical demo for Nepal pilot — drug search, interaction checker, consent gate, regex PII scrubber. Synthetic data only.

---

## Decision

| Concern | Choice | Notes |
|---|---|---|
| UI | **Flutter 3.x** (Android-first) | Single codebase; iOS later if needed |
| Local store | **SQLite** via Flutter/Dart bindings | Seed from `data/nepal/` + `mvp_schema.sql` |
| Encryption at rest | **Plain SQLite first; SQLCipher soon** | Full Keystore/SQLCipher ceremony deferred past 8h |
| Search | **FTS5** for drugs (+ guideline text as needed) | **Before** `sqlite-vec` / hybrid RAG |
| Vectors / RAG embedding index | **Deferred** (`sqlite-vec` later) | FTS is enough for 50 drugs + 18 chunks today |
| On-device LLM | **None in 8h MVP** | No llama.cpp / GGUF; deterministic DB lookups only |
| PII | **Regex scrubber now; ONNX NER later** | Fixture-evaluated against `pii_scrubber_test_cases.json` |
| Sync / backend | **Deferred** | Consent default OFF; queue local-only / UI-blocked |

---

## Consequences

- Interaction **severity and recommendations come only from seeded `interactions` rows** — no model invention.
- Unencrypted local DB is an accepted residual risk for the demo day; SQLCipher is the next hardening ADR.
- Shipping FTS before vectors keeps seed/bootstrap simple and demo-stable offline.
- Adding an LLM later must not bypass consent gate or invent clinical severity.

---

## Non-goals (this ADR)

EMR patient records, Play Store release, production PHI, cloud ingest-api, certificate pinning, signed OTA models.

---

## References

- `docs/MVP_8H_CHECKPOINTS.md`
- `docs/security/threat-model-v0.1.md`
- `data/schema/mvp_schema.sql`
- `clinical-llm-technical-architecture.md` (target state; this ADR freezes the 8h subset)

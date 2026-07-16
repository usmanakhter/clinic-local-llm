# ADR-003 — Chat agent (RAG-first, local)

**Status:** Accepted (scope for next implementation slices)  
**Date:** 2026-07-16  
**Owner:** Architecture (A5) + ML (A7) + Medical (A2)  

---

## Decision

| Concern | Choice |
|---|---|
| Chat role | Grounded Q&A + discuss scrubbed past notes — **not** diagnosis authority |
| Retrieval | Shared `retrieve()` over drugs + guidelines (+ later sessions) **before** LLM |
| Empty retrieval | **Refuse** — do not invent clinical content |
| Interaction severity | **Never from chat LLM** — explain only if Interact/DB row was retrieved |
| Runtime (POC) | Same localhost Ollama sidecar as Notes (PC demo) |
| Runtime (field phones) | Progressive: RAG-only / templates on weak devices; optional on-device GGUF later |
| Consent | Chat transcripts stay local until scoped opt-in sync |

---

## Consequences

- Chat depends on corpus quality more than model brand.
- South Asia majority phones: chat UX must degrade gracefully without a local LLM.
- Captured chats (with feedback) feed the consented data flywheel after scrubbing.

---

## Non-goals (this ADR)

Cloud chat, MedLM fine-tune day one, selling identifiable transcripts.

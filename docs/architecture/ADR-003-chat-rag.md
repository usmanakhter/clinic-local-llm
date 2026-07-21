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
| Runtime (product Chat) | **On-device Qwen GGUF** (llama.cpp) — **hard error** if no model (no rules/Ollama fallback) |
| Runtime (Notes) | In-app draft engine; optional GGUF when present |
| Runtime (Flutter web Chat) | Hard error in this slice (native Windows/Android for neural Chat) |
| Consent | Chat transcripts stay local until scoped opt-in sync |

---

## Consequences

- Chat depends on corpus quality **and** a present on-device GGUF file.
- Missing model → explicit error (no silent rules/Ollama answers).
- Captured chats (with feedback) feed the consented data flywheel after scrubbing.

---

## Non-goals (this ADR)

Cloud chat, MedLM fine-tune day one, selling identifiable transcripts.

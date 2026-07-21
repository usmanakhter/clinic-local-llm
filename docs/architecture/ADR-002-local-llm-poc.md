# ADR-002 — On-device GGUF LLM (Chat hard-requires model)

**Status:** Accepted (amended 2026-07-21 — Linux desktop)  
**Date:** 2026-07-15  
**Owner:** Architecture (A5) + ML (A7)  
**Supersedes:** ADR-001 “no on-device LLM in 8h MVP”; prior Ollama-sidecar / in-app-rules Chat path  

---

## Decision

| Concern | Choice |
|---|---|
| **Product Chat runtime** | **On-device Qwen GGUF** via **llama.cpp** (Dart FFI / `llamadart`) on **Linux + Android + Windows** |
| Chat if no GGUF | **Hard error** — e.g. “No local model found …” — **no** rules-engine, **no** Ollama, **no** fake paraphrase |
| Notes runtime | In-app draft engine (`InAppDraftEngine`) allowed for structured SOAP; optional GGUF when present |
| Model file | Manual placement under app documents `models/` (or optional bundled asset) — **never** `ollama pull` |
| Default model target | **Qwen2.5-1.5B Instruct Q4_K_M** (or smaller Q4 if size forces it) |
| Flutter web Chat | Same hard error in this slice (neural Chat is native-only until a later WebGPU path) |
| Ollama sidecar | **Non-product** — may remain as dead/dev code; not a Chat fallback |

---

## Why GGUF (and not Ollama / rules Chat)

- Phones will not run an Ollama sidecar; firewalls often block `ollama.com` pulls.
- In-app rules are **not** a neural LLM — product Chat must not pretend they are.
- A local GGUF file + in-process llama.cpp matches the field architecture (STATUS §6 / tech architecture).

---

## Consequences

- Banner shows **On-device · qwen…** only when a GGUF is loaded; otherwise **No local model**.
- Chat answers only when GGUF is ready; retrieval still cite-or-refuse first, then GGUF paraphrases context.
- Model weights are not committed to git; operators copy GGUF via USB / own CDN / `ota-api` later.

---

## Non-goals

SQLCipher, automatic model OTA, device-tier auto-download, cloud inference, WebGPU Chat (this amendment).

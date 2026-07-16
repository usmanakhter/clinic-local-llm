# ADR-002 — Local LLM POC via HTTP Sidecar

**Status:** Accepted  
**Date:** 2026-07-15  
**Owner:** Architecture (A5) + ML (A7)  
**Supersedes for note-drafter only:** ADR-001 “no on-device LLM in 8h MVP”

---

## Decision

| Concern | Choice |
|---|---|
| Runtime | **Ollama** or **llama.cpp server** on localhost (OpenAI-compatible `/v1/chat/completions`) |
| Flutter integration | HTTP client to `http://127.0.0.1:11434` (configurable) |
| Default model preference | `qwen2.5:1.5b` (fast POC); `qwen2.5:3b` if machine allows |
| Allowed LLM use | **Note drafting only** (+ optional grounded guideline paraphrase later) |
| Forbidden LLM use | Inventing interaction **severity**; diagnosing; prescribing authority |
| Fallback | Fixture drafts from `note_drafter_samples.json` when sidecar unavailable |
| JNI / GGUF-in-APK | **Deferred** past this sprint |

---

## Consequences

- Rapid Windows demo without Android NDK/JNI work.
- Web (`localhost:8080`) may hit browser CORS; UI must show fixture fallback when the call fails.
- Clinical reference paths (search, interactions) stay DB-deterministic.

---

## Non-goals

SQLCipher note storage, model OTA, device-tier auto-download, cloud inference.

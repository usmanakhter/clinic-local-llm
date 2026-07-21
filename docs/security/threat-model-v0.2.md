# Threat Model v0.2 — Nepal Clinical Assistant (MVP close)

**Owner:** Security  
**Date:** 2026-07-21  
**Supersedes:** [threat-model-v0.1.md](threat-model-v0.1.md)  
**Scope:** Offline Flutter clinical reference + grounded Chat (GGUF) on **Linux / Windows / Android**; Terms-gated scrubbed sync queue; local ingest stub.  
**Data:** Synthetic fixtures in `data/nepal/` only — **no real PHI** until a pilot legal path exists.

---

## 1. Assets (MVP)

| Asset | Location | Sensitivity |
|---|---|---|
| Drug / interaction / guideline DB | On-device SQLite (+ FTS) | Public reference; integrity matters for severity |
| Local session / Past Notes history | `clinical_sessions` — **unredacted** | Clinician-readable clinical text; treat as sensitive |
| Local patient cards | `patients` (+ field crypto via `DbCrypto`) | Identifiable on device; **not** synced |
| Sync queue | `sync_queue` (`pending` \| `blocked_residual_pii` \| …) | Scrubbed copies only; blocked rows must never upload |
| Terms acceptance | SharedPreferences / consent audit (`np-terms-1.2`) | Legal gate; sync mandatory after accept (no in-app off) |
| On-device GGUF weights | `Documents/nepal_clinical/models/*.gguf` | Model IP / integrity; not PHI |
| Local ingest inbox | `services/ingest-api/inbox/` (dev only) | De-id batches; must stay synthetic |

**Out of scope (post-MVP):** production ap-south-1 ingest, signed OTA, full EMR, Play Store distribution.

---

## 2. Trust boundaries

```text
┌──────────────────── ON-DEVICE TRUST ZONE ────────────────────┐
│  Flutter UI → SQLite (FFI on Linux/Windows)                   │
│  Terms gate (required) → scrub copy → sync_queue              │
│  Local history stays unredacted                               │
│  Chat: retrieve → cite/refuse → GGUF only (hard fail if miss) │
└──────────────────────────────┬───────────────────────────────┘
                               │  BOUNDARY: network egress
                               │  Sync ON after Terms; flush when reachable
                               ▼
                    Local ingest-api :8787 (stub)
                    [ Future: ap-south-1 ingest — not enabled ]
```

| Boundary | Rule |
|---|---|
| UI → DB | Formulary/interactions DB-only for severity; sessions/patients as designed |
| App → Network | No production clinical upload. `SyncWorker.debugFlushPending` → localhost stub only |
| Terms → Sync | First-launch Terms (`np-terms-1.2`) **requires** sync; no separate Consent tab; no in-app sync off |
| Scrub → Queue | Residual structural PII → `blocked_residual_pii` + `scrub_note`; excluded from flush |
| Repo → Device | Synthetic `data/nepal/` fixtures only |
| GGUF → Chat | Missing/unloadable model → explicit error; never rules/Ollama fallback |

---

## 3. Top threats (STRIDE-lite)

| ID | STRIDE | Threat | Impact |
|---|---|---|---|
| T1 | Spoofing | Shared/lost unlocked device | Unredacted sessions + patient cards readable |
| T2 | Tampering | Altered seed DB / GGUF on disk | Wrong severity or unsafe Chat paraphrase |
| T3 | Repudiation | Terms acceptance without durable audit | Sync appears authorized without proof |
| T4 | Info disclosure | Scrub miss → pending upload; backups; debug flush; screenshots | Privacy / pilot credibility |
| T5 | DoS | Corrupt DB, missing GGUF, FTS failure | Demo / field assist unavailable |
| T6 | Elevation | Bypass Terms or flush blocked rows | De-id flywheel poisoned or PHI egress |
| T7 | Tampering / disclosure | Prompt injection via retrieved context into GGUF | Hallucinated advice if cite-or-refuse fails |

**Explicit non-threats for this slice:** remote RCE on AWS (no prod deploy), selling identifiable PHI (Terms + scrub forbid it).

---

## 4. Mitigations + residual risks

| Threat | Mitigation in MVP | Residual risk |
|---|---|---|
| T1 | Field-level `DbCrypto` for patient fields; short-lived demos | Full SQLCipher deferred; unlocked device still exposes local history |
| T2 | Interaction severity **DB-only**; Chat cite-or-refuse before GGUF | No signed formulary/GGUF hash yet |
| T3 | Required Terms gate version `np-terms-1.2`; sync transparency UI | **Lawyer review of Terms still open** (external gate for pilot) |
| T4 | Production heuristics scrubber; reject-to-queue; flush only `pending`; transparency screen | Regex/heuristic miss; Android/desktop backup may include DB |
| T5 | Seed scripts + gold evals + GGUF-required tests | Manual GGUF placement; device-tier packaging later |
| T6 | Status vocabulary `blocked_residual_pii`; debug flush excludes blocked | Accidental prod endpoint wiring without HMAC/WiFi gates |
| T7 | RAG cite-or-refuse; no severity invention by LLM | Model may still paraphrase poorly; disclaimer required |

---

## 5. Hard rules (non-negotiable)

1. **Terms required** before clinical use of the app (includes sync/data consent).  
2. **No invented interaction severity** — unknown pair → local-DB “unknown”; never LLM severity.  
3. **Synthetic data only** in repo/demos until pilot legal path.  
4. **Not for clinical use** — permanent disclaimer until regulatory posture changes.  
5. **Chat never falls back** to rules engine or Ollama — missing GGUF → explicit error.  
6. **No sale/training on identifiable clinical content** — scrub sync payloads; local history stays on device.  
7. **Blocked queue rows never upload** — `blocked_residual_pii` excluded from flush/pending lists.

---

## 6. Acceptance checks

- [x] Fresh install shows Terms gate (`np-terms-1.2`) before home shell  
- [x] Sync transparency UI lists scrubbed queue statuses including blocked  
- [x] Interaction checker: DB severity only  
- [x] Scrubber recall gate on fixture suite (≥99% target; CI QA)  
- [x] Reject-to-queue: residual → `blocked_residual_pii`; not in `listPendingSync`  
- [x] Chat hard-requires GGUF on native; web → no local model  
- [x] Repo/fixtures contain no real PHI  
- [x] Disclaimer visible on clinical screens  
- [ ] **External:** lawyer review of `np-terms-1.2` before pilot  
- [ ] **Post-MVP:** SQLCipher; signed GGUF/OTA; ap-south-1 HMAC + WiFi worker  

---

## 7. Next revision (v0.3)

Production ingest threat surface (HMAC, cert pinning, region lock), Android backup exclusion, signed formulary + model manifests, device-loss / remote wipe policy for pilot devices.

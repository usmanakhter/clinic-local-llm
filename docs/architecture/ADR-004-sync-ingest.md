# ADR-004 — Sync ingest stub (Phase 3)

**Status:** Accepted (stub / local-dev only)  
**Date:** 2026-07-20  
**Owner:** Architecture (A5) + Security (A8) + Backend (A6)  
**Context:** Local `sync_queue` already holds scrubbed interaction copies after Terms accept. This ADR locks the Phase 3 destination, payload boundary, and gate so network sync can be scaffolded without enabling production upload.

---

## Decision

### What syncs

| Syncs | Does **not** sync |
|---|---|
| Scrubbed interaction payloads from `sync_queue` (session summaries, query type, de-id metadata) | Patient registry / EMR-style PHI (names, phones, free-text patient notes as stored locally) |
| Device id + consent version for audit | Unredacted on-device clinical history |
| Scrub timestamps / queue ids | Raw crash logs containing PHI |

Local Activity history stays clinician-readable and unredacted. Only the scrubbed copy enqueued for sync may leave the device.

### Destination (India-region AWS — not Firebase)

Target region: **AWS ap-south-1 (Mumbai)** for DPDPA residency.

| Service | Role |
|---|---|
| `consent-api` | Device registration, consent version, audit trail |
| `ingest-api` | Receive HMAC-signed de-id interaction batches |
| `ota-api` | Model / index manifests and signed patches |
| RDS PostgreSQL | Consent + ingest **metadata only** (no PHI) |
| S3 | Encrypted-at-rest **de-identified** interaction corpus |

**Explicit non-choice:** Firebase (Auth / Firestore / Analytics) is **not** the sync backend.

### Flow

```text
Terms accept (np-terms-*)
  → local session insert (unredacted)
  → scrub copy → sync_queue (pending | blocked_residual_pii)
  → WiFi-only worker (default OFF in this stub)
  → HMAC-signed POST /v1/ingest/batch
  → server re-validates; reject residual PII
  → inbox / curated corpus pipeline
```

Device policy (production): WiFi-only by default; no cellular upload unless a future explicit setting overrides.

### Dev vs prod

| Mode | Behavior |
|---|---|
| **Dev / POC** | Local `services/ingest-api` on `127.0.0.1:8787`; Flutter `SyncWorker.flushPending()` after Terms (auto on home open + Sync transparency); HMAC optional / stubbed |
| **Prod** | ap-south-1 endpoints; TLS + cert pinning; HMAC required; WiFi-preferred; **upload gated on scrubber >99% recall** on held-out PII fixtures |

After Terms acceptance (`np-terms-1.2`), sync is **always on** — no in-app off switch. Queuing is continuous; upload attempts run when an ingest endpoint is reachable.

Regex scrub (~30% name/place recall) is **demo-only**. Production network sync must not ship until the production scrubber clears the recall gate.

### Transparency UI (shipped)

Clinicians can open **Sync transparency** (app-bar cloud icon) to see scrubbed `sync_queue` rows: status (`pending` / `synced` / `blocked_residual_pii` / …), scrub timestamps, and `scrub_note`. Debug flush to local ingest-api is available from that screen; destination region / batch ids for production ap-south-1 remain post-MVP.

---

## Consequences

- Client sync stays **opt-in / debug-only** until scrub quality and legal review clear.
- Server is a second line of defense: reject obvious PHI keys and residual structural PII even if the device gate failed.
- Expanding sync to patient cards or identifiable notes requires a new ADR + consent scope bump.

---

## Non-goals (this ADR)

Production deployment, WorkManager WiFi jobs, real HMAC key management, Firebase, uploading patient registry rows.

---

## References

- `docs/STATUS.md`
- `docs/security/threat-model-v0.2.md`
- `services/ingest-api/` (local stub)
- `apps/clinical_assistant/lib/data/sync_worker.dart`
- `apps/clinical_assistant/lib/screens/sync_transparency_screen.dart`
- `clinical-llm-technical-architecture.md` §2.7 Backend MVP

# ADR-004 — Sync ingest (Phase 3)

**Status:** Accepted  
**Date:** 2026-07-20 (amended 2026-07-22)  
**Owner:** Architecture (A5) + Security (A8) + Backend (A6)  
**Context:** Local `sync_queue` holds scrubbed interaction copies after Terms accept. This ADR locks destination, payload boundary, and server gate.

---

## Decision

### What syncs

| Syncs | Does **not** sync |
|---|---|
| Scrubbed interaction payloads from `sync_queue` (session summaries, query type, de-id metadata) | Patient registry / EMR-style PHI (names, phones, free-text patient notes as stored locally) |
| Device id + consent version for audit | Unredacted on-device clinical history |
| Scrub timestamps / queue ids | Raw crash logs containing PHI |

Local session history stays clinician-readable and unredacted. Only the scrubbed copy enqueued for sync may leave the device.

### Destination — Supabase Mumbai (ap-south-1)

**Production sync host:** [Supabase](https://supabase.com) project in **Mumbai (ap-south-1)** for India-region residency (DPDPA-aligned placement).

| Piece | Role |
|---|---|
| Edge Function `ingest-batch` | Receive de-id batches; re-validate; reject residual PII |
| Postgres `sync_ingest` | Store scrubbed payloads (RLS on; no direct client writes) |
| Local `services/ingest-api` | Dev/offline stub only (`127.0.0.1:8787`) |

**Explicit non-choice:** Firebase (Auth / Firestore / Analytics) is **not** the sync backend.

**Why not AWS RDS/S3 yet:** Early volume is ≪1GB. A Mumbai Supabase project covers ingest + SQL without Lightsail/RDS/App Runner overhead. AWS (or equivalent) remains an **optional later scale path** if we outgrow Supabase, need dedicated OTA object pipelines, or counsel requires a different processor — not a planned “next hop” for the current flywheel.

### Flow

```text
Terms accept (np-terms-*)
  → local session insert (unredacted)
  → scrub copy → sync_queue (pending | blocked_residual_pii)
  → WiFi-preferred worker
  → POST ingest-batch (Supabase) or local /v1/ingest/batch
  → server re-validates; reject residual PII
  → sync_ingest rows → curated corpus pipeline
```

Device policy (production): WiFi-only by default; no cellular upload unless a future explicit setting overrides.

### Dev vs prod

| Mode | Behavior |
|---|---|
| **Dev / POC** | Local `services/ingest-api` on `127.0.0.1:8787`; Flutter `SyncWorker.flushPending()` after Terms; HMAC optional / stubbed |
| **Prod** | Supabase Mumbai Edge Function; TLS; `INGEST_BASE_URL` + `INGEST_ANON_KEY` dart-defines; HMAC still TODO; WiFi-preferred; **upload gated on scrubber >99% recall** on held-out PII fixtures |

After Terms acceptance (`np-terms-1.2`), sync is **always on** — no in-app off switch. Queuing is continuous; upload attempts run when an ingest endpoint is reachable.

### Transparency UI (shipped)

Clinicians can open **Sync transparency** (app-bar cloud icon) to see scrubbed `sync_queue` rows: status (`pending` / `synced` / `blocked_residual_pii` / …), scrub timestamps, and `scrub_note`.

---

## Consequences

- Server is a second line of defense: reject obvious PHI keys and residual structural PII even if the device gate failed.
- App must not insert into `sync_ingest` with the anon key; only the Edge Function (service role) writes.
- Expanding sync to patient cards or identifiable notes requires a new ADR + consent scope bump.
- OTA model delivery can stay a separate concern (object storage later); it does not force AWS for interaction ingest.

---

## Non-goals (this ADR)

WorkManager WiFi jobs, real HMAC key management, Firebase, uploading patient registry rows, multi-region failover.

---

## References

- `supabase/README.md`
- `docs/STATUS.md`
- `docs/security/threat-model-v0.2.md`
- `services/ingest-api/` (local stub)
- `apps/clinical_assistant/lib/data/sync_worker.dart`
- `apps/clinical_assistant/lib/screens/sync_transparency_screen.dart`

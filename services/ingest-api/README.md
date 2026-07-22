# ingest-api (local stub)

Minimal FastAPI service that accepts scrubbed `sync_queue` batches and writes them under `inbox/`.

**Dev/offline only.** Production ingest is Supabase Mumbai — see `supabase/README.md` and ADR-004.

## Run locally

```bash
cd services/ingest-api
python -m venv .venv

# Windows
.venv\Scripts\activate
# macOS / Linux
# source .venv/bin/activate

pip install -r requirements.txt
# If pydantic-core fails to build (e.g. very new Python), use:
#   pip install --only-binary=:all: -r requirements.txt
uvicorn main:app --host 127.0.0.1 --port 8787 --reload
```

Health: `GET http://127.0.0.1:8787/health`

## Ingest batch

```bash
curl -s -X POST http://127.0.0.1:8787/v1/ingest/batch \
  -H "Content-Type: application/json" \
  -d '{"device_id":"dev-device","consent_version":"np-terms-1.2","items":[{"id":"sync_demo","payload":{"query_type":"drug_search","input_summary":"amoxicillin"},"scrubbed_at":"2026-07-20T12:00:00Z"}]}'
```

Accepted batches land in `services/ingest-api/inbox/*.json`.

Payloads with keys like `patient_name` / `phone`, or residual phone/email text, are rejected with HTTP 422.

## Flutter

Default (no dart-defines) still hits this stub. For Mumbai:

```bash
flutter run \
  --dart-define=INGEST_BASE_URL=https://<project-ref>.supabase.co/functions/v1/ingest-batch \
  --dart-define=INGEST_ANON_KEY=<anon-key>
```

See ADR-004: `docs/architecture/ADR-004-sync-ingest.md`.

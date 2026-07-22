# Supabase Mumbai sync ingest

Production destination for scrubbed `sync_queue` batches (ADR-004). Region: **ap-south-1 (Mumbai)**.

Local FastAPI under `services/ingest-api/` remains the offline/dev stub.

## One-time setup

```bash
# Install CLI: https://supabase.com/docs/guides/cli
supabase login
supabase link --project-ref <your-project-ref>

# Apply table + RLS
supabase db push

# Deploy ingest gate
supabase functions deploy ingest-batch
```

## Invoke

```bash
PROJECT_URL="https://<project-ref>.supabase.co"
ANON_KEY="<anon-or-publishable-key>"

curl -s -X POST "$PROJECT_URL/functions/v1/ingest-batch" \
  -H "Content-Type: application/json" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $ANON_KEY" \
  -d '{"device_id":"dev-device","consent_version":"np-terms-1.2","items":[{"id":"sync_demo","payload":{"query_type":"drug_search","input_summary":"amoxicillin"},"scrubbed_at":"2026-07-20T12:00:00Z"}]}'
```

Accepted rows land in `public.sync_ingest` (service role only; RLS blocks direct client writes).

## Flutter

```bash
flutter run --dart-define=INGEST_BASE_URL=https://<project-ref>.supabase.co/functions/v1/ingest-batch \
  --dart-define=INGEST_ANON_KEY=<anon-key>
```

Without dart-defines, the app keeps using local `http://127.0.0.1:8787`.

-- Scrubbed sync_queue ingest (de-identified only). No patient registry / PHI.
-- Direct client writes are denied; only the Edge Function (service role) inserts.

create table if not exists public.sync_ingest (
  id text primary key,
  device_id text not null,
  consent_version text not null,
  payload jsonb not null,
  scrubbed_at timestamptz,
  received_at timestamptz not null default now(),
  batch_id text
);

create index if not exists sync_ingest_received_at_idx
  on public.sync_ingest (received_at desc);

create index if not exists sync_ingest_device_id_idx
  on public.sync_ingest (device_id);

alter table public.sync_ingest enable row level security;

-- No policies for anon/authenticated → no direct table access from the app.
-- Service role bypasses RLS for the ingest Edge Function.

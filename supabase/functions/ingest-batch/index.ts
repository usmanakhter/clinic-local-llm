/**
 * Ingest scrubbed sync_queue batches (mirrors services/ingest-api validation).
 *
 * POST /functions/v1/ingest-batch
 * Body: { device_id, consent_version, items: [{ id, payload, scrubbed_at }] }
 *
 * Deploy: supabase functions deploy ingest-batch
 * Invoke with apikey + Authorization Bearer <anon or publishable key>.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const FORBIDDEN_KEYS = new Set([
  "patient_name",
  "full_name",
  "display_name",
  "phone",
  "phone_number",
  "mobile",
  "email",
  "address",
  "national_id",
]);

const RESIDUAL_PII = [
  /\+977[\s\-]?\d{8,10}\b/,
  /(?:\+?977[\s\-]*)?(?:98|97)\d{8}\b/,
  /\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b/,
];

const REDACTED = "[REDACTED]";
const SCRUB_HINT = /(?:\+?977|98\d{8}|97\d{8}|@)/i;

type IngestItem = {
  id: string;
  payload: unknown;
  scrubbed_at: string;
};

type IngestBatch = {
  device_id: string;
  consent_version: string;
  items: IngestItem[];
};

function walkKeys(obj: unknown, found: Set<string>): void {
  if (obj !== null && typeof obj === "object") {
    if (Array.isArray(obj)) {
      for (const item of obj) walkKeys(item, found);
      return;
    }
    for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
      found.add(k.toLowerCase());
      walkKeys(v, found);
    }
  }
}

function asText(obj: unknown): string {
  if (typeof obj === "string") return obj;
  return JSON.stringify(obj);
}

function validatePayload(payload: unknown): void {
  const keys = new Set<string>();
  walkKeys(payload, keys);
  const bad = [...keys].filter((k) => FORBIDDEN_KEYS.has(k)).sort();
  if (bad.length > 0) {
    throw new Response(
      JSON.stringify({
        detail: `Rejected - forbidden PHI keys: ${bad.join(", ")}`,
      }),
      { status: 422, headers: { "Content-Type": "application/json" } },
    );
  }

  const text = asText(payload);
  for (const pattern of RESIDUAL_PII) {
    if (pattern.test(text)) {
      throw new Response(
        JSON.stringify({
          detail: "Rejected - residual structural PII in payload",
        }),
        { status: 422, headers: { "Content-Type": "application/json" } },
      );
    }
  }

  if (SCRUB_HINT.test(text) && !text.includes(REDACTED)) {
    throw new Response(
      JSON.stringify({
        detail:
          "Rejected - expected [REDACTED] missing for scrub-hint fields",
      }),
      { status: 422, headers: { "Content-Type": "application/json" } },
    );
  }
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method === "GET") {
    return new Response(
      JSON.stringify({ status: "ok", service: "ingest-batch" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ detail: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let body: IngestBatch;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ detail: "Invalid JSON" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (!body.device_id || !body.consent_version) {
    return new Response(
      JSON.stringify({ detail: "device_id and consent_version required" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  if (!Array.isArray(body.items) || body.items.length === 0) {
    return new Response(JSON.stringify({ detail: "items must not be empty" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    for (const item of body.items) {
      if (!item?.id) {
        return new Response(JSON.stringify({ detail: "each item needs id" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      validatePayload(item.payload);
    }
  } catch (err) {
    if (err instanceof Response) {
      const detail = await err.text();
      return new Response(detail, {
        status: err.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    throw err;
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return new Response(
      JSON.stringify({ detail: "Server misconfigured" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const supabase = createClient(supabaseUrl, serviceKey);
  const batchId = crypto.randomUUID();
  const rows = body.items.map((item) => ({
    id: item.id,
    device_id: body.device_id,
    consent_version: body.consent_version,
    payload: item.payload,
    scrubbed_at: item.scrubbed_at ?? null,
    batch_id: batchId,
  }));

  const { error } = await supabase.from("sync_ingest").upsert(rows, {
    onConflict: "id",
    ignoreDuplicates: false,
  });

  if (error) {
    return new Response(
      JSON.stringify({ detail: `DB error: ${error.message}` }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const accepted = body.items.map((i) => i.id);
  return new Response(
    JSON.stringify({
      ok: true,
      accepted: accepted.length,
      item_ids: accepted,
      batch_id: batchId,
    }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});

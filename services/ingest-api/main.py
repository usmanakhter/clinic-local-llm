"""Local ingest-api stub — accepts scrubbed sync_queue batches for Phase 3 POC.

Not production. Writes accepted batches to ./inbox as JSON files.
Rejects obvious PHI markers; does not implement HMAC or AWS deploy.
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

APP_DIR = Path(__file__).resolve().parent
INBOX_DIR = APP_DIR / "inbox"
INBOX_DIR.mkdir(exist_ok=True)

# Obvious PHI field names that must never appear in outbound payloads.
FORBIDDEN_KEYS = frozenset(
    {
        "patient_name",
        "full_name",
        "display_name",
        "phone",
        "phone_number",
        "mobile",
        "email",
        "address",
        "national_id",
    }
)

# Structural PII that should have been replaced with [REDACTED] on-device.
RESIDUAL_PII = [
    re.compile(r"\+977[\s\-]?\d{8,10}\b"),
    re.compile(r"(?:\+?977[\s\-]*)?(?:98|97)\d{8}\b"),
    re.compile(r"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b"),
]

REDACTED = "[REDACTED]"
# If payload text looks like it still holds a Nepali mobile / email pattern
# without a redaction token anywhere, treat as failed scrub.
SCRUB_HINT = re.compile(
    r"(?:\+?977|98\d{8}|97\d{8}|@)",
    re.IGNORECASE,
)

app = FastAPI(title="clinic-local-llm ingest-api", version="0.1.0")


class IngestItem(BaseModel):
    id: str
    payload: Any
    scrubbed_at: str


class IngestBatch(BaseModel):
    device_id: str
    consent_version: str
    items: list[IngestItem] = Field(default_factory=list)


def _walk_keys(obj: Any, found: set[str]) -> None:
    if isinstance(obj, dict):
        for k, v in obj.items():
            found.add(str(k).lower())
            _walk_keys(v, found)
    elif isinstance(obj, list):
        for item in obj:
            _walk_keys(item, found)


def _as_text(obj: Any) -> str:
    if isinstance(obj, str):
        return obj
    return json.dumps(obj, ensure_ascii=False)


def validate_payload(payload: Any) -> None:
    keys: set[str] = set()
    _walk_keys(payload, keys)
    bad = sorted(keys & FORBIDDEN_KEYS)
    if bad:
        raise HTTPException(
            status_code=422,
            detail=f"Rejected - forbidden PHI keys: {', '.join(bad)}",
        )

    text = _as_text(payload)
    for pattern in RESIDUAL_PII:
        if pattern.search(text):
            raise HTTPException(
                status_code=422,
                detail="Rejected - residual structural PII in payload",
            )

    # Expected scrub fields: if content still hints at phone/email patterns
    # but never contains [REDACTED], assume scrub did not run.
    if SCRUB_HINT.search(text) and REDACTED not in text:
        raise HTTPException(
            status_code=422,
            detail="Rejected - expected [REDACTED] missing for scrub-hint fields",
        )


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "ingest-api"}


@app.post("/v1/ingest/batch")
def ingest_batch(body: IngestBatch) -> dict[str, Any]:
    if not body.items:
        raise HTTPException(status_code=400, detail="items must not be empty")

    accepted: list[str] = []
    for item in body.items:
        validate_payload(item.payload)
        accepted.append(item.id)

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    safe_device = re.sub(r"[^a-zA-Z0-9_-]", "_", body.device_id)[:64]
    out_path = INBOX_DIR / f"batch_{stamp}_{safe_device}.json"
    record = {
        "received_at": datetime.now(timezone.utc).isoformat(),
        "device_id": body.device_id,
        "consent_version": body.consent_version,
        "item_ids": accepted,
        "items": [item.model_dump() for item in body.items],
    }
    out_path.write_text(json.dumps(record, indent=2, ensure_ascii=False), encoding="utf-8")

    return {
        "ok": True,
        "accepted": len(accepted),
        "item_ids": accepted,
        "inbox_file": out_path.name,
    }

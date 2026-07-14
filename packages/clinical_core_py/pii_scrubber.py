"""Regex PII scrubber — mirrors apps/clinical_assistant/lib/privacy/pii_scrubber.dart."""

from __future__ import annotations

import re

REDACTED = "[REDACTED]"

SCRUB_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"\+977[\s\-]?\d{8,10}\b"),
    re.compile(r"(?:\+?977[\s\-]*)?(?:98|97)\d{8}\b"),
    re.compile(r"[९८][०-९]{9}"),
    re.compile(r"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b"),
    re.compile(r"\bNMC[\-\s]?\d{4}[\-\s]?\d{4,}\b", re.IGNORECASE),
    re.compile(r"\b[A-Z]\d{7}\b"),
    re.compile(r"\bHREG[\-\s]?\d{4}[\-\s]?\d{3,}\b", re.IGNORECASE),
    re.compile(r"\bHP[\-\s]?\d{4}[\-\s]?\d{4,}\b", re.IGNORECASE),
    re.compile(r"\bNP[\-\s]?[A-Z]{2,4}[\-\s]?\d{9,}\b", re.IGNORECASE),
    re.compile(r"\b\d{2,4}/\d{2,4}[\-\s]?\d{6,}\b"),
    re.compile(r"[०-९]{2,4}/[०-९]{2,4}[\-\s]?[०-९]{6,}"),
    re.compile(r"[०-९]{2}[\-\s][०-९]{2}[\-\s][०-९]{2}[\-\s][०-९]{6,}"),
]


def scrub_text(text: str) -> str:
    out = text
    for pat in SCRUB_PATTERNS:
        out = pat.sub(REDACTED, out)
    return out

#!/usr/bin/env python3
"""Smoke local LLM sidecar (Ollama). Skips cleanly if unavailable."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434").rstrip("/")
MODEL = os.environ.get("CLINICAL_LLM_MODEL", "qwen2.5:1.5b")


def available() -> bool:
    for path in ("/api/tags", "/v1/models"):
        try:
            with urllib.request.urlopen(f"{BASE}{path}", timeout=3) as res:
                if res.status == 200:
                    return True
        except Exception:
            continue
    return False


def _complete(system: str, user: str, temperature: float = 0.2) -> str:
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": temperature,
        "stream": False,
    }
    req = urllib.request.Request(
        f"{BASE}/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=90) as res:
        data = json.loads(res.read().decode("utf-8"))
    return data["choices"][0]["message"]["content"]


def draft() -> str:
    return _complete(
        (
            "Draft a short clinical note. Draft only. "
            "Do not invent interaction severity. "
            "End with: Draft only — not for clinical use."
        ),
        (
            "CC: Fever and cough 4 days\n"
            "Hx: Adult 30s, no chronic illness\n"
            "Exam: Temp 38.5C, throat erythema, chest clear\n"
            "Assessment: Likely viral URTI\n"
            "Plan: Paracetamol, fluids"
        ),
    )


def grounded() -> str:
    return _complete(
        (
            "Answer ONLY from RETRIEVED CONTEXT. Cite ids. "
            "Do not invent interaction severity. "
            "End with: Draft only — not for clinical use."
        ),
        (
            "QUESTION: scrub typhus treatment\n\n"
            "RETRIEVED CONTEXT:\n"
            "- [drug_056] Doxycycline: first-line for scrub typhus in Nepal; "
            "100mg BD; avoid in pregnancy.\n"
            "- [guide_019] Scrub Typhus: empiric doxycycline when suspected.\n"
        ),
        temperature=0.1,
    )


def main() -> int:
    if not available():
        print(f"SKIP: local LLM not reachable at {BASE}")
        print("Start: ollama serve && ollama pull qwen2.5:1.5b")
        return 0
    try:
        text = draft()
        grounded_text = grounded()
    except urllib.error.URLError as e:
        print(f"SKIP: LLM call failed: {e}")
        return 0
    print(f"OK model={MODEL} note_draft")
    print(text[:400])
    print("---")
    print(f"OK model={MODEL} grounded_chat")
    print(grounded_text[:400])
    return 0


if __name__ == "__main__":
    sys.exit(main())

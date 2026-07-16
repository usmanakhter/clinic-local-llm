#!/usr/bin/env python3
"""Smoke test for shared retrieve API."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "packages"))

from clinical_core_py import ClinicalRepository  # noqa: E402
from clinical_core_py.retrieve import format_context_block, retrieve  # noqa: E402


def main() -> int:
    with ClinicalRepository() as repo:
        hit = retrieve(repo, "dengue fever avoid aspirin")
        assert not hit.refused, hit.refuse_reason
        assert any(g.id == "guide_002" for g in hit.guidelines), hit.guidelines
        ctx = format_context_block(hit)
        assert "guide_002" in ctx
        assert "Do not invent" in ctx

        empty = retrieve(repo, "   ")
        assert empty.refused

        miss = retrieve(repo, "xyzzy-nonexistent-token-98765")
        # May refuse or return weak hits; if any drugs/guides, ok; if none, refuse
        if not miss.drugs and not miss.guidelines:
            assert miss.refused

    print("retrieve_smoke OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())

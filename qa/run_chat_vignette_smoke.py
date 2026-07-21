#!/usr/bin/env python3
"""Chat vignette retrieval smoke (Python parity with Flutter test)."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "packages"))

from clinical_core_py import ClinicalRepository, retrieve  # noqa: E402

VIGNETTES = [
    ("scrub typhus doxycycline", False),
    ("dengue paracetamol avoid aspirin", False),
    ("hypertension amlodipine nepal", False),
    ("snake bite antivenom", False),
    ("zzqwx nonclinical gibberish 99999", True),
]


def main() -> int:
    fails = 0
    with ClinicalRepository() as repo:
        for query, expect_refuse in VIGNETTES:
            result = retrieve(repo, query)
            if result.refused != expect_refuse:
                print(f"FAIL {query!r}: refused={result.refused} expected={expect_refuse}")
                fails += 1
                continue
            if not expect_refuse and not result.drugs and not result.guidelines:
                print(f"FAIL {query!r}: no hits")
                fails += 1
            else:
                print(f"OK {query!r}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())

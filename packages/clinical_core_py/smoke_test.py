#!/usr/bin/env python3
"""Thin smoke asserts for clinical_core_py against seeded nepal_mvp_dev.db."""

from __future__ import annotations

import sys
from pathlib import Path

_PKG_PARENT = Path(__file__).resolve().parents[1]
if str(_PKG_PARENT) not in sys.path:
    sys.path.insert(0, str(_PKG_PARENT))

from clinical_core_py.interactions import lookup
from clinical_core_py.repository import ClinicalRepository
from clinical_core_py.search import search_drugs


def main() -> None:
    with ClinicalRepository() as repo:
        para = search_drugs(repo, "Paracetamol")
        assert para, "search(Paracetamol) returned no hits"
        assert para[0].drug.id == "drug_001", (
            f"expected drug_001 first, got {para[0].drug.id}"
        )

        nepalol = search_drugs(repo, "Nepalol")
        assert nepalol, "search(Nepalol) returned no hits"
        ids = {r.drug.id for r in nepalol}
        assert "drug_001" in ids, f"Nepalol should resolve to Paracetamol, got {ids}"

        pair = lookup(repo, "drug_005", "drug_006")
        assert pair is not None, "expected interaction for drug_005 + drug_006"
        assert pair.severity == "contraindicated", (
            f"expected contraindicated, got {pair.severity}"
        )

        unknown = lookup(repo, "drug_001", "drug_050")
        assert unknown is None, f"unknown pair must be None, got {unknown}"

    print("smoke_test OK")


if __name__ == "__main__":
    main()

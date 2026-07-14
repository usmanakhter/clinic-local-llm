#!/usr/bin/env python3
"""CLI demo for clinical_core_py domain logic.

Examples:
  python -m packages.clinical_core_py.cli_demo search Paracetamol
  python packages/clinical_core_py/cli_demo.py interact drug_005 drug_006
  python packages/clinical_core_py/cli_demo.py guide typhoid
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Allow `python packages/clinical_core_py/cli_demo.py` without install.
_PKG_PARENT = Path(__file__).resolve().parents[1]
if str(_PKG_PARENT) not in sys.path:
    sys.path.insert(0, str(_PKG_PARENT))

from clinical_core_py.guidelines import search_guidelines
from clinical_core_py.interactions import lookup
from clinical_core_py.repository import ClinicalRepository
from clinical_core_py.search import search_drugs


def _cmd_search(repo: ClinicalRepository, q: str) -> int:
    hits = search_drugs(repo, q)
    if not hits:
        print("No drugs matched.")
        return 1
    for r in hits:
        brands = ", ".join(b.name for b in r.drug.brand_names) or "—"
        print(
            f"{r.drug.id}\t{r.drug.generic_name}\t"
            f"score={r.score:.0f}\t[{r.match_reason}]\tbrands={brands}"
        )
    return 0


def _cmd_interact(repo: ClinicalRepository, id_a: str, id_b: str) -> int:
    hit = lookup(repo, id_a, id_b)
    if hit is None:
        print("null")
        print(
            json.dumps(
                {
                    "drug_a_id": id_a,
                    "drug_b_id": id_b,
                    "interaction": None,
                    "note": "No curated row — do not infer safety",
                },
                indent=2,
            )
        )
        return 0
    print(
        json.dumps(
            {
                "id": hit.id,
                "drug_a_id": hit.drug_a_id,
                "drug_b_id": hit.drug_b_id,
                "severity": hit.severity,
                "mechanism": hit.mechanism,
                "clinical_effect": hit.clinical_effect,
                "recommendation": hit.recommendation,
                "source": hit.source,
            },
            indent=2,
            ensure_ascii=False,
        )
    )
    return 0


def _cmd_guide(repo: ClinicalRepository, q: str) -> int:
    hits = search_guidelines(repo, q)
    if not hits:
        print("No guideline chunks matched.")
        return 1
    for r in hits:
        snippet = r.chunk.chunk_text.replace("\n", " ")
        if len(snippet) > 120:
            snippet = snippet[:117] + "..."
        print(
            f"{r.chunk.id}\t{r.chunk.title}\t"
            f"score={r.score:.0f}\t[{r.match_reason}]\t{snippet}"
        )
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="clinical_core_py",
        description="Nepal clinical MVP domain demo (search / interact / guide)",
    )
    p.add_argument(
        "--db",
        default=None,
        help="Path to nepal_mvp_dev.db (default: data/nepal_mvp_dev.db)",
    )
    sub = p.add_subparsers(dest="command", required=True)

    s = sub.add_parser("search", help="Search drugs by generic/brand/Nepali name")
    s.add_argument("q", help="Query string")

    i = sub.add_parser("interact", help="Lookup interaction for two drug ids")
    i.add_argument("id_a", help="First drug id (e.g. drug_005)")
    i.add_argument("id_b", help="Second drug id (e.g. drug_006)")

    g = sub.add_parser("guide", help="Keyword search guideline chunks")
    g.add_argument("q", help="Query string")

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    with ClinicalRepository(args.db) as repo:
        if args.command == "search":
            return _cmd_search(repo, args.q)
        if args.command == "interact":
            return _cmd_interact(repo, args.id_a, args.id_b)
        if args.command == "guide":
            return _cmd_guide(repo, args.q)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

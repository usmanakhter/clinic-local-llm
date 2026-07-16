#!/usr/bin/env python3
"""
Gold eval for data/nepal/eval_queries.jsonl against clinical_core_py.

Usage (repo root):
    python qa/run_eval_queries.py

Exit 0 if overall top-k hit rate >= 70% AND all interaction_check rows pass.
"""

from __future__ import annotations

import json
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "packages"))

from clinical_core_py import (  # noqa: E402
    ClinicalRepository,
    lookup_interaction,
    search_drugs,
    search_guidelines,
)

NEPAL = ROOT / "data" / "nepal"
EVAL_PATH = NEPAL / "eval_queries.jsonl"
INTERACTIONS_PATH = NEPAL / "interactions.json"
ARTIFACTS = ROOT / "artifacts"
REPORT_PATH = ARTIFACTS / "eval_gold_report.md"

TOP_K = 5
PASS_THRESHOLD = 70.0


def load_jsonl(path: Path) -> list[dict]:
    rows: list[dict] = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def load_interactions_by_id() -> dict[str, dict]:
    data = json.loads(INTERACTIONS_PATH.read_text(encoding="utf-8"))
    return {row["id"]: row for row in data.get("interactions", [])}


def eval_drug(repo: ClinicalRepository, row: dict) -> dict:
    expected = set(row.get("expected_drug_ids") or [])
    hits = search_drugs(repo, row["query"], limit=TOP_K)
    got = [h.drug.id for h in hits]
    ok = bool(expected & set(got)) if expected else True
    return {
        "id": row["id"],
        "type": "drug_lookup",
        "ok": ok,
        "expected": sorted(expected),
        "got": got,
        "detail": "top-k ∩ expected" if ok else "miss",
    }


def eval_guideline(repo: ClinicalRepository, row: dict) -> dict:
    expected = set(row.get("expected_guideline_ids") or [])
    hits = search_guidelines(repo, row["query"], limit=TOP_K)
    got = [h.chunk.id for h in hits]
    ok = bool(expected & set(got)) if expected else True
    return {
        "id": row["id"],
        "type": "guideline_search",
        "ok": ok,
        "expected": sorted(expected),
        "got": got,
        "detail": "top-k ∩ expected" if ok else "miss",
    }


def eval_interaction(
    repo: ClinicalRepository,
    row: dict,
    by_id: dict[str, dict],
) -> dict:
    expected_ids = row.get("expected_interaction_ids") or []
    if not expected_ids:
        return {
            "id": row["id"],
            "type": "interaction_check",
            "ok": False,
            "expected": [],
            "got": [],
            "detail": "no expected_interaction_ids",
        }
    ix_id = expected_ids[0]
    catalog = by_id.get(ix_id)
    if not catalog:
        return {
            "id": row["id"],
            "type": "interaction_check",
            "ok": False,
            "expected": expected_ids,
            "got": [],
            "detail": f"missing catalog id {ix_id}",
        }
    hit = lookup_interaction(repo, catalog["drug_a_id"], catalog["drug_b_id"])
    ok = hit is not None and hit.id == ix_id and hit.severity == catalog["severity"]
    # Secondary: guideline ids if present (informational for pass of interaction row)
    guide_ok = True
    guide_detail = ""
    expected_guides = set(row.get("expected_guideline_ids") or [])
    if expected_guides:
        guides = search_guidelines(repo, row["query"], limit=TOP_K)
        got_g = {g.chunk.id for g in guides}
        guide_ok = bool(expected_guides & got_g)
        guide_detail = f"; guides={'ok' if guide_ok else 'miss'}"
    return {
        "id": row["id"],
        "type": "interaction_check",
        "ok": ok,
        "expected": expected_ids,
        "got": [hit.id] if hit else [],
        "detail": (
            f"severity={hit.severity if hit else None}{guide_detail}"
            if ok
            else f"lookup failed{guide_detail}"
        ),
        "guide_ok": guide_ok,
    }


def write_report(results: list[dict], overall_pct: float, by_type: dict) -> None:
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    lines = [
        "# Eval Gold Report — Nepal Clinical AI",
        "",
        f"- Generated: `{now}`",
        f"- Fixture: `data/nepal/eval_queries.jsonl`",
        f"- Top-k: `{TOP_K}`",
        f"- Pass threshold: `{PASS_THRESHOLD}%` overall",
        "",
        f"## Overall: **{overall_pct:.1f}%** "
        f"({sum(1 for r in results if r['ok'])}/{len(results)})",
        "",
        "## By type",
        "",
    ]
    for t, stats in sorted(by_type.items()):
        pct = 100.0 * stats["ok"] / stats["n"] if stats["n"] else 0
        lines.append(f"- `{t}`: {stats['ok']}/{stats['n']} ({pct:.1f}%)")
    lines.extend(["", "## Failures", ""])
    fails = [r for r in results if not r["ok"]]
    if not fails:
        lines.append("_None._")
    else:
        lines.append("| ID | Type | Expected | Got | Detail |")
        lines.append("|---|---|---|---|---|")
        for r in fails:
            lines.append(
                f"| `{r['id']}` | `{r['type']}` | `{r['expected']}` | "
                f"`{r['got']}` | {r['detail']} |"
            )
    lines.append("")
    REPORT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    if not EVAL_PATH.is_file():
        print(f"ERROR: missing {EVAL_PATH}", file=sys.stderr)
        return 1

    rows = load_jsonl(EVAL_PATH)
    by_id = load_interactions_by_id()
    results: list[dict] = []

    with ClinicalRepository() as repo:
        for row in rows:
            t = row.get("type")
            if t == "drug_lookup":
                results.append(eval_drug(repo, row))
                # secondary guideline expectation (informational, not scored in drug row)
            elif t == "guideline_search":
                results.append(eval_guideline(repo, row))
            elif t == "interaction_check":
                results.append(eval_interaction(repo, row, by_id))
            else:
                results.append(
                    {
                        "id": row.get("id", "?"),
                        "type": t or "unknown",
                        "ok": False,
                        "expected": [],
                        "got": [],
                        "detail": "unknown type",
                    }
                )

    by_type: dict[str, dict] = defaultdict(lambda: {"ok": 0, "n": 0})
    for r in results:
        by_type[r["type"]]["n"] += 1
        if r["ok"]:
            by_type[r["type"]]["ok"] += 1

    overall_ok = sum(1 for r in results if r["ok"])
    overall_pct = 100.0 * overall_ok / len(results) if results else 0.0
    write_report(results, overall_pct, by_type)

    print(f"overall={overall_pct:.1f}% ({overall_ok}/{len(results)})")
    for t, stats in sorted(by_type.items()):
        pct = 100.0 * stats["ok"] / stats["n"] if stats["n"] else 0
        print(f"  {t}: {stats['ok']}/{stats['n']} ({pct:.1f}%)")
    print(f"Report: {REPORT_PATH}")

    ix_fail = [
        r for r in results if r["type"] == "interaction_check" and not r["ok"]
    ]
    gate_ok = overall_pct >= PASS_THRESHOLD and not ix_fail
    if not gate_ok:
        print("GATE FAIL: need >=70% overall and all interaction_check green")
        return 1
    print("GATE PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())

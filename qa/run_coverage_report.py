#!/usr/bin/env python3
"""OPD coverage + retrieval recall dashboard for Nepal corpus.

Usage (repo root):
    python qa/run_coverage_report.py

Writes artifacts/coverage_report.md and exits 0 if OPD coverage >= 90%.
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "packages"))

from clinical_core_py import ClinicalRepository, lookup_interaction, search_drugs, search_guidelines  # noqa: E402

NEPAL = ROOT / "data" / "nepal"
CHECKLIST = NEPAL / "opd_condition_checklist.json"
EVAL_PATH = NEPAL / "eval_queries.jsonl"
ARTIFACTS = ROOT / "artifacts"
REPORT = ARTIFACTS / "coverage_report.md"
TOP_K = 5
OPD_TARGET = 90.0
EVAL_TARGET = 85.0


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def load_jsonl(path: Path) -> list[dict]:
    rows = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def eval_condition(repo: ClinicalRepository, cond: dict) -> dict:
    q = cond["search_query"]
    exp_drugs = set(cond.get("expected_drug_ids") or [])
    exp_guides = set(cond.get("expected_guideline_ids") or [])

    drug_hits = [h.drug.id for h in search_drugs(repo, q, limit=TOP_K)]
    guide_hits = [h.chunk.id for h in search_guidelines(repo, q, limit=TOP_K)]

    drug_ok = bool(exp_drugs & set(drug_hits)) if exp_drugs else True
    guide_ok = bool(exp_guides & set(guide_hits)) if exp_guides else True
    retrieve_ok = drug_ok and guide_ok

    return {
        "id": cond["id"],
        "name": cond["name"],
        "weight": cond.get("weight", 1),
        "drug_ok": drug_ok,
        "guide_ok": guide_ok,
        "retrieve_ok": retrieve_ok,
        "got_drugs": drug_hits[:3],
        "got_guides": guide_hits[:3],
    }


def eval_gold_row(repo: ClinicalRepository, row: dict, ix_by_id: dict) -> dict:
    t = row.get("type")
    q = row["query"]
    ok = False
    if t == "drug_lookup":
        got = [h.drug.id for h in search_drugs(repo, q, limit=TOP_K)]
        exp = set(row.get("expected_drug_ids") or [])
        ok = bool(exp & set(got)) if exp else True
        if row.get("expected_guideline_ids"):
            g = [h.chunk.id for h in search_guidelines(repo, q, limit=TOP_K)]
            ok = ok and bool(set(row["expected_guideline_ids"]) & set(g))
    elif t == "guideline_search":
        got = [h.chunk.id for h in search_guidelines(repo, q, limit=TOP_K)]
        exp = set(row.get("expected_guideline_ids") or [])
        ok = bool(exp & set(got)) if exp else True
    elif t == "interaction_check":
        ix_id = (row.get("expected_interaction_ids") or [None])[0]
        cat = ix_by_id.get(ix_id)
        if cat:
            hit = lookup_interaction(repo, cat["drug_a_id"], cat["drug_b_id"])
            ok = hit is not None and hit.id == ix_id and hit.severity == cat["severity"]
    return {"id": row["id"], "type": t, "ok": ok}


def write_report(
    checklist: dict,
    cond_results: list[dict],
    gold_results: list[dict],
    weighted_pct: float,
    gold_pct: float,
) -> None:
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    by_topic: dict[str, list] = defaultdict(list)
    for r in cond_results:
        by_topic["all"].append(r)

    fails = [r for r in cond_results if not r["retrieve_ok"]]
    lines = [
        "# Coverage Dashboard — Nepal Clinical AI",
        "",
        f"- Generated: `{now}`",
        f"- OPD checklist: `{CHECKLIST.name}` ({checklist['condition_count']} conditions)",
        f"- Gold eval: `{EVAL_PATH.name}` ({len(gold_results)} queries)",
        "",
        "## Summary",
        "",
        f"| Metric | Result | Target |",
        f"|---|---|---|",
        f"| OPD catalog coverage (schema) | **{checklist['coverage_percent']}%** | {OPD_TARGET}% |",
        f"| OPD retrieval coverage (weighted) | **{weighted_pct:.1f}%** | {OPD_TARGET}% |",
        f"| Gold eval pass rate | **{gold_pct:.1f}%** | {EVAL_TARGET}% |",
        "",
        "## OPD retrieval misses",
        "",
    ]
    if not fails:
        lines.append("_None — all conditions retrieve expected drug + guideline in top-k._")
    else:
        lines.append("| Condition | Drugs OK | Guides OK | Top drug hits | Top guide hits |")
        lines.append("|---|---|---|---|---|")
        for r in fails:
            lines.append(
                f"| {r['name']} | {r['drug_ok']} | {r['guide_ok']} | "
                f"`{r['got_drugs']}` | `{r['got_guides']}` |"
            )

    lines.extend(["", "## Gold eval by type", ""])
    by_type: dict[str, dict] = defaultdict(lambda: {"ok": 0, "n": 0})
    for r in gold_results:
        by_type[r["type"]]["n"] += 1
        if r["ok"]:
            by_type[r["type"]]["ok"] += 1
    for t, s in sorted(by_type.items()):
        pct = 100.0 * s["ok"] / s["n"] if s["n"] else 0
        lines.append(f"- `{t}`: {s['ok']}/{s['n']} ({pct:.1f}%)")

    lines.append("")
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    if not CHECKLIST.is_file():
        print(f"ERROR: missing {CHECKLIST}", file=sys.stderr)
        return 1

    checklist = load_json(CHECKLIST)
    gold_rows = load_jsonl(EVAL_PATH)
    ix_data = load_json(NEPAL / "interactions.json")
    ix_by_id = {r["id"]: r for r in ix_data.get("interactions", [])}

    cond_results: list[dict] = []
    gold_results: list[dict] = []

    with ClinicalRepository() as repo:
        for cond in checklist["conditions"]:
            cond_results.append(eval_condition(repo, cond))
        for row in gold_rows:
            gold_results.append(eval_gold_row(repo, row, ix_by_id))

    total_w = sum(c.get("weight", 1) for c in checklist["conditions"])
    hit_w = sum(c.get("weight", 1) for c, r in zip(checklist["conditions"], cond_results) if r["retrieve_ok"])
    weighted_pct = 100.0 * hit_w / total_w if total_w else 0.0

    gold_ok = sum(1 for r in gold_results if r["ok"])
    gold_pct = 100.0 * gold_ok / len(gold_results) if gold_results else 0.0

    write_report(checklist, cond_results, gold_results, weighted_pct, gold_pct)

    print(f"opd_catalog={checklist['coverage_percent']}% opd_retrieval={weighted_pct:.1f}% gold={gold_pct:.1f}%")
    print(f"Report: {REPORT}")

    gate = checklist["coverage_percent"] >= OPD_TARGET and weighted_pct >= OPD_TARGET and gold_pct >= EVAL_TARGET
    if not gate:
        print("GATE FAIL: need OPD >=90% and gold >=85%")
        return 1
    print("GATE PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())

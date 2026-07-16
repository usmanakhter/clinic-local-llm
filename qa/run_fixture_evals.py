#!/usr/bin/env python3
"""
Nepal Clinical AI MVP — fixture integrity & scrubber baseline evals (QA A9).

Usage (from repo root):
    python qa/run_fixture_evals.py

Exit code:
    0  interaction catalog integrity OK (count, uniqueness, bidirectional severity)
    1  interaction catalog integrity failed

PII scrubber recall is reported but does not fail the process when <99%.
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "packages"))
from clinical_core_py.pii_scrubber import scrub_text  # noqa: E402

NEPAL = ROOT / "data" / "nepal"
ARTIFACTS = ROOT / "artifacts"
REPORT_PATH = ARTIFACTS / "qa_fixture_report.md"

ALLOWED_SEVERITIES = frozenset({"minor", "moderate", "major", "contraindicated"})



def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def load_jsonl(path: Path) -> list[dict]:
    rows: list[dict] = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def pair_key(drug_a: str, drug_b: str) -> tuple[str, str]:
    return tuple(sorted((drug_a, drug_b)))


def eval_interactions(data: dict) -> dict:
    interactions = data.get("interactions", [])
    declared = data.get("interaction_count")
    issues: list[str] = []

    if declared is not None and declared != len(interactions):
        issues.append(
            f"interaction_count={declared} but loaded {len(interactions)} rows"
        )

    if declared is None and len(interactions) < 1:
        issues.append("expected interactions, got 0")
    if declared is not None and len(interactions) != declared:
        pass  # already recorded above
    elif declared is None and len(interactions) != 35:
        # legacy default when manifest omits count
        issues.append(f"expected 35 interactions, got {len(interactions)}")

    ids = [row["id"] for row in interactions]
    if len(ids) != len(set(ids)):
        dupes = [i for i, c in Counter(ids).items() if c > 1]
        issues.append(f"duplicate interaction ids: {dupes}")

    # Canonical map: unordered pair -> severity (+ original ids for reporting)
    by_pair: dict[tuple[str, str], dict] = {}
    for row in interactions:
        sev = row.get("severity")
        if sev not in ALLOWED_SEVERITIES:
            issues.append(f"{row.get('id')}: invalid severity {sev!r}")
        key = pair_key(row["drug_a_id"], row["drug_b_id"])
        if key in by_pair:
            issues.append(
                f"duplicate drug pair {key}: {by_pair[key]['id']} vs {row['id']}"
            )
        by_pair[key] = row

    # Simulate bidirectional lookup: both a-b and b-a id order resolve
    forward_ok = 0
    reverse_ok = 0
    mismatch: list[str] = []
    for row in interactions:
        a, b, sev = row["drug_a_id"], row["drug_b_id"], row["severity"]
        # a → b
        hit_ab = by_pair.get(pair_key(a, b))
        if hit_ab and hit_ab["severity"] == sev:
            forward_ok += 1
        else:
            mismatch.append(f"{row['id']} a->b failed ({a},{b}) severity={sev}")
        # b → a (reversed presentation order)
        hit_ba = by_pair.get(pair_key(b, a))
        # Reverse order must resolve to the same severity via unordered key.
        # If another catalog row claims the same pair with a different id/severity,
        # reverse_ok fails for the losing row (integrity conflict).
        if hit_ba and hit_ba["severity"] == sev and hit_ba["id"] == row["id"]:
            reverse_ok += 1
        else:
            other = hit_ba["id"] if hit_ba else "none"
            mismatch.append(
                f"{row['id']} b->a failed ({b},{a}) severity={sev} "
                f"(canonical hit={other})"
            )

    if mismatch:
        issues.extend(mismatch)

    ok = len(issues) == 0 and forward_ok == len(interactions) and reverse_ok == len(
        interactions
    )
    severity_counts = Counter(r["severity"] for r in interactions)

    return {
        "ok": ok,
        "count": len(interactions),
        "declared_count": declared,
        "forward_ok": forward_ok,
        "reverse_ok": reverse_ok,
        "severity_counts": dict(severity_counts),
        "issues": issues,
    }


def token_removed(scrubbed: str, token: str) -> bool:
    """True if expected token no longer appears as a contiguous substring."""
    if not token:
        return True
    return token not in scrubbed


def eval_pii(data: dict) -> dict:
    cases = data.get("cases", [])
    total_expected = 0
    removed_hits = 0
    case_rows: list[dict] = []

    for case in cases:
        expected = case.get("expected_removed") or []
        scrubbed = scrub_text(case["input"])
        hits = 0
        misses: list[str] = []
        for tok in expected:
            total_expected += 1
            if token_removed(scrubbed, tok):
                hits += 1
                removed_hits += 1
            else:
                misses.append(tok)
        case_rows.append(
            {
                "id": case["id"],
                "expected_n": len(expected),
                "hits": hits,
                "misses": misses,
                "pass": len(misses) == 0,
            }
        )

    recall = (removed_hits / total_expected * 100.0) if total_expected else 100.0
    cases_pass = sum(1 for r in case_rows if r["pass"])
    return {
        "case_count": len(cases),
        "cases_pass": cases_pass,
        "tokens_expected": total_expected,
        "tokens_removed": removed_hits,
        "recall_pct": recall,
        "case_rows": case_rows,
    }


def eval_queries_summary(rows: list[dict]) -> dict:
    by_type = Counter(r.get("type", "unknown") for r in rows)
    by_locale = Counter(r.get("locale", "unknown") for r in rows)
    return {
        "total": len(rows),
        "by_type": dict(by_type),
        "by_locale": dict(by_locale),
    }


def write_report(
    interaction: dict,
    pii: dict,
    queries: dict | None,
) -> None:
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    lines: list[str] = [
        "# QA Fixture Report — Nepal Clinical AI MVP",
        "",
        f"- Generated: `{now}`",
        f"- Agent: A9",
        f"- Fixtures: `data/nepal/`",
        f"- Runner: `qa/run_fixture_evals.py`",
        "",
        "## Interaction catalog integrity",
        "",
        f"- Status: **{'PASS' if interaction['ok'] else 'FAIL'}**",
        f"- Loaded pairs: `{interaction['count']}` (declared `{interaction['declared_count']}`)",
        f"- Forward lookups OK: `{interaction['forward_ok']}/{interaction['count']}`",
        f"- Reverse (b→a) lookups OK: `{interaction['reverse_ok']}/{interaction['count']}`",
        f"- Severity distribution: `{interaction['severity_counts']}`",
        "",
    ]
    if interaction["issues"]:
        lines.append("### Issues")
        lines.append("")
        for issue in interaction["issues"][:50]:
            lines.append(f"- {issue}")
        if len(interaction["issues"]) > 50:
            lines.append(f"- ... and {len(interaction['issues']) - 50} more")
        lines.append("")
    else:
        lines.append(
            f"All {interaction['count']} pairs resolve with exact severity in both id orders."
        )
        lines.append("")

    lines.extend(
        [
            "## PII scrubber baseline (simple regex)",
            "",
            "> Exit code ignores scrubber score; production target remains >99% recall.",
            "",
            f"- Cases: `{pii['cases_pass']}/{pii['case_count']}` fully cleared",
            f"- Tokens: `{pii['tokens_removed']}/{pii['tokens_expected']}` removed",
            f"- **Recall: {pii['recall_pct']:.2f}%**",
            "",
            "### Misses by case (expected_removed still present)",
            "",
        ]
    )
    miss_cases = [r for r in pii["case_rows"] if r["misses"]]
    if not miss_cases:
        lines.append("_None — all expected_removed tokens scrubbed._")
        lines.append("")
    else:
        lines.append("| Case | Hits | Missed tokens |")
        lines.append("|---|---:|---|")
        for r in miss_cases:
            missed = ", ".join(f"`{m}`" for m in r["misses"])
            lines.append(        f"| `{r['id']}` | {r['hits']}/{r['expected_n']} | {missed} |"
            )
        lines.append("")

    if queries:
        lines.extend(
            [
                "## Eval queries inventory",
                "",
                f"- Total queries: `{queries['total']}`",
                f"- By type: `{queries['by_type']}`",
                f"- By locale: `{queries['by_locale']}`",
                "",
            ]
        )

    lines.extend(
        [
            "## Exit policy",
            "",
            "- Process exit **0** iff interaction catalog integrity PASS.",
            "- Scrubber recall is informational until NER/on-device scrub lands.",
            "",
        ]
    )
    REPORT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _safe_print(msg: str) -> None:
    """Avoid Windows cp1252 crashes on Unicode fixture text."""
    try:
        print(msg)
    except UnicodeEncodeError:
        encoding = getattr(sys.stdout, "encoding", None) or "utf-8"
        print(msg.encode(encoding, errors="replace").decode(encoding, errors="replace"))


def main() -> int:
    interactions_path = NEPAL / "interactions.json"
    pii_path = NEPAL / "pii_scrubber_test_cases.json"
    eval_path = NEPAL / "eval_queries.jsonl"

    if not interactions_path.is_file():
        print(f"ERROR: missing {interactions_path}", file=sys.stderr)
        return 1
    if not pii_path.is_file():
        print(f"ERROR: missing {pii_path}", file=sys.stderr)
        return 1

    interaction = eval_interactions(load_json(interactions_path))
    pii = eval_pii(load_json(pii_path))

    queries = None
    if eval_path.is_file():
        queries = eval_queries_summary(load_jsonl(eval_path))

    write_report(interaction, pii, queries)

    _safe_print("=== Interaction catalog ===")
    _safe_print(
        f"status={'PASS' if interaction['ok'] else 'FAIL'} "
        f"count={interaction['count']} "
        f"forward={interaction['forward_ok']}/{interaction['count']} "
        f"reverse={interaction['reverse_ok']}/{interaction['count']}"
    )
    if interaction["issues"]:
        for issue in interaction["issues"][:10]:
            _safe_print(f"  ! {issue}")
        if len(interaction["issues"]) > 10:
            _safe_print(f"  ! ... +{len(interaction['issues']) - 10} more")

    _safe_print("=== PII scrubber (regex baseline) ===")
    _safe_print(
        f"recall={pii['recall_pct']:.2f}% "
        f"tokens={pii['tokens_removed']}/{pii['tokens_expected']} "
        f"cases_pass={pii['cases_pass']}/{pii['case_count']}"
    )
    _safe_print("(scrubber score reported only -- does not fail exit)")

    if queries:
        _safe_print("=== Eval queries ===")
        _safe_print(f"total={queries['total']} by_type={queries['by_type']}")

    _safe_print(f"Report written: {REPORT_PATH}")

    return 0 if interaction["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())

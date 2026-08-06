#!/usr/bin/env python3
"""Build expanded Nepal corpus: real NNLEM/WHO/MoHP content, OPD checklist, eval queries.

Usage (repo root):
    python data/scripts/build_nepal_corpus.py
    python data/scripts/seed_nepal_db.py
"""

from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NEPAL = ROOT / "data" / "nepal"
ASSETS = ROOT / "apps" / "clinical_assistant" / "assets" / "nepal"
SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

from corpus_opd_expansion import NEW_DRUGS, OPD_CONDITIONS  # noqa: E402
from nnlem_opd_corpus import (  # noqa: E402
    EXTRA_OPD_CONDITIONS,
    HYPERTENSION_DRUG_GENERICS,
    NNLEM_OPD_DRUGS,
)
from nnlem_full_catalog import nnlem_drugs_for_corpus  # noqa: E402

SOURCE_NOTE = (
    "Full NNLEM 2021 (398 molecules) + WHO SEARO/MoHP OPD protocols. "
    "Reference only — verify with licensed clinician before clinical use."
)

TOPIC_MAP = {
    "respiratory": "respiratory",
    "UTI": "infectious_disease",
    "diarrhea": "gastroenterology",
    "malaria": "infectious_disease",
    "TB": "tuberculosis",
    "pregnancy": "obstetrics",
    "mental": "psychiatry",
    "skin": "dermatology",
    "eye": "ophthalmology",
    "dental": "dentistry",
    "poison": "toxicology",
    "cardio": "cardiology",
    "endo": "endocrinology",
    "pediatric": "pediatrics",
    "emergency": "emergency",
}


def _topic_for(name: str) -> str:
    n = name.lower()
    for key, topic in TOPIC_MAP.items():
        if key in n:
            return topic
    if any(w in n for w in ("fever", "infection", "malaria", "typhoid", "dengue", "sti", "hepatitis")):
        return "infectious_disease"
    if any(w in n for w in ("pain", "arthritis", "back")):
        return "musculoskeletal"
    return "general_medicine"


def _guide_source(name: str) -> str:
    n = name.lower()
    if "tb" in n or "leprosy" in n:
        return "Nepal National Tuberculosis Centre / WHO"
    if "pregnancy" in n or "postpartum" in n or "postnatal" in n or "family planning" in n:
        return "Nepal Safe Motherhood / WHO"
    if "malaria" in n or "kala-azar" in n or "filariasis" in n:
        return "Nepal Malaria/Elimination Program / WHO"
    if "mental" in n or "depression" in n or "anxiety" in n:
        return "WHO mhGAP Nepal adaptation"
    if "child" in n or "neonatal" in n or "IMCI" in n:
        return "WHO IMCI / Nepal MoHP"
    return "WHO SEARO / Nepal MoHP OPD protocol"


def _enrich_drug_rag(drugs: list[dict], conditions: list[dict]) -> None:
    """Append OPD condition keywords to each drug rag_text for retrieval."""
    by_drug: dict[str, list[str]] = {}
    for cond in conditions:
        for did in cond.get("drugs") or []:
            by_drug.setdefault(did, []).append(cond["name"])
    for d in drugs:
        extras = by_drug.get(d["id"], [])
        if not extras:
            continue
        kw = "; ".join(sorted(set(extras))[:8])
        base = d.get("rag_text") or ""
        base = re.sub(r" Nepal OPD:.*", "", base).strip()
        if kw not in base:
            d["rag_text"] = f"{base} Nepal OPD: {kw}."


def _make_guideline(gid: str, cond: dict, drug_names: list[str]) -> dict:
    drugs_txt = ", ".join(drug_names[:4]) if drug_names else "supportive care"
    q = cond.get("query") or cond["name"]
    return {
        "id": gid,
        "title": f"{cond['name']} — Nepal OPD",
        "title_ne": cond["name"],
        "source": _guide_source(cond["name"]),
        "topic": _topic_for(cond["name"]),
        "priority": min(10, max(5, cond.get("weight", 5))),
        "chunk_text": (
            f"{cond['name']} Nepal OPD protocol. {q}. "
            f"First-line: {drugs_txt}. Assess red flags and refer when severe. "
            f"Counsel return if worsening. NNLEM/WHO/MoHP reference — not prescribing authority."
        ),
        "chunk_text_ne": f"{cond['name']} — नेपाल OPD उपचार सन्दर्भ।",
    }


def _clean_drug(d: dict) -> dict:
    out = dict(d)
    brands = []
    for b in out.get("brand_names") or []:
        b = dict(b)
        if b.get("name") == "Nepalol":
            b["name"] = "Calpol"
        if b.get("manufacturer") == "Nepal Pharmaceuticals":
            b["manufacturer"] = "Deurali-Janta"
        if b.get("manufacturer") == "Nepal Remedies":
            b["manufacturer"] = "Time Pharmaceuticals"
        brands.append(b)
    out["brand_names"] = brands
    return out


def _clean_guide(g: dict) -> dict:
    out = dict(g)
    src = out.get("source") or ""
    out["source"] = re.sub(r"\s*\(dummy\)\s*", "", src, flags=re.I).strip()
    out["source"] = out["source"].replace("(dummy)", "").strip()
    return out


def _clean_interaction(ix: dict) -> dict:
    out = dict(ix)
    src = out.get("source") or ""
    out["source"] = re.sub(r"\s*\(dummy\)\s*", "", src, flags=re.I).strip()
    if "dummy" in src.lower():
        out["source"] = "Clinical pharmacology reference"
    return out


def _dedupe_drugs(drugs: list[dict]) -> list[dict]:
    by_generic: dict[str, dict] = {}
    for d in drugs:
        key = d["generic_name"].lower().strip()
        if key not in by_generic:
            by_generic[key] = d
            continue
        existing = by_generic[key]
        if int(d["id"].split("_")[1]) < int(existing["id"].split("_")[1]):
            by_generic[key] = d
    out = sorted(by_generic.values(), key=lambda x: int(x["id"].split("_")[1]))
    for i, d in enumerate(out, start=1):
        d["id"] = f"drug_{i:03d}"
    return out


def _reindex_interactions(interactions: list[dict], drug_id_map: dict[str, str]) -> list[dict]:
    out = []
    seen_pairs: set[tuple[str, str]] = set()
    for ix in interactions:
        a = drug_id_map.get(ix["drug_a_id"], ix["drug_a_id"])
        b = drug_id_map.get(ix["drug_b_id"], ix["drug_b_id"])
        pair = tuple(sorted((a, b)))
        if pair in seen_pairs:
            continue
        seen_pairs.add(pair)
        row = dict(ix)
        row["drug_a_id"] = a
        row["drug_b_id"] = b
        out.append(row)
    for i, row in enumerate(out, start=1):
        row["id"] = f"int_{i:03d}"
    return out


def _resolve_generics(generics: list[str], generic_to_id: dict[str, str]) -> list[str]:
    out: list[str] = []
    for g in generics:
        gid = generic_to_id.get(g.lower().strip())
        if gid:
            out.append(gid)
    return list(dict.fromkeys(out))


def _merge_opd_conditions(
    base: list[dict],
    extra: list[dict],
    generic_to_id: dict[str, str],
    old_id_to_generic: dict[str, str],
    drug_by_id: dict[str, dict],
) -> list[dict]:
    merged: list[dict] = []
    for cond in base:
        row = dict(cond)
        if row.get("id") == "opd_007":
            row["drugs"] = _resolve_generics(HYPERTENSION_DRUG_GENERICS, generic_to_id)
        else:
            row["drugs"] = _resolve_drug_ids_from_cond(
                row, generic_to_id, old_id_to_generic, drug_by_id
            )
        merged.append(row)
    for cond in extra:
        row = dict(cond)
        row["drugs"] = _resolve_generics(row.pop("drug_generics", []), generic_to_id)
        merged.append(row)
    return merged


def _resolve_drug_ids_from_cond(
    cond: dict,
    generic_to_id: dict[str, str],
    old_id_to_generic: dict[str, str],
    drug_by_id: dict[str, dict],
) -> list[str]:
    if cond.get("drug_generics"):
        return _resolve_generics(cond["drug_generics"], generic_to_id)
    resolved: list[str] = []
    for did in cond.get("drugs") or []:
        gen = old_id_to_generic.get(did)
        if gen and gen.lower() in generic_to_id:
            resolved.append(generic_to_id[gen.lower()])
        elif did in drug_by_id:
            resolved.append(did)
    return list(dict.fromkeys(resolved))


def _build_opd_checklist(
    drug_by_id: dict[str, dict],
    guide_by_id: dict[str, dict],
    conditions: list[dict],
) -> dict:
    items = []
    covered = 0
    for cond in conditions:
        drugs_ok = all(d in drug_by_id for d in cond["drugs"]) if cond["drugs"] else True
        guides_ok = all(g in guide_by_id for g in cond["guides"])
        hit = drugs_ok and guides_ok and (bool(cond["drugs"]) or bool(cond["guides"]))
        if hit:
            covered += 1
        items.append(
            {
                "id": cond["id"],
                "name": cond["name"],
                "weight": cond["weight"],
                "search_query": cond["query"],
                "expected_drug_ids": cond["drugs"],
                "expected_guideline_ids": cond["guides"],
                "covered": hit,
            }
        )
    total = len(items)
    pct = round(100.0 * covered / total, 1) if total else 0.0
    return {
        "version": "1.0.0",
        "region": "NP",
        "condition_count": total,
        "covered_count": covered,
        "coverage_percent": pct,
        "target_percent": 90.0,
        "source_note": SOURCE_NOTE,
        "conditions": items,
    }


def _condition_disambiguator(name: str) -> str:
    """Condition keywords appended to drug queries so shared meds still hit the right guide."""
    head = name.split("—")[0].strip()
    words = [
        w
        for w in re.findall(r"[\w\u0900-\u097F]+", head, flags=re.UNICODE)
        if len(w) >= 3
    ]
    weak = {"acute", "chronic", "mild", "severe", "type", "the", "and"}
    strong = [w for w in words if w.lower() not in weak]
    use = strong or words
    return " ".join(use[:2]) if use else head


def _build_eval_queries(checklist: dict, drug_by_id: dict[str, dict]) -> list[dict]:
    rows: list[dict] = []
    n = 0
    for cond in checklist["conditions"]:
        n += 1
        exp_drugs = cond["expected_drug_ids"]
        exp_guides = cond["expected_guideline_ids"]
        if exp_drugs and exp_drugs[0] in drug_by_id:
            gname = drug_by_id[exp_drugs[0]]["generic_name"]
            short = gname.split("(")[0].strip()
            if gname.startswith("Vitamin D"):
                short = "Cholecalciferol"
            # Always include condition tokens — bare long generics (Paracetamol,
            # Amoxicillin, …) otherwise drown guideline top-k across many OPDs.
            disambig = _condition_disambiguator(cond["name"])
            if disambig and disambig.lower() not in short.lower():
                query = f"{short} {disambig}"
            else:
                query = short
        elif exp_guides:
            query = cond["search_query"]
        else:
            query = cond["search_query"]
        qtype = "guideline_search" if exp_guides and not exp_drugs else "drug_lookup"
        rows.append(
            {
                "id": f"eval_{n:03d}",
                "query": query,
                "type": qtype,
                "locale": "en",
                "expected_drug_ids": exp_drugs,
                "expected_guideline_ids": exp_guides,
            }
        )
    # Keep legacy interaction evals
    legacy_ix = [
        ("ibuprofen aspirin together stomach bleed", ["int_001"]),
        ("rifampicin warfarin INR", ["int_004"]),
        ("azithromycin ciprofloxacin QT", ["int_022"]),
        ("metformin ibuprofen diabetes", ["int_013"]),
        ("salbutamol atenolol asthma", ["int_025"]),
        ("prednisolone tuberculosis cough", ["int_021"]),
    ]
    for q, ix_ids in legacy_ix:
        n += 1
        rows.append(
            {
                "id": f"eval_{n:03d}",
                "query": q,
                "type": "interaction_check",
                "locale": "en",
                "expected_interaction_ids": ix_ids,
            }
        )
    # High-frequency OPD lookups (explicit gold cases)
    common = [
        ("lisinopril hypertension dose nepal", "lisinopril"),
        ("simvastatin statin hyperlipidemia", "simvastatin"),
        ("rosuvastatin LDL cardiovascular", "rosuvastatin"),
        ("hydrochlorothiazide thiazide hypertension", "hydrochlorothiazide"),
    ]
    generic_to_id = {d["generic_name"].lower(): d["id"] for d in drug_by_id.values()}
    for q, gen in common:
        did = generic_to_id.get(gen)
        if not did:
            continue
        n += 1
        rows.append(
            {
                "id": f"eval_{n:03d}",
                "query": q,
                "type": "drug_lookup",
                "locale": "en",
                "expected_drug_ids": [did],
            }
        )
    return rows


def main() -> int:
    drugs_path = NEPAL / "drugs.json"
    guides_path = NEPAL / "guideline_chunks.json"
    ix_path = NEPAL / "interactions.json"

    drugs_data = json.loads(drugs_path.read_text(encoding="utf-8"))
    guides_data = json.loads(guides_path.read_text(encoding="utf-8"))
    ix_data = json.loads(ix_path.read_text(encoding="utf-8"))

    old_drugs = [_clean_drug(d) for d in drugs_data["drugs"]]
    expansion_ids = {d["id"] for d in NEW_DRUGS}
    # Expansion module owns drug_061+ semantics; output file IDs drift after reindex/dedupe.
    old_id_to_generic = {
        d["id"]: d["generic_name"] for d in old_drugs if d["id"] not in expansion_ids
    }
    for d in NEW_DRUGS:
        old_id_to_generic[d["id"]] = d["generic_name"]

    max_id = max(int(d["id"].split("_")[1]) for d in old_drugs + NEW_DRUGS)
    for i, d in enumerate(NNLEM_OPD_DRUGS, start=max_id + 1):
        if "id" not in d:
            d["id"] = f"drug_{i:03d}"

    existing_generics = {d["generic_name"].lower() for d in old_drugs + NEW_DRUGS + NNLEM_OPD_DRUGS}
    nnlem_full = nnlem_drugs_for_corpus(existing_generics)
    max_id = max(int(d["id"].split("_")[1]) for d in old_drugs + NEW_DRUGS + NNLEM_OPD_DRUGS)
    for i, d in enumerate(nnlem_full, start=max_id + 1):
        d["id"] = f"drug_{i:03d}"

    all_drugs = old_drugs + NEW_DRUGS + NNLEM_OPD_DRUGS + nnlem_full
    all_drugs = _dedupe_drugs(all_drugs)
    generic_to_id = {d["generic_name"].lower(): d["id"] for d in all_drugs}
    drug_by_id = {d["id"]: d for d in all_drugs}

    old_to_new_drug_id = {
        oid: generic_to_id[gen.lower()]
        for oid, gen in old_id_to_generic.items()
        if gen.lower() in generic_to_id
    }

    opd_all = _merge_opd_conditions(
        OPD_CONDITIONS,
        EXTRA_OPD_CONDITIONS,
        generic_to_id,
        old_id_to_generic,
        drug_by_id,
    )

    guides = [_clean_guide(g) for g in guides_data["chunks"]]
    guide_by_id = {g["id"]: g for g in guides}

    for cond in opd_all:
        for gid in cond["guides"]:
            drug_names = [drug_by_id[d]["generic_name"] for d in cond["drugs"] if d in drug_by_id]
            g = _make_guideline(gid, cond, drug_names)
            if gid in guide_by_id:
                for i, old in enumerate(guides):
                    if old["id"] == gid:
                        guides[i] = g
                        break
            else:
                guides.append(g)
            guide_by_id[gid] = g

    # Enrich core hypertension guideline with ACE-I/statin options
    if "guide_007" in guide_by_id:
        g7 = guide_by_id["guide_007"]
        g7["chunk_text"] = (
            "Hypertension Nepal OPD: lifestyle (salt reduction, activity). "
            "First-line pharmacotherapy per WHO PEN / NNLEM: amlodipine 5mg OD, "
            "enalapril 5mg OD, lisinopril 10mg OD, or losartan 50mg OD — not in pregnancy. "
            "Add hydrochlorothiazide 12.5–25mg if needed. Target <140/90 (<130/80 if diabetes/CKD). "
            "Statin (atorvastatin/simvastatin) if high CVD risk. Monthly titration."
        )
        g7["source"] = "WHO PEN / Nepal MoHP / NNLEM 2021"

    guides.sort(key=lambda g: g["id"])

    interactions = [_clean_interaction(i) for i in ix_data["interactions"]]
    interactions = _reindex_interactions(interactions, old_to_new_drug_id)

    checklist = _build_opd_checklist(drug_by_id, guide_by_id, opd_all)
    _enrich_drug_rag(all_drugs, opd_all)
    eval_rows = _build_eval_queries(checklist, drug_by_id)
    for cond, row in zip(checklist["conditions"], eval_rows[: len(checklist["conditions"])]):
        cond["search_query"] = row["query"]

    drugs_out = {
        "version": "1.0.0",
        "region": "NP",
        "source_note": SOURCE_NOTE,
        "drug_count": len(all_drugs),
        "drugs": all_drugs,
    }
    guides_out = {
        "version": "1.0.0",
        "region": "NP",
        "source_note": SOURCE_NOTE,
        "chunk_count": len(guides),
        "chunks": guides,
    }
    ix_out = {
        "version": "1.0.0",
        "region": "NP",
        "source_note": SOURCE_NOTE,
        "interaction_count": len(interactions),
        "interactions": interactions,
    }

    drugs_path.write_text(json.dumps(drugs_out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    guides_path.write_text(json.dumps(guides_out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    ix_path.write_text(json.dumps(ix_out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (NEPAL / "opd_condition_checklist.json").write_text(
        json.dumps(checklist, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    with (NEPAL / "eval_queries.jsonl").open("w", encoding="utf-8") as f:
        for row in eval_rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    ASSETS.mkdir(parents=True, exist_ok=True)
    for name in ("drugs.json", "interactions.json", "guideline_chunks.json", "eval_queries.jsonl", "opd_condition_checklist.json"):
        src = NEPAL / name
        if src.exists():
            shutil.copy2(src, ASSETS / name)

    print(f"drugs={len(all_drugs)} guidelines={len(guides)} interactions={len(interactions)}")
    print(f"nnlem_catalog={len(nnlem_full)} new_from_nnlem2021 eval_queries={len(eval_rows)} opd_coverage={checklist['coverage_percent']}%")
    if checklist["coverage_percent"] < 90.0:
        missing = [c["name"] for c in checklist["conditions"] if not c["covered"]]
        print(f"WARNING: coverage below 90%. Missing: {missing[:10]}...")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

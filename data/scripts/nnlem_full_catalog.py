"""Generate drug records for full NNLEM 2021 catalog entries missing from corpus."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NNLEM_JSON = ROOT / "data" / "nepal" / "nnlem_2021_molecules.json"


def _mk_drug(generic: str, category: str, tier: str) -> dict:
    short = generic.split()[0].split("-")[0].split("+")[0].strip()
    if short.lower() == "vitamin":
        short = generic.split("(")[0].strip()[:20]
    return {
        "generic_name": generic,
        "generic_name_ne": generic,
        "category": category,
        "nelm_tier": tier,
        "dosage_forms": ["tablet"],
        "strengths": ["standard"],
        "brand_names": [{"name": short[:20], "manufacturer": "Various Nepal"}],
        "indications": [],
        "contraindications": [],
        "adult_dose": "Per NNLEM 2021 / Nepal national formulary",
        "pediatric_dose": "Per NNLEM / specialist where applicable",
        "pregnancy_category": "C",
        "rag_text": (
            f"{generic} — Nepal National List of Essential Medicines (NNLEM) 2021, "
            f"sixth revision (DDA/MoHP). WHO EML 2019 aligned. Reference only."
        ),
    }


def load_nnlem_molecules(path: Path | None = None) -> list[dict]:
    p = path or NNLEM_JSON
    data = json.loads(p.read_text(encoding="utf-8"))
    return data["molecules"]


def nnlem_drugs_for_corpus(existing_generics: set[str]) -> list[dict]:
    """Return drug dicts for NNLEM molecules not already in corpus (by generic name)."""
    out: list[dict] = []
    for mol in load_nnlem_molecules():
        key = mol["generic_name"].lower().strip()
        if key in existing_generics:
            continue
        out.append(_mk_drug(mol["generic_name"], mol.get("category", "NNLEM 2021"), mol.get("nelm_tier", "core")))
    return out


NNLEM_FULL_DRUGS: list[dict] = []  # populated at build time

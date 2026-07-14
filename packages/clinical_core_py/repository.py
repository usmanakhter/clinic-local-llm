"""SQLite repository for Nepal MVP clinical reference data."""

from __future__ import annotations

import json
import sqlite3
import subprocess
import sys
from pathlib import Path
from typing import Any

from .models import BrandName, Drug, GuidelineChunk, Interaction

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = REPO_ROOT / "data" / "nepal_mvp_dev.db"
SEED_SCRIPT = REPO_ROOT / "data" / "scripts" / "seed_nepal_db.py"


def ensure_db(db_path: Path = DEFAULT_DB) -> Path:
    """Return path to seeded DB; run seed script if the file is missing."""
    if not db_path.exists():
        if not SEED_SCRIPT.exists():
            raise FileNotFoundError(
                f"Missing DB at {db_path} and seed script at {SEED_SCRIPT}"
            )
        subprocess.run(
            [sys.executable, str(SEED_SCRIPT), str(db_path)],
            check=True,
            cwd=str(REPO_ROOT),
        )
    if not db_path.exists():
        raise FileNotFoundError(f"Seed finished but DB still missing: {db_path}")
    return db_path


def _parse_json_list(raw: str | None) -> list[Any]:
    if not raw:
        return []
    data = json.loads(raw)
    return data if isinstance(data, list) else []


def row_to_drug(row: sqlite3.Row) -> Drug:
    brands_raw = _parse_json_list(row["brand_names"])
    brands = [
        BrandName.from_dict(b) if isinstance(b, dict) else BrandName(name=str(b))
        for b in brands_raw
    ]
    return Drug(
        id=row["id"],
        generic_name=row["generic_name"],
        generic_name_ne=row["generic_name_ne"],
        category=row["category"],
        nelm_tier=row["nelm_tier"],
        dosage_forms=[str(x) for x in _parse_json_list(row["dosage_forms"])],
        strengths=[str(x) for x in _parse_json_list(row["strengths"])],
        brand_names=brands,
        indications=[str(x) for x in _parse_json_list(row["indications"])],
        contraindications=[str(x) for x in _parse_json_list(row["contraindications"])],
        adult_dose=row["adult_dose"],
        pediatric_dose=row["pediatric_dose"],
        pregnancy_category=row["pregnancy_category"],
        rag_text=row["rag_text"],
        updated_at=row["updated_at"] if "updated_at" in row.keys() else None,
    )


def row_to_interaction(row: sqlite3.Row) -> Interaction:
    return Interaction(
        id=row["id"],
        drug_a_id=row["drug_a_id"],
        drug_b_id=row["drug_b_id"],
        severity=row["severity"],
        mechanism=row["mechanism"],
        clinical_effect=row["clinical_effect"],
        recommendation=row["recommendation"],
        source=row["source"],
    )


def row_to_guideline(row: sqlite3.Row) -> GuidelineChunk:
    return GuidelineChunk(
        id=row["id"],
        title=row["title"],
        title_ne=row["title_ne"],
        source=row["source"],
        topic=row["topic"],
        chunk_text=row["chunk_text"],
        chunk_text_ne=row["chunk_text_ne"],
        priority=int(row["priority"] or 0),
    )


class ClinicalRepository:
    """Thin SQLite access layer. Flutter team: mirror as a DAO over sqlcipher/sqflite."""

    def __init__(self, db_path: Path | str | None = None) -> None:
        path = ensure_db(Path(db_path) if db_path else DEFAULT_DB)
        self.db_path = path
        self._conn = sqlite3.connect(str(path))
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA foreign_keys = ON")

    def close(self) -> None:
        self._conn.close()

    def __enter__(self) -> ClinicalRepository:
        return self

    def __exit__(self, *args: object) -> None:
        self.close()

    @property
    def connection(self) -> sqlite3.Connection:
        return self._conn

    def fts_available(self) -> bool:
        try:
            n = self._conn.execute("SELECT COUNT(*) AS n FROM drugs_fts").fetchone()["n"]
            return int(n) > 0
        except sqlite3.Error:
            return False

    def get_drug(self, drug_id: str) -> Drug | None:
        row = self._conn.execute(
            "SELECT * FROM drugs WHERE id = ?", (drug_id,)
        ).fetchone()
        return row_to_drug(row) if row else None

    def get_drugs_by_ids(self, ids: list[str]) -> dict[str, Drug]:
        if not ids:
            return {}
        placeholders = ",".join("?" * len(ids))
        rows = self._conn.execute(
            f"SELECT * FROM drugs WHERE id IN ({placeholders})", ids
        ).fetchall()
        return {r["id"]: row_to_drug(r) for r in rows}

    def fetch_interaction_pair(
        self, drug_a_id: str, drug_b_id: str
    ) -> Interaction | None:
        """Exact ordering only. Prefer interactions.lookup for bidirectional check."""
        row = self._conn.execute(
            """
            SELECT * FROM interactions
            WHERE drug_a_id = ? AND drug_b_id = ?
            LIMIT 1
            """,
            (drug_a_id, drug_b_id),
        ).fetchone()
        return row_to_interaction(row) if row else None

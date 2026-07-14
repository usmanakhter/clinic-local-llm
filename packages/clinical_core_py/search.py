"""Drug search: FTS5 when available, LIKE fallback otherwise. Ranked results."""

from __future__ import annotations

import re
from typing import Iterable

from .models import Drug, RankedDrug
from .repository import ClinicalRepository, row_to_drug


def _normalize(q: str) -> str:
    return " ".join(q.strip().lower().split())


def _brand_haystack(drug: Drug) -> str:
    return " ".join(b.name for b in drug.brand_names).lower()


def _score_drug(drug: Drug, query: str) -> tuple[float, str]:
    """Heuristic rank so Flutter can mirror without depending on SQLite bm25."""
    q = _normalize(query)
    if not q:
        return 0.0, "empty"

    gn = (drug.generic_name or "").lower()
    gn_ne = (drug.generic_name_ne or "").lower()
    brands = _brand_haystack(drug)

    if gn == q:
        return 100.0, "exact_generic"
    if any(b.name.lower() == q for b in drug.brand_names):
        return 95.0, "exact_brand"
    if gn_ne == q:
        return 92.0, "exact_generic_ne"
    if gn.startswith(q):
        return 85.0, "prefix_generic"
    if any(b.name.lower().startswith(q) for b in drug.brand_names):
        return 80.0, "prefix_brand"
    if q in gn:
        return 70.0, "contains_generic"
    if q in brands:
        return 65.0, "contains_brand"
    if q in gn_ne:
        return 60.0, "contains_generic_ne"
    rag = (drug.rag_text or "").lower()
    if q in rag:
        return 40.0, "contains_rag"
    return 10.0, "weak"


def _fts_match_query(query: str) -> str:
    """Build a conservative FTS5 MATCH string from user text."""
    tokens = re.findall(r"[\w\u0900-\u097F]+", query, flags=re.UNICODE)
    if not tokens:
        return query.strip()
    # Prefix each token for brand/partial typing; quote to reduce syntax surprises.
    parts = [f'"{t}"*' if t.isascii() else f'"{t}"' for t in tokens]
    return " OR ".join(parts)


def _search_fts(repo: ClinicalRepository, query: str, limit: int) -> list[Drug]:
    match = _fts_match_query(query)
    rows = repo.connection.execute(
        """
        SELECT drugs.*
        FROM drugs_fts
        JOIN drugs ON drugs.rowid = drugs_fts.rowid
        WHERE drugs_fts MATCH ?
        LIMIT ?
        """,
        (match, limit * 3),
    ).fetchall()
    return [row_to_drug(r) for r in rows]


def _search_like(repo: ClinicalRepository, query: str, limit: int) -> list[Drug]:
    pattern = f"%{query.strip()}%"
    rows = repo.connection.execute(
        """
        SELECT * FROM drugs
        WHERE generic_name LIKE ? COLLATE NOCASE
           OR generic_name_ne LIKE ?
           OR brand_names LIKE ?
        LIMIT ?
        """,
        (pattern, pattern, pattern, limit * 3),
    ).fetchall()
    return [row_to_drug(r) for r in rows]


def _dedupe_rank(drugs: Iterable[Drug], query: str, limit: int) -> list[RankedDrug]:
    seen: set[str] = set()
    ranked: list[RankedDrug] = []
    for drug in drugs:
        if drug.id in seen:
            continue
        seen.add(drug.id)
        score, reason = _score_drug(drug, query)
        if score <= 0:
            continue
        ranked.append(RankedDrug(drug=drug, score=score, match_reason=reason))
    ranked.sort(key=lambda r: (-r.score, r.drug.generic_name.lower()))
    return ranked[:limit]


def search_drugs(
    repo: ClinicalRepository,
    query: str,
    *,
    limit: int = 20,
) -> list[RankedDrug]:
    """
    Search by generic_name, generic_name_ne, and brand_names JSON text.

    Prefer FTS5; fall back to LIKE if FTS is empty or MATCH errors.
    Results are re-ranked with a portable heuristic (mirrorable in Dart).
    """
    q = query.strip()
    if not q:
        return []

    candidates: list[Drug] = []
    if repo.fts_available():
        try:
            candidates = _search_fts(repo, q, limit)
        except Exception:
            candidates = []

    if not candidates:
        candidates = _search_like(repo, q, limit)

    return _dedupe_rank(candidates, q, limit)

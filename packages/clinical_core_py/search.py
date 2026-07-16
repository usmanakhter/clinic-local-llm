"""Drug search: FTS5 when available, LIKE fallback otherwise. Ranked results."""

from __future__ import annotations

import re
from typing import Iterable

from .models import Drug, RankedDrug
from .repository import ClinicalRepository, row_to_drug

_STOP = frozenset(
    {
        "a",
        "an",
        "the",
        "and",
        "or",
        "of",
        "for",
        "to",
        "in",
        "on",
        "with",
        "no",
        "not",
        "dose",
        "child",
        "years",
        "year",
        "safe",
        "problem",
        "together",
        "should",
        "give",
        "first",
        "aid",
        "cheap",
        "start",
        "rural",
        "nepal",
        "medicine",
    }
)


def _normalize(q: str) -> str:
    return " ".join(q.strip().lower().split())


def _tokens(query: str) -> list[str]:
    raw = re.findall(r"[\w\u0900-\u097F]+", query, flags=re.UNICODE)
    out: list[str] = []
    for t in raw:
        tl = t.lower()
        if len(tl) < 2:
            continue
        if tl in _STOP:
            continue
        out.append(t)
    return out or raw or [query.strip()]


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
    rag = (drug.rag_text or "").lower()
    indications = " ".join(drug.indications or []).lower()

    def score_one(term: str) -> tuple[float, str]:
        if gn == term:
            return 100.0, "exact_generic"
        if any(b.name.lower() == term for b in drug.brand_names):
            return 95.0, "exact_brand"
        if gn_ne == term:
            return 92.0, "exact_generic_ne"
        if gn.startswith(term):
            return 85.0, "prefix_generic"
        if any(b.name.lower().startswith(term) for b in drug.brand_names):
            return 80.0, "prefix_brand"
        if term in gn:
            return 70.0, "contains_generic"
        if term in brands:
            return 65.0, "contains_brand"
        if term in gn_ne:
            return 60.0, "contains_generic_ne"
        if term in rag or term in indications:
            return 40.0, "contains_rag"
        return 0.0, "none"

    best_score, best_reason = score_one(q)
    for tok in _tokens(query):
        s, r = score_one(tok.lower())
        if s > best_score:
            best_score, best_reason = s, f"token:{r}"
    if best_score <= 0:
        return 10.0, "weak"
    return best_score, best_reason


def _fts_match_query(query: str) -> str:
    """Build a conservative FTS5 MATCH string from user text."""
    tokens = _tokens(query)
    if not tokens:
        return query.strip()
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
        (match, limit * 5),
    ).fetchall()
    return [row_to_drug(r) for r in rows]


def _search_like(repo: ClinicalRepository, query: str, limit: int) -> list[Drug]:
    tokens = _tokens(query)
    seen: dict[str, Drug] = {}
    for tok in tokens:
        pattern = f"%{tok}%"
        rows = repo.connection.execute(
            """
            SELECT * FROM drugs
            WHERE generic_name LIKE ? COLLATE NOCASE
               OR generic_name_ne LIKE ?
               OR brand_names LIKE ?
               OR rag_text LIKE ? COLLATE NOCASE
               OR indications LIKE ?
            LIMIT ?
            """,
            (pattern, pattern, pattern, pattern, pattern, limit * 3),
        ).fetchall()
        for r in rows:
            d = row_to_drug(r)
            seen[d.id] = d
    return list(seen.values())[: limit * 5]


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

    like_hits = _search_like(repo, q, limit)
    by_id = {d.id: d for d in candidates}
    for d in like_hits:
        by_id[d.id] = d

    return _dedupe_rank(by_id.values(), q, limit)

"""Guideline search: FTS5 when available + multi-token LIKE hybrid."""

from __future__ import annotations

import re

from .models import GuidelineChunk, RankedGuideline
from .repository import ClinicalRepository, row_to_guideline

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
        "first",
        "aid",
        "fever",
        "medicine",
        "avoid",
        "should",
        "give",
        "cold",
        "flu",
        "nepal",
        "opd",
        "protocol",
        "treatment",
    }
)


def _tokens(query: str) -> list[str]:
    raw = re.findall(r"[\w\u0900-\u097F]+", query, flags=re.UNICODE)
    out: list[str] = []
    for t in raw:
        tl = t.lower()
        if len(tl) < 2 or tl in _STOP:
            continue
        out.append(t)
    return out or raw or [query.strip()]


def _fts_match_query(query: str) -> str:
    tokens = _tokens(query)
    if not tokens:
        return query.strip()
    parts = [f'"{t}"*' if t.isascii() else f'"{t}"' for t in tokens]
    return " OR ".join(parts)


def _score_chunk(chunk: GuidelineChunk, query: str) -> tuple[float, str]:
    q = query.strip().lower()
    if not q:
        return 0.0, "empty"

    title = (chunk.title or "").lower()
    title_ne = (chunk.title_ne or "").lower()
    topic = (chunk.topic or "").lower()
    body = (chunk.chunk_text or "").lower()
    body_ne = (chunk.chunk_text_ne or "").lower()
    source = (chunk.source or "").lower()
    p = float(chunk.priority)

    def score_one(term: str) -> tuple[float, str]:
        if title == term or topic == term:
            return 100.0 + p, "exact_title_or_topic"
        if term in title:
            return 80.0 + p, "title"
        if term in topic:
            return 70.0 + p, "topic"
        if term in title_ne:
            return 65.0 + p, "title_ne"
        if term in body:
            return 50.0 + p, "chunk_text"
        if term in body_ne:
            return 45.0 + p, "chunk_text_ne"
        if term in source:
            return 30.0 + p, "source"
        return 0.0, "none"

    best_s, best_r = score_one(q)
    bonus = 0.0
    for tok in _tokens(query):
        s, r = score_one(tok.lower())
        if s > best_s:
            best_s, best_r = s, f"token:{r}"
        elif s > 0:
            bonus += 5.0
    if best_s <= 0:
        return 0.0, "none"
    return best_s + min(bonus, 20.0), best_r


def _search_fts(repo: ClinicalRepository, query: str, limit: int) -> list[GuidelineChunk]:
    match = _fts_match_query(query)
    rows = repo.connection.execute(
        """
        SELECT guideline_chunks.*
        FROM guidelines_fts
        JOIN guideline_chunks ON guideline_chunks.rowid = guidelines_fts.rowid
        WHERE guidelines_fts MATCH ?
        LIMIT ?
        """,
        (match, limit * 5),
    ).fetchall()
    return [row_to_guideline(r) for r in rows]


def _search_like(repo: ClinicalRepository, query: str, limit: int) -> list[GuidelineChunk]:
    tokens = _tokens(query)
    seen: dict[str, GuidelineChunk] = {}
    for tok in tokens:
        pattern = f"%{tok}%"
        rows = repo.connection.execute(
            """
            SELECT * FROM guideline_chunks
            WHERE title LIKE ? COLLATE NOCASE
               OR title_ne LIKE ?
               OR topic LIKE ? COLLATE NOCASE
               OR chunk_text LIKE ? COLLATE NOCASE
               OR chunk_text_ne LIKE ?
               OR source LIKE ? COLLATE NOCASE
            ORDER BY priority DESC
            LIMIT ?
            """,
            (pattern, pattern, pattern, pattern, pattern, pattern, limit * 3),
        ).fetchall()
        for r in rows:
            chunk = row_to_guideline(r)
            seen[chunk.id] = chunk
    return list(seen.values())


def search_guidelines(
    repo: ClinicalRepository,
    query: str,
    *,
    limit: int = 20,
) -> list[RankedGuideline]:
    """Hybrid FTS + LIKE guideline search with heuristic re-rank."""
    q = query.strip()
    if not q:
        return []

    candidates: dict[str, GuidelineChunk] = {}
    if repo.guidelines_fts_available():
        try:
            for c in _search_fts(repo, q, limit):
                candidates[c.id] = c
        except Exception:
            pass
    for c in _search_like(repo, q, limit):
        candidates[c.id] = c

    ranked: list[RankedGuideline] = []
    for chunk in candidates.values():
        score, reason = _score_chunk(chunk, q)
        if score <= 0:
            continue
        ranked.append(
            RankedGuideline(chunk=chunk, score=score, match_reason=reason)
        )
    ranked.sort(key=lambda r: (-r.score, r.chunk.title.lower()))
    return ranked[:limit]

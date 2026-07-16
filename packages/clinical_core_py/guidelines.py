"""Guideline search: multi-token LIKE + ranking (FTS optional later in app)."""

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


def search_guidelines(
    repo: ClinicalRepository,
    query: str,
    *,
    limit: int = 20,
) -> list[RankedGuideline]:
    """Multi-token keyword search; ranked by portable heuristic + priority."""
    q = query.strip()
    if not q:
        return []

    tokens = _tokens(q)
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

    ranked: list[RankedGuideline] = []
    for chunk in seen.values():
        score, reason = _score_chunk(chunk, q)
        if score <= 0:
            continue
        ranked.append(
            RankedGuideline(chunk=chunk, score=score, match_reason=reason)
        )
    ranked.sort(key=lambda r: (-r.score, r.chunk.title.lower()))
    return ranked[:limit]

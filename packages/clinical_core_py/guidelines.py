"""Simple keyword search over guideline_chunks."""

from __future__ import annotations

from .models import GuidelineChunk, RankedGuideline
from .repository import ClinicalRepository, row_to_guideline


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

    if title == q or topic == q:
        return 100.0 + chunk.priority, "exact_title_or_topic"
    if q in title:
        return 80.0 + chunk.priority, "title"
    if q in topic:
        return 70.0 + chunk.priority, "topic"
    if q in title_ne:
        return 65.0 + chunk.priority, "title_ne"
    if q in body:
        return 50.0 + chunk.priority, "chunk_text"
    if q in body_ne:
        return 45.0 + chunk.priority, "chunk_text_ne"
    if q in source:
        return 30.0 + chunk.priority, "source"
    return 0.0, "none"


def search_guidelines(
    repo: ClinicalRepository,
    query: str,
    *,
    limit: int = 20,
) -> list[RankedGuideline]:
    """Keyword LIKE across English/Nepali title and chunk text; ranked + priority."""
    q = query.strip()
    if not q:
        return []

    pattern = f"%{q}%"
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

    ranked: list[RankedGuideline] = []
    for row in rows:
        chunk = row_to_guideline(row)
        score, reason = _score_chunk(chunk, q)
        if score <= 0:
            continue
        ranked.append(RankedGuideline(chunk=chunk, score=score, match_reason=reason))

    ranked.sort(key=lambda r: (-r.score, r.chunk.title.lower()))
    return ranked[:limit]

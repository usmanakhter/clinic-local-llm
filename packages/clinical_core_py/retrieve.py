"""Shared retrieve API — single entry for Interact / Guidelines / Chat / export.

Returns ranked drug + guideline hits for a free-text query. Never invents
interaction severity; callers that need pairs must use interactions.lookup.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field

from .guidelines import search_guidelines
from .models import Drug, GuidelineChunk
from .repository import ClinicalRepository
from .search import search_drugs


@dataclass
class RetrievedDrug:
    id: str
    generic_name: str
    score: float
    match_reason: str
    excerpt: str


@dataclass
class RetrievedGuideline:
    id: str
    title: str
    source: str
    topic: str | None
    score: float
    match_reason: str
    excerpt: str


@dataclass
class RetrieveResult:
    query: str
    drugs: list[RetrievedDrug] = field(default_factory=list)
    guidelines: list[RetrievedGuideline] = field(default_factory=list)
    refused: bool = False
    refuse_reason: str | None = None

    def to_dict(self) -> dict:
        return {
            "query": self.query,
            "drugs": [asdict(d) for d in self.drugs],
            "guidelines": [asdict(g) for g in self.guidelines],
            "refused": self.refused,
            "refuse_reason": self.refuse_reason,
        }


def _drug_excerpt(drug: Drug, max_len: int = 220) -> str:
    text = (drug.rag_text or drug.adult_dose or drug.generic_name or "").strip()
    return text if len(text) <= max_len else text[: max_len - 1] + "…"


def _guide_excerpt(chunk: GuidelineChunk, max_len: int = 280) -> str:
    text = (chunk.chunk_text or chunk.title or "").strip()
    return text if len(text) <= max_len else text[: max_len - 1] + "…"


def retrieve(
    repo: ClinicalRepository,
    query: str,
    *,
    drug_limit: int = 5,
    guideline_limit: int = 5,
) -> RetrieveResult:
    """Hybrid keyword retrieve over drugs + guidelines for Chat/RAG callers."""
    q = (query or "").strip()
    if not q:
        return RetrieveResult(
            query=q,
            refused=True,
            refuse_reason="Empty query",
        )

    drugs = [
        RetrievedDrug(
            id=r.drug.id,
            generic_name=r.drug.generic_name,
            score=r.score,
            match_reason=r.match_reason,
            excerpt=_drug_excerpt(r.drug),
        )
        for r in search_drugs(repo, q, limit=drug_limit)
    ]
    guidelines = [
        RetrievedGuideline(
            id=r.chunk.id,
            title=r.chunk.title,
            source=r.chunk.source,
            topic=r.chunk.topic,
            score=r.score,
            match_reason=r.match_reason,
            excerpt=_guide_excerpt(r.chunk),
        )
        for r in search_guidelines(repo, q, limit=guideline_limit)
    ]

    if not drugs and not guidelines:
        return RetrieveResult(
            query=q,
            refused=True,
            refuse_reason="No local drugs or guidelines matched — refuse to invent clinical content",
        )

    return RetrieveResult(query=q, drugs=drugs, guidelines=guidelines)


def format_context_block(result: RetrieveResult, *, max_chars: int = 3500) -> str:
    """Serialize retrieval hits for an LLM system/user context block."""
    if result.refused:
        return f"[RETRIEVAL REFUSED] {result.refuse_reason}"

    parts: list[str] = [f"Query: {result.query}", "", "### Drugs"]
    for d in result.drugs:
        parts.append(f"- [{d.id}] {d.generic_name} (score={d.score:.0f}): {d.excerpt}")
    parts.append("")
    parts.append("### Guidelines")
    for g in result.guidelines:
        topic = f" topic={g.topic}" if g.topic else ""
        parts.append(
            f"- [{g.id}] {g.title} ({g.source}{topic}; score={g.score:.0f}): {g.excerpt}"
        )
    parts.append("")
    parts.append(
        "Rules: Answer only from the snippets above. Cite ids. "
        "Do not invent drug-drug interaction severity."
    )
    text = "\n".join(parts)
    return text if len(text) <= max_chars else text[: max_chars - 1] + "…"

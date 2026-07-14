"""Domain models mirroring data/schema/mvp_schema.sql (fields the app cares about).

Portable reference for the Flutter/Dart mirror — keep field names aligned.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class BrandName:
    name: str
    manufacturer: str | None = None

    @classmethod
    def from_dict(cls, raw: dict[str, Any]) -> BrandName:
        return cls(name=raw["name"], manufacturer=raw.get("manufacturer"))


@dataclass(frozen=True)
class Drug:
    id: str
    generic_name: str
    generic_name_ne: str | None
    category: str | None
    nelm_tier: str | None  # core | complementary | supplementary
    dosage_forms: list[str]
    strengths: list[str]
    brand_names: list[BrandName]
    indications: list[str]
    contraindications: list[str]
    adult_dose: str | None
    pediatric_dose: str | None
    pregnancy_category: str | None
    rag_text: str
    updated_at: str | None = None


@dataclass(frozen=True)
class Interaction:
    """Drug-drug interaction. severity is always from the DB — never invented."""

    id: str
    drug_a_id: str
    drug_b_id: str
    severity: str  # contraindicated | major | moderate | minor
    mechanism: str | None
    clinical_effect: str | None
    recommendation: str
    source: str | None


@dataclass(frozen=True)
class GuidelineChunk:
    id: str
    title: str
    title_ne: str | None
    source: str
    topic: str | None
    chunk_text: str
    chunk_text_ne: str | None
    priority: int = 0


@dataclass(frozen=True)
class RankedDrug:
    drug: Drug
    score: float
    match_reason: str = ""


@dataclass(frozen=True)
class RankedGuideline:
    chunk: GuidelineChunk
    score: float
    match_reason: str = field(default="")

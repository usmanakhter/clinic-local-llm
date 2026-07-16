"""Portable Nepal clinical domain logic (Python reference for Flutter/Dart mirror)."""

from .guidelines import search_guidelines
from .interactions import lookup as lookup_interaction
from .models import Drug, GuidelineChunk, Interaction, RankedDrug, RankedGuideline
from .repository import ClinicalRepository, DEFAULT_DB, ensure_db
from .retrieve import RetrieveResult, format_context_block, retrieve
from .search import search_drugs

__all__ = [
    "ClinicalRepository",
    "DEFAULT_DB",
    "Drug",
    "GuidelineChunk",
    "Interaction",
    "RankedDrug",
    "RankedGuideline",
    "RetrieveResult",
    "ensure_db",
    "format_context_block",
    "lookup_interaction",
    "retrieve",
    "search_drugs",
    "search_guidelines",
]

__version__ = "0.1.0"

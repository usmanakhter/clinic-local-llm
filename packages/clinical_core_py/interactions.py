"""Drug-drug interaction lookup. Never invent severity — unknown pairs are None."""

from __future__ import annotations

from .models import Interaction
from .repository import ClinicalRepository


def lookup(
    repo: ClinicalRepository,
    drug_a_id: str,
    drug_b_id: str,
) -> Interaction | None:
    """
    Return the stored interaction for the pair, checking both orderings.

    Preference: exact (a, b) first, then (b, a). If neither exists, return None.
    Callers must treat None as "no curated row" — not as "safe".
    """
    if not drug_a_id or not drug_b_id:
        return None
    if drug_a_id == drug_b_id:
        return None

    exact = repo.fetch_interaction_pair(drug_a_id, drug_b_id)
    if exact is not None:
        return exact

    reverse = repo.fetch_interaction_pair(drug_b_id, drug_a_id)
    return reverse

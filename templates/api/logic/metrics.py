"""Every number this project would quote outward, derived rather than typed.

Fill in `_tally()` and `all_metrics()` for this project's corpus.

The problem this shape exists for. A corpus size is recorded, referenced, and
propagated into outward-facing documents. It is a true count of trace FILES --
some of which hold no model output at all -- and quoted without its definition
it becomes a count of graded runs instead. Nobody lies at any step.

A metric is a NAME, a value DERIVED on every run, and a DEFINITION saying in
words what is counted. The definition field is the one that prevents this:
a number with no stated definition can be quoted as anything close.
"""
from __future__ import annotations

from typing import Dict, List

from pydantic import BaseModel


class Metric(BaseModel):
    name: str
    value: int
    definition: str          # what is counted, in words. Never omit this.
    derived_from: str = ""   # which artefacts it was computed from


def all_metrics() -> List[Metric]:
    """Return every figure this project would quote. Derive each one here.

    Two rules learned the hard way:
      - Report attempts and results as SEPARATE metrics. Collapsing them is
        how a file count becomes a result count.
      - Count failures explicitly. Anything skipped silently by other code
        is invisible everywhere else, which is why it is counted here.
    """
    raise NotImplementedError("define this project's metrics")


def as_dict() -> Dict[str, Dict]:
    return {m.name: m.model_dump() for m in all_metrics()}


def get(name: str) -> Metric:
    for m in all_metrics():
        if m.name == name:
            return m
    known = ", ".join(m.name for m in all_metrics())
    raise KeyError(f"no metric named {name!r}. Known: {known}")

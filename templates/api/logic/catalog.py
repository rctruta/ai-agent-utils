"""What exists in this project's corpus. Interprets nothing.

Fill in for this project's artefacts: runs, captures, reports, whatever the
corpus is made of.

Reading and interpreting are kept apart on purpose. If the catalog scored
results as it read them, a change to how a result is scored would silently
change which results are found, and the two failures would be impossible to
tell apart.

Paths come from a constants module or an environment variable, never a
literal -- a hardcoded path makes the whole layer unusable against an
archived copy of the corpus.
"""
from __future__ import annotations

from typing import Dict, List

from pydantic import BaseModel, Field


class Item(BaseModel):
    """One artefact. `raw` keeps the whole document so an operation can reach
    a field this model does not name, without re-reading the file."""
    path: str
    raw: Dict = Field(default_factory=dict, repr=False)


def corpus_dir() -> str:
    raise NotImplementedError("read this from constants or the environment")


def item_names() -> List[str]:
    raise NotImplementedError("list the corpus")


def load(name: str) -> Item:
    raise NotImplementedError("read one artefact")


def summary() -> List[Dict]:
    """One row per item: enough to choose what to look at, nothing more."""
    raise NotImplementedError

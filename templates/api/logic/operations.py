"""The questions actually asked of this corpus, written once.

Name the four or five questions someone has already asked TWICE. Not the
questions that might be asked -- speculative operations are the stub that
stays empty and gets deleted.

For a corpus of study traces, the four were:

    by_model     what each participant did on one study
    divergence   where repeats of the same cell disagree
    compare      what changed between two runs
    failures     what failed, and why

Each returns a plain dict. One implementation then serves a CLI, a notebook
and later an MCP tool, without the logic migrating into whichever called it
first.

Do NOT re-implement scoring here. Whatever module owns what a result MEANS
should be imported and called. Two definitions of the same verdict is the
real failure; duplicated code is only the symptom.
"""
from __future__ import annotations

from typing import Dict, Optional

from . import catalog                                    # noqa: F401


def failures(name: Optional[str] = None) -> Dict:
    """What failed, and why.

    Start with this one. It is the question whose answer every other
    operation depends on: an artefact that records an error has nothing for
    the other operations to measure, and if that is not surfaced they report
    a confident result over missing data.
    """
    raise NotImplementedError

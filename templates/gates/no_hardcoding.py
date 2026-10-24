#!/usr/bin/env python3
"""no_hardcoding — refuse code that repeats a value its data file already holds.

  .gates/no_hardcoding.py              report
  .gates/no_hardcoding.py --check      exit 1 on any hit
  .gates/no_hardcoding.py --baseline   accept today's findings

The failure this exists for: a generator emits a literal copy of values that
also sit in the data file it is supposed to read. Editing the data then changes
nothing, and the rendered page keeps showing the old copy. "No hardcoded
values" stated in writing does not prevent this. A rule in a document is not a
gate.

What it does: collects values out of the data files, normalises them, and
refuses any that also appear inside the code that is supposed to render them.

All configuration is strictly declarative. It reads from [tool.gates.no_hardcoding]
in pyproject.toml or .gates.toml. If required keys are not declared, it fails fast.
"""
import html as html_mod
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _baseline
import _config

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GATE = "no_hardcoding"

REQUIRED_KEYS = [
    "data_dirs",
    "code_dirs",
    "data_extensions",
    "code_extensions",
    "min_length",
]

ROOT, config = _config.load_gate_config(HERE, GATE, REQUIRED_KEYS)

DATA_DIRS = config["data_dirs"]
CODE_DIRS = config["code_dirs"]
DATA_EXTS = tuple(config["data_extensions"])
CODE_EXTS = tuple(config["code_extensions"])
MIN_LEN = int(config["min_length"])
EXCLUDE = set(config.get("exclude", []))

# A value quoted in YAML, or a bare list item: both are things an author wrote
# as data and a generator should be reading rather than restating.
VALUE = re.compile(r'"([^"\n]{%d,})"|^\s*-\s+(?!-)([^\n#]{%d,})$' % (MIN_LEN, MIN_LEN), re.M)


def normalise(s):
    s = html_mod.unescape(s)
    s = re.sub(r"&[a-z]+;|&#x?\w+;", " ", s)          # entities the unescape missed
    s = re.sub(r"[‐-―—–-]+", "-", s)                  # every dash is one dash
    s = re.sub(r"[`*_\[\]()<>]", "", s)               # markdown emphasis, links, tags
    s = s.replace('"', "").replace("'", "")           # a YAML list item keeps its quotes
    s = re.sub(r",?\s*\b(19|20)\d{2}\b", "", s)        # a year, wherever it sits
    s = re.sub(r"\s+", " ", s)
    return s.strip(" .,;:").lower()


GENERATED = re.compile(r'generated[_ ]by|@generated|do not edit', re.I)


def is_generated(text):
    return bool(GENERATED.search(text[:600]))


def _tracked():
    """Only files git tracks. An untracked artifact is not part of the
    repository, so it cannot be a second copy of anything in it."""
    try:
        out = subprocess.run(["git", "-C", ROOT, "ls-files", "-z"],
                             capture_output=True, text=True, timeout=30).stdout
        return {os.path.join(ROOT, f) for f in out.split("\0") if f}
    except Exception:
        return None


TRACKED = _tracked()


def walk(dirs, exts):
    for d in dirs:
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            continue
        for root, subs, files in os.walk(base):
            subs[:] = [s for s in subs if not s.startswith(".") and s != "__pycache__"]
            for f in files:
                if not f.endswith(exts):
                    continue
                rel_path = os.path.relpath(os.path.join(root, f), ROOT)
                if rel_path in EXCLUDE or f in EXCLUDE:
                    continue
                full = os.path.join(root, f)
                if TRACKED is not None and full not in TRACKED:
                    continue
                yield full


def main():
    values = {}
    for fp in walk(DATA_DIRS, DATA_EXTS):
        text = open(fp, errors="ignore").read()
        if is_generated(text):
            continue
        for m in VALUE.finditer(text):
            raw = (m.group(1) or m.group(2) or "").strip()
            n = normalise(raw)
            if len(n) >= MIN_LEN:
                values.setdefault(n, (os.path.relpath(fp, ROOT), raw[:70]))

    hits = []
    for fp in walk(CODE_DIRS, CODE_EXTS):
        rel = os.path.relpath(fp, ROOT)
        if os.path.basename(fp) == os.path.basename(__file__):
            continue
        for i, line in enumerate(open(fp, errors="ignore"), 1):
            n = normalise(line)
            if len(n) < MIN_LEN:
                continue
            for value, (src, sample) in values.items():
                if value in n:
                    hits.append((rel, i, src, sample))
                    break

    found = {f"{rel}\t{normalise(sample)}":
             f"{rel}:{i}\n      repeats a value from {src}: {sample}"
             for rel, i, src, sample in hits}

    if "--baseline" in sys.argv:
        out = _baseline.save(ROOT, GATE, found,
                             f"{len(found)} finding(s) at adoption")
        print(f"Baselined {len(found)} finding(s) -> {os.path.relpath(out, ROOT)}")
        return

    new, old = _baseline.split(ROOT, GATE, found)
    blocking = _baseline.report(
        GATE, new, old,
        "The data file is the source. Read it; do not restate it.\n"
        "To accept the current state instead: .gates/no_hardcoding.py --baseline")

    _baseline.record(ROOT, GATE, len(new), len(old), blocking)

    if "--check" in sys.argv and blocking:
        sys.exit(1)


if __name__ == "__main__":
    main()

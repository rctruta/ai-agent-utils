#!/usr/bin/env python3
"""
no_hardcoding — refuse code that repeats a value its data file already holds.

  .gates/no_hardcoding.py              report
  .gates/no_hardcoding.py --check      exit 1 on any hit

The failure this exists for, observed 2026-10-13: a generator rendered a list of
certificates as literal HTML while the same certificates sat in the YAML it was
supposed to read. The data was edited — years removed, deliberately — and the
page kept showing the hardcoded copy with the years in it. The rule "no
hardcoded values" had been stated repeatedly, in writing, to every agent that
touched the repository. A rule in a document is not a gate.

What it does: collects values out of the data files, normalises them, and
refuses any that also appear inside the code that is supposed to render them.

Normalisation matters more than the comparison. The certificate in the data read
"Large Language Models — Databricks / edX" and the copy in the generator read
"Large Language Models &mdash; Databricks / edX, 2023" — not equal as strings,
the same claim to a reader. So: HTML entities decoded, dashes unified, case and
whitespace flattened, and a trailing year dropped before comparing.

Configure it where it differs per project — the defaults suit a `data/` plus
generators layout:

  DATA_DIRS   where values live
  CODE_DIRS   where they must not be repeated
  MIN_LEN     shorter strings collide by accident; 25 is a reasonable floor
"""
import html as html_mod
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

DATA_DIRS = ["data"]
CODE_DIRS = ["tools", "templates", "scripts", "src"]
DATA_EXTS = (".yaml", ".yml", ".json", ".toml")
CODE_EXTS = (".py", ".html", ".js", ".mjs", ".sh")
MIN_LEN = 25

# A value quoted in YAML, or a bare list item: both are things an author wrote
# as data and a generator should be reading rather than restating.
VALUE = re.compile(r'"([^"\n]{%d,})"|^\s*-\s+(?!-)([^\n#]{%d,})$' % (MIN_LEN, MIN_LEN), re.M)


def normalise(s):
    s = html_mod.unescape(s)
    s = re.sub(r"&[a-z]+;|&#x?\w+;", " ", s)          # entities the unescape missed
    s = re.sub(r"[‐-―—–-]+", "-", s)         # every dash is one dash
    s = re.sub(r"[`*_\[\]()<>]", "", s)                # markdown emphasis, links, tags
    s = s.replace('"', "").replace("'", "")            # a YAML list item keeps its quotes
    s = re.sub(r",?\s*\b(19|20)\d{2}\b", "", s)         # a year, wherever it sits
    s = re.sub(r"\s+", " ", s)
    return s.strip(" .,;:").lower()


def walk(dirs, exts):
    for d in dirs:
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            continue
        for root, subs, files in os.walk(base):
            subs[:] = [s for s in subs if not s.startswith(".") and s != "__pycache__"]
            for f in files:
                if f.endswith(exts):
                    yield os.path.join(root, f)


def main():
    values = {}
    for fp in walk(DATA_DIRS, DATA_EXTS):
        text = open(fp, errors="ignore").read()
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

    if hits:
        print("HARDCODED DATA IN CODE:\n")
        for rel, i, src, sample in hits:
            print(f"  {rel}:{i}")
            print(f"      repeats a value from {src}: {sample}")
        print("\nThe data file is the source. Read it; do not restate it.\n")
    else:
        print("No data values hardcoded in code.")

    if "--check" in sys.argv and hits:
        sys.exit(1)


main()

#!/usr/bin/env python3
"""
check_registry — GATES.md must agree with templates/gates/.

    python3 tests/check_registry.py            report
    python3 tests/check_registry.py --check    exit 1 on any disagreement

This checks the registry against itself, so it lives in tests/ and is not
distributed. It asserts three things:

  1. The version stated in GATES.md equals templates/gates/VERSION.
  2. Every script in templates/gates/ is accounted for -- either a row in the
     registry table, or named in TOOLS below as something that reports rather
     than refuses.
  3. The table's index column is 1..N with no gaps or repeats.

WHY. The version in GATES.md is hand-typed and drifts from
templates/gates/VERSION, in the document whose entire subject is that
hand-maintained claims drift. A script can also sit in templates/gates/ and
be absent from the table, with nothing to say whether that is deliberate.

The irony is the point: no_hardcoding refuses code that restates a value its
data file already holds, and the registry documenting that gate restated its
own version number. A rule the author does not apply to themselves is a rule
nobody else will apply either.

The version is kept visible in GATES.md rather than replaced by a pointer,
because a reader wants to see it -- and the same choice is made in
publish_contract, where versions are duplicated across files on purpose and a
gate asserts they agree.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(ROOT, "GATES.md")
SEED = os.path.join(ROOT, "templates", "gates")
VERSION_FILE = os.path.join(SEED, "VERSION")

# Scripts in templates/gates/ that are NOT gates: they report, distribute or
# assist, and refuse nothing. Listed explicitly so "absent from the table" is
# a decision rather than an oversight.
TOOLS = {
    "check_version.py":  "reports whether a repo's gates are current",
    "gates_report.sh":   "reports what each gate has found, as a snapshot",
    "survey.sh":         "reports what a gate WOULD find, before adopting it",
    "_baseline.py":      "shared library; adopts a gate without breaking a repo",
    "_config.py":        "shared library; declarative TOML configuration loader for gates",
}

# Data a gate reads, not a script.
DATA = {"VERSION", "FACTS.yaml", "publish_contract.toml"}

ROW = re.compile(r"^\|\s*(?:(\d+)\s*\|\s*)?`(?P<name>[a-zA-Z0-9_/]+\.(?:py|sh))`\s*\|")
STATED = re.compile(r"^\*\*Version:\s*(\d+)\*\*", re.M)


def findings():
    out = []
    if not os.path.isfile(DOC):
        return [f"{DOC} is missing"]
    doc = open(DOC, encoding="utf-8").read()

    # 1. the stated version
    want = open(VERSION_FILE, encoding="utf-8").read().strip()
    m = STATED.search(doc)
    if not m:
        out.append('GATES.md has no "**Version: N**" line to check against '
                   'templates/gates/VERSION')
    elif m.group(1) != want:
        out.append(f"GATES.md says Version {m.group(1)} but "
                   f"templates/gates/VERSION says {want}. The registry's own "
                   f"version is the one number it must not restate wrongly.")

    # 2. every script accounted for
    documented, indices = set(), []
    for line in doc.splitlines():
        r = ROW.match(line)
        if r:
            documented.add(os.path.basename(r.group("name")))
            if r.group(1):
                indices.append(int(r.group(1)))

    present = set()
    for _, _, files in os.walk(SEED):
        for f in files:
            if f.endswith((".py", ".sh")):
                present.add(f)

    for f in sorted(present - documented - set(TOOLS)):
        out.append(f"templates/gates/{f} exists but has no row in GATES.md. "
                   f"Add one, or add it to TOOLS in this script if it reports "
                   f"rather than refuses.")
    for f in sorted(documented - present):
        out.append(f"GATES.md documents {f}, which is not in templates/gates/. "
                   f"A row for a gate nobody has is worse than no row.")
    for f in sorted(set(TOOLS) & documented):
        out.append(f"{f} is listed in TOOLS as not-a-gate but also has a row "
                   f"in GATES.md. Pick one.")

    # 3. the index column
    if indices:
        expected = list(range(1, len(indices) + 1))
        if indices != expected:
            out.append(f"the table's index column is {indices}, expected "
                       f"{expected}. Renumber it; an index with a gap invites "
                       f"a reference to a gate that is not there.")
    return out


def main():
    found = findings()
    if not found:
        want = open(VERSION_FILE, encoding="utf-8").read().strip()
        n = sum(1 for line in open(DOC, encoding="utf-8") if ROW.match(line))
        print(f"check_registry: clean — GATES.md and templates/gates/ agree at "
              f"version {want}, {n} gate(s) documented, {len(TOOLS)} tool(s) "
              f"declared not-a-gate.")
        return 0
    print("\nREGISTRY:\n")
    for f in found:
        print(f"  {f}")
    print()
    return 1 if "--check" in sys.argv else 0


sys.exit(main())

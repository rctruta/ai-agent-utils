#!/usr/bin/env python3
"""
no_local_paths — refuse tracked files that carry one machine's absolute paths.

  .gates/no_local_paths.py              report
  .gates/no_local_paths.py --check      exit 1 on any hit

The failure this exists for, observed 2026-10-13: a generator written for one
person's site was synced into a template meant for anyone, with
`~/Projects/<their-name>/README.md` hardcoded in it. Cloning the template got
you a script pointed at a stranger's repository. Nothing was secret; it simply
could not work anywhere but one laptop, and it published a directory layout
that was nobody else's business.

A home path in committed code is one of three things, all worth catching: a
script that only runs on its author's machine, a leak of a local directory
structure, or a dependency on a sibling repository that was never declared.

Paths inside comments, docstrings and documentation count. That is where this
one was.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

PATTERNS = [
    ("macOS home",   re.compile(r"/Users/[A-Za-z0-9._-]+")),
    ("Linux home",   re.compile(r"/home/[A-Za-z0-9._-]+")),
    ("Windows home", re.compile(r"[Cc]:\\\\?Users\\\\?[A-Za-z0-9._-]+")),
]

# Where a local path is the subject rather than a dependency: a gate that
# reports them has to be able to name them.
SKIP_BASENAMES = {os.path.basename(__file__)}
SKIP_DIRS = {".git", "node_modules", "venv", ".venv", "__pycache__",
             "dist", "build", "site-packages", ".pytest_cache"}
# An allowlist exists so an exemption is a decision in the diff, never silence.
ALLOW = [
    # "docs/setup.md",   # explains where to clone, intentionally absolute
]


def tracked():
    try:
        out = subprocess.run(["git", "-C", ROOT, "ls-files", "-z"],
                             capture_output=True, text=True, timeout=30).stdout
        return [f for f in out.split("\0") if f]
    except Exception:
        names = []
        for root, subs, files in os.walk(ROOT):
            subs[:] = [s for s in subs if s not in SKIP_DIRS]
            names += [os.path.relpath(os.path.join(root, f), ROOT) for f in files]
        return names


def main():
    hits = []
    for rel in tracked():
        if rel in ALLOW or os.path.basename(rel) in SKIP_BASENAMES:
            continue
        if any(part in SKIP_DIRS for part in rel.split(os.sep)):
            continue
        path = os.path.join(ROOT, rel)
        if not os.path.isfile(path):
            continue
        try:
            text = open(path, errors="ignore").read()
        except Exception:
            continue
        for label, pattern in PATTERNS:
            for i, line in enumerate(text.splitlines(), 1):
                m = pattern.search(line)
                if m:
                    hits.append((rel, i, label, m.group(0)))
                    break

    if hits:
        print("LOCAL PATHS IN TRACKED FILES:\n")
        for rel, i, label, found in hits:
            print(f"  {rel}:{i}  {label}  {found}")
        print("\nUse a path relative to the repository root, or read it from\n"
              "configuration. If one is deliberate, add it to ALLOW with a reason.\n")
    else:
        print("No local paths in tracked files.")

    if "--check" in sys.argv and hits:
        sys.exit(1)


main()

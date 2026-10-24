#!/usr/bin/env python3
"""Refuse a script that hardcodes what belongs in config, or that needs bash.

  python3 .gates/check_script_standards.py            report
  python3 .gates/check_script_standards.py --check    exit 1 on a new finding
  python3 .gates/check_script_standards.py --baseline adopt existing findings

The failure this exists for: a script that decides what leaves a repository
encodes that decision as a pattern in its own source. A prefix that matches
one directory and not its parent silently publishes the parent, and nobody
reviews the decision because it is a few characters inside a variable rather
than a line in a config file.

The same shape brings hardcoded endpoints, absolute paths and addresses, and
a dependency on `tar`, `comm` or `grep -E`, which makes the script work on one
machine and nowhere else. "Configuration lives in a file, never in code"
stated in writing does not prevent any of it. A rule in a document binds
nobody.

WHAT IT REFUSES

In a tracked .py file: a literal http(s) URL, an absolute filesystem path, a
home directory, or an email address. Those are configuration. They belong in
a YAML file the script reads, so that what the script does can be reviewed in
a diff of that file rather than by reading code.

In a tracked .sh file: process substitution `<(...)`, `[[ ]]`, arrays, and
`sed -i` -- constructs that are bash-only or GNU-only and that make a script
work on one machine and nowhere else.

WHAT IT ALLOWS, AND WHY

Comments and docstrings. A URL in a comment is documentation; the failure was
a URL the code acted on.

Test files. A test needs literal values to assert against -- that is the
point of a test.

`.gates/` and the seed's own installers. They run in repositories that have
installed nothing, which is why they are stdlib shell on purpose, and a
pyyaml import once broke `init-agent-project` outright.

Existing findings, once baselined. A gate that fails on day one gets switched
off, and a gate that is off catches nothing.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import _baseline                                            # noqa: E402

GATE = "check_script_standards"

# Only directories whose files genuinely need literal values. A gate that
# exempts its own directory cannot see what it is carrying: scan.py kept a
# real address in its own docstring for two weeks because its file was in
# its own skip list (GATES.md, "Two gates that were fixed rather than
# added"). So .gates/ is NOT skipped. Its real findings -- a pattern that
# must contain "/Users/" because detecting that is the gate's whole job --
# go in the baseline, which is committed and visible in a diff rather than
# silent.
SKIP_DIRS = ("tests/", "test/")
SKIP_NAMES = ("conftest.py", "setup.py")

PY_RULES = [
    (re.compile(r"""['"]https?://[^'"\s]+['"]"""), "a literal URL"),
    (re.compile(r"""['"]/(?:Users|home|opt|var|etc|tmp)/[^'"\s]*['"]"""),
     "an absolute path"),
    (re.compile(r"""['"]~/[^'"\s]*['"]"""), "a home directory"),
    (re.compile(r"""['"][\w.+-]+@[\w-]+\.[\w.]+['"]"""), "an email address"),
]

SH_RULES = [
    (re.compile(r"<\("), "process substitution, which is bash-only"),
    # Bash's [[ is always followed by whitespace: `[[ -f x ]]`. Requiring
    # that separates it from a POSIX character class `[[:space:]]` and from
    # a TOML array-of-tables header `[[surfaces.requires]]`, both of which
    # this flagged on its first real run.
    (re.compile(r"\[\[\s"), "[[ ]], which is bash-only"),
    (re.compile(r"=\(\s*\$?\w"), "an array, which is bash-only"),
    # `sed -i.bak` supplies a suffix and works on both. The incompatible
    # forms are bare `-i` (GNU) and `-i ''` (BSD), which is `-i` followed by
    # whitespace. Flagged `sed -i.bak` on its first real run.
    (re.compile(r"\bsed\s+-i(?=\s)"), "sed -i with no suffix, which "
                                      "differs on BSD and GNU"),
]


def tracked():
    out = subprocess.run(["git", "-C", ROOT, "ls-files", "-z"],
                         capture_output=True, text=True, timeout=30).stdout
    return [f for f in out.split("\0") if f]


def strip_comments_py(line):
    """Drop a trailing comment so a URL in prose is not a finding.

    Deliberately crude: it does not parse strings containing '#'. A false
    negative here costs nothing -- the value is still in a string literal and
    the next rule catches it -- while a false positive on documentation is
    what makes a gate annoying enough to switch off.
    """
    in_s = None
    for i, ch in enumerate(line):
        if in_s:
            if ch == in_s:
                in_s = None
        elif ch in "\"'":
            in_s = ch
        elif ch == "#":
            return line[:i]
    return line


def scan():
    found = []
    for rel in tracked():
        if rel.startswith(SKIP_DIRS) or os.path.basename(rel) in SKIP_NAMES:
            continue
        if os.path.basename(rel).startswith("test_"):
            continue
        path = os.path.join(ROOT, rel)
        if not os.path.isfile(path):
            continue
        if rel.endswith(".py"):
            rules, strip = PY_RULES, strip_comments_py
        elif rel.endswith(".sh"):
            rules, strip = SH_RULES, (lambda s: s.split("#", 1)[0])
        else:
            continue
        in_doc = False
        for line in open(path, errors="ignore"):
            if rel.endswith(".py"):
                # Skip docstrings: they are prose, like comments.
                ticks = line.count('"""') + line.count("'''")
                if ticks:
                    in_doc = not in_doc if ticks % 2 else in_doc
                    continue
                if in_doc:
                    continue
            code = strip(line)
            for rx, why in rules:
                m = rx.search(code)
                if m:
                    found.append((f"{rel}::{m.group(0)[:60]}", rel, why,
                                  code.strip()[:70]))
                    break
    return found


def main():
    found = scan()
    # _baseline.split takes a dict of key -> printable description.
    described = {k: f"{rel}: {why}\n      {text}" for k, rel, why, text in found}

    if "--baseline" in sys.argv:
        print(_baseline.save(ROOT, GATE, described.keys(),
                             f"{len(described)} finding(s) at adoption"))
        return 0

    new_f, old_f = _baseline.split(ROOT, GATE, described)
    blocking = _baseline.report(
        GATE, new_f, old_f,
        "  Configuration belongs in a YAML file the script reads, so that\n"
        "  what it does is reviewable in a diff of that file. For shell, use\n"
        "  POSIX sh -- a bash-only construct works on one machine and nowhere\n"
        "  else. See the script-standards skill.")
    _baseline.record(ROOT, GATE, len(new_f), len(old_f), blocking)
    return 1 if blocking else 0


code = main()
if "--check" in sys.argv:
    sys.exit(code)

#!/usr/bin/env python3
"""Refuse outbound text that reads like a private conversation, or names
work that is not published yet.

    python3 .gates/check_outbound.py <file> [<file> ...]
    python3 .gates/check_outbound.py --check <file>     exit 1 on any hit

Outbound text is text that becomes public but is not a tracked source file:
a commit message, a pull-request body, a release note. Every other gate in
this directory reads the git index, so none of them can see any of it.

A commit message and a PR body are published artifacts. Because neither is
a file in the index, a full suite of gates and a full test run can pass while
both say whatever they say.

Two separate rules, with different stakes:

  register    A public artifact is not addressed to one reader. "Say the
              word and I'll build it" and "your call" belong in a chat
              window. This is a style rule and its cost of a false positive
              is low: reword and move on.

  disclosure  A reference to unpublished work must not reach a public
              commit message or PR body. This is the rule with teeth, and
              it is the reason this file exists rather than a note in
              AGENTS.md.

Why the term list is not in this repository. The list names unpublished work.
Committing it here would publish exactly what it exists to protect -- a gate
that leaks its own subject. So it is read from an untracked file:

    .gates/outbound_private.txt      one term per line, '#' comments

That path is gitignored. When it is missing this gate FAILS rather than
passes: a silent skip is how a protection becomes decoration. Use
--no-private only when there is genuinely nothing to protect, and say so in
the diff.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PRIVATE_LIST = os.path.join(HERE, "outbound_private.txt")

# Second-person address, and the hedging offers that come with it. A public
# artifact describes a change; it does not negotiate with a reader.
REGISTER = [
    (re.compile(r"(?<![\w'])(your|yours|you'(?:re|ll|ve|d))(?![\w'])", re.I),
     "addresses a reader directly"),
    (re.compile(r"(?<![\w'])you(?![\w'])", re.I),
     "addresses a reader directly"),
    (re.compile(r"\b(say the word|let me know|if you want|want me to|"
                r"shall I|I'll (?:build|do|fix|add) (?:it|that)|"
                r"one thing for you|over to you|your call|up to you)\b", re.I),
     "asks the reader to decide"),
    (re.compile(r"\b(I'm not going to|I won't|I was wrong|my mistake|"
                r"taking .{0,12}down|sorry)\b", re.I),
     "narrates the author's own process"),
]

# A fenced block or an indented block is quoted material -- a log line, a
# traceback, a config excerpt. Reword prose, not evidence.
FENCE = re.compile(r"^\s*(```|~~~)")


def private_terms(allow_missing):
    """Terms that must not appear in public outbound text.

    Read from an untracked file on purpose; see the module docstring.
    """
    if not os.path.isfile(PRIVATE_LIST):
        if allow_missing:
            return []
        print(f"check_outbound: {PRIVATE_LIST} is missing.\n"
              f"  This gate blocks references to unpublished work, and the\n"
              f"  list of that work is deliberately NOT tracked. Create the\n"
              f"  file (one term per line) or pass --no-private and say why\n"
              f"  in the diff. It will not pass by default.", file=sys.stderr)
        raise SystemExit(2)
    terms = []
    for line in open(PRIVATE_LIST, errors="ignore"):
        line = line.split("#", 1)[0].strip()
        if line:
            terms.append(line)
    return terms


def scan(path, terms):
    hits = []
    in_fence = False
    for i, line in enumerate(open(path, errors="ignore"), 1):
        if FENCE.search(line):
            in_fence = not in_fence
            continue
        if in_fence or line.startswith(("    ", "\t")):
            continue
        # A commit message's trailing git template is not the author's prose.
        if line.startswith("#"):
            continue
        for term in terms:
            if re.search(rf"(?<!\w){re.escape(term)}(?!\w)", line, re.I):
                hits.append((i, "DISCLOSURE", f"names unpublished work: {term!r}",
                             line.strip()[:76]))
        for pattern, why in REGISTER:
            m = pattern.search(line)
            if m:
                hits.append((i, "REGISTER", f"{why}: {m.group(0)!r}",
                             line.strip()[:76]))
                break
    return hits


def main(argv):
    paths = [a for a in argv if not a.startswith("--")]
    if not paths:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    terms = private_terms("--no-private" in argv)

    failed = False
    for path in paths:
        if not os.path.isfile(path):
            print(f"check_outbound: {path} does not exist.", file=sys.stderr)
            return 2
        hits = scan(path, terms)
        if not hits:
            continue
        failed = True
        print(f"\nOUTBOUND TEXT NOT FIT TO PUBLISH -- {path}\n", file=sys.stderr)
        for i, kind, why, text in hits:
            print(f"  {kind:11} line {i}  {why}\n              {text}",
                  file=sys.stderr)
        print("\n  This string becomes public and no other gate can see it.\n"
              "  Describe the change: what it does, why it is correct. Not who\n"
              "  asked for it, not what is still undecided, and nothing that\n"
              "  is not published yet.\n", file=sys.stderr)

    if not failed:
        n = len(terms)
        print(f"check_outbound: clean ({len(paths)} file(s), "
              f"{n} private term(s) enforced).")
    return 1 if failed else 0


code = main(sys.argv[1:])
if "--check" in sys.argv:
    sys.exit(code)
sys.exit(0 if code != 2 else 2)

#!/usr/bin/env python3
"""
Check every registered fact in FACTS.yaml against its source.

Agent-agnostic: stdlib only, no network unless a fact asks for it, runs from a
bare python3 in a git hook regardless of which agent (or human) triggered it.

  python3 .gates/verify.py           report
  python3 .gates/verify.py --check   exit 1 if any verified fact fails
"""
import os, re, sys, subprocess, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FACTS = os.path.join(HERE, "FACTS.yaml")


def load():
    """Minimal parser for this file's shape — avoids a PyYAML dependency."""
    facts, cur, section = [], None, None
    for line in open(FACTS):
        s = line.rstrip("\n")
        if s.startswith("facts:"):
            section = "facts"; continue
        if s.startswith(("banned:", "allow:")):
            section = None; continue
        if section != "facts":
            continue
        m = re.match(r"\s*-\s+id:\s*(.+)", s)
        if m:
            cur = {"id": m.group(1).strip()}; facts.append(cur); continue
        m = re.match(r"\s+(\w+):\s*(.*)", s)
        if m and cur is not None:
            cur[m.group(1)] = m.group(2).strip().strip('"')
    return facts


def resolve(p):
    p = os.path.expanduser(p)
    return p if os.path.isabs(p) else os.path.join(ROOT, p)


def check(f):
    if f.get("status") != "verified":
        return ("SKIP", f.get("status", "unverified"))
    kind, src = f.get("check"), f.get("source", "")
    try:
        if kind == "dircount":
            d = resolve(src)
            n = len([x for x in os.listdir(d) if re.fullmatch(r"[0-9a-f]{8}", x)])
            ok = str(n) == f["claim"]
            return ("PASS", f"{n} entries") if ok else ("FAIL", f"found {n}, claim says {f['claim']}")
        if kind == "shell":
            out = subprocess.run(src, shell=True, capture_output=True, text=True, timeout=45).stdout
            ok = f.get("expect", f["claim"]) in out
            return ("PASS", "expected string in output") if ok else ("FAIL", "expected string absent")
        if kind == "url_contains":
            body = urllib.request.urlopen(src, timeout=25).read().decode(errors="ignore")
            ok = f.get("expect", f["claim"]) in body
            return ("PASS", "found at source") if ok else ("FAIL", "not found at source")
        if "grep" in f:
            p = resolve(src)
            if not os.path.exists(p):
                return ("FAIL", f"source missing: {src}")
            ok = f["grep"] in open(p, errors="ignore").read()
            return ("PASS", "found in source") if ok else ("FAIL", f"'{f['grep']}' not in {os.path.basename(p)}")
    except Exception as e:
        return ("ERROR", str(e)[:60])
    return ("SKIP", "no check defined")


def main():
    facts = load()
    if not facts:
        print("No facts registered in .gates/FACTS.yaml"); return
    bad = 0
    print(f"{'STATUS':7} {'ID':28} DETAIL")
    print("-" * 78)
    for f in facts:
        st, detail = check(f)
        if st in ("FAIL", "ERROR"):
            bad += 1
        print(f"{st:7} {f['id']:28} {detail}")
    print("-" * 78)
    ver = sum(1 for f in facts if f.get("status") == "verified")
    rep = sum(1 for f in facts if f.get("status") == "reported")
    print(f"{len(facts)} facts: {ver} verified, {rep} reported | failures: {bad}")
    if "--check" in sys.argv and bad:
        sys.exit(1)


main()

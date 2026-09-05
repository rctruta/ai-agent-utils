#!/usr/bin/env python3
"""
Scan outward-facing files for banned claims, and report numbers that are not
registered in FACTS.yaml.

Banned claims BLOCK (--check exits 1). Unregistered numbers only REPORT — a
noisy blocker gets bypassed, and a bypassed gate is worse than no gate.

  python3 .gates/scan.py [paths...]
  python3 .gates/scan.py --check [paths...]
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FACTS = os.path.join(HERE, "FACTS.yaml")

EXTS = (".txt", ".md", ".html", ".rst", ".tex")
SKIP_DIRS = {".git", ".gates", "node_modules", "venv", ".venv", "assets",
             "dist", "build", "__pycache__", "site-packages"}


def parse():
    claims, banned, allow, sec = set(), [], [], None
    for line in open(FACTS):
        if line.startswith("facts:"):  sec = "f"; continue
        if line.startswith("banned:"): sec = "b"; continue
        if line.startswith("allow:"):  sec = "a"; continue
        m = re.match(r'\s+claim:\s*"(.+)"', line)
        if m and sec == "f":
            for tok in re.findall(r"[\d][\d,.]*\+?%?x?", m.group(1)):
                claims.add(tok.rstrip("."))
        m = re.match(r'\s+-\s+pattern:\s*"(.+)"', line)
        if m and sec == "b": banned.append(m.group(1))
        m = re.match(r'\s+contains:\s*"(.+)"', line)
        if m and sec == "a": allow.append(m.group(1))
    return claims, banned, allow


NUM = re.compile(r"\b\d[\d,]*(?:\.\d+)?\s?(?:x|×|%|\+)?\b")
# Years, small integers and version-shaped tokens are noise, not claims.
NOISE = re.compile(r"^(19|20)\d\d[,.]?$|^\d{1,2}$|^\d+\.\d+\.\d+$")


def files(paths):
    for p in paths:
        p = os.path.expanduser(p)
        if os.path.isfile(p):
            yield p; continue
        for root, dirs, fs in os.walk(p):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for f in fs:
                if f.endswith(EXTS):
                    yield os.path.join(root, f)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    paths = args or [ROOT]
    claims, banned, allow = parse()
    hits, unreg = [], {}

    for fp in files(paths):
        txt = open(fp, errors="ignore").read()
        for b in banned:
            if b in txt:
                for i, line in enumerate(txt.splitlines(), 1):
                    if b in line and not any(a in line for a in allow):
                        hits.append((fp, i, b, line.strip()[:70]))
        for n in {t.strip() for t in NUM.findall(txt)}:
            if n in claims or NOISE.match(n):
                continue
            unreg.setdefault(n, set()).add(os.path.basename(fp))

    if hits:
        print("BANNED CLAIMS FOUND — these were fabricated before:\n")
        for fp, ln, b, line in hits:
            print(f"  {os.path.relpath(fp, ROOT)}:{ln}  [{b}]  {line}")
        print()
    else:
        print("No banned claims found.\n")

    if unreg and "--quiet" not in sys.argv:
        print("Unregistered numbers (review; register in FACTS.yaml or remove):\n")
        for n in sorted(unreg, key=lambda k: -len(unreg[k]))[:20]:
            print(f"  {n:12} in {', '.join(sorted(unreg[n])[:4])}")

    if "--check" in sys.argv and hits:
        sys.exit(1)


main()

#!/usr/bin/env python3
"""
check_protection_call — every branch-protection call must send a VALID shape.

    python3 tests/check_protection_call.py            report
    python3 tests/check_protection_call.py --check    exit 1 on a bad shape

GitHub's branch-protection endpoint takes `required_status_checks` as either
null or an object carrying BOTH `strict` and `contexts`. Send half of it and
you get a 422 that names neither field:

    For 'anyOf/1', {"strict" => false} is not a null.

WHY THIS REPLACES WHAT WAS HERE. ci_checks.sh step 2 banned ONE invalid form,
the dotted `required_pull_request_reviews.required...` that never worked. A
different invalid form -- `strict` without `contexts` -- then sailed past,
because a check that bans one known-bad shape says nothing about the next
one, even when a correct shape is already in the repository to copy.

So this asserts the shapes that WORK rather than blacklisting shapes that do
not. A new way to get it wrong is caught by the same rule, which is the whole
difference between a pattern matcher and an invariant.

It scans scripts, markdown and workflows, because the command gets copied into
prose and a wrong command in a README is run by a person who trusts it.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".git", ".venv", "node_modules", "__pycache__", "scratch", "dist"}
SKIP_FILES = {os.path.basename(__file__)}
EXTS = (".sh", ".md", ".yml", ".yaml", ".py", ".txt")

# A call is any run of text mentioning the protection endpoint, up to a blank
# line. Calls are written across continuations, so line-by-line is not enough.
CALL = re.compile(r"[^\n]*branches/[^\n]*/protection.*?(?=\n\s*\n|\Z)", re.S)

STRICT = re.compile(r"required_status_checks\[strict\]")
CONTEXTS = re.compile(r"required_status_checks\[contexts\]\[\]")
NULL_CHECKS = re.compile(r"required_status_checks\s*=\s*null")
# Only in a field-sending position. The same dotted path is correct in a `--jq`
# expression, which READS the response rather than building the request, so
# matching it anywhere in the call flags a line that is right.
DOTTED = re.compile(
    r"(?:-F|-f|--field|--raw-field)\s+[\"']?"
    r"required_(?:pull_request_reviews|status_checks)\.[a-z_]")
# A shell variable or array carrying the flags: ${CHECK_ARGS[@]}, $CHECKS_TXT.
VAR = re.compile(r"\$\{?([A-Z_][A-Z0-9_]*)(?:\[@\])?\}?")


def check_var_assignments(rel, text, names):
    """Every assignment to a variable that supplies the flags must be valid.

    A variable with no assignment in this file is not judged: it may come from
    the environment, and guessing would be worse than saying nothing.
    """
    out = []
    for name in set(names):
        assigns = re.findall(rf"^\s*{name}=.*$", text, re.M)
        relevant = [a for a in assigns if "required_status_checks" in a]
        if not relevant:
            continue
        for a in relevant:
            has_strict, has_ctx = bool(STRICT.search(a)), bool(CONTEXTS.search(a))
            has_null = bool(NULL_CHECKS.search(a))
            if has_strict and not has_ctx:
                out.append(f"{rel}  {name} is assigned "
                           f"required_status_checks[strict] with no "
                           f"[contexts][]: {a.strip()[:70]}")
            elif has_ctx and not has_strict:
                out.append(f"{rel}  {name} is assigned [contexts][] with no "
                           f"[strict]: {a.strip()[:70]}")
            elif not (has_strict or has_ctx or has_null):
                out.append(f"{rel}  {name} mentions required_status_checks in "
                           f"no recognised shape: {a.strip()[:70]}")
    return out


def findings(root=None):
    # The tree to scan is an argument, so this can be pointed at a fixture.
    # A checker that can only read its own repository cannot be shown to
    # refuse anything, and an unprovable checker is the thing it exists to
    # prevent.
    root = root or ROOT
    out = []
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if not name.endswith(EXTS) or name in SKIP_FILES:
                continue
            rel = os.path.relpath(os.path.join(dirpath, name), root)
            try:
                text = open(os.path.join(dirpath, name),
                            encoding="utf-8", errors="ignore").read()
            except Exception:
                continue
            if "/protection" not in text:
                continue
            for m in CALL.finditer(text):
                call = m.group(0)
                line = text[:m.start()].count("\n") + 1
                if DOTTED.search(call):
                    out.append(f"{rel}:{line}  dotted field syntax "
                               f"(required_x.y) — never accepted; 422")
                has_strict = bool(STRICT.search(call))
                has_ctx = bool(CONTEXTS.search(call))
                has_null = bool(NULL_CHECKS.search(call))
                if has_strict and not has_ctx:
                    out.append(
                        f"{rel}:{line}  required_status_checks[strict] without "
                        f"[contexts][] — GitHub needs BOTH or null, and "
                        f"answers with: For 'anyOf/1', {{\"strict\"}} is not a "
                        f"null")
                if has_ctx and not has_strict:
                    out.append(
                        f"{rel}:{line}  required_status_checks[contexts][] "
                        f"without [strict] — same rule, other half missing")
                if not (has_strict or has_ctx or has_null):
                    # The shape may arrive through a shell variable -- the
                    # working call in init-agent-project.sh passes
                    # "${CHECK_ARGS[@]}", built two lines above. Follow the
                    # variable and judge every assignment to it, rather than
                    # reporting a call this checker simply cannot see into.
                    via = VAR.findall(call)
                    if via:
                        out += check_var_assignments(rel, text, via)
                    else:
                        out.append(
                            f"{rel}:{line}  no required_status_checks at all "
                            f"and no variable supplying it. Send `-F "
                            f"required_status_checks=null` for a repo with no "
                            f"CI, or strict+contexts for one with it.")
    return out


def main():
    root = None
    if "--root" in sys.argv:
        root = sys.argv[sys.argv.index("--root") + 1]
    found = findings(root)
    if not found:
        print("check_protection_call: clean — every branch-protection call "
              "sends a valid required_status_checks shape.")
        return 0
    print("\nPROTECTION CALL:\n")
    for f in found:
        print(f"  {f}")
    print("\nThe two shapes that work, both already in init-agent-project.sh:\n")
    print('  with CI:    -F "required_status_checks[strict]=false" '
          '-F "required_status_checks[contexts][]=test"')
    print("  without CI: -F required_status_checks=null\n")
    return 1 if "--check" in sys.argv else 0


sys.exit(main())

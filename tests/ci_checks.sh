#!/bin/bash
# ci_checks.sh — the generator's own gate. Run by .github/workflows/ci.yml.
# Asserts that init-agent-project.sh provisions exactly what the README claims,
# on each interactive path. Remote behavior (repo creation, branch protection)
# is NOT covered here — it can't run without side effects; see README §A for
# how those were verified live.
set -e
cd "$(dirname "$0")/.."
SCRIPT="$PWD/init-agent-project.sh"

echo "1) script parses"
bash -n "$SCRIPT"

echo "2) no broken dotted gh syntax anywhere (never worked; 422)"
! grep -q 'required_pull_request_reviews\.required' "$SCRIPT" README.md

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
run() { printf "$1" | bash "$SCRIPT" "$2" "$ROOT" >/dev/null 2>&1; }

echo "3) default path: pre-push only — no lock, no CI workflow"
run 'N\nN\nN\n' plain
[ -f "$ROOT/plain/.githooks/pre-push" ]
[ ! -e "$ROOT/plain/.githooks/pre-commit" ]
[ ! -e "$ROOT/plain/agent-lock" ]
[ ! -e "$ROOT/plain/.github/workflows/ci.yml" ]
! grep -q 'same-tree commit lock' "$ROOT/plain/AGENTS.md"
! grep -q 'agent-lock' "$ROOT/plain/README.md"

echo "4) lock opt-in path: helper + pre-commit + documented"
run 'N\ny\nN\n' locked
[ -x "$ROOT/locked/agent-lock" ]
[ -f "$ROOT/locked/.githooks/pre-commit" ]
grep -q 'same-tree commit lock' "$ROOT/locked/AGENTS.md"
grep -q 'Optional same-tree lock' "$ROOT/locked/README.md"

echo "5) python path: CI workflow provisioned, committed, job named 'test'"
run 'y\nN\nN\n' py
[ -f "$ROOT/py/.github/workflows/ci.yml" ]
grep -q '^  test:' "$ROOT/py/.github/workflows/ci.yml"
(cd "$ROOT/py" && git ls-files | grep -q 'workflows/ci.yml')
grep -q 'pytest' "$ROOT/py/requirements.txt"

echo "6) hooks are wired (core.hooksPath) and first commit exists"
[ "$(git -C "$ROOT/plain" config core.hooksPath)" = ".githooks" ]
git -C "$ROOT/plain" rev-parse HEAD >/dev/null

echo "ALL CHECKS PASSED"

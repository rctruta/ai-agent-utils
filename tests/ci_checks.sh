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

echo "2) every branch-protection call sends a valid shape (not just: not one bad one)"
# This banned ONE invalid form -- the dotted required_x.y that never worked.
# A different invalid form, strict without contexts, then sailed past: a check
# that blacklists one known-bad shape says nothing about the next one.
# check_protection_call.py asserts the shapes that
# WORK instead, across scripts, markdown and workflows, and follows a shell
# variable when the flags arrive through one.
python3 "$(dirname "$0")/check_protection_call.py" --check

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
run() { printf "$1" | bash "$SCRIPT" "$2" "$ROOT" "${@:3}" >/dev/null 2>&1; }

echo "3) default path: pre-push + claim gate — no lock, no CI workflow"
run 'N\nN\nN\n' plain
[ -f "$ROOT/plain/.githooks/pre-push" ]
# pre-commit now exists because the claim gate lives there. It must contain the
# gate and must NOT contain the optional same-tree lock.
[ -f "$ROOT/plain/.githooks/pre-commit" ]
grep -q 'claim integrity gate' "$ROOT/plain/.githooks/pre-commit"
! grep -q 'agent-lock' "$ROOT/plain/.githooks/pre-commit"
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

echo "5b) gates: installed by default, provable, and skippable"
[ -f "$ROOT/plain/.gates/FACTS.yaml" ]
[ -x "$ROOT/plain/.gates/verify.py" ]
[ -x "$ROOT/plain/.gates/scan.py" ]
[ -f "$ROOT/plain/.claude/skills/gates/SKILL.md" ]
[ -f "$ROOT/plain/.cursor/rules/gates.mdc" ]
grep -q 'Claim integrity (enforced)' "$ROOT/plain/AGENTS.md"
# every gate must actually fire
(cd "$ROOT/plain" && ./.gates/tests/prove_gates.sh >/dev/null)
# --no-gates restores the minimal path
run 'N\nN\nN\n' nogates --no-gates
[ ! -e "$ROOT/nogates/.gates" ]
[ ! -e "$ROOT/nogates/.claude" ]
! grep -q 'Claim integrity' "$ROOT/nogates/AGENTS.md"

echo "5c) no editor is opened on a non-interactive run"
# Every automated run pipes its answers in, so stdin is not a TTY. Before this
# condition existed, each test run opened a VS Code window and left a
# repository behind to close and delete by hand. A fake `code` on PATH proves
# the step is skipped rather than merely absent from CI, where `code` does not
# exist and the check would pass for the wrong reason.
FAKEBIN="$(mktemp -d)"
printf '#!/bin/sh\necho OPENED >> "$FAKE_LOG"\n' > "$FAKEBIN/code"
chmod +x "$FAKEBIN/code"
FAKE_LOG="$FAKEBIN/opened.log"
export FAKE_LOG
PATH="$FAKEBIN:$PATH" run 'N\nN\nN\n' noeditor
[ ! -f "$FAKE_LOG" ]
rm -rf "$FAKEBIN"

echo "5d) GATES.md agrees with templates/gates/ (version + every script)"
python3 "$(dirname "$0")/check_registry.py" --check

echo "6) hooks are wired (core.hooksPath) and first commit exists"
[ "$(git -C "$ROOT/plain" config core.hooksPath)" = ".githooks" ]
git -C "$ROOT/plain" rev-parse HEAD >/dev/null

echo "7) the protection-call checker itself refuses and spares the right lines"
# A checker is only trustworthy once it has been seen to do both. The dotted
# path is an error in a field that BUILDS the request and correct in a --jq
# expression that READS the response, so the narrow rule is the whole point.
PC="$(mktemp -d)"
mkdir -p "$PC/sends" "$PC/reads"
# Assembled, never literal: written out in full this line would itself be a
# finding, and the checker scans this file.
_A="required_status"; _B="_checks"; DOT="$_A$_B.strict"
printf 'gh api -X PUT "repos/$R/branches/main/protection" \\\n  -F "%s=false"\n' "$DOT" \
  > "$PC/sends/x.sh"
printf 'gh api "repos/$R/branches/main/protection" \\\n  --jq %s"strict \\(.required_status_checks.strict)"%s\n' "'" "'" \
  > "$PC/reads/x.sh"
if python3 "$(dirname "$0")/check_protection_call.py" --check --root "$PC/sends" >/dev/null 2>&1; then
  echo "  FAIL: the checker did NOT refuse a dotted field in a sending position" >&2
  rm -rf "$PC"; exit 1
fi
if ! python3 "$(dirname "$0")/check_protection_call.py" --check --root "$PC/reads" >/dev/null 2>&1; then
  echo "  FAIL: the checker flagged a dotted path inside a --jq read" >&2
  rm -rf "$PC"; exit 1
fi
rm -rf "$PC"

echo "ALL CHECKS PASSED"

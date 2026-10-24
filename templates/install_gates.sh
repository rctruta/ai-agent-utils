#!/bin/sh
# Appends the claim-integrity gate to the project's pre-commit hook and writes
# the agent adapters. Kept in its own file so nested heredocs never collide
# with the generator's own quoting.
set -e

# Where the templates live, derived from this script rather than passed in,
# so the caller cannot get it wrong.
TEMPLATES="$(cd "$(dirname "$0")" && pwd)"

cp "$TEMPLATES/pre-commit-config.yaml" .pre-commit-config.yaml
cp "$TEMPLATES/ruff.toml" ruff.toml
cp "$TEMPLATES/gitleaks.toml" .gitleaks.toml

if [ -f pyproject.toml ]; then
  if ! grep -q '\[tool\.gates' pyproject.toml; then
    cat >> pyproject.toml <<'GATESCONF'

[tool.gates.no_hardcoding]
min_length = 25
data_dirs = ["data"]
code_dirs = ["tools", "src", "templates"]
data_extensions = [".yaml", ".yml", ".json", ".toml"]
code_extensions = [".py", ".html", ".js", ".mjs", ".sh"]
exclude = []

[tool.gates.claim_integrity]
facts_file = ".gates/FACTS.yaml"
GATESCONF
  fi
else
  if [ ! -f .gates.toml ]; then
    cat > .gates.toml <<'GATESCONF'
[tool.gates.no_hardcoding]
min_length = 25
data_dirs = ["data"]
code_dirs = ["tools", "src", "templates"]
data_extensions = [".yaml", ".yml", ".json", ".toml"]
code_extensions = [".py", ".html", ".js", ".mjs", ".sh"]
exclude = []

[tool.gates.claim_integrity]
facts_file = ".gates/FACTS.yaml"
GATESCONF
  fi
fi

cat >> .githooks/pre-commit <<'GATEHOOK'

# --- pre-commit framework --------------------------------------------------
# The general-purpose checks are declared in .pre-commit-config.yaml. They
# run from here rather than from .git/hooks, because core.hooksPath points at
# this directory and git ignores .git/hooks while it does.
#
# If the config is present the runner must be too: a missing runner is a
# precondition that was not met, not a clean run. Exit 3 says so.
CONFIG="$(git rev-parse --show-toplevel)/.pre-commit-config.yaml"
if [ -f "$CONFIG" ]; then
  if command -v pre-commit >/dev/null 2>&1; then
    pre-commit run --hook-stage pre-commit || exit 1
  else
    echo "  -> .pre-commit-config.yaml is present but pre-commit is not installed." >&2
    echo "     Run: pip install pre-commit" >&2
    echo "     Not running a declared check is not a pass." >&2
    exit 3
  fi
fi

# --- claim integrity gate --------------------------------------------------
# Registered facts must still match their sources; banned claims block.
# Stdlib python3 only, so it runs without a project venv.
ROOT="$(git rev-parse --show-toplevel)"
if [ -f "$ROOT/.gates/verify.py" ]; then
  PY="$(command -v python3 || true)"
  if [ -n "$PY" ]; then
    "$PY" "$ROOT/.gates/verify.py" --check || {
      echo "  -> A registered fact no longer matches its source (.gates/FACTS.yaml)." >&2
      exit 1; }
    "$PY" "$ROOT/.gates/scan.py" --check --quiet "$ROOT" || {
      echo "  -> A banned claim appears in a staged file. See .gates/FACTS.yaml." >&2
      exit 1; }
    if [ -d "$ROOT/data" ]; then
      "$PY" "$ROOT/.gates/no_hardcoding.py" --check || {
        echo "  -> Code restates a value its data file already holds." >&2
        exit 1; }
    fi
    # Each guarded by its own test, because a repository may adopt the set
    # partially and a hook calling a gate that is not installed would fail on
    # something that is not a violation.
    # Publishing surfaces declare their own rules; a surface whose trigger
    # file appears without them is a finding.
    [ -f "$ROOT/.gates/check_publish_contract.py" ] && {
      "$PY" "$ROOT/.gates/check_publish_contract.py" --check || {
        echo "  -> A publishing surface is missing required information." >&2
        exit 1; }; }
    [ -f "$ROOT/.gates/scratch_external.py" ] && {
      "$PY" "$ROOT/.gates/scratch_external.py" --check || {
        echo "  -> A local notes folder is reachable by git, or a note is tracked." >&2
        exit 1; }; }
    [ -f "$ROOT/.gates/no_orphans.py" ] && {
      "$PY" "$ROOT/.gates/no_orphans.py" --check || {
        echo "  -> A module is imported only by its own tests." >&2
        exit 1; }; }
  fi
fi
GATEHOOK

mkdir -p .claude/skills/gates .cursor/rules

cat > .claude/skills/gates/SKILL.md <<'SKILLEOF'
---
name: gates
description: What this repository enforces mechanically. Read before making a factual claim, citing a number, attributing work to someone, or changing a working configuration.
---

This repo has gates. They are git hooks and plain scripts in .gates/, so they
run regardless of which agent is driving. This file describes them; it does not
enforce anything.

## Before stating a number or attributing work

Every load-bearing claim must be registered in .gates/FACTS.yaml with a source.
Run: python3 .gates/verify.py

A claim you have not checked is not ready to write down. Attributions to third
parties — who filed an issue, who reviewed what — are verified against the
source system, never against an earlier draft.

## Before changing something that works

Tag the known-good commit, with the command that proves it in the message:

    git tag -a known-good-<name> -m "<command that proves it works>"

Then "it worked before" is a recorded command rather than a memory, and
nothing extra has to be installed or kept working.

## Declarative Gate Configuration

Gate engines in `.gates/` are immutable mechanism. Project paths, thresholds, and exclusions are configured in `pyproject.toml` (under `[tool.gates]`) or `.gates.toml`. Never edit the Python code in `.gates/` to change project behavior.

## Prove the gates still fire

    .gates/tests/prove_gates.sh
SKILLEOF

cat > .cursor/rules/gates.mdc <<'CURSOREOF'
---
description: Repository gates - claim integrity and change safety
alwaysApply: true
---
Facts must be registered in .gates/FACTS.yaml and pass python3 .gates/verify.py
Banned claims listed in that file block commits.
Before changing a working configuration, tag the known-good commit with the proving command in its message.
Gate configuration is declared in pyproject.toml or .gates.toml. Do not edit scripts in .gates/.
The gates are git hooks; they run regardless of which agent is active.
CURSOREOF

cat >> AGENTS.md <<'AGENTSEOF'

## Claim integrity (enforced)
- Every load-bearing number is registered in .gates/FACTS.yaml with a source,
  and pre-commit re-checks it. A number you have not verified does not go into
  an outward-facing document.
- Fabricated claims are banned by pattern. When a wrong number is found in the
  wild, add it to the banned list so it cannot return.
- Third-party attribution is verified against the source system - the issue
  tracker, the log, the registry - never against an earlier draft.

## Change safety
- Before mutating a working system, tag the known-good commit and put the
  command that proves it in the tag message:
  git tag -a known-good-<name> -m "<command that proves it works>"
  Then "it worked before" is a recorded command rather than a memory.

## What else is enforced here

This file does not list the gates. A prose list goes stale the moment a gate
is added or removed, which is the failure the gates exist to prevent. Ask the
repository instead:

    ls .gates/*.py                  what is installed
    python3 .gates/check_version.py whether it is current with the registry
    sh .gates/gates_report.sh       what each one has found
    cat .gates/NOT_ADOPTED          what this repo declines, if anything does

Read a gate's docstring for what it refuses and the incident that produced it.
Every one of them was a rule stated in prose first, and broken anyway.

## Proving the gates
Run .gates/tests/prove_gates.sh - it demonstrates each gate firing.
An untested gate is theatre.

## If you write a check

- Wire it into .githooks/pre-commit in the SAME change. A check nothing runs
  is a file, not a gate.
- Use the standard library only. This repo may have nothing installed.
- Prove it both ways: it fires on a planted violation AND stays quiet on a
  clean tree.
- A gate may not exempt its own file unless there is genuinely nothing there
  to find, and then say so in the code.

## If a gate fires and you think it is wrong

Check its premise before changing anything. A finding can be about the checker
rather than the code - the wrong interpreter, a trigger that means something
narrower than it looks, a probe asserting an old meaning. Establish which,
then fix that.

Never route around it: no `--no-verify`, no `--admin`, no deleting the check.
If the gate is genuinely wrong, fix the gate and prove the fix.

## Documentation Triggers (When to Update README)
Do NOT update the README for internal bug fixes, refactorings, or minor code edits.
Review and update README and agent instructions ONLY when a change crosses an external boundary:
1. CLI / Entrypoints: A command, CLI flag, or runner script is added, renamed, or removed.
2. Dependencies & Toolchain: A dependency, interpreter version, or external tool requirement is changed in pyproject.toml / package.json.
3. Environment & Configuration: A new environment variable, configuration table, or setup prerequisite is introduced.
4. Repository Layout: A top-level directory or primary data pipeline is added, moved, or removed.
If none of these boundaries was crossed, leave the README untouched.
AGENTSEOF

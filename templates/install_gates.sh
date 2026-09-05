#!/bin/sh
# Appends the claim-integrity gate to the project's pre-commit hook and writes
# the agent adapters. Kept in its own file so nested heredocs never collide
# with the generator's own quoting.
set -e

cat >> .githooks/pre-commit <<'GATEHOOK'

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

    .gates/checkpoint.sh save <name> "<command that proves it works>"

The save is refused if the proof fails, so a checkpoint is always known-good.
After changing, run: .gates/checkpoint.sh verify <name>

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
Before changing a working configuration run .gates/checkpoint.sh save <name> "<proof>"
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

## Change safety (enforced)
- Checkpoint before mutating a working system:
  .gates/checkpoint.sh save <name> "<command that proves it works>"
  The save is refused unless the proof passes, so "it worked before" is a
  recorded command, not a memory.

## Proving the gates
Run .gates/tests/prove_gates.sh - it demonstrates each gate firing.
An untested gate is theatre.
AGENTSEOF

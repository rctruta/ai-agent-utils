#!/bin/sh
# survey — run a gate read-only across many repositories and count findings.
#
#   survey.sh <gate> <repo> [repo...]
#   survey.sh no_hardcoding ~/Projects/*
#
# The question "will adopting this gate break anything" answered as a
# measurement rather than a promise. Nothing is written; no repository is
# modified. A gate is copied into a temporary directory inside each repository,
# run, and removed.
#
# Read the counts, then decide per repository: a few findings are worth fixing
# now, many are worth baselining, and a repository with no commits coming is
# worth leaving alone.
set -e
GATE="$1"; shift || true
[ -z "$GATE" ] && { echo "usage: survey.sh <gate> <repo>..." >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/$GATE.py"
[ -f "$SRC" ] || { echo "no such gate: $SRC" >&2; exit 1; }

printf '%-34s %8s  %s\n' "repository" "findings" "state"
printf '%-34s %8s  %s\n' "----------------------------------" "--------" "-----"

for repo in "$@"; do
  [ -d "$repo/.git" ] || continue
  name="$(basename "$repo")"
  tmp="$repo/.gates-survey"
  mkdir -p "$tmp"
  cp "$SRC" "$HERE/_baseline.py" "$tmp/" 2>/dev/null || cp "$SRC" "$tmp/"

  # the gate resolves its root as the parent of its own directory
  out="$(python3 "$tmp/$GATE.py" 2>/dev/null || true)"
  n="$(printf '%s' "$out" | grep -cE '^  [^ ]' || true)"

  if [ -f "$repo/.gates/baseline/$GATE.txt" ]; then state="baselined"
  elif [ -d "$repo/.gates" ];                  then state="gated"
  else                                              state="not adopted"; fi

  printf '%-34s %8s  %s\n' "$name" "$n" "$state"
  rm -rf "$tmp"
done

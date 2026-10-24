#!/bin/sh
# update_gates — bring an existing repository's gates up to date.
#
#   update_gates.sh            copy gates newer than the ones here
#   update_gates.sh --dry      say what would change, write nothing
#
# Gates reach a repository at init time and never again. That is how two gates
# ended up in the seed and in no project at all, including the one they came
# from. This is the path backwards.
#
# Adoption does not fail your build: a gate that can fire on existing code
# supports .gates/baseline/<gate>.txt, so old findings are reported and new ones
# block. See GATES.md.
set -e
SRC="$(cd "$(dirname "$0")/gates" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
DEST="$ROOT/.gates"
DRY=0
[ "$1" = "--dry" ] && DRY=1

HAVE="$([ -f "$DEST/VERSION" ] && cat "$DEST/VERSION" || echo "none")"
WANT="$(cat "$SRC/VERSION")"
echo "gates: this repository has $HAVE, available is $WANT"

# A repository may decline a gate for a reason: rctruta.github.io ships no
# wheel, and verifies its numbers against an external .claims registry, so
# check_wheel, verify and scan are wrong for it. That decision used to live
# nowhere, so this script silently reinstalled all three on the next run --
# the same failure as a gate that was never promoted into the registry, one
# layer down: a decision made in a repository that nothing records.
#
# .gates/NOT_ADOPTED is that record. One basename per line, with the reason
# as a comment, so declining a gate is a line in a diff rather than silence.
DECLINED="$DEST/NOT_ADOPTED"
declined() {
  [ -f "$DECLINED" ] || return 1
  grep -vE '^\s*(#|$)' "$DECLINED" | grep -qxF "$1"
}

changed=0
for f in "$SRC"/*.py "$SRC"/*.sh "$SRC"/VERSION; do
  b="$(basename "$f")"
  [ "$b" = "survey.sh" ] && continue        # a tool for many repos, not for one
  if declined "$b"; then
    # Reinstalling it would overrule a recorded decision; removing a stray
    # copy makes the record true on disk.
    if [ -f "$DEST/$b" ]; then
      echo "  DECLINED $b (in .gates/NOT_ADOPTED) -- removing stray copy"; changed=1
      [ "$DRY" = "1" ] || rm -f "$DEST/$b"
    else
      echo "  DECLINED $b (in .gates/NOT_ADOPTED)"
    fi
    continue
  fi
  if [ ! -f "$DEST/$b" ]; then
    echo "  NEW      $b"; changed=1
    [ "$DRY" = "1" ] || { mkdir -p "$DEST"; cp "$f" "$DEST/$b"; }
  elif ! cmp -s "$f" "$DEST/$b"; then
    echo "  UPDATED  $b"; changed=1
    [ "$DRY" = "1" ] || cp "$f" "$DEST/$b"
  fi
done

# Data files that belong to a gate, not gate code. publish_contract.toml is a
# gate's CONFIGURATION: the registry ships a starter with every surface marked
# `planned`, and each repository then edits it to say what it actually
# publishes. So the rule differs from the .py files -- copied when ABSENT,
# never overwritten.
#
# This was missed entirely at first: the loop above matches *.py, *.sh and
# VERSION, so check_publish_contract.py would have been distributed without the
# contract it reads. A gate arriving without its data is the same silent gap
# this gate exists to catch, one layer up.
for f in "$SRC"/*.toml; do
  [ -f "$f" ] || continue
  b="$(basename "$f")"
  if [ ! -f "$DEST/$b" ]; then
    echo "  NEW      $b (starter; edit it for this repository)"; changed=1
    [ "$DRY" = "1" ] || { mkdir -p "$DEST"; cp "$f" "$DEST/$b"; }
  elif ! cmp -s "$f" "$DEST/$b"; then
    echo "  KEPT     $b (yours; the registry's starter is not copied over it)"
  fi
done

# Gates the registry has retired. Copying forward is not enough: a repository
# keeps running a deleted gate indefinitely, and its hook keeps calling it.
# `for` over a substitution rather than a pipe into `while`: a piped loop runs
# in a subshell, so it cannot set `changed` for the caller.
if [ -f "$SRC/RETIRED" ]; then
  for b in $(grep -vE '^[[:space:]]*(#|$)' "$SRC/RETIRED"); do
    if [ -f "$DEST/$b" ]; then
      echo "  RETIRED  $b (removing; see .pre-commit-config.yaml)"; changed=1
      [ "$DRY" = "1" ] || rm -f "$DEST/$b"
    fi
    # Its baseline goes too. A retired gate's accepted-findings file is a
    # tracked record of paths and values that nothing reads any more, and
    # another check can object to what it contains.
    BL="$DEST/baseline/$(echo "$b" | sed 's/\.py$//').txt"
    if [ -f "$BL" ]; then
      echo "  RETIRED  $(basename "$BL") (its gate is gone)"; changed=1
      [ "$DRY" = "1" ] || { [ "$(git -C "$ROOT" ls-files --error-unmatch "${BL#"$ROOT/"}" 2>/dev/null)" ] \
        && git -C "$ROOT" rm -q "${BL#"$ROOT/"}" || rm -f "$BL"; }
    fi
    if [ -f "$ROOT/.githooks/pre-commit" ] && \
       grep -q "$b" "$ROOT/.githooks/pre-commit"; then
      echo "  ACTION   .githooks/pre-commit still calls $b -- remove that block"
      changed=1
    fi
  done
fi

# The general-purpose checks are declared, not scripted. Copied when absent and
# never overwritten: the `local` section is where a repository's own patterns
# go, and the registry's copy would discard them.
for pair in "pre-commit-config.yaml:.pre-commit-config.yaml" "ruff.toml:ruff.toml" "gitleaks.toml:.gitleaks.toml"; do
  from="$SRC/../$(echo "$pair" | cut -d: -f1)"
  to="$ROOT/$(echo "$pair" | cut -d: -f2)"
  [ -f "$from" ] || continue
  if [ ! -f "$to" ]; then
    echo "  NEW      $(basename "$to")"; changed=1
    [ "$DRY" = "1" ] || cp "$from" "$to"
  elif ! cmp -s "$from" "$to"; then
    echo "  KEPT     $(basename "$to") (yours; the registry's copy is not forced over it)"
  fi
done

if [ -d "$SRC/tests" ] && [ "$DRY" = "0" ]; then
  mkdir -p "$DEST/tests" && cp "$SRC"/tests/*.sh "$DEST/tests/" 2>/dev/null || true
fi

[ "$changed" = "0" ] && { echo "  already current"; exit 0; }

if [ "$DRY" = "1" ]; then
  echo "  (dry run — nothing written)"
  exit 0
fi

chmod +x "$DEST"/*.py "$DEST"/*.sh "$DEST"/tests/*.sh 2>/dev/null || true
cat <<'NEXT'

Next, in this order:

  1. Run each new gate once, bare, to see what it finds here.
  2. If the findings predate the gate, accept them:  .gates/<gate>.py --baseline
     Commit the baseline. It may shrink later; it may never grow.
  3. Prove the set still fires:                      sh .gates/tests/prove_gates.sh
  4. Add the new gates to .githooks/pre-commit if they are not there yet.
NEXT

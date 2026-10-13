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

changed=0
for f in "$SRC"/*.py "$SRC"/*.sh "$SRC"/VERSION; do
  b="$(basename "$f")"
  [ "$b" = "survey.sh" ] && continue        # a tool for many repos, not for one
  if [ ! -f "$DEST/$b" ]; then
    echo "  NEW      $b"; changed=1
    [ "$DRY" = "1" ] || { mkdir -p "$DEST"; cp "$f" "$DEST/$b"; }
  elif ! cmp -s "$f" "$DEST/$b"; then
    echo "  UPDATED  $b"; changed=1
    [ "$DRY" = "1" ] || cp "$f" "$DEST/$b"
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

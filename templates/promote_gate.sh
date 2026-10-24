#!/bin/sh
# promote_gate — move a gate that was born in a project INTO the registry.
#
#   templates/promote_gate.sh ~/Projects/some-repo/tools/check_thing.py
#   templates/promote_gate.sh <path> --dry      say what would happen, write nothing
#
# The direction nothing covered. update_gates.sh carries gates OUT of the
# registry into a repository. Nothing carried one back IN, so a gate written
# where a problem actually surfaced stayed in that one repository -- proven in
# both directions, wired into a hook, and absent from templates/gates/, from
# prove_gates.sh, and from the GATES.md registry, so
# check_version.py reported both repositories as version 2 while they ran gates
# the registry had never heard of. Discovered, proved, used -- and not
# persistent. That is the failure this closes.
#
# It REFUSES rather than reminds, and refuses BEFORE copying anything. A gate
# arrives in the registry only once its probe and its registry row already
# exist, which forces the order of work:
#
#   1. write the gate, in the repo where the problem surfaced
#   2. add a probe to templates/gates/tests/prove_gates.sh -- BOTH directions:
#      it fires on a planted violation, and stays quiet on a clean tree
#   3. add a row to the registry table in GATES.md, naming the failure mode
#   4. run this
#   5. survey.sh before adopting anywhere; update_gates.sh to distribute
#
# Steps 2 and 3 are where this has been breaking. A gate whose reason is not
# written down is the first one somebody deletes, and an unproven gate is
# theatre -- so neither is a follow-up.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
REG="$HERE/gates"
PROVE="$REG/tests/prove_gates.sh"
DOC="$(cd "$HERE/.." && pwd)/GATES.md"
VERSION_FILE="$REG/VERSION"

SRC="$1"
DRY=""
[ "$2" = "--dry" ] && DRY=1

if [ -z "$SRC" ]; then
  echo "usage: promote_gate.sh <path-to-gate> [--dry]" >&2
  exit 2
fi
if [ ! -f "$SRC" ]; then
  echo "promote_gate: $SRC is not a file" >&2
  exit 2
fi

NAME="$(basename "$SRC")"
case "$NAME" in
  *.py|*.sh) ;;
  *) echo "promote_gate: $NAME is not a .py or .sh gate" >&2; exit 2 ;;
esac

FAIL=0

# 1. The probe. Both directions, which is why the grep is for the name and the
#    author still has to have written a real case -- this cannot check that the
#    probe is honest, only that it exists.
if ! grep -q "$NAME" "$PROVE" 2>/dev/null; then
  echo "REFUSED: tests/prove_gates.sh has no probe mentioning $NAME." >&2
  echo "         An untested gate is theatre. Add a case that fires on a" >&2
  echo "         planted violation AND stays quiet on a clean tree." >&2
  FAIL=1
fi

# 2. The registry row, which is the gate's reason. GATES.md's table is
#    `gate | refuses | the failure mode`: refuses is what it blocks, the
#    failure mode is why that is worth blocking.
# The optional leading `N |` is the table's index column. Without allowing for
# it this refuses every gate already in the table, because the name is not in
# the first cell.
if ! grep -qE "^\|([[:space:]]*[0-9]+[[:space:]]*\|)?[[:space:]]*\`?(tests/)?$NAME\`?[[:space:]]*\|" "$DOC" 2>/dev/null; then
  echo "REFUSED: GATES.md has no registry row for $NAME." >&2
  echo "         Add one: | \`$NAME\` | what it refuses | the failure mode |" >&2
  echo "         A gate whose reason has been forgotten is the first one" >&2
  echo "         somebody deletes." >&2
  FAIL=1
fi

[ "$FAIL" = "1" ] && exit 1

# A gate authored directly in templates/gates/ needs no copy, but it still
# needs the version bump -- otherwise check_version.py reports every repository
# as current and nothing is ever told to update: for a gate authored here the
# prerequisites pass, the copy is a no-op, and VERSION silently stays put.
if [ -f "$REG/$NAME" ] && cmp -s "$SRC" "$REG/$NAME"; then
  if [ "$3" = "--bump" ] || [ "$2" = "--bump" ]; then
    OLD="$(cat "$VERSION_FILE" 2>/dev/null || echo 0)"
    NEW=$((OLD + 1))
    printf '%s\n' "$NEW" > "$VERSION_FILE"
    echo "$NAME already in the registry and identical; VERSION $OLD -> $NEW"
  else
    echo "promote_gate: $NAME is already in the registry and identical."
    echo "  Its probe and registry row are present, so nothing was copied."
    echo "  If it is newly registered, bump so repositories are told to update:"
    echo "    sh $0 $SRC --bump"
    exit 0
  fi
else

OLD="$(cat "$VERSION_FILE" 2>/dev/null || echo 0)"
NEW=$((OLD + 1))

if [ -n "$DRY" ]; then
  echo "would copy   $SRC"
  echo "          -> $REG/$NAME"
  [ -f "$REG/$NAME" ] && echo "             (replacing the existing copy)"
  echo "would bump   VERSION $OLD -> $NEW"
  exit 0
fi

  cp "$SRC" "$REG/$NAME"
  chmod +x "$REG/$NAME"
  printf '%s\n' "$NEW" > "$VERSION_FILE"
  echo "promoted $NAME into the registry; VERSION $OLD -> $NEW"
fi
echo
echo "Next, in this order:"
echo
echo "  1. Prove it where the gates are INSTALLED, not here. prove_gates.sh"
echo "     resolves its gate directory as \$ROOT/.gates relative to itself, so"
echo "     run from the registry it skips every probe and reports success on"
echo "     nothing. Any repository carrying .gates/ will do:"
echo
echo "       cd <a repo with .gates/> && sh .gates/tests/prove_gates.sh"
echo
echo "  2. Survey before adopting. Read-only, counts what it would find:"
echo
echo "       sh $REG/survey.sh ${NAME%.*} ~/Projects/*"
echo
echo "  3. Distribute, in each repository that should carry it:"
echo
echo "       sh $HERE/update_gates.sh"
echo
echo "Do not retrofit it into a dormant repository. A gate on something with no"
echo "commits coming is pure cost."

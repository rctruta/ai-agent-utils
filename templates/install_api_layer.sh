#!/bin/sh
# install_api_layer — add the analysis layer to a project past the trigger.
#
#   install_api_layer.sh          copy the skeletons into ./api/
#   install_api_layer.sh --dry    say what would change, write nothing
#
# Deliberately NOT part of init-agent-project. See templates/api/README.md:
# an empty stub in every repository is dead weight, and dead weight gets
# deleted. Install this once a corpus has been asked a question twice.
set -e
SRC="$(cd "$(dirname "$0")/api" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
DEST="$ROOT/api"
DRY=0
[ "$1" = "--dry" ] && DRY=1

if [ -d "$DEST" ]; then
    echo "$DEST already exists; not overwriting. Compare by hand:"
    echo "  diff -r $SRC $DEST"
    exit 1
fi
if [ "$DRY" = "1" ]; then
    echo "would create $DEST from $SRC:"
    find "$SRC" -type f | sed "s|$SRC|  api|"
    exit 0
fi
mkdir -p "$DEST"
cp -R "$SRC/." "$DEST/"
echo "installed the analysis layer into $DEST"
echo "Next: fill in catalog.py, then operations.py, then metrics.py."
echo "Read $DEST/README.md first -- the order matters."

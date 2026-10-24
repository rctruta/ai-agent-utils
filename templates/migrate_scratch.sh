#!/bin/sh
# migrate_scratch — move a directory outside the worktree, so git cannot
# stage it at all.
#
#   migrate_scratch.sh ~/Projects/some-repo                 notes (default)
#   migrate_scratch.sh ~/Projects/some-repo --dir private   private material
#   migrate_scratch.sh ~/Projects/some-repo --dry           say what it would do
#
# --dir generalises this to any directory that must never be committable.
# `scratch` is notes; `private` is material that is kept in git somewhere but
# must not be in THIS repository. The arrangement is identical and so is the
# guarantee, so there is one script rather than two that drift.
#
# Turns an in-worktree `scratch/` into a symlink pointing at
# $AGENT_NOTES_ROOT/<repo> (default ~/scratch/<repo>), so git stops being able
# to stage its contents at all. See .gates/scratch_external.py for why a
# .gitignore line was not enough: it is consulted only for files git does not
# already track, so a repository can keep `scratch/` ignored and a draft
# tracked at the same path indefinitely.
#
# Idempotent and non-destructive: it MOVES files, never deletes them, refuses
# to overwrite an existing note of the same name, and leaves a repository that
# is already arranged correctly untouched. Untracking is reported per file,
# because `git rm --cached` is a commit the author has to make and explain.
set -e

REPO="$1"
DRY=""
CREATE=""
DIRNAME="scratch"
NEXT_IS_DIR=""
for A in "$@"; do
  if [ -n "$NEXT_IS_DIR" ]; then DIRNAME="$A"; NEXT_IS_DIR=""; continue; fi
  [ "$A" = "--dir" ] && NEXT_IS_DIR=1
  [ "$A" = "--dry" ] && DRY=1
  # Without this, running the script across a Projects directory creates a
  # notes folder and edits .gitignore in every dormant repo and scratch test
  # project in it -- 37 of 44 on the first dry run. A gate that treats an
  # absent scratch as clean should not have a migration that manufactures one.
  [ "$A" = "--create" ] && CREATE=1
done

if [ -z "$REPO" ]; then
  echo "usage: migrate_scratch.sh <path-to-repo> [--dry]" >&2
  exit 2
fi
if [ ! -d "$REPO/.git" ] && [ ! -f "$REPO/.git" ]; then
  echo "migrate_scratch: $REPO is not a git repository" >&2
  exit 2
fi

REPO="$(cd "$REPO" && pwd)"
NAME="$(basename "$REPO")"
SRC_PROBE="$REPO/$DIRNAME"

# Nothing to migrate and not asked to create: say so and leave.
if [ ! -e "$SRC_PROBE" ] && [ ! -L "$SRC_PROBE" ] && [ -z "$CREATE" ] \
   && [ -z "$(cd "$REPO" && git ls-files "$DIRNAME")" ]; then
  echo "$NAME: no $DIRNAME folder; nothing to do (--create to make one)"
  exit 0
fi
# One root per kind. Notes and private material do not share a directory:
# ~/scratch is routinely opened and read aloud; ~/private is not.
if [ "$DIRNAME" = "scratch" ]; then
  ROOT="${AGENT_NOTES_ROOT:-$HOME/scratch}"
else
  ROOT="${AGENT_PRIVATE_ROOT:-$HOME/private}"
fi
DEST="$ROOT/$NAME"
SRC="$REPO/$DIRNAME"

say() { echo "  $1"; }
run() { [ -n "$DRY" ] && say "would: $*" || eval "$@"; }

echo "$NAME"

# 1. Already a symlink outside the worktree? Nothing to move.
if [ -L "$SRC" ]; then
  TARGET="$(cd "$(dirname "$SRC")" && cd "$(readlink "$SRC")" 2>/dev/null && pwd || true)"
  case "$TARGET" in
    "$REPO"|"$REPO"/*)
      say "$DIRNAME is a symlink pointing INSIDE the worktree; repointing" ;;
    "")
      say "$DIRNAME is a dangling symlink; replacing" ;;
    *)
      say "already external -> $TARGET"
      SKIP_MOVE=1 ;;
  esac
fi

# 2. Untrack anything git is carrying under scratch. This is the leak, and it
#    is the one step that changes the repository's history-to-be, so it is
#    staged and reported rather than committed here.
TRACKED="$(cd "$REPO" && git ls-files "$DIRNAME")"
if [ -n "$TRACKED" ]; then
  echo "$TRACKED" | while read -r F; do
    say "untracking: $F"
  done
  [ -z "$DRY" ] && (cd "$REPO" && echo "$TRACKED" | tr '\n' '\0' | xargs -0 git rm -q --cached --) || true
  say "staged as deletions -- commit them, then decide about history separately"
fi

# 3. Move the contents out. Never overwrite: a collision means two different
#    notes share a name, and only the author knows which one matters.
if [ -z "$SKIP_MOVE" ] && [ -d "$SRC" ]; then
  run "mkdir -p '$DEST'"
  COUNT=0
  for F in "$SRC"/* "$SRC"/.[!.]*; do
    [ -e "$F" ] || continue
    B="$(basename "$F")"
    if [ -e "$DEST/$B" ]; then
      say "SKIPPED (name already taken in $DEST): $B"
      continue
    fi
    run "mv '$F' '$DEST/$B'"
    COUNT=$((COUNT + 1))
  done
  say "moved $COUNT entr(y|ies) -> $DEST"
  # Only remove the directory if it is now empty; a leftover means a collision
  # above, and silently discarding it would be the exact failure this guards.
  if [ -z "$DRY" ]; then
    if rmdir "$SRC" 2>/dev/null; then
      ln -s "$DEST" "$SRC"
      say "$DIRNAME -> $DEST"
    else
      say "REFUSED to replace $SRC: not empty (see SKIPPED above). Resolve, re-run."
      exit 1
    fi
  else
    say "would: rmdir $DIRNAME && ln -s '$DEST' $DIRNAME"
  fi
elif [ ! -e "$SRC" ] && [ ! -L "$SRC" ]; then
  run "mkdir -p '$DEST'"
  [ -z "$DRY" ] && ln -s "$DEST" "$SRC" || say "would: ln -s '$DEST' $DIRNAME"
  say "no $DIRNAME here; created the arrangement"
elif [ -n "$SKIP_MOVE" ]; then
  :
fi

# 4. The ignore rule still matters -- not for the notes, which git can no
#    longer reach, but for the symlink itself, which `git add -A` would
#    otherwise commit as a 60-byte pointer publishing where the notes live.
GI="$REPO/.gitignore"
if ! (cd "$REPO" && git check-ignore -q "$DIRNAME" 2>/dev/null); then
  if [ -n "$DRY" ]; then
    say "would: append '$DIRNAME' to .gitignore"
  else
    printf '\n# A symlink outside the worktree; git cannot stage through it.\n# See .gates/scratch_external.py\n%s\n' "$DIRNAME" >> "$GI"
    say "added $DIRNAME to .gitignore"
  fi
fi

echo

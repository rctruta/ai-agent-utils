#!/bin/sh
# checkpoint — record a known-good state BEFORE mutating a working system,
# so "it worked yesterday" is a file, not a memory.
#
# The failure this exists for: a working configuration is changed, the change
# makes it worse, and nobody recorded what "working" looked like.
#
#   .gates/checkpoint.sh save   <name> "<command that proves it works>"
#   .gates/checkpoint.sh verify <name>     re-run the proof; 0 = still good
#   .gates/checkpoint.sh list
#   .gates/checkpoint.sh show   <name>
#
# Agent-agnostic: POSIX sh, no dependencies.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/.gates/checkpoints"
LEDGER="$ROOT/.gates/ledger.jsonl"
mkdir -p "$DIR"

ts()  { date -u +%Y-%m-%dT%H:%M:%SZ; }
sha() { git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "no-git"; }

log() {
  printf '{"ts":"%s","gate":"checkpoint","action":"%s","name":"%s","commit":"%s","result":"%s"}\n' \
    "$(ts)" "$1" "$2" "$(sha)" "$3" >> "$LEDGER"
}

case "$1" in
  save)
    [ -z "$2" ] && { echo "usage: checkpoint.sh save <name> \"<proof command>\"" >&2; exit 1; }
    NAME="$2"; PROOF="$3"
    [ -z "$PROOF" ] && { echo "Refusing: a checkpoint needs a command that PROVES the state is good." >&2; exit 1; }
    if ! sh -c "$PROOF" >"$DIR/$NAME.proof.out" 2>&1; then
      echo "Refusing to save '$NAME': the proof command FAILED, so this state is not known-good." >&2
      echo "  proof: $PROOF" >&2
      sed -n '1,10p' "$DIR/$NAME.proof.out" >&2
      log save "$NAME" refused
      exit 1
    fi
    printf '%s\n' "$PROOF" > "$DIR/$NAME.proof"
    printf 'saved %s at commit %s\n' "$(ts)" "$(sha)" > "$DIR/$NAME.meta"
    echo "Checkpoint '$NAME' saved. Proof passed and is recorded."
    log save "$NAME" ok
    ;;
  verify)
    [ -z "$2" ] && { echo "usage: checkpoint.sh verify <name>" >&2; exit 1; }
    NAME="$2"
    [ -f "$DIR/$NAME.proof" ] || { echo "No checkpoint named '$NAME'." >&2; exit 1; }
    PROOF="$(cat "$DIR/$NAME.proof")"
    if sh -c "$PROOF" >/dev/null 2>&1; then
      echo "'$NAME' still good."; log verify "$NAME" pass
    else
      echo "'$NAME' NO LONGER PASSES its own proof:" >&2
      echo "  proof: $PROOF" >&2
      echo "  saved: $(cat "$DIR/$NAME.meta" 2>/dev/null)" >&2
      log verify "$NAME" fail
      exit 1
    fi
    ;;
  list)
    ls "$DIR" 2>/dev/null | sed 's/\.proof$//' | grep -v '\.' | sort -u || echo "(none)"
    ;;
  show)
    NAME="$2"; cat "$DIR/$NAME.meta" 2>/dev/null; echo "proof: $(cat "$DIR/$NAME.proof" 2>/dev/null)"
    ;;
  *)
    echo "usage: checkpoint.sh {save|verify|list|show}" >&2; exit 1 ;;
esac

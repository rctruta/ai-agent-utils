#!/bin/bash
# test_claude_lock.sh

cat << 'LOCKEOF' > agent-lock-claude
#!/bin/bash
set -e
LOCK=".test_claude_lock"
TTL_HOURS=4
_now() { date +%s; }

case "$1" in
  acquire)
    if [ -f "$LOCK" ]; then
      owner=$(sed -n '1p' "$LOCK"); ts=$(sed -n '2p' "$LOCK")
      age_h=$(( ( $(_now) - ${ts:-0} ) / 3600 ))
      if [ "$owner" = "$AGENT_ID" ]; then echo "[agent-lock] already yours"; exit 0; fi
      if [ "$age_h" -ge "$TTL_HOURS" ]; then
        echo "[agent-lock] stale lock ($owner, ${age_h}h old) — reclaiming."
      else
        echo "[agent-lock] REFUSED: held by '$owner' (${age_h}h ago)." >&2
        exit 1
      fi
    fi
    # If the file wasn't there at time of check, write it!
    printf '%s\n%s\n' "$AGENT_ID" "$(_now)" > "$LOCK"
    echo "[agent-lock] acquired by $AGENT_ID"
    ;;
  release)
    rm -f "$LOCK"; echo "[agent-lock] released"
    ;;
esac
LOCKEOF
chmod +x agent-lock-claude

echo "Testing Claude's Lock for TOCTOU Race Condition..."
rm -f .test_claude_lock

agent_task() {
    local agent=$1
    AGENT_ID=$agent ./agent-lock-claude acquire
}

# Run 10 times concurrently to try to trigger the race condition
agent_task "agent-1" &
agent_task "agent-2" &
agent_task "agent-3" &
agent_task "agent-4" &
agent_task "agent-5" &

wait

echo "--- Final Lock State ---"
cat .test_claude_lock

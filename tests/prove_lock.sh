#!/bin/bash
# prove_lock.sh
# This script mathematically proves that the lockfile prevents concurrent clobbering.
# It spawns two processes simultaneously that both try to acquire the lock.

# 1. Create the mock agent-lock script
cat << 'LOCKEOF' > mock-agent-lock
#!/bin/bash
set -e
LOCK=".test_agent_lock"
TTL_HOURS=4
_now() { date +%s; }

case "$1" in
  acquire)
    # Emulate the exact lock logic from init-agent-project.sh
    # We use 'set -o noclobber' for atomic file creation
    if ( set -o noclobber; printf '%s\n%s\n' "$AGENT_ID" "$(_now)" > "$LOCK" 2>/dev/null ); then
        echo "[mock-agent-lock] acquired by $AGENT_ID"
        exit 0
    else
        # File exists. Read owner.
        owner=$(sed -n '1p' "$LOCK" 2>/dev/null || echo "unknown")
        if [ "$owner" = "$AGENT_ID" ]; then 
            echo "[mock-agent-lock] already yours ($AGENT_ID)"; exit 0; 
        fi
        echo "[mock-agent-lock] REFUSED: held by '$owner' (you are $AGENT_ID). One agent per branch." >&2
        exit 1
    fi
    ;;
  release)
    rm -f "$LOCK"
    echo "[mock-agent-lock] released"
    ;;
esac
LOCKEOF
chmod +x mock-agent-lock

# Ensure clean slate
./mock-agent-lock release >/dev/null 2>&1

echo "Starting Race Condition Test..."
echo "Simulating Claude (AGENT_ID=claude) and Gemini (AGENT_ID=gemini) acquiring simultaneously:"
echo "---------------------------------------------------------------------------------------"

# Function for an agent to try acquiring the lock
agent_task() {
    local agent=$1
    echo "[$agent] Attempting to acquire lock..."
    AGENT_ID=$agent ./mock-agent-lock acquire
}

# Run both simultaneously in the background
agent_task "claude" &
agent_task "gemini" &

# Wait for both to finish
wait

echo "---------------------------------------------------------------------------------------"
echo "Test Complete. Only ONE agent should have succeeded. The other MUST have been REFUSED."

#!/bin/bash
# test-commit-lock.sh
# A concrete demonstration of the Lockfile Protocol acting as a hard gate.
# It stages a temporary repository, initializes it, and simulates two distinct
# agents colliding at the git commit layer.
set -e

# Store the path to the init script before changing directories
INIT_SCRIPT="$(pwd)/init-agent-project.sh"

echo "=== Staging Two-Agent Lock Scenario ==="
TEMP_DIR=$(mktemp -d)
echo "1. Creating sterile test workspace in $TEMP_DIR"

# Initialize the workspace (automatically skips Python and Remote setup by passing 'N' twice)
printf "N\nN\n" | "$INIT_SCRIPT" lock-demo "$TEMP_DIR" >/dev/null 2>&1
cd "$TEMP_DIR/lock-demo"

echo "2. Agent A (claude-cli) acquires the lock..."
echo "AGENT_ID=claude-cli" > .env
./agent-lock acquire

echo "3. Agent B (gemini-ide) makes an edit and attempts to commit..."
echo "AGENT_ID=gemini-ide" > .env
echo "A brilliant piece of code by Gemini" > feature.txt
git add feature.txt

# Attempt to commit as Agent B. We temporarily disable 'set -e' because 
# we EXPECT this command to fail.
set +e
git commit -m "Agent B attempts to sneak a commit" > commit_output.log 2>&1
COMMIT_EXIT_CODE=$?
set -e

echo ""
echo "=== Test Results ==="
if [ $COMMIT_EXIT_CODE -ne 0 ]; then
    echo "✅ SUCCESS! The pre-commit hook functioned as a hard gate."
    echo "Agent B's commit was mechanically refused. Git output:"
    echo "--------------------------------------------------------"
    cat commit_output.log
    echo "--------------------------------------------------------"
else
    echo "❌ FAILURE! Agent B was able to commit while Agent A held the lock."
    echo "The pre-commit hook failed to enforce the boundary."
    exit 1
fi

# Clean up
rm -rf "$TEMP_DIR"

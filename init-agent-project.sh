#!/bin/bash
# init-agent-project.sh
# Initializes a secure workspace for human-agent collaboration.
#
# Design principle: GATES, NOT WORDS. Anything the agent MUST or MUST NOT do
# is enforced by a hook or a script that aborts the operation — never by a
# sentence in a document the agent may not read (or may read and ignore).
set -e

# --- 0. Preflight: fail early, not half-provisioned -------------------------
# With `set -e`, a missing tool mid-run leaves a half-initialized directory.
# Check the hard dependency (git) up front; uv is checked only if needed.
if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is required but not found on PATH." >&2
  exit 1
fi

if [ -z "$1" ]; then
  echo "Error: Project name required."
  echo "Usage: ./init-agent-project.sh <project_name> [root_directory]"
  exit 1
fi

PROJECT_NAME=$1
ROOT_DIR=${2:-$HOME/Projects}

# 1. Ensure Root Directory Exists
if [ ! -d "$ROOT_DIR" ]; then
  echo "=> Root directory $ROOT_DIR does not exist. Creating it."
  mkdir -p "$ROOT_DIR"
fi

cd "$ROOT_DIR"
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"

echo "Initializing Agentic Workspace: $PROJECT_NAME"

# 2. Interactive Python Check
read -p "Is this a Python project? [y/N] " IS_PYTHON
IS_PYTHON=${IS_PYTHON:-N}

# Fail early if Python was requested but uv is missing.
if [[ "$IS_PYTHON" =~ ^[Yy]$ ]] && ! command -v uv >/dev/null 2>&1; then
  echo "Error: Python project requested but 'uv' is not on PATH." >&2
  echo "  Install uv (https://docs.astral.sh/uv/) or answer 'N'." >&2
  exit 1
fi

# 3. Create AGENTS.md (The Universal Contract)
cat << 'EOF' > AGENTS.md
# AGENTS.md

Shared contract for every autonomous agent that touches this repository.
The human user is the owner; agents are delegates.

**These are gates, not vows.** Where this document states a rule, a hook or
script enforces it — because instructions drift and gates hold. If a rule
here is NOT backed by a mechanism, treat it as a courtesy, not a guarantee.

---

## 1. The Lockfile Protocol (Traffic Control) — ENFORCED by `.githooks/pre-commit`
Agents CANNOT see each other's unpushed, uncommitted local edits. To prevent
concurrent modification, this repo enforces one lock holder at a time.

**Before starting any task that writes files:**
```bash
./agent-lock acquire
```
- If another live agent holds the lock, `acquire` refuses and exits non-zero.
- The `pre-commit` hook independently REFUSES any commit while a foreign lock
  is held — so an agent that skips this step still cannot commit over you.

**When you finish and have pushed:**
```bash
./agent-lock release
```

Distinct identity per agent: set `AGENT_ID` (e.g. `AGENT_ID=claude-term`,
`AGENT_ID=gemini-ide`) so two agents in the SAME clone are told apart. Without
distinct IDs the lock degrades to a shared-identity speed bump (see README
"Honest scope"). A crashed agent's lock auto-expires after 4h so no deadlock.

## 2. The One Rule: Main is the Truth
`origin/main` is the only source of truth. Any state that lives only on your
local machine is invisible to your counterpart.

### At the start of every turn that will modify files
```bash
git pull origin main
```

### At the end of every turn that created or modified files
```bash
git add -A
git commit -m "clear message"
git push origin main
```
In the **same turn** as the change — not "later," not "when I'm done for the
day."

## 3. Never leave state behind — ENFORCED by `.githooks/pre-push`
`git status` at the end of your turn must be clean. Untracked files are not
"in progress" — they're invisible. Commit it or delete it; there is no third
state. The pre-push hook refuses to push a dirty tree.

## 4. No agent attribution in commits
Do NOT add `Co-authored-by:` trailers, "Generated with <agent>" lines, or any
agent attribution to commit messages or PR descriptions. The human owns the
history.

## 5. Do not bypass the gates
Never use `git push --no-verify`, `git commit --no-verify`, or
`gh pr merge --admin` to route around a failing hook or check. A red gate
means fix the cause. Bypassing is the single most damaging move an agent can
make (see README "The Rogue Agent Lesson"). The remote branch-protection
layer exists precisely to catch this.
EOF

# 4. Setup Environment Variables
cat << 'EOF' > .env.example
# Give each agent a DISTINCT id so the lockfile can tell them apart.
AGENT_ID=
GEMINI_API_KEY=
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
EOF
cp .env.example .env

# 5. The agent-lock helper (turns the protocol from prose into a command) -----
cat << 'LOCKEOF' > agent-lock
#!/bin/bash
# agent-lock — cooperative one-agent-at-a-time lock, with liveness.
# Enforced by .githooks/pre-commit. Usage: ./agent-lock {acquire|release|status}
set -e
LOCK=".agent_lock"
TTL_HOURS=4
_me() { echo "${AGENT_ID:-$(git config user.email 2>/dev/null || whoami)}@$(hostname)"; }
_now() { date +%s; }

case "$1" in
  acquire)
    if [ -f "$LOCK" ]; then
      owner=$(sed -n '1p' "$LOCK"); ts=$(sed -n '2p' "$LOCK")
      age_h=$(( ( $(_now) - ${ts:-0} ) / 3600 ))
      if [ "$owner" = "$(_me)" ]; then echo "[agent-lock] already yours"; exit 0; fi
      if [ "$age_h" -ge "$TTL_HOURS" ]; then
        echo "[agent-lock] stale lock ($owner, ${age_h}h old) — reclaiming."
      else
        echo "[agent-lock] REFUSED: held by '$owner' (${age_h}h ago). One agent per branch." >&2
        exit 1
      fi
    fi
    printf '%s\n%s\n' "$(_me)" "$(_now)" > "$LOCK"
    echo "[agent-lock] acquired by $(_me)"
    ;;
  release)
    if [ -f "$LOCK" ] && [ "$(sed -n '1p' "$LOCK")" != "$(_me)" ]; then
      echo "[agent-lock] REFUSED: lock held by someone else; not releasing." >&2
      exit 1
    fi
    rm -f "$LOCK"; echo "[agent-lock] released"
    ;;
  status)
    if [ -f "$LOCK" ]; then
      echo "[agent-lock] held by $(sed -n '1p' "$LOCK") since $(date -r "$(sed -n '2p' "$LOCK")" 2>/dev/null || echo '?')"
    else
      echo "[agent-lock] free"
    fi
    ;;
  *) echo "usage: ./agent-lock {acquire|release|status}"; exit 2 ;;
esac
LOCKEOF
chmod +x agent-lock

# 6. Create Hooks --------------------------------------------------------------
mkdir -p .githooks

# 6a. pre-commit: enforce the lock (the gate that makes §1 real).
cat << 'EOF' > .githooks/pre-commit
#!/bin/bash
# Enforce the agent lock: refuse a commit while a FOREIGN lock is held.
# This is what turns the Lockfile Protocol from prose into a gate.
set -e
LOCK=".agent_lock"
[ -f "$LOCK" ] || exit 0   # no lock held → nothing to enforce
owner=$(sed -n '1p' "$LOCK" 2>/dev/null)
me="${AGENT_ID:-$(git config user.email 2>/dev/null || whoami)}@$(hostname)"
if [ "$owner" != "$me" ]; then
    echo "[pre-commit] REFUSING COMMIT: .agent_lock held by '$owner' (you are '$me')." >&2
    echo "  Another agent is working. Run './agent-lock status', or set a distinct" >&2
    echo "  AGENT_ID if you ARE a second agent. See AGENTS.md." >&2
    exit 1
fi
EOF

# 6b. pre-push: refuse a dirty tree (and, for Python, a red test suite).
# NOTE: git hooks are bypassable with --no-verify. This is layer 1 (honest
# mistakes + non-adversarial agents). Layer 2 is remote branch protection —
# see the README. Do not sell this hook as unbypassable.
cat << 'EOF' > .githooks/pre-push
#!/bin/bash
# Enforce dirty-tree policy and (for Python) the test gate.
# Layer 1 of 2. Bypassable locally with --no-verify; remote branch protection
# is the backstop. See README "The Rogue Agent Lesson".
set -e

ROOT="$(git rev-parse --show-toplevel)"

if [ -n "$(git status --porcelain)" ]; then
    echo "[pre-push] REFUSING PUSH: working tree has uncommitted or untracked files" >&2
    echo "  Commit your changes or delete untracked files before pushing." >&2
    exit 1
fi
EOF

# 7. Python-Specific Setup
if [[ "$IS_PYTHON" =~ ^[Yy]$ ]]; then
  echo "Setting up Python boundaries..."

  # Append pytest check to the pre-push hook
  cat << 'EOF' >> .githooks/pre-push

PY="$ROOT/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3 || true)"

if [ -x "$PY" ]; then
    echo "[pre-push] running full test suite..."
    if ! "$PY" -m pytest tests/ -q --no-header; then
        echo "" >&2
        echo "[pre-push] REFUSING PUSH: test suite is red." >&2
        exit 1
    fi
fi
EOF

  # VS Code settings — committed on purpose (see .gitignore un-ignore below),
  # so the interpreter pin reaches every clone and every agent.
  mkdir -p .vscode
  cat << 'EOF' > .vscode/settings.json
{
    "python.defaultInterpreterPath": "${workspaceFolder}/.venv/bin/python",
    "python.terminal.activateEnvironment": true,
    "python.testing.pytestEnabled": true
}
EOF

  # Pytest structure
  mkdir tests
  touch tests/__init__.py
  cat << 'EOF' > tests/test_basic.py
def test_environment_initialized():
    assert True
EOF

  cat << 'EOF' > requirements.txt
pytest
EOF

  # Venv initialization
  echo "Creating uv venv..."
  uv venv
  source .venv/bin/activate
  uv pip install -r requirements.txt
fi

chmod +x .githooks/pre-commit .githooks/pre-push

# 8. Git Setup ----------------------------------------------------------------
# .vscode is ignored EXCEPT settings.json — the interpreter pin is the whole
# point of provisioning it, so it must be committed and shared, not local-only.
cat << 'EOF' > .gitignore
.venv/
.env
__pycache__/
*.pyc
.pytest_cache/
.vscode/*
!.vscode/settings.json
.agent_lock
EOF

git init -q
git config core.hooksPath .githooks
git add .
git commit -q -m "chore: initialized secure agent workspace"

echo "✅ Workspace initialized successfully."
echo "   AGENTS.md contract created (rules are hook-enforced)."
echo "   .githooks/pre-commit installed (lockfile gate)."
echo "   .githooks/pre-push installed (dirty-tree + test gate; layer 1 of 2)."
echo "   ./agent-lock helper installed."
echo ""
echo "Next: create the remote, push main, then enable BRANCH PROTECTION"
echo "(Require PR + Require status checks + Include administrators) — layer 2."

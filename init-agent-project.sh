#!/bin/bash
# init-agent-project.sh
# Initializes a secure workspace for human-agent collaboration.
set -e

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

# 3. Create AGENTS.md (The Universal Contract)
cat << 'EOF' > AGENTS.md
# AGENTS.md

Shared contract for every autonomous agent that touches this repository.
The human user is the owner; agents are delegates. 

---

## 1. The Lockfile Protocol (Traffic Control)
Agents CANNOT see each other's unpushed, uncommitted local edits. To prevent catastrophic concurrent modification:
**Before starting any task, check for `.agent_lock` in the root directory.**
- If `.agent_lock` exists: STOP IMMEDIATELY. Another agent is working. Tell the user you cannot proceed.
- If it does not exist: Create `.agent_lock` before you write any code.
- When you finish your turn and push your commits, DELETE `.agent_lock`.

## 2. The One Rule: Main is the Truth
`origin/main` is the only source of truth. Any state that lives only on your local machine is invisible to your counterpart.

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
In the **same turn** as the change — not "later," not "when I'm done for the day."

## 3. Never leave state behind
`git status` at the end of your turn should be clean. Untracked files are not "in progress" — they're invisible. If the file is worth keeping, commit it. If it's not, delete it. There is no third state.
EOF

# 4. Setup Environment Variables
cat << 'EOF' > .env.example
GEMINI_API_KEY=
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
EOF
cp .env.example .env

# 5. Create Pre-Push Hook
mkdir -p .githooks
cat << 'EOF' > .githooks/pre-push
#!/bin/bash
# Enforce dirty tree policy and testing gates.
set -e

ROOT="$(git rev-parse --show-toplevel)"

if [ -n "$(git status --porcelain)" ]; then
    echo "[pre-push] REFUSING PUSH: working tree has uncommitted or untracked files" >&2
    echo "  Commit your changes or delete untracked files before pushing." >&2
    exit 1
fi
EOF

# 6. Python-Specific Setup
if [[ "$IS_PYTHON" =~ ^[Yy]$ ]]; then
  echo "Setting up Python boundaries..."
  
  # Append pytest check to hook
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

  # VS Code settings
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

chmod +x .githooks/pre-push

# 7. Git Setup
cat << 'EOF' > .gitignore
.venv/
.env
__pycache__/
*.pyc
.pytest_cache/
.vscode/
.agent_lock
EOF

git init
git config core.hooksPath .githooks
git add .
git commit -m "chore: initialized secure agent workspace"

echo "✅ Workspace initialized successfully."
echo "AGENTS.md contract created."
echo ".githooks/pre-push installed."

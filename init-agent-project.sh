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

# The same-tree commit lock is OPTIONAL and narrow: it only helps two agents
# sharing ONE working directory (with distinct AGENT_IDs), and gives zero
# protection across clones/worktrees. For almost everyone the discipline —
# branches + PRs + branch protection — is the real answer. Default: no.
read -p "Add the optional same-tree agent-lock? (most projects don't need it) [y/N] " WANT_LOCK
WANT_LOCK=${WANT_LOCK:-N}

# 3. Create AGENTS.md (a map of the gates — deliberately short)
# Design note: prose an agent re-reads every turn is expensive and does not
# reliably change behavior. So this file is kept minimal; the HOOKS enforce,
# this file only documents. The ideal AGENTS.md shrinks toward empty as more
# behavior moves into gates.
cat << 'EOF' > AGENTS.md
# AGENTS.md — a map of the gates (deliberately short)

You are a delegate; the human owns this repository. This file documents what
the repo ENFORCES. It does not enforce anything itself — the hooks do.

Prose that an agent re-reads every turn is expensive and does not reliably
change behavior. So this file is minimal, and every rule below is backed by a
mechanism. **You do not need to memorize this: if you cross a boundary, a gate
stops you.**

## The gates (enforced)
- **Push a clean tree.** The `pre-push` hook refuses a dirty working tree (and,
  for Python, a red test suite). `git status` must be clean at end of turn —
  commit it or delete it; there is no third state.
- **Main is the truth.** `git pull` at the start of a file-modifying turn;
  `git add -A && git commit && git push` in the SAME turn as the change. Work
  on branches, open PRs; never commit to `main` directly.
- **The real multi-agent gate is remote branch protection** (Require PR +
  Include administrators), not anything local. Structure — one agent per
  branch — is what keeps agents from colliding, not a lockfile.

## The rules a hook can't enforce (on your honor — and watched)
- **No bypass.** Never `git push --no-verify`, `git commit --no-verify`, or
  `gh pr merge --admin` to route around a gate. Remote branch protection is
  watching for exactly this.
- **No agent attribution** in commit messages or PRs. The human owns the
  history.
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

# 5. OPTIONAL same-tree agent-lock (helper + pre-commit gate). Only provisioned
# if the user opted in — for the narrow case of two agents in one working tree.
if [[ "$WANT_LOCK" =~ ^[Yy]$ ]]; then

# Document the opt-in lock in AGENTS.md (appended, so the base contract stays
# lock-free for the common case).
cat << 'EOF' >> AGENTS.md

## Optional: the same-tree commit lock
- **Lock before you write.** `./agent-lock acquire` (and `release` after you
  push). The `pre-commit` hook refuses commits while another agent holds the
  lock. Two agents in one working tree: give each a distinct `AGENT_ID`.
  (Zero effect across separate clones/worktrees — use branch protection there.)
EOF

# The agent-lock helper (turns the protocol from prose into a command).
cat << 'LOCKEOF' > agent-lock
#!/bin/bash
# agent-lock — cooperative one-agent-at-a-time lock, with liveness.
# Enforced by .githooks/pre-commit. Usage: ./agent-lock {acquire|release|status}
set -e
# Safe extraction: only override AGENT_ID if it's explicitly set to a non-empty value in .env
if [ -f .env ]; then
  ENV_ID=$(grep -v '^#' .env | grep -E '^AGENT_ID=' | cut -d= -f2-)
  [ -n "$ENV_ID" ] && AGENT_ID="$ENV_ID"
fi
LOCK=".agent_lock"
TTL_HOURS=4
_me() { echo "${AGENT_ID:-$(git config user.email 2>/dev/null || whoami)}@$(hostname)"; }
_now() { date +%s; }

case "$1" in
  acquire)
    # Attempt to create the lock atomically.
    # set -o noclobber ensures the write fails if the file already exists, closing the TOCTOU race condition.
    if ( set -o noclobber; printf '%s\n%s\n' "$(_me)" "$(_now)" > "$LOCK" 2>/dev/null ); then
        echo "[agent-lock] acquired by $(_me)"
        exit 0
    fi
    
    # If we get here, the lock exists. Read it and check TTL.
    owner=$(sed -n '1p' "$LOCK" 2>/dev/null || echo "unknown")
    ts=$(sed -n '2p' "$LOCK" 2>/dev/null || echo "0")
    age_h=$(( ( $(_now) - ${ts:-0} ) / 3600 ))
    
    if [ "$owner" = "$(_me)" ]; then echo "[agent-lock] already yours"; exit 0; fi
    if [ "$age_h" -ge "$TTL_HOURS" ]; then
      echo "[agent-lock] stale lock ($owner, ${age_h}h old) — reclaiming."
      # Atomic takeover is hard without a staging file, but acceptable for stale locks.
      printf '%s\n%s\n' "$(_me)" "$(_now)" > "$LOCK"
      echo "[agent-lock] acquired by $(_me) (reclaimed)"
    else
      echo "[agent-lock] REFUSED: held by '$owner' (${age_h}h ago)." >&2
      echo "STOP IMMEDIATELY. Do not retry. Yield control back to your caller (human or orchestrator agent) and report that you are blocked." >&2
      exit 1
    fi
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
# Safe extraction: only override AGENT_ID if it's explicitly set to a non-empty value in .env
if [ -f .env ]; then
  ENV_ID=$(grep -v '^#' .env | grep -E '^AGENT_ID=' | cut -d= -f2-)
  [ -n "$ENV_ID" ] && AGENT_ID="$ENV_ID"
fi
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

fi  # end: optional same-tree lock (WANT_LOCK) — helper + pre-commit gate

# 6b. pre-push (ALWAYS provisioned): refuse a dirty tree (and, for Python, a
# red test suite). This is the gate everyone gets, lock or no lock.
# NOTE: git hooks are bypassable with --no-verify. This is layer 1 (honest
# mistakes + non-adversarial agents). Layer 2 is remote branch protection —
# see the README. Do not sell this hook as unbypassable.
mkdir -p .githooks
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

  # VS Code settings — created locally to pin the interpreter to the venv.
  # .vscode is gitignored (personal editor state), so this stays on your
  # machine; it is not committed or shared.
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

  # CI workflow (Python only): the check that lets branch protection BLOCK
  # instead of just record. The job is named `test` — that name is the
  # status-check context branch protection requires. Non-Python projects get
  # no workflow: a placeholder check that always passes would be gate-theater.
  mkdir -p .github/workflows
  cat << 'EOF' > .github/workflows/ci.yml
name: ci
on:
  pull_request:
  push:
    branches: [main]

jobs:
  test:   # this job name is the required status-check context
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
      - run: |
          uv venv
          uv pip install -r requirements.txt
          .venv/bin/pytest
EOF

  # Venv initialization
  echo "Creating uv venv..."
  uv venv
  source .venv/bin/activate
  uv pip install -r requirements.txt
fi

chmod +x .githooks/pre-push
[ -f .githooks/pre-commit ] && chmod +x .githooks/pre-commit

# 8. Git Setup ----------------------------------------------------------------
# .vscode/ is gitignored entirely — editor state is personal. The interpreter
# pin is provisioned locally so VS Code activates the right venv, but it is not
# committed or shared.
cat << 'EOF' > .gitignore
.venv/
.env
__pycache__/
*.pyc
.pytest_cache/
.vscode/
.agent_lock
EOF

# README stub — leave the new project self-documenting (ironically, the
# generator had none). $PROJECT_NAME expands; backticks are escaped to stay
# literal in this unquoted heredoc.
cat << EOF > README.md
# $PROJECT_NAME

An agent-safe workspace: humans and AI coding agents share this repository.
The rules of engagement
live in \`AGENTS.md\` — and they are **enforced by git hooks**, not merely
written down.

## Guardrails
- The pre-push hook refuses a dirty working tree — including untracked
  files — (and, for Python, a red test suite).
- \`main\` is the source of truth: work on branches, open PRs; never commit
  to \`main\` directly.

## Getting started
- **Fresh clone? Hooks do NOT clone.** Run this once per clone or the
  guardrails above are silently absent:
  \`git config core.hooksPath .githooks\`
- Python: open a new terminal and run \`source .venv/bin/activate\`.
- Copy \`.env.example\` to \`.env\` and set your keys. If you run more than
  one agent, give each process its own \`AGENT_ID\` (export it in that
  agent's environment — one shared \`.env\` can only hold one value).

## License
Add a LICENSE file of your choice (MIT is a common, permissive default).
EOF

# The stub documents the lock only when it was actually provisioned.
if [[ "$WANT_LOCK" =~ ^[Yy]$ ]]; then
cat << 'EOF' >> README.md

## Optional same-tree lock (provisioned in this repo)
`./agent-lock acquire` before writing (`release` after you push). The
pre-commit hook refuses commits while another agent holds the lock.
Same-tree only; does nothing across clones.
EOF
fi

git init -q
git config core.hooksPath .githooks
git add .
git commit -q -m "chore: initialized secure agent workspace"

echo "✅ Workspace initialized successfully (local repo, first commit made)."
echo "   AGENTS.md contract created (rules are hook-enforced)."
echo "   .githooks/pre-push installed (dirty-tree + test gate; layer 1 of 2)."
if [[ "$WANT_LOCK" =~ ^[Yy]$ ]]; then
  echo "   .githooks/pre-commit installed (lockfile gate)."
  echo "   ./agent-lock helper installed."
fi

# 9. Optional: create the GitHub remote and push (the "and then do the thing").
# Uses `gh`, which authenticates over HTTPS with its own token — NO SSH KEY
# NEEDED. If gh is missing or not logged in, we print the exact command and
# leave the (already safe) local repo untouched.
echo ""
read -p "Create a GitHub repo and push it now? [y/N] " DO_REMOTE
DO_REMOTE=${DO_REMOTE:-N}

if [[ "$DO_REMOTE" =~ ^[Yy]$ ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "  ! GitHub CLI (gh) not found. Install https://cli.github.com then run:"
    echo "      gh repo create $PROJECT_NAME --source=. --remote=origin --push"
  elif ! gh auth status >/dev/null 2>&1; then
    echo "  ! Not logged in to GitHub CLI. Run 'gh auth login -s workflow' — choose"
    echo "    HTTPS when asked (this needs NO SSH key; gh manages an HTTPS token;"
    echo "    the workflow scope lets it push the CI file). Then run:"
    echo "      gh repo create $PROJECT_NAME --source=. --remote=origin --push"
  elif [[ "$IS_PYTHON" =~ ^[Yy]$ ]] && ! gh auth status 2>&1 | grep -q "'workflow'"; then
    # Python projects include .github/workflows/ci.yml. GitHub REFUSES a push
    # that creates/updates workflow files from an OAuth token without the
    # `workflow` scope — the repo gets created but the push dies half-done.
    # Fail fast BEFORE creating the remote (verified live 2026-07-12).
    echo "  ! Your gh token lacks the 'workflow' scope, which GitHub requires to"
    echo "    push this project's CI file (.github/workflows/ci.yml). Fix it, then"
    echo "    re-run or push by hand:"
    echo "      gh auth refresh -h github.com -s workflow"
    echo "      gh repo create $PROJECT_NAME --source=. --remote=origin --push"
  else
    read -p "  Visibility? [private/public] (default private) " VIS
    case "$VIS" in public) VIS_FLAG="--public";; *) VIS_FLAG="--private";; esac
    if gh repo create "$PROJECT_NAME" $VIS_FLAG --source=. --remote=origin --push; then
      echo "  ✅ Created and pushed via gh's authenticated HTTPS — no SSH key required."
      REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
      echo ""
      # Layer 2 (branch protection) is a POLICY choice the human makes — offer
      # to apply it now, otherwise print the exact command to run in the
      # terminal. This is what makes "one agent can't bypass CI" real.
      # Printed-command variant of the required-checks args (used in both
      # fallback echoes below; must stay in sync with CHECK_ARGS).
      if [[ "$IS_PYTHON" =~ ^[Yy]$ ]]; then
        CHECKS_TXT='-F "required_status_checks[strict]=false" -F "required_status_checks[contexts][]=test"'
      else
        CHECKS_TXT='-F required_status_checks=null'
      fi
      read -p "  Enable branch protection on main now (layer 2, requires PRs)? [y/N] " DO_PROT
      DO_PROT=${DO_PROT:-N}
      if [[ "$DO_PROT" =~ ^[Yy]$ ]]; then
        # NOTE: gh's -F flag does NOT nest dotted keys — brackets are required
        # (verified live 2026-07-12: dotted form → 422, bracket form → 200;
        # required_status_checks[contexts][] also verified live → 200).
        # Also: branch protection on PRIVATE repos requires GitHub Pro; on a
        # free plan this call returns 403 for private repos.
        # Python projects get CI (.github/workflows/ci.yml, job `test`), so
        # protection can REQUIRE that check — the gate blocks, not records.
        # Non-Python projects have no CI, so requiring a check would block
        # every merge forever; they get the PR-paper-trail config instead.
        if [[ "$IS_PYTHON" =~ ^[Yy]$ ]]; then
          CHECK_ARGS=(-F "required_status_checks[strict]=false" -F "required_status_checks[contexts][]=test")
        else
          CHECK_ARGS=(-F required_status_checks=null)
        fi
        if gh api -X PUT "repos/${REPO_SLUG}/branches/main/protection" \
             -F "required_pull_request_reviews[required_approving_review_count]=0" \
             -F enforce_admins=true "${CHECK_ARGS[@]}" \
             -F restrictions=null >/dev/null 2>&1; then
          echo "  ✅ Branch protection on: PRs required, administrators included. main is locked."
          if [[ "$IS_PYTHON" =~ ^[Yy]$ ]]; then
            echo "     PRs must pass the 'test' CI check (pytest) before merging — the gate BLOCKS."
          else
            echo "     (Direct pushes to main are now rejected — you work on branches and open PRs, even you."
            echo "      With 0 required reviews and no CI it forces the PR paper trail; it does not by itself"
            echo "      block a bad PR from being merged — add required checks/reviews for that.)"
          fi
        else
          echo "  ! Protection call failed. Common cause: private repo on a free plan"
          echo "    (GitHub requires Pro for branch protection on private repos)."
          echo "    Make the repo public or upgrade, then run it yourself:"
          echo "      gh api -X PUT repos/${REPO_SLUG}/branches/main/protection \\"
          echo "        -F \"required_pull_request_reviews[required_approving_review_count]=0\" \\"
          echo "        -F enforce_admins=true ${CHECKS_TXT} -F restrictions=null"
        fi
      else
        echo "  To enable it later, YOU (the human) run this in your terminal"
        echo "  (note: private repos need GitHub Pro for branch protection):"
        echo "      gh api -X PUT repos/${REPO_SLUG:-<owner>/$PROJECT_NAME}/branches/main/protection \\"
        echo "        -F \"required_pull_request_reviews[required_approving_review_count]=0\" \\"
        echo "        -F enforce_admins=true ${CHECKS_TXT} -F restrictions=null"
        echo "    (or on GitHub: Settings → Branches → Add rule → Require a PR +"
        echo "     Include administrators)"
      fi
    else
      echo "  ! Could not create/push (repo may already exist, or auth scope)."
      echo "    If the error mentions 'workflow scope': your token can't push CI"
      echo "    files — run 'gh auth refresh -h github.com -s workflow' and retry."
      echo "    Otherwise, fallback:"
      echo "      git remote add origin <URL>   # use the HTTPS URL github shows you"
      echo "      git push -u origin main"
      echo "    If git then asks for a password, run 'gh auth setup-git' once so git"
      echo "    reuses gh's HTTPS token (still no SSH key)."
    fi
  fi
else
  echo "Next, when ready (no SSH key needed — gh uses an HTTPS token):"
  echo "    gh auth login -s workflow   # once per machine; choose HTTPS ('-s workflow'"
  echo "                                # lets the token push CI files)"
  echo "    gh repo create $PROJECT_NAME --source=. --remote=origin --push"
fi

# 10. Open in VS Code (if available). The committed .vscode/settings.json pins
# the venv; a NEW integrated terminal auto-activates it (VS Code behavior — on
# the very first terminal you may need to press Enter once for it to re-source).
if command -v code >/dev/null 2>&1; then
  echo ""
  echo "Opening $PROJECT_NAME in VS Code..."
  code .
fi

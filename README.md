# AI Agent Utils

*A pragmatic developer toolkit for human-agent pair programming: automated git guardrails, pre-commit enforcement, and explicit agent contracts that keep coding delegates disciplined.*


## The Philosophy: Gates, Not Words

When working with autonomous coding agents (Claude Code, Cursor, Gemini, Copilot), telling an agent what *not* to do in system prompts or documentation frequently fails under context compaction or complex multi-step tasks.

> *"Both came out of a project where 'no hardcoded values' had been stated to every agent that touched the repository, repeatedly, in writing. Words alone do not bind coding agents; automated hooks and enforced contracts do."*

`ai-agent-utils` focuses on **Agent Hygiene**: structural boundaries and local git hooks that prevent agents from:
- Force-pushing or committing directly to `main`
- Merging failing Pull Requests via admin overrides
- Hardcoding duplicated constants instead of reading authoritative data files
- Staging unreviewed or sensitive artifacts with `git add .`

---

## Core Tools

### 1. The Workspace Initializer (`init-agent-project.sh`)

Provisions a new repository with end-to-end agent guardrails:

```bash
# Global installation:
init-agent-project <project_name>

# Local execution:
./init-agent-project.sh <project_name>
```

**What it sets up:**
- **Local Pre-Push Hook (`.githooks/pre-push`):** Refuses to push a dirty working tree or broken test suite.
- **Pre-Commit Enforcement (`.pre-commit-config.yaml`):** Pinned `ruff` (linting & formatting) and `gitleaks` (secret scanning & local path detection).
- **The Agent Contract (`AGENTS.md`):** A concise, explicit set of operating rules for coding agents.
- **GitHub Branch Protection:** Automates requiring PRs and status checks via the GitHub API.
- **Python Workspace (Optional):** Generates `uv` virtual environment and Pytest harness.

---

### 2. The Agent Contract (`AGENTS.md`)

An agent-agnostic contract placed in the root of each seeded project. It defines clear boundaries:
- **Agents do not publish:** Delegates work on feature branches; the human owner reviews, pushes, and merges.
- **Stage by name:** Prohibits blanket `git add -A` and `git add .` to prevent accidental staging.
- **Private data separation:** Ensures personal material and local notes stay out of the repo tree.
- **Conventional Commits:** Standardizes technical, concise commit messages without conversational narrative.

---

### 3. Claim & Data Integrity Gates (`.gates/`)

Specialized automated checks designed specifically for common agent failure modes:

| Gate | Target Failure Mode |
| :--- | :--- |
| `no_hardcoding.py` | Refuses code that duplicates literals that already exist in a structured data file (`data/*.yaml`). |
| `verify.py` | Validates that claims and numbers cited in documentation match registered ground-truth sources (`FACTS.yaml`). |
| `gitleaks` | Detects accidentally committed credentials and absolute home-directory paths. |

#### Declarative TOML Configuration

Gate engines are immutable mechanism. All project-specific configuration is declared in `pyproject.toml` (or `.gates.toml`) and loaded using Python's built-in `tomllib` with zero external dependencies:

```toml
[tool.gates.no_hardcoding]
min_length = 25
data_dirs = ["data"]
code_dirs = ["tools", "src", "templates"]
data_extensions = [".yaml", ".yml", ".json", ".toml"]
code_extensions = [".py", ".html", ".js", ".mjs", ".sh"]
exclude = []

[tool.gates.claim_integrity]
facts_file = ".gates/FACTS.yaml"
```

If required configuration is missing, the gate fails fast and informs the author rather than running on hidden in-code assumptions.

---

## Installation & Setup

```bash
# Clone the repository
git clone https://github.com/rctruta/ai-agent-utils.git
cd ai-agent-utils

# Install CLI globally
mkdir -p ~/.local/bin
cp init-agent-project.sh ~/.local/bin/init-agent-project
chmod +x ~/.local/bin/init-agent-project
```

### Running the Test Suite

```bash
bash tests/ci_checks.sh
```

---

## License

MIT © Ramona C. Truta

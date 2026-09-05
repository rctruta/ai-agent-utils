# AI Agent Utilities

*A small, honest toolkit for working with AI coding agents: one script that sets up a repo with enforced git discipline — hooks, branch protection, and an agent contract that documents the gates instead of pleading with the agent.*

## The Initialization Script: `init-agent-project.sh`

This script sets up a workspace with git guardrails for working with coding agents. It strips away opinionated application frameworks and focuses entirely on **Agent Hygiene**. (It does not sandbox anything — the hooks are local policy, bypassable by design; see the layered honesty notes below.)

### Two families of gates

`init-agent-project` installs two independent gate families. Both are plain
scripts run by git hooks, so they bind **whoever is driving** — you, Claude
Code, Cursor, Gemini, or CI. Nothing depends on a particular agent.

**1. Git discipline** (original): clean tree on push, branch protection, no
direct commits to `main`, committer identity.

**2. Claim integrity and change safety** (`.gates/`, on by default; `--no-gates`
to skip):

- `.gates/FACTS.yaml` — every load-bearing claim, its source, and how to check
  it. Facts are marked `verified` (checked against a source) or `reported`
  (human testimony, no external artifact). The distinction is explicit rather
  than assumed.
- `.gates/verify.py` — re-checks every verified fact against its source.
- `.gates/scan.py` — blocks claims on the `banned` list, and reports numbers
  that appear in documents but are not registered. Banned claims block;
  unregistered numbers only report, because a noisy blocker gets bypassed and a
  bypassed gate is worse than no gate.
- `.gates/checkpoint.sh` — record a known-good state *before* mutating a working
  system. The save is **refused** unless a supplied proof command passes, so a
  checkpoint is always a state that demonstrably worked.
- `.gates/ledger.jsonl` — append-only record of which gate ran, when, on which
  commit, and what it returned.
- `.gates/tests/prove_gates.sh` — demonstrates each gate actually firing. An
  untested gate is theatre.

### Agent-agnostic by construction

Enforcement lives in `.githooks/` and `.gates/`. Agent-specific files only
*describe* the gates and are generated as thin adapters:

| File | For |
| :--- | :--- |
| `AGENTS.md` | any agent — the contract |
| `.claude/skills/gates/SKILL.md` | Claude Code |
| `.cursor/rules/gates.mdc` | Cursor |

Delete every adapter and enforcement is unchanged. A new tool means a new
adapter file, not a change to the gates.

### Honest boundary

The hooks are local policy. `--no-verify` defeats them, and remote branch
protection is the only thing that stops a determined bypass. These gates stop
the careless path — which is where fabricated numbers and unrecorded config
changes actually come from — not an adversary.

### Installation

To make the script globally available on your machine:

#### Mac / Linux
```bash
# Make it executable
chmod +x init-agent-project.sh

# Move it to your local binaries directory (ensure ~/.local/bin is in your PATH)
mkdir -p ~/.local/bin
mv init-agent-project.sh ~/.local/bin/init-agent-project
```

#### Windows
It is highly recommended to run this script within **WSL (Windows Subsystem for Linux)** or **Git Bash**. 
1. Open Git Bash or your WSL terminal.
2. Run the same commands as the Mac/Linux instructions above to place the script in a PATH-accessible directory (like `~/.local/bin`).

### Usage

```bash
# If installed globally:
init-agent-project <project_name>

# If running from the current directory:
./init-agent-project.sh <project_name>
```

The script is interactive. It asks three questions:
- **"Is this a Python project?"** — If yes, it generates a `uv` virtual environment, a Pytest structure, and a `.vscode/settings.json` (gitignored, local) that pins the interpreter. If no, it skips straight to the git hooks and agent contracts.
- **"Add the optional same-tree agent-lock?"** — default **no**; say yes only for the narrow two-agents-in-one-directory case.
- **"Create a GitHub repo and push it now?"** — If yes, it uses `gh` to create the remote and push in one step.

---

## Working with Git: the exact commands

### Authentication first
```bash
gh auth login -s workflow   # pick: GitHub.com → HTTPS → login in browser
gh auth setup-git           # makes plain `git push` reuse gh's token too
```

---

## The Manifesto: Why Agent Hygiene is Mandatory

If you are using autonomous coding agents, you are no longer the only developer on your repository. You are an orchestrator managing highly capable but structurally blind delegates.

### 1. The Rogue Agent Lesson (Why CI is not enough)
*Never rely on GitHub Actions or remote CI as your primary security gate.*

In a recent experiment, an autonomous agent successfully passed its local tests and opened a Pull Request. When the remote CI workflow failed, the agent executed:
`gh pr merge --admin`

It bypassed the red CI workflow using administrator privileges and merged broken code into `main`. **The gate has to run on the pusher's machine.**

---

## License

MIT — do whatever you want with it; no warranty. See `LICENSE`.

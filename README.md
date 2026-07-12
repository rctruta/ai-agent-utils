# AI Agent Utilities

A collection of boilerplate scripts and security guidelines for safely collaborating with autonomous coding agents (like Claude Code, Gemini IDE, etc.).

## The Initialization Script: `init-agent-project.sh`

This script generates a secure, bounded workspace optimized for multi-agent collaboration. It strips away opinionated application frameworks and focuses entirely on **Agent Hygiene**.

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

The script is interactive. It will ask if you are building a Python project.
- **If Yes**: It generates a `uv` virtual environment, a Pytest structure, and `.vscode/settings.json` to force agents to use the correct Python interpreter.
- **If No**: It skips the Python setup and just provisions the Git Hooks and Agent Contracts.

### What it Provisions
1. **`AGENTS.md` (The Contract)**: A manifesto placed in the root of your project. Every rule in it is backed by a mechanism — gates, not vows.
2. **`.githooks/pre-commit` (The Lock Gate)**: Refuses any commit while another agent holds the lock. This is what makes the Lockfile Protocol real instead of a suggestion.
3. **`.githooks/pre-push` (The Local Gate)**: Refuses to push a dirty working tree or (for Python) a red test suite. This is **layer 1** — see the Rogue Agent Lesson for why you also need layer 2.
4. **`./agent-lock` (The Helper)**: One-command `acquire`/`release`/`status`, so the lock protocol is a command rather than a three-step ritual an agent must remember.
5. **`.vscode/settings.json`** (Python projects): pins the interpreter to the project venv — and is **committed on purpose**, so the pin reaches every clone and every agent, not just your machine.
6. **`.env.example`**: A safe template for LLM API keys and a distinct `AGENT_ID` per agent.

---

## The Manifesto: Why Agent Hygiene is Mandatory

If you are using autonomous coding agents, you are no longer the only developer on your repository. You are an orchestrator managing highly capable but structurally blind delegates. 

Without explicit boundaries, agents will silently fracture your repository's state. Here are the core lessons learned from the frontier of multi-agent development.

### 1. The Rogue Agent Lesson (Why CI is not enough)
*Never rely on GitHub Actions or remote CI as your primary security gate.* 

In a recent experiment, an autonomous agent successfully passed its local tests and opened a Pull Request. When the remote CI workflow failed, the agent did not attempt to fix the failing tests. Instead, it noticed it had GitHub CLI (`gh`) access and simply executed:
`gh pr merge --admin`

It bypassed the red CI workflow using administrator privileges and merged the broken code directly into `main`. **The gate has to run on the pusher's machine.**

This repository provisions a strict local `.githooks/pre-push` script that aborts the `git push` before the bytes leave your laptop. **But be honest about its limit:** a git hook is bypassable with `git push --no-verify`, which is the local-layer equivalent of `gh pr merge --admin`. An agent willing to reach for one flag will reach for the other. So the hook is **layer 1** — it stops honest mistakes and non-adversarial agents. **Layer 2 is remote branch protection with *Include administrators* enabled** (see §3): that catches the deliberate bypass, because a `--no-verify` push into a protected branch still fails the required status check. Use both. Neither alone is a gate; together they are.

### 2. Multi-Agent Traffic Control (The Lockfile Protocol)
If you use multiple agents (e.g., Claude Code in the terminal and Gemini in your IDE) on the same repository, they will inevitably overwrite each other. **Agents are blind to each other's unpushed, uncommitted local edits.**

Here is the trap I fell into first, and the fix. A lockfile protocol written **as prose** in `AGENTS.md` — "check for `.agent_lock` before you start" — is just another word, and words don't bind: an agent that never reads the file, or reads it and doesn't bother, overwrites you anyway. (I measured this elsewhere: given an optional-but-useful convention, agents adopt it roughly none of the time unprompted.) So this utility makes the lock a **gate**:

- **`./agent-lock acquire`** writes the lock (stamped with the holder's identity + time). It refuses if another live agent holds it.
- **`.githooks/pre-commit`** independently **refuses any commit while a foreign lock is held** — so an agent that skips `acquire` entirely still cannot commit over you.
- **`./agent-lock release`** clears it after you push. A crashed agent's lock **auto-expires after 4h**, so a dead holder never deadlocks the repo.

**Honest scope.** The hook tells agents apart by `AGENT_ID` (falling back to git email / `whoami`). Across separate clones or users it is a hard gate. For two agents in the *same* working directory, give each a distinct `AGENT_ID` (e.g. `claude-term`, `gemini-ide`) to get true mutual exclusion; without distinct IDs it degrades to a shared-identity speed bump. That is the real boundary of what a git hook can enforce — stated plainly rather than oversold.

*One agent per branch at a time — now enforced, not just requested.*

### 3. Branch Protection & The Chicken-and-Egg Problem
You should always protect your `main` branch on GitHub, requiring Pull Requests for all changes. Agents should only ever work on feature branches.

However, you cannot protect a branch that doesn't exist. When starting a new project using this script:
1. Push your initial commit directly to main (`git push -u origin main`).
2. Immediately go to GitHub Settings -> Branches -> Add branch protection rule.
3. Enforce **Require a pull request before merging**, **Require status checks to pass**, and — critically — **Include administrators** (in the API, `enforce_admins: true`).

That last box is the one that closes the `--no-verify` / `--admin` hole: with administrators included, even you cannot merge a red or bypassed branch without noticing. From that moment on the gate is locked at both layers, and your agents operate safely in branches.

---
*Built with hard-won wisdom from the SQL Benchmarking Laboratory.*

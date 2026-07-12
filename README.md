# AI Agent Utilities

A collection of boilerplate scripts and security guidelines for safely collaborating with autonomous coding agents (like Claude Code, Gemini IDE, etc.).

## The Initialization Script: `init-agent-project.sh`

This script generates a secure, bounded workspace optimized for multi-agent collaboration. It strips away opinionated application frameworks and focuses entirely on **Agent Hygiene**.

### Usage

```bash
chmod +x init-agent-project.sh
./init-agent-project.sh <project_name>
```

The script is interactive. It will ask if you are building a Python project.
- **If Yes**: It generates a `uv` virtual environment, a Pytest structure, and `.vscode/settings.json` to force agents to use the correct Python interpreter.
- **If No**: It skips the Python setup and just provisions the Git Hooks and Agent Contracts.

### What it Provisions
1. **`AGENTS.md` (The Contract)**: A manifesto placed in the root of your project instructing all agents on the rules of engagement.
2. **`.githooks/pre-push` (The Gate)**: A strict local gate that prevents you (or your agents) from pushing a dirty working tree or failing tests to your remote branch.
3. **`.env.example`**: A safe template for storing LLM API keys locally.

---

## The Manifesto: Why Agent Hygiene is Mandatory

If you are using autonomous coding agents, you are no longer the only developer on your repository. You are an orchestrator managing highly capable but structurally blind delegates. 

Without explicit boundaries, agents will silently fracture your repository's state. Here are the core lessons learned from the frontier of multi-agent development.

### 1. The Rogue Agent Lesson (Why CI is not enough)
*Never rely on GitHub Actions or remote CI as your primary security gate.* 

In a recent experiment, an autonomous agent successfully passed its local tests and opened a Pull Request. When the remote CI workflow failed, the agent did not attempt to fix the failing tests. Instead, it noticed it had GitHub CLI (`gh`) access and simply executed:
`gh pr merge --admin`

It bypassed the red CI workflow using administrator privileges and merged the broken code directly into `main`. **The gate has to run on the pusher's machine.** 

This repository provisions a strict local `.githooks/pre-push` script. The agent cannot bypass a script that physically aborts the `git push` command before the bytes leave your laptop.

### 2. Multi-Agent Traffic Control (The Lockfile Protocol)
If you use multiple agents (e.g., Claude Code in the terminal and Gemini in your IDE) on the same repository, they will inevitably overwrite each other. **Agents are blind to each other's unpushed, uncommitted local edits.**

To prevent catastrophic concurrent modification, this utility installs **The Lockfile Protocol** into your `AGENTS.md`.
- Before an agent starts a task, it is instructed to check for `.agent_lock`.
- If the file exists, the agent will refuse to work.
- If it doesn't exist, the agent creates the file, does its work, commits/pushes, and deletes the file.

*One agent per branch at a time.*

### 3. Branch Protection & The Chicken-and-Egg Problem
You should always protect your `main` branch on GitHub, requiring Pull Requests for all changes. Agents should only ever work on feature branches.

However, you cannot protect a branch that doesn't exist. When starting a new project using this script:
1. Push your initial commit directly to main (`git push -u origin main`).
2. Immediately go to GitHub Settings -> Branches -> Add branch protection rule.
3. Enforce **Require a pull request before merging**.

From that moment on, the gate is locked, and your agents must operate safely in branches.

---
*Built with hard-won wisdom from the SQL Benchmarking Laboratory.*

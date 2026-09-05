# AGENTS.md — Agent Contract & Gate Map

> **Workspace Policy for `ai-agent-utils`.** Humans and AI coding agents share this repository.
> Every enforceable rule below is backed by a local gate or remote policy mechanism.

---

## 1. Local & Remote Gates

- **Local Gate (`.githooks/pre-push`):**
  - Refuses to push a dirty working tree (including untracked files).
  - Runs `pytest tests/ -v` on Python changes; push aborts if any test fails.
- **Remote Gate (GitHub Branch Protection):**
  - `main` is the source of truth; do not commit directly to `main`.
  - Feature work must happen on topic branches (`feat/...` or `fix/...`) via Pull Requests.

---

## 2. Project Architecture & Tools

- **Initialization Script:** `init-agent-project.sh` — provisions new repositories with git hooks, branch protection options, and python `uv` environments.
- **Substrate Security & Avatar QR Studio:** `avatar_qr.py` / CLI `avatar-qr` — generates Level H scannable avatar QR codes, audits image substrates for sub-visual Vision Transformer traps, and sanitizes image optical noise.
- **Package Specification:** `pyproject.toml` (Hatchling backend, Python >= 3.9).

---

## 3. Fresh Clone Setup

If working in a fresh clone, activate git hooks:

```bash
git config core.hooksPath .githooks
uv venv && source .venv/bin/activate
uv pip install -e ".[dev]"
```

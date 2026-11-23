# ai-agent-utils

[![CI](https://github.com/rctruta/ai-agent-utils/actions/workflows/ci.yml/badge.svg)](https://github.com/rctruta/ai-agent-utils/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-green.svg)](LICENSE)
[![Docs: CC BY 4.0](https://img.shields.io/badge/Docs-CC_BY_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by/4.0/)

Workspace initializer and git-hook gates for repositories shared by humans and coding agents.

Rules written in prose do not hold under long sessions or context compaction. Every boundary this repository ships is enforced by a git hook, a standard linter/scanner, or CI; `AGENTS.md` only documents what those gates refuse.

## Install

Symlink the script onto `PATH` (do not copy it — the initializer resolves `templates/gates/` relative to its own repository):

```bash
git clone https://github.com/rctruta/ai-agent-utils.git
cd ai-agent-utils
mkdir -p ~/.local/bin
ln -s "$PWD/init-agent-project.sh" ~/.local/bin/init-agent-project
```

Requires `git`, `python3` (>= 3.11 for stdlib `tomllib` in gates), and [uv](https://docs.astral.sh/uv/) if seeding Python workspaces. `pre-commit` is used to run the declared checks; `gh` is optional for creating the GitHub remote and applying branch protection.

## Usage

```bash
init-agent-project [OPTIONS] <project_name> [root_directory]
```

| Option | Effect |
| --- | --- |
| `--gates` | Full workspace with `.gates/`, `.pre-commit-config.yaml`, `AGENTS.md`, `scratch/` symlink, hooks, and optional CI (default). |
| `--no-gates` | Skips `.gates/` and `pre-commit`; keeps `.githooks/pre-push`, `AGENTS.md`, `scratch/`, and optional Python/CI setup. |
| `--lite` | Minimal workspace for quick prototypes or upstream issue reproductions: `git init`, `.gitignore`, minimal `README.md`, a lightweight `.githooks/pre-push` (dirty tree, tracked `.env`, and `gitleaks` if installed), and optional Python `uv` venv. Skips `.gates/`, `AGENTS.md`, `scratch/`, CI, and remote prompts. |
| `--python` | Provisions a Python `uv` venv and `requirements.txt` without prompting. |
| `-h`, `--help` | Prints usage and exits. |

Examples:

```bash
# Full agent-safe workspace (interactive)
init-agent-project my-service

# Non-interactive throwaway or upstream issue repro with Python
init-agent-project --lite --python issue-repro /tmp
```

## What a seeded repository gets

| Path | What it does |
| --- | --- |
| `.githooks/pre-commit` | Runs `pre-commit` (`ruff`, `gitleaks`, AST/YAML/TOML checks, private-key detection) and the `.gates/` checks on every commit. |
| `.githooks/pre-push` | Refuses a dirty working tree (including untracked files) and runs `pytest` / `npm test` when present. |
| `.gates/` | Stdlib-only Python gates for claim integrity (`verify.py`, `scan.py`), hardcoded duplicates (`no_hardcoding.py`), dead modules (`no_orphans.py`), external `scratch/` (`scratch_external.py`), script standards (`check_script_standards.py`), and publishing contracts (`check_publish_contract.py`). See [GATES.md](GATES.md) for the full registry and `.gates/tests/prove_gates.sh` for the self-tests. |
| `.pre-commit-config.yaml`, `.gitleaks.toml`, `ruff.toml` | Standard checks pinned and reviewable in diffs, including home-directory path detection. |
| `scratch` | Symlink to a directory outside the repository (`$AGENT_NOTES_ROOT/<project>`, default `~/scratch/<project>`). Git refuses to stage files through a symlink. |
| `.github/workflows/ci.yml` | Runs tests and the same `.gates/` + `prove_gates.sh` suite on pull requests, with SHA-pinned actions and cached `pre-commit` environments. |
| `AGENTS.md`, `.claude/`, `.cursor/` | Short contract and editor adapters describing the enforced rules. |

Gate engines in `.gates/` are generic mechanism. Project-specific paths, thresholds, and exclusions are declared in `pyproject.toml` under `[tool.gates.*]` (or `.gates.toml`) and read with `tomllib`.

## Limits

- **Hooks do not clone.** Anyone cloning a seeded repository must run `git config core.hooksPath .githooks` once per clone.
- **Local hooks are bypassable.** `--no-verify` skips local hooks; GitHub branch protection requiring the `test` CI status check is layer 2.
- **Private repositories on free GitHub plans** do not support branch protection via the API; the initializer prints the exact command to run once eligible.

## Verification

The generator tests itself on throwaway workspaces, proves every gate fires on a planted violation, and executes the generated CI jobs from fresh clones:

```bash
bash tests/ci_checks.sh
```

## License

Copyright 2026 Ramona C. Truta. Code and templates are licensed under the [Apache License 2.0](LICENSE). Documentation (`README.md`, `GATES.md`, `AGENTS.md`) is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

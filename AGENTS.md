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

## Publishing: what an agent may and may not do

This repository is public. Anything pushed to it, including branches, commit
messages and pull-request text, can be read by anyone and stays in history.

- **Agents do not publish.** No `git push` unless the owner asks for it in the
  current session, and never to `main`. No merging pull requests, no
  force-push, no rewriting history, no changing repository settings. An agent
  works on a local branch; the owner reviews, pushes and merges.
- **Stage files by name.** Never `git add -A` or `git add .`. Before every
  commit, read `git status` and `git diff --staged` and confirm each path is
  meant to be public.
- **Private material stays outside the repository.** Personal material and
  unpublished work are never copied in, referenced by
  absolute path, or quoted in code, comments, tests, commit messages or PR
  text. Code that needs private data reads its location from an environment
  variable.
- **Commit messages and PR text are public writing.** Use a short
  Conventional Commits subject (`fix: ...`, `docs: ...`, `chore: ...`) that
  says what changed. A body, if any, explains the change technically. No
  session narrative, no account of earlier mistakes, no incident dates, no
  names of people or private documents.
- **The owner reviews before merge:** `git log -p origin/main..HEAD` and the
  PR title. Squash merges use the PR title only, so the commit on `main` says
  exactly what was reviewed.
- **Secrets:** gitleaks runs in pre-commit, and GitHub secret scanning and push
  protection are on. Fix a finding by removing the value. Do not allowlist it
  unless the owner says so.

---

## 2. Project Architecture & Tools

- **Initialization Script:** `init-agent-project.sh` — provisions new repositories with git hooks, branch protection options, and python `uv` environments.
- **Package Specification:** `pyproject.toml` (Hatchling backend, Python >= 3.9).

---

## 3. Fresh Clone Setup

If working in a fresh clone, activate git hooks:

```bash
git config core.hooksPath .githooks
uv venv && source .venv/bin/activate
uv pip install -e ".[dev]"
```

---

## 4. Rules a gate now enforces

Each of these was written as a rule first, stated repeatedly, and broken anyway.
A rule in a document binds nobody. These are the gates that replaced them.

- **No value is written twice.** If a value lives in a data file, code reads it;
  code does not restate it. `.gates/no_hardcoding.py` compares the two after
  normalising entities, dashes, case and years, and refuses the commit.
  *Origin: a generator rendered a list of certificates as literal HTML while the
  same certificates sat in the YAML it was meant to read. The data was edited
  and the page kept showing the hardcoded copy.*

- **No tracked file carries a credential or one machine's absolute path.**
  The `gitleaks` hook in `.pre-commit-config.yaml` runs gitleaks' default
  rules plus the home-directory rule in `.gitleaks.toml`.

- **A gate scans itself.** No gate may exempt its own directory. The escape
  valve is the `allow:` block in `FACTS.yaml`, which is a decision visible in
  the diff rather than an invisible skip-list entry.
  *Origin: a privacy gate written after a real address leaked kept that address
  in its own docstring for two weeks, because its file was in its own skip list.*

- **Local notes live outside the worktree.** `scratch/` is a symlink to a
  directory outside the repository, and `.gates/scratch_external.py` asserts
  it. git refuses to stage through a symlink — `fatal: pathspec is beyond a
  symbolic link` — so the guarantee does not depend on anyone remembering.
  *Origin: a public repository carried `scratch/` on line 25 of its .gitignore
  AND a 23 KB draft tracked in HEAD for three months. An ignore rule is
  consulted only for files git does not already track, so it had been present
  and powerless the whole time.*

- **A publishing surface declares its own rules.**
  `.gates/check_publish_contract.py` reads `publish_contract.toml`, where each
  surface names the file whose presence means it is in play. A live surface
  whose trigger is missing fails; a *planned* surface whose trigger appears
  also fails, because the artifact's arrival demands its rules. That second
  case is what lets a surface be declared years before it exists.
  *Origin: three silent drifts in one afternoon — a registry manifest naming
  the previous version, that manifest existing only on an unpushed local
  branch, and a CITATION.cff three releases stale so every citation named the
  wrong version. The registry being published to checked none of it.*

- **A tracked Python file must at least parse.** The `check-ast` hook in
  `.pre-commit-config.yaml`. Every other check reads files as text, so a
  syntax error passes all of them.

- **Lint findings are defects, not style.** The `ruff-check` hook runs the
  rule set selected in `ruff.toml` — `E9`, `F`, `B` — and reports without
  editing. Widening the selection is a one-line change, and the findings it
  produces are fixed in that same change rather than ignored.

- **An untested gate is theatre.** `.gates/tests/prove_gates.sh` makes each gate
  fire on a planted violation and stay quiet on a clean tree. Run it after
  touching any gate.

---

## 5. Rules no gate can enforce

These are real and they are on your honour, because the check needs judgement
or project-specific wiring. Stating them here is not enforcement; it is a
reminder of where the gates stop.

- **A check that nothing runs is a file, not a gate.** Wire it into a hook in
  the same change that writes it. If it needs a built artifact or a library
  the running environment lacks, say which stage it belongs to rather than
  leaving it to be discovered.
  *Origin: a manifest test with ten assertions, covering exactly the drift that
  later shipped, was written in August, committed only to a local branch that
  was never pushed, and run by nothing. The check existed. Nothing gated it.*

- **A gate in this registry runs on the standard library alone.** A freshly
  bootstrapped project has installed nothing. A gate that imports a third-party
  package will crash in its pre-commit hook.
  *Origin: a gate that read its config with pyyaml broke `init-agent-project`
  outright — the hook raised ModuleNotFoundError and the first commit never
  happened. `tomllib` has been in the standard library since 3.11.*

- **When a gate and your expectation disagree, check the gate's premise before
  "fixing" anything.** A finding can be about the checker rather than the code.
  *Origin: three times in one day — a parse error that was only an error on an
  older interpreter, a trigger that fired because `pyproject.toml` signals that
  a project exists rather than that it publishes, and a probe that blamed the
  gate for its own oversight.*

- **Two patches to the same failure means the model is wrong.** Fix the design,
  not the third symptom.
  *Origin: a release failed on a missing library, then on another missing
  library, and only the third failure revealed that the real defect was having
  one name for two different moments in the release job.*

- **A structural change needs its blast radius measured, not reasoned about.**
  Before refactoring, snapshot what the system produces. After, diff the
  snapshots. Content that changed during a change that was supposed to be
  structural is the finding.

      git tag -a known-good-pre-refactor -m "<command that proves it works>"
      # refactor
      git show known-good-pre-refactor   # re-read the proving command

  *Origin: a template conversion dropped an entire section from a page, five
  credits and a line of prose. Every test passed: they asserted that the HTML
  was well-formed and that every anchor resolved, and nothing asserted the
  content was still there.*

- **Tests must assert content, not only shape.** A page can lose a section and
  stay valid. For any generated artifact, assert that every record in the source
  reaches the output — the mapping is project-specific, so the test is yours to
  write.

- **Fixing a late-stage bug means re-checking the early stages.** The same
  defect usually has siblings that were written at the same time by the same
  hand. When you find one, grep for its shape before moving on.
  *Origin: the hardcoded certificates were fixed; nineteen more hardcoded values
  sat in the same file, found only when a gate was pointed at it.*

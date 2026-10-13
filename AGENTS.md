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

- **No tracked file carries one machine's absolute path.**
  `.gates/no_local_paths.py` refuses `/Users/...`, `/home/...` and the Windows
  equivalent, in code and in comments.
  *Origin: a generator was shared into a template with another repository's home
  path hardcoded in it.*

- **A gate scans itself.** No gate may exempt its own directory. The escape
  valve is the `allow:` block in `FACTS.yaml`, which is a decision visible in
  the diff rather than an invisible skip-list entry.
  *Origin: a privacy gate written after a real address leaked kept that address
  in its own docstring for two weeks, because its file was in its own skip list.*

- **An untested gate is theatre.** `.gates/tests/prove_gates.sh` makes each gate
  fire on a planted violation and stay quiet on a clean tree. Run it after
  touching any gate.

---

## 5. Rules no gate can enforce

These are real and they are on your honour, because the check needs judgement
or project-specific wiring. Stating them here is not enforcement; it is a
reminder of where the gates stop.

- **A structural change needs its blast radius measured, not reasoned about.**
  Before refactoring, snapshot what the system produces. After, diff the
  snapshots. Content that changed during a change that was supposed to be
  structural is the finding.

      .gates/checkpoint.sh save pre-refactor "<command that proves it works>"
      # refactor
      .gates/checkpoint.sh verify pre-refactor

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

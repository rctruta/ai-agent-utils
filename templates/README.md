# templates/

The seed. Everything a repository gets is copied from here, which is why this
directory is the one place a change has to be made once rather than in every
project.

Nothing here runs against *this* repository. These files are installed into
another one, by `init-agent-project` for a new project or by `update_gates.sh`
for an existing one. The registry's own consistency is checked separately, by
`tests/check_registry.py`.

## The four scripts, and which direction each moves

The gates exist in two places: here, and in each repository that adopted them.
Keeping those in step is four separate motions, and each has its own script
because conflating them is how a gate gets lost.

| script | direction | what it does |
| :--- | :--- | :--- |
| `install_gates.sh` | seed → new repo | writes the pre-commit hook and the agent adapters. Called by `init-agent-project`. |
| `update_gates.sh` | seed → existing repo | brings a repository up to the current `gates/VERSION`. Honours `.gates/NOT_ADOPTED`. |
| `promote_gate.sh` | repo → seed | carries a gate written in a project back here. Refuses until it has a probe and a registry row. |
| `migrate_scratch.sh` | one-off, per repo | moves an in-worktree `scratch/` outside the worktree, where git cannot stage it. |

`promote_gate.sh` is the one that did not exist for a long time, and its
absence is why two gates ran in two repositories for weeks while
`check_version.py` reported both as out of date — proven, wired, and invisible
to the registry. A seed with no path back from the field only ever drifts one
way.

`update_gates.sh` copies `.py`, `.sh` and `VERSION` as code: newest wins. It
treats `.toml` differently — copied when absent, **never overwritten** —
because `publish_contract.toml` is per-repository configuration rather than
gate code. That distinction was missed at first, and the gate would have been
distributed without the contract it reads.

## gates/

The gates themselves, plus the data two of them read and the tools that report
on them. `../GATES.md` is the registry: one row per gate, what it refuses, and
the failure mode it prevents. `tests/check_registry.py` refuses a script here
with no row there.

Not every file in `gates/` is a gate:

| file | what it is |
| :--- | :--- |
| `_baseline.py` | shared library. Lets a repository adopt a gate that already has findings, as a backlog rather than a wall. |
| `VERSION` | the seed version. The single source; `GATES.md` restates it and a check asserts they agree. |
| `FACTS.yaml` | the claim registry `verify.py` and `scan.py` read. |
| `publish_contract.toml` | which surfaces a project publishes to, and what each requires. Starter: everything `planned`. |
| `check_version.py` | reports whether a repository's gates are current. Refuses nothing. |
| `gates_report.sh` | a dated snapshot of what each gate has found. Refuses nothing. |
| `survey.sh` | reports what a gate *would* find across repositories, before adopting it. Refuses nothing. |
| `tests/prove_gates.sh` | makes every gate fire on a planted violation and stay quiet on a clean tree. |

## The rules that apply to anything added here

- **Standard library only.** A gate runs in a freshly bootstrapped repository
  that has installed nothing. One that imported `pyyaml` broke
  `init-agent-project` outright: the pre-commit hook raised
  `ModuleNotFoundError` and the first commit never happened. `tomllib` has
  been in the standard library since Python 3.11.

- **A probe in both directions, or it does not ship.** `promote_gate.sh`
  refuses a gate with no case in `prove_gates.sh`. An untested gate is
  theatre, and a gate that only ever passes is indistinguishable from one that
  never looks.

- **A row in `GATES.md`, naming the failure mode.** A gate whose reason has been
  forgotten is the first one somebody deletes. `check_registry.py` enforces
  the row; only a person can write the reason.

- **A gate may not exempt its own file** unless there is genuinely nothing
  there to find, and then it says so in the code. A privacy gate once kept a
  real address in its own docstring for two weeks because its file was in its
  own skip list.

- **Findings predating adoption are a backlog, not a regression.** Use
  `_baseline.py`. A gate that fails on day one gets switched off, and a gate
  that is off catches nothing. The tracked half of `scratch_external` refuses
  a baseline on purpose, because an
  already-published private file has no reading in which accepting it is
  correct.

## Making a gate enforceable, not advisory

A hook in `.githooks/` is a convention. `git push --no-verify` skips it, and
so does anything that does not know it exists. A **required status check** is
enforced by GitHub and cannot be skipped.

    cp ci/test.yaml <repo>/.github/workflows/test.yaml
    cd <repo> && git add -A && git commit && git push
    gh workflow run .github/workflows/test.yaml      # prove it green first
    set_branch_protection.sh                         # then require it

**That order is not optional.** Requiring a context no workflow emits blocks
every merge forever, waiting for a check that never arrives. A first CI run
commonly fails for reasons that never show up locally -- a file outside the
repository, a gitignored directory -- so setting protection blind locks the
branch. `set_branch_protection.sh` refuses
unless the context has already been seen green on the default branch.

The context name is the **job** name in the workflow, not the workflow's
`name:`. The script reads it from the file so the rule and the workflow
cannot drift apart.

Branch protection needs a public repository or GitHub Pro; on a private repo
without it the API returns 403 and the hook stays the only enforcement.

### What CI is actually for here

Not redundancy with the hook. CI is the only place the suite runs from a
**clean checkout**, which is what surfaces a test depending on something the
repository does not carry. Every such test had been passing locally forever.

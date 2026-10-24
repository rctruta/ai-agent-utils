# The gates

A rule in a document binds nobody. Each gate here is a script a git hook runs,
so it binds whoever is driving — a person, Claude Code, Cursor, Gemini, or CI.

Each row states the failure mode the gate exists to prevent, because a check
whose purpose has been forgotten is the first one somebody deletes.

**Version: 15** — the same number as `templates/gates/VERSION`, which is the
source. `tests/check_registry.py` refuses a commit where the two disagree, and
also refuses a script in `templates/gates/` with no row below. A
hand-maintained version line drifts, so it is checked rather than trusted.

See *Adopting a new gate* below for how an existing repository catches up.

---

## The registry

| # | gate | refuses | the failure mode |
|---|---|---|---|
| 1 | `verify.py` | a registered fact whose source no longer supports it | a number copied into a document keeps its old value after the source changes, and nothing compares the two |
| 2 | `scan.py` | a banned claim; reports numbers registered nowhere | a figure that was never derived from anything reads exactly like one that was |
| 3 | `no_hardcoding.py` | code restating a value its data file already holds | a generator emits a literal copy of what it was meant to read, so editing the data changes nothing and the page keeps rendering the old value |
| 4 | `no_orphans.py` | a module that only its own tests import — code that exists, is tested, and is wired to nothing | a passing unit test is taken as evidence that a feature is live. The test proves the module works, not that anything calls it, and a green suite is the reason nobody looks again. Same shape: a check asserting on a sentinel that exists only inside the test that planted it |
| 5 | `check_wheel.py` | a distribution containing anything that is not the package, or any home-directory path | `python -m build` packages whatever the tree contains and exits 0. Build directories, virtualenvs, test trees and unrelated local scripts ship silently, and the problem degrades across releases rather than appearing at once |
| 6 | `scratch_external.py` | a local notes folder git can reach: a real `scratch/` inside the worktree, a symlink resolving back into it, or any note already tracked | a `.gitignore` rule is consulted only for files git does not already track, so a note added before the rule stays tracked while the rule appears to be the protection. The fix is arrangement, not a better rule: notes live outside the worktree and `scratch` is a symlink, so `git add scratch/note.md` fails with `fatal: pathspec is beyond a symbolic link` — git's own refusal, binding the human and the agent equally. A tracked note is never baselineable; accepting it would record the exposure as approved |
| 7 | `check_publish_contract.py` | a publishing surface with no rules, or a live one whose defining file has vanished | the artifacts that define a public listing drift apart silently: a manifest declaring one version while the package declares another, a required file existing only on an unpushed branch, a citation file naming a release several versions old. Registry-side validators check that a version exists, never that it agrees with anything. **The mechanism:** surfaces are declared in `publish_contract.toml` beside the gate, each naming the file whose presence means it is in play. A `live` surface with a missing trigger fails; a `planned` surface whose trigger *appears* also fails, because the artifact's arrival demands its own rules. That second case is not standard practice — normally a manifest appears, nobody wrote rules for it, and nothing says so — and it is what lets a surface be declared long before it exists. Reads its contract with `tomllib` and a version line with a line-anchored regex, so it imports nothing: a gate runs in release jobs and in freshly bootstrapped repositories that have installed nothing, where a third-party import breaks the run outright. A missing version line is a finding, never a pass, which is what makes the cheap parser acceptable. Checks declare their `stages` (`commit`, `prepublish`, `postbuild`) explicitly, because a default is a guess about where a check can run |
| 8 | `check_script_standards.py` | a tracked `.py` carrying a literal URL, absolute path, home directory or email address; a tracked `.sh` using a bash-only or GNU-only construct | a script that decides what leaves a repository encodes that decision in its own source, where nobody reviews it — a few characters inside a variable, invisible in any diff of what is published. Hardcoded endpoints and `tar`/`comm`/`grep -E` additionally make the script work on one machine and nowhere else. Comments, docstrings, tests and `.gates/` are exempt: a URL in prose is documentation, a test needs literal values to assert against, and the gate installers are stdlib shell on purpose. Baselineable, because a gate that fails on day one gets switched off |
| 9 | `check_outbound.py` | a commit message or pull-request body written in the register of a private conversation, or naming unpublished work | a commit message and a PR body are published, and neither is a file in the index — so every gate reading the index passes while both say whatever they say. Editing afterwards reduces exposure without removing it: hosts serve superseded commits by SHA and keep description edit history. The term list is **untracked** on purpose — a committed list of unpublished work publishes what it protects — and the gate exits 2 rather than passing when that file is missing, because a silent skip is how a protection becomes decoration. `.githooks/commit-msg` gives the message a path and checks it; a PR body comes from `.github/PR_BODY.md` via `tools/open_pr.sh`, which removes the unexamined path rather than warning about it |
| 10 | `tests/prove_gates.sh` | — proves each gate above fires on a planted violation and stays quiet on a clean tree | an untested gate is theatre |

### What pre-commit covers instead

The general-purpose checks are not scripts here. They are declared in
`.pre-commit-config.yaml`, which every seeded repository gets, and run from
`.githooks/pre-commit`:

| check | refuses |
|---|---|
| `check-ast` | a Python file that does not parse |
| `ruff-check` | the `E9`, `F`, `B` rule sets, reported and never auto-fixed |
| `detect-private-key` | a private key in a tracked file |
| `check-yaml` / `check-toml` | a config file that does not parse |
| `check-added-large-files` | an oversized blob entering history |
| `check-merge-conflict` | conflict markers |
| `end-of-file-fixer` / `trailing-whitespace` | whitespace drift |
| `gitleaks` | a credential (its default rules) or a home-directory path (the rule added in `.gitleaks.toml`) |

Secret scanning is gitleaks rather than a local pattern: it is the standard
tool, maintained elsewhere, and its configuration is reviewable in a diff.
GitHub secret scanning and push protection are the server-side half.

### What is deliberately NOT here

Two patterns were added at version 15 and removed again: one grepping for
phrases that mark a file private, one refusing third-person prose about the
author.

Both were **policy, not mechanism** — the distinction this repository exists
to hold. A mechanism is reusable by anyone: how a check is wired, scoped,
reported and proven. A policy is one project's judgement about its own
content, and shipping one into a seed imposes it on every repository seeded
afterwards, where it is at best irrelevant.

The design said so before the reasoning did. Each needed an exemption for
the file that defined it, then another for its own template copy, then a
negative lookahead for a legitimate exception. **Three carve-outs is not a
rule with edge cases; it is a rule that was never general.**

A phrase list is also not a mechanism: it catches the one wording someone
happened to use and nothing else. The structural guarantee already exists —
`scratch_external.py` puts notes where git cannot stage them — and secret or
PII scanning belongs to a tool built for it.

Project-specific patterns belong in that project's own `local` section, where
they are visibly one project's choice. They do not belong in this seed.

### Four gates pre-commit replaced, at version 15

`check_compiles.py`, `no_local_paths.py`, `no_private_marker.py` and
`check_voice.py` are gone. Each reimplemented, in project-specific Python,
something a standard tool already does: file selection, staged-versus-tracked
handling, reporting, exit codes. That is machinery to maintain and explain in
exchange for nothing the standard tool does not give.

One of them had failed open: it selected files by directory name, and in a
repository without those directories it read nothing and reported clean.
Selecting by extension cannot fail that way. The general rule — **a check
scoped to a path silently stops checking when the path changes.**

The replacements are proven the way the scripts were. `prove_gates.sh` plants
a violation, runs the one hook that should object, and asserts a non-zero exit
— plus one probe asserting silence on a clean file, because a check that
refuses everything is as useless as one that refuses nothing.

### Prove the entry point, not only the gates

Every per-gate probe invokes its gate directly, so none of them can detect
that git never reaches the gates at all. An entry point that returns early
disables everything appended after it while every individual probe still
passes.

`prove_gates.sh` therefore ends with one end-to-end probe: it plants a
violation in a throwaway repository wired exactly like the real one, runs
`git commit`, and asserts refusal. **A test that exercises a component
directly cannot detect that the component is unreachable.** Anything with a
dispatcher — a hook chain, a workflow with a path filter, a router — needs a
probe at the entry, not only at the leaves.

### One gate that was removed

- **`checkpoint.sh`, dropped at version 12.** It saved a named known-good
  state together with a command proving it worked, and refused to save when
  the proof failed. The implementation did what it said. Nobody used it: a
  survey of the repositories carrying it found no real checkpoints at all,
  only the artifact its own test created.

  Git already does this. A tag on a known-good commit, with the proving
  command in the tag message, is the same guarantee with nothing extra to
  install or maintain. A gate that is never exercised is not protection, it is
  one more thing that has to keep working.

  Removed from the seed; repositories that already have a copy keep it until
  they run `update_gates.sh`.

### One gate that was fixed rather than added

- **`scan.py` no longer skips `.gates/`.** A gate that exempts its own
  directory cannot see what it is carrying. The `allow:` block in `FACTS.yaml`
  is the escape valve — an exemption belongs in a diff, not in a skip list.

---

## Adopting a new gate in an existing repository

```sh
~/Projects/ai-agent-utils/templates/install_gates.sh --update
```

This copies gates newer than the ones already there and leaves everything else
alone. It does not fail your build on day one, because of the next section.

### The baseline, and why a new gate does not break old work

A gate added to an existing repository will fire on code that predates it.
That is a **backlog**, not a regression, and the two look identical from
outside:

- firing on a change you just made — the gate working
- firing on code older than the gate — a finding

So on adoption each gate records what it finds into
`.gates/baseline/<gate>.txt`, commits it, and from then on **fails only on
findings that are not in the baseline**. Nothing that worked yesterday breaks
today; nothing new slips in either. The file may shrink and should. Every
removal is a line in a diff.

```sh
.gates/no_hardcoding.py --baseline     # accept today's findings
.gates/no_hardcoding.py                # report everything, old and new
.gates/no_hardcoding.py --check        # exit 1 on anything not baselined
```

### Before adopting anywhere: survey first

```sh
~/Projects/ai-agent-utils/templates/gates/survey.sh no_hardcoding ~/Projects/*
```

Runs the gate read-only across every repository and prints a count each. That
is the "will this break something" question answered as a measurement rather
than a promise. A repository with three findings is worth fixing now; one with
forty-seven is worth baselining and leaving alone.

**Do not retrofit gates into dormant repositories.** A gate on something with
no commits coming is pure cost.

---

## A hook is local policy. An Action is not.

Every gate here runs in a git hook, which means it runs on one machine and is
bypassed by `--no-verify`, by committing from elsewhere, and by anyone else's
clone. `core.hooksPath` is local configuration, so a fresh clone has every
hook switched off until someone runs one command.

**The rule: a gate that matters belongs in both places.** The hook catches it
before the commit; the Action catches it when the hook did not run. Projects
seeded by `init-agent-project` get a `gates` job in `.github/workflows/ci.yml`
that runs every gate and then `prove_gates.sh`.

### When a private repository becomes public

Going public changes what the gates are for. Do these before flipping the
switch, not after:

1. **Hooks become Actions.** A private repository can live on local hooks
   because one person commits to it. A public one has readers, forks and
   contributors, none of whom have your hooks.
2. **Run every gate over the full history, not just the tip.** A secret
   removed in the tip is still in the history, and so is a local path.
3. **Check the publication boundary itself** if the repository has one — an
   export script, an excluded directory. Verify against the published tree,
   not against the script's own output.
4. **Check that Actions can actually run.** A workflow on a repository whose
   Actions minutes are exhausted never runs and never says so.

## Structural change means the README changes

A gate cannot check this, so it is written down: when the shape of a
repository changes — a new directory, a renamed artifact, a build step added
or removed, a data file that becomes the source of something it was not — the
README in that repository is part of the change, not a follow-up.

The test is a stranger cloning it an hour later. If what they read no longer
describes what they got, the change is not finished.

## Promoting a gate INTO the registry

`update_gates.sh` carries gates out of the registry into a repository.
Nothing carried one back in, so a gate written where a problem actually
surfaced stayed in that one repository — proven, wired into a hook, and absent
from this registry, from `prove_gates.sh`, and from the table above.
`check_version.py` then reported that repository as current while it ran gates
nothing here knew about.

```sh
templates/promote_gate.sh ~/Projects/some-repo/tools/check_thing.py
```

It **refuses before copying** unless two things already exist: a probe in
`tests/prove_gates.sh` naming the file, and a row in the registry table above.
That forces the order — the proof and the reason are prerequisites, not
follow-ups.

**Prove it where the gates are installed, never here.** `prove_gates.sh`
resolves its gate directory as `$ROOT/.gates` relative to its own location, so
run from the registry it skips every probe and cheerfully reports success on
nothing — a vacuous green. Run it from any repository carrying `.gates/`.

## Where the recursion stops

`prove_gates.sh` proves every gate fires. Nothing proves `prove_gates.sh`.

That is deliberate, and it is why the gates are stdlib Python and POSIX `sh`
with no dependencies: the last thing in the chain has to be small enough to
verify by reading it. If the test harness needed its own test framework, the
chain would not terminate.

---

## What this measures, and where the evidence lives

A loop that cannot be measured is a story about a loop. Four things are worth
counting, and the rest is noise:

| what | where it lives | committed? |
|---|---|---|
| **why a gate exists** | the registry above — one row, one failure mode | yes |
| **who has it** | `.gates/VERSION` per repository; `check_version.py` compares | yes |
| **the backlog** | `.gates/baseline/<gate>.txt` — findings accepted at adoption | yes |
| **what it caught** | `.gates/ledger.jsonl` — one line per run, blocked or passed | no, local and high-volume |

The aggregate is a dated snapshot, and it is the artifact to keep:

```sh
templates/gates/gates_report.sh ~/Projects/* > reports/gates-$(date -u +%F).md
```

Read it for two things, neither of which can be argued, only counted:

- **A baseline that has not shrunk since adoption** is a backlog nobody is
  working. That is allowed, but it should be said out loud rather than
  discovered later.
- **A gate with no blocks and no open findings** is either prevention working
  or dead weight. The count alone cannot tell you which — `prove_gates.sh`
  showing it still fires is what separates them.

The ledger is deliberately not committed: one line per run is noise in a diff,
and a file the hook writes during a commit is a file that changes the commit.
The committed record is the registry row, the baseline, and the dated
snapshot.

## Adding a gate

1. Write it in `templates/gates/`. Stdlib only. `--check` exits 1; bare run
   reports.
2. Support the baseline if it can fire on existing code — import `_baseline`.
3. Add a case to `tests/prove_gates.sh` in **both** directions: fires on a
   planted violation, quiet on a clean tree.
4. Add a row to the registry above, with the failure mode it prevents.
5. Bump the version at the top of this file and in `templates/gates/VERSION`.
6. Survey your repositories before adopting it in any of them.

## What does not go in this file

No dates, no repository names, no document titles, no durations, no counts
tied to a specific incident, and nothing about who made a mistake. A row
states the failure mode in the general case — enough for a reader to see why
the check is worth keeping, and nothing a reader could use to reconstruct a
particular event. The history is kept privately and is not part of this
repository.

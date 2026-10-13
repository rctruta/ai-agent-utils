# The gates

Every gate in this repository exists because something went wrong once. The
incident is recorded beside it, because a gate whose reason has been forgotten
is the first one somebody deletes.

A rule in a document binds nobody. Each of these is a script a git hook runs,
so it binds whoever is driving — you, Claude Code, Cursor, Gemini, or CI.

**Version: 2** — see *Adopting a new gate* below for how an existing repository
catches up.

---

## The registry

| gate | refuses | the incident |
|---|---|---|
| `verify.py` | a registered fact whose source no longer supports it | numbers in a résumé and on a site drifted from the repositories that produced them |
| `scan.py` | a banned claim; reports numbers registered nowhere | a fabricated run count reached a live job application |
| `no_hardcoding.py` | code restating a value its data file already holds | a generator rendered certificates as literal HTML while the same certificates sat in the YAML it was meant to read; the data was edited, the page kept showing the old copy with the years still in it |
| `no_local_paths.py` | a tracked file carrying one machine's absolute path | a generator was shared into a template with another repository's home path hardcoded in it |
| `checkpoint.sh` | saving a "known-good" state whose proof does not pass | a working configuration was changed, the change made it worse, and nothing recorded what working had looked like |
| `tests/prove_gates.sh` | — proves each gate above fires on a planted violation and stays quiet on a clean tree | an untested gate is theatre |

### Two gates that were fixed rather than added

- **`scan.py` no longer skips `.gates/`.** A gate that exempts its own directory
  cannot see what it is carrying: a privacy gate written after a real address
  leaked kept that address in its own docstring for two weeks, because its file
  was in its own skip list. The `allow:` block in `FACTS.yaml` is the escape
  valve — an exemption belongs in a diff, not in a skip list.

---

## Adopting a new gate in an existing repository

```sh
~/Projects/ai-agent-utils/templates/install_gates.sh --update
```

This copies gates newer than the ones already there and leaves everything else
alone. It does not fail your build on day one, because of the next section.

### The baseline, and why a new gate does not break old work

A gate added to an existing repository will fire on code that predates it. That
is a **backlog**, not a regression, and the two look identical from the outside:

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

**Do not retrofit gates into dormant repositories.** A gate on something with no
commits coming is pure cost.

---

## A hook is local policy. An Action is not.

Every gate here runs in a git hook, which means it runs on one laptop and is
bypassed by `--no-verify`, by committing from another machine, and by anyone
else's clone. That is by design — a hook is fast and it is honest about being
local — but it is not the whole story.

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
2. **Run every gate over the full history, not just the tip.** A secret removed
   in the tip is still in the history, and so is a local path.
3. **Check the publication boundary itself** if the repository has one — an
   export script, an excluded directory. Verify against the published tree, not
   against the script's own output.
4. **Check that Actions can actually run.** A workflow on a repository whose
   Actions minutes are exhausted never runs and never says so.

## Structural change means the README changes

A gate cannot check this, so it is written down: when the shape of a repository
changes — a new directory, a renamed artifact, a build step added or removed, a
data file that becomes the source of something it was not — the README in that
repository is part of the change, not a follow-up.

The test is a stranger cloning it an hour later. If what they read no longer
describes what they got, the change is not finished.

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
| **why a gate exists** | the registry above — one row, one incident | yes |
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
- **A gate with no blocks and no open findings** is either prevention working or
  dead weight. The count alone cannot tell you which — `prove_gates.sh` showing
  it still fires is what separates them.

The ledger is deliberately not committed: one line per run is noise in a diff,
and a file the hook writes during a commit is a file that changes the commit.
The committed record is the registry row, the baseline, and the dated snapshot.

## Adding a gate

1. Write it in `templates/gates/`. Stdlib only. `--check` exits 1; bare run reports.
2. Support the baseline if it can fire on existing code — import `_baseline`.
3. Add a case to `tests/prove_gates.sh` in **both** directions: fires on a
   planted violation, quiet on a clean tree.
4. Add a row to the registry above, with the incident.
5. Bump the version at the top of this file and in `templates/gates/VERSION`.
6. Survey your repositories before adopting it in any of them.

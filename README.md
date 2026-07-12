# AI Agent Utilities

*A small, honest toolkit for working with AI coding agents: one script that sets up a repo with enforced git discipline — hooks, branch protection, and an agent contract that documents the gates instead of pleading with the agent.*

## The Initialization Script: `init-agent-project.sh`

This script sets up a workspace with git guardrails for working with coding agents. It strips away opinionated application frameworks and focuses entirely on **Agent Hygiene**. (It does not sandbox anything — the hooks are local policy, bypassable by design; see the layered honesty notes below.)

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
- **"Add the optional same-tree agent-lock?"** — default **no**; say yes only for the narrow two-agents-in-one-directory case (see §2 of the manifesto for why most projects should decline).
- **"Create a GitHub repo and push it now?"** — If yes, it uses `gh` to create the remote and push in one step (see *Authentication* below — **no SSH key needed**). If no, it leaves you a ready local repo and prints the exact command to run later.

So the full flow is: **init → track → first commit → (optionally) create remote → push → (optionally) enable branch protection → open in VS Code**. The script can take you all the way to a protected repo open in your editor, or stop at the local commit if you prefer to drive the rest by hand.

When it creates the remote, it also offers to enable **branch protection** for you (layer 2). If you decline, it prints the exact command for you to run in your own terminal later — see §A.

### What it Provisions
1. **`AGENTS.md` (The Contract)**: A short map of the gates, placed in the root of your project. Every *enforceable* rule is backed by a mechanism; the few that can't be enforced locally (no `--no-verify`, no agent attribution) are explicitly labelled on-your-honor — and backstopped by branch protection where possible.
2. **`.githooks/pre-push` (The Gate Everyone Gets)**: Refuses to push a dirty working tree — *including untracked files* — or (for Python) a red test suite. This is **layer 1** — see the Rogue Agent Lesson for why you also need layer 2. Always provisioned. **Caveat: git hooks do not survive cloning.** `core.hooksPath` is local config; anyone (or any agent) working in a fresh clone has no hooks until they run `git config core.hooksPath .githooks` — the generated README stub says so up front.
3. **`.env.example`**: A safe template for LLM API keys and an `AGENT_ID`. Note: one `.env` holds one value — if you run multiple agents in one tree, give each *process* its own `AGENT_ID` via an environment export (an exported value wins over an empty `.env` line).
4. **`.vscode/settings.json`** (Python projects): pins the interpreter to the project venv on your machine, so VS Code activates the right environment. `.vscode/` is **gitignored** (editor state is personal), so this stays local. When the script opens the project in VS Code, a new integrated terminal auto-activates the venv (on the very first terminal you may need to press Enter once).
5. **`README.md` (stub)**: A starter README for the new project — because a hygiene tool that leaves you with no README would be its own small irony.

**Optional (off by default — the script asks, and most projects should say no):** a same-tree commit lock, for the narrow case of two agents sharing **one working directory**. If you opt in you also get:
- **`.githooks/pre-commit` (The Lock Gate)**: refuses any commit while another agent holds the lock.
- **`./agent-lock` (The Helper)**: one-command `acquire`/`release`/`status`.

Skip it unless you actually run two agents in one tree — across separate clones/branches it does nothing, and branch protection is the real gate (see §2).

> **A note on the irony of shipping an `AGENTS.md`.** I've measured that an
> `AGENTS.md` re-read into an agent's context every turn carries a real,
> recurring cost — so isn't shipping one a contradiction?
> No, because the file here **enforces nothing**: the hooks do. This
> `AGENTS.md` is the human-readable *map of the gates*, kept deliberately
> short, and it tells the agent outright that it doesn't need to memorize it —
> if it crosses a boundary, a gate stops it. Prose that *describes* a gate is
> fine; prose that *substitutes* for one is the anti-pattern. The ideal
> `AGENTS.md` shrinks toward empty as behavior moves into gates.

---

## Working with Git: the exact commands

The script makes the first commit locally and — if you say yes to its prompts —
creates the GitHub remote, pushes, and even offers to enable **branch
protection** for you. It only ever *offers* the policy steps (push, protection);
it never forces them, so you stay in control of what goes public and when. Here
is the whole path either way, for when you want to drive it by hand.

### Authentication first (the part nobody explains — and you do NOT need an SSH key)

`gh` (the GitHub CLI) authenticates over **HTTPS with a token it manages**. Run
this **once per machine**:

```bash
gh auth login        # pick: GitHub.com → HTTPS → login in browser
gh auth setup-git    # makes plain `git push` reuse gh's token too
```

After that, `gh repo create --push`, `git push`, and pushing from **VS Code**
all work with no SSH key and no password prompts. (If you *saw* VS Code ask for
`https://github.com...` credentials, that's the symptom of git having an HTTPS
remote but no stored credential — `gh auth setup-git` is the fix.)

*Prefer SSH keys?* You can — generate a key, add it to GitHub, and use SSH
remotes (`git@github.com:owner/repo.git`). It's more setup for the same result.
The `gh`/HTTPS path above is why this tool's commands need no key.

### A. First push to GitHub (once per project)

The script offers to do this for you. To do it by hand (or if you skipped the
prompt), from inside the project:

```bash
gh repo create <owner>/<project> --private --source=. --remote=origin --push
```

Then lock the gate — **layer 2, do it before any agent runs:**

```bash
gh api -X PUT repos/<owner>/<project>/branches/main/protection \
  -F "required_pull_request_reviews[required_approving_review_count]=0" \
  -F enforce_admins=true \
  -F required_status_checks=null \
  -F restrictions=null
# (or: GitHub → Settings → Branches → Add rule → Require a PR +
#  Include administrators)
```

Two facts about this command, learned the hard way:
- **The bracket syntax is required.** `gh api -F` does *not* nest dotted keys —
  the dotted form sends a literal field name and the API rejects it with 422
  (verified live). If you find the dotted variant in an older revision of this
  repo, it never worked.
- **Private repos need GitHub Pro** for branch protection; on a free plan this
  call returns 403 for a private repo. Make the repo public or upgrade.

From here on, **direct pushes to `main` are rejected** — humans and agents both
work on branches and open PRs (verified: a direct push fails with `GH006`,
even for the repo admin, thanks to `enforce_admins`). **Be honest about what
this does and doesn't do:** with 0 required reviews and no required status
checks, it forces every change through a PR — visibility and a paper trail —
but it does **not** stop an agent from opening a PR and merging it itself.
To make the gate *block* rather than *record*, add required status checks
(you'll need a CI workflow — this script doesn't create one) or a required
review count ≥ 1.

### B. The daily branch workflow

```bash
git checkout main
git pull origin main            # start from the truth, always
git checkout -b feat/<thing>    # never work on main

# ... make changes; (./agent-lock acquire first, only if you opted into
#     the same-tree lock at setup) ...

git add -A
git commit -m "clear message"   # pre-commit + pre-push gates run here / on push
git push -u origin feat/<thing>
gh pr create --fill
# after CI/review: gh pr merge --squash --delete-branch   (NOT --admin)
```

### C. Switching to / syncing a different branch (the part that bites)

```bash
# See where you are and whether the tree is clean FIRST:
git status --short && git branch --show-current

# Switch to an existing branch (tree must be clean — commit or stash first):
git fetch origin
git checkout <branch>
git pull origin <branch>

# Bring your feature branch up to date with main:
git checkout feat/<thing>
git fetch origin
git merge origin/main           # or: git rebase origin/main
```

**The one that cost me hours** — after a PR is squash-merged, your local `main`
has the *raw* commits while `origin/main` has *one* squashed commit, so git
sees "divergence" and `git pull` refuses with *"not possible to fast-forward."*
When your local commits are already merged via the PR, the fix is to make local
`main` a clean mirror of the remote:

```bash
git checkout main
git fetch origin
git reset --hard origin/main    # SAFE only when your local commits already
                                # landed in the PR; it DISCARDS local main commits
```

Guardrails so you never need the escape hatch: keep `main` a pure mirror of
`origin/main` (never commit to it directly — always branch), and `git fetch`
before you branch so you start from current truth.

---

## The Manifesto: Why Agent Hygiene is Mandatory

If you are using autonomous coding agents, you are no longer the only developer on your repository. You are an orchestrator managing highly capable but structurally blind delegates. 

Without explicit boundaries, agents will silently fracture your repository's state. Here are the core lessons learned from the frontier of multi-agent development.

### 1. The Rogue Agent Lesson (Why CI is not enough)
*Never rely on GitHub Actions or remote CI as your primary security gate.* 

In a recent experiment, an autonomous agent successfully passed its local tests and opened a Pull Request. When the remote CI workflow failed, the agent did not attempt to fix the failing tests. Instead, it noticed it had GitHub CLI (`gh`) access and simply executed:
`gh pr merge --admin`

It bypassed the red CI workflow using administrator privileges and merged the broken code directly into `main`. **The gate has to run on the pusher's machine.**

This repository provisions a strict local `.githooks/pre-push` script that aborts the `git push` before the bytes leave your laptop. **But be honest about its limit:** a git hook is bypassable with `git push --no-verify`, which is the local-layer equivalent of `gh pr merge --admin`. An agent willing to reach for one flag will reach for the other. So the hook is **layer 1** — it stops honest mistakes and non-adversarial agents. **Layer 2 is remote branch protection with *Include administrators* enabled** (see §3): a `--no-verify` push straight to a protected `main` is rejected by GitHub itself (`GH006`), which the flag cannot bypass. Be precise about layer 2's limit too: as configured here (0 required reviews, no required status checks — generated projects ship no CI), it forces every change through a PR but does not stop an agent merging its own PR. It converts a silent bypass into a visible, attributable one. To make it *block*, add required checks or reviews — see §A. Use both layers; neither alone is a gate.

### 2. Multi-Agent Traffic Control (The Lockfile Protocol) — *optional, you probably don't need it*

**Read this as a cautionary tale, not a recommended default.** The real fix for
agents colliding is structural: one agent per branch, `main` protected, PRs to
merge. A same-tree lockfile only helps the narrow case where two agents share
**one working directory** — and even then it has hard limits (below). It's
**off by default**; the script asks before provisioning it. Most repos —
including the ones I built this for — don't turn it on. Here's the mechanism
anyway, honestly scoped.

If you use multiple agents in the same working tree, they can overwrite each other. **Agents are blind to each other's unpushed, uncommitted local edits.**

Here is the trap I fell into first, and the fix. A lockfile protocol written **as prose** in `AGENTS.md` — "check for `.agent_lock` before you start" — is just another word, and words don't bind: an agent that never reads the file, or reads it and doesn't bother, overwrites you anyway. So this utility makes the lock a **gate**:

- **`./agent-lock acquire`** writes the lock (stamped with the holder's identity + time). It refuses if another live agent holds it.
- **`.githooks/pre-commit`** independently **refuses any commit while a foreign lock is held** — so an agent that skips `acquire` entirely still cannot commit over you.
- **`./agent-lock release`** clears it after you push. A crashed agent's lock **auto-expires after 4h**, so a dead holder never deadlocks the repo.

**Honest scope.** Be realistic about what this mechanism actually protects:
- **Zero protection across separate clones.** The `.agent_lock` file is deliberately **gitignored**. It stays local and is never committed or pushed. Each clone has its own lockfile. For collaboration across different clones, you MUST rely on remote branch protection and PRs (layer 2).
- **Protection only within the SAME working directory.** This is where the lock works, but identity is **opt-in per agent**: if you do not give each agent a distinct `AGENT_ID`, both fall back to your `git user.email`. The hook thinks they are the same agent and allows them to commit over each other. And since both agents share the *same* `.env` file, distinct IDs cannot live there — export `AGENT_ID` in each agent's own process environment (an exported value takes precedence over an empty `.env` line).
- **The lock gates commits, not concurrent typing.** The `pre-commit` hook only fires at commit time. Two agents in one tree can still clobber each other's *unsaved/uncommitted* work before any commit happens. The lock serializes commits; it doesn't magically prevent concurrent editing.

*If all of the above sounds like more machinery than your problem deserves — it probably is. One agent per branch, protected `main`, PRs to merge: that's the actual solution.*

### 3. Branch Protection & The Chicken-and-Egg Problem
You should always protect your `main` branch on GitHub, requiring Pull Requests for all changes. Agents should only ever work on feature branches.

However, you cannot protect a branch that doesn't exist. When starting a new project using this script:
1. Push your initial commit directly to main (`git push -u origin main`).
2. Immediately go to GitHub Settings -> Branches -> Add branch protection rule (or run the §A command — note the private-repo/Pro limitation there).
3. Enforce **Require a pull request before merging** and — critically — **Include administrators** (in the API, `enforce_admins: true`). Add **Require status checks to pass** only once the project actually has CI; requiring checks that never run blocks every merge.

That last box is what closes the direct-push hole: with administrators included, even you cannot push straight to `main` (`GH006`, verified). Remember §1's caveat — without required checks or reviews, a PR is a paper trail, not a blocker. From that moment on both layers are doing exactly what they honestly can, and your agents operate in branches.

---
## License

MIT — do whatever you want with it; no warranty. See `LICENSE`.

*(Generated projects don't get a license automatically — that's your call
per project. The README stub reminds you to add one; MIT is a fine default.)*

---
*Built with hard-won wisdom from the [SQL Benchmarking Laboratory](https://github.com/rctruta/sql-benchmarks-dagster).*

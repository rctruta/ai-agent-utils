#!/usr/bin/env python3
"""Build the public export of this repository, and optionally push it.

    python publish.py                 assemble the export and report
    python publish.py --push          also commit and push it
    python publish.py --push -m "..." with a commit message

Replaces publish_public.sh. The shell version hardcoded the remotes, the
export path, the git identity, and the include and exclude lists, and it was
built on `tar`, `comm` and `grep -E`, none of which exist on Windows. Every
one of those values now lives in export_config.yaml, and everything here is
stdlib plus pydantic, so the decision is reviewable in one file and the code
runs anywhere Python does.

What it does, in order: refuse unless `origin` is the private remote; select
files by the config's include list; drop anything matching the exclude
patterns; copy the selection into a temp directory; apply the substitutions;
refuse on a leak check; report what was held back; push only when asked.
"""
from __future__ import annotations

import argparse
import logging
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, List

import yaml
from pydantic import BaseModel, Field

REPO = Path(__file__).resolve().parent
CONFIG_PATH = REPO / "export_config.yaml"

logging.basicConfig(level=logging.INFO, format="%(message)s")
log = logging.getLogger("publish")


# ---------------------------------------------------------------- config

class Remotes(BaseModel):
    private: str
    public: str


class Include(BaseModel):
    directories: List[str] = Field(default_factory=list)
    files: List[str] = Field(default_factory=list)


class LeakChecks(BaseModel):
    local_paths: List[str] = Field(default_factory=list)
    secrets: List[str] = Field(default_factory=list)
    # Literal phrases that must not appear in the export, wherever they live.
    # A filename rule cannot catch a held-back note whose CONTENT was pasted
    # into a published file; this does. Matched literally, not as a regex, so
    # a phrase with punctuation in it needs no escaping.
    forbidden_content: List[str] = Field(default_factory=list)


class Commit(BaseModel):
    author_name: str
    author_email: str
    default_message: str


class ExportConfig(BaseModel):
    """The entire publishing decision, validated rather than assumed.

    Pydantic and not a dict: a typo in a key name should stop the run before
    anything is assembled, not publish a smaller set than intended and say
    nothing.
    """
    remotes: Remotes
    export_dir: str = ""
    include: Include
    exclude_patterns: List[str] = Field(default_factory=list)
    substitutions: Dict[str, str] = Field(default_factory=dict)
    leak_checks: LeakChecks
    commit: Commit

    @classmethod
    def load(cls, path: Path) -> "ExportConfig":
        if not path.is_file():
            raise SystemExit(f"no config at {path}")
        return cls(**yaml.safe_load(path.read_text(encoding="utf-8")))


# ---------------------------------------------------------------- helpers

def git(*args: str, cwd: Path = REPO) -> str:
    """Run git and return its stdout. Raises on a non-zero exit, because a
    silent git failure here would produce a wrong export rather than none."""
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True,
                       text=True, check=True)
    return r.stdout


def tracked_files() -> List[str]:
    """Every file git tracks, as repo-relative POSIX paths.

    -z and a split on NUL rather than on newline: a filename may contain a
    newline, and splitting on one would silently mangle it.
    """
    out = git("ls-files", "-z")
    return [p for p in out.split("\0") if p]


def select(files: List[str], cfg: ExportConfig):
    """Split the tracked set into what is published and what is held back."""
    wanted_dirs = tuple(f"{d.rstrip('/')}/" for d in cfg.include.directories)
    wanted_files = set(cfg.include.files)
    excluded = re.compile("|".join(cfg.exclude_patterns), re.I) \
        if cfg.exclude_patterns else None

    kept, held = [], []
    for f in files:
        named = f.startswith(wanted_dirs) or f in wanted_files
        if named and not (excluded and excluded.search(f)):
            kept.append(f)
        else:
            held.append(f)
    return sorted(kept), sorted(held)


def assemble(kept: List[str], cfg: ExportConfig, dest: Path) -> None:
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    for rel in kept:
        target = dest / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPO / rel, target)
    for src, as_name in cfg.substitutions.items():
        if (REPO / src).is_file():
            shutil.copy2(REPO / src, dest / as_name)


def leak_check(dest: Path, cfg: ExportConfig) -> List[str]:
    """Scan the assembled export. Returns the problems found, empty if clean.

    Runs on what is about to be pushed rather than on the source, so a file
    that arrived through a substitution is checked too.
    """
    patterns = [(p, "a local path") for p in cfg.leak_checks.local_paths] + \
               [(p, "a credential") for p in cfg.leak_checks.secrets]
    compiled = [(re.compile(p), why) for p, why in patterns] + \
               [(re.compile(re.escape(p)), "held-back content")
                for p in cfg.leak_checks.forbidden_content]
    problems = []
    for path in sorted(dest.rglob("*")):
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for rx, why in compiled:
            if rx.search(text):
                problems.append(f"{path.relative_to(dest)}: {why} "
                                f"matching {rx.pattern!r}")
    return problems


def report_held_back(held: List[str]) -> None:
    """Say what is NOT being published, every run.

    An allow-list fails in the opposite direction to a deny-list: something
    that should go out is silently never added. Printing the held-back set is
    the only thing that makes that visible.
    """
    if not held:
        log.info("  nothing held back")
        return
    counts: Dict[str, int] = {}
    for f in held:
        counts[f.split("/")[0]] = counts.get(f.split("/")[0], 0) + 1
    for name, n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
        log.info("  %4d  %s", n, name)


def verify_export(dest: Path) -> int:
    """Run the export's OWN test suite, inside the export.

    This is the boundary check. The export declares what is public; if a
    published test reaches for something that was held back, it fails HERE,
    before anything leaves the machine.

    It catches the case nobody can predict -- a file becomes private later,
    is dropped from `include`, and a public test quietly depended on it.
    Testing the artifact rather than the intention is what makes that
    detectable without knowing in advance which file it will be.

    The failure this exists for: a test suite reads files its repository
    does not carry -- something gitignored, or something outside the tree
    entirely. It passes locally forever, because locally the files are
    there. A suite that runs nowhere but one machine is not the gate it is
    taken for.

    Returns pytest's exit code; 5 (no tests collected) is not a failure,
    since an export may legitimately ship none.
    """
    import subprocess as sp
    if not any(dest.rglob("test_*.py")):
        log.info("  no tests in the export, nothing to verify")
        return 0
    r = sp.run([sys.executable, "-m", "pytest", "-q", "--no-header"],
               cwd=dest, capture_output=True, text=True)
    tail = (r.stdout or r.stderr).strip().splitlines()
    log.info("  %s", tail[-1] if tail else "(no output)")
    if r.returncode == 5:
        return 0
    if r.returncode != 0:
        for line in tail[-12:]:
            log.error("    %s", line)
    return r.returncode


def push(dest: Path, cfg: ExportConfig, message: str) -> None:
    git("init", "-q", cwd=dest)
    git("config", "user.name", cfg.commit.author_name, cwd=dest)
    git("config", "user.email", cfg.commit.author_email, cwd=dest)
    git("add", "-A", cwd=dest)
    git("commit", "-q", "-m", message, cwd=dest)
    git("remote", "add", "origin", cfg.remotes.public, cwd=dest)
    git("push", "-f", "origin", "HEAD:main", cwd=dest)
    log.info("pushed to %s", cfg.remotes.public)


# ---------------------------------------------------------------- main

def main(argv: List[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--push", action="store_true",
                    help="commit and push the export to the public remote")
    ap.add_argument("-m", "--message", default=None, help="commit message")
    ap.add_argument("--config", type=Path, default=CONFIG_PATH)
    ap.add_argument("--no-verify", action="store_true",
                    help="skip running the export's own tests (not advised)")
    args = ap.parse_args(argv)

    cfg = ExportConfig.load(args.config)

    origin = git("remote", "get-url", "origin").strip()
    if origin != cfg.remotes.private:
        log.error("REFUSING: origin is %s, not the private remote.", origin)
        log.error("  git remote set-url origin %s", cfg.remotes.private)
        return 2

    kept, held = select(tracked_files(), cfg)
    dest = Path(cfg.export_dir) if cfg.export_dir else \
        Path(tempfile.gettempdir()) / f"{REPO.name}-public"
    assemble(kept, cfg, dest)

    log.info("--- held back (not named in include)")
    report_held_back(held)
    log.info("exported %d files to %s", sum(1 for _ in dest.rglob("*")
                                            if _.is_file()), dest)

    log.info("--- leak checks")
    problems = leak_check(dest, cfg)
    if problems:
        for p in problems:
            log.error("  REFUSING: %s", p)
        return 1
    log.info("  clean")

    if not args.no_verify:
        log.info("--- the export's own test suite")
        rc = verify_export(dest)
        if rc != 0:
            log.error("  REFUSING: the published tests do not pass inside the "
                      "export.\n  A public test is reaching for something "
                      "held back. Add it to `include`, or make the test "
                      "declare the precondition and skip.")
            return 1

    if args.push:
        push(dest, cfg, args.message or cfg.commit.default_message)
    else:
        log.info("\nReview %s, then: python publish.py --push -m \"message\"",
                 dest)
    return 0


if __name__ == "__main__":
    sys.exit(main())

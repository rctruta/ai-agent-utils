#!/bin/sh
# prove_gates.sh — demonstrate that each gate actually FIRES.
# An untested gate is theatre. This is the same discipline as prove_lock.sh.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
G="$ROOT/.gates"
PASS=0; FAIL=0; SKIP=0
# A repository may adopt some gates and not others — this one already had a
# claim gate of its own, so it took only the two new ones. A probe for a gate
# that is not installed is skipped, not failed.
have() { [ -f "$G/$1" ] || { echo "  SKIP  $1 not installed here"; SKIP=$((SKIP+1)); return 1; }; }
ok()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

echo "Proving the gates fire..."

if have scan.py; then
# 1. scan.py must BLOCK a banned claim
TMP="$ROOT/.gates/.probe.md"
cp "$G/FACTS.yaml" "$G/FACTS.yaml.bak"
printf 'facts: []\nbanned:\n  - pattern: "ZZPROBE9"\n    reason: "test probe"\nallow: []\n' > "$G/FACTS.yaml"
echo "This document contains ZZPROBE9 which is banned." > "$TMP"
if python3 "$G/scan.py" --check --quiet "$TMP" >/dev/null 2>&1; then
  bad "scan.py did NOT block a banned claim"
else
  ok "scan.py blocks a banned claim"
fi
rm -f "$TMP"; mv "$G/FACTS.yaml.bak" "$G/FACTS.yaml"

# 2. scan.py must PASS a clean file
echo "Nothing objectionable here." > "$TMP"
if python3 "$G/scan.py" --check --quiet "$TMP" >/dev/null 2>&1; then
  ok "scan.py passes a clean file"
else
  bad "scan.py false-positived on a clean file"
fi
rm -f "$TMP"

fi

if have verify.py; then
# 3. verify.py must FAIL a fact whose source does not support it.
# Written as a complete file so it does not depend on where sections sit.
cp "$G/FACTS.yaml" "$G/FACTS.yaml.bak"
echo "this scratch file contains nothing of interest" > "$G/.probe.src"
cat > "$G/FACTS.yaml" <<'YAML'
facts:
  - id: probe_should_fail
    claim: "999999"
    context: "probe"
    status: verified
    source: .gates/.probe.src
    grep: "999999"
banned: []
allow: []
YAML
if python3 "$G/verify.py" --check >/dev/null 2>&1; then
  bad "verify.py did NOT fail an unsupported fact"
else
  ok "verify.py fails an unsupported fact"
fi
mv "$G/FACTS.yaml.bak" "$G/FACTS.yaml"; rm -f "$G/.probe.src"

fi

# 6. the pre-commit hook must exist and be executable
if [ -x "$ROOT/.githooks/pre-commit" ]; then
  ok "pre-commit hook present and executable"
else
  bad "pre-commit hook missing or not executable"
fi

if have no_hardcoding.py; then
# 7. no_hardcoding must BLOCK a value that a data file already holds
PROBE="$ROOT/.gates/.probe"
mkdir -p "$PROBE/data" "$PROBE/tools" "$PROBE/.gates"
cp "$G/no_hardcoding.py" "$G/_baseline.py" "$PROBE/.gates/"   # gate + its baseline helper
printf 'certs:\n  - "Large Language Models - Example Body"\n' > "$PROBE/data/x.yaml"
printf "    f'    <li>Large Language Models &mdash; Example Body, 2023</li>'\n" > "$PROBE/tools/gen.py"
# the gate reads only git-tracked files, so the probe has to be a repository
(cd "$PROBE" && git init -q && git add -A) >/dev/null 2>&1
if python3 "$PROBE/.gates/no_hardcoding.py" --check >/dev/null 2>&1; then
  bad "no_hardcoding did NOT block a value restated from data"
else
  ok "no_hardcoding blocks a value restated from data"
fi
# and must stay quiet when the generator reads its data instead
printf "import yaml  # reads data/x.yaml\n" > "$PROBE/tools/gen.py"
(cd "$PROBE" && git add -A) >/dev/null 2>&1
if python3 "$PROBE/.gates/no_hardcoding.py" --check >/dev/null 2>&1; then
  ok "no_hardcoding is quiet when nothing is restated"
else
  bad "no_hardcoding fired on a clean tree"
fi
rm -rf "$PROBE"

fi

if have no_hardcoding.py; then
# 9. the baseline must accept old findings and still block new ones. This is
#    what makes a gate adoptable in a repository that predates it.
BPROBE="$ROOT/.gates/.bprobe"
mkdir -p "$BPROBE/.gates" "$BPROBE/data" "$BPROBE/tools"
cp "$G/no_hardcoding.py" "$G/_baseline.py" "$BPROBE/.gates/"
printf 'certs:\n  - "An Old Finding - Example Body"\n' > "$BPROBE/data/x.yaml"
printf "    f'<li>An Old Finding &mdash; Example Body, 2023</li>'\n" > "$BPROBE/tools/gen.py"
(cd "$BPROBE" && git init -q && git add -A) >/dev/null 2>&1
python3 "$BPROBE/.gates/no_hardcoding.py" --baseline >/dev/null 2>&1
if python3 "$BPROBE/.gates/no_hardcoding.py" --check >/dev/null 2>&1; then
  ok "baseline accepts a finding that predates the gate"
else
  bad "baseline did NOT accept a pre-existing finding"
fi
printf 'certs:\n  - "An Old Finding - Example Body"\n  - "A New Finding - Other Body"\n' > "$BPROBE/data/x.yaml"
printf "    f'<li>An Old Finding &mdash; Example Body, 2023</li>'\n    f'<li>A New Finding &mdash; Other Body</li>'\n" > "$BPROBE/tools/gen.py"
(cd "$BPROBE" && git add -A) >/dev/null 2>&1
if python3 "$BPROBE/.gates/no_hardcoding.py" --check >/dev/null 2>&1; then
  bad "baseline swallowed a NEW finding"
else
  ok "baseline still blocks a new finding"
fi
rm -rf "$BPROBE"

fi

# ---------------------------------------------------------------- voice -----

# ---------------------------------------------------------------- wheel -----
# A published wheel can carry files that are not the package at all -- nested
# build directories, a virtualenv, test trees, local scripts with home-directory
# paths -- as the bulk of the download, with `python -m build` exiting 0
# throughout.
if have check_wheel.py; then
  WP="$(mktemp -d)"
  mkdir -p "$WP/dist"
  cp "$G/check_wheel.py" "$WP/"

  # Assembled, never literal: this file is installed into every seeded
  # project, and a fixture indistinguishable from what it tests for blocks the
  # first commit of a fresh one.
  HOMEISH="/U""sers/someone/Projects/thing"
  python3 - "$WP" "$HOMEISH" <<'MKWHL'
import sys, zipfile, os
d, HOMEISH = sys.argv[1], sys.argv[2]
def build(name, extra):
    with zipfile.ZipFile(os.path.join(d, "dist", name), "w") as z:
        z.writestr("sql_benchmarks/__init__.py", "x = 1\n")
        z.writestr("pkg-0.1.dist-info/METADATA", "Name: pkg\n")
        for p, body in extra:
            z.writestr(p, body)
build("clean-0.1-py3-none-any.whl", [])
build("dirty-0.1-py3-none-any.whl",
      [("scratch/notes.py", "P = '" + HOMEISH + "'\n")])
MKWHL

  if python3 "$WP/check_wheel.py" "$WP/dist/clean-0.1-py3-none-any.whl" >/dev/null 2>&1; then
    ok "check_wheel passes a wheel holding only the package"
  else
    bad "check_wheel rejected a clean wheel"
  fi
  if python3 "$WP/check_wheel.py" "$WP/dist/dirty-0.1-py3-none-any.whl" >/dev/null 2>&1; then
    bad "check_wheel MISSED scratch/ and a home path in the wheel"
  else
    ok "check_wheel refuses a wheel carrying scratch/ and a home path"
  fi
  rm -rf "$WP"
fi

# --------------------------------------------------------------- orphans ----
# The cause: code exists, is tested, and is wired to nothing, so a passing test
# certifies a feature that never runs. One shape: a DDL generator
# producing PK/index/FK statements from the config, with a passing unit test,
# imported by nothing in the live path -- so `primary_key: true` in every
# config was declared-but-unenforced behind a green tick.
if have no_orphans.py; then
  OP="$(mktemp -d)"
  mkdir -p "$OP/.gates" "$OP/pkg/plugins" "$OP/tests" "$OP/conf"
  cp "$G/no_orphans.py" "$G/_baseline.py" "$OP/.gates/"
  (cd "$OP" && git init -q) >/dev/null 2>&1

  printf 'def used(): return 1\n' > "$OP/pkg/helper.py"
  printf 'from pkg.helper import used\ndef run(): return used()\n' > "$OP/pkg/live.py"
  printf 'class Gen:\n    def sql(self): return "CREATE INDEX"\n' > "$OP/pkg/ddl.py"
  printf 'from pkg.ddl import Gen\ndef test_g(): assert Gen().sql()\n' > "$OP/tests/test_ddl.py"
  (cd "$OP" && git add -A) >/dev/null 2>&1

  if (cd "$OP" && python3 .gates/no_orphans.py --check) >/dev/null 2>&1; then
    bad "no_orphans MISSED a module only its own test imports"
  else
    ok "no_orphans refuses a module only its own test imports"
  fi

  # Live code importing it must clear the finding.
  printf 'from pkg.ddl import Gen\ndef wire(): return Gen()\n' >> "$OP/pkg/live.py"
  (cd "$OP" && git add -A) >/dev/null 2>&1
  if (cd "$OP" && python3 .gates/no_orphans.py --check) >/dev/null 2>&1; then
    ok "no_orphans goes quiet once live code imports it"
  else
    bad "no_orphans still fired after the module was wired in"
  fi

  # A plugin resolved by dotted string from a config is reached without any
  # import statement, and is not an orphan.
  printf 'def generate(): return []\n' > "$OP/pkg/plugins/gen.py"
  printf 'from pkg.plugins.gen import generate\ndef test_p(): assert generate()==[]\n' > "$OP/tests/test_p.py"
  printf 'dataset:\n  source: pkg.plugins.gen\n' > "$OP/conf/e.yaml"
  (cd "$OP" && git add -A) >/dev/null 2>&1
  if (cd "$OP" && python3 .gates/no_orphans.py --check) >/dev/null 2>&1; then
    ok "no_orphans spares a plugin named in a config"
  else
    bad "no_orphans flagged a plugin a config resolves by name"
  fi

  # The bug this case pins: a relative import was invisible, so the first
  # version reported sixteen orphans in a working repository -- every one of
  # them imported by a sibling with `from .x import Y`.
  mkdir -p "$OP/pkg/resources"
  printf '' > "$OP/pkg/resources/__init__.py"
  printf 'class Duck:\n    pass\n' > "$OP/pkg/resources/duck.py"
  printf 'from .duck import Duck\nclass Quack(Duck):\n    pass\n' > "$OP/pkg/resources/quack.py"
  printf 'from pkg.resources.duck import Duck\ndef test_d(): assert Duck\n' > "$OP/tests/test_duck.py"
  printf 'from pkg.resources.quack import Quack\ndef hold(): return Quack\n' >> "$OP/pkg/live.py"
  (cd "$OP" && git add -A) >/dev/null 2>&1
  if (cd "$OP" && python3 .gates/no_orphans.py --check) >/dev/null 2>&1; then
    ok "no_orphans resolves a relative import and spares the sibling"
  else
    bad "no_orphans flagged a module imported relatively by a sibling"
  fi
  rm -rf "$OP"
fi

# -------------------------------------------------------------- scratch -----
# A repository can carry `scratch/` in .gitignore and a tracked note under that
# same path at once. An ignore rule is consulted only for files git does not
# already track, so it stays silent indefinitely. These probes assert the
# arrangement that makes the rule
# unnecessary -- notes outside the worktree, where git refuses to stage them.
if have scratch_external.py; then
  SP="$(mktemp -d)"; SX="$(mktemp -d)"
  mkdir -p "$SP/.gates"
  cp "$G/scratch_external.py" "$G/_baseline.py" "$SP/.gates/"
  (cd "$SP" && git init -q && git commit -q --allow-empty -m init) >/dev/null 2>&1

  # 1. No notes folder at all. This gate refuses a leaky one; it does not
  #    demand one exist, or every repository would fail on adoption.
  if (cd "$SP" && python3 .gates/scratch_external.py --check) >/dev/null 2>&1; then
    ok "scratch_external quiet when there is no notes folder"
  else
    bad "scratch_external fired on a repository with no notes folder"
  fi

  # 2. The arrangement it exists to enforce: outside the worktree, ignored.
  mkdir -p "$SX/notes-store"
  ln -s "$SX/notes-store" "$SP/scratch"
  echo "a private draft" > "$SX/notes-store/draft.md"
  printf 'scratch\n' > "$SP/.gitignore"
  (cd "$SP" && git add -A) >/dev/null 2>&1
  if (cd "$SP" && python3 .gates/scratch_external.py --check) >/dev/null 2>&1; then
    ok "scratch_external quiet on an external, ignored notes folder"
  else
    bad "scratch_external fired on the arrangement it is meant to accept"
  fi

  # 3. git must refuse to stage through the link. This is the guarantee the
  #    whole design rests on, so it is proven here and not assumed.
  if (cd "$SP" && git add scratch/draft.md) >/dev/null 2>&1; then
    bad "git staged a file through the symlink -- the design premise is wrong"
  else
    ok "git refuses to stage a file through the symlink"
  fi

  # 4. A real directory inside the worktree: nothing has leaked, but the
  #    contents are one `git add -A` away from it.
  rm "$SP/scratch"; mkdir -p "$SP/scratch"
  echo "a private draft" > "$SP/scratch/draft.md"
  if (cd "$SP" && python3 .gates/scratch_external.py --check) >/dev/null 2>&1; then
    bad "scratch_external MISSED a real notes directory in the worktree"
  else
    ok "scratch_external refuses a real notes directory in the worktree"
  fi

  # 5. The symlink that points back inside the worktree -- the arrangement
  #    that looks right and defeats itself.
  rm -rf "$SP/scratch"; mkdir -p "$SP/inside"
  ln -s ./inside "$SP/scratch"
  if (cd "$SP" && python3 .gates/scratch_external.py --check) >/dev/null 2>&1; then
    bad "scratch_external MISSED a symlink resolving inside the worktree"
  else
    ok "scratch_external refuses a symlink resolving inside the worktree"
  fi
  rm -rf "$SP/scratch" "$SP/inside"

  # 6. The specimen itself, reproduced exactly: a note tracked in the index
  #    while .gitignore names the folder. The rule is present and powerless.
  mkdir -p "$SP/scratch"
  echo "a private draft" > "$SP/scratch/draft.md"
  (cd "$SP" && git add -f scratch/draft.md && git commit -q -m "the specimen") >/dev/null 2>&1
  if (cd "$SP" && python3 .gates/scratch_external.py --check) >/dev/null 2>&1; then
    bad "scratch_external MISSED a tracked note that .gitignore claims to cover"
  else
    ok "scratch_external refuses a tracked note despite the ignore rule"
  fi

  # 7. --baseline must REFUSE while that note is tracked. A baseline records a
  #    backlog; an already-published private note is not a backlog, and
  #    accepting it would launder the leak into a committed approval.
  if (cd "$SP" && python3 .gates/scratch_external.py --baseline) >/dev/null 2>&1; then
    bad "scratch_external baselined a TRACKED note -- it must refuse"
  else
    ok "scratch_external refuses to baseline a tracked note"
  fi
  [ -f "$SP/.gates/baseline/scratch_external.txt" ] \
    && bad "scratch_external wrote a baseline file while refusing" \
    || ok "scratch_external wrote no baseline file when it refused"

  # 8. Untrack it, and the structural finding alone IS baselineable -- so a
  #    repository can adopt the gate mid-migration without blocking commits.
  (cd "$SP" && git rm -q --cached scratch/draft.md) >/dev/null 2>&1
  if (cd "$SP" && python3 .gates/scratch_external.py --baseline) >/dev/null 2>&1; then
    ok "scratch_external baselines a structural finding once nothing is tracked"
  else
    bad "scratch_external refused to baseline a purely structural finding"
  fi
  if (cd "$SP" && python3 .gates/scratch_external.py --check) >/dev/null 2>&1; then
    ok "scratch_external passes once the structural finding is baselined"
  else
    bad "scratch_external still blocked after its finding was baselined"
  fi

  # 9. The baseline must not swallow a NEW tracked note afterwards.
  echo "another private draft" > "$SP/scratch/second.md"
  (cd "$SP" && git add -f scratch/second.md) >/dev/null 2>&1
  if (cd "$SP" && python3 .gates/scratch_external.py --check) >/dev/null 2>&1; then
    bad "the baseline swallowed a newly tracked note"
  else
    ok "scratch_external still blocks a newly tracked note after baselining"
  fi
  rm -rf "$SP" "$SX"
fi

# ------------------------------------------------------- private marker -----

# ------------------------------------------------------ publish contract -----
# Three silent drifts of one shape, in the
# artifacts that define a public listing: a manifest naming the previous
# version, a manifest and ownership token that existed only on an unpushed
# local branch, and a CITATION.cff three releases stale. The registry being
# published to checked none of it.
#
# Each probe writes its own contract rather than patching the shipped one.
# Editing the real file with string replacement made these probes fragile and
# twice reported the gate as broken when the probe was.
if have check_publish_contract.py; then
  CP="$(mktemp -d)"
  mkdir -p "$CP/.gates"
  cp "$G/check_publish_contract.py" "$CP/.gates/"
  (cd "$CP" && git init -q && git commit -q --allow-empty -m init) >/dev/null 2>&1
  CT="$CP/.gates/publish_contract.toml"
  run_cp() { (cd "$CP" && python3 .gates/check_publish_contract.py --check) ; }

  cat > "$CT" <<'TOMLEOF'
[version_source]
path = "pyproject.toml"
kind = "toml_project_version"

[[surfaces]]
id = "npm"
status = "planned"
trigger = "package.json"
why = "probe surface"
TOMLEOF

  # 1. A planned surface whose trigger is absent: nothing to do.
  if run_cp >/dev/null 2>&1; then
    ok "publish_contract quiet when no surface's trigger exists"
  else
    bad "publish_contract fired on a repository that publishes nothing"
  fi

  # 2. The trigger demanding its own rules -- the behaviour that is not
  #    standard practice. Normally the file appears, nobody wrote the rules,
  #    and nothing says so.
  printf '{}\n' > "$CP/package.json"
  if run_cp >/dev/null 2>&1; then
    bad "publish_contract MISSED a planned surface whose trigger appeared"
  else
    ok "publish_contract refuses a planned surface whose trigger appeared"
  fi

  # 3. A live surface whose defining file is gone -- the server.json incident.
  rm -f "$CP/package.json"
  sed -i.bak 's/status = "planned"/status = "live"/' "$CT" && rm -f "$CT.bak"
  if run_cp >/dev/null 2>&1; then
    bad "publish_contract MISSED a live surface with no trigger file"
  else
    ok "publish_contract refuses a live surface whose trigger is missing"
  fi

  # 4. ...and quiet once the file it names is there.
  printf '{}\n' > "$CP/package.json"
  if run_cp >/dev/null 2>&1; then
    ok "publish_contract accepts a live surface whose trigger exists"
  else
    bad "publish_contract still fired once the live trigger was present"
  fi

  # 5. Version agreement, which is what started all this.
  cat > "$CP/pyproject.toml" <<'TOMLEOF'
[project]
name = "probe"
version = "9.9.9"
TOMLEOF
  cat >> "$CT" <<'TOMLEOF'

[[surfaces.requires]]
kind = "json_version_matches_source"
path = "package.json"
field = "version"
TOMLEOF
  printf '{"version": "1.0.0"}\n' > "$CP/package.json"
  if run_cp >/dev/null 2>&1; then
    bad "publish_contract MISSED a version disagreeing with the source"
  else
    ok "publish_contract refuses a version that disagrees with the source"
  fi

  # 6. ...and accepts agreement, so the gate is about agreeing and not about
  #    always failing.
  printf '{"version": "9.9.9"}\n' > "$CP/package.json"
  if run_cp >/dev/null 2>&1; then
    ok "publish_contract accepts versions that agree"
  else
    bad "publish_contract fired on versions that agree"
  fi

  # 7. A check with no `stages` is itself a finding. A default would be a
  #    guess about where a check can run, and guessing it made one release
  #    fail three times.
  cat >> "$CT" <<'TOMLEOF'

[[surfaces.checks]]
path = ".gates/check_publish_contract.py"
TOMLEOF
  if run_cp 2>&1 | grep -q "declares no"; then
    ok "publish_contract refuses a check that names no stages"
  else
    bad "publish_contract accepted a check with no stages declared"
  fi

  # 8. A CFF version is read without pyyaml, and a MISSING version line is a
  #    finding rather than a pass. A cheap parser is only acceptable while its
  #    misses are loud.
  cat > "$CT" <<'TOMLEOF'
[version_source]
path = "pyproject.toml"
kind = "toml_project_version"

[[surfaces]]
id = "citation"
status = "live"
trigger = "CITATION.cff"
why = "probe surface"

[[surfaces.requires]]
kind = "yaml_version_matches_source"
path = "CITATION.cff"
field = "version"
TOMLEOF
  printf 'cff-version: 1.2.0\nversion: 9.9.9\n' > "$CP/CITATION.cff"
  if run_cp >/dev/null 2>&1; then
    ok "publish_contract reads a CFF version with no yaml module"
  else
    bad "publish_contract could not read a CFF version without pyyaml"
  fi

  printf 'cff-version: 1.2.0\nversion: 0.0.1\n' > "$CP/CITATION.cff"
  if run_cp >/dev/null 2>&1; then
    bad "publish_contract MISSED a stale CFF version"
  else
    ok "publish_contract refuses a stale CFF version"
  fi

  printf 'cff-version: 1.2.0\ntitle: no version line here\n' > "$CP/CITATION.cff"
  if run_cp 2>&1 | grep -q "no top-level"; then
    ok "publish_contract treats a missing CFF version as a finding"
  else
    bad "publish_contract passed a CFF file with no version line"
  fi
  rm -f "$CP/CITATION.cff"

  # 9. An inline empty array that a later block cannot extend is a TOML error
  #    an editor will hit, so it must be explained rather than traced back.
  cat > "$CT" <<'TOMLEOF'
[version_source]
path = "pyproject.toml"
kind = "toml_project_version"

[[surfaces]]
id = "npm"
status = "planned"
trigger = "package.json"
why = "probe surface"
requires = []

[[surfaces.requires]]
kind = "file_exists"
path = "README.md"
TOMLEOF
  if run_cp 2>&1 | grep -q "inline"; then
    ok "publish_contract explains an inline-array TOML conflict"
  else
    bad "publish_contract gave no hint for an inline-array TOML conflict"
  fi
  rm -rf "$CP"
fi



# ---------------------------------------------- check_script_standards
if [ -f "$G/check_script_standards.py" ]; then
  # Its own tree. Writing into another probe's directory makes the result
  # depend on whether that probe ran, and on what it left behind.
  SS=$(mktemp -d)
  mkdir -p "$SS/.gates"
  cp "$G/check_script_standards.py" "$G/_baseline.py" "$SS/.gates/"
  (cd "$SS" && git init -q) >/dev/null 2>&1
  printf '"""Docs mention https://example.com — prose, not a finding."""\nCFG = "export_config.yaml"\n' > "$SS/ok_script.py"
  (cd "$SS" && git add -A) >/dev/null 2>&1
  if (cd "$SS" && python3 .gates/check_script_standards.py --check) >/dev/null 2>&1; then
    ok "check_script_standards quiet on a config-driven script"
  else
    bad "check_script_standards fired on an acceptable script"
  fi

  printf 'URL = "https://github.com/x/y.git"\n' > "$SS/bad_script.py"
  (cd "$SS" && git add -A) >/dev/null 2>&1
  if (cd "$SS" && python3 .gates/check_script_standards.py --check) >/dev/null 2>&1; then
    bad "check_script_standards MISSED a hardcoded URL"
  else
    ok "check_script_standards refuses a hardcoded URL"
  fi

  printf '#!/bin/sh\ncomm -23 <(sort a) b\n' > "$SS/bad_shell.sh"
  (cd "$SS" && git add -A) >/dev/null 2>&1
  if (cd "$SS" && python3 .gates/check_script_standards.py --check) >/dev/null 2>&1; then
    bad "check_script_standards MISSED a bash-only construct"
  else
    ok "check_script_standards refuses a bash-only construct"
  fi
  rm -f "$SS/ok_script.py" "$SS/bad_script.py" "$SS/bad_shell.sh"
  (cd "$SS" && git add -A) >/dev/null 2>&1
  rm -rf "$SS"
fi

# ----------------------------------------------------------- pre-commit -----
# The checks declared in .pre-commit-config.yaml are gates too, and a declared
# check is no more trustworthy than a written one until it has been seen to
# refuse something. Each probe writes one violating file, runs the single hook
# that should object to it, and asserts a non-zero exit.
if [ -f "$ROOT/.pre-commit-config.yaml" ]; then
  if ! command -v pre-commit >/dev/null 2>&1; then
    echo "  SKIP  pre-commit config present but the runner is not installed"
    SKIP=$((SKIP+1))
  else
    PP="$ROOT/.gates/.ppobe"
    REL=".gates/.ppobe/p.py"
    mkdir -p "$PP"
    # Staged, and named relative to the repository. pre-commit's contract is
    # the staged set: an untracked file given by absolute path makes
    # check-added-large-files raise rather than report.
    stage_probe() { (cd "$ROOT" && git add -f "$REL") >/dev/null 2>&1; }
    unstage_probe() { (cd "$ROOT" && git rm -q --cached "$REL") >/dev/null 2>&1; }

    # Assembled, never literal, for the same reason as the probes above: a
    # fixture indistinguishable from what it tests for blocks its own repo.
    HOMEISH="/U""sers/someone/x.md"
    printf 'OUT = "%s"\n' "$HOMEISH" > "$PP/p.py"
    stage_probe
    if (cd "$ROOT" && pre-commit run gitleaks \
          --files "$REL") >/dev/null 2>&1; then
      bad "pre-commit gitleaks did NOT block a home path"
    else
      ok "pre-commit gitleaks blocks a home path"
    fi



    printf 'def broken(\n' > "$PP/p.py"
    stage_probe
    if (cd "$ROOT" && pre-commit run check-ast --files "$REL") \
          >/dev/null 2>&1; then
      bad "pre-commit check-ast did NOT block a file that fails to parse"
    else
      ok "pre-commit check-ast blocks a file that fails to parse"
    fi

    # A gate that refuses everything is as useless as one that refuses
    # nothing, so silence on a clean file is proven too.
    printf 'def fine():\n    return 1\n' > "$PP/p.py"
    stage_probe
    if (cd "$ROOT" && pre-commit run --files "$REL") >/dev/null 2>&1; then
      ok "pre-commit quiet on a clean file"
    else
      bad "pre-commit fired on a clean file"
    fi

    unstage_probe
    rm -rf "$PP"
  fi
fi

# ------------------------------------------------ hooks are executable -----
# git ignores a hook without the execute bit and says so only as a hint on
# push. A hook that is installed, correct and never run is the same outcome as
# no hook at all.
if [ -d "$ROOT/.githooks" ]; then
  NOEXEC=""
  for h in "$ROOT"/.githooks/*; do
    [ -f "$h" ] || continue
    [ -x "$h" ] || NOEXEC="$NOEXEC $(basename "$h")"
  done
  if [ -n "$NOEXEC" ]; then
    bad "hook(s) not executable, so git ignores them:$NOEXEC"
  else
    ok "every file in .githooks is executable"
  fi
fi

# ------------------------------------------------- the hook, end to end -----
# Every probe above runs a gate directly, so none of them can tell whether git
# reaches that gate at all. An entry point that returns early, or a hook file
# without the execute bit, disables everything behind it while every
# individual probe still passes.
#
# Run in THIS repository, against the real installed hook. A copy into a
# throwaway tree cannot know what the hook needs -- a helper script outside
# .gates, a baseline, a pinned committer identity -- and every missing piece
# makes the hook refuse for a reason that has nothing to do with the test.
#
# Both directions, because one proves nothing: a hook that refuses everything
# passes a refusal-only probe. Nothing is committed; a file is staged, the
# hook is run as git runs it, and the file is removed either way.
if [ -f "$ROOT/.githooks/pre-commit" ] && git -C "$ROOT" hook run --help >/dev/null 2>&1; then
  HP="$ROOT/.gates/.hprobe.py"
  hook_run() { git -C "$ROOT" hook run pre-commit >/dev/null 2>&1; }
  cleanup_hp() {
    git -C "$ROOT" rm -q --cached "${HP#"$ROOT/"}" >/dev/null 2>&1 || true
    rm -f "$HP"
  }

  printf 'def fine():\n    return 1\n' > "$HP"
  git -C "$ROOT" add -f "${HP#"$ROOT/"}" >/dev/null 2>&1
  if hook_run; then
    ok "the pre-commit hook accepts a clean staged file end to end"

    # A file that does not parse. No local pattern owns this, and it cannot
    # stop being a violation when a pattern is retired.
    printf 'def broken(\n' > "$HP"
    git -C "$ROOT" add -f "${HP#"$ROOT/"}" >/dev/null 2>&1
    if hook_run; then
      bad "the pre-commit HOOK accepted a file that does not parse"
    else
      ok "the pre-commit hook refuses a violating staged file end to end"
    fi
  else
    bad "the pre-commit hook refused a CLEAN file, so a refusal proves nothing"
  fi
  cleanup_hp
fi

echo
echo "gates proven: $PASS passed, $FAIL failed, $SKIP not installed"
[ "$FAIL" -eq 0 ] || exit 1

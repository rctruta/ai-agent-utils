#!/bin/sh
# prove_gates.sh — demonstrate that each gate actually FIRES.
# An untested gate is theatre. This is the same discipline as prove_lock.sh.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
G="$ROOT/.gates"
PASS=0; FAIL=0
ok()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

echo "Proving the gates fire..."

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

# 4. checkpoint must REFUSE to save a state whose proof fails
if "$G/checkpoint.sh" save probe_bad "false" >/dev/null 2>&1; then
  bad "checkpoint saved a state whose proof FAILED"
else
  ok "checkpoint refuses a state whose proof fails"
fi

# 5. checkpoint must save when the proof passes, and verify it
if "$G/checkpoint.sh" save probe_good "true" >/dev/null 2>&1 \
   && "$G/checkpoint.sh" verify probe_good >/dev/null 2>&1; then
  ok "checkpoint saves and re-verifies a good state"
else
  bad "checkpoint could not save/verify a good state"
fi
rm -f "$G/checkpoints/probe_good."* 2>/dev/null || true

# 6. the pre-commit hook must exist and be executable
if [ -x "$ROOT/.githooks/pre-commit" ]; then
  ok "pre-commit hook present and executable"
else
  bad "pre-commit hook missing or not executable"
fi

echo
echo "gates proven: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1

#!/bin/sh
# set_branch_protection — require a green check before anything reaches main.
#
#   set_branch_protection.sh                 use the context from the workflow
#   set_branch_protection.sh --check <name>  override the context name
#   set_branch_protection.sh --dry           print the call, change nothing
#
# A pre-push hook is advisory: `git push --no-verify` skips it, and so does
# anything that does not know it exists. A required status check is enforced
# by the server and cannot be skipped. That is the difference between a
# convention and a boundary.
#
# ORDER MATTERS. Requiring a context that no workflow emits blocks every
# merge forever, waiting for a check that never arrives. So this refuses
# unless the context has already been seen green on the default branch.
# A first CI run commonly fails for reasons invisible locally; setting
# protection blind would have locked both.
set -e

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
BRANCH="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"
WORKFLOW=".github/workflows/test.yaml"
DRY=0
CONTEXT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry) DRY=1 ;;
    --check) shift; CONTEXT="$1" ;;
  esac
  shift
done

# The context is the JOB name in the workflow, not the workflow's `name:`.
# Reading it here is what stops the rule and the workflow drifting apart.
if [ -z "$CONTEXT" ]; then
  [ -f "$WORKFLOW" ] || { echo "no $WORKFLOW; pass --check <name>" >&2; exit 2; }
  CONTEXT=$(awk '/^jobs:/{f=1;next} f&&/^  [a-zA-Z0-9_-]+:/{gsub(/[ :]/,"");print;exit}' "$WORKFLOW")
  [ -n "$CONTEXT" ] || { echo "could not read a job name from $WORKFLOW" >&2; exit 2; }
fi

echo "repo:    $REPO"
echo "branch:  $BRANCH"
echo "context: $CONTEXT"

SHA=$(gh api "repos/$REPO/commits/$BRANCH" --jq .sha)
SEEN=$(gh api "repos/$REPO/commits/$SHA/check-runs" \
         --jq "[.check_runs[] | select(.name==\"$CONTEXT\" and .conclusion==\"success\")] | length")
if [ "${SEEN:-0}" -lt 1 ]; then
  echo "" >&2
  echo "REFUSING: '$CONTEXT' has not been seen green on $BRANCH." >&2
  echo "  Requiring a context no workflow emits blocks every merge." >&2
  echo "  Run the workflow first:  gh workflow run $WORKFLOW" >&2
  exit 1
fi

# The API rejects required_status_checks unless it carries BOTH strict and
# contexts, and rejects bracket-style form fields for nested objects. A JSON
# body is the only shape that works; getting this wrong returned 422 twice.
BODY=$(printf '%s' '{
  "required_status_checks": { "strict": true, "contexts": ["'"$CONTEXT"'"] },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null
}')

if [ "$DRY" = "1" ]; then
  echo "would PUT repos/$REPO/branches/$BRANCH/protection:"
  echo "$BODY"
  exit 0
fi

echo "$BODY" | gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" --input - >/dev/null
gh api "repos/$REPO/branches/$BRANCH/protection" \
  --jq '"set: required \(.required_status_checks.contexts) | strict \(.required_status_checks.strict) | admins \(.enforce_admins.enabled)"'

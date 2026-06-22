#!/bin/bash
set -u

# worktree-merge.sh <phase> <plan>
# Merges vbw/<phase>-<plan> branch into the current branch using --no-ff.
# Output: exactly "clean" on success or "conflict" on merge failure.
# Exit code: always 0 (fail-open).

PHASE="${1:-}"
PLAN="${2:-}"

# Validate required arguments
if [ -z "$PHASE" ] || [ -z "$PLAN" ]; then
  exit 0
fi

# Normalize the plan id into the canonical "<phase>-<plan>" slug so the branch
# matches the one worktree-create.sh produced. A caller may pass a bare plan
# number (MM) or an already phase-qualified id (NN-MM); prepending PHASE to the
# latter would double-prefix to NN-NN-MM. Use an already-qualified plan as-is,
# otherwise combine it with PHASE.
case "$PLAN" in
  *-*) SLUG="$PLAN" ;;
  *)   SLUG="${PHASE}-${PLAN}" ;;
esac
PLAN_NUM="${SLUG#*-}"

BRANCH="vbw/${SLUG}"

# Attempt the merge. Suppress git's own stdout/stderr so the script honors its
# contract of emitting exactly "clean" or "conflict" (git prints a porcelain
# summary to stdout on success and conflict details on failure).
git merge --no-ff "$BRANCH" -m "merge: phase ${PHASE} plan ${PLAN_NUM}" >/dev/null 2>&1
MERGE_STATUS=$?

if [ "$MERGE_STATUS" -eq 0 ]; then
  echo "clean"
else
  git merge --abort 2>/dev/null || true
  echo "conflict"
fi

exit 0

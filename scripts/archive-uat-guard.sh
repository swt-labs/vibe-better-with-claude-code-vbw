#!/usr/bin/env bash
set -u

# archive-uat-guard.sh — hard gate for archive attempts when unresolved UAT exists.
#
# Exit codes:
#   0 => archive allowed (no unresolved UAT detected)
#   2 => block archive (active phase or milestone unresolved UAT)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHASE_DETECT_OUT=$(bash "$SCRIPT_DIR/phase-detect.sh" 2>/dev/null || true)

[ -z "$PHASE_DETECT_OUT" ] && exit 0

get_kv() {
  local key="$1"
  echo "$PHASE_DETECT_OUT" | grep -m1 "^${key}=" | sed 's/^[^=]*=//' || true
}

PLANNING_EXISTS=$(get_kv "planning_dir_exists")
PROJECT_EXISTS=$(get_kv "project_exists")

[ "${PLANNING_EXISTS:-false}" != "true" ] && exit 0
[ "${PROJECT_EXISTS:-false}" != "true" ] && exit 0

ACTIVE_UAT_PHASE=$(get_kv "uat_issues_phase")
MILESTONE_UAT_ISSUES=$(get_kv "milestone_uat_issues")
MILESTONE_UAT_PHASE=$(get_kv "milestone_uat_phase")
MILESTONE_UAT_SLUG=$(get_kv "milestone_uat_slug")

if [ "${ACTIVE_UAT_PHASE:-none}" != "none" ]; then
  echo "Archive blocked: unresolved active-phase UAT issues in Phase ${ACTIVE_UAT_PHASE}. Remediate and re-run UAT before archiving."
  exit 2
fi

if [ "${MILESTONE_UAT_ISSUES:-false}" = "true" ]; then
  if [ "${MILESTONE_UAT_SLUG:-none}" != "none" ] && [ "${MILESTONE_UAT_PHASE:-none}" != "none" ]; then
    echo "Archive blocked: unresolved milestone UAT issues in ${MILESTONE_UAT_SLUG} Phase ${MILESTONE_UAT_PHASE}. Resolve or explicitly recover before archiving."
  else
    echo "Archive blocked: unresolved milestone UAT issues detected. Resolve or explicitly recover before archiving."
  fi
  exit 2
fi

exit 0

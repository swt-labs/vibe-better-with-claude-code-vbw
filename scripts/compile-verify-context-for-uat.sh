#!/usr/bin/env bash
# compile-verify-context-for-uat.sh — Choose full vs remediation-only verify
# context when entering human UAT / re-verification.
#
# Usage: compile-verify-context-for-uat.sh <phase-dir>
#
# Rules:
#   - First-time UAT for a phase always uses full scope, even if QA remediation
#     is done. QA remediation fixes the QA gate; it does not narrow human UAT.
#   - UAT re-verification after prior UAT issues uses remediation-only scope when
#     a UAT remediation stage is active or preserved.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE_DIR="${1:?Usage: compile-verify-context-for-uat.sh <phase-dir>}"

normalize_uat_stage() {
  local raw="${1:-}"
  case "$raw" in
    research|plan|execute|fix|verify|done|verified) printf '%s' "$raw" ;;
    *) printf '' ;;
  esac
}

read_uat_stage() {
  local phase_dir="$1"
  local raw=""

  if [ -f "$phase_dir/remediation/uat/.uat-remediation-stage" ]; then
    raw=$(grep '^stage=' "$phase_dir/remediation/uat/.uat-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
  elif [ -f "$phase_dir/.uat-remediation-stage" ]; then
    if grep -q '^stage=' "$phase_dir/.uat-remediation-stage" 2>/dev/null; then
      raw=$(grep '^stage=' "$phase_dir/.uat-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    else
      raw=$(tr -d '[:space:]' < "$phase_dir/.uat-remediation-stage")
    fi
  fi

  normalize_uat_stage "$raw"
}

UAT_STAGE="$(read_uat_stage "$PHASE_DIR")"

# Active remediation stages route to remediation-only scope.
# "verified" means remediation is complete — use full scope for any re-verification.
if [ -n "$UAT_STAGE" ] && [ "$UAT_STAGE" != "verified" ]; then
  exec bash "$SCRIPT_DIR/compile-verify-context.sh" --remediation-only "$PHASE_DIR"
fi

exec bash "$SCRIPT_DIR/compile-verify-context.sh" "$PHASE_DIR"
#!/usr/bin/env bash
# extract-uat-resume.sh — Extract UAT resume metadata from a phase directory.
# Usage: extract-uat-resume.sh <phase-dir>
#
# Outputs compact resume metadata so the LLM doesn't need to scan-parse
# the UAT file to find the resume point.
#
# Output formats:
#   uat_resume=none                           — no UAT file exists
#   uat_resume=all_done uat_completed=N uat_total=N — all tests have results
#   uat_resume=<test-id> uat_completed=N uat_total=N — resume at <test-id>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared UAT helpers if available
if [ -f "$SCRIPT_DIR/uat-utils.sh" ]; then
  # shellcheck source=uat-utils.sh
  source "$SCRIPT_DIR/uat-utils.sh"
fi

PHASE_DIR="${1:?Usage: extract-uat-resume.sh <phase-dir>}"

if [ ! -d "$PHASE_DIR" ]; then
  echo "uat_resume=none"
  exit 0
fi

# Find the latest UAT file
if type latest_non_source_uat &>/dev/null; then
  UAT_FILE=$(latest_non_source_uat "$PHASE_DIR")
else
  UAT_FILE=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' -name '[0-9]*-UAT.md' ! -name '*SOURCE-UAT.md' 2>/dev/null | sort | tail -1)
fi

if [ -z "$UAT_FILE" ] || [ ! -f "$UAT_FILE" ]; then
  echo "uat_resume=none"
  exit 0
fi

# Parse all test entries: count total, find first without a result
awk '
  BEGIN { total=0; completed=0; first_incomplete=""; cur_id=""; cur_has_result=0 }

  function check_prev() {
    if (cur_id != "" && cur_has_result == 0 && first_incomplete == "") {
      first_incomplete = cur_id
    }
  }

  /^### [PD][0-9]/ {
    # Before starting new test, check if previous test was incomplete
    check_prev()
    # Extract test ID: "### P01-T2: title" or "### D1: title"
    cur_id = $2
    sub(/:$/, "", cur_id)
    total++
    cur_has_result = 0
    next
  }
  /^- \*\*Result:\*\*/ {
    val = $0
    sub(/^- \*\*Result:\*\*[[:space:]]*/, "", val)
    gsub(/[[:space:]]+$/, "", val)
    if (val != "") {
      cur_has_result = 1
      completed++
    }
    next
  }
  /^## / {
    # End of tests section — check last test
    check_prev()
  }
  END {
    # Check last test if file ends without ## section
    check_prev()
    if (total == 0) {
      printf "uat_resume=none\n"
    } else if (completed >= total) {
      printf "uat_resume=all_done uat_completed=%d uat_total=%d\n", completed, total
    } else if (first_incomplete != "") {
      printf "uat_resume=%s uat_completed=%d uat_total=%d\n", first_incomplete, completed, total
    } else {
      printf "uat_resume=all_done uat_completed=%d uat_total=%d\n", completed, total
    }
  }
' "$UAT_FILE"

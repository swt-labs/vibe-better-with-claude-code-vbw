#!/usr/bin/env bash
# finalize-uat-status.sh — Deterministically update UAT file frontmatter status and counts.
# Usage: finalize-uat-status.sh <uat-file-path>
#
# Reads all **Result:** lines, counts pass/skip/issue, and updates the YAML
# frontmatter fields: status, completed, passed, skipped, issues, total_tests.
#
# Result classification (case-insensitive):
#   pass/passed             → passed
#   skip/skipped            → skipped
#   issue/fail/failed/partial → issue
#   empty or missing        → incomplete (keeps status=in_progress)
#
# Status determination:
#   Any result is issue/fail/partial → status=issues_found
#   All results are pass/skip       → status=complete
#   Any result is empty              → status=in_progress
#
# Output: status={status} passed={N} skipped={N} issues={N} total={N}

set -euo pipefail

UAT_FILE="${1:?Usage: finalize-uat-status.sh <uat-file-path>}"

if [ ! -f "$UAT_FILE" ]; then
  echo "Error: UAT file not found: $UAT_FILE" >&2
  exit 1
fi

# Parse all **Result:** values from test entries
# Returns: one word per line (pass, skip, issue, empty, or the raw value)
RESULTS=$(awk '
  /^### [PD][0-9]/ { in_test = 1; next }
  in_test && /^- \*\*Result:\*\*/ {
    val = $0
    sub(/^- \*\*Result:\*\*[[:space:]]*/, "", val)
    gsub(/[[:space:]]+$/, "", val)
    # Normalize to lowercase
    for (i = 1; i <= length(val); i++) {
      c = substr(val, i, 1)
      if (c >= "A" && c <= "Z") {
        c = sprintf("%c", index("ABCDEFGHIJKLMNOPQRSTUVWXYZ", c) + 96)
      }
      lval = lval c
    }
    val = lval; lval = ""
    if (val == "" || val == "{pass|skip|issue}") {
      print "empty"
    } else if (val == "pass" || val == "passed") {
      print "pass"
    } else if (val == "skip" || val == "skipped") {
      print "skip"
    } else if (val == "issue" || val == "fail" || val == "failed" || val ~ /^partial/) {
      print "issue"
    } else {
      # Unknown value — treat as issue (defensive)
      print "issue"
    }
    next
  }
  /^### / { in_test = 0 }
' "$UAT_FILE")

# Count results
PASSED=0
SKIPPED=0
ISSUES=0
EMPTY=0
TOTAL=0

while IFS= read -r result; do
  [ -z "$result" ] && continue
  TOTAL=$((TOTAL + 1))
  case "$result" in
    pass)  PASSED=$((PASSED + 1)) ;;
    skip)  SKIPPED=$((SKIPPED + 1)) ;;
    issue) ISSUES=$((ISSUES + 1)) ;;
    empty) EMPTY=$((EMPTY + 1)) ;;
  esac
done <<< "$RESULTS"

# Determine status
# TOTAL=0 means no test entries found — file is incomplete/malformed
if [ "$TOTAL" -eq 0 ] || [ "$EMPTY" -gt 0 ]; then
  STATUS="in_progress"
elif [ "$ISSUES" -gt 0 ]; then
  STATUS="issues_found"
else
  STATUS="complete"
fi

# Only set completed date for terminal statuses
if [ "$STATUS" = "in_progress" ]; then
  TODAY=""
else
  TODAY=$(date +%Y-%m-%d)
fi

# Update frontmatter in-place using awk
# Preserves all other frontmatter fields, only updates the target fields
awk -v status="$STATUS" -v completed="$TODAY" -v passed="$PASSED" \
    -v skipped="$SKIPPED" -v issues="$ISSUES" -v total="$TOTAL" '
  BEGIN { in_fm = 0; fm_done = 0 }
  NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; print; next }
  in_fm && /^---[[:space:]]*$/ {
    in_fm = 0; fm_done = 1; print; next
  }
  in_fm {
    if ($0 ~ /^status[[:space:]]*:/) {
      printf "status: %s\n", status
    } else if ($0 ~ /^completed[[:space:]]*:/) {
      if (completed != "") printf "completed: %s\n", completed
      else printf "completed:\n"  # clear stale date for in_progress
    } else if ($0 ~ /^passed[[:space:]]*:/) {
      printf "passed: %s\n", passed
    } else if ($0 ~ /^skipped[[:space:]]*:/) {
      printf "skipped: %s\n", skipped
    } else if ($0 ~ /^issues[[:space:]]*:/) {
      printf "issues: %s\n", issues
    } else if ($0 ~ /^total_tests[[:space:]]*:/) {
      printf "total_tests: %s\n", total
    } else {
      print
    }
    next
  }
  { print }
' "$UAT_FILE" > "${UAT_FILE}.tmp" && mv "${UAT_FILE}.tmp" "$UAT_FILE"

echo "status=${STATUS} passed=${PASSED} skipped=${SKIPPED} issues=${ISSUES} total=${TOTAL}"

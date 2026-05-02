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
#   empty                   → incomplete (keeps status=in_progress)
#   missing Result line     → malformed UAT block (fail closed)
#
# Status determination:
#   Any result is issue/fail/partial → status=issues_found
#   All results are pass/skip       → status=complete
#   Any result is empty              → status=in_progress
#
# Output: status={status} passed={N} skipped={N} issues={N} total={N}

set -euo pipefail

UAT_FILE="${1:?Usage: finalize-uat-status.sh <uat-file-path>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P 2>/dev/null || pwd)"

if [ ! -f "$UAT_FILE" ]; then
  echo "Error: UAT file not found: $UAT_FILE" >&2
  exit 1
fi

# Parse all **Result:** values from test entries.
# Returns one token per line: pass, skip, issue, empty, __missing__, or
# __unknown__:<raw>.
RESULTS=$(awk '
  /^### [PD][0-9]/ {
    if (in_test && saw_result == 0) print "__missing__"
    in_test = 1
    saw_result = 0
    next
  }
  in_test && /^- \*\*Result:\*\*/ {
    saw_result = 1
    val = $0
    sub(/^- \*\*Result:\*\*[[:space:]]*/, "", val)
    gsub(/[[:space:]]+$/, "", val)
    # Strip common decorators (checkmarks, emoji, bullets)
    gsub(/^[^a-zA-Z{]+/, "", val)
    gsub(/[^a-zA-Z}]+$/, "", val)
    # Normalize to lowercase using portable character mapping (locale-safe)
    upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    lower = "abcdefghijklmnopqrstuvwxyz"
    lval = ""
    for (i = 1; i <= length(val); i++) {
      c = substr(val, i, 1)
      pos = index(upper, c)
      if (pos > 0) c = substr(lower, pos, 1)
      lval = lval c
    }
    val = lval
    if (val == "" || val == "{pass|skip|issue}") {
      print "empty"
    } else if (val ~ /^pass/) {
      print "pass"
    } else if (val ~ /^skip/) {
      print "skip"
    } else if (val ~ /^issue/ || val ~ /^fail/ || val ~ /^partial/) {
      print "issue"
    } else {
      print "__unknown__:" val
    }
    next
  }
  /^### / {
    if (in_test && saw_result == 0) print "__missing__"
    in_test = 0
    saw_result = 0
  }
  END {
    if (in_test && saw_result == 0) print "__missing__"
  }
' "$UAT_FILE")

# Count results
PASSED=0
SKIPPED=0
ISSUES=0
EMPTY=0
TOTAL=0
UNKNOWN=0
MISSING=0

while IFS= read -r result; do
  [ -z "$result" ] && continue
  case "$result" in
    __unknown__:*)
      printf 'finalize-uat-status: unrecognized Result value: %s\n' "${result#__unknown__:}" >&2
      UNKNOWN=$((UNKNOWN + 1))
      continue
      ;;
    __missing__)
      printf 'finalize-uat-status: missing Result line in test block\n' >&2
      MISSING=$((MISSING + 1))
      continue
      ;;
  esac
  TOTAL=$((TOTAL + 1))
  case "$result" in
    pass)  PASSED=$((PASSED + 1)) ;;
    skip)  SKIPPED=$((SKIPPED + 1)) ;;
    issue) ISSUES=$((ISSUES + 1)) ;;
    empty) EMPTY=$((EMPTY + 1)) ;;
  esac
done <<< "$RESULTS"

if [ "$UNKNOWN" -gt 0 ] || [ "$MISSING" -gt 0 ]; then
  echo "finalize-uat-status: refusing to rewrite frontmatter due to malformed Result values" >&2
  exit 1
fi

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
  BEGIN { in_fm = 0; fm_done = 0; saw_completed = 0 }
  NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; print; next }
  in_fm && /^---[[:space:]]*$/ {
    # Inject completed field if it was missing from frontmatter
    if (!saw_completed && completed != "") {
      printf "completed: %s\n", completed
    }
    in_fm = 0; fm_done = 1; print; next
  }
  in_fm {
    if ($0 ~ /^status[[:space:]]*:/) {
      printf "status: %s\n", status
    } else if ($0 ~ /^completed[[:space:]]*:/) {
      saw_completed = 1
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

bash "$SCRIPT_DIR/reconcile-state-md.sh" --changed "$UAT_FILE" >/dev/null 2>&1 || true

echo "status=${STATUS} passed=${PASSED} skipped=${SKIPPED} issues=${ISSUES} total=${TOTAL}"

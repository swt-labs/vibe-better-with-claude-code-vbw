#!/usr/bin/env bash
# extract-uat-issues.sh — Extract compact issue summary from a UAT report.
# Usage: extract-uat-issues.sh <phase-dir>
#
# Outputs one line per issue: ID|SEVERITY|DESCRIPTION|FAILED_IN_ROUNDS
# Plus a header line with phase, total count, and current round number.
# Designed for template expansion injection — compact, deterministic output
# that saves the LLM from reading the full UAT file.
#
# Example output:
#   uat_phase=03 uat_issues_total=2 uat_round=6 uat_file=03-UAT.md
#   P01-T1|major|Phantom positions still showing|1,3,5,6
#   P02-T1|critical|Data not syncing|6
#   D1|minor|Some discovered issue description|6

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared UAT helpers if available
if [ -f "$SCRIPT_DIR/uat-utils.sh" ]; then
  # shellcheck source=uat-utils.sh
  source "$SCRIPT_DIR/uat-utils.sh"
fi

PHASE_DIR="${1:?Usage: extract-uat-issues.sh <phase-dir>}"

if [ ! -d "$PHASE_DIR" ]; then
  echo "uat_extract_error=true" >&2
  exit 1
fi

# Find the latest UAT file
if type latest_non_source_uat &>/dev/null; then
  UAT_FILE=$(latest_non_source_uat "$PHASE_DIR")
else
  UAT_FILE=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' -name '[0-9]*-UAT.md' ! -name '*SOURCE-UAT.md' 2>/dev/null | sort | tail -1)
fi

if [ -z "$UAT_FILE" ] || [ ! -f "$UAT_FILE" ]; then
  echo "uat_extract_error=no_uat_file"
  exit 0
fi

# Extract phase number from directory name
PHASE_NUM=$(basename "$PHASE_DIR" | sed 's/[^0-9].*//')

# Extract status from frontmatter
if type extract_status_value &>/dev/null; then
  STATUS=$(extract_status_value "$UAT_FILE")
else
  STATUS=$(awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && tolower($0) ~ /^[[:space:]]*status[[:space:]]*:/ {
      val=$0; sub(/^[^:]*:[[:space:]]*/, "", val); gsub(/[[:space:]]+$/, "", val)
      print tolower(val); exit
    }
  ' "$UAT_FILE" 2>/dev/null || true)
fi

if [ "$STATUS" != "issues_found" ]; then
  echo "uat_extract_status=${STATUS:-unknown}"
  exit 0
fi

# Parse UAT markdown for issue entries.
# Extracts: test ID (from ### header), severity, single-line description.
awk '
  /^### [PD][0-9]/ {
    # Extract test ID from header: "### P01-T2: title" or "### D1: title"
    id = $2
    sub(/:$/, "", id)
    has_issue = 0
    description = ""
    severity = ""
    next
  }
  /^- \*\*Result:\*\*[[:space:]]*issue/ {
    has_issue = 1
    next
  }
  has_issue && /^[[:space:]]*- Description:/ {
    desc = $0
    sub(/^[[:space:]]*- Description:[[:space:]]*/, "", desc)
    gsub(/[[:space:]]+$/, "", desc)
    description = desc
    if (severity != "") {
      printf "%s|%s|%s\n", id, severity, description
      has_issue = 0; description = ""; severity = ""
    }
    next
  }
  has_issue && /^[[:space:]]*- Severity:/ {
    sev = $0
    sub(/^[[:space:]]*- Severity:[[:space:]]*/, "", sev)
    gsub(/[[:space:]]+$/, "", sev)
    severity = sev
    if (description != "") {
      printf "%s|%s|%s\n", id, severity, description
      has_issue = 0; description = ""; severity = ""
    }
    next
  }
  /^### / {
    # New section — emit partial issue if only one field was captured
    if (has_issue && (description != "" || severity != "")) {
      if (description == "") description = "(no description)"
      if (severity == "") severity = "unknown"
      printf "%s|%s|%s\n", id, severity, description
    }
    has_issue = 0
    description = ""
    severity = ""
  }
' "$UAT_FILE" > /tmp/.vbw-uat-issues-$$.txt
trap 'rm -f /tmp/.vbw-uat-issues-$$.txt /tmp/.vbw-uat-recurrence-$$.txt' EXIT

ISSUE_COUNT=$(wc -l < /tmp/.vbw-uat-issues-$$.txt | tr -d ' ')

# Determine current round number from archived round files
if type count_uat_rounds &>/dev/null; then
  ARCHIVED_ROUNDS=$(count_uat_rounds "$PHASE_DIR" "$PHASE_NUM")
else
  ARCHIVED_ROUNDS=0
fi
CURRENT_ROUND=$((ARCHIVED_ROUNDS + 1))

# Build recurrence data from archived round files.
# Produces lines: "ID ROUND_NUM" in a temp file (Bash 3.2 compatible — no associative arrays).
: > /tmp/.vbw-uat-recurrence-$$.txt
if [ "$ARCHIVED_ROUNDS" -gt 0 ] && type extract_round_issue_ids &>/dev/null; then
  round_num=1
  while [ "$round_num" -le "$ARCHIVED_ROUNDS" ]; do
    # Try both zero-padded and unpadded filenames
    round_file=""
    for candidate in "$PHASE_DIR/${PHASE_NUM}-UAT-round-${round_num}.md" \
                     "$PHASE_DIR/${PHASE_NUM}-UAT-round-$(printf '%02d' "$round_num").md"; do
      if [ -f "$candidate" ]; then
        round_file="$candidate"
        break
      fi
    done
    if [ -n "$round_file" ]; then
      extract_round_issue_ids "$round_file" | while IFS= read -r rid; do
        [ -z "$rid" ] && continue
        echo "$rid $round_num"
      done >> /tmp/.vbw-uat-recurrence-$$.txt
    fi
    round_num=$((round_num + 1))
  done
fi

# Header line — includes uat_round for recurrence-aware remediation
echo "uat_phase=${PHASE_NUM} uat_issues_total=${ISSUE_COUNT} uat_round=${CURRENT_ROUND} uat_file=$(basename "$UAT_FILE")"

# Issue lines with FAILED_IN_ROUNDS (4th field)
while IFS='|' read -r id severity desc; do
  # Collect prior round numbers for this ID from recurrence file
  prior_rounds=""
  if [ -s /tmp/.vbw-uat-recurrence-$$.txt ]; then
    prior_rounds=$(grep "^${id} " /tmp/.vbw-uat-recurrence-$$.txt | awk '{print $2}' | sort -n | tr '\n' ',' | sed 's/,$//' || true)
  fi
  if [ -n "$prior_rounds" ]; then
    failed_rounds="${prior_rounds},${CURRENT_ROUND}"
  else
    failed_rounds="${CURRENT_ROUND}"
  fi
  echo "${id}|${severity}|${desc}|${failed_rounds}"
done < /tmp/.vbw-uat-issues-$$.txt

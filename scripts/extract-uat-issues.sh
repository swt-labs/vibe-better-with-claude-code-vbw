#!/usr/bin/env bash
# extract-uat-issues.sh — Extract compact issue summary from a UAT report.
# Usage: extract-uat-issues.sh <phase-dir>
#
# Outputs one line per issue: ID|SEVERITY|DESCRIPTION
# Plus a header line with phase and total count.
# Designed for template expansion injection — compact, deterministic output
# that saves the LLM from reading the full UAT file.
#
# Example output:
#   uat_phase=03 uat_issues_total=1 uat_file=03-UAT.md
#   P01-T2|major|Data Quality share breakdown only shows on positions where transferred-in shares are the ONLY source
#   D1|minor|Some discovered issue description

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
    # New section without finding issue — reset
    has_issue = 0
    description = ""
    severity = ""
  }
' "$UAT_FILE" > /tmp/.vbw-uat-issues-$$.txt

ISSUE_COUNT=$(wc -l < /tmp/.vbw-uat-issues-$$.txt | tr -d ' ')

# Header line
echo "uat_phase=${PHASE_NUM} uat_issues_total=${ISSUE_COUNT} uat_file=$(basename "$UAT_FILE")"

# Issue lines
cat /tmp/.vbw-uat-issues-$$.txt
rm -f /tmp/.vbw-uat-issues-$$.txt

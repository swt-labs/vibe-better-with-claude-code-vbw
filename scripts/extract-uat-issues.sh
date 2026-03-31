#!/usr/bin/env bash
# extract-uat-issues.sh — Extract compact issue summary from a UAT report.
# Usage: extract-uat-issues.sh <phase-dir>
#
# Outputs one line per issue: ID|SEVERITY|DESCRIPTION|FAILED_IN_ROUNDS
# Plus a header line with phase, total count, round number, and filename.
# Designed for template expansion injection — compact, deterministic output
# that saves the LLM from reading the full UAT file.
#
# Example output:
#   uat_phase=03 uat_issues_total=1 uat_round=3 uat_file=03-UAT.md
#   P01-T2|major|Data Quality share breakdown only shows on positions where transferred-in shares are the ONLY source|1,3
#   D1|minor|Some discovered issue description|3

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

# Find the active UAT file (round-dir first, then phase-root fallback)
if type current_uat &>/dev/null; then
  UAT_FILE=$(current_uat "$PHASE_DIR")
elif type latest_non_source_uat &>/dev/null; then
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
  # Normalize LLM synonyms when uat-utils.sh unavailable
  if type normalize_uat_status &>/dev/null; then
    STATUS=$(normalize_uat_status "$STATUS")
  else
    case "$STATUS" in
      all_pass|passed|pass|all_passed|verified|no_issues) STATUS="complete" ;;
    esac
  fi
fi

if [ "$STATUS" != "issues_found" ]; then
  echo "uat_extract_status=${STATUS:-unknown}"
  exit 0
fi

# Parse UAT markdown for issue entries.
# Extracts: test ID (from ### header), severity, single-line description.
# Accepts Result values: issue, fail, failed, partial, FAIL, PARTIAL (case-insensitive).
# Extracts description from structured "- Description:" sub-bullet OR from
# inline **Issue:** content when structured sub-bullets are missing.
awk '
  function tolower_str(s,    i, c, out) {
    out = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (c >= "A" && c <= "Z")
        c = sprintf("%c", index("ABCDEFGHIJKLMNOPQRSTUVWXYZ", c) + 96)
      out = out c
    }
    return out
  }
  function emit_issue() {
    if (description == "" && inline_issue != "") description = inline_issue
    if (description == "") description = "(no description)"
    if (severity == "") {
      # Infer severity from keywords in description
      ldesc = tolower_str(description)
      if (ldesc ~ /crash|broken|error|doesnt work|fails|exception/)
        severity = "critical"
      else if (ldesc ~ /wrong|incorrect|missing|not working|bug/)
        severity = "major"
      else if (ldesc ~ /minor|cosmetic|nitpick|small|typo|polish/)
        severity = "minor"
      else
        severity = "major"
    }
    # Sanitize pipe chars in description to prevent field corruption
    gsub(/\|/, "-", description)
    printf "%s|%s|%s\n", id, severity, description
    has_issue = 0; description = ""; severity = ""; inline_issue = ""
  }
  /^### [PD][0-9]/ {
    # Emit any pending issue from previous test before starting new one
    if (has_issue) emit_issue()
    # Extract test ID from header: "### P01-T2: title" or "### D1: title"
    id = $2
    sub(/:$/, "", id)
    has_issue = 0
    description = ""
    severity = ""
    inline_issue = ""
    next
  }
  /^- \*\*Result:\*\*/ {
    val = $0
    sub(/^- \*\*Result:\*\*[[:space:]]*/, "", val)
    gsub(/[[:space:]]+$/, "", val)
    lval = tolower_str(val)
    if (lval ~ /^(issue|fail|failed|partial)/) {
      has_issue = 1
    }
    next
  }
  has_issue && /^- \*\*Issue:\*\*/ {
    # Capture inline issue text after **Issue:** (fallback description)
    itxt = $0
    sub(/^- \*\*Issue:\*\*[[:space:]]*/, "", itxt)
    gsub(/[[:space:]]+$/, "", itxt)
    if (itxt != "" && itxt != "{if result=issue}") inline_issue = itxt
    next
  }
  has_issue && /^[[:space:]]*- Description:/ {
    desc = $0
    sub(/^[[:space:]]*- Description:[[:space:]]*/, "", desc)
    gsub(/[[:space:]]+$/, "", desc)
    description = desc
    if (severity != "") {
      emit_issue()
    }
    next
  }
  has_issue && /^[[:space:]]*- Severity:/ {
    sev = $0
    sub(/^[[:space:]]*- Severity:[[:space:]]*/, "", sev)
    gsub(/[[:space:]]+$/, "", sev)
    severity = tolower_str(sev)
    if (description != "" || inline_issue != "") {
      emit_issue()
    }
    next
  }
  /^### / || /^## / {
    # New section — emit pending issue
    if (has_issue) emit_issue()
    has_issue = 0
    description = ""
    severity = ""
    inline_issue = ""
  }
  END {
    # Emit any trailing issue at end of file
    if (has_issue) emit_issue()
  }
' "$UAT_FILE" > /tmp/.vbw-uat-issues-$$.txt
trap 'rm -f /tmp/.vbw-uat-issues-$$.txt /tmp/.vbw-uat-round-ids-$$.txt' EXIT

ISSUE_COUNT=$(wc -l < /tmp/.vbw-uat-issues-$$.txt | tr -d ' ')

# Consistency guard: if frontmatter says issues_found but awk parsed 0 issues,
# the extraction is unreliable. Flag as error rather than returning misleading
# uat_issues_total=0 (which the LLM may trust).
if [ "$ISSUE_COUNT" -eq 0 ]; then
  # Cross-check against frontmatter issues: count
  FM_ISSUES=$(awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^[[:space:]]*issues[[:space:]]*:/ {
      val=$0; sub(/^[^:]*:[[:space:]]*/, "", val); gsub(/[[:space:]]+$/, "", val)
      print val; exit
    }
  ' "$UAT_FILE" 2>/dev/null || true)
  FM_ISSUES=$(printf '%s' "$FM_ISSUES" | tr -d '[:space:]')
  if [ -n "$FM_ISSUES" ] && [ "$FM_ISSUES" != "0" ]; then
    echo "uat_extract_error=inconsistent_status frontmatter_issues=${FM_ISSUES} parsed_issues=0" >&2
    echo "uat_extract_error=true"
    exit 0
  fi
fi

# Compute current round number from archived round files
if type count_uat_rounds &>/dev/null; then
  MAX_ARCHIVED=$(count_uat_rounds "$PHASE_DIR" "$PHASE_NUM")
else
  MAX_ARCHIVED=0
fi
CURRENT_ROUND=$((MAX_ARCHIVED + 1))

# Build recurrence map: for each archived round, extract issue IDs
# Format: associative-style lines "ID ROUND_NUM" in a temp file
# Scans both flat layout ({NN}-UAT-round-*.md) and round-dir layout
# (remediation/uat/round-*/R*-UAT.md).
: > /tmp/.vbw-uat-round-ids-$$.txt
if type extract_round_issue_ids &>/dev/null && [ "$MAX_ARCHIVED" -gt 0 ]; then
  # Flat layout: {phase_num}-UAT-round-{NN}.md
  for rf in "${PHASE_DIR%/}/${PHASE_NUM}"-UAT-round-*.md; do
    [ -f "$rf" ] || continue
    ROUND_NUM=$(basename "$rf" | sed "s/^${PHASE_NUM}-UAT-round-0*\\([0-9]*\\)\\.md$/\\1/")
    if [ -n "$ROUND_NUM" ] && echo "$ROUND_NUM" | grep -qE '^[0-9]+$'; then
      extract_round_issue_ids "$rf" | while IFS= read -r rid; do
        [ -n "$rid" ] && printf '%s %s\n' "$rid" "$ROUND_NUM"
      done
    fi
  done >> /tmp/.vbw-uat-round-ids-$$.txt
  # Round-dir layout: remediation/uat/round-{NN}/R{NN}-UAT.md
  for rf in "${PHASE_DIR%/}"/remediation/uat/round-*/R*-UAT.md; do
    [ -f "$rf" ] || continue
    ROUND_NUM=$(basename "$rf" | sed 's/^R0*\([0-9]*\)-UAT\.md$/\1/')
    if [ -n "$ROUND_NUM" ] && echo "$ROUND_NUM" | grep -qE '^[0-9]+$'; then
      extract_round_issue_ids "$rf" | while IFS= read -r rid; do
        [ -n "$rid" ] && printf '%s %s\n' "$rid" "$ROUND_NUM"
      done
    fi
  done >> /tmp/.vbw-uat-round-ids-$$.txt
fi

# Header line (now includes uat_round)
echo "uat_phase=${PHASE_NUM} uat_issues_total=${ISSUE_COUNT} uat_round=${CURRENT_ROUND} uat_file=$(basename "$UAT_FILE")"

# Issue lines with FAILED_IN_ROUNDS (4th field)
while IFS='|' read -r id severity desc; do
  [ -z "$id" ] && continue
  # Collect rounds where this ID failed in archived files
  PAST_ROUNDS=""
  if [ -s /tmp/.vbw-uat-round-ids-$$.txt ]; then
    PAST_ROUNDS=$(grep "^${id} " /tmp/.vbw-uat-round-ids-$$.txt | awk '{print $2}' | sort -n | tr '\n' ',' | sed 's/,$//' || true)
  fi
  # Append current round
  if [ -n "$PAST_ROUNDS" ]; then
    FAILED_IN="${PAST_ROUNDS},${CURRENT_ROUND}"
  else
    FAILED_IN="${CURRENT_ROUND}"
  fi
  printf '%s|%s|%s|%s\n' "$id" "$severity" "$desc" "$FAILED_IN"
done < /tmp/.vbw-uat-issues-$$.txt

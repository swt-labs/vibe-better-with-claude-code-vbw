#!/usr/bin/env bash
# write-debug-session.sh — Deterministic writer for debug session markdown.
#
# Single writer for all debug-session updates. Modes:
#   investigation  — writes Issue, Investigation, Plan, Implementation sections
#   qa             — appends a QA round entry under ## QA
#   uat            — appends a UAT round entry under ## UAT
#   status         — updates frontmatter status and optional title
#
# Usage:
#   echo '{"mode":"investigation","issue":"...","hypotheses":[...],...}' | write-debug-session.sh <session-file>
#   echo '{"mode":"qa","round":1,"result":"PASS|FAIL|PARTIAL","checks":{...},"details":[...]}' | write-debug-session.sh <session-file>
#   echo '{"mode":"uat","round":1,"result":"pass|issues_found","checkpoints":[...],"issues":[...]}' | write-debug-session.sh <session-file>
#   echo '{"mode":"status","status":"qa_pending","title":"optional new title"}' | write-debug-session.sh <session-file>
#
# Input: JSON on stdin
# Output: Updates the session file in-place
# Exit 1 on invalid JSON or missing required fields

set -euo pipefail

SESSION_FILE="${1:-}"
if [ -z "$SESSION_FILE" ]; then
  echo "Usage: write-debug-session.sh <session-file>" >&2
  exit 1
fi

if [ ! -f "$SESSION_FILE" ] || [ -L "$SESSION_FILE" ]; then
  echo "Error: session file not found or is a symlink: $SESSION_FILE" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not found in PATH" >&2
  exit 1
fi

# Read stdin
json=$(cat)

if ! echo "$json" | jq empty 2>/dev/null; then
  echo "Error: invalid JSON on stdin" >&2
  exit 1
fi

MODE=$(echo "$json" | jq -r '.mode // empty')
if [ -z "$MODE" ]; then
  echo "Error: missing required field 'mode'" >&2
  exit 1
fi

NOW=$(date '+%Y-%m-%d %H:%M:%S')

# Update frontmatter field, scoped to the YAML frontmatter block only.
# Uses awk to restrict replacement to lines between the opening and closing --- delimiters.
update_frontmatter() {
  local field="$1" value="$2"
  if ! grep -q "^${field}:" "$SESSION_FILE" 2>/dev/null; then
    return
  fi

  awk -v field="$field" -v value="$value" '
    BEGIN { in_fm = 0; delim = 0 }
    $0 == "---" {
      delim++
      if (delim == 1) in_fm = 1
      else if (delim == 2) in_fm = 0
      print; next
    }
    in_fm && $0 ~ ("^" field ":") {
      print field ": " value
      next
    }
    { print }
  ' "$SESSION_FILE" > "$SESSION_FILE.tmp" && mv "$SESSION_FILE.tmp" "$SESSION_FILE"
}

# Known top-level session section headings (used as boundaries by replace/append/extract).
# Only these lines are treated as section delimiters — user-pasted ## headings inside
# section content are preserved verbatim and do not prematurely end a section.
KNOWN_SECTIONS_RE='^## (Issue|Investigation|Plan|Implementation|QA|UAT|Remediation History)$'

# Strip leading and trailing blank lines while preserving intentional internal spacing.
normalize_content() {
  printf '%s' "$1" | awk '
    { buf[++n] = $0 }
    END {
      start = 1
      while (start <= n && buf[start] == "") start++
      end = n
      while (end >= start && buf[end] == "") end--
      for (i = start; i <= end; i++) print buf[i]
    }
  '
}

write_normalized_content_file() {
  local content="$1" file="$2"
  normalize_content "$content" > "$file"
}

# Normalize free-form block bodies before embedding them under nested markdown headings.
normalize_block_body() {
  normalize_content "$1"
}

# Escape multiline values for markdown tables without relying on sed implementation quirks.
escape_table_cell() {
  awk '
    BEGIN { first = 1 }
    {
      sub(/\r$/, "", $0)
      gsub(/\|/, "\\|", $0)
      if (!first) printf "<br>"
      printf "%s", $0
      first = 0
    }
  '
}

# Replace content of a section (from ## Heading to next known top-level section or EOF)
replace_section() {
  local heading="$1" content="$2"
  local tmpfile content_file
  tmpfile=$(mktemp)
  content_file=$(mktemp)
  write_normalized_content_file "$content" "$content_file"
  awk -v heading="$heading" -v cfile="$content_file" -v bre="$KNOWN_SECTIONS_RE" '
    BEGIN { in_section = 0; printed = 0 }
    $0 ~ bre {
      if (in_section) {
        in_section = 0
        printed = 1
      }
      if ($0 == "## " heading) {
        print $0
        print ""
        content_printed = 0
        while ((getline line < cfile) > 0) {
          print line
          content_printed = 1
        }
        close(cfile)
        if (content_printed) print ""
        in_section = 1
        next
      }
    }
    !in_section { print }
    END {
      if (in_section && !printed) {
        # Section was last in file — content already printed after heading
      }
    }
  ' "$SESSION_FILE" > "$tmpfile"
  rm -f "$content_file"
  mv "$tmpfile" "$SESSION_FILE"
}

# Append content under a section heading (before the next known top-level section or at EOF)
append_to_section() {
  local heading="$1" content="$2"
  local current_section normalized_new combined_content

  current_section=$(extract_section "$heading" "$SESSION_FILE")
  current_section=$(normalize_content "$current_section")
  normalized_new=$(normalize_content "$content")

  if [ -n "$current_section" ] && [ -n "$normalized_new" ]; then
    combined_content="${current_section}"$'\n\n'"${normalized_new}"
  elif [ -n "$normalized_new" ]; then
    combined_content="$normalized_new"
  else
    combined_content="$current_section"
  fi

  replace_section "$heading" "$combined_content"
}

# Extract content of a section (from ## Heading to next known top-level section or EOF),
# excluding the heading itself.
# Strips leading and trailing blank lines (BSD-compatible)
extract_section() {
  local heading="$1" file="$2"
  awk -v heading="$heading" -v bre="$KNOWN_SECTIONS_RE" '
    $0 ~ bre {
      if (in_section) exit
      if ($0 == "## " heading) { in_section = 1; next }
    }
    in_section {
      # Buffer lines, only print non-trailing-blank content
      buf[++n] = $0
    }
    END {
      # Find first and last non-empty lines
      start = 0; end = 0
      for (i = 1; i <= n; i++) { if (buf[i] != "") { start = i; break } }
      for (i = n; i >= 1; i--) { if (buf[i] != "") { end = i; break } }
      for (i = start; i <= end; i++) print buf[i]
    }
  ' "$file"
}

# Archive current Investigation/Plan/Implementation to Remediation History
# Called before overwriting during remediation rounds (qa_round > 0)
archive_remediation_round() {
  local qa_round
  qa_round=$(awk '/^---$/{c++; next} c==1 && /^qa_round:/{sub(/^qa_round:[[:space:]]*/, ""); print; exit}' "$SESSION_FILE")
  qa_round="${qa_round:-0}"
  [ "$qa_round" -gt 0 ] 2>/dev/null || return 0

  # Extract current sections
  local inv plan impl
  inv=$(extract_section "Investigation" "$SESSION_FILE")
  plan=$(extract_section "Plan" "$SESSION_FILE")
  impl=$(extract_section "Implementation" "$SESSION_FILE")

  # Only archive if there's substantive content beyond template headings/placeholders.
  # Strip markdown headings and blank lines; check if anything remains.
  local has_content=false
  for _sec in "$inv" "$plan" "$impl"; do
    _stripped=$(printf '%s\n' "$_sec" | grep -v '^#\|^[[:space:]]*$' || true)
    case "$_stripped" in *[a-zA-Z0-9]*) has_content=true; break ;; esac
  done
  $has_content || return 0

  # Build archive entry
  local archive_entry
  archive_entry="### Round $qa_round — $NOW"$'\n'
  [ -n "$inv" ] && archive_entry+=$'\n'"#### Investigation"$'\n\n'"$inv"$'\n'
  [ -n "$plan" ] && archive_entry+=$'\n'"#### Plan"$'\n\n'"$plan"$'\n'
  [ -n "$impl" ] && archive_entry+=$'\n'"#### Implementation"$'\n\n'"$impl"$'\n'

  append_to_section "Remediation History" "$archive_entry"
}

case "$MODE" in
  investigation)
    # Required: issue
    ISSUE=$(echo "$json" | jq -r '.issue // empty')
    if [ -z "$ISSUE" ]; then
      echo "Error: investigation mode requires 'issue' field" >&2
      exit 1
    fi

    # Build Investigation section from hypotheses
    INVESTIGATION=""
    HYPO_COUNT=$(echo "$json" | jq '.hypotheses | length // 0')
    if [ "$HYPO_COUNT" -gt 0 ]; then
      INVESTIGATION="### Hypotheses"$'\n'
      for i in $(seq 0 $((HYPO_COUNT - 1))); do
        H_DESC=$(echo "$json" | jq -r ".hypotheses[$i].description // \"Hypothesis $((i+1))\"")
        H_STATUS=$(echo "$json" | jq -r ".hypotheses[$i].status // \"investigating\"")
        H_FOR=$(echo "$json" | jq -r ".hypotheses[$i].evidence_for // \"None\"")
        H_AGAINST=$(echo "$json" | jq -r ".hypotheses[$i].evidence_against // \"None\"")
        H_CONCLUSION=$(echo "$json" | jq -r ".hypotheses[$i].conclusion // \"Pending\"")
        INVESTIGATION+=$'\n'"#### Hypothesis $((i+1)): $H_DESC"$'\n'
        INVESTIGATION+=$'\n'"- **Status:** $H_STATUS"
        INVESTIGATION+=$'\n'"- **Evidence for:** $H_FOR"
        INVESTIGATION+=$'\n'"- **Evidence against:** $H_AGAINST"
        INVESTIGATION+=$'\n'"- **Conclusion:** $H_CONCLUSION"$'\n'
      done
    fi

    ROOT_CAUSE=$(echo "$json" | jq -r '.root_cause // empty')
    ROOT_CAUSE=$(normalize_block_body "$ROOT_CAUSE")
    if [ -n "$ROOT_CAUSE" ]; then
      INVESTIGATION+=$'\n'"### Root Cause"$'\n\n'"$ROOT_CAUSE"
    fi

    PLAN=$(echo "$json" | jq -r '.plan // empty')
    IMPL=$(echo "$json" | jq -r '.implementation // empty')
    IMPL=$(normalize_block_body "$IMPL")

    # Build Changed Files list
    CHANGED_FILES=""
    CF_COUNT=$(echo "$json" | jq '.changed_files | length // 0')
    if [ "$CF_COUNT" -gt 0 ]; then
      for i in $(seq 0 $((CF_COUNT - 1))); do
        CF=$(echo "$json" | jq -r ".changed_files[$i] // empty")
        [ -n "$CF" ] && CHANGED_FILES+="- $CF"$'\n'
      done
    fi

    COMMIT=$(echo "$json" | jq -r '.commit // "No commit yet."')

    # Archive current sections to Remediation History if this is a remediation round
    archive_remediation_round

    # Write sections — always replace Investigation and Plan to prevent stale content
    # after remediation archival (even if the new payload omits them, clear the section)
    replace_section "Issue" "$ISSUE"
    replace_section "Investigation" "${INVESTIGATION:-_No investigation details provided._}"
    replace_section "Plan" "${PLAN:-_No plan provided._}"

    # Build implementation section
    IMPL_CONTENT=""
    [ -n "$IMPL" ] && IMPL_CONTENT="$IMPL"$'\n'
    IMPL_CONTENT+=$'\n'"### Changed Files"$'\n\n'
    if [ -n "$CHANGED_FILES" ]; then
      IMPL_CONTENT+="$CHANGED_FILES"
    else
      IMPL_CONTENT+="{No files changed yet.}"$'\n'
    fi
    IMPL_CONTENT+=$'\n'"### Commit"$'\n\n'"$COMMIT"

    replace_section "Implementation" "$IMPL_CONTENT"

    # Update title if provided
    TITLE=$(echo "$json" | jq -r '.title // empty')
    [ -n "$TITLE" ] && update_frontmatter "title" "$TITLE"

    update_frontmatter "updated" "$NOW"
    echo "mode=investigation"
    echo "session_file=$SESSION_FILE"
    ;;

  qa)
    ROUND=$(echo "$json" | jq -r '.round // empty')
    RESULT=$(echo "$json" | jq -r '.result // empty')
    if [ -z "$ROUND" ] || [ -z "$RESULT" ]; then
      echo "Error: qa mode requires 'round' and 'result' fields" >&2
      exit 1
    fi

    # Validate result
    case "$RESULT" in
      PASS|FAIL|PARTIAL) ;;
      *)
        echo "Error: qa result must be PASS, FAIL, or PARTIAL (got '$RESULT')" >&2
        exit 1
        ;;
    esac

    # Build QA round entry
    QA_ENTRY="### Round $ROUND — $RESULT"$'\n'

    # Detect checks format: array of objects OR summary object
    CHECKS_TYPE=$(echo "$json" | jq -r '.checks | type // "null"')

    if [ "$CHECKS_TYPE" = "array" ]; then
      # Array format from qa.md: [{id, description, status, evidence}, ...]
      CHECKS_TOTAL=$(echo "$json" | jq '.checks | length')
      CHECKS_PASSED=$(echo "$json" | jq '[.checks[] | select(.status == "PASS" or .status == "pass")] | length')
      CHECKS_FAILED=$((CHECKS_TOTAL - CHECKS_PASSED))

      QA_ENTRY+=$'\n'"**Checks:** $CHECKS_PASSED/$CHECKS_TOTAL passed"
      if [ "$CHECKS_FAILED" -gt 0 ]; then
        QA_ENTRY+=", $CHECKS_FAILED failed"
      fi
      QA_ENTRY+=$'\n'

      # Build details table from checks array
      if [ "$CHECKS_TOTAL" -gt 0 ]; then
        QA_ENTRY+=$'\n'"| Check | Status | Evidence |"$'\n'
        QA_ENTRY+="| ----- | ------ | -------- |"$'\n'
        for i in $(seq 0 $((CHECKS_TOTAL - 1))); do
          D_ID=$(echo "$json" | jq -r ".checks[$i].id // \"C$((i+1))\"" | escape_table_cell)
          D_DESC=$(echo "$json" | jq -r ".checks[$i].description // \"Check $((i+1))\"" | escape_table_cell)
          D_STATUS=$(echo "$json" | jq -r ".checks[$i].status // \"—\"" | escape_table_cell)
          D_EVIDENCE=$(echo "$json" | jq -r ".checks[$i].evidence // \"—\"" | escape_table_cell)
          QA_ENTRY+="| $D_ID: $D_DESC | $D_STATUS | $D_EVIDENCE |"$'\n'
        done
      fi
    elif [ "$CHECKS_TYPE" = "object" ]; then
      # Legacy summary object format: {passed, failed, total}
      CHECKS_PASSED=$(echo "$json" | jq -r '.checks.passed // 0')
      CHECKS_FAILED=$(echo "$json" | jq -r '.checks.failed // 0')
      CHECKS_TOTAL=$(echo "$json" | jq -r '.checks.total // 0')

      QA_ENTRY+=$'\n'"**Checks:** $CHECKS_PASSED/$CHECKS_TOTAL passed"
      if [ "$CHECKS_FAILED" -gt 0 ]; then
        QA_ENTRY+=", $CHECKS_FAILED failed"
      fi
      QA_ENTRY+=$'\n'

      # Add details from .details array if present (legacy format)
      DETAIL_COUNT=$(echo "$json" | jq '.details | length // 0')
      if [ "$DETAIL_COUNT" -gt 0 ]; then
        QA_ENTRY+=$'\n'"| Check | Status | Detail |"$'\n'
        QA_ENTRY+="| ----- | ------ | ------ |"$'\n'
        for i in $(seq 0 $((DETAIL_COUNT - 1))); do
          D_NAME=$(echo "$json" | jq -r ".details[$i].name // \"Check $((i+1))\"" | escape_table_cell)
          D_STATUS=$(echo "$json" | jq -r ".details[$i].status // \"—\"" | escape_table_cell)
          D_DETAIL=$(echo "$json" | jq -r ".details[$i].detail // \"—\"" | escape_table_cell)
          QA_ENTRY+="| $D_NAME | $D_STATUS | $D_DETAIL |"$'\n'
        done
      fi
    else
      QA_ENTRY+=$'\n'"**Checks:** No check data provided"$'\n'
    fi

    SUMMARY=$(echo "$json" | jq -r '.summary // empty')
    SUMMARY=$(normalize_block_body "$SUMMARY")
    [ -n "$SUMMARY" ] && QA_ENTRY+=$'\n'"$SUMMARY"$'\n'

    append_to_section "QA" "$QA_ENTRY"

    # Update frontmatter
    update_frontmatter "qa_round" "$ROUND"
    case "$RESULT" in
      PASS) update_frontmatter "qa_last_result" "pass" ;;
      FAIL) update_frontmatter "qa_last_result" "fail" ;;
      PARTIAL) update_frontmatter "qa_last_result" "fail" ;;
    esac
    update_frontmatter "updated" "$NOW"

    echo "mode=qa"
    echo "round=$ROUND"
    echo "result=$RESULT"
    echo "session_file=$SESSION_FILE"
    ;;

  uat)
    ROUND=$(echo "$json" | jq -r '.round // empty')
    RESULT=$(echo "$json" | jq -r '.result // empty')
    if [ -z "$ROUND" ] || [ -z "$RESULT" ]; then
      echo "Error: uat mode requires 'round' and 'result' fields" >&2
      exit 1
    fi

    case "$RESULT" in
      pass|issues_found) ;;
      *)
        echo "Error: uat result must be pass or issues_found (got '$RESULT')" >&2
        exit 1
        ;;
    esac

    UAT_ENTRY="### Round $ROUND — ${RESULT}"$'\n'

    # Add checkpoints if present
    CP_COUNT=$(echo "$json" | jq '.checkpoints | length // 0')
    if [ "$CP_COUNT" -gt 0 ]; then
      UAT_ENTRY+=$'\n'"**Checkpoints:**"$'\n'
      for i in $(seq 0 $((CP_COUNT - 1))); do
        CP_DESC=$(echo "$json" | jq -r ".checkpoints[$i].description // \"Checkpoint $((i+1))\"")
        CP_RESULT=$(echo "$json" | jq -r ".checkpoints[$i].result // \"pending\"")
        CP_RESPONSE=$(echo "$json" | jq -r ".checkpoints[$i].user_response // empty")
        CP_RESPONSE=$(normalize_content "$CP_RESPONSE")
        case "$CP_RESULT" in
          pass) UAT_ENTRY+="- [x] $CP_DESC"$'\n' ;;
          skip) UAT_ENTRY+="- [-] $CP_DESC (**SKIPPED**)"$'\n' ;;
          issue) UAT_ENTRY+="- [ ] $CP_DESC (**ISSUE**)"$'\n' ;;
          fail) UAT_ENTRY+="- [ ] $CP_DESC (**FAILED**)"$'\n' ;;
          *) UAT_ENTRY+="- [ ] $CP_DESC"$'\n' ;;
        esac
        [ -n "$CP_RESPONSE" ] && UAT_ENTRY+="  > $CP_RESPONSE"$'\n'
      done
    fi

    # Add issues if present
    ISSUE_COUNT=$(echo "$json" | jq '.issues | length // 0')
    if [ "$ISSUE_COUNT" -gt 0 ]; then
      UAT_ENTRY+=$'\n'"**Issues found:**"$'\n'
      for i in $(seq 0 $((ISSUE_COUNT - 1))); do
        # Handle both object format {id, description, severity} and plain string format
        ISSUE_TYPE=$(echo "$json" | jq -r ".issues[$i] | type")
        if [ "$ISSUE_TYPE" = "object" ]; then
          ISSUE_DESC=$(echo "$json" | jq -r ".issues[$i].description // \"Issue $((i+1))\"")
          ISSUE_DESC=$(normalize_content "$ISSUE_DESC")
          ISSUE_SEV=$(echo "$json" | jq -r ".issues[$i].severity // empty")
          if [ -n "$ISSUE_SEV" ]; then
            UAT_ENTRY+="- [$ISSUE_SEV] $ISSUE_DESC"$'\n'
          else
            UAT_ENTRY+="- $ISSUE_DESC"$'\n'
          fi
        else
          ISSUE_DESC=$(echo "$json" | jq -r ".issues[$i] // \"Issue $((i+1))\"")
          ISSUE_DESC=$(normalize_content "$ISSUE_DESC")
          UAT_ENTRY+="- $ISSUE_DESC"$'\n'
        fi
      done
    fi

    SUMMARY=$(echo "$json" | jq -r '.summary // empty')
    SUMMARY=$(normalize_block_body "$SUMMARY")
    [ -n "$SUMMARY" ] && UAT_ENTRY+=$'\n'"$SUMMARY"$'\n'

    append_to_section "UAT" "$UAT_ENTRY"

    # Update frontmatter
    update_frontmatter "uat_round" "$ROUND"
    update_frontmatter "uat_last_result" "$RESULT"
    update_frontmatter "updated" "$NOW"

    echo "mode=uat"
    echo "round=$ROUND"
    echo "result=$RESULT"
    echo "session_file=$SESSION_FILE"
    ;;

  status)
    STATUS=$(echo "$json" | jq -r '.status // empty')
    if [ -z "$STATUS" ]; then
      echo "Error: status mode requires 'status' field" >&2
      exit 1
    fi

    # Validate status
    VALID="investigating fix_applied qa_pending qa_failed uat_pending uat_failed complete"
    FOUND=false
    for v in $VALID; do
      [ "$STATUS" = "$v" ] && FOUND=true
    done
    if [ "$FOUND" = false ]; then
      echo "Error: invalid status '$STATUS'. Valid: $VALID" >&2
      exit 1
    fi

    update_frontmatter "status" "$STATUS"

    TITLE=$(echo "$json" | jq -r '.title // empty')
    [ -n "$TITLE" ] && update_frontmatter "title" "$TITLE"

    update_frontmatter "updated" "$NOW"

    echo "mode=status"
    echo "status=$STATUS"
    echo "session_file=$SESSION_FILE"
    ;;

  *)
    echo "Error: unknown mode '$MODE'. Valid: investigation, qa, uat, status" >&2
    exit 1
    ;;
esac

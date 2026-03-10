#!/bin/bash
set -u
# PostToolUse: Auto-update STATE.md, ROADMAP.md + .execution-state.json on PLAN/SUMMARY writes
# Non-blocking, fail-open (always exit 0)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/uat-utils.sh" ]; then
  source "$SCRIPT_DIR/uat-utils.sh"
fi
if [ -f "$SCRIPT_DIR/summary-utils.sh" ]; then
  # shellcheck source=summary-utils.sh
  source "$SCRIPT_DIR/summary-utils.sh"
else
  # Safe default: report zero completions when helpers unavailable
  count_terminal_summaries() { echo "0"; }
fi

planning_root_from_phase_dir() {
  local phase_dir="$1"
  local phases_dir root

  phases_dir=$(dirname "$phase_dir")
  root=$(dirname "$phases_dir")
  if [ "$(basename "$phases_dir")" = "phases" ] && [ -d "$root" ]; then
    echo "$root"
    return 0
  fi

  echo ".vbw-planning"
}

update_state_md() {
  local phase_dir="$1"
  local planning_root state_md

  planning_root=$(planning_root_from_phase_dir "$phase_dir")
  state_md="${planning_root}/STATE.md"

  [ -f "$state_md" ] || return 0

  local plan_count summary_count pct
  plan_count=$(find "$phase_dir" -maxdepth 1 -name '[0-9]*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')
  summary_count=$(count_terminal_summaries "$phase_dir")

  if [ "$plan_count" -gt 0 ]; then
    pct=$(( (summary_count * 100) / plan_count ))
  else
    pct=0
  fi

  local tmp="${state_md}.tmp.$$"
  sed "s/^Plans: .*/Plans: ${summary_count}\/${plan_count}/" "$state_md" | \
    sed "s/^Progress: .*/Progress: ${pct}%/" > "$tmp" 2>/dev/null && \
    mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

slug_to_name() {
  echo "$1" | sed 's/^[0-9]*-//' | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1'
}

# Check if a phase has unresolved UAT issues
# Uses shared extract_status_value() + latest_non_source_uat() from uat-utils.sh
phase_has_uat_issues() {
  local phase_dir="$1"
  local uat_file status_val
  uat_file=$(latest_non_source_uat "$phase_dir")
  [ -f "$uat_file" ] || return 1
  status_val=$(extract_status_value "$uat_file")
  [ "$status_val" = "issues_found" ]
}

update_roadmap() {
  local phase_dir="$1"
  local planning_root roadmap

  planning_root=$(planning_root_from_phase_dir "$phase_dir")
  roadmap="${planning_root}/ROADMAP.md"

  [ -f "$roadmap" ] || return 0

  local dirname phase_num plan_count summary_count status date_str
  dirname=$(basename "$phase_dir")
  phase_num=$(echo "$dirname" | sed 's/^\([0-9]*\).*/\1/' | sed 's/^0*//')
  [ -z "$phase_num" ] && return 0

  plan_count=$(find "$phase_dir" -maxdepth 1 -name '[0-9]*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')
  summary_count=$(count_terminal_summaries "$phase_dir")

  [ "$plan_count" -eq 0 ] && return 0

  if [ "$summary_count" -eq "$plan_count" ]; then
    if phase_has_uat_issues "$phase_dir"; then
      status="uat issues"
      date_str="-"
    else
      status="complete"
      date_str=$(date +%Y-%m-%d)
    fi
  elif [ "$summary_count" -gt 0 ]; then
    status="in progress"
    date_str="-"
  else
    status="planned"
    date_str="-"
  fi

  # Start with a working copy
  local tmp="${roadmap}.tmp.$$"
  cp "$roadmap" "$tmp" 2>/dev/null || return 0

  # Update extended progress table row (| num - name | done | status | date |)
  local existing_name
  existing_name=$(grep -E "^\| *${phase_num} - " "$roadmap" | head -1 | sed 's/^| *[0-9]* - //' | sed 's/ *|.*//')
  if [ -n "$existing_name" ]; then
    local tmp_ext="${roadmap}.tmp_ext.$$"
    sed "s/^| *${phase_num} - .*/| ${phase_num} - ${existing_name} | ${summary_count}\/${plan_count} | ${status} | ${date_str} |/" "$tmp" > "$tmp_ext" 2>/dev/null && \
      mv "$tmp_ext" "$tmp" 2>/dev/null || rm -f "$tmp_ext" 2>/dev/null
  fi

  # Update simple progress table format (| 01 | ● Done |)
  local padded_num
  padded_num=$(printf '%02d' "$phase_num" 2>/dev/null || echo "$phase_num")
  if grep -qE "^\| *0*${phase_num} *\|" "$tmp" 2>/dev/null; then
    local simple_status
    case "$status" in
      complete)      simple_status="● Done" ;;
      "uat issues")  simple_status="⚠ UAT Issues" ;;
      "in progress") simple_status="◐ In Progress" ;;
      planned)       simple_status="○ Planned" ;;
      *)             simple_status="$status" ;;
    esac
    local tmp_simple="${roadmap}.tmp_s.$$"
    sed "s/^| *0*${phase_num} *|.*/| ${padded_num} | ${simple_status} |/" "$tmp" > "$tmp_simple" 2>/dev/null && \
      mv "$tmp_simple" "$tmp" 2>/dev/null || rm -f "$tmp_simple" 2>/dev/null
  fi

  # Check/uncheck checkbox based on status
  local tmp2="${roadmap}.tmp2.$$"
  if [ "$status" = "complete" ]; then
    sed "s/^- \[ \] Phase ${phase_num}:/- [x] Phase ${phase_num}:/" "$tmp" > "$tmp2" 2>/dev/null && \
      mv "$tmp2" "$tmp" 2>/dev/null || rm -f "$tmp2" 2>/dev/null
  elif [ "$status" = "uat issues" ]; then
    sed "s/^- \[[xX]\] Phase ${phase_num}:/- [ ] Phase ${phase_num}:/" "$tmp" > "$tmp2" 2>/dev/null && \
      mv "$tmp2" "$tmp" 2>/dev/null || rm -f "$tmp2" 2>/dev/null
  fi

  mv "$tmp" "$roadmap" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

update_model_profile() {
  local phase_dir="$1"
  local planning_root state_md config_file

  planning_root=$(planning_root_from_phase_dir "$phase_dir")
  state_md="${planning_root}/STATE.md"

  [ -f "$state_md" ] || return 0

  config_file="${planning_root}/config.json"
  [ -f "$config_file" ] || config_file=".vbw-planning/config.json"

  # Read active model profile from config
  local model_profile
  model_profile=$(jq -r '.model_profile // "quality"' "$config_file" 2>/dev/null || echo "quality")

  # Check if Codebase Profile section exists
  if ! grep -q "^## Codebase Profile" "$state_md" 2>/dev/null; then
    return 0
  fi

  # Check if Model Profile line already exists
  if grep -q "^- \*\*Model Profile:\*\*" "$state_md" 2>/dev/null; then
    # Update existing line
    local tmp="${state_md}.tmp.$$"
    sed "s/^- \*\*Model Profile:\*\*.*/- **Model Profile:** ${model_profile}/" "$state_md" > "$tmp" 2>/dev/null && \
      mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    # Insert after Test Coverage line
    local tmp="${state_md}.tmp.$$"
    sed "/^- \*\*Test Coverage:\*\*/a\\
- **Model Profile:** ${model_profile}" "$state_md" > "$tmp" 2>/dev/null && \
      mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  fi
}

advance_phase() {
  local phase_dir="$1"
  local planning_root state_md

  planning_root=$(planning_root_from_phase_dir "$phase_dir")
  state_md="${planning_root}/STATE.md"

  [ -f "$state_md" ] || return 0

  # Check if triggering phase is complete (terminal status, not just existence)
  local plan_count summary_count
  plan_count=$(find "$phase_dir" -maxdepth 1 -name '[0-9]*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')
  summary_count=$(count_terminal_summaries "$phase_dir")
  [ "$plan_count" -gt 0 ] && [ "$summary_count" -eq "$plan_count" ] || return 0

  # Scan all phase dirs to find next incomplete
  local phases_dir total next_num next_name next_has_uat all_done
  phases_dir=$(dirname "$phase_dir")
  total=$(ls -d "$phases_dir"/*/ 2>/dev/null | wc -l | tr -d ' ')
  next_num=""
  next_name=""
  next_has_uat=false
  all_done=true

  while IFS= read -r dir; do
    local dirname p s
    dirname=$(basename "$dir")
    p=$(find "$dir" -maxdepth 1 -name '[0-9]*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')
    s=$(count_terminal_summaries "$dir")

    if [ "$p" -eq 0 ] || [ "$s" -lt "$p" ]; then
      if [ -z "$next_num" ]; then
        next_num=$(echo "$dirname" | sed 's/^\([0-9]*\).*/\1/' | sed 's/^0*//')
        [ -z "$next_num" ] && next_num=0
        next_name=$(slug_to_name "$dirname")
      fi
      all_done=false
      break
    fi
    # Also not done if phase has unresolved UAT issues
    if phase_has_uat_issues "$dir"; then
      if [ -z "$next_num" ]; then
        next_num=$(echo "$dirname" | sed 's/^\([0-9]*\).*/\1/' | sed 's/^0*//')
        [ -z "$next_num" ] && next_num=0
        next_name=$(slug_to_name "$dirname")
        next_has_uat=true
      fi
      all_done=false
      break
    fi
  done < <(ls -d "$phases_dir"/*/ 2>/dev/null | (sort -V 2>/dev/null || awk -F/ '{n=$NF; gsub(/[^0-9].*/,"",n); if (n == "") n=0; print (n+0)"\t"$0}' | sort -n -k1,1 -k2,2 | cut -f2-))

  [ "$total" -eq 0 ] && return 0

  local tmp="${state_md}.tmp.$$"
  if [ "$all_done" = true ]; then
    sed "s/^Status: .*/Status: complete/" "$state_md" > "$tmp" 2>/dev/null && \
      mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  elif [ -n "$next_num" ]; then
    local next_status="ready"
    [ "$next_has_uat" = true ] && next_status="needs_remediation"
    sed "s/^Phase: .*/Phase: ${next_num} of ${total} (${next_name})/" "$state_md" | \
      sed "s/^Status: .*/Status: ${next_status}/" > "$tmp" 2>/dev/null && \
      mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  fi
}

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

# PLAN.md trigger: update plan count + activate status
if echo "$FILE_PATH" | grep -qE 'phases/[^/]+/[0-9]+(-[0-9]+)?-PLAN\.md$'; then
  update_state_md "$(dirname "$FILE_PATH")"
  update_roadmap "$(dirname "$FILE_PATH")"
  # Status: ready → active when a plan is written
  _sm="$(planning_root_from_phase_dir "$(dirname "$FILE_PATH")")/STATE.md"
  if [ -f "$_sm" ] && grep -q '^Status: ready' "$_sm" 2>/dev/null; then
    _tmp="${_sm}.tmp.$$"
    sed 's/^Status: ready/Status: active/' "$_sm" > "$_tmp" 2>/dev/null && \
      mv "$_tmp" "$_sm" 2>/dev/null || rm -f "$_tmp" 2>/dev/null
  fi
fi

# UAT.md trigger: update roadmap + state when UAT results are written
if echo "$FILE_PATH" | grep -qE 'phases/[^/]+/[0-9]+(-[0-9]+)?-UAT\.md$'; then
  [ -f "$FILE_PATH" ] || exit 0
  update_roadmap "$(dirname "$FILE_PATH")"
  advance_phase "$(dirname "$FILE_PATH")"
  exit 0
fi

# SUMMARY.md trigger: update execution state + progress
if ! echo "$FILE_PATH" | grep -qE 'phases/.*-SUMMARY\.md$'; then
  exit 0
fi

[ -f "$FILE_PATH" ] || exit 0

PHASE_DIR="$(dirname "$FILE_PATH")"
PLANNING_ROOT="$(planning_root_from_phase_dir "$PHASE_DIR")"
STATE_FILE="${PLANNING_ROOT}/.execution-state.json"
SUMMARY_ID="$(basename "$FILE_PATH" | sed 's/-SUMMARY\.md$//')"

# Parse SUMMARY.md YAML frontmatter for phase, plan, status
PHASE=""
PLAN=""
STATUS=""
IN_FRONTMATTER=0

while IFS= read -r line; do
  if [ "$line" = "---" ]; then
    if [ "$IN_FRONTMATTER" -eq 0 ]; then
      IN_FRONTMATTER=1
      continue
    else
      break
    fi
  fi
  if [ "$IN_FRONTMATTER" -eq 1 ]; then
    key=$(echo "$line" | cut -d: -f1 | tr -d ' ')
    val=$(echo "$line" | cut -d: -f2- | sed 's/^ *//')
    case "$key" in
      phase) PHASE="$val" ;;
      plan) PLAN="$val" ;;
      status) STATUS="$val" ;;
    esac
  fi
done < "$FILE_PATH"

# Best-effort fallback for non-frontmatter summaries
if [ -z "$PHASE" ]; then
  PHASE=$(basename "$PHASE_DIR" | sed 's/^\([0-9]*\).*/\1/' | sed 's/^0*//')
fi

if [ -z "$PLAN" ]; then
  PLAN=$(echo "$SUMMARY_ID" | sed 's/^[0-9]*-//')
  [ "$PLAN" = "$SUMMARY_ID" ] && PLAN="$SUMMARY_ID"
fi

# Normalize status: map known variants to canonical values
case "$(echo "${STATUS:-}" | tr '[:upper:]' '[:lower:]')" in
  complete|completed|done) STATUS="complete" ;;
  partial|incomplete|in_progress|in-progress) STATUS="partial" ;;
  failed|error|errored) STATUS="failed" ;;
  "") STATUS="complete" ;;  # default for missing status
  *) STATUS="complete" ;;   # unknown status — normalize to complete
esac

# Update execution-state as best-effort only (never gates STATE/ROADMAP updates)
if [ -f "$STATE_FILE" ] && [ -n "$PLAN" ]; then
  TEMP_FILE="${STATE_FILE}.tmp"
  jq --arg phase "$PHASE" --arg plan "$PLAN" --arg status "$STATUS" --arg summary_id "$SUMMARY_ID" '
    def as_num: (try tonumber catch null);
    if (.plans | type) == "array" then
      .plans |= map(
        if (.id == $summary_id)
           or (.id == $plan)
           or ((.id | split("-") | last | as_num) != null and ($plan | as_num) != null and ((.id | split("-") | last | as_num) == ($plan | as_num)))
        then .status = $status
        else .
        end
      )
    elif (.phases | type) == "object" and .phases[$phase] and (.phases[$phase] | type) == "object" and .phases[$phase][$plan] then
      .phases[$phase][$plan].status = $status
    else
      .
    end
  ' "$STATE_FILE" > "$TEMP_FILE" 2>/dev/null && mv "$TEMP_FILE" "$STATE_FILE" 2>/dev/null || rm -f "$TEMP_FILE" 2>/dev/null
fi

update_state_md "$(dirname "$FILE_PATH")"
update_roadmap "$(dirname "$FILE_PATH")"
update_model_profile "$(dirname "$FILE_PATH")"
advance_phase "$(dirname "$FILE_PATH")"

exit 0

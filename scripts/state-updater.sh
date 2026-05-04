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
  count_complete_summaries() { echo "0"; }
  count_terminal_summaries() { echo "0"; }
  extract_summary_status() { printf ''; return 1; }
fi
if [ -f "$SCRIPT_DIR/phase-state-utils.sh" ]; then
  # shellcheck source=phase-state-utils.sh
  source "$SCRIPT_DIR/phase-state-utils.sh"
else
  list_canonical_phase_dirs() {
    local parent="$1"
    [ -d "$parent" ] || return 0
    local dirs=() d base
    for d in "$parent"/*/; do
      [ -d "$d" ] || continue
      base="${d%/}"; base="${base##*/}"
      case "$base" in [0-9]*-*) dirs+=("${d%/}") ;; esac
    done
    [ ${#dirs[@]} -gt 0 ] || return 0
    printf '%s\n' "${dirs[@]}" | sort -V 2>/dev/null || \
      printf '%s\n' "${dirs[@]}" | awk -F/ '{n=$NF; gsub(/[^0-9].*/,"",n); if (n == "") n=0; print (n+0)"\t"$0}' | sort -n -k1,1 -k2,2 | cut -f2-
  }
  count_phase_plans() {
    local dir="$1"
    local count=0
    local f
    for f in "$dir"/[0-9]*-PLAN.md "$dir"/PLAN.md; do
      [ -f "$f" ] && count=$((count + 1))
    done
    echo "$count"
  }
  phase_dir_display_name() {
    local dir="$1"
    basename "$dir" | sed 's/^[0-9]*-//' | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1'
  }
fi

if ! type normalize_roadmap_phase_num >/dev/null 2>&1; then
  normalize_roadmap_phase_num() {
    local num="$1"
    num=$(printf '%s' "$num" | sed 's/^0*//')
    printf '%s\n' "${num:-0}"
  }
fi

if ! type roadmap_numbering_scheme >/dev/null 2>&1; then
  roadmap_numbering_scheme() {
    printf '%s\n' "unknown"
  }
fi

if ! type roadmap_phase_num_for_dir >/dev/null 2>&1; then
  roadmap_phase_num_for_dir() {
    printf '\n'
  }
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

reconcile_state_md_for_changed_path() {
  local changed_path="$1"

  [ -n "$changed_path" ] || return 0
  [ -f "$SCRIPT_DIR/reconcile-state-md.sh" ] || return 0
  bash "$SCRIPT_DIR/reconcile-state-md.sh" --changed "$changed_path" >/dev/null 2>&1 || true
}

update_state_md() {
  local phase_dir="$1"

  reconcile_state_md_for_changed_path "$phase_dir"
}

is_reconciliation_artifact() {
  local changed_path="$1"

  case "$changed_path" in
    phases/[0-9]*-*/*-PLAN.md|*/phases/[0-9]*-*/*-PLAN.md|\
    phases/[0-9]*-*/PLAN.md|*/phases/[0-9]*-*/PLAN.md|\
    phases/[0-9]*-*/*-SUMMARY.md|*/phases/[0-9]*-*/*-SUMMARY.md|\
    phases/[0-9]*-*/SUMMARY.md|*/phases/[0-9]*-*/SUMMARY.md|\
    phases/[0-9]*-*/*-UAT.md|*/phases/[0-9]*-*/*-UAT.md|\
    phases/[0-9]*-*/*-VERIFICATION.md|*/phases/[0-9]*-*/*-VERIFICATION.md|\
    phases/[0-9]*-*/remediation/uat/round-*/R*-PLAN.md|*/phases/[0-9]*-*/remediation/uat/round-*/R*-PLAN.md|\
    phases/[0-9]*-*/remediation/uat/round-*/R*-SUMMARY.md|*/phases/[0-9]*-*/remediation/uat/round-*/R*-SUMMARY.md|\
    phases/[0-9]*-*/remediation/uat/round-*/R*-UAT.md|*/phases/[0-9]*-*/remediation/uat/round-*/R*-UAT.md|\
    phases/[0-9]*-*/remediation/uat/round-*/R*-VERIFICATION.md|*/phases/[0-9]*-*/remediation/uat/round-*/R*-VERIFICATION.md|\
    phases/[0-9]*-*/remediation/round-*/R*-PLAN.md|*/phases/[0-9]*-*/remediation/round-*/R*-PLAN.md|\
    phases/[0-9]*-*/remediation/round-*/R*-SUMMARY.md|*/phases/[0-9]*-*/remediation/round-*/R*-SUMMARY.md|\
    phases/[0-9]*-*/remediation/round-*/R*-UAT.md|*/phases/[0-9]*-*/remediation/round-*/R*-UAT.md|\
    phases/[0-9]*-*/remediation/round-*/R*-VERIFICATION.md|*/phases/[0-9]*-*/remediation/round-*/R*-VERIFICATION.md|\
    phases/[0-9]*-*/remediation/uat/.uat-remediation-stage|*/phases/[0-9]*-*/remediation/uat/.uat-remediation-stage|\
    phases/[0-9]*-*/remediation/.uat-remediation-stage|*/phases/[0-9]*-*/remediation/.uat-remediation-stage|\
    phases/[0-9]*-*/.uat-remediation-stage|*/phases/[0-9]*-*/.uat-remediation-stage)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

find_phase_dir_for_changed_path() {
  local changed_path="$1"
  local dir parent base parent_base

  [ -n "$changed_path" ] || { echo ""; return 0; }
  if [ -d "$changed_path" ]; then
    dir="$changed_path"
  else
    dir=$(dirname "$changed_path")
  fi

  while [ -n "$dir" ] && [ "$dir" != "." ] && [ "$dir" != "/" ]; do
    base=$(basename "$dir")
    parent=$(dirname "$dir")
    parent_base=$(basename "$parent")
    case "$base" in
      [0-9]*-*)
        if [ "$parent_base" = "phases" ]; then
          echo "$dir"
          return 0
        fi
        ;;
    esac
    dir="$parent"
  done

  echo ""
  return 0
}

is_phase_root_artifact() {
  local changed_path="$1"
  local phase_dir parent_dir

  phase_dir=$(find_phase_dir_for_changed_path "$changed_path")
  [ -n "$phase_dir" ] || return 1
  parent_dir=$(dirname "$changed_path")
  [ "${parent_dir%/}" = "${phase_dir%/}" ]
}

slug_to_name() {
  echo "$1" | sed 's/^[0-9]*-//' | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1'
}

rewrite_roadmap_checkboxes_for_phase() {
  local roadmap="$1" marker="$2"
  shift 2

  [ -f "$roadmap" ] || return 0
  [ "$#" -gt 0 ] || return 0

  local tmp line raw_num line_num target target_num matched
  tmp="${roadmap}.tmp_checkbox.$$.${RANDOM:-0}"
  : > "$tmp" 2>/dev/null || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    matched=false
    if [[ "$line" =~ ^-\ \[.\]\ \[?Phase\ ([0-9][0-9]*): ]]; then
      raw_num="${BASH_REMATCH[1]}"
      line_num=$(normalize_roadmap_phase_num "$raw_num")
      for target in "$@"; do
        [ -n "$target" ] || continue
        target_num=$(normalize_roadmap_phase_num "$target")
        if [ "$line_num" = "$target_num" ]; then
          matched=true
          break
        fi
      done
      if [ "$matched" = true ]; then
        line="- [${marker}]${line:5}"
      fi
    fi
    printf '%s\n' "$line" >> "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 0; }
  done < "$roadmap"

  [ -s "$tmp" ] && mv "$tmp" "$roadmap" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

# Check if a phase has unresolved UAT issues
# Uses shared extract_status_value() + current_uat() from uat-utils.sh
phase_has_uat_issues() {
  local phase_dir="$1"
  local uat_file status_val
  uat_file=$(current_uat "$phase_dir")
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

  local dirname ordinal_phase_num table_phase_num checkbox_phase_num checkbox_scheme prefix_phase_num plan_count summary_count status date_str
  dirname=$(basename "$phase_dir")
  prefix_phase_num=$(echo "$dirname" | sed 's/^\([0-9]*\).*/\1/' | sed 's/^0*//')
  ordinal_phase_num=$(phase_dir_position "$phase_dir")
  if [ -z "$ordinal_phase_num" ]; then
    ordinal_phase_num="$prefix_phase_num"
  fi
  [ -z "$ordinal_phase_num" ] && return 0
  table_phase_num="$ordinal_phase_num"

  plan_count=$(count_phase_plans "$phase_dir")
  summary_count=$(count_terminal_summaries "$phase_dir")
  complete_count=$(count_complete_summaries "$phase_dir")

  [ "$plan_count" -eq 0 ] && return 0

  if [ "$complete_count" -eq "$plan_count" ]; then
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
  local tmp="${roadmap}.tmp.$$.${RANDOM:-0}"
  cp "$roadmap" "$tmp" 2>/dev/null || return 0

  # Update extended progress table row (| num - name | done | status | date |)
  local existing_name
  existing_name=$(grep -E "^\| *${table_phase_num} - " "$roadmap" | head -1 | sed 's/^| *[0-9]* - //' | sed 's/ *|.*//')
  if [ -z "$existing_name" ] && [ -n "$prefix_phase_num" ] && [ "$prefix_phase_num" != "$table_phase_num" ]; then
    table_phase_num="$prefix_phase_num"
    existing_name=$(grep -E "^\| *${table_phase_num} - " "$roadmap" | head -1 | sed 's/^| *[0-9]* - //' | sed 's/ *|.*//')
  fi
  if [ -n "$existing_name" ]; then
    local tmp_ext="${roadmap}.tmp_ext.$$.${RANDOM:-0}"
    sed "s/^| *${table_phase_num} - .*/| ${table_phase_num} - ${existing_name} | ${summary_count}\/${plan_count} | ${status} | ${date_str} |/" "$tmp" > "$tmp_ext" 2>/dev/null && \
      [ -s "$tmp_ext" ] && mv "$tmp_ext" "$tmp" 2>/dev/null || rm -f "$tmp_ext" 2>/dev/null
  fi

  # Update simple progress table format (| 01 | ● Done |)
  local padded_num
  padded_num=$(printf '%02d' "$table_phase_num" 2>/dev/null || echo "$table_phase_num")
  if grep -qE "^\| *0*${table_phase_num} *\|" "$tmp" 2>/dev/null; then
    local simple_status
    case "$status" in
      complete)      simple_status="● Done" ;;
      "uat issues")  simple_status="⚠ UAT Issues" ;;
      "in progress") simple_status="◐ In Progress" ;;
      planned)       simple_status="○ Planned" ;;
      *)             simple_status="$status" ;;
    esac
    local tmp_simple="${roadmap}.tmp_s.$$.${RANDOM:-0}"
    sed "s/^| *0*${table_phase_num} *|.*/| ${padded_num} | ${simple_status} |/" "$tmp" > "$tmp_simple" 2>/dev/null && \
      [ -s "$tmp_simple" ] && mv "$tmp_simple" "$tmp" 2>/dev/null || rm -f "$tmp_simple" 2>/dev/null
  fi

  checkbox_scheme=$(roadmap_numbering_scheme "$tmp" "$(dirname "$phase_dir")")
  checkbox_phase_num=$(roadmap_phase_num_for_dir "$checkbox_scheme" "$phase_dir" "$(dirname "$phase_dir")")

  # Check/uncheck checkbox based on status
  if [ -n "$checkbox_phase_num" ]; then
    if [ "$status" = "complete" ]; then
      rewrite_roadmap_checkboxes_for_phase "$tmp" "x" "$checkbox_phase_num"
    elif [ "$status" = "uat issues" ]; then
      rewrite_roadmap_checkboxes_for_phase "$tmp" " " "$checkbox_phase_num"
    fi
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
    local tmp="${state_md}.tmp.$$.${RANDOM:-0}"
    sed "s/^- \*\*Model Profile:\*\*.*/- **Model Profile:** ${model_profile}/" "$state_md" > "$tmp" 2>/dev/null && \
      [ -s "$tmp" ] && mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    # Insert after Test Coverage line
    local tmp="${state_md}.tmp.$$.${RANDOM:-0}"
    sed "/^- \*\*Test Coverage:\*\*/a\\
- **Model Profile:** ${model_profile}" "$state_md" > "$tmp" 2>/dev/null && \
      [ -s "$tmp" ] && mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  fi
}

advance_phase() {
  local phase_dir="$1"

  reconcile_state_md_for_changed_path "$phase_dir"
}

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
RECONCILE_AFTER=false
if is_reconciliation_artifact "$FILE_PATH"; then
  _changed_phase_dir=$(find_phase_dir_for_changed_path "$FILE_PATH")
  if [ -n "$_changed_phase_dir" ]; then
    RECONCILE_AFTER=true
  fi
fi

# Phase-root PLAN.md trigger: update ROADMAP. STATE.md is reconciled below.
if is_phase_root_artifact "$FILE_PATH" && echo "$FILE_PATH" | grep -qE 'phases/[^/]+/([0-9]+(-[0-9]+)?-PLAN|PLAN)\.md$'; then
  update_roadmap "$(dirname "$FILE_PATH")"
fi

# Phase-root UAT.md trigger: update ROADMAP. STATE.md is reconciled below.
if is_phase_root_artifact "$FILE_PATH" && echo "$FILE_PATH" | grep -qE 'phases/[^/]+/[0-9]+(-[0-9]+)?-UAT\.md$'; then
  if [ -f "$FILE_PATH" ]; then
    update_roadmap "$(dirname "$FILE_PATH")"
  fi
fi

# Phase-root SUMMARY.md trigger: update execution state, ROADMAP, and model profile.
# Remediation R*-SUMMARY.md files may affect current UAT routing but must not
# mark phase-root execution plans complete.
if is_phase_root_artifact "$FILE_PATH" && echo "$FILE_PATH" | grep -qE 'phases/[^/]+/([0-9]+(-[0-9]+)?-SUMMARY|SUMMARY)\.md$' && [ -f "$FILE_PATH" ]; then
  PHASE_DIR="$(dirname "$FILE_PATH")"
  PLANNING_ROOT="$(planning_root_from_phase_dir "$PHASE_DIR")"
  STATE_FILE="${PLANNING_ROOT}/.execution-state.json"
  case "$(basename "$FILE_PATH")" in
    SUMMARY.md) SUMMARY_ID="" ;;
    *) SUMMARY_ID="$(basename "$FILE_PATH" | sed 's/-SUMMARY\.md$//')" ;;
  esac

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

  # Normalize status: only verified terminal SUMMARY statuses update execution-state.
  # Missing, unknown, and nonterminal statuses are intentionally ignored so a
  # partial product write cannot preemptively unlock dependent plans.
  STATUS_RAW="$STATUS"
  if type extract_summary_status >/dev/null 2>&1; then
    _summary_status_raw=$(extract_summary_status "$FILE_PATH" 2>/dev/null || true)
    if [ -n "$_summary_status_raw" ]; then
      STATUS_RAW="$_summary_status_raw"
    fi
  fi
  STATUS_RAW=$(printf '%s' "${STATUS_RAW:-}" | tr '[:upper:]' '[:lower:]' | tr -d "\r\"'" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  STATUS=""
  case "$STATUS_RAW" in
    complete|completed) STATUS="complete" ;;
    partial) STATUS="partial" ;;
    failed) STATUS="failed" ;;
  esac

  # Update execution-state as best-effort only (never gates STATE/ROADMAP updates)
  if [ -f "$STATE_FILE" ] && [ -n "$PLAN" ] && [ -n "$STATUS" ]; then
    TEMP_FILE="${STATE_FILE}.tmp.$$.${RANDOM:-0}"
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
    ' "$STATE_FILE" > "$TEMP_FILE" 2>/dev/null && [ -s "$TEMP_FILE" ] && mv "$TEMP_FILE" "$STATE_FILE" 2>/dev/null || rm -f "$TEMP_FILE" 2>/dev/null
  fi

  update_roadmap "$PHASE_DIR"
  update_model_profile "$PHASE_DIR"
fi

if [ "$RECONCILE_AFTER" = true ]; then
  reconcile_state_md_for_changed_path "$FILE_PATH"
fi

exit 0

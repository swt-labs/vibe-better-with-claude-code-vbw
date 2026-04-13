#!/usr/bin/env bash
set -euo pipefail

# track-known-issues.sh — Maintain a phase-scoped registry of unresolved known issues.
#
# Usage:
#   track-known-issues.sh sync-summaries <phase-dir>
#   track-known-issues.sh sync-verification <phase-dir> <verification-path>
#   track-known-issues.sh promote-todos <phase-dir>
#   track-known-issues.sh status <phase-dir>
#   track-known-issues.sh clear <phase-dir>

CMD="${1:-}"
PHASE_DIR="${2:-}"
VERIFICATION_PATH="${3:-}"

usage() {
  echo "usage: track-known-issues.sh <sync-summaries|sync-verification|promote-todos|status|clear> <phase-dir> [verification-path]" >&2
  exit 1
}

case "$CMD" in
  sync-summaries|status|clear|promote-todos)
    [ -n "$PHASE_DIR" ] || usage
    ;;
  sync-verification)
    [ -n "$PHASE_DIR" ] || usage
    [ -n "$VERIFICATION_PATH" ] || usage
    ;;
  *)
    usage
    ;;
esac

if [ ! -d "$PHASE_DIR" ]; then
  echo "known_issues_path=${PHASE_DIR%/}/known-issues.json"
  echo "known_issues_status=missing_phase_dir"
  echo "known_issues_count=0"
  exit 1
fi

REGISTRY_PATH="${PHASE_DIR%/}/known-issues.json"

extract_frontmatter_array_items() {
  local file_path="${1:-}"
  local key_name="${2:-}"
  [ -f "$file_path" ] || return 0
  [ -n "$key_name" ] || return 0
  awk -v key="$key_name" '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    function strip_quotes(v, first, last) {
      first = substr(v, 1, 1)
      last = substr(v, length(v), 1)
      if ((first == "\"" && last == "\"") || (first == squote && last == squote)) {
        return substr(v, 2, length(v) - 2)
      }
      return v
    }
    function emit_value(v) {
      v = trim(v)
      if (v == "") return
      v = strip_quotes(v)
      if (v != "") print v
    }
    function parse_flow_array(rest, i, ch, current, quote) {
      rest = trim(rest)
      if (rest !~ /^\[/) return 0
      sub(/^\[/, "", rest)
      sub(/\][[:space:]]*$/, "", rest)
      current = ""
      quote = ""
      for (i = 1; i <= length(rest); i++) {
        ch = substr(rest, i, 1)
        if (quote == "") {
          if (ch == "\"" || ch == squote) {
            quote = ch
            current = current ch
            continue
          }
          if (ch == ",") {
            emit_value(current)
            current = ""
            continue
          }
        } else if (ch == quote) {
          quote = ""
          current = current ch
          continue
        }
        current = current ch
      }
      emit_value(current)
      return 1
    }
    BEGIN {
      in_fm = 0
      in_arr = 0
      squote = sprintf("%c", 39)
    }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && $0 ~ ("^" key ":[[:space:]]*") {
      rest = $0
      sub("^" key ":[[:space:]]*", "", rest)
      if (parse_flow_array(rest)) exit
      in_arr = 1
      next
    }
    in_fm && in_arr && /^[[:space:]]+- / {
      line = $0
      sub(/^[[:space:]]+- /, "", line)
      emit_value(line)
      next
    }
    in_fm && in_arr && /^[^[:space:]]/ { exit }
  ' "$file_path" 2>/dev/null
}

frontmatter_key_present() {
  local file_path="${1:-}"
  local key_name="${2:-}"
  [ -f "$file_path" ] || return 1
  [ -n "$key_name" ] || return 1
  awk -v key="$key_name" '
    BEGIN { in_fm = 0; found = 0 }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit(found ? 0 : 1) }
    in_fm && $0 ~ ("^" key ":[[:space:]]*") { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$file_path" >/dev/null 2>&1
}

trim() {
  printf '%s' "${1:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

strip_code_ticks() {
  local value
  value=$(trim "${1:-}")
  value="${value#\`}" 
  value="${value%\`}"
  printf '%s' "$value"
}

phase_number() {
  local base phase
  base=$(basename "${PHASE_DIR%/}")
  phase=$(printf '%s' "$base" | sed 's/^\([0-9]*\).*/\1/')
  phase="${phase:-01}"
  if ! [[ "$phase" =~ ^[0-9]+$ ]]; then
    phase="01"
  fi
  printf '%02d' "$((10#$phase))"
}

relative_to_phase() {
  local target="${1:-}"
  case "$target" in
    "$PHASE_DIR"/*) printf '%s' "${target#"$PHASE_DIR/"}" ;;
    *) printf '%s' "$(basename "$target")" ;;
  esac
}

registry_is_valid() {
  [ -f "$REGISTRY_PATH" ] || return 1
  jq -e '
    type == "object"
    and (.schema_version | type == "number")
    and (.phase | type == "string")
    and (.issues | type == "array")
  ' "$REGISTRY_PATH" >/dev/null 2>&1
}

canonical_json() {
  printf '%s' "${1:-[]}" | jq -cS '.' 2>/dev/null
}

load_registry_issues() {
  if registry_is_valid; then
    jq -c '.issues // []' "$REGISTRY_PATH"
  else
    echo '[]'
  fi
}

status_output() {
  local status="$1"
  local count="$2"
  echo "known_issues_path=$REGISTRY_PATH"
  echo "known_issues_status=$status"
  echo "known_issues_count=$count"
}

count_registry_issues() {
  if registry_is_valid; then
    jq '.issues | length' "$REGISTRY_PATH"
  else
    echo 0
  fi
}

new_issue_object() {
  local test="$1"
  local file="$2"
  local error="$3"
  local source_path="$4"
  local round="$5"
  local disposition="${6:-}"

  if [ -n "$disposition" ]; then
    jq -cn \
      --arg test "$test" \
      --arg file "$file" \
      --arg error "$error" \
      --arg source_path "$source_path" \
      --arg disposition "$disposition" \
      --argjson round "$round" \
      '{
        test: $test,
        file: $file,
        error: $error,
        first_seen_in: $source_path,
        last_seen_in: $source_path,
        first_seen_round: $round,
        last_seen_round: $round,
        times_seen: 1,
        disposition: $disposition
      }'
  else
    jq -cn \
      --arg test "$test" \
      --arg file "$file" \
      --arg error "$error" \
      --arg source_path "$source_path" \
      --argjson round "$round" \
      '{
        test: $test,
        file: $file,
        error: $error,
        first_seen_in: $source_path,
        last_seen_in: $source_path,
        first_seen_round: $round,
        last_seen_round: $round,
        times_seen: 1
      }'
  fi
}

parse_frontmatter_issue_json() {
  local item="$1"
  local source_path="$2"
  local round="$3"
  local test file error

  item=$(trim "$item")
  [ -n "$item" ] || return 1
  if ! printf '%s' "$item" | jq -e '
    type == "object"
    and (.test | type == "string")
    and (.file | type == "string")
    and (.error | type == "string")
  ' >/dev/null 2>&1; then
    return 1
  fi

  test=$(printf '%s' "$item" | jq -r '.test')
  file=$(printf '%s' "$item" | jq -r '.file')
  error=$(printf '%s' "$item" | jq -r '.error')
  new_issue_object "$(strip_code_ticks "$test")" "$(strip_code_ticks "$file")" "$(strip_code_ticks "$error")" "$source_path" "$round"
}

parse_freeform_issue_line() {
  local line="$1"
  local source_path="$2"
  local round="$3"
  local test=""
  local file=""
  local error=""

  line=$(trim "$line")
  [ -n "$line" ] || return 1

  if [[ "$line" =~ ^(.+)[[:space:]]+\(([^()]+)\):[[:space:]]*(.+)$ ]]; then
    test=$(strip_code_ticks "${BASH_REMATCH[1]}")
    file=$(strip_code_ticks "${BASH_REMATCH[2]}")
    error=$(strip_code_ticks "${BASH_REMATCH[3]}")
  elif [[ "$line" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
    test=$(strip_code_ticks "${BASH_REMATCH[1]}")
    file="$test"
    error=$(strip_code_ticks "${BASH_REMATCH[2]}")
  else
    return 1
  fi

  [ -n "$test" ] || return 1
  [ -n "$file" ] || file="$test"
  [ -n "$error" ] || return 1

  new_issue_object "$test" "$file" "$error" "$source_path" "$round"
}

extract_summary_issue_lines() {
  local summary_file
  while IFS= read -r summary_file; do
    [ -f "$summary_file" ] || continue
    local source_rel
    source_rel=$(relative_to_phase "$summary_file")
    awk -v source_rel="$source_rel" '
      /^## Pre-existing Issues/ { found=1; next }
      found && /^## / { exit }
      found && /^[[:space:]]*$/ { next }
      found && /^- / {
        line = $0
        sub(/^- /, "", line)
        print source_rel "\t" line
      }
    ' "$summary_file" 2>/dev/null || true
  done < <(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' \( -name '*-SUMMARY.md' -o -name 'SUMMARY.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
}

extract_summary_issues_json() {
  local tmp_json
  tmp_json=$(mktemp)
  local summary_file source_rel frontmatter_items
  while IFS= read -r summary_file; do
    [ -f "$summary_file" ] || continue
    source_rel=$(relative_to_phase "$summary_file")
    frontmatter_items=$(extract_frontmatter_array_items "$summary_file" pre_existing_issues)
    if frontmatter_key_present "$summary_file" pre_existing_issues; then
      while IFS= read -r item; do
        [ -n "$item" ] || continue
        parse_frontmatter_issue_json "$item" "$source_rel" 0 || true
      done <<< "$frontmatter_items"
    else
      awk -v source_rel="$source_rel" '
        /^## Pre-existing Issues/ { found=1; next }
        found && /^## / { exit }
        found && /^[[:space:]]*$/ { next }
        found && /^- / {
          line = $0
          sub(/^- /, "", line)
          print source_rel "\t" line
        }
      ' "$summary_file" 2>/dev/null | while IFS=$'\t' read -r summary_rel line; do
        [ -n "$summary_rel" ] || continue
        parse_freeform_issue_line "$line" "$summary_rel" 0 || true
      done
    fi
  done < <(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' \( -name '*-SUMMARY.md' -o -name 'SUMMARY.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort)) > "$tmp_json"

  jq -s 'map(select(type == "object")) | unique_by(.test, .file, .error) | sort_by(.test, .file, .error)' "$tmp_json"
  rm -f "$tmp_json"
}

extract_verification_issue_rows() {
  local verification_file="$1"
  local source_rel="$2"
  awk -F'|' -v source_rel="$source_rel" '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    /^## Pre-existing Issues/ { found=1; next }
    found && /^## / { exit }
    found && /^\|/ {
      if ($0 ~ /^\|[[:space:]-]+(\|[[:space:]-]+)+\|?[[:space:]]*$/) next
      test = trim($2)
      file = trim($3)
      err = trim($4)
      if (tolower(test) == "test" && tolower(file) == "file") next
      if (test == "") next
      print source_rel "\t" test "\t" file "\t" err
    }
  ' "$verification_file" 2>/dev/null || true
}

round_for_verification_path() {
  local source_rel="$1"
  local base
  base=$(basename "$source_rel")
  if [[ "$base" =~ ^R([0-9]+)-VERIFICATION\.md$ ]]; then
    printf '%d' "$((10#${BASH_REMATCH[1]}))"
  else
    echo 0
  fi
}

round_for_phase_artifact_path() {
  local source_rel="$1"
  local base
  base=$(basename "$source_rel")
  if [[ "$base" =~ ^R([0-9]+)- ]]; then
    printf '%d' "$((10#${BASH_REMATCH[1]}))"
  else
    echo 0
  fi
}

extract_summary_known_issue_outcomes_json() {
  local summary_file="$1"
  local source_rel="$2"
  local round="$3"
  local tmp_json
  local item
  tmp_json=$(mktemp)

  while IFS= read -r item; do
    item=$(trim "$item")
    [ -n "$item" ] || continue
    if ! printf '%s' "$item" | jq -e '
      type == "object"
      and (.test | type == "string")
      and (.file | type == "string")
      and (.error | type == "string")
      and (.disposition == "accepted-process-exception")
    ' >/dev/null 2>&1; then
      continue
    fi

    test=$(printf '%s' "$item" | jq -r '.test')
    file=$(printf '%s' "$item" | jq -r '.file')
    error=$(printf '%s' "$item" | jq -r '.error')
    disposition=$(printf '%s' "$item" | jq -r '.disposition')
    new_issue_object \
      "$(strip_code_ticks "$test")" \
      "$(strip_code_ticks "$file")" \
      "$(strip_code_ticks "$error")" \
      "$source_rel" \
      "$round" \
      "$disposition"
  done < <(extract_frontmatter_array_items "$summary_file" known_issue_outcomes) > "$tmp_json"

  jq -s 'map(select(type == "object")) | unique_by(.test, .file, .error) | sort_by(.test, .file, .error)' "$tmp_json"
  rm -f "$tmp_json"
}

extract_latest_summary_known_issue_outcomes_json() {
  local summary_file=""
  local source_rel=""
  local round="0"
  summary_file=$(find "$PHASE_DIR/remediation/qa" -maxdepth 2 -type f -name 'R*-SUMMARY.md' 2>/dev/null | (sort -V 2>/dev/null || sort) | tail -1)
  [ -n "$summary_file" ] || { echo '[]'; return 0; }
  source_rel=$(relative_to_phase "$summary_file")
  round=$(round_for_phase_artifact_path "$source_rel")
  extract_summary_known_issue_outcomes_json "$summary_file" "$source_rel" "$round"
}

extract_verification_issues_json() {
  local verification_file="$1"
  local source_rel="$2"
  local round="$3"
  local tmp_json
  tmp_json=$(mktemp)

  extract_verification_issue_rows "$verification_file" "$source_rel" | while IFS=$'\t' read -r _source_rel test file error; do
    [ -n "$test" ] || continue
    test=$(strip_code_ticks "$test")
    file=$(strip_code_ticks "$file")
    error=$(strip_code_ticks "$error")
    [ -n "$file" ] || file="$test"
    [ -n "$error" ] || continue
    new_issue_object "$test" "$file" "$error" "$source_rel" "$round"
  done > "$tmp_json"

  jq -s 'map(select(type == "object")) | unique_by(.test, .file, .error) | sort_by(.test, .file, .error)' "$tmp_json"
  rm -f "$tmp_json"
}

merge_issue_sets() {
  local existing_json="$1"
  local incoming_json="$2"

  jq -cn \
    --argjson existing "$existing_json" \
    --argjson incoming "$incoming_json" '
      def issue_key: (.test + "\u001f" + .file + "\u001f" + (.error // ""));
      def mapify($items): reduce $items[] as $item ({}; .[($item | issue_key)] = $item);
      def merge_issue($old; $new):
        if $old == null then
          $new
        else
          $old
          | .last_seen_in = $new.last_seen_in
          | .last_seen_round = $new.last_seen_round
          | .times_seen = (
              if (($old.last_seen_in // "") == ($new.last_seen_in // "") and (($old.last_seen_round // 0) == ($new.last_seen_round // 0)))
              then ($old.times_seen // 1)
              else (($old.times_seen // 1) + 1)
              end
            )
          | if ($new.disposition // "") != "" then .disposition = $new.disposition else . end
        end;
      ($existing | mapify(.)) as $existing_map
      | reduce $incoming[] as $issue (
          $existing_map;
          .[($issue | issue_key)] = merge_issue(.[($issue | issue_key)]; $issue)
        )
      | [.[]]
      | sort_by(.test, .file, .error)
    '
}

replace_issue_set() {
  local existing_json="$1"
  local incoming_json="$2"

  jq -cn \
    --argjson existing "$existing_json" \
    --argjson incoming "$incoming_json" '
      def issue_key: (.test + "\u001f" + .file + "\u001f" + (.error // ""));
      def mapify($items): reduce $items[] as $item ({}; .[($item | issue_key)] = $item);
      def merge_issue($old; $new):
        if $old == null then
          $new
        else
          $old
          | .last_seen_in = $new.last_seen_in
          | .last_seen_round = $new.last_seen_round
          | .times_seen = (
              if (($old.last_seen_in // "") == ($new.last_seen_in // "") and (($old.last_seen_round // 0) == ($new.last_seen_round // 0)))
              then ($old.times_seen // 1)
              else (($old.times_seen // 1) + 1)
              end
            )
          | if ($new.disposition // "") != "" then .disposition = $new.disposition else . end
        end;
      ($existing | mapify(.)) as $existing_map
      | [ $incoming[] | merge_issue($existing_map[issue_key]; .) ]
      | sort_by(.test, .file, .error)
    '
}

write_registry() {
  local issues_json="$1"
  local count tmp_file
  count=$(printf '%s' "$issues_json" | jq 'length')

  if [ "$count" -eq 0 ] 2>/dev/null; then
    rm -f "$REGISTRY_PATH"
    status_output "missing" 0
    return 0
  fi

  tmp_file=$(mktemp "${REGISTRY_PATH}.tmp.XXXXXX")
  jq -n \
    --arg phase "$(phase_number)" \
    --argjson issues "$issues_json" '
      {
        schema_version: 1,
        phase: $phase,
        issues: ($issues | sort_by(.test, .file, .error))
      }
    ' > "$tmp_file"
  mv "$tmp_file" "$REGISTRY_PATH"
  status_output "present" "$count"
}

sync_summaries() {
  local existing_state existing_json incoming_json merged_json
  existing_state="missing"
  if [ -f "$REGISTRY_PATH" ]; then
    if registry_is_valid; then
      existing_state="present"
      existing_json=$(load_registry_issues)
    else
      existing_state="malformed"
      existing_json='[]'
    fi
  else
    existing_json='[]'
  fi

  incoming_json=$(extract_summary_issues_json)
  if [ "$existing_state" = "malformed" ]; then
    merged_json=$(printf '%s' "$incoming_json")
  else
    merged_json=$(merge_issue_sets "$existing_json" "$incoming_json")
  fi
  write_registry "$merged_json"
}

sync_verification() {
  local source_rel round existing_state existing_json incoming_json final_json summary_seed_json
  source_rel=$(relative_to_phase "$VERIFICATION_PATH")
  round=$(round_for_verification_path "$source_rel")
  existing_state="missing"

  if [ -f "$REGISTRY_PATH" ]; then
    if registry_is_valid; then
      existing_state="present"
      existing_json=$(load_registry_issues)
    else
      existing_state="malformed"
      existing_json='[]'
    fi
  else
    existing_json='[]'
  fi

  incoming_json=$(extract_verification_issues_json "$VERIFICATION_PATH" "$source_rel" "$round")

  if [ "$round" -gt 0 ] 2>/dev/null; then
    # Round-scoped verification is authoritative for unresolved known issues.
    if [ "$existing_state" = "malformed" ]; then
      existing_json='[]'
    fi
    local incoming_count
    incoming_count=$(printf '%s' "$incoming_json" | jq 'length' 2>/dev/null || echo 0)
    if [ "$incoming_count" -eq 0 ] && [ "$existing_state" = "present" ]; then
      # Empty incoming from round verification means "no data about pre-existing
      # issues" (QA omitted the section or it was empty). Preserve existing
      # registry rather than deleting it — the existing state is authoritative.
      status_output "$existing_state" "$(printf '%s' "$existing_json" | jq 'length')"
      return 0
    fi
    final_json=$(replace_issue_set "$existing_json" "$incoming_json")
    write_registry "$final_json"
    return 0
  fi

  # Phase-level verification only adds new issues — it does not clear the
  # execution-time backlog because initial QA may not have re-verified every
  # pre-existing issue already tracked from SUMMARY.md.
  if [ "$existing_state" != "present" ]; then
    summary_seed_json=$(extract_summary_issues_json)
    final_json=$(merge_issue_sets "$summary_seed_json" "$incoming_json")
  else
    final_json=$(merge_issue_sets "$existing_json" "$incoming_json")
  fi
  write_registry "$final_json"
}

promote_todos() {
  # Promote unresolved known issues to STATE.md ## Todos as [KNOWN-ISSUE] entries.
  # Deduplicates by test name + file path against existing [KNOWN-ISSUE] lines.
  local planning_dir="${VBW_PLANNING_DIR:-}"
  if [ -z "$planning_dir" ]; then
    # PHASE_DIR is like .vbw-planning/phases/03-slug/, so go up two levels
    planning_dir=$(cd "$PHASE_DIR/../.." && pwd)
  fi
  local state_path="${planning_dir}/STATE.md"

  if [ ! -f "$state_path" ]; then
    echo "promoted_count=0"
    echo "already_tracked_count=0"
    echo "total_known_issues=0"
    echo "promote_status=no_state_file"
    return 0
  fi

  local issues_json accepted_outcomes_json promotable_json
  issues_json=$(load_registry_issues)
  accepted_outcomes_json=$(extract_latest_summary_known_issue_outcomes_json)
  promotable_json=$(merge_issue_sets "$issues_json" "$accepted_outcomes_json")
  local total
  total=$(printf '%s' "$promotable_json" | jq 'length')

  if [ "$total" -eq 0 ] 2>/dev/null; then
    echo "promoted_count=0"
    echo "already_tracked_count=0"
    echo "total_known_issues=0"
    echo "promote_status=empty_registry"
    return 0
  fi

  # Read STATE.md content
  local state_content
  state_content=$(cat "$state_path")

  # Extract the todos section for dedup and placeholder checking — two-pass approach mirroring list-todos.sh
  # Captures ALL non-blank lines (not just bullets) so the None. placeholder is detected
  local todos_section todo_anchor
  # Pass 1: flat items directly under ## Todos (not inside ### subsections)
  todos_section=$(printf '%s\n' "$state_content" | awk '
    /^## Todos?$/ { found=1; next }
    found && /^##/ { exit }
    found && /^### / { sub_found=1; next }
    found && sub_found && /^##/ { exit }
    found && !sub_found && /[^ \t]/ { print }
  ')
  todo_anchor="## Todos"

  if [ -z "$todos_section" ]; then
    # Pass 2: legacy ### Pending Todos subsection (pre-migration STATE.md)
    # Stop at ### Completed Todos or any ## heading — explicit boundary
    todos_section=$(printf '%s\n' "$state_content" | awk '
      /^### Pending Todos$/ { found=1; next }
      found && /^### Completed Todos$/ { exit }
      found && /^##/ { exit }
      found && /[^ \t]/ { print }
    ')
    if [ -n "$todos_section" ]; then
      todo_anchor="### Pending Todos"
    fi
  fi

  local phase_num
  phase_num=$(phase_number)
  local today
  today=$(date +%Y-%m-%d)

  local promoted=0
  local already=0
  local new_entries=""
  local disposition_updates=""
  local promoted_details=""

  # Iterate issues and check for duplicates
  local i=0
  while [ "$i" -lt "$total" ]; do
    local test_name file_path error_msg times_seen source_artifact disposition
    test_name=$(printf '%s' "$promotable_json" | jq -r ".[$i].test // \"unknown\"")
    file_path=$(printf '%s' "$promotable_json" | jq -r ".[$i].file // \"unknown\"")
    error_msg=$(printf '%s' "$promotable_json" | jq -r ".[$i].error // \"unspecified error\"")
    times_seen=$(printf '%s' "$promotable_json" | jq -r ".[$i].times_seen // 1")
    source_artifact=$(printf '%s' "$promotable_json" | jq -r ".[$i].last_seen_in // \"\"")
    disposition=$(printf '%s' "$promotable_json" | jq -r ".[$i].disposition // \"\"")

    # Preserve full error for detail context before truncating for STATE.md readability
    local full_error_msg="$error_msg"

    # Truncate error message for todo readability (max 80 chars)
    if [ "${#error_msg}" -gt 80 ]; then
      error_msg="${error_msg:0:77}..."
    fi

    # Dedup by test+file pair regardless of tag prefix (matches [KNOWN-ISSUE], [HIGH], untagged, etc.)
    local is_dup=false
    local needs_disposition_update=false
    local dedup_key="${test_name} (${file_path}): ${error_msg}"
    local existing_line=""
    if printf '%s' "$todos_section" | grep -qF "$dedup_key"; then
      is_dup=true
      # Check if existing line needs a disposition update
      if [ "$disposition" = "accepted-process-exception" ]; then
        existing_line=$(printf '%s' "$todos_section" | grep -F "$dedup_key" | head -1)
        if ! printf '%s' "$existing_line" | grep -qF "accepted as process-exception"; then
          needs_disposition_update=true
        fi
      fi
    fi

    local source_ref=""
    if [ -n "$source_artifact" ]; then
      source_ref=" (see ${source_artifact})"
    fi

    if [ "$is_dup" = true ] && [ "$needs_disposition_update" = true ]; then
      # Already tracked but disposition changed — rewrite the line
      # Preserve any existing ref tag from the original line
      local existing_ref=""
      if [[ "$existing_line" =~ \(ref:([a-f0-9]{8})\) ]]; then
        existing_ref=" (ref:${BASH_REMATCH[1]})"
      fi
      local new_line="- [KNOWN-ISSUE] ${test_name} (${file_path}): ${error_msg} — accepted as process-exception for this phase (phase ${phase_num}, seen ${times_seen}x)${source_ref} (added ${today})${existing_ref}"
      disposition_updates="${disposition_updates}${existing_line}"$'\x1f'"${new_line}"$'\n'
      promoted=$((promoted + 1))
    elif [ "$is_dup" = true ]; then
      already=$((already + 1))
    else
      # Compute ref hash for todo-details linkage
      local ref_hash
      ref_hash=$(printf '%s' "${test_name} (${file_path}): ${error_msg}" | shasum | cut -c1-8)

      if [ "$disposition" = "accepted-process-exception" ]; then
        new_entries="${new_entries}- [KNOWN-ISSUE] ${test_name} (${file_path}): ${error_msg} — accepted as process-exception for this phase (phase ${phase_num}, seen ${times_seen}x)${source_ref} (added ${today}) (ref:${ref_hash})"$'\n'
      else
        new_entries="${new_entries}- [KNOWN-ISSUE] ${test_name} (${file_path}): ${error_msg} (phase ${phase_num}, seen ${times_seen}x)${source_ref} (added ${today}) (ref:${ref_hash})"$'\n'
      fi
      # Collect detail for newly promoted items (use full_error_msg for rich context)
      # Base64-encode full_error_msg to prevent newlines from breaking field separator parsing
      local encoded_error
      encoded_error=$(printf '%s' "$full_error_msg" | base64 | tr -d '\n')
      promoted_details="${promoted_details}${ref_hash}"$'\x1f'"${test_name}"$'\x1f'"${file_path}"$'\x1f'"${encoded_error}"$'\x1f'"${times_seen}"$'\x1f'"${source_artifact}"$'\x1f'"${disposition}"$'\n'
      promoted=$((promoted + 1))
    fi
    i=$((i + 1))
  done

  # Apply disposition updates (rewrite existing lines in-place)
  if [ -n "$disposition_updates" ]; then
    while IFS=$'\x1f' read -r old_line new_line; do
      [ -n "$old_line" ] || continue
      state_content=$(printf '%s\n' "$state_content" | OLD_LINE="$old_line" NEW_LINE="$new_line" awk '
        { if (index($0, ENVIRON["OLD_LINE"]) > 0) print ENVIRON["NEW_LINE"]; else print }
      ')
    done <<< "$disposition_updates"
  fi

  if [ "$promoted" -eq 0 ]; then
    echo "promoted_count=0"
    echo "already_tracked_count=$already"
    echo "total_known_issues=$total"
    echo "promote_status=all_tracked"
    return 0
  fi

  # Write updated STATE.md atomically
  local tmp_file
  tmp_file=$(mktemp "${state_path}.tmp.XXXXXX")

  if [ -z "$new_entries" ]; then
    # Disposition-only updates — state_content already has the rewrites applied
    printf '%s\n' "$state_content" > "$tmp_file"
  else
    # New entries to add — build awk anchor pattern from todo_anchor
    local awk_anchor awk_stop_pattern
    awk_anchor=$(printf '%s' "$todo_anchor" | sed 's/[.[\*^$()+?{|]/\\&/g')
    if [ "$todo_anchor" = "### Pending Todos" ]; then
      awk_stop_pattern='(^### Completed Todos$)|(^##)'
    else
      awk_stop_pattern='^##'
    fi

    if printf '%s' "$todos_section" | grep -qE '^\s*None\.?\s*$'; then
      # Replace the placeholder with new entries
      printf '%s\n' "$state_content" | ENTRIES="${new_entries%$'\n'}" AWK_ANCHOR="$awk_anchor" AWK_STOP="$awk_stop_pattern" awk '
        $0 ~ ENVIRON["AWK_ANCHOR"] { in_todos=1; print; next }
        in_todos && $0 ~ ENVIRON["AWK_STOP"] { in_todos=0; print; next }
        in_todos && /^[[:space:]]*None\.?[[:space:]]*$/ { print ENVIRON["ENTRIES"]; in_todos=0; next }
        { print }
      ' > "$tmp_file"
    else
      # Append new entries before the next section heading after the anchor
      printf '%s\n' "$state_content" | ENTRIES="${new_entries%$'\n'}" AWK_ANCHOR="$awk_anchor" AWK_STOP="$awk_stop_pattern" awk '
        $0 ~ ENVIRON["AWK_ANCHOR"] { in_todos=1; print; next }
        in_todos && $0 ~ ENVIRON["AWK_STOP"] { print ENVIRON["ENTRIES"]; print ""; in_todos=0; print; next }
        { print }
        END { if (in_todos) { print ENVIRON["ENTRIES"] } }
      ' > "$tmp_file"
    fi
  fi

  mv "$tmp_file" "$state_path"

  # Store extended detail for each promoted issue in todo-details.json
  local detail_script=""
  local session_key="${CLAUDE_SESSION_ID:-default}"
  local link="/tmp/.vbw-plugin-root-link-${session_key}"
  if [ -f "${link}/scripts/todo-details.sh" ]; then
    detail_script="${link}/scripts/todo-details.sh"
  fi
  if [ -n "$detail_script" ] && [ -f "$detail_script" ]; then
    local details_path="${planning_dir}/todo-details.json"
    while IFS=$'\x1f' read -r hash p_test p_file p_error p_times p_source p_disp; do
      [ -n "$hash" ] || continue
      # Decode base64-encoded error message
      p_error=$(printf '%s' "$p_error" | base64 -d 2>/dev/null) || p_error="(decode error)"

      local detail_json
      detail_json=$(jq -n \
        --arg summary "${p_test} (${p_file}): ${p_error}" \
        --arg context "Known issue from phase ${phase_num}. Test: ${p_test}. File: ${p_file}. Error: ${p_error}. Seen ${p_times} time(s). Source: ${p_source:-unknown}. Disposition: ${p_disp:-unresolved}." \
        --arg file "$p_file" \
        --arg added "$today" \
        '{summary: $summary, context: $context, files: [$file], added: $added, source: "known-issue"}')

      bash "$detail_script" add "$hash" "$detail_json" "$details_path" >/dev/null 2>&1 || true
    done <<< "$promoted_details"
  fi

  echo "promoted_count=$promoted"
  echo "already_tracked_count=$already"
  echo "total_known_issues=$total"
  echo "promote_status=promoted"
}

case "$CMD" in
  status)
    if [ ! -f "$REGISTRY_PATH" ]; then
      status_output "missing" 0
    elif registry_is_valid; then
      status_output "present" "$(count_registry_issues)"
    else
      status_output "malformed" 0
    fi
    ;;
  clear)
    rm -f "$REGISTRY_PATH"
    status_output "missing" 0
    ;;
  sync-summaries)
    sync_summaries
    ;;
  sync-verification)
    sync_verification
    ;;
  promote-todos)
    promote_todos
    ;;
esac
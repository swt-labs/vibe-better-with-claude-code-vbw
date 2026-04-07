#!/usr/bin/env bash
set -euo pipefail

# track-known-issues.sh — Maintain a phase-scoped registry of unresolved known issues.
#
# Usage:
#   track-known-issues.sh sync-summaries <phase-dir>
#   track-known-issues.sh sync-verification <phase-dir> <verification-path>
#   track-known-issues.sh status <phase-dir>
#   track-known-issues.sh clear <phase-dir>

CMD="${1:-}"
PHASE_DIR="${2:-}"
VERIFICATION_PATH="${3:-}"

usage() {
  echo "usage: track-known-issues.sh <sync-summaries|sync-verification|status|clear> <phase-dir> [verification-path]" >&2
  exit 1
}

case "$CMD" in
  sync-summaries|status|clear)
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
  extract_summary_issue_lines | while IFS=$'\t' read -r source_rel line; do
    [ -n "$source_rel" ] || continue
    parse_freeform_issue_line "$line" "$source_rel" 0 || true
  done > "$tmp_json"

  jq -s 'map(select(type == "object")) | unique_by(.test, .file) | sort_by(.test, .file)' "$tmp_json"
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

  jq -s 'map(select(type == "object")) | unique_by(.test, .file) | sort_by(.test, .file)' "$tmp_json"
  rm -f "$tmp_json"
}

merge_issue_sets() {
  local existing_json="$1"
  local incoming_json="$2"

  jq -cn \
    --argjson existing "$existing_json" \
    --argjson incoming "$incoming_json" '
      def issue_key: (.test + "\u001f" + .file);
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
        end;
      ($existing | mapify(.)) as $existing_map
      | reduce $incoming[] as $issue (
          $existing_map;
          .[($issue | issue_key)] = merge_issue(.[($issue | issue_key)]; $issue)
        )
      | [.[]]
      | sort_by(.test, .file)
    '
}

replace_issue_set() {
  local existing_json="$1"
  local incoming_json="$2"

  jq -cn \
    --argjson existing "$existing_json" \
    --argjson incoming "$incoming_json" '
      def issue_key: (.test + "\u001f" + .file);
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
        end;
      ($existing | mapify(.)) as $existing_map
      | [ $incoming[] | merge_issue($existing_map[issue_key]; .) ]
      | sort_by(.test, .file)
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
        issues: ($issues | sort_by(.test, .file))
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
    final_json=$(replace_issue_set "$existing_json" "$incoming_json")
    write_registry "$final_json"
    return 0
  fi

  # Phase-level verification only adds new issues — it does not clear the
  # execution-time backlog because initial QA may not have re-verified every
  # pre-existing issue already tracked from SUMMARY.md.
  if [ "$existing_state" = "malformed" ]; then
    summary_seed_json=$(extract_summary_issues_json)
    final_json=$(merge_issue_sets "$summary_seed_json" "$incoming_json")
  else
    final_json=$(merge_issue_sets "$existing_json" "$incoming_json")
  fi
  write_registry "$final_json"
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
esac
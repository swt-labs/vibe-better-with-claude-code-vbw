#!/usr/bin/env bash
# track-uat-deviations.sh — deterministic accepted summary-deviation registry.
#
# Usage:
#   track-uat-deviations.sh signature <source-plan> <source-path> <text>
#   track-uat-deviations.sh accepted-signatures <phase-dir>
#   track-uat-deviations.sh record-from-uat <phase-dir> <uat-file>
#   track-uat-deviations.sh todo-from-uat <phase-dir> <uat-file> <checkpoint-id>

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  track-uat-deviations.sh signature <source-plan> <source-path> <text>
  track-uat-deviations.sh accepted-signatures <phase-dir>
  track-uat-deviations.sh record-from-uat <phase-dir> <uat-file>
  track-uat-deviations.sh todo-from-uat <phase-dir> <uat-file> <checkpoint-id>
EOF
}

trim_value() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

lower_value() {
  local value="${1:-}"
  local upper="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  local lower="abcdefghijklmnopqrstuvwxyz"
  local i c pos out=""
  for ((i = 0; i < ${#value}; i++)); do
    c="${value:$i:1}"
    pos="${upper%%"$c"*}"
    if [ "${#pos}" -lt "${#upper}" ]; then
      c="${lower:${#pos}:1}"
    fi
    out="$out$c"
  done
  printf '%s' "$out"
}

strip_uat_metadata_value() {
  local line="${1:-}"
  local prefix="${2:-}"
  line="${line#"$prefix"}"
  trim_value "$line"
}

sha256_text() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 | awk '{print $NF}'
  else
    echo "track-uat-deviations: no sha256 tool available" >&2
    exit 1
  fi
}

deviation_signature() {
  local source_plan source_path text
  source_plan=$(trim_value "${1:-}")
  source_path=$(trim_value "${2:-}")
  text=$(trim_value "${3:-}")
  [ -n "$source_plan" ] || { echo "track-uat-deviations: source plan is required" >&2; exit 1; }
  [ -n "$source_path" ] || { echo "track-uat-deviations: source path is required" >&2; exit 1; }
  [ -n "$text" ] || { echo "track-uat-deviations: deviation text is required" >&2; exit 1; }
  printf '%s\n%s\n%s\n' "$source_plan" "$source_path" "$text" | sha256_text
}

registry_path() {
  local phase_dir="${1:-}"
  [ -n "$phase_dir" ] || { echo "track-uat-deviations: phase dir is required" >&2; exit 1; }
  printf '%s/remediation/uat/accepted-deviations.json\n' "${phase_dir%/}"
}

require_jq_for_registry() {
  local message="${1:-jq not available; accepted deviation registry operation skipped}"
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi
  echo "track-uat-deviations: jq not available; $message" >&2
  return 1
}

emit_accepted_deviation_record() {
  local signature="$1"
  local source_plan="$2"
  local source_path="$3"
  local text="$4"
  local accepted_in="$5"
  local accepted_at="$6"
  jq -cn \
    --arg signature "$signature" \
    --arg source_plan "$source_plan" \
    --arg source_path "$source_path" \
    --arg text "$text" \
    --arg accepted_in "$accepted_in" \
    --arg accepted_at "$accepted_at" \
    '{signature:$signature,source_plan:$source_plan,source_path:$source_path,text:$text,disposition:"accepted-process-exception",accepted_in:$accepted_in,accepted_at:$accepted_at}'
}

append_accepted_deviation_record_if_complete() {
  local output_file="$1"
  local in_d="$2"
  local signature="$3"
  local source_plan="$4"
  local source_path="$5"
  local text="$6"
  local result="$7"
  local disposition="$8"
  local accepted_in="$9"
  local accepted_at="${10}"

  if [ "$in_d" = true ] && [ -n "$signature" ] && [ "$result" = "pass" ] && [ "$disposition" = "accepted-process-exception" ]; then
    emit_accepted_deviation_record "$signature" "$source_plan" "$source_path" "$text" "$accepted_in" "$accepted_at" >> "$output_file"
  fi
}

accepted_signatures() {
  local phase_dir registry
  phase_dir="${1:-}"
  registry=$(registry_path "$phase_dir")
  [ -f "$registry" ] || return 0
  require_jq_for_registry "cannot read accepted deviation registry; continuing without accepted signatures" || return 0
  jq -r '.accepted[]?.signature // empty' "$registry" 2>/dev/null || true
}

record_from_uat() {
  local phase_dir uat_file registry registry_dir tmp_records tmp_registry phase_name now uat_rel
  local line in_d sig source_plan source_path text result disposition
  phase_dir="${1:-}"
  uat_file="${2:-}"
  [ -d "$phase_dir" ] || { echo "track-uat-deviations: phase dir not found: $phase_dir" >&2; exit 1; }
  [ -f "$uat_file" ] || { echo "track-uat-deviations: UAT file not found: $uat_file" >&2; exit 1; }
  require_jq_for_registry "skipping accepted deviation registry sync; UAT result remains valid" || return 0
  registry=$(registry_path "$phase_dir")
  registry_dir=$(dirname "$registry")
  mkdir -p "$registry_dir"
  tmp_records=$(mktemp "${TMPDIR:-/tmp}/vbw-accepted-deviations.XXXXXX")
  tmp_registry=$(mktemp "${TMPDIR:-/tmp}/vbw-accepted-registry.XXXXXX")
  _TRACK_TMP_RECORDS="$tmp_records"
  _TRACK_TMP_REGISTRY="$tmp_registry"
  trap 'rm -f "${_TRACK_TMP_RECORDS:-}" "${_TRACK_TMP_REGISTRY:-}"' EXIT
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  uat_rel="${uat_file#"$phase_dir/"}"
  in_d=false
  sig=""
  source_plan=""
  source_path=""
  text=""
  result=""
  disposition=""

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [[ "$line" == "### "* ]]; then
      append_accepted_deviation_record_if_complete "$tmp_records" "$in_d" "$sig" "$source_plan" "$source_path" "$text" "$result" "$disposition" "$uat_rel" "$now"
      if [[ "$line" =~ ^###[[:space:]]D[0-9]+(:|[[:space:]]) ]]; then
        in_d=true
      else
        in_d=false
      fi
      sig=""
      source_plan=""
      source_path=""
      text=""
      result=""
      disposition=""
      continue
    fi

    if [ "$in_d" = true ] && [[ "$line" == "- **Deviation Signature:**"* ]]; then
      sig=$(strip_uat_metadata_value "$line" "- **Deviation Signature:**")
    elif [ "$in_d" = true ] && [[ "$line" == "- **Source Plan:**"* ]]; then
      source_plan=$(strip_uat_metadata_value "$line" "- **Source Plan:**")
    elif [ "$in_d" = true ] && [[ "$line" == "- **Source Summary:**"* ]]; then
      source_path=$(strip_uat_metadata_value "$line" "- **Source Summary:**")
    elif [ "$in_d" = true ] && [[ "$line" == "- **Source Path:**"* ]]; then
      source_path=$(strip_uat_metadata_value "$line" "- **Source Path:**")
    elif [ "$in_d" = true ] && [[ "$line" == "- **Deviation:**"* ]]; then
      text=$(strip_uat_metadata_value "$line" "- **Deviation:**")
    elif [ "$in_d" = true ] && [[ "$line" == "- **Result:**"* ]]; then
      result=$(lower_value "$(strip_uat_metadata_value "$line" "- **Result:**")")
    elif [ "$in_d" = true ] && [[ "$line" == "- **Disposition:**"* ]]; then
      disposition=$(lower_value "$(strip_uat_metadata_value "$line" "- **Disposition:**")")
    fi
  done < "$uat_file"
  append_accepted_deviation_record_if_complete "$tmp_records" "$in_d" "$sig" "$source_plan" "$source_path" "$text" "$result" "$disposition" "$uat_rel" "$now"

  [ -s "$tmp_records" ] || return 0
  phase_name=$(basename "$phase_dir")
  if [ -f "$registry" ] && jq -e 'type == "object"' "$registry" >/dev/null 2>&1; then
    jq -s --arg phase "$phase_name" '
      .[0] as $registry
      | .[1:] as $new
      | {
          schema_version: 1,
          phase: ($registry.phase // $phase),
          accepted: (((($registry.accepted // []) + $new) | unique_by(.signature)) | sort_by(.source_plan, .source_path, .signature))
        }
    ' "$registry" "$tmp_records" > "$tmp_registry"
  else
    jq -s --arg phase "$phase_name" '{schema_version: 1, phase: $phase, accepted: (.|unique_by(.signature)|sort_by(.source_plan, .source_path, .signature))}' "$tmp_records" > "$tmp_registry"
  fi
  mv "$tmp_registry" "$registry"
}

collapse_spaces() {
  local value="${1:-}"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  while [[ "$value" == *"  "* ]]; do
    value="${value//  / }"
  done
  trim_value "$value"
}

truncate_for_todo() {
  local value max
  value=$(collapse_spaces "${1:-}")
  max="${2:-120}"
  if [ "${#value}" -gt "$max" ] 2>/dev/null; then
    value="${value:0:$((max - 3))}..."
  fi
  printf '%s' "$value"
}

phase_identity() {
  local phase_dir="${1:-}"
  basename "${phase_dir%/}"
}

phase_number() {
  local phase_dir="${1:-}" base phase
  base=$(phase_identity "$phase_dir")
  phase=$(printf '%s' "$base" | sed 's/^\([0-9]*\).*/\1/')
  if [[ "$phase" =~ ^[0-9]+$ ]]; then
    printf '%02d' "$((10#$phase))"
  else
    printf '%s' "$base"
  fi
}

planning_root_for_phase() {
  local phase_dir="${1:-}" dir
  [ -n "$phase_dir" ] || return 1
  dir=$(cd "$phase_dir" 2>/dev/null && pwd -P) || return 1
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ "$(basename "$dir")" = ".vbw-planning" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

relative_to_phase() {
  local phase_dir="${1:-}" target="${2:-}"
  case "$target" in
    "$phase_dir"/*) printf '%s' "${target#"$phase_dir/"}" ;;
    *) printf '%s' "$(basename "$target")" ;;
  esac
}

deviation_todo_ref() {
  local phase_dir="$1" signature="$2" source_plan="$3" source_path="$4" text="$5"
  printf '%s\n%s\n%s\n%s\n%s\n' \
    "$(phase_identity "$phase_dir")" \
    "$signature" \
    "$source_plan" \
    "$source_path" \
    "$text" \
    | sha256_text \
    | cut -c1-8
}

emit_todo_from_uat_status() {
  local status="$1" ref="${2:-}" line="${3:-}" detail_status="${4:-skipped}" detail_warning="${5:-}" todo_warning="${6:-}"
  printf 'todo_status=%s\n' "$status"
  [ -n "$ref" ] && printf 'todo_ref=%s\n' "$ref"
  [ -n "$line" ] && printf 'todo_line=%s\n' "$line"
  [ -n "$detail_status" ] && printf 'detail_status=%s\n' "$detail_status"
  [ -n "$detail_warning" ] && printf 'detail_warning=%s\n' "$detail_warning"
  [ -n "$todo_warning" ] && printf 'todo_warning=%s\n' "$todo_warning"
  return 0
}

extract_requested_uat_deviation() {
  local uat_file="$1" checkpoint_id="$2"
  local line in_target=false

  TODO_UAT_SIGNATURE=""
  TODO_UAT_SOURCE_PLAN=""
  TODO_UAT_SOURCE_PATH=""
  TODO_UAT_DEVIATION=""
  TODO_UAT_RESULT=""
  TODO_UAT_DISPOSITION=""

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [[ "$line" == "### "* ]]; then
      if [ "$in_target" = true ]; then
        return 0
      fi
      if [[ "$line" =~ ^###[[:space:]]${checkpoint_id}(:|[[:space:]]) ]]; then
        in_target=true
      else
        in_target=false
      fi
      continue
    fi

    [ "$in_target" = true ] || continue
    if [[ "$line" == "- **Deviation Signature:**"* ]]; then
      TODO_UAT_SIGNATURE=$(strip_uat_metadata_value "$line" "- **Deviation Signature:**")
    elif [[ "$line" == "- **Source Plan:**"* ]]; then
      TODO_UAT_SOURCE_PLAN=$(strip_uat_metadata_value "$line" "- **Source Plan:**")
    elif [[ "$line" == "- **Source Summary:**"* ]]; then
      TODO_UAT_SOURCE_PATH=$(strip_uat_metadata_value "$line" "- **Source Summary:**")
    elif [[ "$line" == "- **Source Path:**"* ]]; then
      TODO_UAT_SOURCE_PATH=$(strip_uat_metadata_value "$line" "- **Source Path:**")
    elif [[ "$line" == "- **Deviation:**"* ]]; then
      TODO_UAT_DEVIATION=$(strip_uat_metadata_value "$line" "- **Deviation:**")
    elif [[ "$line" == "- **Result:**"* ]]; then
      TODO_UAT_RESULT=$(lower_value "$(strip_uat_metadata_value "$line" "- **Result:**")")
    elif [[ "$line" == "- **Disposition:**"* ]]; then
      TODO_UAT_DISPOSITION=$(lower_value "$(strip_uat_metadata_value "$line" "- **Disposition:**")")
    fi
  done < "$uat_file"

  [ "$in_target" = true ]
}

insert_todo_line() {
  local state_path="$1" todo_line="$2" ref="$3"
  local tmp_file has_todos=false anchor stop_pattern flat_todos grep_status

  grep -qF "(ref:${ref})" "$state_path"
  grep_status=$?
  if [ "$grep_status" -eq 0 ]; then
    return 2
  elif [ "$grep_status" -gt 1 ]; then
    return 1
  fi

  tmp_file=$(mktemp "${state_path}.tmp.XXXXXX") || return 1

  if ! flat_todos=$(awk '
    /^## Todos$/ { found=1; next }
    found && /^## / { exit }
    found && /^### / { exit }
    found && /^- / { print }
  ' "$state_path"); then
    rm -f "$tmp_file"
    return 1
  fi

  if [ -n "$flat_todos" ]; then
    has_todos=true
    anchor='^## Todos$'
    stop_pattern='(^### )|(^## )'
  else
    grep -Eq '^### Pending Todos$' "$state_path"
    grep_status=$?
    if [ "$grep_status" -eq 0 ]; then
      has_todos=true
      anchor='^### Pending Todos$'
      stop_pattern='(^### Completed Todos$)|(^## )'
    elif [ "$grep_status" -gt 1 ]; then
      rm -f "$tmp_file"
      return 1
    else
      grep -Eq '^## Todos$' "$state_path"
      grep_status=$?
      if [ "$grep_status" -eq 0 ]; then
        has_todos=true
        anchor='^## Todos$'
        stop_pattern='(^### )|(^## )'
      elif [ "$grep_status" -gt 1 ]; then
        rm -f "$tmp_file"
        return 1
      fi
    fi
  fi

  if [ "$has_todos" != true ]; then
    if ! cat "$state_path" > "$tmp_file"; then
      rm -f "$tmp_file"
      return 1
    fi
    if ! printf '\n## Todos\n%s\n' "$todo_line" >> "$tmp_file"; then
      rm -f "$tmp_file"
      return 1
    fi
    if ! grep -qF "(ref:${ref})" "$tmp_file"; then
      rm -f "$tmp_file"
      return 1
    fi
    if ! mv "$tmp_file" "$state_path"; then
      rm -f "$tmp_file"
      return 1
    fi
    return 0
  fi

  if ! awk -v todo_line="$todo_line" -v anchor="$anchor" -v stop_re="$stop_pattern" '
    $0 ~ anchor {
      in_todos = 1
      print
      next
    }
    in_todos && $0 ~ stop_re {
      if (!inserted) {
        print todo_line
        print ""
        inserted = 1
      }
      in_todos = 0
      print
      next
    }
    in_todos && /^[[:space:]]*None\.?[[:space:]]*$/ {
      if (!inserted) {
        print todo_line
        inserted = 1
      }
      next
    }
    { print }
    END {
      if (in_todos && !inserted) {
        print todo_line
      }
    }
  ' "$state_path" > "$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi
  if ! grep -qF "(ref:${ref})" "$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi
  if ! mv "$tmp_file" "$state_path"; then
    rm -f "$tmp_file"
    return 1
  fi
  return 0
}

upsert_uat_deviation_detail() {
  local planning_root="$1" phase_dir="$2" uat_file="$3" checkpoint_id="$4" ref="$5" todo_line="$6"
  local signature="$7" source_plan="$8" source_path="$9" text="${10}"
  local detail_script details_path detail_json detail_out detail_status detail_message today uat_rel phase_id

  detail_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/todo-details.sh"
  if [ ! -f "$detail_script" ]; then
    printf 'unavailable\ttodo-details.sh not found'
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    printf 'warning\tjq not available for todo detail registry update'
    return 0
  fi

  details_path="${planning_root%/}/todo-details.json"
  today=$(date +%Y-%m-%d)
  uat_rel=$(relative_to_phase "$phase_dir" "$uat_file")
  phase_id=$(phase_identity "$phase_dir")
  detail_json=$(jq -cn \
    --arg summary "${todo_line#- }" \
    --arg context "Accepted UAT summary deviation for phase ${phase_id}. Deviation: ${text}. Source plan: ${source_plan}. Source: ${source_path}. UAT checkpoint: ${uat_rel}#${checkpoint_id}." \
    --arg source_plan "$source_plan" \
    --arg source_path "$source_path" \
    --arg uat_path "$uat_rel" \
    --arg added "$today" \
    --arg signature "$signature" \
    --arg phase "$phase_id" \
    --arg checkpoint "$checkpoint_id" '
      {
        summary: $summary,
        context: $context,
        files: ([$source_path, $uat_path] | map(select(. != "")) | unique),
        added: $added,
        source: "uat-deviation",
        uat_deviation: {
          phase: $phase,
          checkpoint: $checkpoint,
          signature: $signature,
          source_plan: $source_plan,
          source_path: $source_path
        }
      }
    ')

  detail_out=$(bash "$detail_script" add "$ref" "$detail_json" "$details_path" 2>/dev/null || true)
  detail_status=$(printf '%s' "$detail_out" | jq -r '.status // "error"' 2>/dev/null || echo "error")
  if [ "$detail_status" = "ok" ]; then
    printf 'ok\t'
  else
    detail_message=$(printf '%s' "$detail_out" | jq -r '.message // "todo detail registry update failed"' 2>/dev/null || echo "todo detail registry update failed")
    printf 'warning\t%s' "$detail_message"
  fi
}

todo_from_uat() {
  local phase_dir uat_file checkpoint_id planning_root state_path ref phase_num today summary todo_line insert_status insert_rc detail_result detail_status detail_warning
  phase_dir="${1:-}"
  uat_file="${2:-}"
  checkpoint_id="${3:-}"
  [ -d "$phase_dir" ] || { echo "track-uat-deviations: phase dir not found: $phase_dir" >&2; exit 1; }
  [ -f "$uat_file" ] || { echo "track-uat-deviations: UAT file not found: $uat_file" >&2; exit 1; }
  [[ "$checkpoint_id" =~ ^D[0-9]+$ ]] || { echo "track-uat-deviations: checkpoint id must look like DNN: $checkpoint_id" >&2; exit 1; }

  if ! extract_requested_uat_deviation "$uat_file" "$checkpoint_id"; then
    emit_todo_from_uat_status "missing_metadata"
    return 0
  fi

  if [ "$TODO_UAT_RESULT" != "pass" ] || [ "$TODO_UAT_DISPOSITION" != "accepted-process-exception" ]; then
    emit_todo_from_uat_status "not_accepted"
    return 0
  fi

  if [ -z "$TODO_UAT_SIGNATURE" ] || [ -z "$TODO_UAT_SOURCE_PLAN" ] || [ -z "$TODO_UAT_SOURCE_PATH" ] || [ -z "$TODO_UAT_DEVIATION" ]; then
    emit_todo_from_uat_status "missing_metadata"
    return 0
  fi

  planning_root=$(planning_root_for_phase "$phase_dir" || true)
  if [ -z "$planning_root" ]; then
    emit_todo_from_uat_status "no_state_file"
    return 0
  fi
  state_path="${planning_root%/}/STATE.md"
  if [ ! -f "$state_path" ]; then
    emit_todo_from_uat_status "no_state_file"
    return 0
  fi

  ref=$(deviation_todo_ref "$phase_dir" "$TODO_UAT_SIGNATURE" "$TODO_UAT_SOURCE_PLAN" "$TODO_UAT_SOURCE_PATH" "$TODO_UAT_DEVIATION")
  phase_num=$(phase_number "$phase_dir")
  today=$(date +%Y-%m-%d)
  summary=$(truncate_for_todo "$TODO_UAT_DEVIATION" 110)
  todo_line="- [UAT-DEVIATION] ${TODO_UAT_SOURCE_PLAN}: ${summary} (phase ${phase_num}, see ${TODO_UAT_SOURCE_PATH}) (added ${today}) (ref:${ref})"

  insert_rc=0
  insert_todo_line "$state_path" "$todo_line" "$ref" || insert_rc=$?
  case "$insert_rc" in
    0) insert_status="added" ;;
    2) insert_status="already_tracked" ;;
    *)
      emit_todo_from_uat_status "state_update_failed" "" "" "skipped" "" "STATE.md todo update failed; todo not persisted"
      return 0
      ;;
  esac

  detail_result=$(upsert_uat_deviation_detail "$planning_root" "$phase_dir" "$uat_file" "$checkpoint_id" "$ref" "$todo_line" "$TODO_UAT_SIGNATURE" "$TODO_UAT_SOURCE_PLAN" "$TODO_UAT_SOURCE_PATH" "$TODO_UAT_DEVIATION")
  detail_status="${detail_result%%$'\t'*}"
  detail_warning=""
  if [[ "$detail_result" == *$'\t'* ]]; then
    detail_warning="${detail_result#*$'\t'}"
  fi
  emit_todo_from_uat_status "$insert_status" "$ref" "$todo_line" "$detail_status" "$detail_warning"
}

cmd="${1:-}"
case "$cmd" in
  signature)
    [ $# -eq 4 ] || { usage; exit 1; }
    deviation_signature "$2" "$3" "$4"
    ;;
  accepted-signatures)
    [ $# -eq 2 ] || { usage; exit 1; }
    accepted_signatures "$2"
    ;;
  record-from-uat)
    [ $# -eq 3 ] || { usage; exit 1; }
    record_from_uat "$2" "$3"
    ;;
  todo-from-uat)
    [ $# -eq 4 ] || { usage; exit 1; }
    todo_from_uat "$2" "$3" "$4"
    ;;
  *)
    usage
    exit 1
    ;;
esac
#!/usr/bin/env bash
# track-uat-deviations.sh — deterministic accepted summary-deviation registry.
#
# Usage:
#   track-uat-deviations.sh signature <source-plan> <source-path> <text>
#   track-uat-deviations.sh accepted-signatures <phase-dir>
#   track-uat-deviations.sh record-from-uat <phase-dir> <uat-file>

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  track-uat-deviations.sh signature <source-plan> <source-path> <text>
  track-uat-deviations.sh accepted-signatures <phase-dir>
  track-uat-deviations.sh record-from-uat <phase-dir> <uat-file>
EOF
}

trim_value() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
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

accepted_signatures() {
  local phase_dir registry
  phase_dir="${1:-}"
  registry=$(registry_path "$phase_dir")
  [ -f "$registry" ] || return 0
  require_jq_for_registry "cannot read accepted deviation registry; continuing without accepted signatures" || return 0
  jq -r '.accepted[]?.signature // empty' "$registry" 2>/dev/null || true
}

record_from_uat() {
  local phase_dir uat_file registry registry_dir tmp_records tmp_registry phase_name now
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

  awk -v uat_file="${uat_file#"$phase_dir/"}" -v accepted_at="$now" '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    function json_escape(v) {
      gsub(/\\/, "\\\\", v)
      gsub(/"/, "\\\"", v)
      return v
    }
    function emit() {
      if (in_d && sig != "" && result == "pass" && disposition == "accepted-process-exception") {
        printf "{\"signature\":\"%s\",\"source_plan\":\"%s\",\"source_path\":\"%s\",\"text\":\"%s\",\"disposition\":\"accepted-process-exception\",\"accepted_in\":\"%s\",\"accepted_at\":\"%s\"}\n", json_escape(sig), json_escape(source_plan), json_escape(source_path), json_escape(text), json_escape(uat_file), json_escape(accepted_at)
      }
    }
    /^### / {
      emit()
      in_d = ($0 ~ /^### D[0-9]+(:|[[:space:]])/)
      sig = source_plan = source_path = text = result = disposition = ""
      next
    }
    in_d && /^- \*\*Deviation Signature:\*\*/ {
      sig = $0; sub(/^- \*\*Deviation Signature:\*\*[[:space:]]*/, "", sig); sig = trim(sig); next
    }
    in_d && /^- \*\*Source Plan:\*\*/ {
      source_plan = $0; sub(/^- \*\*Source Plan:\*\*[[:space:]]*/, "", source_plan); source_plan = trim(source_plan); next
    }
    in_d && /^- \*\*Source Summary:\*\*/ {
      source_path = $0; sub(/^- \*\*Source Summary:\*\*[[:space:]]*/, "", source_path); source_path = trim(source_path); next
    }
    in_d && /^- \*\*Source Path:\*\*/ {
      source_path = $0; sub(/^- \*\*Source Path:\*\*[[:space:]]*/, "", source_path); source_path = trim(source_path); next
    }
    in_d && /^- \*\*Deviation:\*\*/ {
      text = $0; sub(/^- \*\*Deviation:\*\*[[:space:]]*/, "", text); text = trim(text); next
    }
    in_d && /^- \*\*Result:\*\*/ {
      result = $0; sub(/^- \*\*Result:\*\*[[:space:]]*/, "", result); result = tolower(trim(result)); next
    }
    in_d && /^- \*\*Disposition:\*\*/ {
      disposition = $0; sub(/^- \*\*Disposition:\*\*[[:space:]]*/, "", disposition); disposition = tolower(trim(disposition)); next
    }
    END { emit() }
  ' "$uat_file" > "$tmp_records"

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
  *)
    usage
    exit 1
    ;;
esac
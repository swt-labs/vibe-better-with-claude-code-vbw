#!/usr/bin/env bash
set -u

# debug-skill-enrichment.sh — bounded sparse-context enrichment for /vbw:debug
#
# Reads a sparse bug/todo description and returns a tiny amount of extra signal:
# - up to 3 likely files matched from concrete symbol/service/type/file cues
# - up to 5 framework/domain markers found in those files
#
# This helper does NOT select skills. It only surfaces bounded evidence so the
# orchestrator can make a better preselection decision without turning every
# sparse todo into a broad repo scan.
#
# Usage:
#   bash debug-skill-enrichment.sh "SplitTransferService reverse split bug"
#   printf '%s' "SplitTransferService reverse split bug" | bash debug-skill-enrichment.sh
#
# Output JSON (always exits 0):
#   {"status":"ok|no_signal|no_match|error","triggered":true|false,...}

if ! command -v jq >/dev/null 2>&1; then
  printf '{"status":"error","triggered":false,"message":"jq unavailable"}\n'
  exit 0
fi

QUERY="${1:-}"
if [ -z "$QUERY" ] && [ ! -t 0 ]; then
  QUERY=$(cat 2>/dev/null || true)
fi

collapse_ws() {
  printf '%s' "$1" | tr '\n' ' ' | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//'
}

append_unique_line() {
  local var_name="$1"
  local value="$2"
  local current=""
  [ -n "$value" ] || return 0
  current=$(eval "printf '%s' \"\${$var_name-}\"")
  if [ -n "$current" ] && printf '%s\n' "$current" | grep -Fqx "$value"; then
    return 0
  fi
  if [ -n "$current" ]; then
    eval "$var_name=\"\${$var_name}\"\$'\\n'\"\$value\""
  else
    eval "$var_name=\"\$value\""
  fi
}

line_count() {
  local value="$1"
  printf '%s\n' "$value" | sed '/^$/d' | wc -l | tr -d ' '
}

json_array_from_lines() {
  local value="$1"
  printf '%s\n' "$value" | sed '/^$/d' | jq -R . | jq -s .
}

join_lines() {
  local value="$1"
  printf '%s\n' "$value" | sed '/^$/d' | awk 'BEGIN { first=1 } { if (!first) printf ", "; printf "%s", $0; first=0 } END { printf "" }'
}

emit_json() {
  local status="$1"
  local triggered="$2"
  local summary="$3"
  local message="$4"
  local tokens_json files_json markers_json
  tokens_json=$(json_array_from_lines "${TOKENS:-}")
  files_json=$(json_array_from_lines "${MATCHED_FILES:-}")
  markers_json=$(json_array_from_lines "${MARKERS:-}")
  jq -n -c \
    --arg status "$status" \
    --arg summary "$summary" \
    --arg message "$message" \
    --argjson triggered "$triggered" \
    --argjson tokens "$tokens_json" \
    --argjson matched_files "$files_json" \
    --argjson markers "$markers_json" \
    '{status:$status, triggered:$triggered, tokens:$tokens, matched_files:$matched_files, markers:$markers, summary:$summary, message:$message, source:"bounded_enrichment"}'
}

QUERY=$(collapse_ws "$QUERY")
if [ -z "$QUERY" ]; then
  emit_json "no_signal" false "" "Empty query"
  exit 0
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P 2>/dev/null || pwd)
if ! cd "$ROOT" 2>/dev/null; then
  emit_json "error" false "" "Unable to enter repository root"
  exit 0
fi

TOKENS=""
MATCHED_FILES=""
MARKERS=""

extract_tokens() {
  printf '%s\n' "$QUERY" | tr '[:space:]' '\n' | awk '
    function clean(v) {
      gsub(/^[`"'"'"'([{<]+/, "", v)
      gsub(/[`"'"'"')]}>.,:;!?]+$/, "", v)
      return v
    }
    function emit(v) {
      if (v == "") return
      v = clean(v)
      if (v == "") return
      if (seen[v]++) return
      print v
    }
    {
      raw = clean($0)
      if (raw == "") next
      if (raw ~ /\// || raw ~ /\.[A-Za-z0-9]+$/) emit(raw)
      if (raw ~ /^[A-Z][a-z0-9_]+([A-Z][A-Za-z0-9_]*)+$/) emit(raw)
      if (raw ~ /^[A-Za-z0-9_]+(Service|Manager|Controller|ViewModel|Repository|Store|Schema|Container|Context|Model)$/) emit(raw)
    }
  ' | head -n 3
}

candidate_stream_for_token() {
  local token="$1"
  {
    git ls-files 2>/dev/null | grep -i -F "$token" 2>/dev/null || true
    git grep -I -l -F -- "$token" 2>/dev/null || true
  } | awk '!seen[$0]++' | head -n 5
}

while IFS= read -r token; do
  [ -n "$token" ] || continue
  append_unique_line TOKENS "$token"
done < <(extract_tokens)

if [ "$(line_count "$TOKENS")" -eq 0 ]; then
  emit_json "no_signal" false "" "No concrete symbol, service, type, or file cue detected"
  exit 0
fi

while IFS= read -r token; do
  [ -n "$token" ] || continue
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    append_unique_line MATCHED_FILES "$file"
    if [ "$(line_count "$MATCHED_FILES")" -ge 3 ]; then
      break
    fi
  done < <(candidate_stream_for_token "$token")
  if [ "$(line_count "$MATCHED_FILES")" -ge 3 ]; then
    break
  fi
done < <(printf '%s\n' "$TOKENS" | sed '/^$/d')

if [ "$(line_count "$MATCHED_FILES")" -eq 0 ]; then
  emit_json "no_match" true "" "Concrete cue detected, but no likely files were found"
  exit 0
fi

while IFS= read -r file; do
  [ -n "$file" ] || continue
  [ -f "$file" ] || continue
  while IFS='|' read -r label pattern; do
    [ -n "$label" ] || continue
    if grep -Eq "$pattern" "$file" 2>/dev/null; then
      append_unique_line MARKERS "$label"
      if [ "$(line_count "$MARKERS")" -ge 5 ]; then
        break
      fi
    fi
  done <<'EOF'
import SwiftData|import[[:space:]]+SwiftData
@Model|@Model
ModelContext|ModelContext
ModelContainer|ModelContainer
FetchDescriptor|FetchDescriptor
VersionedSchema|VersionedSchema
SchemaMigrationPlan|SchemaMigrationPlan
PersistentModel|PersistentModel
import CoreData|import[[:space:]]+CoreData
NSManagedObjectContext|NSManagedObjectContext
NSPersistentContainer|NSPersistentContainer
NSFetchRequest|NSFetchRequest
NSManagedObject|NSManagedObject
EOF
  if [ "$(line_count "$MARKERS")" -ge 5 ]; then
    break
  fi
done < <(printf '%s\n' "$MATCHED_FILES" | sed '/^$/d')

PRIMARY_TOKEN=$(printf '%s\n' "$TOKENS" | sed -n '1p')
FILES_SUMMARY=$(join_lines "$MATCHED_FILES")
MARKERS_SUMMARY=$(join_lines "$MARKERS")
SUMMARY="Bounded enrichment matched ${PRIMARY_TOKEN} -> ${FILES_SUMMARY}"
if [ -n "$MARKERS_SUMMARY" ]; then
  SUMMARY="${SUMMARY}; markers: ${MARKERS_SUMMARY}"
fi

emit_json "ok" true "$SUMMARY" "Bounded enrichment matched likely files"
exit 0
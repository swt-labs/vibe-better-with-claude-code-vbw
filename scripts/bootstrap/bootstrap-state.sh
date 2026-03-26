#!/usr/bin/env bash
set -euo pipefail

# bootstrap-state.sh — Generate STATE.md for a VBW project
#
# Usage: bootstrap-state.sh OUTPUT_PATH PROJECT_NAME MILESTONE_NAME PHASE_COUNT
#   OUTPUT_PATH      Path to write STATE.md
#   PROJECT_NAME     Name of the project
#   MILESTONE_NAME   Name of the current milestone
#   PHASE_COUNT      Number of phases in the roadmap

if [[ $# -lt 4 ]]; then
  echo "Usage: bootstrap-state.sh OUTPUT_PATH PROJECT_NAME MILESTONE_NAME PHASE_COUNT" >&2
  exit 1
fi

OUTPUT_PATH="$1"
PROJECT_NAME="$2"
MILESTONE_NAME="$3"
PHASE_COUNT="$4"

# Validate PHASE_COUNT is a positive integer
if ! [[ "$PHASE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: PHASE_COUNT must be a positive integer, got: '$PHASE_COUNT'" >&2
  exit 1
fi

STARTED=$(date +%Y-%m-%d)

# Ensure parent directory exists
mkdir -p "$(dirname "$OUTPUT_PATH")"

# Extract a section body (lines between heading and next ## heading, exclusive).
# Case-insensitive heading match. Returns empty string if section not found.
extract_section() {
  local file="$1" heading="$2"
  awk -v h="$heading" '
    BEGIN { pat = tolower(h) }
    { low = tolower($0) }
    low ~ ("^##[[:space:]]+" pat "[[:space:]]*$") { found=1; next }
    found && /^## / { found=0 }
    found { print }
  ' "$file"
}

extract_todos_section() {
  local file="$1"
  awk '
    {
      low = tolower($0)

      if (low ~ /^##[[:space:]]+todos[[:space:]]*$/) {
        found=1
        mode="h2"
        next
      }

      if (low ~ /^###[[:space:]]+pending[[:space:]]+todos[[:space:]]*$/) {
        found=1
        mode="h3"
        next
      }

      if (found && mode == "h2" && /^## /) {
        found=0
        mode=""
      }

      if (found && mode == "h3" && (/^## / || /^### /)) {
        found=0
        mode=""
      }

      if (found) {
        print
      }
    }
  ' "$file"
}

format_todos_section() {
  local todos="$1"
  local emitted=0

  if [[ -z "$todos" ]]; then
    echo "None."
    return 0
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local normalized
    normalized=$(printf '%s\n' "$line" | sed -E 's/^[-*][[:space:]]+//' | tr '[:upper:]' '[:lower:]')
    [[ "$normalized" == "none" || "$normalized" == "none." ]] && continue
    echo "$line"
    emitted=1
  done <<< "$todos"

  if [[ "$emitted" -eq 0 ]]; then
    echo "None."
  fi
}

format_decisions_table() {
  local decisions="$1"
  local emitted=0

  if [[ -z "$decisions" ]]; then
    echo "| Decision | Date | Rationale |"
    echo "|----------|------|-----------|"
    echo "| _(No decisions yet)_ | | |"
    return 0
  fi

  echo "| Decision | Date | Rationale |"
  echo "|----------|------|-----------|"

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ^\| ]]; then
      local lower
      lower=$(printf '%s\n' "$line" | tr '[:upper:]' '[:lower:]')
      [[ "$lower" =~ ^\|([[:space:]:-]+\|)+[[:space:]:-]*$ ]] && continue
      [[ "$lower" =~ ^\|[[:space:]]*decision([[:space:]]*\|.*)?$ ]] && continue
      [[ "$lower" =~ ^\|[[:space:]]*_\(no[[:space:]]+decisions[[:space:]]+yet\)_([[:space:]]*\|.*)?$ ]] && continue
      echo "$line"
      emitted=1
      continue
    fi

    [[ "$line" =~ ^#+[[:space:]] ]] && continue
    line=$(printf '%s\n' "$line" | sed -E 's/^[-*][[:space:]]+//')
    local lower_line
    lower_line=$(printf '%s\n' "$line" | tr '[:upper:]' '[:lower:]')
    [[ -z "$line" ]] && continue
    [[ "$lower_line" == "none" ]] && continue
    [[ "$lower_line" == "none." ]] && continue
    [[ "$lower_line" == "_(no decisions yet)_" ]] && continue
    line=$(printf '%s\n' "$line" | sed 's/|/\\|/g')
    echo "| $line | | |"
    emitted=1
  done <<< "$decisions"

  if [[ "$emitted" -eq 0 ]]; then
    echo "| _(No decisions yet)_ | | |"
  fi
}

# Preserve existing project-level sections if output file already exists
# (e.g., carried forward from a prior milestone by persist-state-after-ship.sh)
EXISTING_TODOS=""
EXISTING_DECISIONS=""
EXISTING_BLOCKERS=""
EXISTING_CODEBASE=""
if [[ -f "$OUTPUT_PATH" ]]; then
  EXISTING_TODOS=$(extract_todos_section "$OUTPUT_PATH")
  # Decisions may use "## Decisions" or "## Key Decisions"
  EXISTING_DECISIONS=$(awk '
    { low = tolower($0) }
    low ~ /^##[[:space:]]+(key )?decisions[[:space:]]*$/ { found=1; next }
    found && /^## / { found=0 }
    found && low ~ /^###[[:space:]]+pending[[:space:]]+todos[[:space:]]*$/ { found=0; skip_skills=0; next }
    found && low ~ /^###[[:space:]]+skills[[:space:]]*$/ { skip_skills=1; next }
    skip_skills && /^###?#? / { skip_skills=0 }
    found && !skip_skills { print }
  ' "$OUTPUT_PATH")
  EXISTING_BLOCKERS=$(extract_section "$OUTPUT_PATH" "Blockers")
  EXISTING_CODEBASE=$(extract_section "$OUTPUT_PATH" "Codebase Profile")
fi

{
  echo "# State"
  echo ""
  echo "**Project:** ${PROJECT_NAME}"
  echo "**Milestone:** ${MILESTONE_NAME}"
  echo ""
  echo "## Current Phase"
  echo "Phase: 1 of ${PHASE_COUNT}"
  echo "Plans: 0/0"
  echo "Progress: 0%"
  echo "Status: ready"
  echo ""
  echo "## Phase Status"

  for i in $(seq 1 "$PHASE_COUNT"); do
    if [[ "$i" -eq 1 ]]; then
      echo "- **Phase ${i}:** Pending planning"
    else
      echo "- **Phase ${i}:** Pending"
    fi
  done

  echo ""
  echo "## Key Decisions"
  if [[ -n "$EXISTING_DECISIONS" ]]; then
    format_decisions_table "$EXISTING_DECISIONS"
  else
    format_decisions_table ""
  fi
  echo ""
  echo "## Todos"
  if [[ -n "$EXISTING_TODOS" ]]; then
    format_todos_section "$EXISTING_TODOS"
  else
    format_todos_section ""
  fi
  echo ""
  echo "## Blockers"
  if [[ -n "$EXISTING_BLOCKERS" ]]; then
    echo "$EXISTING_BLOCKERS"
  else
    echo "None"
  fi

  # Codebase Profile (optional — only if it existed in prior state)
  if [[ -n "$EXISTING_CODEBASE" ]]; then
    echo ""
    echo "## Codebase Profile"
    echo "$EXISTING_CODEBASE"
  fi

  echo ""
  echo "## Activity Log"
  echo "- ${STARTED}: Created ${MILESTONE_NAME} milestone (${PHASE_COUNT} phases)"
} > "$OUTPUT_PATH"

exit 0

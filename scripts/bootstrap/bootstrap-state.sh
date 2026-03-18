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

# Preserve existing project-level sections if output file already exists
# (e.g., carried forward from a prior milestone by persist-state-after-ship.sh)
EXISTING_TODOS=""
EXISTING_DECISIONS=""
EXISTING_BLOCKERS=""
EXISTING_CODEBASE=""
if [[ -f "$OUTPUT_PATH" ]]; then
  EXISTING_TODOS=$(extract_section "$OUTPUT_PATH" "Todos")
  # Decisions may use "## Decisions" or "## Key Decisions"
  EXISTING_DECISIONS=$(awk '
    { low = tolower($0) }
    low ~ /^##[[:space:]]+(key )?decisions[[:space:]]*$/ { found=1; next }
    found && /^## / { found=0 }
    found { print }
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
    echo "$EXISTING_DECISIONS"
  else
    echo "| Decision | Date | Rationale |"
    echo "|----------|------|-----------|"
    echo "| _(No decisions yet)_ | | |"
  fi
  echo ""
  echo "## Todos"
  if [[ -n "$EXISTING_TODOS" ]]; then
    echo "$EXISTING_TODOS"
  else
    echo "None."
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

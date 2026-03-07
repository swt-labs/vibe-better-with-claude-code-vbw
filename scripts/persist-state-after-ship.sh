#!/usr/bin/env bash
set -euo pipefail

# persist-state-after-ship.sh — Extract project-level sections from archived
# STATE.md and write a fresh root STATE.md so todos, decisions, skills, blockers,
# and codebase profile survive across milestone boundaries.
#
# Usage: persist-state-after-ship.sh ARCHIVED_STATE_PATH OUTPUT_PATH PROJECT_NAME
#
# Called by Ship mode (vibe.md Step 5) AFTER moving STATE.md to the archive.
# Reads the archived copy and writes a minimal root STATE.md with only
# project-level sections. Milestone-specific sections (Current Phase) are
# excluded — they belong in the archive.
#
# Project-level sections (preserved):
#   ## Decisions (including ### Skills subsection)
#   ## Todos
#   ## Blockers
#   ## Codebase Profile
#   ## Memory
#
# Milestone-level sections (excluded):
#   ## Current Phase / ## Phase Status
#
# Exit codes:
#   0 = success
#   1 = archived STATE.md not found or args missing

if [[ $# -lt 3 ]]; then
  echo "Usage: persist-state-after-ship.sh ARCHIVED_STATE_PATH OUTPUT_PATH PROJECT_NAME" >&2
  exit 1
fi

ARCHIVED_PATH="$1"
OUTPUT_PATH="$2"
PROJECT_NAME="$3"

if [[ ! -f "$ARCHIVED_PATH" ]]; then
  echo "ERROR: Archived STATE.md not found: $ARCHIVED_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

# Sections to preserve (project-level, survive across milestones)
# Uses awk to extract each section by ## heading, stopping at the next ## heading.
# Case-insensitive matching. Collects content from ALL matching headings
# (prints heading once, merges body lines) to handle duplicate sections.
extract_section() {
  local file="$1"
  local heading="$2"
  awk -v h="$heading" '
    BEGIN { pat = tolower(h) }
    { low = tolower($0) }
    low ~ ("^##[[:space:]]+" pat "[[:space:]]*$") { found=1; if (!hdr) { print $0; hdr=1 }; next }
    found && /^## / { found=0 }
    found { print }
  ' "$file"
}

# Decisions section may use "## Decisions" (template) or "## Key Decisions"
# (bootstrap-state.sh). Case-insensitive. Merges all matching occurrences.
extract_decisions_with_skills() {
  local file="$1"
  awk '
    { low = tolower($0) }
    low ~ /^##[[:space:]]+(key )?decisions[[:space:]]*$/ { found=1; if (!hdr) { print $0; hdr=1 }; next }
    found && /^## / { found=0 }
    found { print }
  ' "$file"
}

# Check if extracted section has content beyond just the heading line
section_has_body() {
  [[ -n "$1" ]] && echo "$1" | tail -n +2 | grep -qv '^[[:space:]]*$'
}

generate_root_state() {
  echo "# State"
  echo ""
  echo "**Project:** ${PROJECT_NAME}"
  echo ""

  # Decisions (+ Skills subsection)
  local decisions
  decisions=$(extract_decisions_with_skills "$ARCHIVED_PATH")
  if section_has_body "$decisions"; then
    echo "$decisions"
    echo ""
  else
    echo "## Decisions"
    echo "- _(No decisions yet)_"
    echo ""
  fi

  # Todos
  local todos
  todos=$(extract_section "$ARCHIVED_PATH" "Todos")
  if section_has_body "$todos"; then
    echo "$todos"
    echo ""
  else
    echo "## Todos"
    echo "None."
    echo ""
  fi

  # Blockers
  local blockers
  blockers=$(extract_section "$ARCHIVED_PATH" "Blockers")
  if section_has_body "$blockers"; then
    echo "$blockers"
    echo ""
  else
    echo "## Blockers"
    echo "None"
    echo ""
  fi

  # Codebase Profile (optional — only if it exists in archived state)
  local codebase
  codebase=$(extract_section "$ARCHIVED_PATH" "Codebase Profile")
  if section_has_body "$codebase"; then
    echo "$codebase"
    echo ""
  fi

  # Memory (MuninnDB vault state — persists across milestones)
  local memory
  memory=$(extract_section "$ARCHIVED_PATH" "Memory")
  if section_has_body "$memory"; then
    echo "$memory"
    echo ""
  else
    echo "## Memory"
    echo "**Vault:** _(see config.json)_"
    echo ""
  fi
}

generate_root_state > "$OUTPUT_PATH"

exit 0

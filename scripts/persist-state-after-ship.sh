#!/usr/bin/env bash
set -euo pipefail

# persist-state-after-ship.sh — Extract project-level sections from archived
# STATE.md and write a fresh root STATE.md so todos, decisions, blockers,
# and codebase profile survive across milestone boundaries.
#
# Usage: persist-state-after-ship.sh ARCHIVED_STATE_PATH OUTPUT_PATH PROJECT_NAME
#
# Called by Ship mode (vibe.md Step 5) AFTER moving STATE.md to the archive.
# Reads the archived copy and writes a minimal root STATE.md with only
# project-level sections. Milestone-specific sections (Current Phase, Activity
# Log) are excluded — they belong in the archive.
#
# Project-level sections (preserved):
#   ## Decisions / ## Key Decisions
#   ## Todos / ### Pending Todos
#   ## Blockers
#   ## Codebase Profile
#
# Milestone-level sections (excluded):
#   ## Current Phase / ## Phase Status
#   ## Activity Log / ## Recent Activity
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

extract_section() {
  local file="$1"
  local heading="$2"
  awk -v h="$heading" '
    BEGIN { pat = tolower(h) }
    { low = tolower($0) }
    low ~ ("^##[[:space:]]+" pat "[[:space:]]*$") {
      found=1
      if (!hdr) { print $0; hdr=1 }
      next
    }
    found && /^## / { found=0 }
    found { print }
  ' "$file"
}

extract_todos() {
  local file="$1"
  awk '
    {
      low = tolower($0)

      if (low ~ /^##[[:space:]]+todos[[:space:]]*$/) {
        found=1
        mode="h2"
        if (!hdr) { print "## Todos"; hdr=1 }
        next
      }

      if (low ~ /^###[[:space:]]+pending[[:space:]]+todos[[:space:]]*$/) {
        found=1
        mode="h3"
        if (!hdr) { print "## Todos"; hdr=1 }
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

      if (found) { print }
    }
  ' "$file"
}

extract_decisions() {
  local file="$1"
  awk '
    {
      low = tolower($0)
    }
    low ~ /^##[[:space:]]+(key )?decisions[[:space:]]*$/ {
      found=1
      if (!hdr) { print "## Key Decisions"; hdr=1 }
      next
    }
    found && /^## / { found=0 }
    found && low ~ /^###[[:space:]]+pending[[:space:]]+todos[[:space:]]*$/ { found=0; skip_skills=0; next }
    found && low ~ /^###[[:space:]]+skills[[:space:]]*$/ { skip_skills=1; next }
    skip_skills && /^###?#? / { skip_skills=0 }
    found && !skip_skills { print }
  ' "$file"
}

section_has_body() {
  [[ -n "$1" ]] && echo "$1" | tail -n +2 | grep -qv '^[[:space:]]*$'
}

normalize_decisions_section() {
  local section="$1"
  [[ -n "$section" ]] || return 0

  local rows
  rows=$(printf '%s\n' "$section" | awk '
    NR == 1 { next }
    {
      low = tolower($0)
      if (low ~ /^[-*][[:space:]]+none\.?[[:space:]]*$/) next
      if (low ~ /^none\.?[[:space:]]*$/) next
      if (low ~ /^[-*][[:space:]]+_\(no[[:space:]]+decisions[[:space:]]+yet\)_[[:space:]]*$/) next
      if (low ~ /^\|[[:space:]]*_\(no[[:space:]]+decisions[[:space:]]+yet\)_([[:space:]]*\|.*)?$/) next
      if (low ~ /^\|[[:space:]]*decision([[:space:]]*\|.*)?$/) next
      if (low ~ /^\|([[:space:]:-]+\|)+[[:space:]:-]*$/) next
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 ~ /^#+[[:space:]]/) next
      if ($0 ~ /^\|/) {
        print
        next
      }
      line=$0
      sub(/^[-*][[:space:]]+/, "", line)
      gsub(/\|/, "\\|", line)
      print "| " line " | | |"
    }
  ')

  echo "## Key Decisions"
  echo "| Decision | Date | Rationale |"
  echo "|----------|------|-----------|"
  if [[ -n "$rows" ]]; then
    printf '%s\n' "$rows"
  else
    echo "| _(No decisions yet)_ | | |"
  fi
}

normalize_todos_section() {
  local section="$1"
  [[ -n "$section" ]] || return 0

  local rows
  rows=$(printf '%s\n' "$section" | awk '
    NR == 1 { next }
    {
      low = tolower($0)
      if (low ~ /^[-*][[:space:]]+none\.?[[:space:]]*$/) next
      if (low ~ /^none\.?[[:space:]]*$/) next
      if ($0 ~ /^[[:space:]]*$/) next
      print
    }
  ')

  echo "## Todos"
  if [[ -n "$rows" ]]; then
    printf '%s\n' "$rows"
  else
    echo "None."
  fi
}

generate_root_state() {
  echo "# State"
  echo ""
  echo "**Project:** ${PROJECT_NAME}"
  echo ""

  local decisions
  decisions=$(extract_decisions "$ARCHIVED_PATH")
  decisions=$(normalize_decisions_section "$decisions")
  echo "$decisions"
  echo ""

  local todos
  todos=$(extract_todos "$ARCHIVED_PATH")
  todos=$(normalize_todos_section "$todos")
  echo "$todos"
  echo ""

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

  local codebase
  codebase=$(extract_section "$ARCHIVED_PATH" "Codebase Profile")
  if section_has_body "$codebase"; then
    echo "$codebase"
    echo ""
  fi
}

generate_root_state > "$OUTPUT_PATH"

exit 0

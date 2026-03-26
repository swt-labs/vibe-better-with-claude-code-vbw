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

if ! [[ "$PHASE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: PHASE_COUNT must be a positive integer, got: '$PHASE_COUNT'" >&2
  exit 1
fi

STARTED=$(date +%Y-%m-%d)
mkdir -p "$(dirname "$OUTPUT_PATH")"

extract_section() {
  local file="$1" heading="$2"
  awk -v h="$heading" '
    BEGIN { pat = tolower(h) }
    { low = tolower($0) }
    low ~ ("^##[[:space:]]+" pat "[[:space:]]*$") { found=1; next }
    found && /^##[[:space:]]+/ { found=0 }
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

      if (found && mode == "h2" && /^##[[:space:]]+/) {
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

decision_key() {
  local line="$1"
  local escaped_pipe='__VBW_ESCAPED_PIPE__'

  if [[ "$line" =~ ^\| ]]; then
    line=$(printf '%s\n' "$line" | sed "s/\\\\|/${escaped_pipe}/g" | sed 's/^|//' | sed 's/|$//' | awk -F'|' '{print $1}' | sed "s/${escaped_pipe}/|/g")
  else
    line=$(printf '%s\n' "$line" | sed -E 's/^[-*][[:space:]]+//')
  fi

  printf '%s\n' "$line" | sed -E 's/\*\*//g' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g' | tr '[:upper:]' '[:lower:]'
}

decision_row_score() {
  local line="$1"
  local score=0
  local escaped_pipe='__VBW_ESCAPED_PIPE__'

  if [[ "$line" =~ ^\| ]]; then
    local cols col1 col2 col3
    cols=$(printf '%s\n' "$line" | sed "s/\\\\|/${escaped_pipe}/g" | sed 's/^|//' | sed 's/|$//')
    col1=$(printf '%s\n' "$cols" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1}' | sed "s/${escaped_pipe}/|/g")
    col2=$(printf '%s\n' "$cols" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}' | sed "s/${escaped_pipe}/|/g")
    col3=$(printf '%s\n' "$cols" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3}' | sed "s/${escaped_pipe}/|/g")
    [ -n "$col1" ] && score=1
    [ -n "$col2" ] && score=$((score + 1))
    [ -n "$col3" ] && score=$((score + 1))
  else
    line=$(printf '%s\n' "$line" | sed -E 's/^[-*][[:space:]]+//')
    [ -n "$line" ] && score=1
  fi

  echo "$score"
}

format_decisions_table() {
  local decisions="$1"
  local -a seen_keys=()
  local -a rows=()
  local -a scores=()

  echo "| Decision | Date | Rationale |"
  echo "|----------|------|-----------|"

  if [[ -z "$decisions" ]]; then
    echo "| _(No decisions yet)_ | | |"
    return 0
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^\| ]]; then
      local lower
      lower=$(printf '%s\n' "$line" | tr '[:upper:]' '[:lower:]')
      [[ "$lower" =~ ^\|([[:space:]:-]+\|)+[[:space:]:-]*$ ]] && continue
      [[ "$lower" =~ ^\|[[:space:]]*decision([[:space:]]*\|.*)?$ ]] && continue
      [[ "$lower" =~ ^\|[[:space:]]*_\(no[[:space:]]+decisions[[:space:]]+yet\)_([[:space:]]*\|.*)?$ ]] && continue
    else
      [[ "$line" =~ ^#+[[:space:]] ]] && continue
      line=$(printf '%s\n' "$line" | sed -E 's/^[-*][[:space:]]+//')
      local lower_line
      lower_line=$(printf '%s\n' "$line" | tr '[:upper:]' '[:lower:]')
      [[ -z "$line" ]] && continue
      [[ "$lower_line" == "none" ]] && continue
      [[ "$lower_line" == "none." ]] && continue
      [[ "$lower_line" == "_(no decisions yet)_" ]] && continue
      line=$(printf '%s\n' "$line" | sed 's/|/\\|/g')
      line="| $line | | |"
    fi

    local key score idx found
    key=$(decision_key "$line")
    [ -n "$key" ] || continue
    score=$(decision_row_score "$line")
    found=-1
    for idx in "${!seen_keys[@]}"; do
      if [[ "${seen_keys[$idx]}" == "$key" ]]; then
        found=$idx
        break
      fi
    done

    if [ "$found" -ge 0 ]; then
      if [ "$score" -gt "${scores[$found]}" ]; then
        rows[$found]="$line"
        scores[$found]="$score"
      fi
      continue
    fi

    seen_keys+=("$key")
    rows+=("$line")
    scores+=("$score")
  done <<< "$decisions"

  if [ "${#rows[@]}" -eq 0 ]; then
    echo "| _(No decisions yet)_ | | |"
  else
    for row in "${rows[@]}"; do
      echo "$row"
    done
  fi
}

EXISTING_TODOS=""
EXISTING_DECISIONS=""
EXISTING_BLOCKERS=""
EXISTING_CODEBASE=""
if [[ -f "$OUTPUT_PATH" ]]; then
  EXISTING_TODOS=$(extract_todos_section "$OUTPUT_PATH")
  EXISTING_DECISIONS=$(awk '
    { low = tolower($0) }
    low ~ /^##[[:space:]]+(key )?decisions[[:space:]]*$/ { found=1; next }
    found && /^##[[:space:]]/ { found=0 }
    found && low ~ /^###[[:space:]]+pending[[:space:]]+todos[[:space:]]*$/ { found=0; skip_skills=0; next }
    found && low ~ /^###[[:space:]]+skills[[:space:]]*$/ { skip_skills=1; next }
    skip_skills && /^###?#? / { skip_skills=0 }
    found && !skip_skills { print }
  ' "$OUTPUT_PATH")
  EXISTING_BLOCKERS=$(extract_section "$OUTPUT_PATH" "Blockers")
  EXISTING_CODEBASE=$(extract_section "$OUTPUT_PATH" "Codebase Profile")
  if [[ -n "$EXISTING_CODEBASE" ]] && ! printf '%s\n' "$EXISTING_CODEBASE" | grep -Eqv '^[[:space:]]*(None\.?)?[[:space:]]*$'; then
    EXISTING_CODEBASE=""
  fi
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

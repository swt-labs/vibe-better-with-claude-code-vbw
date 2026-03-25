#!/usr/bin/env bash
set -euo pipefail

# unarchive-milestone.sh — Restore an archived milestone to active work
#
# Usage: unarchive-milestone.sh MILESTONE_DIR PLANNING_DIR
#
# Moves phases/, ROADMAP.md, STATE.md back to root PLANNING_DIR.
# Merges Todos and Decisions sections from both root and archived STATE.md,
# deduplicating by normalized text comparison.
# Deletes SHIPPED.md and removes the milestone dir if empty.
#
# Exit codes: 0 on success, 1 on failure

MILESTONE_DIR="${1:-}"
PLANNING_DIR="${2:-}"

if [[ -z "$MILESTONE_DIR" || -z "$PLANNING_DIR" ]]; then
  echo "Usage: unarchive-milestone.sh MILESTONE_DIR PLANNING_DIR" >&2
  exit 1
fi

if [[ ! -d "$MILESTONE_DIR" ]]; then
  echo "Error: milestone directory not found: $MILESTONE_DIR" >&2
  exit 1
fi

# --- Extract todos from STATE.md ---
# Supports current/legacy headings: "## Todos" and "### Pending Todos"
extract_todo_items() {
  local file="$1"
  [ -f "$file" ] || return 0
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

      if (found && /^[-*] /) {
        print
      }
    }
  ' "$file"
}

# --- Extract decisions from STATE.md ---
# Supports current/legacy headings: "## Key Decisions" and "## Decisions"
extract_decision_items() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk '
    {
      low = tolower($0)

      if (low ~ /^##[[:space:]]+(key[[:space:]]+)?decisions[[:space:]]*$/) {
        found=1
        next
      }

      if (found && /^## /) {
        found=0
      }

      if (!found) {
        next
      }

      if (/^[-*] /) {
        print
        next
      }

      if (/^\|/) {
        # Skip markdown separators and common table header row
        if (low ~ /^\|[[:space:]:-]+\|?[[:space:]]*$/) {
          next
        }
        if (low ~ /^\|[[:space:]]*decision([[:space:]]*\|.*)?$/) {
          next
        }
        print
      }
    }
  ' "$file"
}

# --- Normalize todo item for dedup comparison ---
normalize_todo_item() {
  printf '%s\n' "$1" | \
    sed -E 's/^[-*][[:space:]]+//' | \
    sed -E 's/^\[[^]]+\][[:space:]]*//' | \
    sed -E 's/[[:space:]]*\(added[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}\)$//' | \
    sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g' | \
    tr '[:upper:]' '[:lower:]'
}

# --- Normalize decision item for dedup comparison ---
# For table rows, dedup by the decision text (first column) only.
normalize_decision_item() {
  local line="$1"

  if [[ "$line" =~ ^\| ]]; then
    line=$(printf '%s\n' "$line" | sed 's/^|//' | awk -F'|' '{print $1}')
  else
    line=$(printf '%s\n' "$line" | sed -E 's/^[-*][[:space:]]+//')
  fi

  printf '%s\n' "$line" | \
    sed -E 's/\*\*//g' | \
    sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g' | \
    tr '[:upper:]' '[:lower:]'
}

# --- Merge two sets of items with dedup ---
# Usage: merge_items KIND "items1_multiline" "items2_multiline"
# Returns deduplicated union
merge_items() {
  local kind="$1" items1="$2" items2="$3"
  local -a seen_normalized=()
  local -a result=()

  # Process items1 first (keep original formatting)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" == "None." ]] && continue
    local norm
    if [[ "$kind" == "decisions" ]]; then
      norm=$(normalize_decision_item "$line")
    else
      norm=$(normalize_todo_item "$line")
    fi
    [ -z "$norm" ] && continue

    local found=false
    for s in "${seen_normalized[@]+"${seen_normalized[@]}"}"; do
      if [[ "$s" == "$norm" ]]; then
        found=true
        break
      fi
    done
    if [[ "$found" == false ]]; then
      seen_normalized+=("$norm")
      result+=("$line")
    fi
  done <<< "$items1"

  # Process items2 (add only unseen)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" == "None." ]] && continue
    local norm
    if [[ "$kind" == "decisions" ]]; then
      norm=$(normalize_decision_item "$line")
    else
      norm=$(normalize_todo_item "$line")
    fi
    [ -z "$norm" ] && continue

    local found=false
    for s in "${seen_normalized[@]+"${seen_normalized[@]}"}"; do
      if [[ "$s" == "$norm" ]]; then
        found=true
        break
      fi
    done
    if [[ "$found" == false ]]; then
      seen_normalized+=("$norm")
      result+=("$line")
    fi
  done <<< "$items2"

  for item in "${result[@]+"${result[@]}"}"; do
    echo "$item"
  done
}

# --- Replace or append a section in a file with normalized heading matching ---
# Usage: replace_or_append_section FILE KIND CANONICAL_HEADER NEW_CONTENT
# KIND: "todos" or "decisions"
replace_or_append_section() {
  local file="$1" kind="$2" canonical_header="$3" new_content="$4"
  local tmp="${file}.tmp.$$"
  local content_file="${file}.content.$$"

  printf '%s\n' "$new_content" > "$content_file"

  awk -v kind="$kind" -v canonical="$canonical_header" -v cfile="$content_file" '
    function is_decision_heading(line, low) {
      low = tolower(line)
      return (low ~ /^##[[:space:]]+(key[[:space:]]+)?decisions[[:space:]]*$/)
    }

    function is_todo_heading(line, low) {
      low = tolower(line)
      return (low ~ /^##[[:space:]]+todos[[:space:]]*$/)
    }

    function is_pending_todos_heading(line, low) {
      low = tolower(line)
      return (low ~ /^###[[:space:]]+pending[[:space:]]+todos[[:space:]]*$/)
    }

    function is_target_heading(line) {
      if (kind == "decisions") {
        return is_decision_heading(line)
      }
      return (is_todo_heading(line) || is_pending_todos_heading(line))
    }

    function start_skip_mode(line) {
      if (kind == "todos" && is_pending_todos_heading(line)) {
        return "h3"
      }
      return "h2"
    }

    function skip_should_end(mode, line) {
      if (mode == "h3") {
        return (line ~ /^## / || line ~ /^### /)
      }
      return (line ~ /^## /)
    }

    function print_canonical_section(ln) {
      print canonical
      while ((getline ln < cfile) > 0) {
        print ln
      }
      close(cfile)
    }

    {
      line = $0

      if (skip && skip_should_end(skip_mode, line)) {
        skip = 0
        skip_mode = ""
      }

      if (skip) {
        next
      }

      if (is_target_heading(line)) {
        if (!inserted) {
          print_canonical_section()
          inserted = 1
          printed_any = 1
          last_nonempty = 1
        }
        skip = 1
        skip_mode = start_skip_mode(line)
        next
      }

      print line
      printed_any = 1
      last_nonempty = (line !~ /^[[:space:]]*$/)
    }

    END {
      if (!inserted) {
        if (printed_any && last_nonempty) {
          print ""
        }
        print_canonical_section()
      }
    }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
  rm -f "$content_file"
}

ROOT_STATE="$PLANNING_DIR/STATE.md"
ARCHIVED_STATE="$MILESTONE_DIR/STATE.md"

# --- Merge Todos and Decisions ---
root_todos=""
archived_todos=""
root_decisions=""
archived_decisions=""

if [ -f "$ROOT_STATE" ]; then
  root_todos=$(extract_todo_items "$ROOT_STATE")
  root_decisions=$(extract_decision_items "$ROOT_STATE")
fi

if [ -f "$ARCHIVED_STATE" ]; then
  archived_todos=$(extract_todo_items "$ARCHIVED_STATE")
  archived_decisions=$(extract_decision_items "$ARCHIVED_STATE")
fi

merged_todos=$(merge_items "todos" "$archived_todos" "$root_todos")
merged_decisions=$(merge_items "decisions" "$archived_decisions" "$root_decisions")

# --- Move files back to root ---
# Move phases
if [ -d "$MILESTONE_DIR/phases" ]; then
  if [ -d "$PLANNING_DIR/phases" ]; then
    # Abort if root phases/ contains any files (active work would be destroyed)
    if [ -n "$(find "$PLANNING_DIR/phases" -type f 2>/dev/null)" ]; then
      echo "Error: root phases/ directory contains files — aborting to prevent data loss" >&2
      echo "  Back up or remove $PLANNING_DIR/phases/ before unarchiving." >&2
      exit 1
    fi
    rm -rf "$PLANNING_DIR/phases"
  fi
  mv "$MILESTONE_DIR/phases" "$PLANNING_DIR/phases"
fi

# Move ROADMAP.md
if [ -f "$MILESTONE_DIR/ROADMAP.md" ]; then
  mv "$MILESTONE_DIR/ROADMAP.md" "$PLANNING_DIR/ROADMAP.md"
fi

# Move milestone CONTEXT.md (scope decisions)
if [ -f "$MILESTONE_DIR/CONTEXT.md" ]; then
  mv "$MILESTONE_DIR/CONTEXT.md" "$PLANNING_DIR/CONTEXT.md"
fi

# Move STATE.md (archived version is the base)
if [ -f "$ARCHIVED_STATE" ]; then
  mv "$ARCHIVED_STATE" "$ROOT_STATE"
fi

# --- Write merged sections into restored STATE.md ---
if [ -f "$ROOT_STATE" ]; then
  if [ -n "$merged_todos" ]; then
    replace_or_append_section "$ROOT_STATE" "todos" "## Todos" "$merged_todos"
  fi
  if [ -n "$merged_decisions" ]; then
    replace_or_append_section "$ROOT_STATE" "decisions" "## Key Decisions" "$merged_decisions"
  fi
fi

# --- Clean up milestone dir ---
rm -f "$MILESTONE_DIR/SHIPPED.md" 2>/dev/null || true

# Remove milestone dir if empty (or only has empty subdirs)
find "$MILESTONE_DIR" -type d -empty -delete 2>/dev/null || true
if [ -d "$MILESTONE_DIR" ]; then
  # Check if truly empty (no files remaining)
  if [ -z "$(find "$MILESTONE_DIR" -type f 2>/dev/null)" ]; then
    rm -rf "$MILESTONE_DIR"
  fi
fi

exit 0

#!/usr/bin/env bash
set -euo pipefail

# bootstrap-claude.sh — Generate or update CLAUDE.md with VBW sections
#
# Usage:
#   bootstrap-claude.sh OUTPUT_PATH PROJECT_NAME CORE_VALUE [EXISTING_PATH]
#     OUTPUT_PATH    Path to write CLAUDE.md
#     PROJECT_NAME   Name of the project
#     CORE_VALUE     One-line core value statement
#     EXISTING_PATH  (Optional) Path to existing CLAUDE.md to preserve non-VBW content
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../lib/claude-md-vbw-sections.sh"

if [[ ! -f "$LIB" ]]; then
  echo "Error: helper library not found at $LIB" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$LIB"


# VBW-managed section headers (order matters for generation)
VBW_SECTIONS=("${VBW_CANONICAL_HEADERS[@]}")

# Formerly VBW-managed sections — still stripped during brownfield regeneration
# to clean up stale content from existing CLAUDE.md files.
VBW_DEPRECATED_SECTIONS=(
  "## Key Decisions"  # Removed: tracked in .vbw-planning/PROJECT.md and STATE.md
  "## Installed Skills"  # Removed: skills surfaced through runtime activation pipeline
)

# Strong GSD-managed section headers (always stripped when present)
GSD_STRONG_SECTIONS=(
  "## Codebase Intelligence"
  "## Project Reference"
  "## GSD Rules"
  "## GSD Context"
)

# Soft GSD headers are only stripped when strong GSD headers are detected.
# This avoids removing legitimate user sections like "## Context" in non-GSD files.
GSD_SOFT_SECTIONS=(
  "## What This Is"
  "## Core Value"
  "## Context"
  "## Constraints"
)

if [[ $# -lt 3 ]]; then
  echo "Usage: bootstrap-claude.sh OUTPUT_PATH PROJECT_NAME CORE_VALUE [EXISTING_PATH]" >&2
  exit 1
fi

OUTPUT_PATH="$1"
PROJECT_NAME="$2"
CORE_VALUE="$3"
EXISTING_PATH="${4:-}"

if [[ -z "$PROJECT_NAME" || -z "$CORE_VALUE" ]]; then
  echo "Error: PROJECT_NAME and CORE_VALUE must not be empty" >&2
  exit 1
fi

# Ensure parent directory exists
mkdir -p "$(dirname "$OUTPUT_PATH")"

# Generate VBW-managed content
# Brownfield mode may suppress individual sections when an existing file already
# has that guidance under a different heading/title. Exact canonical sections
# are refreshed; custom variants are preserved and not duplicated.
INCLUDE_ACTIVE_CONTEXT=true
INCLUDE_VBW_RULES=true
INCLUDE_CODE_INTELLIGENCE=true
INCLUDE_PLUGIN_ISOLATION=true

generate_vbw_sections() {
  local emitted=false

  if [[ "$INCLUDE_ACTIVE_CONTEXT" == true ]]; then
    vbw_generate_active_context_section
    emitted=true
  fi

  if [[ "$INCLUDE_VBW_RULES" == true ]]; then
    if [[ "$emitted" == true ]]; then echo ""; fi
    vbw_generate_vbw_rules_section
    emitted=true
  fi

  if [[ "$INCLUDE_CODE_INTELLIGENCE" == true ]]; then
    if [[ "$emitted" == true ]]; then echo ""; fi
    vbw_generate_code_intelligence_section
    emitted=true
  fi

  if [[ "$INCLUDE_PLUGIN_ISOLATION" == true ]]; then
    if [[ "$emitted" == true ]]; then echo ""; fi
    vbw_generate_plugin_isolation_section
  fi
}

# Check if a line is a VBW-managed section header
is_vbw_section() {
  local line="$1"
  for header in "${VBW_SECTIONS[@]}"; do
    if [[ "$line" == "$header" ]]; then
      return 0
    fi
  done
  return 1
}

# Check if a line is a GSD-managed section header (stripped to prevent insight leakage)
is_gsd_section() {
  local line="$1"
  for header in "${GSD_STRONG_SECTIONS[@]}"; do
    if [[ "$line" == "$header" ]]; then
      return 0
    fi
  done

  if [[ "${ALLOW_SOFT_GSD_STRIP:-false}" == "true" ]]; then
    for header in "${GSD_SOFT_SECTIONS[@]}"; do
      if [[ "$line" == "$header" ]]; then
        return 0
      fi
    done
  fi

  return 1
}

# Check if a line is a deprecated VBW section header (stripped but not regenerated)
is_deprecated_vbw_section() {
  local line="$1"
  for header in "${VBW_DEPRECATED_SECTIONS[@]}"; do
    if [[ "$line" == "$header" ]]; then
      return 0
    fi
  done
  return 1
}

# Check if a line is a managed section header (VBW, deprecated VBW, or GSD — all get stripped)
is_managed_section() {
  is_vbw_section "$1" || is_deprecated_vbw_section "$1" || is_gsd_section "$1"
}

# If existing file provided and it exists, preserve non-managed content
if [[ -n "$EXISTING_PATH" && -f "$EXISTING_PATH" ]]; then
  # Enable soft GSD stripping only when file shows strong GSD fingerprint.
  ALLOW_SOFT_GSD_STRIP=false
  if grep -Eq '^## (Codebase Intelligence|Project Reference|GSD Rules|GSD Context)$' "$EXISTING_PATH"; then
    ALLOW_SOFT_GSD_STRIP=true
  fi

  # Extract sections that are NOT managed by VBW or GSD
  NON_VBW_CONTENT=""
  IN_MANAGED_SECTION=false
  FOUND_NON_VBW=false
  IN_DEPRECATED_SECTION=false
  DEPRECATED_SECTION_BUFFER=""
  DEPRECATED_HAS_USER_CONTENT=false

  # Migrate data rows from a deprecated Key Decisions table to STATE.md.
  # Appends any non-header, non-separator, non-placeholder table rows.
  # Deduplicates against rows already present in STATE.md.
  migrate_key_decisions_to_state() {
    local buffer="$1"
    local state_path
    state_path="$(dirname "$OUTPUT_PATH")/.vbw-planning/STATE.md"

    # Extract data rows: lines starting with | that aren't the header, separator, or placeholder
    local data_rows=""
    local row_count=0
    while IFS= read -r row; do
      # Skip header row, separator row, and placeholder row
      [[ "$row" =~ ^\|\ *Decision ]] && continue
      [[ "$row" =~ ^\|[-[:space:]|]+\|$ ]] && continue
      [[ "$row" =~ _\(No\ decisions\ yet\)_ ]] && continue
      # Must be a table data row (starts with |)
      [[ "$row" =~ ^\| ]] || continue
      data_rows+="${row}"$'\n'
      row_count=$((row_count + 1))
    done <<< "$buffer"

    if [[ $row_count -eq 0 ]]; then
      return 0
    fi

    # Only migrate if STATE.md exists and has a Key Decisions section.
    # Return 1 to signal the caller should preserve the section as user-owned.
    if [[ ! -f "$state_path" ]]; then
      echo "Warning: Cannot migrate $row_count Key Decisions row(s) — STATE.md not found at $state_path" >&2
      return 1
    fi

    if ! grep -q '^## Key Decisions' "$state_path"; then
      echo "Warning: Cannot migrate $row_count Key Decisions row(s) — no ## Key Decisions section in STATE.md" >&2
      return 1
    fi

    # Deduplicate: remove rows that already exist in STATE.md
    local unique_rows=""
    local unique_count=0
    while IFS= read -r drow; do
      [[ -z "$drow" ]] && continue
      # Normalize whitespace for comparison (handles minor spacing differences)
      if ! tr -s ' ' < "$state_path" | grep -qF "$(printf '%s' "$drow" | tr -s ' ')"; then
        unique_rows+="${drow}"$'\n'
        unique_count=$((unique_count + 1))
      fi
    done <<< "$data_rows"

    if [[ $unique_count -eq 0 ]]; then
      echo "Skipped migration — all $row_count Key Decisions row(s) already in STATE.md" >&2
      return 0
    fi

    # Remove placeholder row if present, skip blank lines between table rows
    # and next section, then append unique data rows after the separator.
    local tmp_state
    tmp_state="$(mktemp)"
    trap 'rm -f "${tmp_state:-}"' RETURN
    local in_kd_section=false
    local past_separator=false
    local rows_inserted=false

    while IFS= read -r sline || [[ -n "$sline" ]]; do
      if [[ "$sline" == "## Key Decisions" ]]; then
        in_kd_section=true
        past_separator=false
        rows_inserted=false
        echo "$sline" >> "$tmp_state"
        continue
      fi
      # Detect next section — insert migrated rows, then blank line, then header
      if [[ "$in_kd_section" == true && "$sline" =~ ^##\  ]]; then
        if [[ "$past_separator" == true && "$rows_inserted" == false ]]; then
          printf '%s' "$unique_rows" >> "$tmp_state"
          rows_inserted=true
        fi
        echo "" >> "$tmp_state"
        in_kd_section=false
        echo "$sline" >> "$tmp_state"
        continue
      fi
      if [[ "$in_kd_section" == true ]]; then
        # Detect separator row
        if [[ "$sline" =~ ^\|[-[:space:]|]+\|$ && ! "$sline" =~ ^\|\ *Decision ]]; then
          past_separator=true
          echo "$sline" >> "$tmp_state"
          continue
        fi
        # Skip placeholder row
        if [[ "$sline" =~ _\(No\ decisions\ yet\)_ ]]; then
          continue
        fi
        # Skip blank lines after separator (before data rows or next section)
        if [[ "$past_separator" == true && -z "$sline" ]]; then
          continue
        fi
        echo "$sline" >> "$tmp_state"
      else
        echo "$sline" >> "$tmp_state"
      fi
    done < "$state_path"

    # If Key Decisions was the last section (no next ## header), append rows at EOF
    if [[ "$in_kd_section" == true && "$past_separator" == true && "$rows_inserted" == false ]]; then
      printf '%s' "$unique_rows" >> "$tmp_state"
      rows_inserted=true
    fi

    # Guard: if no separator was found, the Key Decisions section has no table.
    # Abort migration to avoid data loss — caller will preserve the section.
    if [[ "$past_separator" == false ]]; then
      rm -f "$tmp_state"
      echo "Warning: Cannot migrate $unique_count Key Decisions row(s) — STATE.md Key Decisions section has no table" >&2
      return 1
    fi

    mv "$tmp_state" "$state_path"
    echo "Migrated $unique_count Key Decisions row(s) from CLAUDE.md to STATE.md" >&2
  }

  # Flush a buffered deprecated section.
  # - Strips the ## header and the markdown table (header/separator/data rows)
  # - Migrates table data rows to STATE.md
  # - Preserves any non-table content (free text, lists, etc.) as user-owned
  flush_deprecated_buffer() {
    if [[ "$IN_DEPRECATED_SECTION" == true ]]; then
      if [[ "$DEPRECATED_HAS_USER_CONTENT" == true ]]; then
        if ! migrate_key_decisions_to_state "$DEPRECATED_SECTION_BUFFER"; then
          # Migration target unavailable — preserve entire section as user-owned
          NON_VBW_CONTENT+="${DEPRECATED_SECTION_BUFFER}"
          FOUND_NON_VBW=true
          IN_DEPRECATED_SECTION=false
          DEPRECATED_SECTION_BUFFER=""
          DEPRECATED_HAS_USER_CONTENT=false
          return
        fi
      fi

      # Extract non-table, non-header lines and preserve as user content
      local preserved=""
      local section_label=""
      local first_line=true
      while IFS= read -r bline; do
        # Capture the ## header label for archived heading, then skip it
        if [[ "$first_line" == true ]]; then
          first_line=false
          section_label="${bline#\#\# }"
          continue
        fi
        # Skip table rows: header, separator, and data rows
        [[ "$bline" =~ ^\|\ *Decision ]] && continue
        [[ "$bline" =~ ^\|[-[:space:]|]+\|$ ]] && continue
        [[ "$bline" =~ ^\| ]] && continue
        preserved+="${bline}"$'\n'
      done <<< "$DEPRECATED_SECTION_BUFFER"

      # If there's non-blank content left, emit it as user-owned
      # Strip leading/trailing blank lines to avoid cosmetic blanks
      if [[ -n "${preserved//[[:space:]]/}" ]]; then
        preserved="$(echo "$preserved" | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
        # Wrap orphaned text under an archived heading so it isn't headingless
        NON_VBW_CONTENT+="## ${section_label} (Archived Notes)"$'\n'$'\n'"${preserved}"$'\n'$'\n'
        FOUND_NON_VBW=true
      fi

      # Reset state
      IN_DEPRECATED_SECTION=false
      DEPRECATED_SECTION_BUFFER=""
      DEPRECATED_HAS_USER_CONTENT=false
    fi
  }

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim trailing whitespace for reliable header matching
    line="${line%"${line##*[![:space:]]}"}"

    # Check if this line starts a VBW or GSD managed section
    if is_managed_section "$line"; then
      flush_deprecated_buffer
      # Start tracking deprecated sections via buffer
      if is_deprecated_vbw_section "$line"; then
        IN_DEPRECATED_SECTION=true
        DEPRECATED_SECTION_BUFFER="${line}"$'\n'
        DEPRECATED_HAS_USER_CONTENT=false
      fi
      IN_MANAGED_SECTION=true
      continue
    fi

    # Check if this line starts a new non-managed section (any ## header not in either list)
    if [[ "$line" =~ ^##\  ]] && ! is_managed_section "$line"; then
      flush_deprecated_buffer
      IN_MANAGED_SECTION=false
    fi

    # Buffer lines in deprecated sections and detect user content
    if [[ "$IN_DEPRECATED_SECTION" == true ]]; then
      DEPRECATED_SECTION_BUFFER+="${line}"$'\n'
      # Lines that are NOT part of the empty template: anything beyond
      # blank lines, the table header row, and the separator row
      if [[ -n "$line" && ! "$line" =~ ^\|[-[:space:]|]+\|$ && ! "$line" =~ ^\|\ *Decision ]]; then
        DEPRECATED_HAS_USER_CONTENT=true
      fi
      continue
    fi

    if [[ "$IN_MANAGED_SECTION" == false ]]; then
      NON_VBW_CONTENT+="${line}"$'\n'
      FOUND_NON_VBW=true
    fi
  done < "$EXISTING_PATH"

  # Final check: flush any buffered deprecated section at EOF
  flush_deprecated_buffer

  if vbw_should_emit_managed_section "$EXISTING_PATH" "Active Context" "## Active Context"; then
    INCLUDE_ACTIVE_CONTEXT=true
  else
    INCLUDE_ACTIVE_CONTEXT=false
  fi

  if vbw_should_emit_managed_section "$EXISTING_PATH" "VBW Rules" "## VBW Rules"; then
    INCLUDE_VBW_RULES=true
  else
    INCLUDE_VBW_RULES=false
  fi

  if vbw_should_emit_code_intelligence_section "$EXISTING_PATH"; then
    INCLUDE_CODE_INTELLIGENCE=true
  else
    INCLUDE_CODE_INTELLIGENCE=false
  fi

  if vbw_should_emit_managed_section "$EXISTING_PATH" "Plugin Isolation" "## Plugin Isolation"; then
    INCLUDE_PLUGIN_ISOLATION=true
  else
    INCLUDE_PLUGIN_ISOLATION=false
  fi

  # Write: preserved content + refreshed/appended VBW sections.
  {
    if [[ "$FOUND_NON_VBW" == true ]]; then
      # Trim leading/trailing blank lines from preserved content
      echo "$NON_VBW_CONTENT" | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
      if [[ "$INCLUDE_ACTIVE_CONTEXT" == true || "$INCLUDE_VBW_RULES" == true || "$INCLUDE_CODE_INTELLIGENCE" == true || "$INCLUDE_PLUGIN_ISOLATION" == true ]]; then
        echo ""
      fi
    fi
    generate_vbw_sections
  } > "$OUTPUT_PATH"
else
  # New file: generate fresh
  {
    echo "# ${PROJECT_NAME}"
    echo ""
    echo "**Core value:** ${CORE_VALUE}"
    echo ""
    generate_vbw_sections
  } > "$OUTPUT_PATH"
fi

exit 0

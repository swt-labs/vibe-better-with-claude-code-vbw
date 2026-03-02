#!/bin/bash
# emit-skill-xml.sh — Generate <available_skills> XML from installed skill directories
#
# Scans three skill directories (global, project, agents ecosystem), reads SKILL.md
# frontmatter, and outputs structured XML for session context injection.
#
# Usage: bash emit-skill-xml.sh [project-dir]
# Output: <available_skills> XML block, or empty string if no skills found.

set -eo pipefail

# Resolve project dir to absolute path so skill locations aren't relative
PROJECT_DIR="$(cd "${1:-.}" 2>/dev/null && pwd || echo "${1:-.}")"
# shellcheck source=resolve-claude-dir.sh
. "$(dirname "$0")/resolve-claude-dir.sh"

# --- XML-escape helper ---
xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}

# --- Collect skills from all three directories ---
# Dedup by folder name using a delimited string (bash 3.2 compat, no declare -A)
_SEEN_NAMES=""
SKILL_ENTRIES=""

_is_seen() {
  # Use newline delimiter to avoid false matches on folder names containing commas
  # Wrap in newlines for exact line matching (prevents substring false positives)
  local NL=$'\n'
  case "${NL}${_SEEN_NAMES}${NL}" in *"${NL}${1}${NL}"*) return 0 ;; esac
  return 1
}

_mark_seen() {
  _SEEN_NAMES="${_SEEN_NAMES:+${_SEEN_NAMES}
}$1"
}

scan_skill_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  for skill_dir in "$dir"/*/; do
    [ -d "$skill_dir" ] || continue
    local folder_name
    folder_name=$(basename "$skill_dir")

    # Dedup: skip if already seen (earlier dirs have priority)
    if _is_seen "$folder_name"; then
      continue
    fi
    _mark_seen "$folder_name"

    local skill_md="$skill_dir/SKILL.md"
    [ -f "$skill_md" ] || continue

    # Read first 30 lines for YAML frontmatter
    local head_content
    head_content=$(head -30 "$skill_md" 2>/dev/null | tr -d '\r' || true)

    # Extract name and description from within YAML frontmatter fences only
    local name="" description=""
    local frontmatter
    frontmatter=$(printf '%s\n' "$head_content" | awk '/^---$/{if(n++) exit; next} n{print}')

    name=$(printf '%s\n' "$frontmatter" | sed -n 's/^name:[[:space:]]*//p' | head -1)
    # Handle multiline YAML descriptions (indented continuation lines)
    local in_desc=false desc_lines=""
    while IFS= read -r _line; do
      if [ "$in_desc" = true ]; then
        case "$_line" in
          \ *|$'\t'*) desc_lines="${desc_lines} $(printf '%s' "$_line" | sed 's/^[[:space:]]*//')" ;;
          *) break ;;
        esac
      else
        case "$_line" in
          description:*) in_desc=true; desc_lines=$(printf '%s' "$_line" | sed 's/^description:[[:space:]]*//') ;;
        esac
      fi
    done <<< "$frontmatter"
    description="$desc_lines"

    # Strip surrounding quotes if present
    name=$(printf '%s' "$name" | sed 's/^["'\'']\(.*\)["'\''"]$/\1/')
    description=$(printf '%s' "$description" | sed 's/^["'\'']\(.*\)["'\''"]$/\1/')

    # Fallbacks
    [ -z "$name" ] && name="$folder_name"
    [ -z "$description" ] && description="No description available"

    # XML-escape values
    local esc_name esc_desc esc_loc
    esc_name=$(xml_escape "$name")
    esc_desc=$(xml_escape "$description")
    esc_loc=$(xml_escape "$skill_md")

    SKILL_ENTRIES="${SKILL_ENTRIES}  <skill>
    <name>${esc_name}</name>
    <description>${esc_desc}</description>
    <location>${esc_loc}</location>
  </skill>
"
  done
}

# Project skills first (highest priority for dedup)
scan_skill_dir "$PROJECT_DIR/.claude/skills"
# Global skills second
scan_skill_dir "$CLAUDE_DIR/skills"
# Agents ecosystem last
scan_skill_dir "$HOME/.agents/skills"

# --- Output ---
if [ -z "$SKILL_ENTRIES" ]; then
  # No skills found: output nothing
  exit 0
fi

printf '<available_skills>\n%s</available_skills>' "$SKILL_ENTRIES"

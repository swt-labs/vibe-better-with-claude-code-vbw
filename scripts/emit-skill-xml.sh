#!/bin/bash
# emit-skill-xml.sh — Generate <available_skills> XML from installed skill directories
#
# Scans three skill directories (global, project, agents ecosystem), reads SKILL.md
# frontmatter, and outputs structured XML for session context injection.
#
# Usage: bash emit-skill-xml.sh [project-dir]
# Output: <available_skills> XML block, or empty string if no skills found.

set -eo pipefail

PROJECT_DIR="${1:-.}"
# shellcheck source=resolve-claude-dir.sh
. "$(dirname "$0")/resolve-claude-dir.sh"

# --- XML-escape helper ---
xml_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  printf '%s' "$s"
}

# --- Collect skills from all three directories ---
declare -A SEEN_SKILLS  # dedup by folder name (project wins)
SKILL_ENTRIES=""

scan_skill_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  for skill_dir in "$dir"/*/; do
    [ -d "$skill_dir" ] || continue
    local folder_name
    folder_name=$(basename "$skill_dir")

    # Dedup: skip if already seen (earlier dirs have priority)
    if [ -n "${SEEN_SKILLS[$folder_name]+x}" ]; then
      continue
    fi
    SEEN_SKILLS[$folder_name]=1

    local skill_md="$skill_dir/SKILL.md"
    [ -f "$skill_md" ] || continue

    # Read first 30 lines for YAML frontmatter
    local head_content
    head_content=$(head -30 "$skill_md" 2>/dev/null || true)

    # Extract name and description from YAML frontmatter
    local name="" description=""
    name=$(printf '%s\n' "$head_content" | sed -n 's/^name:[[:space:]]*//p' | head -1)
    description=$(printf '%s\n' "$head_content" | sed -n 's/^description:[[:space:]]*//p' | head -1)

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

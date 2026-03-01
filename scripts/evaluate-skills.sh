#!/usr/bin/env bash
# evaluate-skills.sh — Forced skill evaluation for compile-context.sh
#
# Reads installed skill names from STATE.md, locates each skill's SKILL.md on disk,
# extracts the description from YAML frontmatter, and outputs tab-separated pairs.
# This enables description-based skill matching (Fix 2 from dev.to article) instead
# of name-only matching which causes false positives.
#
# Usage: bash evaluate-skills.sh <planning-dir> [project-dir]
# Output: name\tdescription (one per line, to stdout)
# Exit: always 0 (skill evaluation failure must not block context compilation)
#
# Search paths for SKILL.md (same order as detect-stack.sh):
#   1. $CLAUDE_DIR/skills/{name}/SKILL.md   (global Claude config)
#   2. {project}/.claude/skills/{name}/SKILL.md (project-scoped)
#   3. $HOME/.agents/skills/{name}/SKILL.md  (npx skills add -g)

set -eo pipefail

PLANNING_DIR="${1:-.vbw-planning}"
PROJECT_DIR="${2:-.}"

# Source CLAUDE_DIR resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/resolve-claude-dir.sh" ]; then
  # shellcheck source=resolve-claude-dir.sh
  . "$SCRIPT_DIR/resolve-claude-dir.sh"
else
  CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
fi

# --- Parse installed skill names from STATE.md ---
STATE_FILE="$PLANNING_DIR/STATE.md"
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Extract the **Installed:** line from ### Skills section
INSTALLED_LINE=$(sed -n '/^### Skills$/,/^### \|^## /p' "$STATE_FILE" | grep '^\*\*Installed:\*\*' | head -1 || true)
if [ -z "$INSTALLED_LINE" ]; then
  exit 0
fi

# Strip prefix: "**Installed:** name1, name2" → "name1, name2"
NAMES_CSV=$(echo "$INSTALLED_LINE" | sed 's/^\*\*Installed:\*\* *//')

# Handle "None detected" / "None" / empty
case "$NAMES_CSV" in
  "None detected"|"None"|""|"none")
    exit 0
    ;;
esac

# --- Extract description from a SKILL.md file's YAML frontmatter ---
extract_description() {
  local skill_file="$1"
  if [ ! -f "$skill_file" ]; then
    echo "(not found on disk)"
    return
  fi

  # Read YAML frontmatter between first two --- lines
  local in_frontmatter=false
  local found_desc=false
  local description=""

  while IFS= read -r line; do
    if [ "$in_frontmatter" = false ]; then
      if [ "$line" = "---" ]; then
        in_frontmatter=true
      fi
      continue
    fi

    # End of frontmatter
    if [ "$line" = "---" ]; then
      break
    fi

    # Match "description: ..." line
    if [ "$found_desc" = false ]; then
      case "$line" in
        description:*)
          found_desc=true
          # Extract value after "description:" — handle both inline and multi-line
          local value
          value=$(echo "$line" | sed 's/^description: *//')
          if [ -n "$value" ]; then
            description="$value"
          fi
          ;;
      esac
    else
      # Continuation line: starts with 2+ spaces (YAML multi-line)
      case "$line" in
        "  "*)
          local trimmed
          trimmed=$(echo "$line" | sed 's/^  *//')
          if [ -n "$description" ]; then
            description="$description $trimmed"
          else
            description="$trimmed"
          fi
          ;;
        *)
          # Not a continuation — stop collecting
          break
          ;;
      esac
    fi
  done < "$skill_file"

  if [ -n "$description" ]; then
    echo "$description"
  else
    echo "(no description)"
  fi
}

# --- Locate SKILL.md and extract description for each skill ---
# Split comma-separated names, trim whitespace
echo "$NAMES_CSV" | tr ',' '\n' | while IFS= read -r raw_name; do
  # Trim leading/trailing whitespace
  name=$(echo "$raw_name" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  [ -z "$name" ] && continue

  # Search in 3 locations (same priority as detect-stack.sh)
  skill_file=""
  if [ -f "$CLAUDE_DIR/skills/$name/SKILL.md" ]; then
    skill_file="$CLAUDE_DIR/skills/$name/SKILL.md"
  elif [ -f "$PROJECT_DIR/.claude/skills/$name/SKILL.md" ]; then
    skill_file="$PROJECT_DIR/.claude/skills/$name/SKILL.md"
  elif [ -f "$HOME/.agents/skills/$name/SKILL.md" ]; then
    skill_file="$HOME/.agents/skills/$name/SKILL.md"
  fi

  if [ -n "$skill_file" ]; then
    desc=$(extract_description "$skill_file")
  else
    desc="(not found on disk)"
  fi

  printf '%s\t%s\n' "$name" "$desc"
done

exit 0

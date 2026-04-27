#!/bin/bash
# detect-stack.sh — Detect project tech stack and recommend skills
# Called by /vbw:init Step 3 and /vbw:skills to avoid 50+ inline tool calls.
# Reads stack-mappings.json, checks project files, outputs JSON.
#
# Usage: bash detect-stack.sh [project-dir]
# Output: JSON object with detected stack, installed skills, and suggestions.

set -eo pipefail

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

PROJECT_DIR="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAPPINGS="$SCRIPT_DIR/../config/stack-mappings.json"

if [ ! -f "$MAPPINGS" ]; then
  echo '{"error":"stack-mappings.json not found"}' >&2
  exit 1
fi

# --- Collect installed skills ---
INSTALLED_GLOBAL=""
INSTALLED_PROJECT=""
# shellcheck source=resolve-claude-dir.sh
. "$(dirname "$0")/resolve-claude-dir.sh"
if [ -d "$CLAUDE_DIR/skills" ]; then
  INSTALLED_GLOBAL=$(ls -1 "$CLAUDE_DIR/skills/" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
fi
if [ -d "$PROJECT_DIR/.claude/skills" ]; then
  INSTALLED_PROJECT=$(ls -1 "$PROJECT_DIR/.claude/skills/" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
fi
ALL_INSTALLED="$INSTALLED_GLOBAL,$INSTALLED_PROJECT"

# --- Read manifest files once ---
# Reads root manifest first, then appends subdirectory manifests (depth 2-3)
# for monorepo support. This catches dependencies in packages/*/package.json etc.
read_manifest() {
  local filename="$1"
  local content=""
  # Root manifest
  if [ -f "$PROJECT_DIR/$filename" ]; then
    content=$(cat "$PROJECT_DIR/$filename" 2>/dev/null)
  fi
  # Subdirectory manifests (monorepo patterns: packages/*, apps/*, src/*)
  while IFS= read -r subfile; do
    [ -z "$subfile" ] && continue
    content="$content"$'\n'"$(cat "$subfile" 2>/dev/null)"
  done < <(find "$PROJECT_DIR" -maxdepth 3 -name "$filename" \
    -not -path '*/node_modules/*' -not -path '*/.git/*' \
    -not -path '*/vendor/*' -not -path '*/target/*' \
    -not -path "$PROJECT_DIR/$filename" 2>/dev/null | head -10)
  echo "$content"
}

PKG_JSON=$(read_manifest "package.json")
REQUIREMENTS_TXT=$(read_manifest "requirements.txt")
PYPROJECT_TOML=$(read_manifest "pyproject.toml")
GEMFILE=$(read_manifest "Gemfile")
CARGO_TOML=$(read_manifest "Cargo.toml")
GO_MOD=$(read_manifest "go.mod")
COMPOSER_JSON=$(read_manifest "composer.json")
MIX_EXS=$(read_manifest "mix.exs")
POM_XML=$(read_manifest "pom.xml")
BUILD_GRADLE=$(read_manifest "build.gradle")

# --- Check a single detect pattern ---
# Returns 0 (true) if pattern matches, 1 (false) if not.
check_pattern() {
  local pattern="$1"

  if echo "$pattern" | grep -qF ':'; then
    # Dependency pattern: "file:dependency"
    local file dep content
    file=$(echo "$pattern" | cut -d: -f1)
    dep=$(echo "$pattern" | cut -d: -f2-)

    case "$file" in
      package.json)    content="$PKG_JSON" ;;
      requirements.txt) content="$REQUIREMENTS_TXT" ;;
      pyproject.toml)  content="$PYPROJECT_TOML" ;;
      Gemfile)         content="$GEMFILE" ;;
      Cargo.toml)      content="$CARGO_TOML" ;;
      go.mod)          content="$GO_MOD" ;;
      composer.json)   content="$COMPOSER_JSON" ;;
      mix.exs)         content="$MIX_EXS" ;;
      pom.xml)         content="$POM_XML" ;;
      build.gradle)    content="$BUILD_GRADLE" ;;
      *)               content="" ;;
    esac

    if [ -n "$content" ] && echo "$content" | grep -qF "\"$dep\""; then
      return 0
    fi
    # Fallback for non-JSON formats (requirements.txt, go.mod, Gemfile, etc.)
    # Skip for JSON files — quoted match above is sufficient and avoids false
    # positives (e.g., "react" word-matching inside "react-native").
    case "$file" in
      *.json) ;;
      *)
        if [ -n "$content" ] && echo "$content" | grep -qiw "$dep"; then
          return 0
        fi
        ;;
    esac
    return 1
  else
    # File/directory pattern
    if [ -e "$PROJECT_DIR/$pattern" ]; then
      return 0
    fi
    # Recursive detection: check subdirectories up to depth 4
    if find "$PROJECT_DIR" -maxdepth 4 -name "$(basename "$pattern")" -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' -print -quit 2>/dev/null | grep -q .; then
      return 0
    fi
    return 1
  fi
}

# --- Iterate stack-mappings.json and check all entries ---
# Uses jq to extract entries, then checks each detect pattern in bash.
DETECTED=""
RECOMMENDED_SKILLS=""

# Extract all entries as flat lines: category|name|description|skills_csv|detect_csv
ENTRIES=$(jq -r '
  to_entries[] |
  select(.key | startswith("_") | not) |
  .key as $cat |
  .value | to_entries[] |
  [$cat, .key, (.value.description // .key), (.value.skills | join(";")), (.value.detect | join(";"))] |
  join("|")
' "$MAPPINGS" 2>/dev/null)

while IFS='|' read -r _category name _description skills_csv detect_csv; do
  [ -z "$name" ] && continue

  # Check each detect pattern
  matched=false
  IFS=';' read -ra patterns <<< "$detect_csv"
  for pattern in "${patterns[@]}"; do
    if check_pattern "$pattern"; then
      matched=true
      break
    fi
  done

  if [ "$matched" = true ]; then
    # Add to detected list
    if [ -n "$DETECTED" ]; then
      DETECTED="$DETECTED,$name"
    else
      DETECTED="$name"
    fi

    # Add recommended skills
    IFS=';' read -ra skill_list <<< "$skills_csv"
    for skill in "${skill_list[@]}"; do
      if ! echo ",$RECOMMENDED_SKILLS," | grep -qF ",$skill,"; then
        if [ -n "$RECOMMENDED_SKILLS" ]; then
          RECOMMENDED_SKILLS="$RECOMMENDED_SKILLS,$skill"
        else
          RECOMMENDED_SKILLS="$skill"
        fi
      fi
    done
  fi
done <<< "$ENTRIES"

# --- Compute suggestions (recommended but not installed) ---
SUGGESTIONS=""
IFS=',' read -ra rec_arr <<< "$RECOMMENDED_SKILLS"
for skill in "${rec_arr[@]}"; do
  [ -z "$skill" ] && continue
  if ! echo ",$ALL_INSTALLED," | grep -qF ",$skill,"; then
    if [ -n "$SUGGESTIONS" ]; then
      SUGGESTIONS="$SUGGESTIONS,$skill"
    else
      SUGGESTIONS="$skill"
    fi
  fi
done

# --- Check find-skills availability ---
FIND_SKILLS="false"
if [ -d "$CLAUDE_DIR/skills/find-skills" ] || [ -d "$PROJECT_DIR/.claude/skills/find-skills" ]; then
  FIND_SKILLS="true"
fi

# --- Output JSON ---
jq -n \
  --arg detected "$DETECTED" \
  --arg installed_global "$INSTALLED_GLOBAL" \
  --arg installed_project "$INSTALLED_PROJECT" \
  --arg recommended "$RECOMMENDED_SKILLS" \
  --arg suggestions "$SUGGESTIONS" \
  --argjson find_skills "$FIND_SKILLS" \
  --arg global_skills_dir "$CLAUDE_DIR/skills" \
  '{
    detected_stack: ($detected | split(",") | map(select(. != ""))),
    installed: {
      global: ($installed_global | split(",") | map(select(. != ""))),
      project: ($installed_project | split(",") | map(select(. != "")))
    },
    recommended_skills: ($recommended | split(",") | map(select(. != ""))),
    suggestions: ($suggestions | split(",") | map(select(. != ""))),
    find_skills_available: $find_skills,
    global_skills_dir: $global_skills_dir
  }'

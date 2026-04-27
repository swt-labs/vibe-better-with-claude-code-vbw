#!/bin/bash
set -euo pipefail

# extract-skill-follow-up-files.sh — Resolve exact follow-up file paths from
# Claude Code-loaded skills so spawned payloads can pass deterministic paths
# instead of forcing agents to rediscover skill directories.

usage() {
  cat <<'EOF'
Usage: bash extract-skill-follow-up-files.sh [--project-dir PATH] <skill> [<skill> ...]

Emits a <skill_follow_up_files> block containing absolute file paths resolved
from markdown links inside each skill's SKILL.md file. Only project-local
.claude/skills and the global Claude config skills directory are searched.
EOF
}

PROJECT_DIR="."
SKILLS=()
NORMALIZED_SKILLS=()

valid_skill_name() {
  local skill="$1"

  case "$skill" in
    ""|.|..|*/*)
      return 1
      ;;
  esac

  return 0
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir)
      shift
      [ "$#" -gt 0 ] || {
        echo "extract-skill-follow-up-files.sh: --project-dir requires a value" >&2
        exit 1
      }
      PROJECT_DIR="$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        SKILLS+=("$1")
        shift
      done
      break
      ;;
    *)
      SKILLS+=("$1")
      ;;
  esac
  shift
done

[ "${#SKILLS[@]}" -gt 0 ] || exit 0

PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd -P)

for raw_skill in "${SKILLS[@]}"; do
  while IFS= read -r parsed_skill; do
    [ -n "$parsed_skill" ] || continue
    valid_skill_name "$parsed_skill" || continue
    NORMALIZED_SKILLS+=("$parsed_skill")
  done < <(printf '%s\n' "$raw_skill" | tr ',[:space:]' '\n\n' | sed '/^$/d')
done

[ "${#NORMALIZED_SKILLS[@]}" -gt 0 ] || exit 0
SKILLS=("${NORMALIZED_SKILLS[@]}")

# shellcheck source=resolve-claude-dir.sh
. "$(dirname "$0")/resolve-claude-dir.sh"

resolve_skill_dir() {
  local skill="$1"
  local candidate

  for candidate in \
    "$PROJECT_DIR/.claude/skills/$skill" \
    "$CLAUDE_DIR/skills/$skill"
  do
    if [ -f "$candidate/SKILL.md" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

normalize_path() {
  local path="$1"
  local dir base

  dir=$(dirname "$path")
  base=$(basename "$path")
  dir=$(cd "$dir" && pwd -P 2>/dev/null) || return 1
  printf '%s/%s\n' "$dir" "$base"
}

extract_markdown_targets() {
  local skill_md="$1"
  local markdown_links

  markdown_links=$(grep -oE '\[[^][]+\]\([^)]+\)' "$skill_md" 2>/dev/null || true)
  [ -n "$markdown_links" ] || return 0

  printf '%s\n' "$markdown_links" \
    | sed -E 's/^[^()]*\(([^)#]+)(#[^)]+)?\)$/\1/' \
    | while IFS= read -r target; do
        [ -n "$target" ] || continue
        case "$target" in
          \#*|http://*|https://*|mailto:*|/*)
            continue
            ;;
        esac
        printf '%s\n' "$target"
      done
}

BLOCK=""

for skill in "${SKILLS[@]}"; do
  skill_dir=$(resolve_skill_dir "$skill" 2>/dev/null) || continue
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue
  skill_dir_abs=$(normalize_path "$skill_dir") || continue

  skill_lines=""
  seen_paths=$'\n'

  while IFS= read -r rel_target; do
    [ -n "$rel_target" ] || continue
    resolved_path="$skill_dir/$rel_target"
    [ -f "$resolved_path" ] || continue
    [ ! -L "$resolved_path" ] || continue
    abs_path=$(normalize_path "$resolved_path") || continue
    [[ "$abs_path" == "$skill_dir_abs"/* ]] || continue

    case "$seen_paths" in
      *$'\n'"$abs_path"$'\n'*)
        continue
        ;;
    esac

    seen_paths="${seen_paths}${abs_path}"$'\n'
    skill_lines="${skill_lines}- ${abs_path}"$'\n'
  done < <(extract_markdown_targets "$skill_md")

  [ -n "$skill_lines" ] || continue

  [ -n "$BLOCK" ] || BLOCK="<skill_follow_up_files>"$'\n'
  BLOCK="${BLOCK}Skill: ${skill}"$'\n'"${skill_lines}"$'\n'
done

if [ -n "$BLOCK" ]; then
  BLOCK="${BLOCK}</skill_follow_up_files>"$'\n'
  printf '%s' "$BLOCK"
fi

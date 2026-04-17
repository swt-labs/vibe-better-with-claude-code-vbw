#!/usr/bin/env bash
# resolve-debug-target.sh — Resolve the contributor-local VBW debug target repo.
#
# Resolution order:
#   1. VBW_DEBUG_TARGET_REPO env var (one-off override)
#   2. <plugin-root>/.claude/vbw-debug-target.txt (preferred local config)
#   3. ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/vbw/debug-target.txt (user-global fallback)
#
# File format: first non-empty, non-comment line is the absolute path to the
# contributor's primary VBW consumer/test repo.
#
# Usage:
#   resolve-debug-target.sh [repo|planning-dir|encoded-path|claude-project-dir|source|all] [--plugin-root PATH]
#
# Notes:
# - --plugin-root exists so tests and diagnostics can point at an explicit repo root
#   without relying on the script's installed location.
# - The resolved target must exist as a directory. The script does not require
#   .vbw-planning/ to exist because some debug flows may need to inspect pre-init repos.

set -euo pipefail

FIELD="${1:-repo}"
if [ $# -gt 0 ]; then
  shift
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

usage() {
  echo "Usage: resolve-debug-target.sh [repo|planning-dir|encoded-path|claude-project-dir|source|all] [--plugin-root PATH]" >&2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --plugin-root)
      if [ $# -lt 2 ]; then
        echo "Error: --plugin-root requires a path" >&2
        usage
        exit 1
      fi
      PLUGIN_ROOT="$2"
      shift 2
      ;;
    *)
      echo "Error: unknown option '$1'" >&2
      usage
      exit 1
      ;;
  esac
done

# shellcheck source=resolve-claude-dir.sh
. "$SCRIPT_DIR/resolve-claude-dir.sh"

read_target_file() {
  local file_path="$1"

  [ -f "$file_path" ] || return 1

  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      sub(/[[:space:]]+$/, "", $0)
      print
      exit
    }
  ' "$file_path"
}

LOCAL_FILE="$PLUGIN_ROOT/.claude/vbw-debug-target.txt"
GLOBAL_FILE="$CLAUDE_DIR/vbw/debug-target.txt"
TARGET_REPO=""
TARGET_SOURCE=""

if [ -n "${VBW_DEBUG_TARGET_REPO:-}" ]; then
  TARGET_REPO="$VBW_DEBUG_TARGET_REPO"
  TARGET_SOURCE="VBW_DEBUG_TARGET_REPO"
elif TARGET_REPO="$(read_target_file "$LOCAL_FILE" 2>/dev/null || true)" && [ -n "$TARGET_REPO" ]; then
  TARGET_SOURCE="$LOCAL_FILE"
elif TARGET_REPO="$(read_target_file "$GLOBAL_FILE" 2>/dev/null || true)" && [ -n "$TARGET_REPO" ]; then
  TARGET_SOURCE="$GLOBAL_FILE"
else
  echo "No VBW debug target repo configured." >&2
  echo "Set VBW_DEBUG_TARGET_REPO, create $LOCAL_FILE, or create $GLOBAL_FILE." >&2
  exit 1
fi

if [ ! -d "$TARGET_REPO" ]; then
  echo "Configured VBW debug target repo does not exist or is not a directory: $TARGET_REPO" >&2
  exit 1
fi

TARGET_REPO="$(cd "$TARGET_REPO" && pwd -P)"
ENCODED_PATH="${TARGET_REPO//\//-}"
PLANNING_DIR="$TARGET_REPO/.vbw-planning"
CLAUDE_PROJECT_DIR="$CLAUDE_DIR/projects/$ENCODED_PATH"

case "$FIELD" in
  repo)
    printf '%s\n' "$TARGET_REPO"
    ;;
  planning-dir)
    printf '%s\n' "$PLANNING_DIR"
    ;;
  encoded-path)
    printf '%s\n' "$ENCODED_PATH"
    ;;
  claude-project-dir)
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    ;;
  source)
    printf '%s\n' "$TARGET_SOURCE"
    ;;
  all)
    printf 'repo=%s\n' "$TARGET_REPO"
    printf 'planning_dir=%s\n' "$PLANNING_DIR"
    printf 'encoded_path=%s\n' "$ENCODED_PATH"
    printf 'claude_project_dir=%s\n' "$CLAUDE_PROJECT_DIR"
    printf 'source=%s\n' "$TARGET_SOURCE"
    ;;
  *)
    echo "Error: unknown field '$FIELD'" >&2
    usage
    exit 1
    ;;
esac

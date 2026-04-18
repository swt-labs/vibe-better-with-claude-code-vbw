#!/usr/bin/env bash
set -u

# post-archive-hook.sh <milestone-slug> <archive-path> <tag> [config-path]
# Fail-open dispatcher for user-configured post-archive hooks.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P 2>/dev/null || dirname "$0")
ROOT_HELPER="$SCRIPT_DIR/lib/vbw-config-root.sh"

if [ -f "$ROOT_HELPER" ]; then
  # shellcheck source=lib/vbw-config-root.sh
  . "$ROOT_HELPER"
  find_vbw_root "$SCRIPT_DIR" 2>/dev/null || true
fi

warn() {
  echo "[post-archive-hook] WARNING: $*" >&2
}

resolve_from_base() {
  local path="$1"
  local base_dir="$2"

  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *)  printf '%s/%s\n' "$base_dir" "$path" ;;
  esac
}

MILESTONE_SLUG="${1:-}"
ARCHIVE_PATH="${2:-}"
TAG="${3-}"

BASE_ROOT="${VBW_CONFIG_ROOT:-$(pwd -P 2>/dev/null || pwd)}"
DEFAULT_CONFIG_PATH="${VBW_PLANNING_DIR:-$BASE_ROOT/.vbw-planning}/config.json"
CONFIG_PATH="${4:-$DEFAULT_CONFIG_PATH}"
CONFIG_PATH=$(resolve_from_base "$CONFIG_PATH" "$BASE_ROOT")

if CONFIG_DIR=$(cd "$(dirname "$CONFIG_PATH")" 2>/dev/null && pwd -P 2>/dev/null); then
  CONFIG_PATH="$CONFIG_DIR/$(basename "$CONFIG_PATH")"
  PLANNING_DIR="$CONFIG_DIR"
else
  PLANNING_DIR=$(dirname "$CONFIG_PATH")
fi

PROJECT_ROOT=$(dirname "$PLANNING_DIR")
export VBW_CONFIG_ROOT="$PROJECT_ROOT"
export VBW_PLANNING_DIR="$PLANNING_DIR"

[ -n "$MILESTONE_SLUG" ] || exit 0
[ -n "$ARCHIVE_PATH" ] || exit 0

ARCHIVE_PATH=$(resolve_from_base "$ARCHIVE_PATH" "$PROJECT_ROOT")

LOG_EVENT_SCRIPT="$SCRIPT_DIR/log-event.sh"
if [ -f "$LOG_EVENT_SCRIPT" ]; then
  bash "$LOG_EVENT_SCRIPT" milestone_shipped archive \
    "slug=$MILESTONE_SLUG" \
    "archive_path=$ARCHIVE_PATH" \
    "tag=$TAG" \
    >/dev/null 2>&1 || true
fi

if [ ! -f "$CONFIG_PATH" ]; then
  warn "config not found at $CONFIG_PATH; skipping post_archive hook"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  warn "jq unavailable; skipping post_archive hook"
  exit 0
fi

HOOK_PATH=$(jq -r '.hooks.post_archive // ""' "$CONFIG_PATH" 2>/dev/null) || {
  warn "could not read hooks.post_archive from $CONFIG_PATH; skipping post_archive hook"
  exit 0
}

[ -n "$HOOK_PATH" ] || exit 0

HOOK_PATH=$(resolve_from_base "$HOOK_PATH" "$PROJECT_ROOT")

if [ ! -f "$HOOK_PATH" ]; then
  warn "configured post_archive hook not found at $HOOK_PATH; skipping"
  exit 0
fi

if ! bash "$HOOK_PATH" "$MILESTONE_SLUG" "$ARCHIVE_PATH" "$TAG"; then
  warn "configured post_archive hook failed at $HOOK_PATH; continuing archive"
fi

exit 0
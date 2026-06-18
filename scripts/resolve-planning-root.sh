#!/usr/bin/env bash
# resolve-planning-root.sh — Print the nearest-ancestor .vbw-planning/ path.
#
# Usage:
#   bash resolve-planning-root.sh [start_dir]
#
# Resolution cascade (matches scripts/lib/vbw-config-root.sh):
#   1. VBW_PLANNING_ROOT env var (if set, non-empty, and an existing directory)
#      — prints "$VBW_PLANNING_ROOT/.vbw-planning"
#   2. $(git rev-parse --git-common-dir)/info/vbw-planning-root.txt pointer file
#   3. Filesystem walk-up from CWD (and explicit start_dir when supplied)
#   4. Fallback: $PWD/.vbw-planning (backwards-compatible)
#
# A start_dir is only consulted when supplied explicitly as $1. The script does
# NOT silently fall back to its own SCRIPT_DIR, because in --plugin-dir dev
# mode that would resolve to the plugin clone's own .vbw-planning/ when the
# caller is outside any real workspace.
#
# Exit contract: always exits 0. Prints exactly one absolute path to the
# .vbw-planning DIRECTORY on stdout (NOT the workspace root above it). Consumers
# build "$PLANNING_ROOT/config.json", "$PLANNING_ROOT/ROADMAP.md", etc.
# stderr may carry a one-line auto-resolve banner (emitted by find_vbw_root).
set -u

# Step 1 contract: print the .vbw-planning DIR (matching post-walk-up output),
# not the raw workspace root. The env var names the workspace; the script's
# output names the planning DIR inside it. Validate the workspace exists so a
# stale/typo env var falls through to the rest of the cascade instead of
# silently routing consumers to a non-existent path.
if [ -n "${VBW_PLANNING_ROOT:-}" ] && [ -d "$VBW_PLANNING_ROOT" ]; then
  # Diagnose env-var pointing at a non-VBW workspace (no .vbw-planning/).
  # The override is still honored (user may be bootstrapping), but we tell
  # them upfront so the eventual "Run /vbw:init first" guard makes sense.
  if [ ! -d "$VBW_PLANNING_ROOT/.vbw-planning" ] && [ -z "${_VBW_ENV_VAR_WARNED:-}" ]; then
    printf 'VBW: VBW_PLANNING_ROOT=%s honored but no .vbw-planning/ exists under it.\n' \
      "$VBW_PLANNING_ROOT" >&2
    _VBW_ENV_VAR_WARNED=1
    export _VBW_ENV_VAR_WARNED
  fi
  printf '%s\n' "$VBW_PLANNING_ROOT/.vbw-planning"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/vbw-config-root.sh
. "$SCRIPT_DIR/lib/vbw-config-root.sh"
find_vbw_root "${1:-}"
printf '%s\n' "$VBW_PLANNING_DIR"
exit 0

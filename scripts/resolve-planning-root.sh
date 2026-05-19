#!/usr/bin/env bash
# resolve-planning-root.sh — Print the nearest-ancestor .vbw-planning/ path.
#
# Usage:
#   bash resolve-planning-root.sh [start_dir]
#
# Resolution cascade (matches scripts/lib/vbw-config-root.sh):
#   1. VBW_PLANNING_ROOT env var (if set and non-empty) — printed verbatim
#   2. $(git rev-parse --git-common-dir)/info/vbw-planning-root.txt pointer file
#   3. Filesystem walk-up from CWD (and optional start_dir)
#   4. Fallback: $PWD/.vbw-planning (backwards-compatible)
#
# Exit contract: always exits 0. Prints exactly one absolute path on stdout.
# stderr may carry a one-line auto-resolve banner (emitted by find_vbw_root).
set -u

if [ -n "${VBW_PLANNING_ROOT:-}" ]; then
  printf '%s\n' "$VBW_PLANNING_ROOT"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/vbw-config-root.sh
. "$SCRIPT_DIR/lib/vbw-config-root.sh"
find_vbw_root "${1:-$SCRIPT_DIR}"
printf '%s\n' "$VBW_PLANNING_DIR"
exit 0

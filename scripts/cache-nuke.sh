#!/usr/bin/env bash
# cache-nuke.sh — Wipe ALL VBW caches to prevent stale contamination.
#
# Usage:
#   cache-nuke.sh              # wipe everything
#   cache-nuke.sh --keep-latest  # keep latest cached plugin version, wipe rest
#
# Called by: /vbw:update, session-start.sh
# Output: JSON summary of what was wiped.

set -eo pipefail

KEEP_LATEST=false
if [[ "${1:-}" == "--keep-latest" ]]; then
  KEEP_LATEST=true
fi

# shellcheck source=resolve-claude-dir.sh
. "$(dirname "$0")/resolve-claude-dir.sh"
PLUGIN_CACHE_DIR="$CLAUDE_DIR/plugins/cache/vbw-marketplace/vbw"
UID_TAG="$(id -u)"

wiped_plugin_cache=false
wiped_temp_caches=false
versions_removed=0

# --- 1. Plugin cache ---
if [[ -d "$PLUGIN_CACHE_DIR" ]]; then
  if [[ "$KEEP_LATEST" == true ]]; then
    # Only consider real directories for keep-latest — symlinks are left untouched.
    VERSIONS=$(ls -d "$PLUGIN_CACHE_DIR"/*/ 2>/dev/null | while IFS= read -r _d; do
      [ -L "${_d%/}" ] || echo "$_d"
    done | sort -V || true)
    COUNT=$(echo "$VERSIONS" | grep -c '/' || true)
    if [[ "$COUNT" -gt 1 ]]; then
      TO_REMOVE=$(echo "$VERSIONS" | head -n $((COUNT - 1)))
      versions_removed=0
      while IFS= read -r dir; do
        [ -n "$dir" ] || continue
        if rm -rf "$dir" 2>/dev/null; then
          versions_removed=$((versions_removed + 1))
        fi
      done <<< "$TO_REMOVE"
      if [[ "$versions_removed" -gt 0 ]]; then
        wiped_plugin_cache=true
      fi
    fi
  else
    versions_removed=$(ls -d "$PLUGIN_CACHE_DIR"/*/ 2>/dev/null | wc -l | tr -d ' ')
    if rm -rf "$PLUGIN_CACHE_DIR" 2>/dev/null; then
      wiped_plugin_cache=true
    else
      versions_removed=0
      wiped_plugin_cache=false
    fi
  fi
fi

# --- 2. Temp caches (statusline + update check) ---
TEMP_FILES=$(ls /tmp/vbw-*-"${UID_TAG}"-* /tmp/vbw-*-"${UID_TAG}" /tmp/vbw-update-check-"${UID_TAG}" 2>/dev/null || true)
if [[ -n "$TEMP_FILES" ]]; then
  while IFS= read -r f; do rm -f "$f" 2>/dev/null || true; done <<< "$TEMP_FILES"
  wiped_temp_caches=true
fi

# --- JSON summary ---
cat <<EOF
{"wiped":{"plugin_cache":${wiped_plugin_cache},"temp_caches":${wiped_temp_caches},"versions_removed":${versions_removed}}}
EOF

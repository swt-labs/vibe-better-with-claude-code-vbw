#!/usr/bin/env bash
# vbw-config-root.sh — Canonical VBW workspace root resolution
# Fixes upstream issue #258: bare .vbw-planning/ paths fail in monorepo submodules.
#
# Source this file from other scripts:
#   . "$(dirname "$0")/lib/vbw-config-root.sh"
#   find_vbw_root
#
# After calling find_vbw_root(), these variables are exported:
#   VBW_CONFIG_ROOT  — absolute path to the workspace root (directory containing .vbw-planning/)
#   VBW_PLANNING_DIR — convenience alias: $VBW_CONFIG_ROOT/.vbw-planning
#
# Resolution: walks up from $PWD until .vbw-planning/config.json is found.
# Fallback: VBW_CONFIG_ROOT="." when no config is found (backwards-compatible — CWD is root).
#
# Idempotent: if VBW_CONFIG_ROOT is already set, the walk is skipped (cache hit).
# This is the single source of truth for VBW workspace root resolution.
# New scripts MUST source this file instead of hardcoding ".vbw-planning".

find_vbw_root() {
  # Cache hit: already resolved in this shell or by a parent script
  if [ -n "${VBW_CONFIG_ROOT:-}" ]; then
    export VBW_CONFIG_ROOT
    export VBW_PLANNING_DIR="${VBW_CONFIG_ROOT}/.vbw-planning"
    return 0
  fi

  local _cwd
  # Use pwd -P to resolve symlinks so traversal works through symlinked directories
  _cwd=$(pwd -P 2>/dev/null || pwd)
  while [ "$_cwd" != "/" ]; do
    if [ -f "$_cwd/.vbw-planning/config.json" ]; then
      export VBW_CONFIG_ROOT="$_cwd"
      export VBW_PLANNING_DIR="$_cwd/.vbw-planning"
      return 0
    fi
    _cwd=$(dirname "$_cwd")
  done

  # Not found anywhere in the ancestry — fall back to absolute CWD (backwards-compatible)
  local _fallback
  _fallback=$(pwd -P 2>/dev/null || pwd)
  export VBW_CONFIG_ROOT="$_fallback"
  export VBW_PLANNING_DIR="$_fallback/.vbw-planning"
}

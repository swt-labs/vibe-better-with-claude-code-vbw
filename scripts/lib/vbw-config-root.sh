#!/usr/bin/env bash
# vbw-config-root.sh — Canonical VBW workspace root resolution
# Fixes upstream issue #258: bare .vbw-planning/ paths fail in monorepo submodules.
#
# Source this file from other scripts:
#   . "$(dirname "$0")/lib/vbw-config-root.sh"
#   find_vbw_root            # walks up from PWD only
#   find_vbw_root "$SCRIPT_DIR"  # walks up from script dir first, then PWD (recommended
#                                #   for mid-session hooks where agent CWD may have shifted)
#
# After calling find_vbw_root(), these variables are exported:
#   VBW_CONFIG_ROOT  — absolute path to the workspace root (directory containing .vbw-planning/)
#   VBW_PLANNING_DIR — convenience alias: $VBW_CONFIG_ROOT/.vbw-planning
#
# Resolution strategy when start_dir is provided:
#   1. Walk up from start_dir — finds config when script lives inside the project (dev/--plugin-dir)
#   2. If not found, walk up from PWD — finds config when script lives in plugin cache (production)
#   3. Fallback: PWD (backwards-compatible — CWD is root)
# When called without args: walks from PWD only (all existing callers unchanged).
#
# Idempotent: if VBW_CONFIG_ROOT is already set, the walk is skipped (cache hit).
# This is the single source of truth for VBW workspace root resolution.
# New scripts MUST source this file instead of hardcoding ".vbw-planning".

_walk_up_for_vbw_root() {
  local _cwd="$1"
  while [ "$_cwd" != "/" ]; do
    if [ -f "$_cwd/.vbw-planning/config.json" ]; then
      export VBW_CONFIG_ROOT="$_cwd"
      export VBW_PLANNING_DIR="$_cwd/.vbw-planning"
      return 0
    fi
    _cwd=$(dirname "$_cwd")
  done
  return 1
}

find_vbw_root() {
  # Cache hit: already resolved in this shell or by a parent script
  if [ -n "${VBW_CONFIG_ROOT:-}" ]; then
    export VBW_CONFIG_ROOT
    export VBW_PLANNING_DIR="${VBW_CONFIG_ROOT}/.vbw-planning"
    return 0
  fi

  local _start_dir _cwd_dir
  _cwd_dir=$(pwd -P 2>/dev/null || pwd)

  if [ -n "${1:-}" ]; then
    # Resolve start_dir to an absolute path
    _start_dir=$(cd "$1" && pwd -P 2>/dev/null) || _start_dir="$1"
    # Walk up from start_dir first (works when script lives inside the project, e.g. dev/--plugin-dir)
    _walk_up_for_vbw_root "$_start_dir" && return 0
    # Not found via script-relative walk — try CWD (production: plugin cache is outside project)
    # Only attempt if CWD differs from start_dir to avoid redundant traversal
    [ "$_cwd_dir" != "$_start_dir" ] && _walk_up_for_vbw_root "$_cwd_dir" && return 0
  else
    _walk_up_for_vbw_root "$_cwd_dir" && return 0
  fi

  # Not found anywhere — fall back to CWD (backwards-compatible)
  export VBW_CONFIG_ROOT="$_cwd_dir"
  export VBW_PLANNING_DIR="$_cwd_dir/.vbw-planning"
}

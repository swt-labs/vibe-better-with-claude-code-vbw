#!/usr/bin/env bash
# vbw-config-root.sh — Canonical VBW workspace root resolution
# Fixes upstream issue #258: bare .vbw-planning/ paths fail in monorepo submodules.
#
# Source this file from other scripts:
#   . "$(dirname "$0")/lib/vbw-config-root.sh"
#   find_vbw_root            # uses PWD as anchor (hooks called from session CWD)
#   find_vbw_root "$SCRIPT_DIR"  # uses stable script-relative anchor (recommended for statusline/mid-session hooks)
#
# After calling find_vbw_root(), these variables are exported:
#   VBW_CONFIG_ROOT  — absolute path to the workspace root (directory containing .vbw-planning/)
#   VBW_PLANNING_DIR — convenience alias: $VBW_CONFIG_ROOT/.vbw-planning
#
# Resolution: walks up from start_dir (or $PWD when omitted) until .vbw-planning/config.json is found.
# Fallback: VBW_CONFIG_ROOT=start_dir when no config is found (backwards-compatible).
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
  # Accept optional start_dir arg; fall back to PWD only when absent.
  # Callers that run mid-session (e.g. statusline, PreToolUse hooks) SHOULD pass a
  # stable, script-relative anchor so agents moving around the monorepo don't shift
  # the resolved root to a foreign repo.
  if [ -n "${1:-}" ]; then
    _cwd=$(cd "$1" && pwd -P 2>/dev/null) || _cwd="$1"
  else
    _cwd=$(pwd -P 2>/dev/null || pwd)
  fi
  while [ "$_cwd" != "/" ]; do
    if [ -f "$_cwd/.vbw-planning/config.json" ]; then
      export VBW_CONFIG_ROOT="$_cwd"
      export VBW_PLANNING_DIR="$_cwd/.vbw-planning"
      return 0
    fi
    _cwd=$(dirname "$_cwd")
  done

  # Not found anywhere in the ancestry — fall back to the resolved start dir
  local _fallback
  if [ -n "${1:-}" ]; then
    _fallback=$(cd "$1" && pwd -P 2>/dev/null) || _fallback="$1"
  else
    _fallback=$(pwd -P 2>/dev/null || pwd)
  fi
  export VBW_CONFIG_ROOT="$_fallback"
  export VBW_PLANNING_DIR="$_fallback/.vbw-planning"
}

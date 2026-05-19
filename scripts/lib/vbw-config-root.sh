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
#   VBW_CLAUDE_SIDECHAIN_ROOT — Claude internal sidechain root when CWD is under
#                               {host}/.claude/worktrees/agent-* (unset otherwise)
#   VBW_CLAUDE_SIDECHAIN_HOST_ROOT — host repo for the Claude sidechain (unset otherwise)
#
# Resolution strategy when start_dir is provided:
#   1. Walk up from PWD — prefer the active workspace when the script lives in a different repo
#      (e.g. local --plugin-dir development with the VBW repo checked out separately)
#   2. If not found, walk up from start_dir — useful when the script lives inside the project but
#      the current process has drifted outside the workspace root
#   3. Fallback: PWD (backwards-compatible — CWD is root)
# When called without args: walks from PWD only (all existing callers unchanged).
#
# Idempotent: if VBW_CONFIG_ROOT is already set, the walk is skipped (cache hit).
# This is the single source of truth for VBW workspace root resolution.
# New scripts MUST source this file instead of hardcoding ".vbw-planning".

_walk_up_for_vbw_root() {
  local _cwd="$1" _prev
  while [ "$_cwd" != "/" ]; do
    if [ -f "$_cwd/.vbw-planning/config.json" ]; then
      export VBW_CONFIG_ROOT="$_cwd"
      export VBW_PLANNING_DIR="$_cwd/.vbw-planning"
      return 0
    fi
    _prev="$_cwd"
    _cwd=$(dirname "$_cwd")
    # Guard: dirname stopped making progress (e.g. relative path hit ".")
    [ "$_cwd" = "$_prev" ] && break
  done
  return 1
}

_prefer_claude_sidechain_host_root() {
  local _cwd="$1" _probe _parent _grandparent _host

  _probe="$_cwd"
  while [ "$_probe" != "/" ]; do
    case "$(basename "$_probe")" in
      agent-*)
        _parent=$(dirname "$_probe")
        _grandparent=$(dirname "$_parent")
        if [ "$(basename "$_parent")" = "worktrees" ] && [ "$(basename "$_grandparent")" = ".claude" ]; then
          _host=$(dirname "$_grandparent")
          if [ -f "$_host/.vbw-planning/config.json" ]; then
            export VBW_CONFIG_ROOT="$_host"
            export VBW_PLANNING_DIR="$_host/.vbw-planning"
            export VBW_CLAUDE_SIDECHAIN_ROOT="$_probe"
            export VBW_CLAUDE_SIDECHAIN_HOST_ROOT="$_host"
            return 0
          fi
        fi
        ;;
    esac

    _parent=$(dirname "$_probe")
    [ "$_parent" = "$_probe" ] && break
    _probe="$_parent"
  done

  return 1
}

_emit_vbw_fallback_banner() {
  # One-line stderr banner emitted exactly once per shell process when
  # find_vbw_root falls through every cascade step and resorts to the
  # cwd-relative fallback. Uses a SEPARATE sentinel from the auto-resolve
  # banner so a single process can legitimately surface both signals.
  local _planning_dir="$1"
  [ -n "${_VBW_FALLBACK_BANNER_EMITTED:-}" ] && return 0
  printf 'VBW: warning: no .vbw-planning/ ancestor found; using cwd-relative fallback (%s).\n' "$_planning_dir" >&2
  _VBW_FALLBACK_BANNER_EMITTED=1
  export _VBW_FALLBACK_BANNER_EMITTED
}

_emit_vbw_auto_resolve_banner() {
  # One-line stderr banner emitted exactly once per shell process when CWD
  # is below the resolved planning root. Guarded by _VBW_BANNER_EMITTED.
  local _root="$1" _cwd="$2"
  [ -n "${_VBW_BANNER_EMITTED:-}" ] && return 0
  [ "$_root" = "$_cwd" ] && return 0
  case "$_cwd/" in
    "$_root"/*) ;;
    *) return 0 ;;
  esac
  printf 'VBW: planning found at %s — paths resolved from there.\n' "$_root" >&2
  _VBW_BANNER_EMITTED=1
  export _VBW_BANNER_EMITTED
}

find_vbw_root() {
  # Cache hit: already resolved in this shell or by a parent script
  if [ -n "${VBW_CONFIG_ROOT:-}" ]; then
    export VBW_CONFIG_ROOT
    export VBW_PLANNING_DIR="${VBW_CONFIG_ROOT}/.vbw-planning"
    return 0
  fi

  local _start_dir _cwd_dir _ptr_file _ptr_root
  _cwd_dir=$(pwd -P 2>/dev/null || pwd)

  # Step 1: honor VBW_PLANNING_ROOT env var (workspace root, not planning dir)
  if [ -n "${VBW_PLANNING_ROOT:-}" ]; then
    export VBW_CONFIG_ROOT="$VBW_PLANNING_ROOT"
    export VBW_PLANNING_DIR="$VBW_PLANNING_ROOT/.vbw-planning"
    _emit_vbw_auto_resolve_banner "$VBW_CONFIG_ROOT" "$_cwd_dir"
    return 0
  fi

  # Step 2: git-common-dir pointer file (shared across worktrees of the same clone)
  if _ptr_file=$(git rev-parse --git-common-dir 2>/dev/null); then
    _ptr_file="$_ptr_file/info/vbw-planning-root.txt"
    if [ -f "$_ptr_file" ]; then
      _ptr_root=$(grep -vE '^[[:space:]]*(#|$)' "$_ptr_file" 2>/dev/null \
        | head -n 1 \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
      if [ -n "$_ptr_root" ] && [ -d "$_ptr_root" ]; then
        export VBW_CONFIG_ROOT="$_ptr_root"
        export VBW_PLANNING_DIR="$_ptr_root/.vbw-planning"
        _emit_vbw_auto_resolve_banner "$VBW_CONFIG_ROOT" "$_cwd_dir"
        return 0
      fi
    fi
  fi

  if [ -n "${1:-}" ]; then
    # Claude Code can run subagents inside unmanaged internal sidechains at
    # {host}/.claude/worktrees/agent-*. Treat those as executions of the host
    # workspace before nearest-ancestor walking can select the copied sidechain
    # .vbw-planning tree. VBW-managed .vbw-worktrees/* are intentionally not
    # covered by this exception.
    if _prefer_claude_sidechain_host_root "$_cwd_dir"; then
      _emit_vbw_auto_resolve_banner "$VBW_CONFIG_ROOT" "$_cwd_dir"; return 0
    fi
    # Prefer the active workspace when CWD is already inside a VBW project.
    if _walk_up_for_vbw_root "$_cwd_dir"; then
      _emit_vbw_auto_resolve_banner "$VBW_CONFIG_ROOT" "$_cwd_dir"; return 0
    fi
    # Resolve start_dir to an absolute path; suppress cd stderr so bad paths
    # don't leak error messages into hook/statusline output (#267)
    if _start_dir=$(cd "$1" 2>/dev/null && pwd -P 2>/dev/null); then
      # Fall back to start_dir when CWD is outside any VBW workspace.
      if _walk_up_for_vbw_root "$_start_dir"; then
        _emit_vbw_auto_resolve_banner "$VBW_CONFIG_ROOT" "$_cwd_dir"; return 0
      fi
    else
      # Failed to resolve start_dir; fall back to walking from CWD only
      if _walk_up_for_vbw_root "$_cwd_dir"; then
        _emit_vbw_auto_resolve_banner "$VBW_CONFIG_ROOT" "$_cwd_dir"; return 0
      fi
    fi
  else
    if _prefer_claude_sidechain_host_root "$_cwd_dir"; then
      _emit_vbw_auto_resolve_banner "$VBW_CONFIG_ROOT" "$_cwd_dir"; return 0
    fi
    if _walk_up_for_vbw_root "$_cwd_dir"; then
      _emit_vbw_auto_resolve_banner "$VBW_CONFIG_ROOT" "$_cwd_dir"; return 0
    fi
  fi

  # Not found anywhere — fall back to CWD (backwards-compatible)
  export VBW_CONFIG_ROOT="$_cwd_dir"
  export VBW_PLANNING_DIR="$_cwd_dir/.vbw-planning"
  _emit_vbw_fallback_banner "$VBW_PLANNING_DIR"
}

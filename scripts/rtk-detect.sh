#!/usr/bin/env bash
# rtk-detect.sh — RTK (Rust Token Killer) detection helper for VBW
#
# Source this file: . "$(dirname "$0")/rtk-detect.sh"
# Sets RTK_* variables. Never exits non-zero. <50ms total.
#
# Optional: set RTK_SKIP_GAINS=true before sourcing to skip the
# rtk gain call (useful when only checking presence, not analytics).

RTK_BINARY=false
RTK_VERSION=""
RTK_HOOK=false
RTK_FULLY_ACTIVE=false
RTK_GAIN_SAVED=0
RTK_GAIN_PCT=0
RTK_GAIN_HAS_DATA=false

# --- Binary check (~1ms) ---
if command -v rtk &>/dev/null; then
  RTK_BINARY=true
  RTK_VERSION=$(rtk --version 2>/dev/null | head -1 | sed 's/^rtk //' || true)
fi

# --- Hook check (~1ms, file stat only) ---
# Source CLAUDE_DIR resolution if not already set
if [ -z "${CLAUDE_DIR:-}" ]; then
  _rtk_detect_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "$_rtk_detect_dir/resolve-claude-dir.sh" ]; then
    . "$_rtk_detect_dir/resolve-claude-dir.sh" 2>/dev/null || true
  fi
fi
# RTK installs hook at CLAUDE_DIR/hooks/rtk-rewrite.sh
# Also check $HOME/.claude as fallback (RTK hardcodes this path)
if [ -f "${CLAUDE_DIR:-$HOME/.claude}/hooks/rtk-rewrite.sh" ] || \
   [ -f "$HOME/.claude/hooks/rtk-rewrite.sh" ]; then
  RTK_HOOK=true
fi

if [ "$RTK_BINARY" = true ] && [ "$RTK_HOOK" = true ]; then
  RTK_FULLY_ACTIVE=true
fi

# --- Gains (~30ms, only if fully active and not skipped) ---
# RTK API: rtk gain --all --format json returns:
#   { "summary": { "total_saved": N, "avg_savings_pct": N, ... }, "daily": [...], ... }
if [ "$RTK_FULLY_ACTIVE" = true ] && [ "${RTK_SKIP_GAINS:-}" != true ] && command -v jq &>/dev/null; then
  _rtk_gains=$(rtk gain --all --format json 2>/dev/null || echo "{}")
  if [ -n "$_rtk_gains" ] && [ "$_rtk_gains" != "{}" ]; then
    RTK_GAIN_SAVED=$(printf '%s' "$_rtk_gains" | jq -r '.summary.total_saved // 0' 2>/dev/null || echo "0")
    RTK_GAIN_PCT=$(printf '%s' "$_rtk_gains" | jq -r '.summary.avg_savings_pct // 0 | floor' 2>/dev/null || echo "0")
    if [ "${RTK_GAIN_SAVED:-0}" != "0" ] && [ "${RTK_GAIN_SAVED:-0}" != "null" ]; then
      RTK_GAIN_HAS_DATA=true
    fi
  fi
fi

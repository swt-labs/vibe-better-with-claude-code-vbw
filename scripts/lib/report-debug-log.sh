#!/usr/bin/env bash
# scripts/lib/report-debug-log.sh — Parse Claude Code debug log for hook evidence
# Sourced by collect-diagnostics.sh. Expects redact() to be applied by the caller.
#
# Usage: collect_debug_log_diagnostics
# Reads ~/.claude/debug/latest (or CLAUDE_CONFIG_DIR override).
# Emits a compact summary: plugin loading, hook counts, hook errors, log path.
# Always succeeds (never exits non-zero).

collect_debug_log_diagnostics() {
  local claude_dir="${CLAUDE_CONFIG_DIR:-${HOME:-/tmp}/.claude}"
  local debug_log="${claude_dir}/debug/latest"

  echo "--- Debug Log Summary ---"

  if [ ! -f "$debug_log" ]; then
    echo "debug_log: not found (${debug_log})"
    echo ""
    return 0
  fi

  local real_path
  real_path=$(readlink "$debug_log" 2>/dev/null || echo "$debug_log")
  echo "debug_log: $real_path"
  echo "debug_log_lines: $(wc -l < "$debug_log" 2>/dev/null | tr -d ' ')"

  # Plugin loading evidence
  local plugin_lines
  plugin_lines=$(grep -cE 'Loading hooks from plugin:|Registered .* hooks from|Loaded plugin|Loading plugin' "$debug_log" 2>/dev/null || echo "0")
  echo "plugin_loading_lines: $plugin_lines"
  if [ "$plugin_lines" -gt 0 ]; then
    grep -E 'Loading hooks from plugin:|Registered .* hooks from|Loaded plugin|Loading plugin' "$debug_log" 2>/dev/null | head -5 | while IFS= read -r line; do
      echo "  $line"
    done
  fi

  # Hook lookup/match counts
  local hook_lookups hook_successes hook_errors
  hook_lookups=$(grep -c 'Getting matching hook commands' "$debug_log" 2>/dev/null || echo "0")
  hook_successes=$(grep -c 'Hook .* success:' "$debug_log" 2>/dev/null || echo "0")
  hook_errors=$(grep -ciE 'hook.*(error|fail|timeout|reject|denied|block|stderr)' "$debug_log" 2>/dev/null || echo "0")
  echo "hook_lookups: $hook_lookups"
  echo "hook_successes: $hook_successes"
  echo "hook_error_lines: $hook_errors"

  # Show hook errors if any (limited to 10)
  if [ "$hook_errors" -gt 0 ]; then
    grep -iE 'hook.*(error|fail|timeout|reject|denied|block|stderr)' "$debug_log" 2>/dev/null | head -10 | while IFS= read -r line; do
      echo "  [ERROR] $line"
    done
  fi

  echo ""
}

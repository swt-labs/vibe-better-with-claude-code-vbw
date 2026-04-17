#!/usr/bin/env bash
# scripts/collect-diagnostics.sh — Collect VBW diagnostic context for bug reporting
# Usage: bash scripts/collect-diagnostics.sh [plugin-root] [project-dir]
#
# Arguments:
#   $1  Plugin root directory (where VERSION, agents/, scripts/ live)
#   $2  Project working directory (where .vbw-planning/ may exist)
#
# Always exits 0. Output is redacted (home paths, usernames, API keys).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source debug-log helper (provides collect_debug_log_diagnostics)
# shellcheck source=lib/report-debug-log.sh
if [ -f "$SCRIPT_DIR/lib/report-debug-log.sh" ]; then
  . "$SCRIPT_DIR/lib/report-debug-log.sh"
fi

PLUGIN_ROOT="${1:-}"
PROJECT_DIR="${2:-$(pwd)}"

# --- Redaction filter applied to all output ---
redact() {

  sed "s|${HOME:-/nonexistent}|~|g" \
    | sed "s|${USER:-__no_user__}|<user>|g" \
    | sed -E 's/(sk-[a-zA-Z0-9_-]{10})[a-zA-Z0-9_-]+/\1.../g' \
    | sed -E 's/(ghp_[a-zA-Z0-9]{10})[a-zA-Z0-9]+/\1.../g' \
    | sed -E 's/(gho_[a-zA-Z0-9]{10})[a-zA-Z0-9]+/\1.../g' \
    | sed -E 's/(github_pat_[a-zA-Z0-9_]{10})[a-zA-Z0-9_]+/\1.../g' \
    | sed -E 's/(ghs_[a-zA-Z0-9]{10})[a-zA-Z0-9]+/\1.../g' \
    | sed -E 's/(ghu_[a-zA-Z0-9]{10})[a-zA-Z0-9]+/\1.../g'
}

# Collect all output into a function so we can pipe through redact once
collect() {
  local vbw_version os_info cc_version install_method cache_state
  local cache_root="${CLAUDE_CONFIG_DIR:-${HOME:-/tmp}/.claude}/plugins/cache/vbw-marketplace/vbw"

  echo "=== VBW Diagnostic Report ==="
  echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date 2>/dev/null || echo "unknown")"
  echo ""

  # --- Environment ---
  echo "--- Environment ---"

  if [ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_ROOT/VERSION" ]; then
    vbw_version=$(cat "$PLUGIN_ROOT/VERSION" 2>/dev/null || echo "unknown")
  else
    vbw_version="unknown"
  fi
  echo "vbw_version: $vbw_version"

  os_info=$(uname -s -r -m 2>/dev/null || echo "unknown")
  echo "os: $os_info"

  cc_version=$(claude --version 2>/dev/null || echo "unknown")
  echo "claude_code_version: $cc_version"

  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    install_method="--plugin-dir"
  elif [ -n "$PLUGIN_ROOT" ]; then
    local resolved_root
    resolved_root=$(cd "$PLUGIN_ROOT" 2>/dev/null && pwd -P) || resolved_root="$PLUGIN_ROOT"
    if [[ "$resolved_root" == *"/plugins/cache/"* ]]; then
      install_method="marketplace"
    else
      install_method="--plugin-dir (resolved)"
    fi
  elif [ -d "$cache_root" ]; then
    install_method="marketplace"
  else
    install_method="unknown"
  fi
  echo "install_method: $install_method"

  if [ -d "$cache_root" ]; then
    cache_state=$(ls -1 "$cache_root" 2>/dev/null | head -20)
    cache_count=$(ls -1 "$cache_root" 2>/dev/null | wc -l | tr -d ' ')
    echo "cache_versions ($cache_count):"
    if [ -n "$cache_state" ]; then
      echo "$cache_state" | sed 's/^/  /'
    else
      echo "  (empty)"
    fi
  else
    echo "cache_versions: (cache directory not found)"
  fi

  echo "bash_version: ${BASH_VERSION:-unknown}"
  echo "plugin_root: ${PLUGIN_ROOT:-not set}"
  echo "project_dir: $PROJECT_DIR"
  echo ""

  # --- Hook Errors ---
  echo "--- Hook Errors (last 20) ---"
  if [ -f "$PROJECT_DIR/.vbw-planning/.hook-errors.log" ]; then
    tail -20 "$PROJECT_DIR/.vbw-planning/.hook-errors.log" 2>/dev/null || echo "(read error)"
  else
    echo "(no .hook-errors.log found)"
  fi
  echo ""

  # --- Session Log ---
  echo "--- Session Log (last 10) ---"
  if [ -f "$PROJECT_DIR/.vbw-planning/.session-log.jsonl" ]; then
    tail -10 "$PROJECT_DIR/.vbw-planning/.session-log.jsonl" 2>/dev/null || echo "(read error)"
  else
    echo "(no .session-log.jsonl found)"
  fi
  echo ""

  # --- Event Log ---
  echo "--- Event Log (last 20) ---"
  if [ -f "$PROJECT_DIR/.vbw-planning/.events/event-log.jsonl" ]; then
    tail -20 "$PROJECT_DIR/.vbw-planning/.events/event-log.jsonl" 2>/dev/null || echo "(read error)"
  else
    echo "(no event-log.jsonl found)"
  fi
  echo ""

  # --- Metrics ---
  echo "--- Metrics (last 10) ---"
  if [ -f "$PROJECT_DIR/.vbw-planning/.metrics/run-metrics.jsonl" ]; then
    tail -10 "$PROJECT_DIR/.vbw-planning/.metrics/run-metrics.jsonl" 2>/dev/null || echo "(read error)"
  else
    echo "(no run-metrics.jsonl found)"
  fi
  echo ""

  # --- Config (redacted) ---
  echo "--- Config (redacted) ---"
  if [ -f "$PROJECT_DIR/.vbw-planning/config.json" ]; then
    if command -v jq >/dev/null 2>&1; then
      jq 'def walk(f): . as $in | if type == "object" then reduce keys[] as $k ({}; . + {($k): ($in[$k] | walk(f))}) | f elif type == "array" then map(walk(f)) | f else f end; walk(if type == "object" then with_entries(if (.key | test("key|token|secret|password|api_key"; "i")) then .value = "[REDACTED]" else . end) else . end)' \
        "$PROJECT_DIR/.vbw-planning/config.json" 2>/dev/null || cat "$PROJECT_DIR/.vbw-planning/config.json" 2>/dev/null || echo "(read error)"
    else
      cat "$PROJECT_DIR/.vbw-planning/config.json" 2>/dev/null || echo "(read error)"
    fi
  else
    echo "(no config.json found — project may not be initialized)"
  fi
  echo ""

  # --- Project State ---
  echo "--- Project State ---"
  if [ -d "$PROJECT_DIR/.vbw-planning" ]; then
    if [ -f "$PROJECT_DIR/.vbw-planning/STATE.md" ]; then
      echo "STATE.md:"
      cat "$PROJECT_DIR/.vbw-planning/STATE.md" 2>/dev/null || echo "(read error)"
    else
      echo "STATE.md: (not found)"
    fi
    echo ""
    echo "Phases:"
    if [ -d "$PROJECT_DIR/.vbw-planning/phases" ]; then
      ls -1 "$PROJECT_DIR/.vbw-planning/phases/" 2>/dev/null || echo "(empty)"
    else
      echo "(no phases directory)"
    fi
  else
    echo "(.vbw-planning/ not found — project not initialized)"
  fi
  echo ""

  # --- Hook Debug Log ---
  echo "--- Hook Debug Log (last 10) ---"
  if [ -f "$PROJECT_DIR/.vbw-planning/.hook-debug.log" ]; then
    tail -10 "$PROJECT_DIR/.vbw-planning/.hook-debug.log" 2>/dev/null || echo "(read error)"
  else
    echo "(no .hook-debug.log found)"
  fi
  echo ""

  # --- Debug Log Summary ---
  if type collect_debug_log_diagnostics &>/dev/null; then
    collect_debug_log_diagnostics
  else
    echo "--- Debug Log Summary ---"
    echo "(helper not available)"
    echo ""
  fi

  # --- Session Artifacts ---
  echo "--- Session Artifacts ---"
  local claude_dir="${CLAUDE_CONFIG_DIR:-${HOME:-/tmp}/.claude}"
  local session_id="${CLAUDE_SESSION_ID:-}"
  local session_key="${session_id:-default}"
  local session_link="/tmp/.vbw-plugin-root-link-${session_key}"

  echo "session_id: ${session_id:-(unset)}"
  echo "session_link: $session_link"
  if [ -L "$session_link" ]; then
    echo "session_link_exists: YES -> $(readlink "$session_link" 2>/dev/null)"
  else
    echo "session_link_exists: NO"
  fi

  # Hook resolution source
  local hook_cache hook_cpr hook_tmp=""
  hook_cache=$(ls -1 "$claude_dir"/plugins/cache/vbw-marketplace/vbw/*/scripts/hook-wrapper.sh 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1 || true)
  hook_cpr="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/hook-wrapper.sh}"
  for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do
    [ -f "$f" ] 2>/dev/null && hook_tmp="$f" && break
  done 2>/dev/null
  if [ -f "${hook_cache:-}" ]; then
    echo "hook_resolution: CACHE"
  elif [ -f "${hook_cpr:-}" ]; then
    echo "hook_resolution: PLUGIN_ROOT"
  elif [ -n "$hook_tmp" ]; then
    echo "hook_resolution: TMP_LINK"
  else
    echo "hook_resolution: NONE"
  fi

  # Config cache / update cache presence
  if [ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_ROOT/VERSION" ] && [ -f "$PLUGIN_ROOT/scripts/lib/vbw-cache-key.sh" ]; then
    local _diag_ver _diag_uid _diag_config_cache _diag_update_cache
    # shellcheck source=lib/vbw-cache-key.sh
    . "$PLUGIN_ROOT/scripts/lib/vbw-cache-key.sh"
    _diag_ver=$(cat "$PLUGIN_ROOT/VERSION" 2>/dev/null | tr -d '[:space:]')
    _diag_uid=$(id -u)
    _diag_config_cache=$(vbw_cache_prefix "${_diag_ver:-0}" "$_diag_uid" "${VBW_CONFIG_ROOT:-$(pwd -P 2>/dev/null || pwd)}")-config.env
    _diag_update_cache="/tmp/vbw-update-check-${_diag_uid}-$(vbw_hash_path "$PLUGIN_ROOT")"
    echo "config_cache_exists: $([ -f "$_diag_config_cache" ] && echo "YES" || echo "NO")"
    echo "update_cache_exists: $([ -f "$_diag_update_cache" ] && echo "YES" || echo "NO")"
  else
    echo "config_cache_exists: (unavailable)"
    echo "update_cache_exists: (unavailable)"
  fi

  # Welcome marker
  echo "welcome_marker: $([ -f "$claude_dir/.vbw-welcomed" ] && echo "YES" || echo "NO")"

  # Cache entry summary
  local cache_dir="${claude_dir}/plugins/cache/vbw-marketplace/vbw"
  if [ -d "$cache_dir" ]; then
    local entry_count
    entry_count=$(ls -d "$cache_dir"/*/ 2>/dev/null | wc -l | tr -d ' ')
    echo "cache_entries: $entry_count"
    for d in "$cache_dir"/*/; do
      [ -d "$d" ] 2>/dev/null || continue
      echo "  $(basename "$d")$([ -L "${d%/}" ] && echo " (symlink)" || echo "")"
    done 2>/dev/null
  else
    echo "cache_entries: (cache dir not found)"
  fi
  echo ""

  # --- Marketplace Status ---
  echo "--- Marketplace Status ---"
  local mp_cache_root="${claude_dir}/plugins/cache/vbw-marketplace/vbw"
  local mp_local_link="${mp_cache_root}/local"
  local mp_installed="${claude_dir}/plugins/installed_plugins.json"

  echo "cache_root: $mp_cache_root"
  echo "cache_root_exists: $([ -d "$mp_cache_root" ] && echo "YES" || echo "NO")"

  if [ -L "$mp_local_link" ]; then
    echo "local_link: SYMLINK -> $(readlink "$mp_local_link" 2>/dev/null)"
  elif [ -d "$mp_local_link" ]; then
    echo "local_link: REAL_DIR"
  else
    echo "local_link: NOT_PRESENT"
  fi

  if [ -f "$mp_installed" ]; then
    if command -v jq >/dev/null 2>&1; then
      local vbw_reg
      vbw_reg=$(jq -r '.plugins // {} | keys[] | select(test("vbw";"i"))' "$mp_installed" 2>/dev/null | head -1)
      echo "registry_entry: ${vbw_reg:-(not found)}"
    else
      echo "registry_entry: (jq unavailable — cannot parse)"
    fi
  else
    echo "registry_entry: (installed_plugins.json not found)"
  fi
  echo ""

  # --- Doctor Checks ---
  echo "--- Doctor Checks ---"

  if command -v jq >/dev/null 2>&1; then
    echo "jq: PASS ($(jq --version 2>/dev/null))"
  else
    echo "jq: FAIL (not installed)"
  fi

  if [ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_ROOT/VERSION" ]; then
    echo "VERSION file: PASS"
  else
    echo "VERSION file: FAIL (not found at plugin root)"
  fi

  if [ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_ROOT/hooks/hooks.json" ]; then
    if command -v jq >/dev/null 2>&1; then
      if jq empty "$PLUGIN_ROOT/hooks/hooks.json" 2>/dev/null; then
        echo "hooks.json: PASS (valid JSON)"
      else
        echo "hooks.json: FAIL (parse error)"
      fi
    else
      echo "hooks.json: SKIP (jq not available)"
    fi
  else
    echo "hooks.json: FAIL (not found)"
  fi

  if [ -n "$PLUGIN_ROOT" ] && [ -d "$PLUGIN_ROOT/agents" ]; then
    local agent_count
    agent_count=$(find "$PLUGIN_ROOT/agents" -name 'vbw-*.md' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$agent_count" -eq 7 ]; then
      echo "agent files: PASS ($agent_count/7)"
    else
      echo "agent files: WARN ($agent_count/7 expected)"
    fi
  else
    echo "agent files: FAIL (agents directory not found)"
  fi

  if command -v gh >/dev/null 2>&1; then
    echo "gh CLI: PASS ($(gh --version 2>/dev/null | head -1))"
  else
    echo "gh CLI: FAIL (not installed — needed for issue filing)"
  fi
}

# Run collection, pipe through redact, always exit 0
collect 2>&1 | redact || true

exit 0

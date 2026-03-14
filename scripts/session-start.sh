#!/bin/bash
set -u
# SessionStart: VBW project state detection, update checks, cache maintenance (exit 0)

# --- Dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"VBW: jq not found. Install: brew install jq (macOS) / apt install jq (Linux). All 17 VBW quality gates are disabled until jq is installed -- no commit validation, no security filtering, no file guarding."}}'
  exit 0
fi

PLANNING_DIR=".vbw-planning"
# shellcheck source=resolve-claude-dir.sh
. "$(dirname "$0")/resolve-claude-dir.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source shared summary-status helpers for status-aware SUMMARY detection
if [ -f "$SCRIPT_DIR/summary-utils.sh" ]; then
  # shellcheck source=summary-utils.sh
  . "$SCRIPT_DIR/summary-utils.sh"
else
  # Safe default: report zero completions when helpers unavailable
  count_complete_summaries() { echo "0"; }
  count_done_summaries() { echo "0"; }
fi

# --- Capture session_id from hook stdin JSON ---
# Claude Code passes a JSON object on stdin to SessionStart hooks containing
# session_id. Since CLAUDE_SESSION_ID was removed from the env (upstream
# regression anthropics/claude-code#24371), we extract it here and inject it
# via CLAUDE_ENV_FILE so command templates get per-session isolation.
# Stdin is ephemeral — must be consumed before any other read.
# Use timeout to avoid blocking when stdin is not piped (e.g., in tests).
if [ -t 0 ]; then
  HOOK_INPUT=""
else
  HOOK_INPUT=$(cat 2>/dev/null) || HOOK_INPUT=""
fi
_VBW_SESSION_ID=""
if [ -n "$HOOK_INPUT" ]; then
  _VBW_SESSION_ID=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null) || _VBW_SESSION_ID=""
fi
# Validate session_id: only allow safe characters (defense in depth)
# Use [[ =~ ]] which operates on the full string, not line-by-line like grep
if [ -n "$_VBW_SESSION_ID" ] && [[ "$_VBW_SESSION_ID" =~ [^a-zA-Z0-9._-] ]]; then
  _VBW_SESSION_ID=""
fi
if [ -n "$_VBW_SESSION_ID" ] && [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  _EXISTING_SID=$(grep '^export CLAUDE_SESSION_ID=' "$CLAUDE_ENV_FILE" 2>/dev/null | head -1 | sed 's/^export CLAUDE_SESSION_ID=//; s/^"//; s/"$//' || true)
  if [ -z "$_EXISTING_SID" ]; then
    printf 'export CLAUDE_SESSION_ID="%s"\n' "$_VBW_SESSION_ID" >> "$CLAUDE_ENV_FILE"
  elif [ "$_EXISTING_SID" != "$_VBW_SESSION_ID" ]; then
    # Replace stale session_id from a previous session (portable: no sed -i)
    _tmp_env=$(mktemp 2>/dev/null || echo "${CLAUDE_ENV_FILE}.tmp")
    grep -v '^export CLAUDE_SESSION_ID=' "$CLAUDE_ENV_FILE" > "$_tmp_env" 2>/dev/null || true
    mv "$_tmp_env" "$CLAUDE_ENV_FILE" 2>/dev/null || true
    printf 'export CLAUDE_SESSION_ID="%s"\n' "$_VBW_SESSION_ID" >> "$CLAUDE_ENV_FILE"
  fi
fi

find_phase_dir_by_num() {
  _planning_dir="$1"
  _phase_num="$2"
  ls -d "$_planning_dir/phases/$(printf '%02d' "$_phase_num")"-*/ 2>/dev/null | head -1
}

phase_dir_has_plans() {
  _phase_dir="$1"
  [ -n "$_phase_dir" ] && [ -d "$_phase_dir" ] && ls "$_phase_dir"*-PLAN.md >/dev/null 2>&1
}

# Choose a recovery phase deterministically when STATE.md/execution-state phase is unusable.
# Priority:
#   1) latest valid plan_end event phase that still has PLAN artifacts
#   2) earliest incomplete phase (plans > summaries)
#   3) latest completed phase (plans > 0 and plans == summaries)
#   4) earliest phase with plans
pick_recovery_phase() {
  _planning_dir="$1"
  _events_file="$2"

  _candidate=""
  if [ -f "$_events_file" ]; then
    while IFS= read -r _event_phase; do
      [ -n "$_event_phase" ] || continue
      if ! [ "$_event_phase" -gt 0 ] 2>/dev/null; then
        continue
      fi
      _event_phase_dir=$(find_phase_dir_by_num "$_planning_dir" "$_event_phase")
      if phase_dir_has_plans "$_event_phase_dir"; then
        _candidate="$_event_phase"
      fi
    done <<EOF
$(jq -Rr 'fromjson? | select(.event == "plan_end") | ((.phase | tostring | tonumber?) // empty)' "$_events_file" 2>/dev/null)
EOF
  fi

  if [ -n "$_candidate" ] && [ "$_candidate" -gt 0 ] 2>/dev/null; then
    echo "$_candidate"
    return 0
  fi

  _first_incomplete=""
  _last_complete=""
  _first_with_plan=""

  for _pd in "$_planning_dir"/phases/*/; do
    [ -d "$_pd" ] || continue
    _pd_base=$(basename "$_pd")
    _pd_num=$(echo "$_pd_base" | sed 's/^\([0-9]*\).*/\1/' | sed 's/^0*//')
    [ -n "$_pd_num" ] || continue
    if ! [ "$_pd_num" -gt 0 ] 2>/dev/null; then
      continue
    fi
    if ! phase_dir_has_plans "$_pd"; then
      continue
    fi

    if [ -z "$_first_with_plan" ] || [ "$_pd_num" -lt "$_first_with_plan" ] 2>/dev/null; then
      _first_with_plan="$_pd_num"
    fi

    _plan_count=0
    for _plan_file in "$_pd"*-PLAN.md; do
      [ -f "$_plan_file" ] || continue
      _plan_count=$((_plan_count + 1))
    done

    _summary_count=$(count_complete_summaries "$_pd")

    if [ "${_summary_count:-0}" -lt "${_plan_count:-0}" ] 2>/dev/null; then
      if [ -z "$_first_incomplete" ] || [ "$_pd_num" -lt "$_first_incomplete" ] 2>/dev/null; then
        _first_incomplete="$_pd_num"
      fi
    elif [ "${_plan_count:-0}" -gt 0 ] 2>/dev/null; then
      if [ -z "$_last_complete" ] || [ "$_pd_num" -gt "$_last_complete" ] 2>/dev/null; then
        _last_complete="$_pd_num"
      fi
    fi
  done

  if [ -n "$_first_incomplete" ] && [ "$_first_incomplete" -gt 0 ] 2>/dev/null; then
    echo "$_first_incomplete"
    return 0
  fi
  if [ -n "$_last_complete" ] && [ "$_last_complete" -gt 0 ] 2>/dev/null; then
    echo "$_last_complete"
    return 0
  fi
  if [ -n "$_first_with_plan" ] && [ "$_first_with_plan" -gt 0 ] 2>/dev/null; then
    echo "$_first_with_plan"
    return 0
  fi

  echo ""
  return 0
}

atomic_write_string() {
  _target="$1"
  _content="$2"
  _tmp="${_target}.tmp.$$"
  if printf '%s\n' "$_content" > "$_tmp" 2>/dev/null && mv "$_tmp" "$_target" 2>/dev/null; then
    return 0
  fi
  rm -f "$_tmp" 2>/dev/null || true
  return 1
}

# If this is a compact-triggered SessionStart, skip — post-compact.sh handles it.
# The compaction marker is set by compaction-instructions.sh (PreCompact) and cleared
# by post-compact.sh. Only skip if the marker is fresh (< 60s) to avoid stale markers
# from crashed compactions blocking normal session starts.
if [ -f "$PLANNING_DIR/.compaction-marker" ]; then
  _cm_ts=$(cat "$PLANNING_DIR/.compaction-marker" 2>/dev/null || echo 0)
  _cm_now=$(date +%s 2>/dev/null || echo 0)
  # Validate timestamp is numeric; treat non-numeric/empty as stale
  if [[ "$_cm_ts" =~ ^[0-9]+$ ]]; then
    _cm_age=$((_cm_now - _cm_ts))
    # Fresh marker (0-59s old): skip session-start, post-compact handles it
    # Negative age (future-dated clock skew) or >= 60s: treat as stale
    if [ "$_cm_age" -ge 0 ] && [ "$_cm_age" -lt 60 ]; then
      exit 0
    fi
  fi
  # Stale, future-dated, or corrupted marker — clean up and continue
  rm -f "$PLANNING_DIR/.compaction-marker" 2>/dev/null
fi

# Reset compaction loop counter at fresh session start
rm -f "$PLANNING_DIR/.compaction-count" 2>/dev/null || true

# Clear VBW context marker from previous session so statusline starts dim.
# Placed after compaction guard: during compaction, post-compact.sh handles cleanup.
# Only clear on genuine new session starts.
rm -f "$PLANNING_DIR/.vbw-context" 2>/dev/null || true

# Clear stale context-usage cache so suggest-compact.sh doesn't fire false
# pre-flight warnings using data from a previous session (#238).
rm -f "$PLANNING_DIR/.context-usage" 2>/dev/null || true

# Auto-migrate config if .vbw-planning exists.
# Version marker retained here for backwards test compatibility.
EXPECTED_FLAG_COUNT=39
if [ -d "$PLANNING_DIR" ] && [ -f "$PLANNING_DIR/config.json" ]; then
  if ! bash "$SCRIPT_DIR/migrate-config.sh" "$PLANNING_DIR/config.json" >/dev/null 2>&1; then
    echo "WARNING: Config migration failed (jq error). Config may be missing flags (expected=$EXPECTED_FLAG_COUNT)." >&2
  fi
fi

# --- Migrate .claude/CLAUDE.md to root CLAUDE.md (one-time, #20) ---
# Old VBW versions wrote a duplicate isolation guard to .claude/CLAUDE.md.
# Consolidate to root CLAUDE.md only. Three scenarios:
#   A) .claude/CLAUDE.md only (no root) → mv to root
#   B) Both exist → root already has isolation via bootstrap, delete guard
#   C) Root only → no-op
if [ -d "$PLANNING_DIR" ] && [ ! -f "$PLANNING_DIR/.claude-md-migrated" ]; then
  GUARD=".claude/CLAUDE.md"
  ROOT_CLAUDE="CLAUDE.md"
  if [ -f "$GUARD" ]; then
    if [ ! -f "$ROOT_CLAUDE" ]; then
      # Scenario A: guard only → move to root
      mv "$GUARD" "$ROOT_CLAUDE" 2>/dev/null || true
    else
      # Scenario B: both exist → root wins, delete guard
      rm -f "$GUARD" 2>/dev/null || true
    fi
  fi
  # Mark migration done (idempotent)
  echo "1" > "$PLANNING_DIR/.claude-md-migrated" 2>/dev/null || true
fi

# --- Migrate ## Todos / ### Pending Todos to flat ## Todos (one-time) ---
# Old STATE.md had a ### Pending Todos subsection under ## Todos.
# New format puts items directly under ## Todos. This migration:
#   1. Finds all STATE.md files (root + milestones)
#   2. Removes the "### Pending Todos" line, leaving items under ## Todos
if [ -d "$PLANNING_DIR" ] && [ ! -f "$PLANNING_DIR/.todo-flat-migrated" ]; then
  # Collect all STATE.md files to migrate
  _todo_state_files=""
  [ -f "$PLANNING_DIR/STATE.md" ] && _todo_state_files="$PLANNING_DIR/STATE.md"
  if [ -d "$PLANNING_DIR/milestones" ]; then
    for _ms_dir in "$PLANNING_DIR"/milestones/*/; do
      [ -f "${_ms_dir}STATE.md" ] && _todo_state_files="$_todo_state_files ${_ms_dir}STATE.md"
    done
  fi

  _todo_migrate_ok=true
  for _sf in $_todo_state_files; do
    if grep -q '^### Pending Todos$' "$_sf" 2>/dev/null; then
      # Remove the ### Pending Todos heading — items stay under ## Todos
      if grep -v '^### Pending Todos$' "$_sf" > "${_sf}.tmp" 2>/dev/null && mv "${_sf}.tmp" "$_sf" 2>/dev/null; then
        : # success
      else
        rm -f "${_sf}.tmp" 2>/dev/null || true
        _todo_migrate_ok=false
      fi
    fi
  done

  # Only write marker if all files migrated successfully
  if [ "$_todo_migrate_ok" = true ]; then
    echo "1" > "$PLANNING_DIR/.todo-flat-migrated" 2>/dev/null || true
  fi
fi

# --- Remove stale ACTIVE file (one-time, architecture simplification) ---
# ACTIVE milestone indirection has been removed. Root paths are canonical.
# Delete any leftover ACTIVE file so nothing reads it.
if [ -d "$PLANNING_DIR" ] && [ -f "$PLANNING_DIR/ACTIVE" ]; then
  rm -f "$PLANNING_DIR/ACTIVE" 2>/dev/null || true
fi

# --- Rename milestones/default/ to meaningful slug (one-time) ---
# Old archive created milestones/default/. Rename to descriptive slug.
if [ -d "$PLANNING_DIR/milestones/default" ] && [ -f "$SCRIPT_DIR/rename-default-milestone.sh" ]; then
  bash "$SCRIPT_DIR/rename-default-milestone.sh" "$PLANNING_DIR" 2>/dev/null || true
fi

# --- Migrate orphaned STATE.md for brownfield post-ship repos (one-time) ---
# If a project shipped a milestone before this fix, STATE.md lives only in
# milestones/{slug}/ with no root copy. Recover project-level sections.
if [ -d "$PLANNING_DIR" ] && [ ! -f "$PLANNING_DIR/STATE.md" ]; then
  bash "$SCRIPT_DIR/migrate-orphaned-state.sh" "$PLANNING_DIR" 2>/dev/null || true
fi

# --- Strip stale ### Skills subsection from STATE.md (one-time) ---
# Skills are now surfaced through the runtime activation pipeline.
# The old ### Skills subsection under ## Decisions is no longer written
# or read. Strip it from all STATE.md files so it doesn't linger.
if [ -d "$PLANNING_DIR" ] && [ ! -f "$PLANNING_DIR/.skills-section-stripped" ]; then
  _skills_state_files=""
  [ -f "$PLANNING_DIR/STATE.md" ] && _skills_state_files="$PLANNING_DIR/STATE.md"
  if [ -d "$PLANNING_DIR/milestones" ]; then
    for _ms_dir in "$PLANNING_DIR"/milestones/*/; do
      [ -f "${_ms_dir}STATE.md" ] && _skills_state_files="$_skills_state_files ${_ms_dir}STATE.md"
    done
  fi

  _skills_strip_ok=true
  for _sf in $_skills_state_files; do
    if grep -q '^### Skills' "$_sf" 2>/dev/null; then
      # Remove ### Skills and its content (up to next ### or ## heading)
      if awk '
        /^### Skills/ { skip=1; next }
        skip && /^###?#? / { skip=0 }
        skip==0 { print }
      ' "$_sf" > "${_sf}.tmp" 2>/dev/null && mv "${_sf}.tmp" "$_sf" 2>/dev/null; then
        : # success
      else
        rm -f "${_sf}.tmp" 2>/dev/null || true
        _skills_strip_ok=false
      fi
    fi
  done

  if [ "$_skills_strip_ok" = true ]; then
    echo "1" > "$PLANNING_DIR/.skills-section-stripped" 2>/dev/null || true
  fi
fi

# --- Brownfield: detect SUMMARY.md files without valid completion status ---
# Projects bootstrapped before status-aware detection may have SUMMARY files
# that were created empty (touch) or with non-terminal statuses. Warn so users
# know these plans won't be counted as complete under the new detection.
_bf_bad_summary_count=0
if [ -d "$PLANNING_DIR/phases" ]; then
  for _bf_phase_dir in "$PLANNING_DIR"/phases/*/; do
    [ -d "$_bf_phase_dir" ] || continue
    for _bf_sf in "$_bf_phase_dir"*-SUMMARY.md; do
      [ -f "$_bf_sf" ] || continue
      if ! is_summary_complete "$_bf_sf"; then
        _bf_bad_summary_count=$((_bf_bad_summary_count + 1))
      fi
    done
  done
fi

# --- Session-level config cache (performance optimization, REQ-01 #9) ---
# Write commonly-read config flags to a flat file for fast sourcing.
# Invalidation: overwritten every session start. Scripts can opt-in:
#   [ -f /tmp/vbw-config-cache-$(id -u) ] && source /tmp/vbw-config-cache-$(id -u)
VBW_CONFIG_CACHE="/tmp/vbw-config-cache-$(id -u)"
if [ -d "$PLANNING_DIR" ] && [ -f "$PLANNING_DIR/config.json" ] && command -v jq &>/dev/null; then
  jq -r '
    "VBW_EFFORT=\(.effort // "balanced")",
    "VBW_AUTONOMY=\(.autonomy // "standard")",
    "VBW_PLANNING_TRACKING=\(.planning_tracking // "manual")",
    "VBW_AUTO_PUSH=\(.auto_push // "never")",
    "VBW_CONTEXT_COMPILER=\(if .context_compiler == null then true else .context_compiler end)"
  ' "$PLANNING_DIR/config.json" > "$VBW_CONFIG_CACHE" 2>/dev/null || true
fi

# --- Flag dependency validation (REQ-01) ---
FLAG_WARNINGS=""
if [ -d "$PLANNING_DIR" ] && [ -f "$PLANNING_DIR/config.json" ]; then
  # v2_hard_gates/v2_hard_contracts dependency removed - both are now always-on
  true
fi

# Compaction marker cleanup moved to the early-exit check above and to post-compact.sh

UPDATE_MSG=""

# Append brownfield SUMMARY warning if any non-complete files were found
if [ "$_bf_bad_summary_count" -gt 0 ]; then
  UPDATE_MSG="${UPDATE_MSG} BROWNFIELD: ${_bf_bad_summary_count} SUMMARY.md file(s) lack valid completion status (missing 'status: complete' in YAML frontmatter). These plans will not be counted as complete. Fix by adding frontmatter or re-execute with /vbw:vibe."
fi

# --- First-run welcome (DXP-03) ---
VBW_MARKER="$CLAUDE_DIR/.vbw-welcomed"
WELCOME_MSG=""
if [ ! -f "$VBW_MARKER" ]; then
  mkdir -p "$CLAUDE_DIR" 2>/dev/null
  touch "$VBW_MARKER" 2>/dev/null
  WELCOME_MSG="FIRST RUN -- Display this welcome to the user verbatim: Welcome to VBW -- Vibe Better with Claude Code. You're not an engineer anymore. You're a prompt jockey with commit access. At least do it properly. Quick start: /vbw:vibe -- describe your project and VBW handles the rest. Type /vbw:help for the full story. --- "
fi

# --- Update check (once per day, fail-silent) ---

CACHE="/tmp/vbw-update-check-$(id -u)"
NOW=$(date +%s)
if [ "$(uname)" = "Darwin" ]; then
  MT=$(stat -f %m "$CACHE" 2>/dev/null || echo 0)
else
  MT=$(stat -c %Y "$CACHE" 2>/dev/null || echo 0)
fi

if [ ! -f "$CACHE" ] || [ $((NOW - MT)) -gt 86400 ]; then
  # Get installed version from plugin.json next to this script
  LOCAL_VER=$(jq -r '.version // "0.0.0"' "$SCRIPT_DIR/../.claude-plugin/plugin.json" 2>/dev/null)

  # Fetch latest version from GitHub (3s timeout)
  REMOTE_VER=$(curl -sf --max-time 3 \
    "https://raw.githubusercontent.com/yidakee/vibe-better-with-claude-code-vbw/main/.claude-plugin/plugin.json" \
    2>/dev/null | jq -r '.version // "0.0.0"' 2>/dev/null)

  # Cache the result regardless
  echo "${LOCAL_VER:-0.0.0}|${REMOTE_VER:-0.0.0}" > "$CACHE" 2>/dev/null

  if [ -n "$REMOTE_VER" ] && [ "$REMOTE_VER" != "0.0.0" ] && [ "$REMOTE_VER" != "$LOCAL_VER" ]; then
    UPDATE_MSG=" UPDATE AVAILABLE: v${LOCAL_VER} -> v${REMOTE_VER}. Run /vbw:update to upgrade."
  fi
else
  # Read cached result
  LOCAL_VER="" REMOTE_VER=""
  IFS='|' read -r LOCAL_VER REMOTE_VER < "$CACHE" 2>/dev/null || true
  if [ -n "${REMOTE_VER:-}" ] && [ "${REMOTE_VER:-}" != "0.0.0" ] && [ "${REMOTE_VER:-}" != "${LOCAL_VER:-}" ]; then
    UPDATE_MSG=" UPDATE AVAILABLE: v${LOCAL_VER:-0.0.0} -> v${REMOTE_VER:-0.0.0}. Run /vbw:update to upgrade."
  fi
fi

# --- Migrate statusLine if using old for-loop pattern ---
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
  SL_CMD=$(jq -r '.statusLine.command // .statusLine // ""' "$SETTINGS_FILE" 2>/dev/null)
  if echo "$SL_CMD" | grep -q 'for f in' && echo "$SL_CMD" | grep -q 'vbw-statusline'; then
    CORRECT_CMD="bash -c 'for _d in \"\${CLAUDE_CONFIG_DIR:-}\" \"\$HOME/.config/claude-code\" \"\$HOME/.claude\"; do [ -z \"\$_d\" ] && continue; f=\$(ls -1 \"\$_d\"/plugins/cache/vbw-marketplace/vbw/*/scripts/vbw-statusline.sh 2>/dev/null | sort -V | tail -1 || true); [ -f \"\$f\" ] && exec bash \"\$f\"; done'"
    cp "$SETTINGS_FILE" "${SETTINGS_FILE}.bak"
    if ! jq --arg cmd "$CORRECT_CMD" '.statusLine = {"type": "command", "command": $cmd}' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"; then
      cp "${SETTINGS_FILE}.bak" "$SETTINGS_FILE"
      rm -f "${SETTINGS_FILE}.tmp"
    else
      mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    fi
    rm -f "${SETTINGS_FILE}.bak"
  fi
fi

# --- tmux Forced In-Process Removal ---
# Previous workaround forced in-process mode in tmux. Claude Code now supports
# tmux split-pane mode natively ("auto" uses split panes inside tmux).
# Restore "auto" if we previously patched it to "in-process".
if [ -f "$SETTINGS_FILE" ]; then
  CURRENT_MODE=$(jq -r '.teammateMode // "auto"' "$SETTINGS_FILE" 2>/dev/null)
  if [ "$CURRENT_MODE" = "in-process" ]; then
    # Restore to "auto" so tmux gets split panes, non-tmux gets inline
    cp "$SETTINGS_FILE" "${SETTINGS_FILE}.bak"
    if jq '.teammateMode = "auto"' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"; then
      mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
      rm -f "${SETTINGS_FILE}.bak"
    else
      cp "${SETTINGS_FILE}.bak" "$SETTINGS_FILE" 2>/dev/null || true
      rm -f "${SETTINGS_FILE}.tmp" "${SETTINGS_FILE}.bak"
    fi
  fi
  # Clean up stale marker from old workaround
  rm -f "$PLANNING_DIR/.tmux-mode-patched" 2>/dev/null || true
fi

# --- Local dev bridge: populate cache for template resolution ---
# When loaded via --plugin-dir (local dev mode), CLAUDE_PLUGIN_ROOT is set but
# the marketplace cache is empty. Template-level backtick expansions resolve the
# plugin root via the cache glob, which fails without a cache entry. Bridge the
# gap by symlinking CLAUDE_PLUGIN_ROOT into the cache directory. This enables
# the same resolution path as marketplace installs.
CACHE_DIR="$CLAUDE_DIR/plugins/cache/vbw-marketplace/vbw"
MKT_DIR="$CLAUDE_DIR/plugins/marketplaces/vbw-marketplace"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "$CLAUDE_PLUGIN_ROOT" ]; then
  if ! ls -d "$CACHE_DIR"/*/ >/dev/null 2>&1; then
    mkdir -p "$CACHE_DIR"
    ln -sfn "$CLAUDE_PLUGIN_ROOT" "$CACHE_DIR/local"
  fi
else
  # Not in local dev mode — remove stale local symlink to prevent prod sessions
  # from silently resolving scripts from a developer's repo checkout.
  if [ -L "$CACHE_DIR/local" ]; then
    rm -f "$CACHE_DIR/local"
  fi
  # If cache is empty in prod mode but marketplace checkout exists, seed a
  # low-priority fallback cache entry so resolution paths stay functional.
  # Name it 0.0.0-* so any real semver cache wins when present.
  if ! ls -d "$CACHE_DIR"/*/ >/dev/null 2>&1 && [ -d "$MKT_DIR/.claude-plugin" ]; then
    mkdir -p "$CACHE_DIR"
    ln -sfn "$MKT_DIR" "$CACHE_DIR/0.0.0-marketplace"
  fi
fi

# --- Clean old cache versions (keep only latest) ---
VBW_CLEANUP_LOCK="/tmp/vbw-cache-cleanup-lock"
if [ -d "$CACHE_DIR" ] && mkdir "$VBW_CLEANUP_LOCK" 2>/dev/null; then
  VERSIONS=$(ls -d "$CACHE_DIR"/*/ 2>/dev/null | sort -V)
  COUNT=$(echo "$VERSIONS" | wc -l | tr -d ' ')
  if [ "$COUNT" -gt 1 ]; then
    echo "$VERSIONS" | head -n $((COUNT - 1)) | while IFS= read -r dir; do
      [ -L "${dir%/}" ] && continue  # Skip local dev symlinks
      rm -rf "$dir"
    done
  fi
  rmdir "$VBW_CLEANUP_LOCK" 2>/dev/null
fi

# --- Cache integrity check (nuke if critical files missing) ---
# Skip integrity check for local dev symlinks — the live repo is always current.
if [ -d "$CACHE_DIR" ]; then
  LATEST_CACHE=$(ls -d "$CACHE_DIR"/*/ 2>/dev/null | sort -V | tail -1)
  if [ -n "$LATEST_CACHE" ] && [ ! -L "${LATEST_CACHE%/}" ]; then
    INTEGRITY_OK=true
    for f in commands/init.md .claude-plugin/plugin.json VERSION config/defaults.json; do
      if [ ! -f "$LATEST_CACHE$f" ]; then
        INTEGRITY_OK=false
        break
      fi
    done
    if [ "$INTEGRITY_OK" = false ]; then
      echo "VBW cache integrity check failed — nuking stale cache" >&2
      rm -rf "$CACHE_DIR"
    fi
  fi
fi

# --- Auto-sync stale marketplace checkout ---
_CACHE_LATEST=$(ls -d "$CACHE_DIR"/*/ 2>/dev/null | sort -V | tail -1)
if [ -d "$MKT_DIR/.git" ] && [ -d "$CACHE_DIR" ]; then
  # Skip version-driven sync when latest cache entry is a local dev symlink —
  # local repo version differences should not drive marketplace checkout behavior.
  if [ -n "$_CACHE_LATEST" ] && [ ! -L "${_CACHE_LATEST%/}" ]; then
    MKT_VER=$(jq -r '.version // "0"' "$MKT_DIR/.claude-plugin/plugin.json" 2>/dev/null)
    CACHE_VER=$(jq -r '.version // "0"' "${_CACHE_LATEST}.claude-plugin/plugin.json" 2>/dev/null)
    if [ "$MKT_VER" != "$CACHE_VER" ] && [ -n "$CACHE_VER" ] && [ "$CACHE_VER" != "0" ]; then
      (cd "$MKT_DIR" && git fetch origin --quiet 2>/dev/null && \
        if git diff --quiet 2>/dev/null; then
          git merge --ff-only origin/main --quiet 2>/dev/null
        else
          echo "VBW: marketplace checkout has local modifications — skipping reset" >&2
        fi) &
    fi
  fi
  # Content staleness: compare command counts
  if [ -d "$MKT_DIR/commands" ] && [ -d "$CACHE_DIR" ]; then
    if [ -n "$_CACHE_LATEST" ] && [ -d "${_CACHE_LATEST}commands" ] && [ ! -L "${_CACHE_LATEST%/}" ]; then
      # Skip staleness check for local dev symlinks — command counts differ during development.
      # zsh compat: bare globs error before ls runs in zsh (nomatch). Use ls dir | grep.
      # shellcheck disable=SC2010
      MKT_CMD_COUNT=$(ls -1 "$MKT_DIR/commands/" 2>/dev/null | grep '\.md$' | wc -l | tr -d ' ')
      # shellcheck disable=SC2010
      CACHE_CMD_COUNT=$(ls -1 "${_CACHE_LATEST}commands/" 2>/dev/null | grep '\.md$' | wc -l | tr -d ' ')
      if [ "${MKT_CMD_COUNT:-0}" -ne "${CACHE_CMD_COUNT:-0}" ]; then
        echo "VBW cache stale — marketplace has ${MKT_CMD_COUNT} commands, cache has ${CACHE_CMD_COUNT}" >&2
        rm -rf "$CACHE_DIR"
        _CACHE_LATEST=""
      fi
    fi
  fi
fi

# --- Sync global commands mirror for vbw: prefix in autocomplete ---
VBW_GLOBAL_CMD="$CLAUDE_DIR/commands/vbw"
CACHED_VER="$_CACHE_LATEST"
if [ -n "$CACHED_VER" ] && [ -d "${CACHED_VER}commands" ]; then
  mkdir -p "$VBW_GLOBAL_CMD"
  # Remove stale commands not in cache, then copy fresh
  if [ -d "$VBW_GLOBAL_CMD" ]; then
    for f in "$VBW_GLOBAL_CMD"/*.md; do
      [ -f "$f" ] || continue
      base=$(basename "$f")
      [ -f "${CACHED_VER}commands/$base" ] || rm -f "$f"
    done
  fi
  cp "${CACHED_VER}commands/"*.md "$VBW_GLOBAL_CMD/" 2>/dev/null
fi

# --- Auto-install git hooks if missing ---
PROJECT_GIT_DIR=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_GIT_DIR=""
if [ -n "$PROJECT_GIT_DIR" ] && [ ! -f "$PROJECT_GIT_DIR/.git/hooks/pre-push" ] && [ -f "$SCRIPT_DIR/install-hooks.sh" ]; then
  (bash "$SCRIPT_DIR/install-hooks.sh" 2>/dev/null) || true
fi

# --- Auto-recover stale execution state (event_recovery gate) ---
# If event-log.jsonl is newer than .execution-state.json (or state is missing
# while events exist), call recover-state.sh to rebuild the state file.
# Gates on event_recovery config flag (recover-state.sh checks internally too).
_auto_recovered=false
if [ -d "$PLANNING_DIR" ] && [ -f "$PLANNING_DIR/config.json" ]; then
  _er_flag=$(jq -r 'if .event_recovery != null then .event_recovery elif .v3_event_recovery != null then .v3_event_recovery else false end' "$PLANNING_DIR/config.json" 2>/dev/null || echo "false")
  _events_file="$PLANNING_DIR/.events/event-log.jsonl"

  # Fix QA#3: require non-empty event log — -s plus grep for actual content
  # (a file with only whitespace/newlines passes -s but has no events)
  if [ "$_er_flag" = "true" ] && [ -s "$_events_file" ] && grep -q '[^[:space:]]' "$_events_file" 2>/dev/null; then
    _exec_state="$PLANNING_DIR/.execution-state.json"
    _needs_recovery=false

    if [ ! -f "$_exec_state" ]; then
      # State missing but events exist — recover
      _needs_recovery=true
    else
      # Compare mtimes: recover if event log is strictly newer
      if [ "$(uname)" = "Darwin" ]; then
        _mt_state=$(stat -f %m "$_exec_state" 2>/dev/null || echo 0)
        _mt_events=$(stat -f %m "$_events_file" 2>/dev/null || echo 0)
      else
        _mt_state=$(stat -c %Y "$_exec_state" 2>/dev/null || echo 0)
        _mt_events=$(stat -c %Y "$_events_file" 2>/dev/null || echo 0)
      fi
      if [ "$_mt_events" -gt "$_mt_state" ] 2>/dev/null; then
        _needs_recovery=true
      fi
    fi

    if [ "$_needs_recovery" = true ]; then
      # Determine current phase from STATE.md
      _phase_num=""
      if [ -f "$PLANNING_DIR/STATE.md" ]; then
        _phase_line=$(grep -m1 "^Phase:" "$PLANNING_DIR/STATE.md" 2>/dev/null || true)
        _phase_num=$(echo "$_phase_line" | sed 's/Phase: *\([0-9]*\).*/\1/')
      fi

      # Fix QA#1: fallback to .execution-state.json phase, then artifact/event-based detection
      if ! [ -n "$_phase_num" ] 2>/dev/null || ! [ "$_phase_num" -gt 0 ] 2>/dev/null; then
        _phase_num=""
        # Try existing execution state
        if [ -f "$_exec_state" ]; then
          _exec_phase=$(jq -r '.phase // ""' "$_exec_state" 2>/dev/null || true)
          if [ -n "$_exec_phase" ] && [ "$_exec_phase" -gt 0 ] 2>/dev/null; then
            _exec_phase_dir=$(find_phase_dir_by_num "$PLANNING_DIR" "$_exec_phase")
            if phase_dir_has_plans "$_exec_phase_dir"; then
              _phase_num="$_exec_phase"
            fi
          fi
        fi
        # Still empty? Choose from events/artifacts rather than max numeric phase.
        if ! [ -n "$_phase_num" ] 2>/dev/null || ! [ "$_phase_num" -gt 0 ] 2>/dev/null; then
          _phase_num=$(pick_recovery_phase "$PLANNING_DIR" "$_events_file")
        fi
      fi

      if [ -n "$_phase_num" ] && [ "$_phase_num" -gt 0 ] 2>/dev/null; then
        _recovered=$(bash "$SCRIPT_DIR/recover-state.sh" "$_phase_num" "$PLANNING_DIR/phases" 2>/dev/null)
        # Only write if we got a non-empty, non-{} result
        if [ -n "$_recovered" ] && [ "$_recovered" != "{}" ]; then
          # Fix QA#2: validate recovered phase matches requested phase and has plans
          _recovered_phase=$(echo "$_recovered" | jq -r '.phase // 0' 2>/dev/null || echo 0)
          _recovered_plan_count=$(echo "$_recovered" | jq -r '.plans | length // 0' 2>/dev/null || echo 0)
          if [ "$_recovered_phase" = "$_phase_num" ] && [ "${_recovered_plan_count:-0}" -gt 0 ] 2>/dev/null; then
            if atomic_write_string "$PLANNING_DIR/.execution-state.json" "$_recovered"; then
              _auto_recovered=true
            fi
          fi
        fi
      fi
    fi
  fi
fi

# --- Reconcile orphaned execution state ---
# Fix QA#4: skip reconcile if auto-recovery already wrote state this session
EXEC_STATE="$PLANNING_DIR/.execution-state.json"
if [ "$_auto_recovered" = false ] && [ -f "$EXEC_STATE" ]; then
  EXEC_STATUS=$(jq -r '.status // ""' "$EXEC_STATE" 2>/dev/null)
  if [ "$EXEC_STATUS" = "running" ]; then
    PHASE_NUM=$(jq -r '.phase // ""' "$EXEC_STATE" 2>/dev/null)
    PHASE_DIR=""
    if [ -n "$PHASE_NUM" ]; then
      PHASE_DIR=$(find_phase_dir_by_num "$PLANNING_DIR" "$PHASE_NUM")
    fi
    if [ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ]; then
      PLAN_COUNT=$(jq -r '.plans | length' "$EXEC_STATE" 2>/dev/null)
      # zsh compat: use ls dir | grep to avoid bare glob expansion errors
      # shellcheck disable=SC2010
      SUMMARY_COUNT=0
      STRICT_COMPLETE=0
      for _ss_sf in "$PHASE_DIR"/*-SUMMARY.md; do
        [ -f "$_ss_sf" ] || continue
        _ss_st=$(sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' "$_ss_sf" 2>/dev/null | head -1 | tr -d '[:space:]')
        case "$_ss_st" in
          complete|completed) SUMMARY_COUNT=$((SUMMARY_COUNT + 1)); STRICT_COMPLETE=$((STRICT_COMPLETE + 1)) ;;
          partial) SUMMARY_COUNT=$((SUMMARY_COUNT + 1)) ;;
        esac
      done

      # Reconcile individual plan statuses against actual SUMMARY.md files.
      # After a reset/undo, .execution-state.json may have stale "complete"
      # entries for plans whose SUMMARY.md no longer exists on disk.
      _json_done=$(jq -r '[.plans[]? | select(.status == "complete" or .status == "partial")] | length' "$EXEC_STATE" 2>/dev/null || echo 0)
      if [ "${_json_done:-0}" -gt "${SUMMARY_COUNT:-0}" ] 2>/dev/null; then
        # Build JSON array of plan IDs that actually have completed SUMMARY.md
        _completed_json="[]"
        for _sf in "$PHASE_DIR"/*-SUMMARY.md; do
          [ -f "$_sf" ] || continue
          _sf_st=$(sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' "$_sf" 2>/dev/null | head -1 | tr -d '[:space:]')
          case "$_sf_st" in
            complete|completed|partial)
              _sf_id=$(basename "$_sf" | sed 's/-SUMMARY\.md$//')
              _completed_json=$(echo "$_completed_json" | jq --arg id "$_sf_id" '. + [$id]')
              ;;
          esac
        done
        # Reset plans to "pending" if their SUMMARY.md is missing on disk
        _reconcile_tmp="${EXEC_STATE}.reconcile.$$"
        jq --argjson completed "$_completed_json" '
          .plans |= map(
            if (.status == "complete" or .status == "partial") and (.id as $pid | $completed | any(. == $pid) | not) then
              .status = "pending"
            else .
            end
          )
        ' "$EXEC_STATE" > "$_reconcile_tmp" 2>/dev/null && mv "$_reconcile_tmp" "$EXEC_STATE" 2>/dev/null || rm -f "$_reconcile_tmp" 2>/dev/null
      fi

      if [ "${STRICT_COMPLETE:-0}" -ge "${PLAN_COUNT:-1}" ] && [ "${PLAN_COUNT:-0}" -gt 0 ]; then
        # All plans are strictly complete — build finished after crash
        _exec_tmp="${EXEC_STATE}.tmp.$$"
        if jq '.status = "complete"' "$EXEC_STATE" > "$_exec_tmp" 2>/dev/null && mv "$_exec_tmp" "$EXEC_STATE" 2>/dev/null; then
          :
        else
          rm -f "$_exec_tmp" 2>/dev/null || true
        fi
        BUILD_STATE="complete (recovered)"
      else
        BUILD_STATE="interrupted (${SUMMARY_COUNT:-0}/${PLAN_COUNT:-0} plans)"
      fi
      UPDATE_MSG="${UPDATE_MSG} Build state: ${BUILD_STATE}."
    fi
  fi
fi

# --- Orphan Agent Cleanup ---
# Detect and terminate orphaned claude processes (PPID=1) from crashed sessions.
# These processes can consume up to 30GB each and accumulate indefinitely.
# Only processes with PPID=1 (init-adopted, truly orphaned) are targeted.
# Cross-platform: macOS uses BSD ps, Linux uses GNU ps.

cleanup_orphaned_agents() {
  # Graceful degradation: skip if ps command unavailable
  if ! command -v ps >/dev/null 2>&1; then
    return 0
  fi

  local orphan_pids=""
  local current_session_pid=$$

  # Detect claude processes with PPID=1 (orphaned, adopted by init)
  # Platform-specific ps syntax
  if [ "$(uname)" = "Darwin" ]; then
    # macOS: BSD ps syntax
    orphan_pids=$(ps -eo pid,ppid,comm 2>/dev/null | awk '$2 == 1 && $3 ~ /claude/ {print $1}' || true)
  else
    # Linux: GNU ps syntax
    orphan_pids=$(ps -eo pid,ppid,comm 2>/dev/null | awk '$2 == 1 && $3 ~ /claude/ {print $1}' || true)
  fi

  # Validate PIDs are numeric and exclude current session
  local validated_pids=""
  for pid in $orphan_pids; do
    # Numeric validation
    if ! echo "$pid" | grep -qE '^[0-9]+$'; then
      continue
    fi
    # Skip current session's own process
    if [ "$pid" = "$current_session_pid" ]; then
      continue
    fi
    validated_pids="$validated_pids $pid"
  done

  # No orphans found
  if [ -z "$validated_pids" ]; then
    return 0
  fi

  # Log orphan detection
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")
  local orphan_count
  orphan_count=$(echo "$validated_pids" | wc -w | tr -d ' ')
  echo "[$timestamp] Orphan cleanup: found $orphan_count orphaned claude process(es)" >> "$PLANNING_DIR/.hook-errors.log" 2>/dev/null || true

  # Terminate with SIGTERM (graceful)
  for pid in $validated_pids; do
    if kill -0 "$pid" 2>/dev/null; then
      echo "[$timestamp] Terminating orphan claude process PID=$pid (SIGTERM)" >> "$PLANNING_DIR/.hook-errors.log" 2>/dev/null || true
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done

  # Wait 2 seconds for graceful shutdown
  sleep 2

  # SIGKILL fallback for survivors
  for pid in $validated_pids; do
    if kill -0 "$pid" 2>/dev/null; then
      echo "[$timestamp] Orphan claude process PID=$pid survived SIGTERM, sending SIGKILL" >> "$PLANNING_DIR/.hook-errors.log" 2>/dev/null || true
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done

  return 0
}

# Run cleanup if not in compaction mode and planning directory exists
if [ -d "$PLANNING_DIR" ]; then
  cleanup_orphaned_agents || true
fi

# --- Prune Dead PIDs ---
# Remove stale entries from .agent-pids to prevent unbounded growth across milestones.
if [ -d "$PLANNING_DIR" ] && [ -f "$SCRIPT_DIR/agent-pid-tracker.sh" ]; then
  bash "$SCRIPT_DIR/agent-pid-tracker.sh" prune 2>/dev/null || true
fi

# --- Stale Team Cleanup ---
if [ -d "$PLANNING_DIR" ] && [ -f "$SCRIPT_DIR/clean-stale-teams.sh" ]; then
  bash "$SCRIPT_DIR/clean-stale-teams.sh" 2>/dev/null || true
fi

# --- Stale .agent-last-words Cleanup ---
# Remove crash recovery files older than 7 days to prevent accumulation.
# BSD find -mtime +N (no units) requires age >= N+2 days, so +6 matches >= 8 days.
if [ -d "$PLANNING_DIR/.agent-last-words" ]; then
  find "$PLANNING_DIR/.agent-last-words" -name "*.txt" -type f -mtime +6 -delete 2>/dev/null || true
fi

# --- tmux Detach Watchdog ---
# Launch watchdog when in tmux to cleanup orphaned agents on detach.
# Watchdog runs in background and monitors for session detachment.
if [ -n "${TMUX:-}" ] && [ -d "$PLANNING_DIR" ]; then
  WATCHDOG_PID_FILE="$PLANNING_DIR/.watchdog-pid"

  # Check if watchdog already running
  EXISTING_WATCHDOG=""
  if [ -f "$WATCHDOG_PID_FILE" ]; then
    EXISTING_WATCHDOG=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null || true)
    # Validate it's still alive
    if [ -n "$EXISTING_WATCHDOG" ] && ! kill -0 "$EXISTING_WATCHDOG" 2>/dev/null; then
      EXISTING_WATCHDOG=""  # Dead, will respawn
      rm -f "$WATCHDOG_PID_FILE" 2>/dev/null || true
    fi
  fi

  # Spawn watchdog if not running
  if [ -z "$EXISTING_WATCHDOG" ] && [ -f "$SCRIPT_DIR/tmux-watchdog.sh" ]; then
    # Extract session name from $TMUX
    SESSION=$(tmux display-message -p '#S' 2>/dev/null || true)
    if [ -n "$SESSION" ]; then
      # Launch in background, disown to survive session-start exit
      bash "$SCRIPT_DIR/tmux-watchdog.sh" "$SESSION" >/dev/null 2>&1 &
      WATCHDOG_PID=$!
      echo "$WATCHDOG_PID" > "$WATCHDOG_PID_FILE"
      # Disown to prevent job control messages
      disown "$WATCHDOG_PID" 2>/dev/null || true
    fi
  fi
fi

# --- Project state ---

if [ ! -d "$PLANNING_DIR" ]; then
  jq -n --arg update "$UPDATE_MSG" --arg welcome "$WELCOME_MSG" '{
    "hookSpecificOutput": {
      "hookEventName": "SessionStart",
      "additionalContext": ($welcome + "No .vbw-planning/ directory found. Run /vbw:init to set up the project." + $update)
    }
  }'
  exit 0
fi

# --- Root-canonical paths (no ACTIVE indirection) ---
MILESTONE_DIR="$PLANNING_DIR"

# --- Shipped milestones detection ---
has_shipped="false"
if [ -d "$PLANNING_DIR/milestones" ]; then
  for _ms in "$PLANNING_DIR"/milestones/*/; do
    [ -f "${_ms}SHIPPED.md" ] && has_shipped="true" && break
  done
fi

# --- Parse config ---
CONFIG_FILE="$PLANNING_DIR/config.json"
config_effort="balanced"
config_autonomy="standard"
config_auto_commit="true"
config_planning_tracking="manual"
config_auto_push="never"
config_verification="standard"
config_prefer_teams="auto"
config_max_tasks="5"
if [ -f "$CONFIG_FILE" ]; then
  config_effort=$(jq -r '.effort // "balanced"' "$CONFIG_FILE" 2>/dev/null)
  config_autonomy=$(jq -r '.autonomy // "standard"' "$CONFIG_FILE" 2>/dev/null)
  config_auto_commit=$(jq -r 'if .auto_commit == null then true else .auto_commit end' "$CONFIG_FILE" 2>/dev/null)
  config_planning_tracking=$(jq -r '.planning_tracking // "manual"' "$CONFIG_FILE" 2>/dev/null)
  config_auto_push=$(jq -r '.auto_push // "never"' "$CONFIG_FILE" 2>/dev/null)
  config_verification=$(jq -r '.verification_tier // "standard"' "$CONFIG_FILE" 2>/dev/null)
  config_prefer_teams=$(jq -r '.prefer_teams // "auto"' "$CONFIG_FILE" 2>/dev/null)
  config_max_tasks=$(jq -r '.max_tasks_per_plan // 5' "$CONFIG_FILE" 2>/dev/null)
fi

# --- Parse STATE.md ---
STATE_FILE="$MILESTONE_DIR/STATE.md"
phase_pos="unknown"
phase_total="unknown"
phase_name="unknown"
phase_status="unknown"
progress_pct="0"
if [ -f "$STATE_FILE" ]; then
  # Extract "Phase: N of M (name)" from "Phase: 1 of 3 (Context Diet)"
  phase_line=$(grep -m1 "^Phase:" "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$phase_line" ]; then
    phase_pos=$(echo "$phase_line" | sed -n 's/^Phase:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    phase_total=$(echo "$phase_line" | sed -n 's/.*[[:space:]]of[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    phase_name=$(echo "$phase_line" | sed -n 's/.*(\(.*\))/\1/p')
  fi
  # Extract status line
  status_line=$(grep -m1 "^Status:" "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$status_line" ]; then
    phase_status=$(echo "$status_line" | sed 's/Status: *//')
  fi
  # Extract progress percentage
  progress_line=$(grep -m1 "^Progress:" "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$progress_line" ]; then
    progress_pct=$(echo "$progress_line" | grep -o '[0-9]*%' | tr -d '%')
  fi
fi
: "${phase_pos:=unknown}"
: "${phase_total:=unknown}"
: "${phase_name:=unknown}"
: "${phase_status:=unknown}"
: "${progress_pct:=0}"

# --- Determine next action ---
NEXT_ACTION=""

# Use phase-detect.sh as the canonical source for phase and milestone UAT routing.
PHASE_DETECT_OUT=$(bash "$SCRIPT_DIR/phase-detect.sh" 2>/dev/null || true)
PD_NEXT_PHASE_STATE=$(echo "$PHASE_DETECT_OUT" | grep -m1 '^next_phase_state=' | sed 's/^[^=]*=//' || true)
PD_NEXT_PHASE=$(echo "$PHASE_DETECT_OUT" | grep -m1 '^next_phase=' | sed 's/^[^=]*=//' || true)
PD_UAT_ISSUES_PHASE=$(echo "$PHASE_DETECT_OUT" | grep -m1 '^uat_issues_phase=' | sed 's/^[^=]*=//' || true)
PD_MILESTONE_UAT_ISSUES=$(echo "$PHASE_DETECT_OUT" | grep -m1 '^milestone_uat_issues=' | sed 's/^[^=]*=//' || true)
PD_MILESTONE_UAT_PHASE=$(echo "$PHASE_DETECT_OUT" | grep -m1 '^milestone_uat_phase=' | sed 's/^[^=]*=//' || true)
PD_MILESTONE_UAT_SLUG=$(echo "$PHASE_DETECT_OUT" | grep -m1 '^milestone_uat_slug=' | sed 's/^[^=]*=//' || true)
PD_HAS_SHIPPED=$(echo "$PHASE_DETECT_OUT" | grep -m1 '^has_shipped_milestones=' | sed 's/^[^=]*=//' || true)

PD_NEXT_PHASE_STATE=${PD_NEXT_PHASE_STATE:-unknown}
PD_NEXT_PHASE=${PD_NEXT_PHASE:-none}
PD_UAT_ISSUES_PHASE=${PD_UAT_ISSUES_PHASE:-none}
PD_MILESTONE_UAT_ISSUES=${PD_MILESTONE_UAT_ISSUES:-false}
PD_MILESTONE_UAT_PHASE=${PD_MILESTONE_UAT_PHASE:-none}
PD_MILESTONE_UAT_SLUG=${PD_MILESTONE_UAT_SLUG:-none}
PD_HAS_SHIPPED=${PD_HAS_SHIPPED:-$has_shipped}

# Keep shipped indicator aligned with phase-detect brownfield fallback semantics.
has_shipped="$PD_HAS_SHIPPED"

if [ ! -f "$PLANNING_DIR/PROJECT.md" ]; then
  NEXT_ACTION="/vbw:init"
else
  # Check execution state for interrupted builds
  EXEC_STATE="$PLANNING_DIR/.execution-state.json"
  MILESTONE_EXEC_STATE="$MILESTONE_DIR/.execution-state.json"
  exec_running=false
  for es in "$EXEC_STATE" "$MILESTONE_EXEC_STATE"; do
    if [ -f "$es" ]; then
      es_status=$(jq -r '.status // ""' "$es" 2>/dev/null)
      if [ "$es_status" = "running" ]; then
        exec_running=true
        break
      fi
    fi
  done

  if [ "$exec_running" = true ]; then
    NEXT_ACTION="/vbw:vibe (build interrupted, will resume)"
  else
    case "$PD_NEXT_PHASE_STATE" in
      needs_uat_remediation)
        NEXT_ACTION="/vbw:vibe (Phase ${PD_UAT_ISSUES_PHASE:-$PD_NEXT_PHASE} has unresolved UAT issues, continue remediation)"
        ;;
      needs_discussion)
        NEXT_ACTION="/vbw:vibe (Phase ${PD_NEXT_PHASE} needs discussion before planning)"
        ;;
      needs_plan_and_execute)
        NEXT_ACTION="/vbw:vibe (Phase ${PD_NEXT_PHASE} needs planning)"
        ;;
      needs_execute)
        NEXT_ACTION="/vbw:vibe (Phase ${PD_NEXT_PHASE} planned, needs execution)"
        ;;
      all_done|no_phases)
        if [ "$PD_MILESTONE_UAT_ISSUES" = "true" ]; then
          NEXT_ACTION="/vbw:vibe (milestone UAT recovery: ${PD_MILESTONE_UAT_SLUG} Phase ${PD_MILESTONE_UAT_PHASE})"
        elif [ "$PD_HAS_SHIPPED" = "true" ] && [ "$PD_NEXT_PHASE_STATE" = "no_phases" ]; then
          NEXT_ACTION="/vbw:vibe (all milestones shipped, start next milestone)"
        elif [ "$PD_NEXT_PHASE_STATE" = "all_done" ]; then
          NEXT_ACTION="/vbw:vibe --archive"
        else
          NEXT_ACTION="/vbw:vibe (needs scoping)"
        fi
        ;;
      *)
        NEXT_ACTION="/vbw:vibe (needs scoping)"
        ;;
    esac
  fi
fi

# --- Build additionalContext ---
CTX="VBW project detected."
CTX="$CTX Shipped milestones: ${has_shipped}."
CTX="$CTX Phase: ${phase_pos}/${phase_total} (${phase_name}) -- ${phase_status}."
CTX="$CTX Progress: ${progress_pct}%."
CTX="$CTX Config: effort=${config_effort}, autonomy=${config_autonomy}, auto_commit=${config_auto_commit}, planning_tracking=${config_planning_tracking}, auto_push=${config_auto_push}, verification=${config_verification}, prefer_teams=${config_prefer_teams}, max_tasks=${config_max_tasks}."
CTX="$CTX Next: ${NEXT_ACTION}."

# --- GSD co-installation warning ---
GSD_WARNING=""
if [ -d "${CLAUDE_DIR}/commands/gsd" ] || [ -d ".planning" ]; then
  GSD_WARNING=" WARNING: GSD plugin detected alongside VBW. Do NOT invoke any /gsd:* or Skill('gsd:*') commands during VBW workflows — they operate on .planning/ (wrong directory) and will corrupt your session state. Only use /vbw:* commands."
fi

# Brownfield cleanup: remove stale .skill-names from older versions
rm -f "$PLANNING_DIR/.skill-names" 2>/dev/null || true

# Seed statusline caches so the first dsR() call (5s timeout) finds warm
# data instead of cold-starting 20+ subprocess forks + 2 curl calls.
# Compute the same cache key that vbw-statusline.sh uses:
_SL_VER=$(cat "$SCRIPT_DIR/../VERSION" 2>/dev/null | tr -d '[:space:]')
_SL_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
if command -v md5sum &>/dev/null; then
  _SL_HASH=$(echo "$_SL_ROOT" | md5sum | cut -c1-8)
elif command -v md5 &>/dev/null; then
  _SL_HASH=$(echo "$_SL_ROOT" | md5 -q | cut -c1-8)
else
  _SL_HASH=$(printf '%s' "$_SL_ROOT" | cksum | cut -d' ' -f1)
fi
_SL_CACHE="/tmp/vbw-${_SL_VER:-0}-$(id -u)-${_SL_HASH}"

# Only seed if caches don't already exist (avoids overwriting real data mid-session).
if [ ! -f "${_SL_CACHE}-fast" ]; then
  # Map session-start.sh variables to fast cache fields.
  _ph=0; _tt=0
  [ "$phase_pos" != "unknown" ] && _ph="$phase_pos"
  [ "$phase_total" != "unknown" ] && _tt="$phase_total"
  _br=$(git branch --show-current 2>/dev/null || true)
  # Fast cache: PH|TT|EF|MP|BR|PD|PT|PPD|QA|GH_URL|GIT_STAGED|GIT_MODIFIED|GIT_AHEAD|
  #   EXEC_STATUS|EXEC_WAVE|EXEC_TWAVES|EXEC_DONE|EXEC_TOTAL|EXEC_CURRENT|
  #   AGENT_DATA|PPT|QA_COLOR|HIDE_AGENT_TMUX|COLLAPSE_AGENT_TMUX|PP_LABEL|REM_ACTIVE
  printf '%s\n' "${_ph}|${_tt}|${config_effort:-balanced}|quality|${_br:-}|0|0|0|--||0|0|0||||0|0||0|0|D|false|false|this phase|false" > "${_SL_CACHE}-fast" 2>/dev/null
fi
if [ ! -f "${_SL_CACHE}-slow" ]; then
  # Slow cache: all-default noauth stub (usage/limits show "--" until 60s rebuild)
  printf '%s\n' "0|0|0|0|-1|0|-1|0|0|noauth|||false|false" > "${_SL_CACHE}-slow" 2>/dev/null
fi
# Sentinel: prevent vbw-statusline.sh from nuking our seeded caches.
[ ! -f "${_SL_CACHE}-ok" ] && touch "${_SL_CACHE}-ok" 2>/dev/null

jq -n --arg ctx "$CTX" --arg update "$UPDATE_MSG" --arg welcome "$WELCOME_MSG" --arg flags "${FLAG_WARNINGS:-}" --arg gsd "${GSD_WARNING:-}" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": ($welcome + $ctx + $update + $flags + $gsd)
  }
}'

exit 0

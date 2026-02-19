#!/bin/bash
set -u
# suggest-compact.sh — Pre-flight context guard for heavy commands.
#
# Dynamically calculates token cost by measuring the actual files each mode
# will load (fixed reference files from plugin root + variable project files
# from .vbw-planning/), converts bytes to tokens (~5 chars/token for
# structured content), and compares against remaining context capacity.
#
# Usage: bash suggest-compact.sh <mode>
#   mode: execute|plan|verify|qa|discuss
#
# Reads:
#   .vbw-planning/.context-usage   — "used_pct|context_window_size" (cached by statusline)
#   .vbw-planning/config.json      — compaction_threshold, autonomy, effort
#   Plugin root reference files     — measured per mode
#   .vbw-planning/ project files    — measured per mode
#
# Output (stdout):
#   Empty string if context is fine, or a warning block if near capacity.

MODE="${1:-execute}"

PLANNING_DIR=".vbw-planning"
USAGE_FILE="$PLANNING_DIR/.context-usage"

# Resolve plugin root (same pattern as command templates)
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ]; then
  PLUGIN_ROOT=$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)
fi
# Fallback: script's own parent directory
if [ -z "$PLUGIN_ROOT" ] || [ ! -d "$PLUGIN_ROOT" ]; then
  PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

# Read autonomy and effort from config (no eval — safe against injection)
AUTONOMY="standard"
EFFORT="balanced"
if [ -f "$PLANNING_DIR/config.json" ] && command -v jq &>/dev/null; then
  AUTONOMY=$(jq -r '.autonomy // "standard"' "$PLANNING_DIR/config.json" 2>/dev/null) || AUTONOMY="standard"
  EFFORT=$(jq -r '.effort // "balanced"' "$PLANNING_DIR/config.json" 2>/dev/null) || EFFORT="balanced"
fi

# --- Dynamic token cost calculation ---
# Sum byte sizes of files that the mode will load, then convert to tokens.
# Chars-per-token ratio: ~5 for structured content (JSON, markdown, code).
# Baseline overhead: ~1500 tokens for template expansions (phase-detect output,
# config.json, pwd, plugin root — already loaded before this script runs).
CHARS_PER_TOKEN=5
BASELINE_OVERHEAD=1500

# Sum bytes of a list of files (skips non-existent)
sum_bytes() {
  local total=0
  for f in "$@"; do
    if [ -f "$f" ]; then
      local size
      size=$(wc -c < "$f" 2>/dev/null) || continue
      total=$((total + size))
    fi
  done
  echo "$total"
}

# Sum bytes of files matching a glob pattern in a directory
sum_glob() {
  local dir="$1" pattern="$2"
  local total=0
  # Use find to avoid glob expansion issues in empty dirs
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    local size
    size=$(wc -c < "$f" 2>/dev/null) || continue
    total=$((total + size))
  done < <(find "$dir" -maxdepth 1 -name "$pattern" -type f 2>/dev/null)
  echo "$total"
}

# Resolve effort profile filename
effort_file() {
  case "$EFFORT" in
    thorough) echo "$PLUGIN_ROOT/references/effort-profile-thorough.md" ;;
    fast)     echo "$PLUGIN_ROOT/references/effort-profile-fast.md" ;;
    turbo)    echo "$PLUGIN_ROOT/references/effort-profile-turbo.md" ;;
    *)        echo "$PLUGIN_ROOT/references/effort-profile-balanced.md" ;;
  esac
}

# Detect current/next phase directory
detect_phase_dir() {
  if [ ! -d "$PLANNING_DIR/phases" ]; then
    echo ""
    return
  fi
  # Find the first phase dir with plans but incomplete summaries,
  # or fall back to the last phase dir
  local last_dir=""
  for d in "$PLANNING_DIR"/phases/*/; do
    [ ! -d "$d" ] && continue
    last_dir="$d"
    local plans summaries
    plans=$(find "$d" -maxdepth 1 -name '*-PLAN.md' -type f 2>/dev/null | wc -l | tr -d ' ')
    summaries=$(find "$d" -maxdepth 1 -name '*-SUMMARY.md' -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$plans" -gt 0 ] && [ "$summaries" -lt "$plans" ]; then
      echo "$d"
      return
    fi
  done
  echo "${last_dir:-}"
}

PHASE_DIR=$(detect_phase_dir)
FIXED_BYTES=0
VARIABLE_BYTES=0

case "$MODE" in
  execute)
    # Fixed: execute-protocol + handoff-schemas + brand-essentials + effort + agent defs + templates
    FIXED_BYTES=$(sum_bytes \
      "$PLUGIN_ROOT/references/execute-protocol.md" \
      "$PLUGIN_ROOT/references/handoff-schemas.md" \
      "$PLUGIN_ROOT/references/vbw-brand-essentials.md" \
      "$(effort_file)" \
      "$PLUGIN_ROOT/agents/vbw-dev.md" \
      "$PLUGIN_ROOT/agents/vbw-qa.md" \
      "$PLUGIN_ROOT/references/verification-protocol.md" \
      "$PLUGIN_ROOT/templates/SUMMARY.md" \
    )
    # Variable: plans + summaries + compiled context + execution state + codebase map
    if [ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ]; then
      VARIABLE_BYTES=$(( \
        $(sum_glob "$PHASE_DIR" "*-PLAN.md") + \
        $(sum_glob "$PHASE_DIR" "*-SUMMARY.md") + \
        $(sum_bytes "$PHASE_DIR/.context-dev.md" "$PHASE_DIR/.context-qa.md") \
      ))
    fi
    # Codebase map files (if they exist)
    VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_bytes \
      "$PLANNING_DIR/codebase/CONVENTIONS.md" \
      "$PLANNING_DIR/codebase/PATTERNS.md" \
      "$PLANNING_DIR/codebase/STRUCTURE.md" \
      "$PLANNING_DIR/codebase/DEPENDENCIES.md" \
    )))
    # State files
    VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_bytes \
      "$PLANNING_DIR/STATE.md" \
      "$PLANNING_DIR/ROADMAP.md" \
      "$PLANNING_DIR/.execution-state.json" \
    )))
    ;;

  plan)
    # Fixed: lead agent + plan template
    FIXED_BYTES=$(sum_bytes \
      "$PLUGIN_ROOT/agents/vbw-lead.md" \
      "$PLUGIN_ROOT/templates/PLAN.md" \
    )
    # Variable: roadmap + requirements + context + research + codebase map
    VARIABLE_BYTES=$(sum_bytes \
      "$PLANNING_DIR/STATE.md" \
      "$PLANNING_DIR/ROADMAP.md" \
      "$PLANNING_DIR/REQUIREMENTS.md" \
    )
    if [ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ]; then
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_glob "$PHASE_DIR" "*-CONTEXT.md")))
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_glob "$PHASE_DIR" "*-RESEARCH.md")))
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_bytes "$PHASE_DIR/.context-lead.md")))
    fi
    VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_bytes \
      "$PLANNING_DIR/codebase/ARCHITECTURE.md" \
      "$PLANNING_DIR/codebase/CONCERNS.md" \
      "$PLANNING_DIR/codebase/STRUCTURE.md" \
    )))
    ;;

  verify)
    # Fixed: UAT template + brand essentials
    FIXED_BYTES=$(sum_bytes \
      "$PLUGIN_ROOT/templates/UAT.md" \
      "$PLUGIN_ROOT/references/vbw-brand-essentials.md" \
    )
    # Variable: plans + summaries + existing UAT
    VARIABLE_BYTES=$(sum_bytes "$PLANNING_DIR/STATE.md")
    if [ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ]; then
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_glob "$PHASE_DIR" "*-PLAN.md")))
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_glob "$PHASE_DIR" "*-SUMMARY.md")))
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_glob "$PHASE_DIR" "*-UAT.md")))
    fi
    ;;

  qa)
    # Fixed: qa agent + verification protocol + handoff schemas + brand essentials + effort
    FIXED_BYTES=$(sum_bytes \
      "$PLUGIN_ROOT/agents/vbw-qa.md" \
      "$PLUGIN_ROOT/references/verification-protocol.md" \
      "$PLUGIN_ROOT/references/handoff-schemas.md" \
      "$PLUGIN_ROOT/references/vbw-brand-essentials.md" \
      "$(effort_file)" \
    )
    # Variable: plans + summaries + roadmap + codebase map
    VARIABLE_BYTES=$(sum_bytes \
      "$PLANNING_DIR/STATE.md" \
      "$PLANNING_DIR/ROADMAP.md" \
    )
    if [ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ]; then
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_glob "$PHASE_DIR" "*-PLAN.md")))
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_glob "$PHASE_DIR" "*-SUMMARY.md")))
    fi
    VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_bytes \
      "$PLANNING_DIR/codebase/TESTING.md" \
      "$PLANNING_DIR/codebase/CONCERNS.md" \
      "$PLANNING_DIR/codebase/ARCHITECTURE.md" \
    )))
    ;;

  discuss)
    # Fixed: discussion engine
    FIXED_BYTES=$(sum_bytes \
      "$PLUGIN_ROOT/references/discussion-engine.md" \
    )
    # Variable: roadmap + config (already counted in baseline)
    VARIABLE_BYTES=$(sum_bytes "$PLANNING_DIR/ROADMAP.md")
    if [ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ]; then
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_glob "$PHASE_DIR" "*-CONTEXT.md")))
    fi
    ;;

  *)
    # Unknown mode: use conservative estimate from file measurement
    FIXED_BYTES=$(sum_bytes \
      "$PLUGIN_ROOT/references/execute-protocol.md" \
      "$PLUGIN_ROOT/references/handoff-schemas.md" \
    )
    VARIABLE_BYTES=$(sum_bytes "$PLANNING_DIR/STATE.md" "$PLANNING_DIR/ROADMAP.md")
    ;;
esac

TOTAL_BYTES=$((FIXED_BYTES + VARIABLE_BYTES))
EST_COST=$(( TOTAL_BYTES / CHARS_PER_TOKEN + BASELINE_OVERHEAD ))

# Read cached context usage from statusline
if [ ! -f "$USAGE_FILE" ]; then
  # No cached data yet (first command in session) — can't guard, skip silently
  exit 0
fi

IFS='|' read -r USED_PCT CTX_SIZE < "$USAGE_FILE" 2>/dev/null || exit 0

# Validate
if ! [[ "${USED_PCT:-}" =~ ^[0-9]+$ ]] || ! [[ "${CTX_SIZE:-}" =~ ^[0-9]+$ ]]; then
  exit 0
fi

[ "$CTX_SIZE" -eq 0 ] && exit 0

# Calculate remaining tokens
REMAINING=$(( CTX_SIZE * (100 - USED_PCT) / 100 ))

# Read compaction_threshold from config if available (override safety margin)
THRESHOLD=""
if [ -f "$PLANNING_DIR/config.json" ] && command -v jq &>/dev/null; then
  THRESHOLD=$(jq -r '.compaction_threshold // empty' "$PLANNING_DIR/config.json" 2>/dev/null)
fi

# Determine the warning threshold: remaining must exceed estimated cost + buffer.
# Buffer = 15% of estimated cost (allow room for the workflow to breathe).
NEEDED=$(( EST_COST + EST_COST * 15 / 100 ))

# If compaction_threshold is set, also check: used tokens must stay below it after load.
USED_TOKENS=$(( CTX_SIZE * USED_PCT / 100 ))
THRESHOLD_EXCEEDED=false
if [[ "${THRESHOLD:-}" =~ ^[0-9]+$ ]] && [ "$THRESHOLD" -gt 0 ]; then
  PROJECTED=$(( USED_TOKENS + EST_COST ))
  if [ "$PROJECTED" -gt "$THRESHOLD" ]; then
    THRESHOLD_EXCEEDED=true
  fi
fi

if [ "$REMAINING" -lt "$NEEDED" ] || [ "$THRESHOLD_EXCEEDED" = true ]; then
  # Emit warning
  if [ "$AUTONOMY" = "confident" ] || [ "$AUTONOMY" = "pure-vibe" ]; then
    cat <<EOF
⚠ **PRE-FLIGHT CONTEXT GUARD:** Context window is at ${USED_PCT}% (${REMAINING} tokens remaining). This ${MODE} workflow needs ~${EST_COST} tokens of headroom (${FIXED_BYTES}B fixed + ${VARIABLE_BYTES}B project files). Running /compact now to prevent mid-workflow compaction.

**ACTION REQUIRED:** Run /compact before proceeding with this workflow. Auto-compacting now because autonomy is set to ${AUTONOMY}.
EOF
  else
    cat <<EOF
⚠ **PRE-FLIGHT CONTEXT GUARD:** Context window is at ${USED_PCT}% (~${REMAINING} tokens remaining). This ${MODE} workflow needs ~${EST_COST} tokens of headroom (${FIXED_BYTES}B fixed + ${VARIABLE_BYTES}B project files). Starting now risks mid-workflow auto-compaction, which degrades context quality.

**RECOMMENDED:** Run \`/compact\` first, then re-run this command. Or run \`/vbw:pause\` then \`/vbw:resume\` for a clean context reload.
EOF
  fi
fi

exit 0

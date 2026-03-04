#!/usr/bin/env bash
# resolve-agent-max-turns.sh - Turn budget resolution for VBW agents
#
# Usage:
#   resolve-agent-max-turns.sh <agent-name> <config-path> [effort]
#
# agent-name: lead|dev|qa|scout|debugger|architect
# config-path: path to .vbw-planning/config.json (optional/fail-open)
# effort: thorough|balanced|fast|turbo (also accepts high|medium|low)
#
# Returns:
#   stdout = positive integer  => pass maxTurns to Task tool
#   stdout = empty string      => omit maxTurns from Task tool (unlimited)
# Exit 0 on success, exit 1 on invalid agent/usage

set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Usage: resolve-agent-max-turns.sh <agent-name> <config-path> [effort]" >&2
  exit 1
fi

AGENT="$1"
CONFIG_PATH="$2"
EFFORT_INPUT="${3:-}"

case "$AGENT" in
  lead|dev|qa|scout|debugger|architect|docs)
    ;;
  *)
    echo "Invalid agent name '$AGENT'. Valid: lead, dev, qa, scout, debugger, architect, docs" >&2
    exit 1
    ;;
esac

default_base_turns() {
  case "$1" in
    scout) echo 15 ;;
    qa) echo 25 ;;
    architect) echo 30 ;;
    debugger) echo 80 ;;
    lead) echo 50 ;;
    dev) echo 75 ;;
    docs) echo 30 ;;
  esac
}

legacy_effort_alias() {
  case "$1" in
    thorough) echo high ;;
    balanced) echo medium ;;
    fast) echo medium ;;
    turbo) echo low ;;
    *) echo medium ;;
  esac
}

normalize_effort() {
  local raw
  raw=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')

  case "$raw" in
    thorough|balanced|fast|turbo)
      printf '%s' "$raw"
      ;;
    high)
      printf 'thorough'
      ;;
    medium)
      printf 'balanced'
      ;;
    low)
      printf 'turbo'
      ;;
    "")
      printf ''
      ;;
    *)
      return 1
      ;;
  esac
}

multiplier_for_effort() {
  # Output: "numerator denominator"
  case "$1" in
    thorough) echo "3 2" ;; # 1.5x
    balanced) echo "1 1" ;; # 1.0x
    fast) echo "4 5" ;;     # 0.8x
    turbo) echo "3 5" ;;    # 0.6x
  esac
}

normalize_turn_value() {
  local value="$1"

  case "$value" in
    false|FALSE|False)
      echo ""
      return 0
      ;;
  esac

  if [ "$value" = "null" ] || [ -z "$value" ]; then
    echo ""
    return 0
  fi

  if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
    return 1
  fi

  if [ "$value" -le 0 ]; then
    echo ""
    return 0
  fi

  echo "$value"
}

CONFIG_VALID=0
if [ -f "$CONFIG_PATH" ] && jq empty "$CONFIG_PATH" >/dev/null 2>&1; then
  CONFIG_VALID=1
fi

# Resolve effort with robust fallbacks:
# 1) explicit argument (if valid)
# 2) config.effort (if available + valid)
# 3) balanced
EFFORT=""
if EFFORT=$(normalize_effort "$EFFORT_INPUT" 2>/dev/null); then
  :
else
  EFFORT=""
fi

if [ -z "$EFFORT" ] && [ "$CONFIG_VALID" -eq 1 ]; then
  CFG_EFFORT=$(jq -r '.effort // empty' "$CONFIG_PATH" 2>/dev/null || echo "")
  if EFFORT=$(normalize_effort "$CFG_EFFORT" 2>/dev/null); then
    :
  else
    EFFORT=""
  fi
fi

[ -z "$EFFORT" ] && EFFORT="balanced"
LEGACY_EFFORT=$(legacy_effort_alias "$EFFORT")

EXPLICIT_VALUE=""
RAW_BASE=""

if [ "$CONFIG_VALID" -eq 1 ]; then
  CONFIGURED_TYPE=$(jq -r --arg agent "$AGENT" '
    if (.agent_max_turns | type == "object") and (.agent_max_turns | has($agent)) then
      (.agent_max_turns[$agent] | type)
    elif (.max_turns | type == "object") and (.max_turns | has($agent)) then
      (.max_turns[$agent] | type)
    else
      "null"
    end
  ' "$CONFIG_PATH" 2>/dev/null || echo "null")

  # Object mode: per-effort values (no multiplier applied)
  if [ "$CONFIGURED_TYPE" = "object" ]; then
    # Use has() checks instead of // chains because jq's // treats false as falsy
    RAW_VALUE=$(jq -r --arg agent "$AGENT" --arg effort "$EFFORT" --arg legacy "$LEGACY_EFFORT" '
      (.agent_max_turns[$agent] // .max_turns[$agent] // {}) as $obj |
      if ($obj | has($effort)) then ($obj[$effort] | tostring)
      elif ($obj | has($legacy)) then ($obj[$legacy] | tostring)
      elif ($obj | has("balanced")) then ($obj["balanced"] | tostring)
      elif ($obj | has("medium")) then ($obj["medium"] | tostring)
      else empty
      end
    ' "$CONFIG_PATH" 2>/dev/null || echo "")

    # Only process if jq returned a real value (not empty from `empty`)
    if [ -n "$RAW_VALUE" ]; then
      if EXPLICIT_VALUE=$(normalize_turn_value "$RAW_VALUE" 2>/dev/null); then
        # normalize succeeded: positive int or empty (unlimited)
        echo "$EXPLICIT_VALUE"
        exit 0
      fi
    fi
  fi

  RAW_BASE=$(jq -r --arg agent "$AGENT" '
    if (.agent_max_turns | type == "object") and (.agent_max_turns | has($agent)) then
      .agent_max_turns[$agent]
    elif (.max_turns | type == "object") and (.max_turns | has($agent)) then
      .max_turns[$agent]
    else
      empty
    end
  ' "$CONFIG_PATH" 2>/dev/null || echo "")
fi

BASE=""
if [ -n "$RAW_BASE" ]; then
  if BASE=$(normalize_turn_value "$RAW_BASE" 2>/dev/null); then
    # normalize succeeded — BASE is empty (unlimited) or positive int
    # RAW_BASE was non-empty but normalized to empty => explicit unlimited
    if [ -z "$BASE" ]; then
      echo ""
      exit 0
    fi
  else
    BASE=""
  fi
fi

if [ -z "$BASE" ]; then
  BASE=$(default_base_turns "$AGENT")
fi

read -r NUM DEN <<<"$(multiplier_for_effort "$EFFORT")"
RESOLVED=$(( (BASE * NUM + DEN / 2) / DEN ))

if [ "$RESOLVED" -lt 1 ]; then
  RESOLVED=1
fi

echo "$RESOLVED"
exit 0

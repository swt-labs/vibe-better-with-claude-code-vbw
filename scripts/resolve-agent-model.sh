#!/usr/bin/env bash
# resolve-agent-model.sh - Model resolution for VBW agents
#
# Reads model_profile from config.json, loads preset from model-profiles.json,
# applies per-agent overrides, and returns the final model string.
#
# Usage: resolve-agent-model.sh <agent-name> <config-path> <profiles-path>
#   agent-name: lead|dev|qa|scout|debugger|architect|docs
#   config-path: path to .vbw-planning/config.json
#   profiles-path: path to config/model-profiles.json
#
# Returns: stdout = model string (opus|sonnet|haiku), exit 0
# Errors: stderr = error message, exit 1
#
# Integration pattern (from command files):
#   MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh lead .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
#   if [ $? -ne 0 ]; then echo "Model resolution failed"; exit 1; fi
#   # Pass to Task tool: model: "${MODEL}"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/vbw-cache-key.sh
. "$SCRIPT_DIR/lib/vbw-cache-key.sh"

file_content_fingerprint() {
  local file_path="$1"

  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$file_path" | awk '{print $1}' | cut -c1-8
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q "$file_path" | cut -c1-8
  else
    cksum "$file_path" | awk '{print $1}'
  fi
}

# Argument parsing
if [ $# -ne 3 ]; then
  echo "Usage: resolve-agent-model.sh <agent-name> <config-path> <profiles-path>" >&2
  exit 1
fi

AGENT="$1"
CONFIG_PATH="$2"
PROFILES_PATH="$3"

# Validate agent name
case "$AGENT" in
  lead|dev|qa|scout|debugger|architect|docs)
    # Valid agent
    ;;
  *)
    echo "Invalid agent name '$AGENT'. Valid: lead, dev, qa, scout, debugger, architect, docs" >&2
    exit 1
    ;;
esac

# Validate config file exists
if [ ! -f "$CONFIG_PATH" ]; then
  echo "Config not found at $CONFIG_PATH. Run /vbw:init first." >&2
  exit 1
fi

# Validate profiles file exists
if [ ! -f "$PROFILES_PATH" ]; then
  echo "Model profiles not found at $PROFILES_PATH. Plugin installation issue." >&2
  exit 1
fi

# Session-level cache: avoid repeated jq calls for the same agent + config pair.
# Scope by content fingerprints and path hash so parallel BATS workers
# using different temp repos cannot collide.
CONFIG_HASH=$(file_content_fingerprint "$CONFIG_PATH")
PROFILES_HASH=$(file_content_fingerprint "$PROFILES_PATH")
PATH_HASH=$(vbw_hash_path "${CONFIG_PATH}|${PROFILES_PATH}")
CACHE_FILE="/tmp/vbw-model-${AGENT}-${PATH_HASH}-${CONFIG_HASH}-${PROFILES_HASH}"
if [ -f "$CACHE_FILE" ]; then
  _cached=$(cat "$CACHE_FILE")
  case "$_cached" in
    opus|sonnet|haiku) echo "$_cached"; exit 0 ;;
  esac
  # Cache is corrupt or empty — fall through to recompute
fi

# Read model_profile from config.json (default to "quality")
PROFILE=$(jq -r '.model_profile // "quality"' "$CONFIG_PATH")

# Validate profile exists in model-profiles.json
if ! jq -e ".$PROFILE" "$PROFILES_PATH" >/dev/null 2>&1; then
  echo "Invalid model_profile '$PROFILE'. Valid: quality, balanced, budget" >&2
  exit 1
fi

# Get model from preset for the agent
MODEL=$(jq -r ".$PROFILE.$AGENT" "$PROFILES_PATH")

# Check for per-agent override in config.json model_overrides
OVERRIDE=$(jq -r ".model_overrides.$AGENT // \"\"" "$CONFIG_PATH")
if [ -n "$OVERRIDE" ]; then
  MODEL="$OVERRIDE"
fi

# Validate final model value
case "$MODEL" in
  opus|sonnet|haiku)
    echo "$MODEL"
    # Cache result for session reuse
    echo "$MODEL" > "$CACHE_FILE" 2>/dev/null || true
    ;;
  *)
    echo "Invalid model '$MODEL' for $AGENT. Valid: opus, sonnet, haiku" >&2
    exit 1
    ;;
esac

#!/usr/bin/env bash
set -euo pipefail

# resolve-lsp.sh — Pre-compute LSP setup needs from detected stack + current state
#
# Usage:
#   resolve-lsp.sh DETECTED_STACK_JSON [SETTINGS_JSON_PATH]
#     DETECTED_STACK_JSON   JSON array string, e.g. '["python","typescript","react"]'
#     SETTINGS_JSON_PATH    (Optional) Path to Claude Code settings.json
#
# Output: JSON object with env_needed flag and deduplicated plugin list
#
# Dependencies: jq

if [[ $# -lt 1 ]]; then
  echo "Usage: resolve-lsp.sh DETECTED_STACK_JSON [SETTINGS_JSON_PATH]" >&2
  exit 1
fi

DETECTED_STACK="$1"

# Resolve settings.json path
if [[ $# -ge 2 && -n "$2" ]]; then
  SETTINGS_PATH="$2"
else
  CLAUDE_DIR=""
  for d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do
    [[ -z "$d" ]] && continue
    if [[ -d "$d" ]]; then
      CLAUDE_DIR="$d"
      break
    fi
  done
  SETTINGS_PATH="${CLAUDE_DIR}/settings.json"
fi

# Resolve plugin root for lsp-mappings.json
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${SCRIPT_DIR%/scripts}"
MAPPINGS_PATH="${PLUGIN_ROOT}/config/lsp-mappings.json"

if [[ ! -f "$MAPPINGS_PATH" ]]; then
  echo "Error: lsp-mappings.json not found at $MAPPINGS_PATH" >&2
  exit 1
fi

# Check if ENABLE_LSP_TOOL is already set in settings.json env
ENV_NEEDED=true
if [[ -f "$SETTINGS_PATH" ]]; then
  LSP_ENV=$(jq -r '.env.ENABLE_LSP_TOOL // ""' "$SETTINGS_PATH" 2>/dev/null || echo "")
  if [[ "$LSP_ENV" == "1" ]]; then
    ENV_NEEDED=false
  fi
fi

# Read enabled plugins from settings.json
ENABLED_PLUGINS="[]"
if [[ -f "$SETTINGS_PATH" ]]; then
  ENABLED_PLUGINS=$(jq -r '.enabledPlugins // []' "$SETTINGS_PATH" 2>/dev/null || echo "[]")
fi

# Read aliases and servers from mappings
ALIASES=$(jq '.aliases' "$MAPPINGS_PATH")
SERVERS=$(jq '.servers' "$MAPPINGS_PATH")

# Resolve detected stack items to unique server keys
RESOLVED_KEYS=""
while IFS= read -r item; do
  [[ -z "$item" ]] && continue
  # Check if item is an alias
  resolved=$(echo "$ALIASES" | jq -r --arg k "$item" '.[$k] // empty' 2>/dev/null || echo "")
  if [[ -n "$resolved" ]]; then
    key="$resolved"
  else
    key="$item"
  fi
  # Check if key exists in servers
  has_server=$(echo "$SERVERS" | jq -r --arg k "$key" 'has($k)' 2>/dev/null || echo "false")
  if [[ "$has_server" == "true" ]]; then
    # Deduplicate via literal token membership (not regex)
    if [[ " $RESOLVED_KEYS " != *" $key "* ]]; then
      RESOLVED_KEYS="$RESOLVED_KEYS $key"
    fi
  fi
done < <(echo "$DETECTED_STACK" | jq -r '.[]' 2>/dev/null)

# Build plugins array
PLUGINS="[]"
for key in $RESOLVED_KEYS; do
  plugin=$(echo "$SERVERS" | jq -r --arg k "$key" '.[$k].plugin // empty')
  org=$(echo "$SERVERS" | jq -r --arg k "$key" '.[$k].plugin_org // empty')
  tier=$(echo "$SERVERS" | jq -r --arg k "$key" '.[$k].tier // 0')
  desc=$(echo "$SERVERS" | jq -r --arg k "$key" '.[$k].description')
  binary_check=$(echo "$SERVERS" | jq -r --arg k "$key" '.[$k].binary_check')
  install_cmd=$(echo "$SERVERS" | jq -r --arg k "$key" '.[$k].install_cmd // empty')
  install_url=$(echo "$SERVERS" | jq -r --arg k "$key" '.[$k].install_url // empty')

  # Check if binary is installed
  binary_installed=false
  if eval "$binary_check" >/dev/null 2>&1; then
    binary_installed=true
  fi

  # Check if plugin is already enabled (skip for plugin-less entries)
  plugin_enabled=false
  if [[ -n "$plugin" ]]; then
    if echo "$ENABLED_PLUGINS" | jq -e --arg p "$plugin" 'map(select(. == $p or test($p))) | length > 0' >/dev/null 2>&1; then
      plugin_enabled=true
    fi
  fi

  # Build plugin entry
  entry=$(jq -n \
    --arg plugin "$plugin" \
    --arg org "$org" \
    --argjson tier "$tier" \
    --arg desc "$desc" \
    --argjson binary_installed "$binary_installed" \
    --arg install_cmd "$install_cmd" \
    --arg install_url "$install_url" \
    --argjson plugin_enabled "$plugin_enabled" \
    '{
      plugin: (if $plugin == "" then null else $plugin end),
      org: (if $org == "" then null else $org end),
      tier: $tier,
      description: $desc,
      binary_installed: $binary_installed,
      install_cmd: (if $install_cmd == "" then null else $install_cmd end),
      install_url: (if $install_url == "" then null else $install_url end),
      plugin_enabled: $plugin_enabled
    }')

  PLUGINS=$(echo "$PLUGINS" | jq --argjson e "$entry" '. + [$e]')
done

# Output result
jq -n \
  --argjson env_needed "$ENV_NEEDED" \
  --argjson plugins "$PLUGINS" \
  '{env_needed: $env_needed, plugins: $plugins}'

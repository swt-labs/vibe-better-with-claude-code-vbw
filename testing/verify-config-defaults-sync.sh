#!/usr/bin/env bash
set -euo pipefail

# verify-config-defaults-sync.sh — Contract test for issue #373
#
# Validates that the settings reference table in commands/config.md stays
# in sync with config/defaults.json (the source of truth for all settings).
#
# Checks:
# 1. Every key in defaults.json has a row in the config.md table
# 2. Every setting name in the config.md table exists in defaults.json
# 3. For boolean/string settings with simple defaults, the default value matches

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_MD="$ROOT/commands/config.md"
DEFAULTS_JSON="$ROOT/config/defaults.json"

PASS=0
FAIL=0

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

echo "=== Config Defaults Sync Contract (Issue #373) ==="

# Extract setting names from the markdown table.
# Table rows look like: | setting_name | type | values | default |
# Skip the header row (Setting) and separator row (------).
md_settings=$(grep -E '^\| [a-z_]+ \|' "$CONFIG_MD" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')

# Extract keys from defaults.json
json_keys=$(jq -r 'keys[]' "$DEFAULTS_JSON")

# --- Check 1: Every key in defaults.json has a row in config.md ---
echo ""
echo "--- Check: defaults.json keys present in config.md table ---"
for key in $json_keys; do
  if echo "$md_settings" | grep -qx "$key"; then
    pass "defaults.json key '$key' found in config.md table"
  else
    fail "defaults.json key '$key' MISSING from config.md table"
  fi
done

# --- Check 2: Every setting in config.md exists in defaults.json ---
echo ""
echo "--- Check: config.md table settings exist in defaults.json ---"
for setting in $md_settings; do
  if echo "$json_keys" | grep -qx "$setting"; then
    pass "config.md setting '$setting' found in defaults.json"
  else
    fail "config.md setting '$setting' NOT in defaults.json (stale/graduated?)"
  fi
done

# --- Check 3: Default values match for simple types ---
# Skip object/array types where table uses shorthand representations.
echo ""
echo "--- Check: default values match for simple types ---"

COMPLEX_KEYS="custom_profiles model_overrides agent_max_turns qa_skip_agents"

for key in $json_keys; do
  # Skip complex types
  skip=false
  for ck in $COMPLEX_KEYS; do
    if [ "$key" = "$ck" ]; then
      skip=true
      break
    fi
  done
  if $skip; then
    continue
  fi

  json_val=$(jq -r --arg k "$key" '.[$k]' "$DEFAULTS_JSON")

  # Extract the default column (4th field) from the matching config.md row
  md_row=$(grep -E "^\| ${key} \|" "$CONFIG_MD" || true)
  if [ -z "$md_row" ]; then
    # Already caught by Check 1, skip value comparison
    continue
  fi

  md_default=$(echo "$md_row" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $5); print $5}')

  if [ "$json_val" = "$md_default" ]; then
    pass "'$key' default matches: $json_val"
  else
    fail "'$key' default mismatch: defaults.json='$json_val' config.md='$md_default'"
  fi
done

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

[ "$FAIL" -eq 0 ] || exit 1

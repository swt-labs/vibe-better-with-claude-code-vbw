#!/usr/bin/env bash
set -euo pipefail

# verify-lsp-setup.sh — Verify LSP setup pipeline artifacts and integration

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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

echo "=== LSP Setup Pipeline Verification ==="

# --- config/lsp-mappings.json ---

MAPPINGS="$ROOT/config/lsp-mappings.json"

if [[ -f "$MAPPINGS" ]]; then
  pass "config/lsp-mappings.json exists"
else
  fail "config/lsp-mappings.json missing"
fi

if jq empty "$MAPPINGS" 2>/dev/null; then
  pass "config/lsp-mappings.json is valid JSON"
else
  fail "config/lsp-mappings.json is not valid JSON"
fi

if jq -e '.aliases' "$MAPPINGS" >/dev/null 2>&1; then
  pass "lsp-mappings.json has aliases section"
else
  fail "lsp-mappings.json missing aliases section"
fi

if jq -e '.servers' "$MAPPINGS" >/dev/null 2>&1; then
  pass "lsp-mappings.json has servers section"
else
  fail "lsp-mappings.json missing servers section"
fi

# Verify all alias targets exist in servers
BAD_ALIASES=$(jq -r '.aliases | to_entries[] | select(.value as $v | .value != null) | .value' "$MAPPINGS" | sort -u | while read -r target; do
  if ! jq -e --arg t "$target" '.servers[$t]' "$MAPPINGS" >/dev/null 2>&1; then
    echo "$target"
  fi
done)
if [[ -z "$BAD_ALIASES" ]]; then
  pass "all alias targets resolve to valid servers"
else
  fail "alias targets missing from servers: $BAD_ALIASES"
fi

# Verify each server has required fields
# plugin and plugin_org may be null for Tier 2 plugin-less entries
REQUIRED_FIELDS=("binary_check" "description")
MISSING=""
for field in "${REQUIRED_FIELDS[@]}"; do
  BAD=$(jq -r --arg f "$field" '.servers | to_entries[] | select(.value[$f] == null or .value[$f] == "") | .key' "$MAPPINGS" 2>/dev/null)
  if [[ -n "$BAD" ]]; then
    MISSING="$MISSING $field($BAD)"
  fi
done
if [[ -z "$MISSING" ]]; then
  pass "all servers have required fields (binary_check, description)"
else
  fail "servers missing required fields:$MISSING"
fi

# Verify Tier 1 entries all have plugin and plugin_org
T1_MISSING=""
T1_BAD=$(jq -r '.servers | to_entries[] | select(.value.tier == 1) | select(.value.plugin == null or .value.plugin == "" or .value.plugin_org == null or .value.plugin_org == "") | .key' "$MAPPINGS" 2>/dev/null)
if [[ -z "$T1_BAD" ]]; then
  pass "all Tier 1 servers have plugin and plugin_org"
else
  fail "Tier 1 servers missing plugin/plugin_org: $T1_BAD"
fi

# --- scripts/resolve-lsp.sh ---

RESOLVE="$ROOT/scripts/resolve-lsp.sh"

if [[ -f "$RESOLVE" ]]; then
  pass "scripts/resolve-lsp.sh exists"
else
  fail "scripts/resolve-lsp.sh missing"
fi

if [[ -x "$RESOLVE" ]]; then
  pass "scripts/resolve-lsp.sh is executable"
else
  fail "scripts/resolve-lsp.sh is not executable"
fi

# Functional test: run resolve-lsp.sh with test input
OUTPUT=$(bash "$RESOLVE" '["python","typescript","react"]' /dev/null 2>/dev/null || echo "ERROR")
if [[ "$OUTPUT" != "ERROR" ]] && echo "$OUTPUT" | jq -e '.env_needed' >/dev/null 2>&1; then
  pass "resolve-lsp.sh produces valid JSON output"
else
  fail "resolve-lsp.sh did not produce valid JSON"
fi

# Verify deduplication: react + typescript should produce 1 typescript entry, not 2
PLUGIN_COUNT=$(echo "$OUTPUT" | jq '[.plugins[] | select(.plugin == "typescript-lsp")] | length' 2>/dev/null || echo "0")
if [[ "$PLUGIN_COUNT" == "1" ]]; then
  pass "resolve-lsp.sh deduplicates aliases (react+typescript → 1 entry)"
else
  fail "resolve-lsp.sh deduplication failed: expected 1 typescript entry, got $PLUGIN_COUNT"
fi

if grep -q '=~ " \$key "' "$RESOLVE"; then
  fail "resolve-lsp.sh still uses quoted rhs with =~ (SC2076)"
else
  pass "resolve-lsp.sh avoids quoted rhs with =~ (SC2076)"
fi

# --- bootstrap-claude.sh: Code Intelligence section ---

BOOTSTRAP="$ROOT/scripts/bootstrap/bootstrap-claude.sh"
CLAUDE_LIB="$ROOT/scripts/lib/claude-md-vbw-sections.sh"

if grep -q '"## Code Intelligence"' "$CLAUDE_LIB"; then
  pass "CLAUDE helper library contains ## Code Intelligence"
else
  fail "CLAUDE helper library missing ## Code Intelligence"
fi

# Verify generate_vbw_sections outputs the section
BOOTSTRAP_OUTPUT=$(bash "$BOOTSTRAP" /tmp/test-lsp-verify.md "VerifyTest" "Test value" 2>/dev/null && cat /tmp/test-lsp-verify.md)
if echo "$BOOTSTRAP_OUTPUT" | grep -q "## Code Intelligence"; then
  pass "bootstrap-claude.sh generate_vbw_sections outputs ## Code Intelligence"
else
  fail "bootstrap-claude.sh generate_vbw_sections missing ## Code Intelligence output"
fi

if echo "$BOOTSTRAP_OUTPUT" | grep -q "goToDefinition"; then
  pass "bootstrap-claude.sh Code Intelligence section has LSP guidance content"
else
  fail "bootstrap-claude.sh Code Intelligence section missing LSP guidance content"
fi
rm -f /tmp/test-lsp-verify.md

# --- commands/init.md: Step 2.5 ---

INIT="$ROOT/commands/init.md"

if grep -q "2\.5.*LSP setup\|LSP setup" "$INIT"; then
  pass "init.md contains Step 2.5 LSP setup"
else
  fail "init.md missing Step 2.5 LSP setup"
fi

if grep -q "resolve-lsp.sh" "$INIT"; then
  pass "init.md references resolve-lsp.sh"
else
  fail "init.md missing resolve-lsp.sh reference"
fi

if grep -q "ENABLE_LSP_TOOL" "$INIT"; then
  pass "init.md references ENABLE_LSP_TOOL env flag"
else
  fail "init.md missing ENABLE_LSP_TOOL reference"
fi

if grep -q "Code Intelligence" "$INIT"; then
  pass "init.md contains Code Intelligence section in brownfield template"
else
  fail "init.md missing Code Intelligence in brownfield template"
fi

if grep -q "unset CLAUDECODE" "$INIT"; then
  pass "init.md uses unset CLAUDECODE pattern for plugin commands"
else
  fail "init.md missing unset CLAUDECODE pattern"
fi

# --- Summary ---

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

[[ "$FAIL" -eq 0 ]] || exit 1

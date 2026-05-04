#!/usr/bin/env bash
set -euo pipefail

# verify-permission-mode-contract.sh — Verify agent permissionMode declarations
#
# Checks:
# - Plan-mode agents (Scout, QA) declare permissionMode: plan
# - Edit agents (Dev, Lead, Architect, Debugger, Docs) declare permissionMode: acceptEdits
# - Every agent has an explicit permissionMode in frontmatter

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README_FILE="$ROOT/README.md"

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

check_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label"
  fi
}

check_not_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$label"
  else
    pass "$label"
  fi
}

markdown_table_cell() {
  local row="$1"
  local index="$2"
  printf '%s\n' "$row" | awk -F'|' -v index="$index" '{ cell=$index; gsub(/^[[:space:]]+|[[:space:]]+$/, "", cell); print cell }'
}

tool_list_contains() {
  local list="$1"
  local tool="$2"
  printf '%s\n' "$list" \
    | sed 's/^[^:]*:[[:space:]]*//' \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | grep -Fxq "$tool"
}

echo "=== Agent permissionMode Contract Verification ==="

# Define expected permission modes (bash 3.2 compatible — no associative arrays)
AGENTS="vbw-scout vbw-qa vbw-dev vbw-lead vbw-architect vbw-debugger vbw-docs"

get_expected_mode() {
  case "$1" in
    vbw-scout|vbw-qa) echo "plan" ;;
    *) echo "acceptEdits" ;;
  esac
}

for agent in $AGENTS; do
  AGENT_FILE="$ROOT/agents/${agent}.md"
  SHORT_NAME="${agent#vbw-}"
  EXPECTED="$(get_expected_mode "$agent")"

  if [[ ! -f "$AGENT_FILE" ]]; then
    fail "${SHORT_NAME}: agent file missing"
    continue
  fi

  # Check that permissionMode is declared in frontmatter (first 15 lines)
  ACTUAL=$(head -15 "$AGENT_FILE" | grep "^permissionMode:" | sed 's/^permissionMode: *//' | tr -d '[:space:]')
  if [[ -z "$ACTUAL" ]]; then
    fail "${SHORT_NAME}: permissionMode not declared in frontmatter (expected: ${EXPECTED})"
  elif [[ "$ACTUAL" == "$EXPECTED" ]]; then
    pass "${SHORT_NAME}: permissionMode is ${ACTUAL}"
  else
    fail "${SHORT_NAME}: permissionMode is ${ACTUAL} (expected: ${EXPECTED})"
  fi
done

README_DEV_ROW=$(grep -F '| **Dev** |' "$README_FILE" || true)
README_PERMISSION_LEGEND=$(grep -F '**Denied / Omitted**' "$README_FILE" || true)
DEV_DESCRIPTION=$(head -15 "$ROOT/agents/vbw-dev.md" | grep '^description:' || true)
DEV_TOOLS_FRONTMATTER=$(head -15 "$ROOT/agents/vbw-dev.md" | awk '/^tools:/ { sub(/^tools:[[:space:]]*/, ""); print }')
README_DEV_ALLOWED_CELL=$(markdown_table_cell "$README_DEV_ROW" 4)
README_DEV_OMITTED_CELL=$(markdown_table_cell "$README_DEV_ROW" 5)

if [[ -n "$README_DEV_ROW" ]]; then
  pass "README: Dev permission row exists"
else
  fail "README: Dev permission row exists"
fi

check_not_contains "dev: description no longer says full tool access" "$DEV_DESCRIPTION" "full tool access"
check_contains "dev: description mentions explicit tool allowlist" "$DEV_DESCRIPTION" "explicit implementation tool allowlist"
check_not_contains "README: Dev row no longer says Full access" "$README_DEV_ROW" "Full access"
check_not_contains "README: Dev row no longer leaves denied tools blank" "$README_DEV_ROW" "| -- |"
check_contains "README: Dev row describes explicit omissions" "$README_DEV_ROW" "Outside explicit allowlist"
for tool in Read Glob Grep Write Edit Bash WebFetch WebSearch LSP Skill SendMessage TaskGet Task TaskCreate Agent TeamCreate TeamDelete AskUserQuestion TodoWrite NotebookEdit; do
  if tool_list_contains "$DEV_TOOLS_FRONTMATTER" "$tool"; then
    if tool_list_contains "$README_DEV_ALLOWED_CELL" "$tool"; then
      pass "README: Dev row allowed cell matches frontmatter for ${tool}"
    else
      fail "README: Dev row allowed cell missing frontmatter tool ${tool}"
    fi
    if tool_list_contains "$README_DEV_OMITTED_CELL" "$tool"; then
      fail "README: Dev row omitted cell should not list allowed tool ${tool}"
    else
      pass "README: Dev row omitted cell excludes allowed tool ${tool}"
    fi
  else
    if tool_list_contains "$README_DEV_OMITTED_CELL" "$tool"; then
      pass "README: Dev row omitted cell lists absent tool ${tool}"
    else
      fail "README: Dev row omitted cell missing absent tool ${tool}"
    fi
    if tool_list_contains "$README_DEV_ALLOWED_CELL" "$tool"; then
      fail "README: Dev row allowed cell should not list absent tool ${tool}"
    else
      pass "README: Dev row allowed cell excludes absent tool ${tool}"
    fi
  fi
done

check_contains "README: permission legend covers allowlist omissions" "$README_PERMISSION_LEGEND" 'for explicit allowlist agents, tools intentionally absent from `tools`'
check_not_contains "README: permission legend no longer describes only disallowedTools" "$README_PERMISSION_LEGEND" '**Denied** = `disallowedTools`'

if grep -Fq 'Dev, Debugger' "$README_FILE" && grep -Fq 'Full access. The ones you actually worry about.' "$README_FILE"; then
  fail "README: permission model no longer groups Dev with full-access agents"
else
  pass "README: permission model no longer groups Dev with full-access agents"
fi

echo ""
echo "TOTAL  ${PASS} PASS, ${FAIL} FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1

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

normalize_tool_list() {
  local list="$1"
  printf '%s\n' "$list" \
    | sed 's/^[^:]*:[[:space:]]*//' \
    | sed 's/^Explicit allowlist:[[:space:]]*//' \
    | sed 's/^Outside explicit allowlist:[[:space:]]*//' \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | awk 'NF { print }' \
    | LC_ALL=C sort
}

print_tool_lines() {
  local list="$1"
  [ -n "$list" ] && printf '%s\n' "$list"
}

compare_tool_lists() {
  local label="$1"
  local actual="$2"
  local expected="$3"

  if [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label"
    printf 'EXPECTED:\n%s\nACTUAL:\n%s\n' "$expected" "$actual"
  fi
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
DEV_ALLOWED_NORMALIZED=$(normalize_tool_list "$DEV_TOOLS_FRONTMATTER")
README_ALLOWED_NORMALIZED=$(normalize_tool_list "$README_DEV_ALLOWED_CELL")
README_OMITTED_NORMALIZED=$(normalize_tool_list "$README_DEV_OMITTED_CELL")
VISIBLE_TOOL_UNIVERSE=$(cat <<'TOOLS'
Agent
AskUserQuestion
Bash
Edit
Glob
Grep
LSP
NotebookEdit
Read
SendMessage
Skill
Task
TaskCreate
TaskGet
TeamCreate
TeamDelete
TodoWrite
WebFetch
WebSearch
Write
TOOLS
)
VISIBLE_TOOL_UNIVERSE_NORMALIZED=$(normalize_tool_list "$VISIBLE_TOOL_UNIVERSE")
UNKNOWN_DEV_TOOLS=$(comm -23 <(print_tool_lines "$DEV_ALLOWED_NORMALIZED") <(print_tool_lines "$VISIBLE_TOOL_UNIVERSE_NORMALIZED"))
EXPECTED_DEV_OMITTED_NORMALIZED=$(comm -23 <(print_tool_lines "$VISIBLE_TOOL_UNIVERSE_NORMALIZED") <(print_tool_lines "$DEV_ALLOWED_NORMALIZED"))

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
compare_tool_lists "README: Dev allowed tokens exactly match frontmatter" "$README_ALLOWED_NORMALIZED" "$DEV_ALLOWED_NORMALIZED"
compare_tool_lists "README: Dev omitted tokens exactly match universe minus frontmatter" "$README_OMITTED_NORMALIZED" "$EXPECTED_DEV_OMITTED_NORMALIZED"
if [ -z "$UNKNOWN_DEV_TOOLS" ]; then
  pass "README: Dev frontmatter tools are in canonical visible-tool universe"
else
  fail "README: Dev frontmatter tools must be added to canonical visible-tool universe"
  printf 'UNKNOWN:\n%s\n' "$UNKNOWN_DEV_TOOLS"
fi
if [ -z "$(comm -12 <(print_tool_lines "$README_ALLOWED_NORMALIZED") <(print_tool_lines "$README_OMITTED_NORMALIZED"))" ]; then
  pass "README: Dev allowed and omitted cells do not overlap"
else
  fail "README: Dev allowed and omitted cells must not overlap"
fi

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

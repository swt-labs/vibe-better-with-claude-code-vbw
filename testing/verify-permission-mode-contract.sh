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
  local cell_index="$2"
  printf '%s\n' "$row" | awk -F'|' -v cell_index="$cell_index" '{ cell=$cell_index; gsub(/^[[:space:]]+|[[:space:]]+$/, "", cell); print cell }'
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
DEV_DISALLOWED_FRONTMATTER=$(head -15 "$ROOT/agents/vbw-dev.md" | awk '/^disallowedTools:/ { sub(/^disallowedTools:[[:space:]]*/, ""); print }')
README_DEV_DENIED_CELL=$(markdown_table_cell "$README_DEV_ROW" 5)
DEV_DENIED_NORMALIZED=$(normalize_tool_list "$DEV_DISALLOWED_FRONTMATTER")
README_DENIED_NORMALIZED=$(normalize_tool_list "$README_DEV_DENIED_CELL")

if [[ -n "$README_DEV_ROW" ]]; then
  pass "README: Dev permission row exists"
else
  fail "README: Dev permission row exists"
fi

if [ -n "$DEV_DISALLOWED_FRONTMATTER" ]; then
  pass "vbw-dev.md: frontmatter declares disallowedTools denylist"
else
  fail "vbw-dev.md: frontmatter must declare disallowedTools denylist"
fi

check_not_contains "vbw-dev.md: description no longer says explicit allowlist" "$DEV_DESCRIPTION" "explicit implementation tool allowlist"
check_contains "vbw-dev.md: description mentions denylist-controlled tool access" "$DEV_DESCRIPTION" "denylist-controlled"

if head -15 "$ROOT/agents/vbw-dev.md" | grep -q '^tools:'; then
  fail "vbw-dev.md: frontmatter must not use a tools allowlist (use disallowedTools denylist for forward compatibility)"
else
  pass "vbw-dev.md: frontmatter does not use a tools allowlist"
fi

for required_denied in Task TaskCreate Agent TeamCreate TeamDelete AskUserQuestion; do
  if printf '%s\n' "$DEV_DENIED_NORMALIZED" | grep -Fxq "$required_denied"; then
    pass "vbw-dev.md: disallowedTools bans $required_denied"
  else
    fail "vbw-dev.md: disallowedTools must ban $required_denied"
  fi
done

for must_not_deny in Bash Read Edit Write Glob Grep LSP Skill WebFetch WebSearch SendMessage TaskGet; do
  if printf '%s\n' "$DEV_DENIED_NORMALIZED" | grep -Fxq "$must_not_deny"; then
    fail "vbw-dev.md: disallowedTools must not ban $must_not_deny (Dev relies on it)"
  else
    pass "vbw-dev.md: disallowedTools does not ban $must_not_deny"
  fi
done

check_not_contains "README: Dev row no longer pins an explicit allowlist" "$README_DEV_ROW" "Explicit allowlist:"
check_not_contains "README: Dev row no longer says Outside explicit allowlist" "$README_DEV_ROW" "Outside explicit allowlist"
check_contains "README: Dev row uses inherited tools language" "$README_DEV_ROW" "Inherited (all except denied)"
compare_tool_lists "README: Dev denied tokens exactly match disallowedTools frontmatter" "$README_DENIED_NORMALIZED" "$DEV_DENIED_NORMALIZED"

check_contains "README: permission legend mentions disallowedTools" "$README_PERMISSION_LEGEND" 'disallowedTools'

if grep -Fq 'Dev, Debugger' "$README_FILE" && grep -Fq 'Full access. The ones you actually worry about.' "$README_FILE"; then
  fail "README: permission model no longer groups Dev with full-access agents"
else
  pass "README: permission model no longer groups Dev with full-access agents"
fi

echo ""
echo "TOTAL  ${PASS} PASS, ${FAIL} FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1

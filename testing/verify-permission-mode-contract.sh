#!/usr/bin/env bash
set -euo pipefail

# verify-permission-mode-contract.sh — Verify agent permissionMode declarations
#
# Checks:
# - Read-only agents (Scout, QA) declare permissionMode: plan
# - Edit agents (Dev, Lead, Architect, Debugger, Docs) declare permissionMode: acceptEdits
# - Every agent has an explicit permissionMode in frontmatter

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

echo ""
echo "TOTAL  ${PASS} PASS, ${FAIL} FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1

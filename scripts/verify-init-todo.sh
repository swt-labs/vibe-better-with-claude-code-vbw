#!/usr/bin/env bash
set -euo pipefail

# verify-init-todo.sh — Contract checks for init/todo state shape
#
# Validates consistency across:
# - templates/STATE.md
# - commands/todo.md instructions
# - scripts/bootstrap/bootstrap-state.sh generated output

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$ROOT/templates/STATE.md"
TODO_CMD="$ROOT/commands/todo.md"
LIST_CMD="$ROOT/commands/list-todos.md"
BOOTSTRAP="$ROOT/scripts/bootstrap/bootstrap-state.sh"

TOTAL_PASS=0
TOTAL_FAIL=0

check() {
  local req="$1"
  local desc="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then
    echo "PASS  $req: $desc"
    TOTAL_PASS=$((TOTAL_PASS + 1))
  else
    echo "FAIL  $req: $desc"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi
}

echo "=== Template + Command Contracts ==="
check "INIT-01" "template has ## Todos section" grep -q '^## Todos$' "$TEMPLATE"
check "INIT-02" "template has no ### Pending Todos subsection (flat)" test ! "$(grep -c '^### Pending Todos$' "$TEMPLATE")" -gt 0
check "TODO-01" "todo command anchors insertion on ## Todos" grep -q 'Find `## Todos`' "$TODO_CMD"
check "TODO-02" "todo command does not reference Pending Todos" test ! "$(grep -c 'Pending Todos' "$TODO_CMD")" -gt 0
check "TODO-03" "todo command avoids preflight plugin-root resolver shell block" test ! "$(grep -c 'VBW_CACHE_ROOT=' "$TODO_CMD")" -gt 0
check "TODO-04" "todo command explains write-access requirement in restricted modes" grep -qi 'write access.*restricted\|restricted.*write access' "$TODO_CMD"
check "LIST-01" "list-todos command avoids preflight plugin-root resolver shell block" test ! "$(grep -c 'VBW_CACHE_ROOT=' "$LIST_CMD")" -gt 0
check "LIST-02" "list-todos command explains restricted-mode requirement" grep -qi 'restricted mode\|restricted.*permission' "$LIST_CMD"
# TODO-05: Contract: file contains a STOP for missing STATE.md with restart guidance.
# Heading-agnostic — greps the whole file for the stop-message keywords.
check "TODO-05" "todo command STOPs with restart guidance when STATE.md missing" \
  bash -c 'grep -q "STATE\.md not found\|STATE\.md does not exist" "$1" && grep -qi "restart" "$1"' _ "$TODO_CMD"
# LIST-03: Contract: file contains a STOP for failed plugin root resolution with restart guidance.
check "LIST-03" "list-todos command STOPs with restart guidance when plugin root fails" \
  bash -c 'grep -qi "root not found\|none resolves" "$1" && grep -qi "restart" "$1"' _ "$LIST_CMD"

echo ""
echo "=== Bootstrap Output Contracts ==="
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vbw-init-todo.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

BOOTSTRAP_STATE="$TMP_DIR/STATE.md"
check "BOOT-01" "bootstrap script executes" bash "$BOOTSTRAP" "$BOOTSTRAP_STATE" "Test Project" "Test Milestone" 2
check "BOOT-02" "bootstrap output has ## Todos section" grep -q '^## Todos$' "$BOOTSTRAP_STATE"
check "BOOT-03" "bootstrap output has no ### Pending Todos (flat)" test ! "$(grep -c '^### Pending Todos$' "$BOOTSTRAP_STATE")" -gt 0
check "BOOT-04" "bootstrap output initializes empty todo placeholder" grep -q '^None\.$' "$BOOTSTRAP_STATE"

echo ""
echo "==============================="
echo "TOTAL: $TOTAL_PASS PASS, $TOTAL_FAIL FAIL"
echo "==============================="

if [ "$TOTAL_FAIL" -eq 0 ]; then
  echo "All init/todo contract checks passed."
  exit 0
fi

echo "Init/todo contract checks failed."
exit 1

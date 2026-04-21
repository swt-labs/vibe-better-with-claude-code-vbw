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
TODO_HARDCODED_HELPER_NEEDLE='/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/todo-details.sh'
TODO_HARDCODED_PLANNING_GIT_NEEDLE='/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh'
TODO_PLANNING_GIT_CMD='bash "${PLUGIN_ROOT}/scripts/planning-git.sh" commit-boundary "add todo item" .vbw-planning/config.json'

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
check "TODO-04" "todo command explains Bash + write-access requirement in restricted modes" grep -qi 'bash.*write access\|write access.*bash' "$TODO_CMD"
# TODO-05: Contract: file contains a STOP for missing STATE.md with restart guidance.
# Heading-agnostic — greps the whole file for the stop-message keywords.
check "TODO-05" "todo command STOPs with restart guidance when STATE.md missing" \
  bash -c 'grep -q "STATE\.md not found\|STATE\.md does not exist" "$1" && grep -qi "restart" "$1"' _ "$TODO_CMD"
check "TODO-06" "todo command defines inline PLUGIN_ROOT resolution for helper writes" \
  bash -c 'grep -Fq "Resolve plugin root." "$1" && grep -Fq "Store the resolved path as `PLUGIN_ROOT`" "$1"' _ "$TODO_CMD"
check "TODO-07" "todo command uses canonical helper path via PLUGIN_ROOT" \
  grep -Fq 'bash "${PLUGIN_ROOT}/scripts/todo-details.sh" add HASH -' "$TODO_CMD"
check "TODO-08" "todo command never hard-codes the session symlink helper path" \
  bash -c '! grep -Fq "$2" "$1"' _ "$TODO_CMD" "$TODO_HARDCODED_HELPER_NEEDLE"
check "TODO-09" "todo command requires parsed helper JSON with status ok before ref append" \
  bash -c 'grep -Fq "parsed stdout is valid JSON with" "$1" && grep -Fq "status=\"ok\"" "$1" && grep -Fq "(ref:HASH)" "$1"' _ "$TODO_CMD"
check "TODO-10" "todo command requires status ok before Extended detail saved confirmation" \
  bash -c 'grep -Fq "parsed stdout is valid JSON with" "$1" && grep -Fq "Extended detail saved (ref:HASH)." "$1"' _ "$TODO_CMD"
check "TODO-11" "todo command forbids direct per-file fallback writes" \
  grep -Fq '.vbw-planning/todo-details/HASH.json' "$TODO_CMD"
check "TODO-12" "todo command uses planning git boundary helper via PLUGIN_ROOT" \
  grep -Fq "$TODO_PLANNING_GIT_CMD" "$TODO_CMD"
check "TODO-13" "todo command never hard-codes the session symlink planning-git path" \
  bash -c '! grep -Fq "$2" "$1"' _ "$TODO_CMD" "$TODO_HARDCODED_PLANNING_GIT_NEEDLE"
check "TODO-14" "todo command forbids bespoke git staging or commit instructions" \
  bash -c '! grep -qE "(^|[^[:alnum:]_])git (add|commit|push)([^[:alnum:]_]|$)" "$1"' _ "$TODO_CMD"
check "TODO-15" "todo command reuses the planning-git unavailable warning" \
  grep -Fq 'VBW: planning-git.sh unavailable; skipping planning git boundary commit' "$TODO_CMD"

write_line=$(grep -nF '3. **Add plain todo to STATE.md:**' "$TODO_CMD" | head -1 | cut -d: -f1 || true)
ref_line=$(grep -nF 'edit the exact todo line you just added in `STATE.md` to append `(ref:HASH)`' "$TODO_CMD" | head -1 | cut -d: -f1 || true)
detail_failure_line=$(grep -nF "If the helper's stdout is not valid JSON or the parsed \`status\` is anything other than \`ok\`" "$TODO_CMD" | head -1 | cut -d: -f1 || true)
planning_line=$(grep -nF "$TODO_PLANNING_GIT_CMD" "$TODO_CMD" | head -1 | cut -d: -f1 || true)
confirm_line=$(grep -nF '7. **Confirm:**' "$TODO_CMD" | head -1 | cut -d: -f1 || true)

check "TODO-16" "planning boundary step appears after the plain todo write step" \
  bash -c '[ -n "$1" ] && [ -n "$2" ] && [ "$1" -lt "$2" ]' _ "$write_line" "$planning_line"
check "TODO-17" "planning boundary step appears after rich-detail ref append instructions" \
  bash -c '[ -n "$1" ] && [ -n "$2" ] && [ "$1" -lt "$2" ]' _ "$ref_line" "$planning_line"
check "TODO-18" "planning boundary step appears after the rich-detail failure branch" \
  bash -c '[ -n "$1" ] && [ -n "$2" ] && [ "$1" -lt "$2" ]' _ "$detail_failure_line" "$planning_line"
check "TODO-19" "planning boundary step appears before final confirmation" \
  bash -c '[ -n "$1" ] && [ -n "$2" ] && [ "$1" -lt "$2" ]' _ "$planning_line" "$confirm_line"
check "LIST-01" "list-todos command avoids preflight plugin-root resolver shell block" test ! "$(grep -c 'VBW_CACHE_ROOT=' "$LIST_CMD")" -gt 0
check "LIST-02" "list-todos command explains restricted-mode requirement" grep -qi 'restricted mode\|restricted.*permission' "$LIST_CMD"
# LIST-03: Contract: file contains a STOP for failed plugin root resolution with restart guidance.
check "LIST-03" "list-todos command STOPs with restart guidance when plugin root fails" \
  bash -c 'grep -qi "root not found\|none resolves" "$1" && grep -qi "restart" "$1"' _ "$LIST_CMD"

echo ""
echo "=== List-Todos Interaction Contract ==="
check "LIST-06" "list-todos displays slash command usage hints" \
  grep -qi '/vbw:vibe N\|/vbw:fix N\|/vbw:debug N' "$LIST_CMD"
check "LIST-07" "list-todos documents remove N action" \
  grep -qi 'remove N' "$LIST_CMD"
check "LIST-08" "list-todos does not reference AskUserQuestion tool" \
  bash -c '! grep -qE "(^|[^[:alnum:]_])AskUserQuestion([^[:alnum:]_]|$)" "$1"' _ "$LIST_CMD"
check "LIST-09" "list-todos instructs STOP after displaying hints" \
  grep -qi 'STOP' "$LIST_CMD"
check "LIST-10" "list-todos allowed-tools does not include AskUserQuestion" \
  bash -c '! grep -qi "AskUserQuestion" "$(head -10 "$1")"' _ "$LIST_CMD"
check "LIST-11" "list-todos describes display-and-stop pattern" \
  grep -qi 'Display action hints and STOP' "$LIST_CMD"

echo ""
echo "=== Bootstrap Output Contracts ==="
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vbw-init-todo.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

BOOTSTRAP_STATE="$TMP_DIR/STATE.md"
check "BOOT-01" "bootstrap script executes" bash "$BOOTSTRAP" "$BOOTSTRAP_STATE" "Test Project" "Test Milestone" 2
check "BOOT-02" "bootstrap output has ## Todos section" grep -q '^## Todos$' "$BOOTSTRAP_STATE"
check "BOOT-03" "bootstrap output has no ### Pending Todos (flat)" test ! "$(grep -c '^### Pending Todos$' "$BOOTSTRAP_STATE")" -gt 0
check "BOOT-04" "bootstrap output initializes empty todo placeholder" grep -q '^None\.$' "$BOOTSTRAP_STATE"
check "BOOT-05" "bootstrap creates todo-details.json alongside STATE.md" test -f "$TMP_DIR/todo-details.json"
check "BOOT-06" "todo-details.json has valid schema" bash -c 'jq -e ".schema_version == 1 and (.items | length) == 0" "$1" >/dev/null' _ "$TMP_DIR/todo-details.json"

echo ""
echo "=== List-Todos Ref Handling ==="
LIST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/vbw-list-ref.XXXXXX")"
trap 'rm -rf "$TMP_DIR" "$LIST_TMP"' EXIT
mkdir -p "$LIST_TMP/.vbw-planning"
cat > "$LIST_TMP/.vbw-planning/STATE.md" << 'HEREDOC'
# State
## Todos
- [HIGH] Fix the widget (added 2025-04-10) (ref:abc12345)
HEREDOC

check "LIST-04" "list-todos.sh parses ref tag into JSON ref field" \
  bash -c 'cd "$1" && VBW_PLANNING_DIR=.vbw-planning bash "$2/scripts/list-todos.sh" 2>/dev/null | jq -e ".items[0].ref == \"abc12345\"" >/dev/null' _ "$LIST_TMP" "$ROOT"

check "LIST-05" "list-todos.sh strips ref tag from display text" \
  bash -c 'cd "$1" && VBW_PLANNING_DIR=.vbw-planning bash "$2/scripts/list-todos.sh" 2>/dev/null | jq -e "(.display | test(\"ref:abc12345\") | not)" >/dev/null' _ "$LIST_TMP" "$ROOT"

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
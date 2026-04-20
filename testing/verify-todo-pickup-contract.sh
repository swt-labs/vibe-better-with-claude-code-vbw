#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIST_CMD="$ROOT/commands/list-todos.md"
DEBUG_CMD="$ROOT/commands/debug.md"
FIX_CMD="$ROOT/commands/fix.md"
VIBE_CMD="$ROOT/commands/vibe.md"
RESEARCH_CMD="$ROOT/commands/research.md"
LIST_SCRIPT="$ROOT/scripts/list-todos.sh"
RESOLVE_SCRIPT="$ROOT/scripts/resolve-todo-item.sh"
LIFECYCLE_SCRIPT="$ROOT/scripts/todo-lifecycle.sh"
TRACK_SCRIPT="$ROOT/scripts/track-known-issues.sh"
COMPILE_SCRIPT="$ROOT/scripts/compile-context.sh"

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

require_grep() {
  local desc="$1"
  local pattern="$2"
  local file="$3"
  if grep -qE "$pattern" "$file"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

require_absent() {
  local desc="$1"
  local pattern="$2"
  local file="$3"
  if grep -qE "$pattern" "$file"; then
    fail "$desc"
  else
    pass "$desc"
  fi
}

echo "=== Todo pickup contract verification ==="

# Shared script surface
require_grep "list-todos.sh emits section_index metadata" 'section_index' "$LIST_SCRIPT"
require_grep "list-todos.sh emits normalized_text metadata" 'normalized_text' "$LIST_SCRIPT"
require_grep "list-todos.sh emits command_text metadata" 'command_text' "$LIST_SCRIPT"
require_grep "resolve-todo-item.sh supports session snapshots" 'session-snapshot' "$RESOLVE_SCRIPT"
require_grep "todo-lifecycle.sh supports pickup command" 'pickup\)' "$LIFECYCLE_SCRIPT"
require_grep "todo-lifecycle.sh supports remove command" 'remove\)' "$LIFECYCLE_SCRIPT"
require_grep "todo-lifecycle.sh supports snapshot-save" 'snapshot-save' "$LIFECYCLE_SCRIPT"
require_grep "track-known-issues.sh supports suppress" 'suppress\)' "$TRACK_SCRIPT"
require_grep "compile-context.sh reads Recent Activity" 'Recent Activity\|Activity Log\|Activity' "$COMPILE_SCRIPT"

# list-todos command surface
require_grep "list-todos persists last-view snapshot" 'todo-lifecycle\.sh" snapshot-save' "$LIST_CMD"
require_grep "list-todos remove uses snapshot resolver" 'resolve-todo-item\.sh" <N> --session-snapshot' "$LIST_CMD"
require_grep "list-todos remove delegates to lifecycle helper" 'todo-lifecycle\.sh" remove' "$LIST_CMD"
require_grep "list-todos filtered view rerun-unfiltered hint exists" 'rerun unfiltered /vbw:list-todos' "$LIST_CMD"
require_absent "list-todos no longer advertises /vbw:research N" '/vbw:research N' "$LIST_CMD"

# debug command surface
require_grep "debug uses snapshot-backed todo resolver" 'resolve-todo-item\.sh" <N> --session-snapshot --require-unfiltered --validate-live' "$DEBUG_CMD"
require_grep "debug writes detail warning through lifecycle helper" 'todo-lifecycle\.sh" detail-warning' "$DEBUG_CMD"
require_grep "debug delegates Source Todo persistence to debug-session-state helper" 'debug-session-state\.sh" start-with-source-todo' "$DEBUG_CMD"
require_grep "debug pickup uses lifecycle helper" 'todo-lifecycle\.sh" pickup /vbw:debug' "$DEBUG_CMD"
require_grep "debug documents helper-owned Source Todo rollback boundary" 'helper owns session creation, `## Source Todo` persistence, and rollback' "$DEBUG_CMD"

# fix command surface
require_grep "fix uses snapshot-backed todo resolver" 'resolve-todo-item\.sh" <N> --session-snapshot --require-unfiltered --validate-live' "$FIX_CMD"
require_grep "fix writes detail warning through lifecycle helper" 'todo-lifecycle\.sh" detail-warning' "$FIX_CMD"
require_grep "fix pickup uses lifecycle helper" 'todo-lifecycle\.sh" pickup /vbw:fix' "$FIX_CMD"

# vibe command surface
require_grep "vibe inspects the todo snapshot" 'todo-lifecycle\.sh" snapshot-show' "$VIBE_CMD"
require_grep "vibe uses snapshot-backed todo resolver" 'resolve-todo-item\.sh" <N> --session-snapshot --require-unfiltered --validate-live' "$VIBE_CMD"
require_grep "vibe preserves filtered-view rerun-unfiltered guard" 'Current list view is filtered — rerun unfiltered /vbw:list-todos before using /vbw:vibe N as a todo pickup' "$VIBE_CMD"
require_grep "vibe eagerly loads detail during Input Parsing for selected todos" 'eagerly load detail during Input Parsing' "$VIBE_CMD"
require_grep "vibe pickup uses lifecycle helper" 'todo-lifecycle\.sh" pickup /vbw:vibe' "$VIBE_CMD"
require_grep "vibe writes detail warning through lifecycle helper" 'todo-lifecycle\.sh" detail-warning' "$VIBE_CMD"

# research warning path
require_grep "research writes detail warning through lifecycle helper" 'todo-lifecycle\.sh" detail-warning' "$RESEARCH_CMD"

echo
 echo "==============================="
 echo "Todo pickup contract: $PASS passed, $FAIL failed"
 echo "==============================="

 [ "$FAIL" -eq 0 ] || exit 1

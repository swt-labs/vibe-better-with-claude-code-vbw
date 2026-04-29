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
require_grep "todo-lifecycle.sh supports list-with-snapshot" 'list-with-snapshot' "$LIFECYCLE_SCRIPT"
require_grep "todo-lifecycle.sh supports snapshot-save" 'snapshot-save' "$LIFECYCLE_SCRIPT"
require_grep "track-known-issues.sh supports suppress" 'suppress\)' "$TRACK_SCRIPT"
require_grep "compile-context.sh reads Recent Activity" 'Recent Activity\|Activity Log\|Activity' "$COMPILE_SCRIPT"

# list-todos command surface
require_grep "list-todos uses helper-backed snapshot capture" 'todo-lifecycle\.sh" list-with-snapshot' "$LIST_CMD"
require_absent "list-todos no longer asks markdown to pipe JSON into snapshot-save" 'todo-lifecycle\.sh" snapshot-save' "$LIST_CMD"
require_grep "list-todos remove uses snapshot resolver" 'resolve-todo-item\.sh" <N> --session-snapshot' "$LIST_CMD"
require_grep "list-todos remove delegates to lifecycle helper" 'todo-lifecycle\.sh" remove' "$LIST_CMD"
require_grep "list-todos filtered view rerun-unfiltered hint exists" 'rerun unfiltered /vbw:list-todos' "$LIST_CMD"
require_grep "list-todos advertises /vbw:research N" '/vbw:research N' "$LIST_CMD"
require_grep "list-todos filtered guard includes /vbw:research N" 'rerun unfiltered /vbw:list-todos before using /vbw:vibe N, /vbw:fix N, /vbw:debug N, or /vbw:research N' "$LIST_CMD"

# debug command surface
require_grep "debug uses snapshot-backed todo resolver" 'resolve-todo-item\.sh" <N> --session-snapshot --require-unfiltered --validate-live' "$DEBUG_CMD"
require_grep "debug writes detail warning through lifecycle helper" 'todo-lifecycle\.sh" detail-warning' "$DEBUG_CMD"
require_grep "debug delegates numbered Source Todo persistence to selected-todo helper" 'debug-session-state\.sh" start-with-selected-todo' "$DEBUG_CMD"
require_absent "debug no longer mentions manual SOURCE_TODO_JSON construction" 'SOURCE_TODO_JSON' "$DEBUG_CMD"
require_grep "debug pickup uses lifecycle helper" 'todo-lifecycle\.sh" pickup /vbw:debug' "$DEBUG_CMD"
require_grep "debug documents helper-owned numbered Source Todo rollback boundary" 'selected-todo helper owns the numbered `/vbw:list-todos` source-todo payload normalization' "$DEBUG_CMD"
require_grep "debug stores pickup status for post-pickup messaging" 'TODO_PICKUP_STATUS=ok[^[:space:]]*partial' "$DEBUG_CMD"
require_grep "debug stores pickup warning for partial cleanup" 'TODO_PICKUP_WARNING' "$DEBUG_CMD"
require_grep "debug stores automatic pickup note" 'TODO_PICKUP_AUTO_NOTE' "$DEBUG_CMD"
require_grep "debug marks pre-pickup numbering as stale after pickup" 'numbered list captured before pickup is stale' "$DEBUG_CMD"
require_grep "debug says selected todo was picked up automatically" 'picked up automatically' "$DEBUG_CMD"
require_grep "debug forbids remove N advice after automatic pickup" 'Never tell the user to `remove N`' "$DEBUG_CMD"
require_grep "debug requires refresh before citing remaining todo numbers" 'Never cite a remaining todo number unless you first refresh' "$DEBUG_CMD"
require_grep "debug reruns list-todos for fresh numbering after pickup" 'Rerun /vbw:list-todos for fresh numbering' "$DEBUG_CMD"
require_grep "debug explicitly surfaces partial pickup warnings" 'TODO_PICKUP_STATUS=partial' "$DEBUG_CMD"

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

# research command surface
require_grep "research uses snapshot-backed todo resolver" 'resolve-todo-item\.sh" <N> --session-snapshot --require-unfiltered --validate-live' "$RESEARCH_CMD"
require_grep "research stores selected todo payload" 'TODO_SELECTED_JSON' "$RESEARCH_CMD"
require_grep "research marks numbered todo selection" 'TODO_SELECTED=true' "$RESEARCH_CMD"
require_grep "research uses selected command text as topic" 'command_text' "$RESEARCH_CMD"
require_grep "research rejects archived milestone selected todos" 'archived milestone state' "$RESEARCH_CMD"
require_grep "research loads selected todo detail through helper" 'todo-details\.sh" get \{hash\}' "$RESEARCH_CMD"
require_grep "research writes detail warning through lifecycle helper" 'todo-lifecycle\.sh" detail-warning' "$RESEARCH_CMD"
require_absent "research does not claim todos automatically" 'todo-lifecycle\.sh" pickup /vbw:research' "$RESEARCH_CMD"

echo
 echo "==============================="
 echo "Todo pickup contract: $PASS passed, $FAIL failed"
 echo "==============================="

 [ "$FAIL" -eq 0 ] || exit 1

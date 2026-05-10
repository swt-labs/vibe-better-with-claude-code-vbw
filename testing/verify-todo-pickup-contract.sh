#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIST_CMD="$ROOT/commands/list-todos.md"
DEBUG_CMD="$ROOT/commands/debug.md"
FIX_CMD="$ROOT/commands/fix.md"
VIBE_CMD="$ROOT/commands/vibe.md"
RESEARCH_CMD="$ROOT/commands/research.md"
LIST_SCRIPT="$ROOT/scripts/list-todos.sh"
DEBUG_START_SCRIPT="$ROOT/scripts/debug-start-selected-todo.sh"
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
if [ -f "$DEBUG_START_SCRIPT" ]; then
  pass "debug-start-selected-todo.sh exists"
else
  fail "debug-start-selected-todo.sh missing"
fi
require_grep "debug-start helper uses snapshot-backed resolver" 'resolve-todo-item\.sh" "\$SELECTION" --session-snapshot --require-unfiltered --validate-live' "$DEBUG_START_SCRIPT"
require_grep "debug-start helper loads selected detail" 'todo-details\.sh" get "\$REF_VALUE"' "$DEBUG_START_SCRIPT"
require_grep "debug-start helper writes detail warning" 'todo-lifecycle\.sh" detail-warning "\$REF_VALUE"' "$DEBUG_START_SCRIPT"
require_grep "debug-start helper creates selected debug session" 'debug-session-state\.sh" start-with-selected-todo' "$DEBUG_START_SCRIPT"
require_grep "debug-start helper owns debug pickup" 'todo-lifecycle\.sh" pickup /vbw:debug' "$DEBUG_START_SCRIPT"
require_grep "debug-start helper supports already-complete repair" 'already_complete' "$DEBUG_START_SCRIPT"
require_grep "debug-start helper returns detail_has_signal" 'detail_has_signal' "$DEBUG_START_SCRIPT"
require_grep "debug-start helper returns accepted_exception_markers" 'accepted_exception_markers' "$DEBUG_START_SCRIPT"
require_grep "debug-start helper preserves routing flags" 'routing_flags' "$DEBUG_START_SCRIPT"
require_grep "debug-start helper emits pickup auto note" 'Selected todo was already picked up automatically' "$DEBUG_START_SCRIPT"
require_grep "debug-start helper knows KNOWN-ISSUE marker" '\[KNOWN-ISSUE\]' "$DEBUG_START_SCRIPT"
require_grep "debug-start helper knows accepted-process-exception disposition marker" 'Disposition:\[\[:space:\]\]\*accepted-process-exception' "$DEBUG_START_SCRIPT"
require_grep "debug-start helper knows known_issue_signature disposition marker" 'known_issue_signature\.disposition' "$DEBUG_START_SCRIPT"
require_grep "debug-start helper knows UAT-DEVIATION marker" '\[UAT-DEVIATION\]' "$DEBUG_START_SCRIPT"
require_grep "debug-start helper knows uat-deviation source marker" 'source: \\"uat-deviation\\"' "$DEBUG_START_SCRIPT"
require_grep "debug-start helper knows uat_deviation object marker" 'uat_deviation' "$DEBUG_START_SCRIPT"
require_grep "debug-start helper knows accepted UAT summary phrase" 'Accepted UAT summary deviation' "$DEBUG_START_SCRIPT"
require_absent "list-todos remains state-backed and does not scan completed debug sessions" 'debugging/completed|Source Todo' "$LIST_SCRIPT"

# list-todos command surface
require_grep "list-todos uses helper-backed snapshot capture" 'todo-lifecycle\.sh" list-with-snapshot' "$LIST_CMD"
require_absent "list-todos no longer asks markdown to pipe JSON into snapshot-save" 'todo-lifecycle\.sh" snapshot-save' "$LIST_CMD"
require_grep "list-todos remove uses snapshot resolver" 'resolve-todo-item\.sh" <N> --session-snapshot' "$LIST_CMD"
require_grep "list-todos remove delegates to lifecycle helper" 'todo-lifecycle\.sh" remove' "$LIST_CMD"
require_grep "list-todos filtered view rerun-unfiltered hint exists" 'rerun unfiltered /vbw:list-todos' "$LIST_CMD"
require_grep "list-todos advertises /vbw:research N" '/vbw:research N' "$LIST_CMD"
require_grep "list-todos filtered guard includes /vbw:research N" 'rerun unfiltered /vbw:list-todos before using /vbw:vibe N, /vbw:fix N, /vbw:debug N, or /vbw:research N' "$LIST_CMD"

# debug command surface
require_grep "debug documents selected-todo helper contract" '<selected_todo_start_helper>' "$DEBUG_CMD"
require_grep "debug calls selected-todo start helper" 'debug-start-selected-todo\.sh" \.vbw-planning <N>' "$DEBUG_CMD"
require_grep "debug detects selected-todo mode after stripping supported routing flags" 'after removing only supported routing flags' "$DEBUG_CMD"
require_grep "debug lists supported selected-todo routing flags" '.*--competing.*--parallel.*--serial|.*--parallel.*--serial.*--competing' "$DEBUG_CMD"
require_grep "debug treats helper output as single source of truth" 'single source of truth for selected-todo startup' "$DEBUG_CMD"
require_grep "debug states helper owns selected-todo state mutation" 'The helper owns numbered selection resolution, optional detail loading, completed-session stale-state repair, debug session creation, `## Source Todo` persistence, and selected-todo pickup' "$DEBUG_CMD"
require_grep "debug stores selected helper payload" 'SELECTED_TODO_START_JSON' "$DEBUG_CMD"
require_grep "debug selected path consumes helper detail_has_signal" 'detail_has_signal' "$DEBUG_CMD"
require_grep "debug selected path consumes helper accepted_exception_markers" 'accepted_exception_markers' "$DEBUG_CMD"
require_grep "debug selected path consumes helper pickup fields" '\.pickup\.status.*\.pickup\.warning.*\.pickup\.auto_note' "$DEBUG_CMD"
require_absent "debug no longer preserves selected todo JSON" 'TODO_SELECTED_JSON' "$DEBUG_CMD"
require_absent "debug no longer preserves selected raw detail helper JSON" 'TODO_DETAIL_RESULT_JSON' "$DEBUG_CMD"
require_absent "debug no longer pipes selected todo JSON into start-with-selected-todo" 'debug-session-state\.sh" start-with-selected-todo' "$DEBUG_CMD"
require_absent "debug no longer runs selected-todo pickup directly" 'todo-lifecycle\.sh" pickup /vbw:debug' "$DEBUG_CMD"
require_absent "debug no longer mentions manual SOURCE_TODO_JSON construction" 'SOURCE_TODO_JSON' "$DEBUG_CMD"
require_grep "debug marks pre-pickup numbering as stale after pickup" 'numbered list captured before pickup is stale' "$DEBUG_CMD"
require_grep "debug says selected todo was picked up automatically" 'picked up automatically' "$DEBUG_CMD"
require_grep "debug forbids remove N advice after automatic pickup" 'Never tell the user to `remove N`' "$DEBUG_CMD"
require_grep "debug requires refresh before citing remaining todo numbers" 'Never cite a remaining todo number unless you first refresh' "$DEBUG_CMD"
require_grep "debug reruns list-todos for fresh numbering after pickup" 'Rerun /vbw:list-todos for fresh numbering' "$DEBUG_CMD"
require_grep "debug explicitly surfaces partial pickup warnings" '\.pickup\.status` is `partial`' "$DEBUG_CMD"

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
require_grep "research loads selected todo detail through helper" 'todo-details\.sh" get <hash>' "$RESEARCH_CMD"
require_grep "research writes detail warning through lifecycle helper" 'todo-lifecycle\.sh" detail-warning <hash>' "$RESEARCH_CMD"
require_grep "research manual detail records ok status" 'Parse the JSON output\. If `status` is `"ok"`, store `DETAIL_STATUS=ok`' "$RESEARCH_CMD"
require_grep "research no-ref path records none detail status" 'If no ref suffix, set `DETAIL_STATUS=none`' "$RESEARCH_CMD"
require_grep "research empty-topic validation uses detail status" 'AND `DETAIL_STATUS=ok`' "$RESEARCH_CMD"
require_absent "research does not claim todos automatically" 'todo-lifecycle\.sh" pickup /vbw:research' "$RESEARCH_CMD"
require_absent "research does not remove todos automatically" 'todo-lifecycle\.sh" remove' "$RESEARCH_CMD"

echo
 echo "==============================="
 echo "Todo pickup contract: $PASS passed, $FAIL failed"
 echo "==============================="

 [ "$FAIL" -eq 0 ] || exit 1

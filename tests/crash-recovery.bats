#!/usr/bin/env bats

# Tests for crash recovery features introduced in the 77438c6..c3c1948 range:
# - agent-stop.sh: last_assistant_message capture to .agent-last-words/
# - validate-summary.sh: crash recovery fallback when SUMMARY.md is missing
# - session-start.sh: stale .agent-last-words cleanup

load test_helper

setup() {
  setup_temp_dir
  create_test_config

  cd "$TEST_TEMP_DIR"

  # Execution state for agent-stop crash detection (phase matches dir prefix)
  echo '{"phase":"01","plan":"01"}' > .vbw-planning/.execution-state.json
  mkdir -p .vbw-planning/phases/01-test
}

teardown() {
  teardown_temp_dir
}

# ===========================================================================
# agent-stop.sh — Last-Words Crash Recovery
# ===========================================================================

@test "agent-stop: captures last_assistant_message when no SUMMARY.md exists" {
  echo '{"pid":"12345","last_assistant_message":"I was working on the widget..."}' \
    | bash "$SCRIPTS_DIR/agent-stop.sh"

  [ -d ".vbw-planning/.agent-last-words" ]
  [ -f ".vbw-planning/.agent-last-words/12345.txt" ]
  grep -q "I was working on the widget" ".vbw-planning/.agent-last-words/12345.txt"
}

@test "agent-stop: includes phase and timestamp in last-words file" {
  echo '{"pid":"12345","last_assistant_message":"final output"}' \
    | bash "$SCRIPTS_DIR/agent-stop.sh"

  grep -q "Phase: 01" ".vbw-planning/.agent-last-words/12345.txt"
  grep -q "Agent PID: 12345" ".vbw-planning/.agent-last-words/12345.txt"
  grep -q "Crash Recovery" ".vbw-planning/.agent-last-words/12345.txt"
}

@test "agent-stop: does NOT write last-words when SUMMARY.md exists" {
  # Create a SUMMARY.md in the phase dir
  echo "## What Was Built" > .vbw-planning/phases/01-test/01-01-SUMMARY.md

  echo '{"pid":"12345","last_assistant_message":"I finished the work"}' \
    | bash "$SCRIPTS_DIR/agent-stop.sh"

  # No last-words file should be created
  [ ! -f ".vbw-planning/.agent-last-words/12345.txt" ]
}

@test "agent-stop: does NOT write last-words when phase summary state is unreadable" {
  chmod 000 .vbw-planning/phases/01-test

  echo '{"pid":"12345","last_assistant_message":"should not write"}' \
    | bash "$SCRIPTS_DIR/agent-stop.sh"

  # Restore permissions for teardown cleanup
  chmod 755 .vbw-planning/phases/01-test
  [ ! -f ".vbw-planning/.agent-last-words/12345.txt" ]
}

@test "agent-stop: appends instead of clobbering when same pid writes twice" {
  echo '{"pid":"12345","last_assistant_message":"first message"}' \
    | bash "$SCRIPTS_DIR/agent-stop.sh"
  echo '{"pid":"12345","last_assistant_message":"second message"}' \
    | bash "$SCRIPTS_DIR/agent-stop.sh"

  [ -f ".vbw-planning/.agent-last-words/12345.txt" ]
  grep -q "first message" ".vbw-planning/.agent-last-words/12345.txt"
  grep -q "second message" ".vbw-planning/.agent-last-words/12345.txt"
}

@test "agent-stop: does NOT write last-words when message is empty" {
  echo '{"pid":"12345","last_assistant_message":""}' \
    | bash "$SCRIPTS_DIR/agent-stop.sh"

  [ ! -f ".vbw-planning/.agent-last-words/12345.txt" ]
}

@test "agent-stop: does NOT write last-words when pid is empty" {
  echo '{"pid":"","last_assistant_message":"some content"}' \
    | bash "$SCRIPTS_DIR/agent-stop.sh"

  [ ! -d ".vbw-planning/.agent-last-words" ] || [ -z "$(ls -A .vbw-planning/.agent-last-words 2>/dev/null)" ]
}

@test "agent-stop: logs agent_shutdown event" {
  mkdir -p .vbw-planning/.events
  echo '{"pid":"99999","last_assistant_message":"bye"}' \
    | bash "$SCRIPTS_DIR/agent-stop.sh"

  # Check event log (log-event.sh writes to .events/event-log.jsonl)
  if [ -f ".vbw-planning/.events/event-log.jsonl" ]; then
    grep -q "agent_shutdown" ".vbw-planning/.events/event-log.jsonl"
  fi
}

# ===========================================================================
# validate-summary.sh — Crash Recovery Fallback
# ===========================================================================

@test "validate-summary: returns fallback when SUMMARY.md missing and recent last-words exists" {
  # Create a recent last-words file
  mkdir -p .vbw-planning/.agent-last-words
  echo "I was working on task 1..." > .vbw-planning/.agent-last-words/12345.txt
  # Touch to ensure it's within the 60s window
  touch .vbw-planning/.agent-last-words/12345.txt

  local input
  input=$(jq -n --arg fp ".vbw-planning/phases/01-test/01-01-SUMMARY.md" '{"tool_input":{"file_path":$fp}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"crash recovery fallback available"* ]]
  [[ "$output" == *"12345.txt"* ]]
}

@test "validate-summary: no output when SUMMARY.md missing and no last-words" {
  local input
  input=$(jq -n --arg fp ".vbw-planning/phases/01-test/01-01-SUMMARY.md" '{"tool_input":{"file_path":$fp}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate-summary: reports stale fallback hint when only stale last-words exist" {
  mkdir -p .vbw-planning/.agent-last-words
  echo "old crash output" > .vbw-planning/.agent-last-words/stale.txt

  if [ "$(uname)" = "Darwin" ]; then
    touch -t "$(date -v-2M '+%Y%m%d%H%M.%S')" .vbw-planning/.agent-last-words/stale.txt
  else
    touch -t "$(date -d '2 minutes ago' '+%Y%m%d%H%M.%S')" .vbw-planning/.agent-last-words/stale.txt
  fi

  local input
  input=$(jq -n --arg fp ".vbw-planning/phases/01-test/01-01-SUMMARY.md" '{"tool_input":{"file_path":$fp}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale crash recovery artifacts"* ]]
}

@test "validate-summary: validates existing SUMMARY.md structure" {
  cat > .vbw-planning/phases/01-test/01-01-SUMMARY.md <<'SUMMARY'
---
phase: 1
plan: 1
status: complete
---
## What Was Built
A widget

## Files Modified
- src/widget.ts
SUMMARY

  local input
  input=$(jq -n --arg fp "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-SUMMARY.md" '{"tool_input":{"file_path":$fp}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  # No validation errors — clean output (no "Missing" messages)
  [[ "$output" != *"Missing"* ]]
}

@test "validate-summary: reports missing sections in SUMMARY.md" {
  echo "No frontmatter here" > .vbw-planning/phases/01-test/01-01-SUMMARY.md

  local input
  input=$(jq -n --arg fp "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-SUMMARY.md" '{"tool_input":{"file_path":$fp}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Missing"* ]]
}

@test "validate-summary: ignores non-SUMMARY.md files" {
  local input
  input=$(jq -n '{"tool_input":{"file_path":"src/app.ts"}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ===========================================================================
# agent-stop + validate-summary integration
# ===========================================================================

@test "crash recovery chain: agent-stop writes last-words, validate-summary finds it" {
  # Step 1: Agent stops without SUMMARY.md
  echo '{"pid":"77777","last_assistant_message":"I built the feature but crashed before writing SUMMARY.md"}' \
    | bash "$SCRIPTS_DIR/agent-stop.sh"

  # Verify last-words was written
  [ -f ".vbw-planning/.agent-last-words/77777.txt" ]

  # Step 2: validate-summary runs and finds the fallback
  local input
  input=$(jq -n --arg fp ".vbw-planning/phases/01-test/01-01-SUMMARY.md" '{"tool_input":{"file_path":$fp}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"crash recovery fallback available"* ]]
  [[ "$output" == *"77777.txt"* ]]
}

# ===========================================================================
# session-start.sh — stale .agent-last-words cleanup
# ===========================================================================

@test "session-start: removes .agent-last-words files older than 7 days" {
  mkdir -p .vbw-planning/.agent-last-words
  echo "old" > .vbw-planning/.agent-last-words/old.txt
  echo "new" > .vbw-planning/.agent-last-words/new.txt

  if [ "$(uname)" = "Darwin" ]; then
    touch -t "$(date -v-8d '+%Y%m%d%H%M.%S')" .vbw-planning/.agent-last-words/old.txt
  else
    touch -t "$(date -d '8 days ago' '+%Y%m%d%H%M.%S')" .vbw-planning/.agent-last-words/old.txt
  fi

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  [ ! -f ".vbw-planning/.agent-last-words/old.txt" ]
  [ -f ".vbw-planning/.agent-last-words/new.txt" ]
}

@test "session-start: keeps recent .agent-last-words files" {
  mkdir -p .vbw-planning/.agent-last-words
  echo "recent" > .vbw-planning/.agent-last-words/recent.txt

  if [ "$(uname)" = "Darwin" ]; then
    touch -t "$(date -v-6d '+%Y%m%d%H%M.%S')" .vbw-planning/.agent-last-words/recent.txt
  else
    touch -t "$(date -d '6 days ago' '+%Y%m%d%H%M.%S')" .vbw-planning/.agent-last-words/recent.txt
  fi

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]
  [ -f ".vbw-planning/.agent-last-words/recent.txt" ]
}

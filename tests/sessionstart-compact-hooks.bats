#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  cd "$TEST_TEMP_DIR"

  # Init git so map-staleness.sh and session-start.sh work
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > init.txt && git add init.txt && git commit -q -m "init"

  # Create minimal STATE.md for session-start.sh
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'STATE'
Phase: 1 of 2 (Setup)
Status: in-progress
Progress: 50%
STATE

  # Create phases dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"

  # Create PROJECT.md so session-start doesn't suggest /vbw:init
  echo "# Test Project" > "$TEST_TEMP_DIR/.vbw-planning/PROJECT.md"
}

teardown() {
  teardown_temp_dir
}

# --- session-start.sh compact skip ---

@test "session-start: skips heavy init when fresh compaction marker present" {
  cd "$TEST_TEMP_DIR"
  date +%s > .vbw-planning/.compaction-marker
  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]
  # Should produce NO output (skipped entirely)
  [ -z "$output" ]
}

@test "session-start: runs normally when no compaction marker" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]
  # Should produce hookSpecificOutput JSON
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
}

@test "session-start: runs normally when compaction marker is stale (>60s)" {
  cd "$TEST_TEMP_DIR"
  # Write a timestamp 120 seconds in the past
  echo $(( $(date +%s) - 120 )) > .vbw-planning/.compaction-marker
  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]
  # Should produce hookSpecificOutput JSON (did not skip)
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
  # Stale marker should be cleaned up
  [ ! -f ".vbw-planning/.compaction-marker" ]
}

# --- map-staleness.sh compact skip ---

@test "map-staleness: skips when fresh compaction marker present" {
  cd "$TEST_TEMP_DIR"
  date +%s > .vbw-planning/.compaction-marker
  run bash "$SCRIPTS_DIR/map-staleness.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "map-staleness: runs normally when no compaction marker" {
  cd "$TEST_TEMP_DIR"
  # bats `run` captures both stdout+stderr; use explicit redirect to test stdout only
  stdout=$(bash "$SCRIPTS_DIR/map-staleness.sh" 2>/dev/null)
  [ -z "$stdout" ]
  # stderr should have the diagnostic
  stderr=$(bash "$SCRIPTS_DIR/map-staleness.sh" 2>&1 >/dev/null)
  [[ "$stderr" == *"status: no_map"* ]]
}

@test "map-staleness: no plain text on stdout when running as hook (no map)" {
  cd "$TEST_TEMP_DIR"
  # Pipe forces non-tty (hook mode). Only JSON should go to stdout.
  result=$(bash "$SCRIPTS_DIR/map-staleness.sh" 2>/dev/null)
  [ -z "$result" ]
}

# --- post-compact.sh marker cleanup ---

@test "post-compact: cleans compaction marker" {
  cd "$TEST_TEMP_DIR"
  date +%s > .vbw-planning/.compaction-marker
  [ -f ".vbw-planning/.compaction-marker" ]
  echo '{}' | bash "$SCRIPTS_DIR/post-compact.sh"
  [ ! -f ".vbw-planning/.compaction-marker" ]
}

@test "post-compact: produces valid hookSpecificOutput JSON" {
  cd "$TEST_TEMP_DIR"
  run bash -c 'echo "{}" | bash "$1"' _ "$SCRIPTS_DIR/post-compact.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
}

@test "post-compact: restores role-matched snapshot and infers pending plan" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_snapshot_resume = true' .vbw-planning/config.json > .vbw-planning/config.json.tmp && \
    mv .vbw-planning/config.json.tmp .vbw-planning/config.json

  cat > .vbw-planning/.execution-state.json <<'STATE'
{"phase":1,"status":"running"}
STATE

  mkdir -p .vbw-planning/.snapshots .vbw-planning/.events
  cat > .vbw-planning/.snapshots/1-20260101T000000.json <<'SNAP1'
{"snapshot_ts":"20260101T000000","phase":1,"agent_role":"vbw-qa","execution_state":{"status":"running","plans":[{"id":"01-02","status":"pending"}]},"recent_commits":[]}
SNAP1
  cat > .vbw-planning/.snapshots/1-20260101T000001.json <<'SNAP2'
{"snapshot_ts":"20260101T000001","phase":1,"agent_role":"vbw-dev","execution_state":{"status":"running","plans":[{"id":"01-01","status":"complete"},{"id":"01-02","status":"pending"}]},"recent_commits":[]}
SNAP2

  # Task 1 completed, task 2 started and not completed yet
  cat > .vbw-planning/.events/event-log.jsonl <<'EVENTS'
{"event":"task_completed_confirmed","phase":1,"plan":2,"data":{"task_id":"1-2-T1"}}
{"event":"task_started","phase":1,"plan":2,"data":{"task_id":"1-2-T2"}}
EVENTS

  run bash -c 'echo "{\"agent_name\":\"vbw-dev\"}" | bash "$1"' _ "$SCRIPTS_DIR/post-compact.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("plan=01-02")' >/dev/null
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("In-progress task before compact: 1-2-T2.")' >/dev/null
}

# --- hook-wrapper.sh exit code passthrough ---

@test "hook-wrapper: passes through exit 2 for PreToolUse block" {
  cd "$TEST_TEMP_DIR"
  # Create a mock script that exits 2
  mkdir -p "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts"
  cat > "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts/hook-wrapper.sh" <<'WRAPPER'
#!/bin/bash
SCRIPT="$1"; shift
[ -z "$SCRIPT" ] && exit 0
CACHE="$(dirname "$0")/.."
TARGET="$CACHE/scripts/$SCRIPT"
[ -z "$TARGET" ] || [ ! -f "$TARGET" ] && exit 0
bash "$TARGET" "$@"
RC=$?
[ "$RC" -eq 0 ] && exit 0
[ "$RC" -eq 2 ] && exit 2
exit 0
WRAPPER
  cat > "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts/mock-block.sh" <<'MOCK'
#!/bin/bash
echo "Blocked: test" >&2
exit 2
MOCK
  chmod +x "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts/hook-wrapper.sh"
  chmod +x "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts/mock-block.sh"
  run bash "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts/hook-wrapper.sh" mock-block.sh
  [ "$status" -eq 2 ]
}

@test "hook-wrapper: exit 0 for successful scripts" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts"
  cat > "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts/hook-wrapper.sh" <<'WRAPPER'
#!/bin/bash
SCRIPT="$1"; shift
[ -z "$SCRIPT" ] && exit 0
CACHE="$(dirname "$0")/.."
TARGET="$CACHE/scripts/$SCRIPT"
[ -z "$TARGET" ] || [ ! -f "$TARGET" ] && exit 0
bash "$TARGET" "$@"
RC=$?
[ "$RC" -eq 0 ] && exit 0
[ "$RC" -eq 2 ] && exit 2
exit 0
WRAPPER
  cat > "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts/mock-allow.sh" <<'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts/hook-wrapper.sh"
  chmod +x "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts/mock-allow.sh"
  run bash "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts/hook-wrapper.sh" mock-allow.sh
  [ "$status" -eq 0 ]
}

@test "hook-wrapper: exit 0 for failing scripts (graceful degradation)" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts"
  cat > "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts/hook-wrapper.sh" <<'WRAPPER'
#!/bin/bash
SCRIPT="$1"; shift
[ -z "$SCRIPT" ] && exit 0
CACHE="$(dirname "$0")/.."
TARGET="$CACHE/scripts/$SCRIPT"
[ -z "$TARGET" ] || [ ! -f "$TARGET" ] && exit 0
bash "$TARGET" "$@"
RC=$?
[ "$RC" -eq 0 ] && exit 0
[ "$RC" -eq 2 ] && exit 2
exit 0
WRAPPER
  cat > "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts/mock-fail.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
  chmod +x "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts/hook-wrapper.sh"
  chmod +x "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts/mock-fail.sh"
  run bash "$TEST_TEMP_DIR/mock-cache/1.0.0/scripts/hook-wrapper.sh" mock-fail.sh
  [ "$status" -eq 0 ]
}

# --- hook-wrapper.sh CLAUDE_PLUGIN_ROOT fallback ---

@test "hook-wrapper: falls back to CLAUDE_PLUGIN_ROOT when cache is empty" {
  cd "$TEST_TEMP_DIR"
  # Set up: no cache, but CLAUDE_PLUGIN_ROOT points to real scripts
  mkdir -p "$TEST_TEMP_DIR/fake-plugin/scripts"
  cp "$SCRIPTS_DIR/hook-wrapper.sh" "$TEST_TEMP_DIR/fake-plugin/scripts/"
  cp "$SCRIPTS_DIR/resolve-claude-dir.sh" "$TEST_TEMP_DIR/fake-plugin/scripts/"
  cat > "$TEST_TEMP_DIR/fake-plugin/scripts/mock-ok.sh" <<'MOCK'
#!/bin/bash
echo "OK from plugin root"
exit 0
MOCK
  chmod +x "$TEST_TEMP_DIR/fake-plugin/scripts/mock-ok.sh"

  # HOME points to empty dir (no cache), CLAUDE_PLUGIN_ROOT points to fake plugin
  run bash -c "export HOME='$TEST_TEMP_DIR/empty-home'; export CLAUDE_PLUGIN_ROOT='$TEST_TEMP_DIR/fake-plugin'; bash '$TEST_TEMP_DIR/fake-plugin/scripts/hook-wrapper.sh' mock-ok.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK from plugin root"* ]]
}

@test "hook-wrapper: prefers cache over CLAUDE_PLUGIN_ROOT when both exist" {
  cd "$TEST_TEMP_DIR"
  # Set up cache with a script
  mkdir -p "$TEST_TEMP_DIR/.claude/plugins/cache/vbw-marketplace/vbw/1.0.0/scripts"
  cp "$SCRIPTS_DIR/hook-wrapper.sh" "$TEST_TEMP_DIR/.claude/plugins/cache/vbw-marketplace/vbw/1.0.0/scripts/"
  cp "$SCRIPTS_DIR/resolve-claude-dir.sh" "$TEST_TEMP_DIR/.claude/plugins/cache/vbw-marketplace/vbw/1.0.0/scripts/"
  cat > "$TEST_TEMP_DIR/.claude/plugins/cache/vbw-marketplace/vbw/1.0.0/scripts/mock-source.sh" <<'MOCK'
#!/bin/bash
echo "FROM_CACHE"
exit 0
MOCK
  chmod +x "$TEST_TEMP_DIR/.claude/plugins/cache/vbw-marketplace/vbw/1.0.0/scripts/mock-source.sh"

  # Also set up CLAUDE_PLUGIN_ROOT with a different script
  mkdir -p "$TEST_TEMP_DIR/fake-plugin/scripts"
  cat > "$TEST_TEMP_DIR/fake-plugin/scripts/mock-source.sh" <<'MOCK'
#!/bin/bash
echo "FROM_PLUGIN_ROOT"
exit 0
MOCK
  chmod +x "$TEST_TEMP_DIR/fake-plugin/scripts/mock-source.sh"

  # Cache should win
  run bash -c "export HOME='$TEST_TEMP_DIR'; export CLAUDE_PLUGIN_ROOT='$TEST_TEMP_DIR/fake-plugin'; bash '$TEST_TEMP_DIR/.claude/plugins/cache/vbw-marketplace/vbw/1.0.0/scripts/hook-wrapper.sh' mock-source.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FROM_CACHE"* ]]
}

# --- security-filter.sh integration (exit 2 should block) ---

@test "security-filter: blocks .env file with exit 2" {
  cd "$TEST_TEMP_DIR"
  INPUT='{"tool_name":"Read","tool_input":{"file_path":".env"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
}

@test "security-filter: allows normal file with exit 0" {
  cd "$TEST_TEMP_DIR"
  INPUT='{"tool_name":"Read","tool_input":{"file_path":"src/app.js"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
}

@test "security-filter: exit 2 preserved through hook-wrapper logic" {
  # Verify that the hook-wrapper exit-code logic preserves exit 2
  # (This tests the actual hook-wrapper.sh, not the mock)
  cd "$TEST_TEMP_DIR"

  # Create a fake plugin cache with the real hook-wrapper and security-filter
  mkdir -p "$TEST_TEMP_DIR/.claude/plugins/cache/vbw-marketplace/vbw/1.0.0/scripts"
  cp "$SCRIPTS_DIR/hook-wrapper.sh" "$TEST_TEMP_DIR/.claude/plugins/cache/vbw-marketplace/vbw/1.0.0/scripts/"
  cp "$SCRIPTS_DIR/security-filter.sh" "$TEST_TEMP_DIR/.claude/plugins/cache/vbw-marketplace/vbw/1.0.0/scripts/"
  cp "$SCRIPTS_DIR/resolve-claude-dir.sh" "$TEST_TEMP_DIR/.claude/plugins/cache/vbw-marketplace/vbw/1.0.0/scripts/"

  INPUT='{"tool_name":"Read","tool_input":{"file_path":".env"}}'
  run bash -c "export HOME='$TEST_TEMP_DIR'; echo '$INPUT' | bash '$TEST_TEMP_DIR/.claude/plugins/cache/vbw-marketplace/vbw/1.0.0/scripts/hook-wrapper.sh' security-filter.sh"
  [ "$status" -eq 2 ]
}

#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export HEALTH_DIR="$TEST_TEMP_DIR/.vbw-planning/.agent-health"
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/.claude"
}

teardown() {
  unset CLAUDE_CONFIG_DIR
  teardown_temp_dir
}

# Integration Test 1: Health file lifecycle (start → idle → stop)
@test "agent-health integration: lifecycle start → idle → stop" {
  cd "$TEST_TEMP_DIR"

  local live_pid
  assign_live_pid live_pid || fail "assign_live_pid failed"
  kill -0 "$live_pid" 2>/dev/null || fail "live pid fixture is not alive"

  # Simulate SubagentStart hook
  echo "{\"pid\":\"$live_pid\",\"agent_type\":\"vbw-dev\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  # Verify health file created
  [ -f "$HEALTH_DIR/dev.json" ]
  run jq -r '.pid' "$HEALTH_DIR/dev.json"
  [ "$output" = "$live_pid" ]
  run jq -r '.idle_count' "$HEALTH_DIR/dev.json"
  [ "$output" = "0" ]

  # Simulate TeammateIdle hook
  echo '{"agent_type":"vbw-dev"}' | bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null

  # Verify idle_count incremented
  run jq -r '.idle_count' "$HEALTH_DIR/dev.json"
  [ "$output" = "1" ]

  # Simulate SubagentStop hook
  echo '{"agent_type":"vbw-dev"}' | bash "$SCRIPTS_DIR/agent-health.sh" stop >/dev/null

  # Verify health file removed
  [ ! -f "$HEALTH_DIR/dev.json" ]
}

# Integration Test 2: Orphan recovery (idle with dead PID clears task owner)
@test "agent-health integration: orphan recovery" {
  cd "$TEST_TEMP_DIR"

  # Setup isolated mock tasks directory
  TASKS_DIR="$CLAUDE_CONFIG_DIR/tasks/test-team-$$"
  mkdir -p "$TASKS_DIR"

  cat > "$TASKS_DIR/task-orphan.json" <<EOF
{
  "id": "task-orphan",
  "owner": "dev",
  "status": "in_progress",
  "subject": "Orphaned task"
}
EOF

  # Create health file with dead PID
  local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  echo "{\"pid\":\"$dead_pid\",\"agent_type\":\"vbw-dev\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  # Verify health file created
  [ -f "$HEALTH_DIR/dev.json" ]

  # Simulate TeammateIdle hook with dead PID
  run bash -c "echo '{\"agent_type\":\"vbw-dev\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle | jq -r '.hookSpecificOutput.additionalContext'"

  # Verify orphan recovery message
  [[ "$output" == *"Orphan recovery"* ]]
  [[ "$output" == *"task-orphan"* ]]
  [[ "$output" == *"PID $dead_pid is dead"* ]]

  # Verify task owner cleared
  run jq -r '.owner' "$TASKS_DIR/task-orphan.json"
  [ "$output" = "" ]

  # Cleanup
  rm -rf "$TASKS_DIR"
}

# Integration Test 3: Stuck agent detection (3 consecutive idles)
@test "agent-health integration: stuck agent detection" {
  cd "$TEST_TEMP_DIR"

  local live_pid
  assign_live_pid live_pid || fail "assign_live_pid failed"
  kill -0 "$live_pid" 2>/dev/null || fail "live pid fixture is not alive"

  # Simulate SubagentStart
  echo "{\"pid\":\"$live_pid\",\"agent_type\":\"vbw-qa\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  # First idle: idle_count = 1
  run bash -c "echo '{\"agent_type\":\"vbw-qa\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle | jq -r '.hookSpecificOutput.additionalContext'"
  [ "$output" = "" ]
  run jq -r '.idle_count' "$HEALTH_DIR/qa.json"
  [ "$output" = "1" ]

  # Second idle: idle_count = 2
  run bash -c "echo '{\"agent_type\":\"vbw-qa\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle | jq -r '.hookSpecificOutput.additionalContext'"
  [ "$output" = "" ]
  run jq -r '.idle_count' "$HEALTH_DIR/qa.json"
  [ "$output" = "2" ]

  # Third idle: idle_count = 3, stuck advisory appears
  run bash -c "echo '{\"agent_type\":\"vbw-qa\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle | jq -r '.hookSpecificOutput.additionalContext'"
  [[ "$output" == *"stuck"* ]]
  [[ "$output" == *"idle_count=3"* ]]
  run jq -r '.idle_count' "$HEALTH_DIR/qa.json"
  [ "$output" = "3" ]
}

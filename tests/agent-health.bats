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

# Test 1: start creates health file
@test "agent-health: start creates health file" {
  cd "$TEST_TEMP_DIR"
  echo '{"pid":"12345","agent_type":"vbw-dev"}' | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  [ -f "$HEALTH_DIR/dev.json" ]
  run jq -r '.pid' "$HEALTH_DIR/dev.json"
  [ "$output" = "12345" ]
  run jq -r '.role' "$HEALTH_DIR/dev.json"
  [ "$output" = "dev" ]
  run jq -r '.idle_count' "$HEALTH_DIR/dev.json"
  [ "$output" = "0" ]
}

@test "agent-health: start prefers agent_id for health file key" {
  cd "$TEST_TEMP_DIR"
  echo '{"pid":"12345","agent_id":"dev-01","agent_type":"vbw-dev","name":"legacy-dev"}' | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  [ -f "$HEALTH_DIR/dev-01.json" ]
  run jq -r '.key' "$HEALTH_DIR/dev-01.json"
  [ "$output" = "dev-01" ]
  run jq -r '.role' "$HEALTH_DIR/dev-01.json"
  [ "$output" = "dev" ]
}

# Test 2: idle increments count
@test "agent-health: idle increments count" {
  cd "$TEST_TEMP_DIR"
  # Create health file with a long-lived PID (PID 1 on Linux/macOS is init)
  # For test purposes, we'll use a background sleep process
  sleep 30 &
  SLEEP_PID=$!
  echo "{\"pid\":\"$SLEEP_PID\",\"agent_type\":\"vbw-qa\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  # Run idle
  echo '{"agent_type":"vbw-qa"}' | bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null

  # Check idle count
  run jq -r '.idle_count' "$HEALTH_DIR/qa.json"
  [ "$output" = "1" ]

  # Cleanup
  kill $SLEEP_PID 2>/dev/null || true
}

# Test 3: idle stuck advisory at count >= 3
@test "agent-health: idle stuck advisory" {
  cd "$TEST_TEMP_DIR"
  sleep 30 &
  SLEEP_PID=$!
  echo "{\"pid\":\"$SLEEP_PID\",\"agent_type\":\"vbw-scout\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  # Run idle 3 times
  for i in 1 2 3; do
    echo '{"agent_type":"vbw-scout"}' | bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null
  done

  # Fourth call should have stuck advisory
  run bash -c "echo '{\"agent_type\":\"vbw-scout\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle | jq -r '.hookSpecificOutput.additionalContext'"
  [[ "$output" == *"stuck"* ]]
  [[ "$output" == *"idle_count=4"* ]]

  kill $SLEEP_PID 2>/dev/null || true
}

# Test 4: orphan recovery clears owner
@test "agent-health: orphan recovery clears owner" {
  cd "$TEST_TEMP_DIR"
  # Setup isolated mock tasks directory
  TASKS_DIR="$CLAUDE_CONFIG_DIR/tasks/test-team-$$"
  mkdir -p "$TASKS_DIR"

  cat > "$TASKS_DIR/task-test.json" <<EOF
{
  "id": "task-test",
  "owner": "dev",
  "status": "in_progress",
  "subject": "Test task"
}
EOF

  # Create health file with dead PID
  echo '{"pid":"99999","agent_type":"vbw-dev"}' | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  # Run idle — should detect dead PID and clear owner
  run bash -c "echo '{\"agent_type\":\"vbw-dev\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle | jq -r '.hookSpecificOutput.additionalContext'"
  [[ "$output" == *"Orphan recovery"* ]]
  [[ "$output" == *"task-test"* ]]

  # Check task owner cleared
  run jq -r '.owner' "$TASKS_DIR/task-test.json"
  [ "$output" = "" ]

  # Cleanup
  rm -rf "$TASKS_DIR"
}

@test "agent-health: stop orphan recovery still uses role when key comes from agent_id" {
  cd "$TEST_TEMP_DIR"
  TASKS_DIR="$CLAUDE_CONFIG_DIR/tasks/test-team-stop-$$"
  mkdir -p "$TASKS_DIR"

  cat > "$TASKS_DIR/task-stop.json" <<EOF
{
  "id": "task-stop",
  "owner": "dev",
  "status": "in_progress",
  "subject": "Stop recovery task"
}
EOF

  echo '{"pid":"99998","agent_id":"dev-01","agent_type":"vbw-dev"}' | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  run bash -c "echo '{\"pid\":\"99998\",\"agent_id\":\"dev-01\",\"agent_type\":\"vbw-dev\"}' | bash '$SCRIPTS_DIR/agent-health.sh' stop | jq -r '.hookSpecificOutput.additionalContext'"
  [[ "$output" == *"task-stop"* ]]

  run jq -r '.owner' "$TASKS_DIR/task-stop.json"
  [ "$output" = "" ]

  rm -rf "$TASKS_DIR"
}

# Test 5: stop removes health file
@test "agent-health: stop removes health file" {
  cd "$TEST_TEMP_DIR"
  sleep 30 &
  SLEEP_PID=$!
  echo "{\"pid\":\"$SLEEP_PID\",\"agent_type\":\"vbw-qa\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  # Verify file exists
  [ -f "$HEALTH_DIR/qa.json" ]

  # Stop
  echo '{"agent_type":"vbw-qa"}' | bash "$SCRIPTS_DIR/agent-health.sh" stop >/dev/null

  # Verify file removed
  [ ! -f "$HEALTH_DIR/qa.json" ]

  kill $SLEEP_PID 2>/dev/null || true
}

# Test 6: cleanup removes directory
@test "agent-health: cleanup removes directory" {
  cd "$TEST_TEMP_DIR"
  # Create health files
  mkdir -p "$HEALTH_DIR"
  echo '{"pid":"1","role":"dev"}' > "$HEALTH_DIR/dev.json"
  echo '{"pid":"2","role":"qa"}' > "$HEALTH_DIR/qa.json"

  # Verify directory exists
  [ -d "$HEALTH_DIR" ]

  # Cleanup
  bash "$SCRIPTS_DIR/agent-health.sh" cleanup

  # Verify directory removed
  [ ! -d "$HEALTH_DIR" ]
}

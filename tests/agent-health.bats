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

run_health_via_wrapper() {
  local cmd="$1"
  local payload="$2"
  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$payload' | CLAUDE_PLUGIN_ROOT='$PROJECT_ROOT' bash '$SCRIPTS_DIR/hook-wrapper.sh' agent-health.sh '$cmd'"
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
  echo '{"pid":"12345","agent_id":"agent-abc123","agent_type":"vbw-dev","name":"dev-01"}' | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  [ -f "$HEALTH_DIR/agent-abc123.json" ]
  run jq -r '.key' "$HEALTH_DIR/agent-abc123.json"
  [ "$output" = "agent-abc123" ]
  run jq -r '.role' "$HEALTH_DIR/agent-abc123.json"
  [ "$output" = "dev" ]
}

@test "agent-health: start accepts legacy agentName field" {
  cd "$TEST_TEMP_DIR"
  echo '{"pid":"12346","agentName":"vbw-qa"}' | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  [ -f "$HEALTH_DIR/qa.json" ]
  run jq -r '.role' "$HEALTH_DIR/qa.json"
  [ "$output" = "qa" ]
}

@test "agent-health: wrapper-routed start initializes from documented native payload without pid" {
  cd "$TEST_TEMP_DIR"
  run_health_via_wrapper start '{"agent_id":"agent-no-pid","agent_type":"vbw-dev"}'
  [ "$status" -eq 0 ]
  [ -f "$HEALTH_DIR/agent-no-pid.json" ]
  run jq -r '.role' "$HEALTH_DIR/agent-no-pid.json"
  [ "$output" = "dev" ]
  run jq -r '.pid' "$HEALTH_DIR/agent-no-pid.json"
  [ -z "$output" ]
}

@test "agent-health: wrapper-routed no-pid start file is reused by idle via agent_id" {
  cd "$TEST_TEMP_DIR"
  run_health_via_wrapper start '{"agent_id":"agent-idle","agent_type":"vbw-qa"}'
  [ "$status" -eq 0 ]

  echo '{"agent_id":"agent-idle","agent_type":"vbw-qa"}' | bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null

  run jq -r '.idle_count' "$HEALTH_DIR/agent-idle.json"
  [ "$output" = "1" ]
}

@test "agent-health: idle refreshes stored pid from payload after wrapper-routed start" {
  cd "$TEST_TEMP_DIR"
  run_health_via_wrapper start '{"agent_id":"agent-refresh","agent_type":"vbw-dev"}'
  [ "$status" -eq 0 ]

  sleep 30 &
  LIVE_PID=$!

  echo "{\"agent_id\":\"agent-refresh\",\"agent_type\":\"vbw-dev\",\"pid\":\"$LIVE_PID\"}" | bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null

  run jq -r '.pid' "$HEALTH_DIR/agent-refresh.json"
  [ "$output" = "$LIVE_PID" ]

  kill $LIVE_PID 2>/dev/null || true
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

  echo '{"pid":"99998","agent_id":"agent-stop-001","agent_type":"vbw:vbw-dev","name":"dev-01"}' | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  run bash -c "echo '{\"pid\":\"99998\",\"agent_id\":\"agent-stop-001\",\"agent_type\":\"vbw:vbw-dev\",\"name\":\"dev-01\"}' | bash '$SCRIPTS_DIR/agent-health.sh' stop | jq -r '.hookSpecificOutput.additionalContext'"
  [[ "$output" == *"task-stop"* ]]

  run jq -r '.owner' "$TASKS_DIR/task-stop.json"
  [ "$output" = "" ]

  rm -rf "$TASKS_DIR"
}

@test "agent-health: orphan recovery preserves role-owned task when another same-role teammate is still alive" {
  cd "$TEST_TEMP_DIR"
  TASKS_DIR="$CLAUDE_CONFIG_DIR/tasks/test-team-shared-$$"
  mkdir -p "$TASKS_DIR"

  cat > "$TASKS_DIR/task-shared.json" <<EOF
{
  "id": "task-shared",
  "owner": "dev",
  "status": "in_progress",
  "subject": "Shared dev task"
}
EOF

  sleep 30 &
  LIVE_PID=$!

  echo "{\"pid\":\"$LIVE_PID\",\"agent_id\":\"agent-live\",\"agent_type\":\"vbw-dev\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  echo '{"pid":"99997","agent_id":"agent-dead","agent_type":"vbw-dev"}' | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  run bash -c "echo '{\"pid\":\"99997\",\"agent_id\":\"agent-dead\",\"agent_type\":\"vbw-dev\"}' | bash '$SCRIPTS_DIR/agent-health.sh' stop | jq -r '.hookSpecificOutput.additionalContext'"
  [[ "$output" == *"another live teammate"* ]]

  run jq -r '.owner' "$TASKS_DIR/task-shared.json"
  [ "$output" = "dev" ]

  kill $LIVE_PID 2>/dev/null || true
  rm -rf "$TASKS_DIR"
}

@test "agent-health: stop prefers payload pid over stale stored pid" {
  cd "$TEST_TEMP_DIR"
  TASKS_DIR="$CLAUDE_CONFIG_DIR/tasks/test-team-stop-live-$$"
  mkdir -p "$TASKS_DIR" "$HEALTH_DIR"

  cat > "$TASKS_DIR/task-stop-live.json" <<EOF
{
  "id": "task-stop-live",
  "owner": "dev",
  "status": "in_progress",
  "subject": "Healthy stop task"
}
EOF

  cat > "$HEALTH_DIR/agent-stop-live.json" <<EOF
{
  "pid": "99996",
  "key": "agent-stop-live",
  "role": "dev",
  "started_at": "2026-01-01T00:00:00Z",
  "last_event_at": "2026-01-01T00:00:00Z",
  "last_event": "start",
  "idle_count": 0
}
EOF

  sleep 30 &
  LIVE_PID=$!

  run bash -c "echo '{\"agent_id\":\"agent-stop-live\",\"agent_type\":\"vbw-dev\",\"pid\":\"$LIVE_PID\"}' | bash '$SCRIPTS_DIR/agent-health.sh' stop | jq -r '.hookSpecificOutput.additionalContext'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run jq -r '.owner' "$TASKS_DIR/task-stop-live.json"
  [ "$output" = "dev" ]

  kill $LIVE_PID 2>/dev/null || true
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

@test "agent-health: start ignores bare native agent_type even in a VBW session" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  echo '{"pid":"12345","agent_type":"dev"}' | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  [ ! -d "$HEALTH_DIR" ] || [ ! -f "$HEALTH_DIR/dev.json" ]
}

@test "agent-health: idle ignores non-VBW team_name even in a VBW session" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"

  run bash -c "echo '{\"teammate_name\":\"dev-01\",\"team_name\":\"external-team\",\"pid\":\"$$\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -d "$HEALTH_DIR" ] || [ ! -f "$HEALTH_DIR/dev-01.json" ]
}

@test "agent-health: idle accepts legacy teammate_name for VBW-owned team namespaces" {
  cd "$TEST_TEMP_DIR"

  sleep 30 &
  LIVE_PID=$!

  while IFS='|' read -r teammate expected_role team_name; do
    run bash -c "echo '{\"teammate_name\":\"$teammate\",\"team_name\":\"$team_name\",\"pid\":\"$LIVE_PID\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle >/dev/null"
    [ "$status" -eq 0 ]

    run jq -r '.key' "$HEALTH_DIR/${teammate}.json"
    [ "$output" = "$teammate" ]
    run jq -r '.role' "$HEALTH_DIR/${teammate}.json"
    [ "$output" = "$expected_role" ]
    run jq -r '.idle_count' "$HEALTH_DIR/${teammate}.json"
    [ "$output" = "1" ]
  done <<'EOF'
dev-01|dev|vbw-phase-01
debugger-01|debugger|vbw-debug-1741625400
scout-01|scout|vbw-map-duo
scout-02|scout|vbw-map-quad
EOF

  kill $LIVE_PID 2>/dev/null || true
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

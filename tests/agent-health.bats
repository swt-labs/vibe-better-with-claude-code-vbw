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

@test "agent-health: start falls back to explicit legacy VBW name when native agent_type is non-VBW" {
  cd "$TEST_TEMP_DIR"
  echo '{"agent_type":"helper-agent","agent_name":"vbw-dev-01","pid":"12347"}' | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  [ -f "$HEALTH_DIR/vbw-dev-01.json" ] || [ -f "$HEALTH_DIR/dev-01.json" ]
  if [ -f "$HEALTH_DIR/dev-01.json" ]; then
    run jq -r '.role' "$HEALTH_DIR/dev-01.json"
  else
    run jq -r '.role' "$HEALTH_DIR/vbw-dev-01.json"
  fi
  [ "$output" = "dev" ]
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
  run jq -r '.pid' "$HEALTH_DIR/agent-idle.json"
  [ -z "$output" ]
}

# Test 2: idle increments count
@test "agent-health: idle increments count" {
  cd "$TEST_TEMP_DIR"
  local live_pid
  assign_live_pid live_pid || fail "assign_live_pid failed"
  kill -0 "$live_pid" 2>/dev/null || fail "live pid fixture is not alive"
  echo "{\"pid\":\"$live_pid\",\"agent_type\":\"vbw-qa\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  # Run idle
  echo '{"agent_type":"vbw-qa"}' | bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null

  # Check idle count
  run jq -r '.idle_count' "$HEALTH_DIR/qa.json"
  [ "$output" = "1" ]
}

# Test 3: idle stuck advisory at count >= 3
@test "agent-health: idle stuck advisory" {
  cd "$TEST_TEMP_DIR"
  local live_pid
  assign_live_pid live_pid || fail "assign_live_pid failed"
  kill -0 "$live_pid" 2>/dev/null || fail "live pid fixture is not alive"
  echo "{\"pid\":\"$live_pid\",\"agent_type\":\"vbw-scout\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  # Run idle 3 times
  for i in 1 2 3; do
    echo '{"agent_type":"vbw-scout"}' | bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null
  done

  # Fourth call should have stuck advisory
  run bash -c "echo '{\"agent_type\":\"vbw-scout\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle | jq -r '.hookSpecificOutput.additionalContext'"
  [[ "$output" == *"stuck"* ]]
  [[ "$output" == *"idle_count=4"* ]]
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
  local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  echo "{\"pid\":\"$dead_pid\",\"agent_type\":\"vbw-dev\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

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

  local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  echo "{\"pid\":\"$dead_pid\",\"agent_id\":\"agent-stop-001\",\"agent_type\":\"vbw:vbw-dev\",\"name\":\"dev-01\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  run bash -c "echo '{\"pid\":\"$dead_pid\",\"agent_id\":\"agent-stop-001\",\"agent_type\":\"vbw:vbw-dev\",\"name\":\"dev-01\"}' | bash '$SCRIPTS_DIR/agent-health.sh' stop | jq -r '.hookSpecificOutput.additionalContext'"
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

  local live_pid
  assign_live_pid live_pid || fail "assign_live_pid failed"
  kill -0 "$live_pid" 2>/dev/null || fail "live pid fixture is not alive"

  echo "{\"pid\":\"$live_pid\",\"agent_id\":\"agent-live\",\"agent_type\":\"vbw-dev\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  echo "{\"pid\":\"$dead_pid\",\"agent_id\":\"agent-dead\",\"agent_type\":\"vbw-dev\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  run bash -c "echo '{\"pid\":\"$dead_pid\",\"agent_id\":\"agent-dead\",\"agent_type\":\"vbw-dev\"}' | bash '$SCRIPTS_DIR/agent-health.sh' stop | jq -r '.hookSpecificOutput.additionalContext'"
  [[ "$output" == *"another live teammate"* ]]

  run jq -r '.owner' "$TASKS_DIR/task-shared.json"
  [ "$output" = "dev" ]

  rm -rf "$TASKS_DIR"
}

@test "agent-health: no-pid native stop removes health file via agent_id" {
  cd "$TEST_TEMP_DIR"
  run_health_via_wrapper start '{"agent_id":"agent-stop-nopid","agent_type":"vbw-dev"}'
  [ "$status" -eq 0 ]
  [ -f "$HEALTH_DIR/agent-stop-nopid.json" ]

  echo '{"agent_id":"agent-stop-nopid","agent_type":"vbw-dev"}' | bash "$SCRIPTS_DIR/agent-health.sh" stop >/dev/null

  [ ! -f "$HEALTH_DIR/agent-stop-nopid.json" ]
}

# Test 5: stop removes health file
@test "agent-health: stop removes health file" {
  cd "$TEST_TEMP_DIR"
  local live_pid
  assign_live_pid live_pid || fail "assign_live_pid failed"
  kill -0 "$live_pid" 2>/dev/null || fail "live pid fixture is not alive"
  echo "{\"pid\":\"$live_pid\",\"agent_type\":\"vbw-qa\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  # Verify file exists
  [ -f "$HEALTH_DIR/qa.json" ]

  # Stop
  echo '{"agent_type":"vbw-qa"}' | bash "$SCRIPTS_DIR/agent-health.sh" stop >/dev/null

  # Verify file removed
  [ ! -f "$HEALTH_DIR/qa.json" ]
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

  while IFS='|' read -r teammate expected_role team_name; do
    key="${team_name}__${teammate}"
    run bash -c "echo '{\"teammate_name\":\"$teammate\",\"team_name\":\"$team_name\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle >/dev/null"
    [ "$status" -eq 0 ]

    run jq -r '.key' "$HEALTH_DIR/${key}.json"
    [ "$output" = "$key" ]
    run jq -r '.role' "$HEALTH_DIR/${key}.json"
    [ "$output" = "$expected_role" ]
    run jq -r '.team_name' "$HEALTH_DIR/${key}.json"
    [ "$output" = "$team_name" ]
    run jq -r '.idle_count' "$HEALTH_DIR/${key}.json"
    [ "$output" = "1" ]
  done <<'EOF'
dev-01|dev|vbw-phase-01
debugger-01|debugger|vbw-debug-1741625400
scout-01|scout|vbw-map-duo
scout-02|scout|vbw-map-quad
EOF
}

@test "agent-health: orphan recovery stays within matching legacy team_name scope" {
  cd "$TEST_TEMP_DIR"
  TASKS_DIR="$CLAUDE_CONFIG_DIR/tasks"
  mkdir -p "$TASKS_DIR/vbw-phase-01" "$TASKS_DIR/vbw-map-duo"

  cat > "$TASKS_DIR/vbw-phase-01/task-phase.json" <<EOF
{
  "id": "task-phase",
  "owner": "dev",
  "status": "in_progress",
  "subject": "Phase team task"
}
EOF

  cat > "$TASKS_DIR/vbw-map-duo/task-map.json" <<EOF
{
  "id": "task-map",
  "owner": "dev",
  "status": "in_progress",
  "subject": "Map team task"
}
EOF

  local live_pid
  assign_live_pid live_pid || fail "assign_live_pid failed"
  kill -0 "$live_pid" 2>/dev/null || fail "live pid fixture is not alive"

  echo "{\"teammate_name\":\"dev-01\",\"team_name\":\"vbw-map-duo\",\"pid\":\"$live_pid\"}" | bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null

  local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  run bash -c "echo '{\"teammate_name\":\"dev-01\",\"team_name\":\"vbw-phase-01\",\"pid\":\"$dead_pid\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle | jq -r '.hookSpecificOutput.additionalContext'"
  [[ "$output" == *"task-phase"* ]]

  run jq -r '.owner' "$TASKS_DIR/vbw-phase-01/task-phase.json"
  [ "$output" = "" ]
  run jq -r '.owner' "$TASKS_DIR/vbw-map-duo/task-map.json"
  [ "$output" = "dev" ]
}

@test "agent-health: orphan recovery preserves role-owned task when same-team teammate has no pid" {
  cd "$TEST_TEMP_DIR"
  TASKS_DIR="$CLAUDE_CONFIG_DIR/tasks"
  mkdir -p "$TASKS_DIR/vbw-phase-01" "$HEALTH_DIR"

  cat > "$TASKS_DIR/vbw-phase-01/task-shared-nopid.json" <<EOF
{
  "id": "task-shared-nopid",
  "owner": "dev",
  "status": "in_progress",
  "subject": "Shared dev task without pid"
}
EOF

  cat > "$HEALTH_DIR/vbw-phase-01__dev-02.json" <<EOF
{
  "pid": "",
  "key": "vbw-phase-01__dev-02",
  "role": "dev",
  "team_name": "vbw-phase-01",
  "started_at": "2026-01-01T00:00:00Z",
  "last_event_at": "2026-01-01T00:00:00Z",
  "last_event": "idle_bootstrap",
  "idle_count": 1
}
EOF

  local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  run bash -c "echo '{\"teammate_name\":\"dev-01\",\"team_name\":\"vbw-phase-01\",\"pid\":\"$dead_pid\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle | jq -r '.hookSpecificOutput.additionalContext'"
  [[ "$output" == *"still tracked"* ]]

  run jq -r '.owner' "$TASKS_DIR/vbw-phase-01/task-shared-nopid.json"
  [ "$output" = "dev" ]
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

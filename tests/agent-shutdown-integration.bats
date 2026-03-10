#!/usr/bin/env bats

# Integration tests for the agent shutdown lifecycle.
# Verifies agent-start → agent-stop reference counting, session-stop cleanup,
# and the full chain including task-verify circuit breaker state lifecycle.
#
# Related: PR #95, Issue #94

load test_helper

# Counter for unique fake PIDs across tests
FAKE_PID_BASE=90000

setup() {
  setup_temp_dir
  create_test_config

  cd "$TEST_TEMP_DIR"

  # Git repo needed for task-verify.sh
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > init.txt
  git add init.txt
  git commit -q -m "chore: initial commit"

  # Create a .vbw-session marker (should be preserved by session-stop)
  echo "test-session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"

  # Clean stale PID tracker lock from previous interrupted runs (rm -rf handles
  # non-empty lock dirs left when a prior run was interrupted after pid write)
  rm -rf /tmp/vbw-agent-pid-lock 2>/dev/null || true
}

teardown() {
  rm -rf /tmp/vbw-agent-pid-lock 2>/dev/null || true
  teardown_temp_dir
}

# Helper: get a unique fake PID (numeric, won't collide with real processes)
next_fake_pid() {
  FAKE_PID_BASE=$((FAKE_PID_BASE + 1))
  echo "$FAKE_PID_BASE"
}

# Helper: simulate SubagentStart hook for a given agent type with a PID
simulate_agent_start() {
  local agent_type="$1"
  local pid="$2"
  echo "{\"agent_type\":\"$agent_type\",\"pid\":\"$pid\"}" \
    | bash "$SCRIPTS_DIR/agent-start.sh"
}

# Helper: simulate SubagentStop hook for a given PID
simulate_agent_stop() {
  local pid="$1"
  echo "{\"pid\":\"$pid\"}" \
    | bash "$SCRIPTS_DIR/agent-stop.sh"
}

# Helper: simulate SessionStop hook with minimal metrics
simulate_session_stop() {
  echo '{"cost_usd":0.01,"duration_ms":5000,"tokens_in":100,"tokens_out":50,"model":"test"}' \
    | bash "$SCRIPTS_DIR/session-stop.sh"
}

# =============================================================================
# Agent Start/Stop Reference Counting
# =============================================================================

@test "agent-start creates .active-agent and sets count to 1" {
  cd "$TEST_TEMP_DIR"
  local pid
  pid=$(next_fake_pid)

  simulate_agent_start "vbw-dev" "$pid"

  [ -f ".vbw-planning/.active-agent" ]
  [ -f ".vbw-planning/.active-agent-count" ]
  run cat ".vbw-planning/.active-agent-count"
  [ "$output" = "1" ]
}

@test "two agent-starts increment count to 2" {
  cd "$TEST_TEMP_DIR"
  local pid1 pid2
  pid1=$(next_fake_pid)
  pid2=$(next_fake_pid)

  simulate_agent_start "vbw-dev" "$pid1"
  simulate_agent_start "vbw-qa" "$pid2"

  run cat ".vbw-planning/.active-agent-count"
  [ "$output" = "2" ]
}

@test "agent-stop decrements count from 2 to 1 — markers preserved" {
  cd "$TEST_TEMP_DIR"
  local pid1 pid2
  pid1=$(next_fake_pid)
  pid2=$(next_fake_pid)

  simulate_agent_start "vbw-dev" "$pid1"
  simulate_agent_start "vbw-qa" "$pid2"

  # Stop first agent
  simulate_agent_stop "$pid1"

  [ -f ".vbw-planning/.active-agent" ]
  [ -f ".vbw-planning/.active-agent-count" ]
  run cat ".vbw-planning/.active-agent-count"
  [ "$output" = "1" ]
}

@test "agent-stop decrements count from 1 to 0 — markers removed" {
  cd "$TEST_TEMP_DIR"
  local pid1
  pid1=$(next_fake_pid)

  simulate_agent_start "vbw-dev" "$pid1"
  simulate_agent_stop "$pid1"

  [ ! -f ".vbw-planning/.active-agent" ]
  [ ! -f ".vbw-planning/.active-agent-count" ]
}

@test "two starts then two stops — all markers cleaned" {
  cd "$TEST_TEMP_DIR"
  local pid1 pid2
  pid1=$(next_fake_pid)
  pid2=$(next_fake_pid)

  simulate_agent_start "vbw-dev" "$pid1"
  simulate_agent_start "vbw-qa" "$pid2"
  simulate_agent_stop "$pid1"
  simulate_agent_stop "$pid2"

  [ ! -f ".vbw-planning/.active-agent" ]
  [ ! -f ".vbw-planning/.active-agent-count" ]
}

@test "agent-stop with no count file but active-agent marker — removes marker" {
  cd "$TEST_TEMP_DIR"
  # Simulate legacy state: marker but no count file
  echo "dev" > ".vbw-planning/.active-agent"

  echo '{"pid":"99999"}' | bash "$SCRIPTS_DIR/agent-stop.sh"

  [ ! -f ".vbw-planning/.active-agent" ]
}

@test "agent-stop always exits 0" {
  cd "$TEST_TEMP_DIR"
  # Even with no markers at all
  run bash -c 'echo "{}" | bash "'"$SCRIPTS_DIR"'/agent-stop.sh"'
  [ "$status" -eq 0 ]
}

# =============================================================================
# PID Tracker Integration with Agent Start/Stop
# =============================================================================

@test "agent-start registers PID — agent-stop unregisters it" {
  cd "$TEST_TEMP_DIR"
  local pid
  pid=$(next_fake_pid)

  simulate_agent_start "vbw-dev" "$pid"

  # PID should be in the tracker
  [ -f ".vbw-planning/.agent-pids" ]
  run grep "^${pid}$" ".vbw-planning/.agent-pids"
  [ "$status" -eq 0 ]

  simulate_agent_stop "$pid"

  # PID should be removed
  run grep "^${pid}$" ".vbw-planning/.agent-pids"
  [ "$status" -ne 0 ]
}

# =============================================================================
# PID Tracker Prune — dead PID cleanup
# =============================================================================

@test "prune removes all dead PIDs and deletes the file" {
  cd "$TEST_TEMP_DIR"
  # Write fake dead PIDs
  printf '99991\n99992\n99993\n' > ".vbw-planning/.agent-pids"

  run bash "$SCRIPTS_DIR/agent-pid-tracker.sh" prune
  [ "$status" -eq 0 ]

  # File should be removed (all PIDs dead)
  [ ! -f ".vbw-planning/.agent-pids" ]
}

@test "prune keeps alive PIDs and removes dead ones" {
  cd "$TEST_TEMP_DIR"
  # Start a real background process to get a live PID
  sleep 30 &
  local alive_pid=$!

  printf "${alive_pid}\n99994\n99995\n" > ".vbw-planning/.agent-pids"

  run bash "$SCRIPTS_DIR/agent-pid-tracker.sh" prune
  [ "$status" -eq 0 ]

  # File should exist with only the alive PID
  [ -f ".vbw-planning/.agent-pids" ]
  run grep "^${alive_pid}$" ".vbw-planning/.agent-pids"
  [ "$status" -eq 0 ]

  # Dead PIDs should be gone
  run grep "^99994$" ".vbw-planning/.agent-pids"
  [ "$status" -ne 0 ]
  run grep "^99995$" ".vbw-planning/.agent-pids"
  [ "$status" -ne 0 ]

  kill "$alive_pid" 2>/dev/null || true
}

@test "prune is a no-op when .agent-pids does not exist" {
  cd "$TEST_TEMP_DIR"
  rm -f ".vbw-planning/.agent-pids"

  run bash "$SCRIPTS_DIR/agent-pid-tracker.sh" prune
  [ "$status" -eq 0 ]
  [ ! -f ".vbw-planning/.agent-pids" ]
}

@test "prune ignores leftover .agent-pids.tmp from interrupted prune" {
  cd "$TEST_TEMP_DIR"
  # Simulate interrupted prune that left a stale temp file with a dead PID
  echo "12345" > ".vbw-planning/.agent-pids.tmp"

  # Put a live PID in the real file
  sleep 30 &
  local alive_pid=$!

  printf "${alive_pid}\n99996\n" > ".vbw-planning/.agent-pids"

  run bash "$SCRIPTS_DIR/agent-pid-tracker.sh" prune
  [ "$status" -eq 0 ]

  # File should contain ONLY the live PID (stale temp content must not leak)
  [ -f ".vbw-planning/.agent-pids" ]
  run cat ".vbw-planning/.agent-pids"
  [ "$output" = "$alive_pid" ]

  # Temp file should be cleaned up
  [ ! -f ".vbw-planning/.agent-pids.tmp" ]

  kill "$alive_pid" 2>/dev/null || true
}

@test "prune recovers from stale lock left by crashed process" {
  cd "$TEST_TEMP_DIR"
  # Simulate stale lock from a crashed process
  mkdir -p /tmp/vbw-agent-pid-lock
  echo "99999" > /tmp/vbw-agent-pid-lock/pid

  printf '99997\n99998\n' > ".vbw-planning/.agent-pids"

  run bash "$SCRIPTS_DIR/agent-pid-tracker.sh" prune
  [ "$status" -eq 0 ]

  # All dead PIDs should be pruned — file removed
  [ ! -f ".vbw-planning/.agent-pids" ]

  # Lock should be released
  [ ! -d /tmp/vbw-agent-pid-lock ]
}

@test "prune recovers from stale lock directory with no pid file" {
  cd "$TEST_TEMP_DIR"
  # Simulate stale lock dir with no pid file (edge case: lock created but pid write failed)
  mkdir -p /tmp/vbw-agent-pid-lock

  printf '99997\n99998\n' > ".vbw-planning/.agent-pids"

  run bash "$SCRIPTS_DIR/agent-pid-tracker.sh" prune
  [ "$status" -eq 0 ]

  # All dead PIDs should be pruned
  [ ! -f ".vbw-planning/.agent-pids" ]

  # Lock should be released
  [ ! -d /tmp/vbw-agent-pid-lock ]
}

# =============================================================================
# Session Stop Cleanup
# =============================================================================

@test "session-stop removes transient markers" {
  cd "$TEST_TEMP_DIR"

  # Create all the transient files session-stop should clean
  echo "dev" > ".vbw-planning/.active-agent"
  echo "2" > ".vbw-planning/.active-agent-count"
  mkdir -p ".vbw-planning/.active-agent-count.lock"
  echo "12345 %1" > ".vbw-planning/.agent-panes"

  simulate_session_stop

  [ ! -f ".vbw-planning/.active-agent" ]
  [ ! -f ".vbw-planning/.active-agent-count" ]
  [ ! -d ".vbw-planning/.active-agent-count.lock" ]
  [ ! -f ".vbw-planning/.agent-panes" ]
}

@test "session-stop removes .task-verify-seen (circuit breaker state)" {
  cd "$TEST_TEMP_DIR"
  echo "abc123hash" > ".vbw-planning/.task-verify-seen"

  simulate_session_stop

  [ ! -f ".vbw-planning/.task-verify-seen" ]
}

@test "session-stop preserves .vbw-session" {
  cd "$TEST_TEMP_DIR"

  simulate_session_stop

  [ -f ".vbw-planning/.vbw-session" ]
  run cat ".vbw-planning/.vbw-session"
  [ "$output" = "test-session" ]
}

@test "session-stop appends to session log" {
  cd "$TEST_TEMP_DIR"

  simulate_session_stop

  [ -f ".vbw-planning/.session-log.jsonl" ]
  run jq -r '.model' ".vbw-planning/.session-log.jsonl"
  [ "$output" = "test" ]
}

@test "session-stop persists and removes cost ledger" {
  cd "$TEST_TEMP_DIR"
  echo '{"lead":0.05,"dev":0.10}' > ".vbw-planning/.cost-ledger.json"

  simulate_session_stop

  # Cost ledger should be gone
  [ ! -f ".vbw-planning/.cost-ledger.json" ]

  # Session log should contain the cost_summary entry (jq slurp handles multi-line JSON)
  run jq -s '[.[] | select(.type == "cost_summary")] | length' ".vbw-planning/.session-log.jsonl"
  [ "$output" = "1" ]
}

@test "session-stop always exits 0 even with no planning dir" {
  cd "$TEST_TEMP_DIR"
  rm -rf ".vbw-planning"

  run simulate_session_stop
  [ "$status" -eq 0 ]
}

# =============================================================================
# Full Chain: task-verify circuit breaker → agent-stop → session-stop
# =============================================================================

@test "full chain: circuit breaker state created during task-verify, cleaned by session-stop" {
  cd "$TEST_TEMP_DIR"

  # A commit that won't match the subject → triggers circuit breaker
  echo "$RANDOM" >> dummy.txt && git add dummy.txt && git commit -q -m "docs: update README"

  # First task-verify call: blocks (exit 2), creates .task-verify-seen
  run bash -c 'echo "{\"task_subject\": \"Implement widget renderer\"}" | bash "'"$SCRIPTS_DIR"'/task-verify.sh"'
  [ "$status" -eq 2 ]
  [ -f ".vbw-planning/.task-verify-seen" ]

  # Second call: circuit breaker fires (exit 0)
  run bash -c 'echo "{\"task_subject\": \"Implement widget renderer\"}" | bash "'"$SCRIPTS_DIR"'/task-verify.sh"'
  [ "$status" -eq 0 ]

  # Now simulate agent shutdown + session stop
  local pid
  pid=$(next_fake_pid)
  simulate_agent_start "vbw-dev" "$pid"
  simulate_agent_stop "$pid"
  simulate_session_stop

  # All transient state should be clean
  [ ! -f ".vbw-planning/.task-verify-seen" ]
  [ ! -f ".vbw-planning/.active-agent" ]
  [ ! -f ".vbw-planning/.active-agent-count" ]
  # Session marker preserved
  [ -f ".vbw-planning/.vbw-session" ]
}

@test "full chain: multi-agent start → task-verify blocks → circuit breaker → stops → session cleanup" {
  cd "$TEST_TEMP_DIR"

  # Start two agents
  local pid1 pid2
  pid1=$(next_fake_pid)
  pid2=$(next_fake_pid)
  simulate_agent_start "vbw-dev" "$pid1"
  simulate_agent_start "vbw-dev" "$pid2"

  run cat ".vbw-planning/.active-agent-count"
  [ "$output" = "2" ]

  # Dev-01 finishes task — no matching commit → blocks
  echo "$RANDOM" >> dummy.txt && git add dummy.txt && git commit -q -m "docs: unrelated change"
  run bash -c 'echo "{\"task_subject\": \"Execute 07-01: Create detail view\"}" | bash "'"$SCRIPTS_DIR"'/task-verify.sh"'
  [ "$status" -eq 2 ]

  # Retry (simulating Claude Code re-queue) → circuit breaker allows
  run bash -c 'echo "{\"task_subject\": \"Execute 07-01: Create detail view\"}" | bash "'"$SCRIPTS_DIR"'/task-verify.sh"'
  [ "$status" -eq 0 ]

  # Dev-02 finishes task with matching commit → no block
  echo "$RANDOM" >> dummy.txt && git add dummy.txt && git commit -q -m "feat(07-02): wire navigation to detail view"
  run bash -c 'echo "{\"task_subject\": \"Execute 07-02: Wire navigation to detail view\"}" | bash "'"$SCRIPTS_DIR"'/task-verify.sh"'
  [ "$status" -eq 0 ]

  # Both agents stop
  simulate_agent_stop "$pid1"
  run cat ".vbw-planning/.active-agent-count"
  [ "$output" = "1" ]

  simulate_agent_stop "$pid2"
  [ ! -f ".vbw-planning/.active-agent-count" ]

  # Session ends
  simulate_session_stop

  # Everything cleaned
  [ ! -f ".vbw-planning/.task-verify-seen" ]
  [ ! -f ".vbw-planning/.active-agent" ]
  [ ! -f ".vbw-planning/.agent-panes" ]
  [ -f ".vbw-planning/.vbw-session" ]
  [ -f ".vbw-planning/.session-log.jsonl" ]
}

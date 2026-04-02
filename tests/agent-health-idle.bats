#!/usr/bin/env bats

# agent-health-idle.bats — Test agent-health.sh idle bootstrap and unique keying
#
# Covers:
# - idle bootstrap works without prior start hook
# - two Dev teammates get separate health files
# - repeated idle increments per-teammate count
# - strong stuck advisory at threshold (idle_count >= 3)

SCRIPT="$BATS_TEST_DIRNAME/../scripts/agent-health.sh"

setup() {
  export HEALTH_DIR
  export PLANNING_DIR
  TMPDIR="$(mktemp -d)"
  PLANNING_DIR="$TMPDIR/.vbw-planning"
  HEALTH_DIR="$TMPDIR/.vbw-planning/.agent-health"
  mkdir -p "$HEALTH_DIR"
  echo "session" > "$PLANNING_DIR/.vbw-session"
  export TEST_PLANNING_DIR="$PLANNING_DIR"

  # Override HEALTH_DIR inside agent-health.sh by creating a wrapper
  WRAPPER="$TMPDIR/agent-health-test.sh"
  cat > "$WRAPPER" <<'WRAPPER_EOF'
#!/usr/bin/env bash
set -u
PLANNING_DIR="$TEST_PLANNING_DIR"
HEALTH_DIR="$TEST_HEALTH_DIR"
WRAPPER_EOF
  # Append the original script minus the first two lines (shebang + set -u)
  # and minus the PLANNING_DIR / HEALTH_DIR assignments
  tail -n +2 "$SCRIPT" | sed '/^PLANNING_DIR=/d; /^HEALTH_DIR=/d' >> "$WRAPPER"
  chmod +x "$WRAPPER"
  export WRAPPER
}

teardown() {
  rm -rf "$TMPDIR"
}

run_health() {
  local cmd="$1"
  shift
  TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" "$cmd" "$@"
}

@test "idle bootstrap: creates health file when none exists from start hook" {
  # No start hook was called — health file doesn't exist
  [ ! -f "$HEALTH_DIR/dev-01.json" ]

  # Legacy/name-based payload inside an active VBW session
  echo "{\"name\":\"dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle

  # After idle, a health file should exist (bootstrapped)
  [ -f "$HEALTH_DIR/dev-01.json" ]
}

@test "idle bootstrap: legacy teammate_name fallback creates health file" {
  [ ! -f "$HEALTH_DIR/dev-01.json" ]

  echo "{\"teammate_name\":\"dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle

  [ -f "$HEALTH_DIR/dev-01.json" ]
}

@test "idle bootstrap: vbw team_name allows teammate_name payload" {
  [ ! -f "$HEALTH_DIR/dev-01.json" ]

  echo "{\"teammate_name\":\"dev-01\",\"team_name\":\"vbw-phase-07\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle

  [ -f "$HEALTH_DIR/dev-01.json" ]
}

@test "idle bootstrap: non-VBW team_name is ignored even with vbw session marker" {
  [ ! -f "$HEALTH_DIR/dev-01.json" ]

  run bash -c "echo '{\"teammate_name\":\"dev-01\",\"team_name\":\"external-team\",\"pid\":\"$$\"}' | TEST_HEALTH_DIR='$HEALTH_DIR' TEST_PLANNING_DIR='$PLANNING_DIR' bash '$WRAPPER' idle"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$HEALTH_DIR/dev-01.json" ]
}

@test "unique keying: two Dev teammates get separate files" {
  # Start two different dev teammates with alive PIDs
  echo "{\"name\":\"dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  echo "{\"name\":\"dev-02\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  # Both should have separate health files
  [ -f "$HEALTH_DIR/dev-01.json" ]
  [ -f "$HEALTH_DIR/dev-02.json" ]
}

@test "unique keying: native agent_id distinguishes same-role teammates without name" {
  echo "{\"agent_type\":\"vbw-dev\",\"agent_id\":\"agent-dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  echo "{\"agent_type\":\"vbw-dev\",\"agent_id\":\"agent-dev-02\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  [ -f "$HEALTH_DIR/agent-dev-01.json" ]
  [ -f "$HEALTH_DIR/agent-dev-02.json" ]
}

@test "idle increments per-teammate, not by role" {
  # Start two devs with alive PIDs
  echo "{\"name\":\"dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  echo "{\"name\":\"dev-02\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  # Idle dev-01 twice
  echo "{\"teammate_name\":\"dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle
  echo "{\"teammate_name\":\"dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle

  # dev-01 should have idle_count=2, dev-02 still at 0
  count_01=$(jq -r '.idle_count' "$HEALTH_DIR/dev-01.json")
  count_02=$(jq -r '.idle_count' "$HEALTH_DIR/dev-02.json")
  [ "$count_01" -eq 2 ]
  [ "$count_02" -eq 0 ]
}

@test "idle increments by native agent_id when legacy name is absent" {
  echo "{\"agent_type\":\"vbw-dev\",\"agent_id\":\"agent-dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  echo "{\"agent_type\":\"vbw-dev\",\"agent_id\":\"agent-dev-02\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  echo "{\"agent_type\":\"vbw-dev\",\"agent_id\":\"agent-dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle >/dev/null
  echo "{\"agent_type\":\"vbw-dev\",\"agent_id\":\"agent-dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle >/dev/null

  count_01=$(jq -r '.idle_count' "$HEALTH_DIR/agent-dev-01.json")
  count_02=$(jq -r '.idle_count' "$HEALTH_DIR/agent-dev-02.json")
  [ "$count_01" -eq 2 ]
  [ "$count_02" -eq 0 ]
}

@test "idle reuses native agent_id file created without pid" {
  echo "{\"agent_type\":\"vbw-dev\",\"agent_id\":\"agent-dev-nopid\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  echo "{\"agent_type\":\"vbw-dev\",\"agent_id\":\"agent-dev-nopid\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle >/dev/null

  count=$(jq -r '.idle_count' "$HEALTH_DIR/agent-dev-nopid.json")
  [ "$count" -eq 1 ]
}

@test "idle increments by teammate_name from documented payload" {
  echo "{\"name\":\"dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  echo "{\"name\":\"dev-02\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  echo "{\"teammate_name\":\"dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle >/dev/null
  echo "{\"teammate_name\":\"dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle >/dev/null

  count_01=$(jq -r '.idle_count' "$HEALTH_DIR/dev-01.json")
  count_02=$(jq -r '.idle_count' "$HEALTH_DIR/dev-02.json")
  [ "$count_01" -eq 2 ]
  [ "$count_02" -eq 0 ]
}

@test "stuck advisory emitted at idle_count >= 3" {
  echo "{\"name\":\"dev-03\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  # Idle 3 times
  echo "{\"teammate_name\":\"dev-03\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle > /dev/null
  echo "{\"teammate_name\":\"dev-03\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle > /dev/null

  # Third idle should produce stuck advisory
  output=$(echo "{\"teammate_name\":\"dev-03\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle)

  echo "$output" | grep -qi 'stuck\|appears stuck\|idle_count=3'
}

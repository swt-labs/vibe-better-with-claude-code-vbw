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
  TMPDIR="$(mktemp -d)"
  HEALTH_DIR="$TMPDIR/.vbw-planning/.agent-health"
  mkdir -p "$HEALTH_DIR"

  # Override HEALTH_DIR inside agent-health.sh by creating a wrapper
  WRAPPER="$TMPDIR/agent-health-test.sh"
  cat > "$WRAPPER" <<'WRAPPER_EOF'
#!/usr/bin/env bash
set -u
HEALTH_DIR="$TEST_HEALTH_DIR"
WRAPPER_EOF
  # Append the original script minus the first two lines (shebang + set -u)
  # and minus the HEALTH_DIR assignment
  tail -n +2 "$SCRIPT" | sed '/^HEALTH_DIR=/d' >> "$WRAPPER"
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

  # Send idle with teammate name "dev-01", use $$ as PID (alive process)
  echo "{\"agent_type\":\"dev\",\"name\":\"dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle

  # After idle, a health file should exist (bootstrapped)
  [ -f "$HEALTH_DIR/dev-01.json" ]
}

@test "unique keying: two Dev teammates get separate files" {
  # Start two different dev teammates with alive PIDs
  echo "{\"agent_type\":\"dev\",\"name\":\"dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  echo "{\"agent_type\":\"dev\",\"name\":\"dev-02\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  # Both should have separate health files
  [ -f "$HEALTH_DIR/dev-01.json" ]
  [ -f "$HEALTH_DIR/dev-02.json" ]
}

@test "idle increments per-teammate, not by role" {
  # Start two devs with alive PIDs
  echo "{\"agent_type\":\"dev\",\"name\":\"dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  echo "{\"agent_type\":\"dev\",\"name\":\"dev-02\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  # Idle dev-01 twice
  echo "{\"agent_type\":\"dev\",\"name\":\"dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle
  echo "{\"agent_type\":\"dev\",\"name\":\"dev-01\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle

  # dev-01 should have idle_count=2, dev-02 still at 0
  count_01=$(jq -r '.idle_count' "$HEALTH_DIR/dev-01.json")
  count_02=$(jq -r '.idle_count' "$HEALTH_DIR/dev-02.json")
  [ "$count_01" -eq 2 ]
  [ "$count_02" -eq 0 ]
}

@test "stuck advisory emitted at idle_count >= 3" {
  echo "{\"agent_type\":\"dev\",\"name\":\"dev-03\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" start

  # Idle 3 times
  echo "{\"agent_type\":\"dev\",\"name\":\"dev-03\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle > /dev/null
  echo "{\"agent_type\":\"dev\",\"name\":\"dev-03\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle > /dev/null

  # Third idle should produce stuck advisory
  output=$(echo "{\"agent_type\":\"dev\",\"name\":\"dev-03\",\"pid\":\"$$\"}" | \
    TEST_HEALTH_DIR="$HEALTH_DIR" bash "$WRAPPER" idle)

  echo "$output" | grep -qi 'stuck\|appears stuck\|idle_count=3'
}

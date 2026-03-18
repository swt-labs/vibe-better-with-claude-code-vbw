#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

# Helper: create STATE.md with a Phase: line
create_state_with_phase() {
  local current="$1" total="$2" name="${3:-Setup}"
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<EOF
# State

## Current Phase
Phase: ${current} of ${total} (${name})
Plans: 0/0
Progress: 0%
Status: active
EOF
}

# Helper: create N phase directories
create_phase_dirs() {
  local count="$1"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases"
  for i in $(seq 1 "$count"); do
    local padded
    padded=$(printf '%02d' "$i")
    mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/${padded}-phase-${i}"
  done
}

# --- Basic total recalculation ---

@test "update-phase-total: increments total after phase added" {
  cd "$TEST_TEMP_DIR"
  create_state_with_phase 1 3 "Setup"
  create_phase_dirs 4  # 4 dirs now, was 3
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning
  [ "$status" -eq 0 ]
  grep -q '^Phase: 1 of 4' .vbw-planning/STATE.md
}

@test "update-phase-total: decrements total after phase removed" {
  cd "$TEST_TEMP_DIR"
  create_state_with_phase 1 4 "Setup"
  create_phase_dirs 3  # 3 dirs now, was 4
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning
  [ "$status" -eq 0 ]
  grep -q '^Phase: 1 of 3' .vbw-planning/STATE.md
}

@test "update-phase-total: preserves current phase number without flags" {
  cd "$TEST_TEMP_DIR"
  create_state_with_phase 2 3 "Build"
  create_phase_dirs 4
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning
  [ "$status" -eq 0 ]
  grep -q '^Phase: 2 of 4' .vbw-planning/STATE.md
}

# --- Insert mode ---

@test "update-phase-total: --inserted shifts current when inserted before" {
  cd "$TEST_TEMP_DIR"
  create_state_with_phase 2 3 "Build"
  create_phase_dirs 4  # after insert, 4 dirs
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning --inserted 1
  [ "$status" -eq 0 ]
  # Current was 2, inserted at 1, so current becomes 3
  grep -q '^Phase: 3 of 4' .vbw-planning/STATE.md
}

@test "update-phase-total: --inserted shifts current when inserted at same position" {
  cd "$TEST_TEMP_DIR"
  create_state_with_phase 2 3 "Build"
  create_phase_dirs 4
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning --inserted 2
  [ "$status" -eq 0 ]
  # Current was 2, inserted at 2, so current becomes 3
  grep -q '^Phase: 3 of 4' .vbw-planning/STATE.md
}

@test "update-phase-total: --inserted no shift when inserted after current" {
  cd "$TEST_TEMP_DIR"
  create_state_with_phase 2 3 "Build"
  create_phase_dirs 4
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning --inserted 4
  [ "$status" -eq 0 ]
  # Current was 2, inserted at 4, no shift
  grep -q '^Phase: 2 of 4' .vbw-planning/STATE.md
}

# --- Remove mode ---

@test "update-phase-total: --removed shifts current when removed before" {
  cd "$TEST_TEMP_DIR"
  create_state_with_phase 3 4 "Polish"
  create_phase_dirs 3  # after remove, 3 dirs
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning --removed 1
  [ "$status" -eq 0 ]
  # Current was 3, removed at 1, so current becomes 2
  grep -q '^Phase: 2 of 3' .vbw-planning/STATE.md
}

@test "update-phase-total: --removed no shift when removed after current" {
  cd "$TEST_TEMP_DIR"
  create_state_with_phase 2 4 "Build"
  create_phase_dirs 3
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning --removed 4
  [ "$status" -eq 0 ]
  # Current was 2, removed at 4, no shift
  grep -q '^Phase: 2 of 3' .vbw-planning/STATE.md
}

@test "update-phase-total: --removed no shift when removed at current position" {
  cd "$TEST_TEMP_DIR"
  # Remove at position 2, current is 2 — guard in vibe.md prevents this
  # for phases with work, but if it happens, current stays same
  create_state_with_phase 2 4 "Build"
  create_phase_dirs 3
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning --removed 2
  [ "$status" -eq 0 ]
  # Current was 2, removed at 2 (not >), no shift
  grep -q '^Phase: 2 of 3' .vbw-planning/STATE.md
}

# --- Edge cases ---

@test "update-phase-total: no-op when STATE.md missing" {
  cd "$TEST_TEMP_DIR"
  create_phase_dirs 3
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning
  [ "$status" -eq 0 ]
}

@test "update-phase-total: no-op when phases dir missing" {
  cd "$TEST_TEMP_DIR"
  create_state_with_phase 1 3 "Setup"
  rmdir "$TEST_TEMP_DIR/.vbw-planning/phases" 2>/dev/null || true
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning
  [ "$status" -eq 0 ]
  # STATE.md unchanged
  grep -q '^Phase: 1 of 3' .vbw-planning/STATE.md
}

@test "update-phase-total: preserves other STATE.md content" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/STATE.md <<'EOF'
# State

## Current Phase
Phase: 1 of 3 (Setup)
Plans: 2/5
Progress: 40%
Status: active

## Decisions
- Decision A

## Todos
- [ ] Task 1
EOF
  create_phase_dirs 4
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning
  [ "$status" -eq 0 ]
  grep -q '^Phase: 1 of 4' .vbw-planning/STATE.md
  grep -q '^Plans: 2/5' .vbw-planning/STATE.md
  grep -q '^Status: active' .vbw-planning/STATE.md
  grep -q '## Decisions' .vbw-planning/STATE.md
  grep -q 'Task 1' .vbw-planning/STATE.md
}

@test "update-phase-total: resolves phase name from directory" {
  cd "$TEST_TEMP_DIR"
  create_state_with_phase 1 2 "Old Name"
  mkdir -p .vbw-planning/phases/01-setup
  mkdir -p .vbw-planning/phases/02-build
  mkdir -p .vbw-planning/phases/03-deploy
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning
  [ "$status" -eq 0 ]
  # Name should be resolved from dir 01-setup
  grep -q '^Phase: 1 of 3 (Setup)' .vbw-planning/STATE.md
}

@test "update-phase-total: clamps current to total when over" {
  cd "$TEST_TEMP_DIR"
  create_state_with_phase 5 5 "Final"
  create_phase_dirs 3  # only 3 dirs remain
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning
  [ "$status" -eq 0 ]
  # Current clamped to 3
  grep -q '^Phase: 3 of 3' .vbw-planning/STATE.md
}

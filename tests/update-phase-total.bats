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

# --- F-09: nameless Phase: format (bootstrap output) ---

@test "update-phase-total: handles nameless Phase: line from bootstrap" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/STATE.md <<'EOF'
# State

## Current Phase
Phase: 1 of 3
Plans: 0/0
Progress: 0%
Status: ready
EOF
  create_phase_dirs 4
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning
  [ "$status" -eq 0 ]
  grep -q '^Phase: 1 of 4' .vbw-planning/STATE.md
}

# --- F-08: Phase Status section rebuild ---

@test "update-phase-total: rebuilds Phase Status after add" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/STATE.md <<'EOF'
# State

## Current Phase
Phase: 1 of 3 (Setup)
Plans: 0/0
Progress: 0%
Status: active

## Phase Status
- **Phase 1:** Pending planning
- **Phase 2:** Pending
- **Phase 3:** Pending

## Decisions
- Decision A
EOF
  create_phase_dirs 4  # added 4th phase
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning
  [ "$status" -eq 0 ]
  # Phase Status should now have 4 entries
  local count
  count=$(grep -c '^\- \*\*Phase [0-9]' .vbw-planning/STATE.md)
  [ "$count" -eq 4 ]
}

@test "update-phase-total: rebuilds Phase Status after remove" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/STATE.md <<'EOF'
# State

## Current Phase
Phase: 1 of 4 (Setup)
Plans: 0/0
Progress: 0%
Status: active

## Phase Status
- **Phase 1:** Pending planning
- **Phase 2:** Pending
- **Phase 3:** Pending
- **Phase 4:** Pending
EOF
  create_phase_dirs 3  # removed one
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning --removed 4
  [ "$status" -eq 0 ]
  local count
  count=$(grep -c '^\- \*\*Phase [0-9]' .vbw-planning/STATE.md)
  [ "$count" -eq 3 ]
}

@test "update-phase-total: Phase Status preserves Decisions section below" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/STATE.md <<'EOF'
# State

## Current Phase
Phase: 1 of 2 (Setup)
Plans: 0/0
Progress: 0%
Status: active

## Phase Status
- **Phase 1:** Pending planning
- **Phase 2:** Pending

## Decisions
- Important decision
EOF
  create_phase_dirs 3
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning
  [ "$status" -eq 0 ]
  grep -q '## Decisions' .vbw-planning/STATE.md
  grep -q 'Important decision' .vbw-planning/STATE.md
}

# --- F-11: position validation ---

@test "update-phase-total: non-numeric position is no-op" {
  cd "$TEST_TEMP_DIR"
  create_state_with_phase 2 3 "Build"
  create_phase_dirs 3
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning --inserted abc
  [ "$status" -eq 0 ]
  # Should exit early without changes
  grep -q '^Phase: 2 of 3' .vbw-planning/STATE.md
}

# --- F-15: status inference with actual artifacts ---

@test "update-phase-total: Phase Status infers Complete from plans+summaries" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/STATE.md <<'EOF'
# State

## Current Phase
Phase: 2 of 3 (Build)
Plans: 0/0
Progress: 0%
Status: active

## Phase Status
- **Phase 1:** Pending
- **Phase 2:** Pending
- **Phase 3:** Pending
EOF
  mkdir -p .vbw-planning/phases/01-setup
  mkdir -p .vbw-planning/phases/02-build
  mkdir -p .vbw-planning/phases/03-deploy
  # Phase 1: complete (1 plan, 1 terminal summary)
  touch .vbw-planning/phases/01-setup/01-PLAN.md
  printf -- '---\nstatus: complete\n---\n' > .vbw-planning/phases/01-setup/01-SUMMARY.md
  # Phase 2: has a plan only
  touch .vbw-planning/phases/02-build/01-PLAN.md
  # Phase 3: empty
  run bash "$SCRIPTS_DIR/update-phase-total.sh" .vbw-planning
  [ "$status" -eq 0 ]
  grep -q 'Phase 1.*Complete' .vbw-planning/STATE.md
  grep -q 'Phase 2.*Planned' .vbw-planning/STATE.md
  grep -q 'Phase 3.*Pending' .vbw-planning/STATE.md
}

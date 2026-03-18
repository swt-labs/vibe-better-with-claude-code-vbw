#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

# --- Greenfield format tests (no existing STATE.md) ---

@test "bootstrap-state: emits ## Current Phase section header" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test Project" "MVP" 3
  [ "$status" -eq 0 ]
  grep -q '^## Current Phase$' .vbw-planning/STATE.md
}

@test "bootstrap-state: emits Phase: line matching reader grep pattern" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test Project" "MVP" 3
  [ "$status" -eq 0 ]
  grep -q '^Phase: 1 of 3$' .vbw-planning/STATE.md
}

@test "bootstrap-state: emits Plans: line" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test Project" "MVP" 3
  [ "$status" -eq 0 ]
  grep -q '^Plans: 0/0$' .vbw-planning/STATE.md
}

@test "bootstrap-state: emits Progress: line" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test Project" "MVP" 3
  [ "$status" -eq 0 ]
  grep -q '^Progress: 0%$' .vbw-planning/STATE.md
}

@test "bootstrap-state: emits Status: line" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test Project" "MVP" 3
  [ "$status" -eq 0 ]
  grep -q '^Status: ready$' .vbw-planning/STATE.md
}

@test "bootstrap-state: emits Activity Log (not Recent Activity)" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test Project" "MVP" 3
  [ "$status" -eq 0 ]
  grep -q '^## Activity Log$' .vbw-planning/STATE.md
  ! grep -q '## Recent Activity' .vbw-planning/STATE.md
}

@test "bootstrap-state: emits Blockers section" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test Project" "MVP" 3
  [ "$status" -eq 0 ]
  grep -q '^## Blockers$' .vbw-planning/STATE.md
}

@test "bootstrap-state: Phase Status lists all phases" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test Project" "MVP" 4
  [ "$status" -eq 0 ]
  grep -q 'Phase 1.*Pending planning' .vbw-planning/STATE.md
  grep -q 'Phase 2.*Pending' .vbw-planning/STATE.md
  grep -q 'Phase 3.*Pending' .vbw-planning/STATE.md
  grep -q 'Phase 4.*Pending' .vbw-planning/STATE.md
}

@test "bootstrap-state: state-updater sed patterns match output format" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test Project" "MVP" 3
  [ "$status" -eq 0 ]

  # Simulate state-updater.sh sed updates
  local tmp=".vbw-planning/STATE.md.tmp"
  sed 's/^Phase: .*/Phase: 2 of 3 (Core Build)/' .vbw-planning/STATE.md | \
    sed 's/^Plans: .*/Plans: 1\/2/' | \
    sed 's/^Progress: .*/Progress: 50%/' | \
    sed 's/^Status: .*/Status: active/' > "$tmp"
  mv "$tmp" .vbw-planning/STATE.md

  grep -q '^Phase: 2 of 3 (Core Build)$' .vbw-planning/STATE.md
  grep -q '^Plans: 1/2$' .vbw-planning/STATE.md
  grep -q '^Progress: 50%$' .vbw-planning/STATE.md
  grep -q '^Status: active$' .vbw-planning/STATE.md
}

@test "bootstrap-state: emits Project and Milestone metadata lines" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "My Project" "Alpha Release" 2
  [ "$status" -eq 0 ]
  grep -q '^\*\*Project:\*\* My Project$' .vbw-planning/STATE.md
  grep -q '^\*\*Milestone:\*\* Alpha Release$' .vbw-planning/STATE.md
}

@test "bootstrap-state: rejects PHASE_COUNT=0" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test" "MVP" 0
  [ "$status" -eq 1 ]
}

@test "bootstrap-state: rejects non-numeric PHASE_COUNT" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test" "MVP" abc
  [ "$status" -eq 1 ]
}

# --- Brownfield preservation tests (existing STATE.md) ---

@test "bootstrap-state: preserves existing Todos from prior milestone" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/STATE.md <<'EOF'
# State

**Project:** Test Project

## Decisions
- Use SwiftUI

## Todos
- Fix auth regression (added 2026-02-10)
- [HIGH] Migrate API (added 2026-02-11)

## Blockers
None
EOF

  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test Project" "Beta" 2
  [ "$status" -eq 0 ]
  grep -q "Fix auth regression" .vbw-planning/STATE.md
  grep -q "Migrate API" .vbw-planning/STATE.md
}

@test "bootstrap-state: preserves existing Decisions from prior milestone" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/STATE.md <<'EOF'
# State

**Project:** Test Project

## Key Decisions
- Use SwiftUI for all new views
- Adopt MVVM pattern

## Todos
None.
EOF

  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test Project" "Beta" 2
  [ "$status" -eq 0 ]
  grep -q "Use SwiftUI" .vbw-planning/STATE.md
  grep -q "MVVM pattern" .vbw-planning/STATE.md
}

@test "bootstrap-state: preserves existing Blockers from prior milestone" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/STATE.md <<'EOF'
# State

**Project:** Test Project

## Decisions
- Initial setup

## Todos
None.

## Blockers
- Waiting on API team for auth endpoint spec
- CI runner quota exceeded
EOF

  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test Project" "Beta" 2
  [ "$status" -eq 0 ]
  grep -q "Waiting on API team" .vbw-planning/STATE.md
  grep -q "CI runner quota" .vbw-planning/STATE.md
}

@test "bootstrap-state: preserves existing Codebase Profile from prior milestone" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/STATE.md <<'EOF'
# State

**Project:** Test Project

## Decisions
- Initial setup

## Todos
None.

## Blockers
None

## Codebase Profile
- Brownfield: true
- Tracked files (approx): 137
- Primary languages: Swift
- Test Coverage: 72%
EOF

  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test Project" "Beta" 2
  [ "$status" -eq 0 ]
  grep -q "## Codebase Profile" .vbw-planning/STATE.md
  grep -q "Brownfield: true" .vbw-planning/STATE.md
  grep -q "Primary languages: Swift" .vbw-planning/STATE.md
}

# --- Post-archive restoration test ---

@test "bootstrap-state: restores ## Current Phase after archive strips it" {
  cd "$TEST_TEMP_DIR"

  # Simulate persist-state-after-ship.sh output (project-level sections only)
  cat > .vbw-planning/STATE.md <<'EOF'
# State

**Project:** Test Project

## Decisions
- Use SwiftUI for all new views

## Todos
- Fix auth regression (added 2026-02-10)

## Blockers
None

## Codebase Profile
- Brownfield: true
- Tracked files (approx): 137
EOF

  # Verify Current Phase is NOT present before
  ! grep -q '## Current Phase' .vbw-planning/STATE.md

  # Run bootstrap-state.sh (simulates scope mode calling it)
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test Project" "New Milestone" 3
  [ "$status" -eq 0 ]

  # Current Phase section should now be present
  grep -q '^## Current Phase$' .vbw-planning/STATE.md
  grep -q '^Phase: 1 of 3$' .vbw-planning/STATE.md
  grep -q '^Plans: 0/0$' .vbw-planning/STATE.md
  grep -q '^Status: ready$' .vbw-planning/STATE.md

  # Project-level sections should be preserved
  grep -q "Use SwiftUI" .vbw-planning/STATE.md
  grep -q "Fix auth regression" .vbw-planning/STATE.md
  grep -q "Brownfield: true" .vbw-planning/STATE.md
}

@test "bootstrap-state: all 4 project-level sections survive full archive+scope cycle" {
  cd "$TEST_TEMP_DIR"

  # Step 1: Start with a complete STATE.md (as it looks during active execution)
  cat > .vbw-planning/STATE.md <<'EOF'
# State

**Project:** Test Project

## Current Phase
Phase: 3 of 3 (Final cleanup)
Plans: 2/2
Progress: 100%
Status: complete

## Decisions
- Use SwiftUI for all new views
- Adopt MVVM pattern

## Todos
- Fix auth module regression (added 2026-02-10)
- [HIGH] Migrate to new API (added 2026-02-11)

## Blockers
None

## Codebase Profile
- Brownfield: true
- Tracked files (approx): 137
- Primary languages: Swift

## Activity Log
- 2026-02-12: Phase 3 built
EOF

  # Step 2: Archive (persist-state-after-ship.sh strips Current Phase + Activity Log)
  mkdir -p .vbw-planning/milestones/default
  cp .vbw-planning/STATE.md .vbw-planning/milestones/default/STATE.md
  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/default/STATE.md .vbw-planning/STATE.md "Test Project"
  [ "$status" -eq 0 ]

  # Verify Current Phase is gone
  ! grep -q '## Current Phase' .vbw-planning/STATE.md

  # Step 3: Scope new milestone (bootstrap-state.sh restores Current Phase)
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    .vbw-planning/STATE.md "Test Project" "Phase 2 Milestone" 4
  [ "$status" -eq 0 ]

  # Current Phase restored
  grep -q '^## Current Phase$' .vbw-planning/STATE.md
  grep -q '^Phase: 1 of 4$' .vbw-planning/STATE.md

  # All 4 project-level sections preserved
  grep -q "Decisions" .vbw-planning/STATE.md
  grep -q "Use SwiftUI" .vbw-planning/STATE.md
  grep -q "## Todos" .vbw-planning/STATE.md
  grep -q "Fix auth module regression" .vbw-planning/STATE.md
  grep -q "## Blockers" .vbw-planning/STATE.md
  grep -q "## Codebase Profile" .vbw-planning/STATE.md
  grep -q "Brownfield: true" .vbw-planning/STATE.md
}

@test "bootstrap-state: fails with missing arguments" {
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" .vbw-planning/STATE.md "Test"
  [ "$status" -eq 1 ]
}

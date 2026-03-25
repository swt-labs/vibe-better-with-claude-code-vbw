#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "milestone-context: MILESTONE-CONTEXT.md template has required sections" {
  TEMPLATE="$PROJECT_ROOT/templates/MILESTONE-CONTEXT.md"
  [ -f "$TEMPLATE" ]

  grep -q "## Scope Boundary" "$TEMPLATE"
  grep -q "## Decomposition Decisions" "$TEMPLATE"
  grep -q "## Requirement Mapping" "$TEMPLATE"
  grep -q "## Key Decisions" "$TEMPLATE"
  grep -q "## Deferred Ideas" "$TEMPLATE"
}

@test "milestone-context: compile-context injects milestone CONTEXT.md when present" {
  TEMP_PLANNING="$TEST_TEMP_DIR/isolated-planning"
  TEMP_PHASES="$TEMP_PLANNING/phases"
  mkdir -p "$TEMP_PHASES/01-test-phase"

  mkdir -p "$TEMP_PLANNING"
  echo '{"v3_context_cache": false}' > "$TEMP_PLANNING/config.json"

  cat > "$TEMP_PLANNING/ROADMAP.md" <<'ROADMAP'
# Roadmap

## Phase 1: Test Phase
**Goal:** Test phase goal
**Success:** Test criteria
**Reqs:** Not available
ROADMAP

  cat > "$TEMP_PLANNING/CONTEXT.md" <<'CTX'
# Test Project — Milestone Context

Gathered: 2026-03-25
Calibration: architect

## Scope Boundary
Build a recipe recommendation app.

## Decomposition Decisions
### Phase Count & Grouping
3 phases because auth, core, polish are independent concerns.
CTX

  rm -rf "$TEST_TEMP_DIR/.vbw-planning"
  ln -sf "$TEMP_PLANNING" "$TEST_TEMP_DIR/.vbw-planning"

  cd "$TEST_TEMP_DIR"
  bash "$PROJECT_ROOT/scripts/compile-context.sh" 01 lead "$TEMP_PHASES"

  CONTEXT_FILE="$TEMP_PHASES/01-test-phase/.context-lead.md"
  [ -f "$CONTEXT_FILE" ]

  grep -q "### Milestone Scope Context" "$CONTEXT_FILE"
  grep -q "Scope Boundary" "$CONTEXT_FILE"
  grep -q "recipe recommendation app" "$CONTEXT_FILE"
}

@test "milestone-context: compile-context omits milestone section when no CONTEXT.md" {
  TEMP_PLANNING="$TEST_TEMP_DIR/isolated-planning"
  TEMP_PHASES="$TEMP_PLANNING/phases"
  mkdir -p "$TEMP_PHASES/01-test-phase"

  mkdir -p "$TEMP_PLANNING"
  echo '{"v3_context_cache": false}' > "$TEMP_PLANNING/config.json"

  cat > "$TEMP_PLANNING/ROADMAP.md" <<'ROADMAP'
# Roadmap

## Phase 1: Test Phase
**Goal:** Test phase goal
**Success:** Test criteria
**Reqs:** Not available
ROADMAP

  # No CONTEXT.md created

  rm -rf "$TEST_TEMP_DIR/.vbw-planning"
  ln -sf "$TEMP_PLANNING" "$TEST_TEMP_DIR/.vbw-planning"

  cd "$TEST_TEMP_DIR"
  bash "$PROJECT_ROOT/scripts/compile-context.sh" 01 lead "$TEMP_PHASES"

  CONTEXT_FILE="$TEMP_PHASES/01-test-phase/.context-lead.md"
  [ -f "$CONTEXT_FILE" ]

  # Should NOT contain milestone context section
  ! grep -q "### Milestone Scope Context" "$CONTEXT_FILE"
}

@test "milestone-context: compile-context injects milestone context for all roles" {
  TEMP_PLANNING="$TEST_TEMP_DIR/isolated-planning"
  TEMP_PHASES="$TEMP_PLANNING/phases"
  mkdir -p "$TEMP_PHASES/01-test-phase"

  mkdir -p "$TEMP_PLANNING"
  echo '{"v3_context_cache": false}' > "$TEMP_PLANNING/config.json"

  cat > "$TEMP_PLANNING/ROADMAP.md" <<'ROADMAP'
# Roadmap

## Phase 1: Test Phase
**Goal:** Test phase goal
**Success:** Test criteria
**Reqs:** Not available
ROADMAP

  cat > "$TEMP_PLANNING/CONTEXT.md" <<'CTX'
# Test — Milestone Context

## Scope Boundary
Test milestone scope.
CTX

  rm -rf "$TEST_TEMP_DIR/.vbw-planning"
  ln -sf "$TEMP_PLANNING" "$TEST_TEMP_DIR/.vbw-planning"

  cd "$TEST_TEMP_DIR"

  for role in lead dev qa scout debugger architect; do
    bash "$PROJECT_ROOT/scripts/compile-context.sh" 01 "$role" "$TEMP_PHASES"
    CONTEXT_FILE="$TEMP_PHASES/01-test-phase/.context-${role}.md"
    [ -f "$CONTEXT_FILE" ] || { echo "Missing .context-${role}.md"; return 1; }
    grep -q "### Milestone Scope Context" "$CONTEXT_FILE" || { echo "Role $role missing milestone context"; return 1; }
  done
}

@test "milestone-context: unarchive-milestone restores CONTEXT.md" {
  cd "$TEST_TEMP_DIR"

  # Create archived milestone with CONTEXT.md
  MILESTONE_DIR=".vbw-planning/milestones/test-ms"
  mkdir -p "$MILESTONE_DIR/phases/01-setup"
  touch "$MILESTONE_DIR/phases/01-setup/01-01-PLAN.md"
  touch "$MILESTONE_DIR/phases/01-setup/01-01-SUMMARY.md"

  cat > "$MILESTONE_DIR/ROADMAP.md" <<'EOF'
# Roadmap
## Phase 1: Setup
EOF

  cat > "$MILESTONE_DIR/STATE.md" <<'EOF'
# State
**Project:** Test
Phase: 1 of 1
Status: complete

## Key Decisions
| Decision | Date | Rationale |

## Todos
None.

## Blockers
None

## Activity Log
- 2026-03-25: Created
EOF

  cat > "$MILESTONE_DIR/CONTEXT.md" <<'EOF'
# Test — Milestone Context

## Scope Boundary
Build test scope.

## Decomposition Decisions
### Phase Count & Grouping
1 phase for simplicity.
EOF

  cat > "$MILESTONE_DIR/SHIPPED.md" <<'EOF'
# Shipped
Date: 2026-03-25
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" "$MILESTONE_DIR" ".vbw-planning"
  [ "$status" -eq 0 ]

  # CONTEXT.md should be restored to planning root
  [ -f ".vbw-planning/CONTEXT.md" ]
  grep -q "Build test scope" ".vbw-planning/CONTEXT.md"
}

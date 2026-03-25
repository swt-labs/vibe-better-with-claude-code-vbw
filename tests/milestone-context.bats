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

## Phase 01: Test Phase
**Goal**: Test phase goal
**Success Criteria**: Test criteria
**Requirements**: Not available
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

  ORIG_CLAUDE_DIR="${CLAUDE_DIR:-}"
  export CLAUDE_DIR="$TEST_TEMP_DIR"
  rm -rf "$TEST_TEMP_DIR/.vbw-planning"
  ln -sf "$TEMP_PLANNING" "$TEST_TEMP_DIR/.vbw-planning"

  cd "$TEST_TEMP_DIR"
  bash "$PROJECT_ROOT/scripts/compile-context.sh" 01 lead "$TEMP_PHASES"

  [ -n "$ORIG_CLAUDE_DIR" ] && export CLAUDE_DIR="$ORIG_CLAUDE_DIR" || unset CLAUDE_DIR

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

## Phase 01: Test Phase
**Goal**: Test phase goal
**Success Criteria**: Test criteria
**Requirements**: Not available
ROADMAP

  # No CONTEXT.md created

  ORIG_CLAUDE_DIR="${CLAUDE_DIR:-}"
  export CLAUDE_DIR="$TEST_TEMP_DIR"
  rm -rf "$TEST_TEMP_DIR/.vbw-planning"
  ln -sf "$TEMP_PLANNING" "$TEST_TEMP_DIR/.vbw-planning"

  cd "$TEST_TEMP_DIR"
  bash "$PROJECT_ROOT/scripts/compile-context.sh" 01 lead "$TEMP_PHASES"

  [ -n "$ORIG_CLAUDE_DIR" ] && export CLAUDE_DIR="$ORIG_CLAUDE_DIR" || unset CLAUDE_DIR

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

## Phase 01: Test Phase
**Goal**: Test phase goal
**Success Criteria**: Test criteria
**Requirements**: Not available
ROADMAP

  cat > "$TEMP_PLANNING/CONTEXT.md" <<'CTX'
# Test — Milestone Context

## Scope Boundary
Test milestone scope.
CTX

  ORIG_CLAUDE_DIR="${CLAUDE_DIR:-}"
  export CLAUDE_DIR="$TEST_TEMP_DIR"
  rm -rf "$TEST_TEMP_DIR/.vbw-planning"
  ln -sf "$TEMP_PLANNING" "$TEST_TEMP_DIR/.vbw-planning"

  cd "$TEST_TEMP_DIR"

  for role in lead dev qa scout debugger architect; do
    bash "$PROJECT_ROOT/scripts/compile-context.sh" 01 "$role" "$TEMP_PHASES"
    CONTEXT_FILE="$TEMP_PHASES/01-test-phase/.context-${role}.md"
    [ -f "$CONTEXT_FILE" ] || { echo "Missing .context-${role}.md"; return 1; }
    grep -q "### Milestone Scope Context" "$CONTEXT_FILE" || { echo "Role $role missing milestone context"; return 1; }
  done

  [ -n "$ORIG_CLAUDE_DIR" ] && export CLAUDE_DIR="$ORIG_CLAUDE_DIR" || unset CLAUDE_DIR
}

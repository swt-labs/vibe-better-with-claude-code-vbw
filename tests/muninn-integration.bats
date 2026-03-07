#!/usr/bin/env bats
# Tests for MuninnDB native integration — verifies MuninnDB is
# unconditionally integrated as the memory system across all components.

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  # Create minimal phase directory structure for compile-context tests
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase"
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
# Test Roadmap
## Phase 1: Test Phase
**Goal:** Test goal
**Success:** Tests pass
**Reqs:** REQ-01
EOF
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/01-01-PLAN.md" <<'EOF'
---
phase: 1
plan: 1
title: "Test Plan"
wave: 1
depends_on: []
must_haves: ["test"]
---
# Test Plan
## Tasks
### Task 1: Test
- **Files:** test.sh
- **Action:** Test
EOF
}

teardown() {
  teardown_temp_dir
}

# ============================================================
# MuninnDB config
# ============================================================

@test "defaults.json has muninndb_vault field" {
  run jq -e 'has("muninndb_vault")' "$CONFIG_DIR/defaults.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "test config includes muninndb_vault" {
  run jq -r '.muninndb_vault' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "test-vault" ]
}

# ============================================================
# compile-context.sh — emit_muninn_memory_hint
# ============================================================

@test "compile-context.sh defines emit_muninn_memory_hint function" {
  grep -q "emit_muninn_memory_hint()" "$SCRIPTS_DIR/compile-context.sh"
}

@test "compile-context.sh emits MuninnDB hint for lead role" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 lead ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Cross-Phase Memory" ".vbw-planning/phases/01-test-phase/.context-lead.md"
  grep -q "muninn_activate" ".vbw-planning/phases/01-test-phase/.context-lead.md"
}

@test "compile-context.sh emits MuninnDB hint for dev role" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 dev ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Cross-Phase Memory" ".vbw-planning/phases/01-test-phase/.context-dev.md"
  grep -q "muninn_activate" ".vbw-planning/phases/01-test-phase/.context-dev.md"
}

@test "compile-context.sh emits MuninnDB hint for qa role" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 qa ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Cross-Phase Memory" ".vbw-planning/phases/01-test-phase/.context-qa.md"
  grep -q "muninn_activate" ".vbw-planning/phases/01-test-phase/.context-qa.md"
}

@test "compile-context.sh emits MuninnDB hint for scout role" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 scout ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Cross-Phase Memory" ".vbw-planning/phases/01-test-phase/.context-scout.md"
  grep -q "muninn_activate" ".vbw-planning/phases/01-test-phase/.context-scout.md"
}

@test "compile-context.sh emits MuninnDB hint for debugger role" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 debugger ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Cross-Phase Memory" ".vbw-planning/phases/01-test-phase/.context-debugger.md"
  grep -q "muninn_activate" ".vbw-planning/phases/01-test-phase/.context-debugger.md"
}

@test "compile-context.sh emits MuninnDB hint for architect role" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 architect ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Cross-Phase Memory" ".vbw-planning/phases/01-test-phase/.context-architect.md"
  grep -q "muninn_activate" ".vbw-planning/phases/01-test-phase/.context-architect.md"
}

# ============================================================
# bootstrap-state.sh — Memory section
# ============================================================

@test "bootstrap-state.sh generates Memory section with vault" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    "$TEST_TEMP_DIR/STATE.md" "Test Project" "v1.0" 3 "my-vault"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/STATE.md" ]
  grep -q "## Memory" "$TEST_TEMP_DIR/STATE.md"
  grep -q "Vault.*my-vault" "$TEST_TEMP_DIR/STATE.md"
}

@test "bootstrap-state.sh generates Memory section without vault" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    "$TEST_TEMP_DIR/STATE.md" "Test Project" "v1.0" 3
  [ "$status" -eq 0 ]
  grep -q "## Memory" "$TEST_TEMP_DIR/STATE.md"
  grep -q "pending setup" "$TEST_TEMP_DIR/STATE.md"
}

@test "bootstrap-state.sh preserves existing Memory section on re-bootstrap" {
  cd "$TEST_TEMP_DIR"
  cat > "$TEST_TEMP_DIR/STATE.md" <<'EOF'
# State

## Memory
**Vault:** existing-vault
**Custom note:** preserved
EOF

  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    "$TEST_TEMP_DIR/STATE.md" "Test Project" "v2.0" 5 "new-vault"
  [ "$status" -eq 0 ]
  grep -q "existing-vault" "$TEST_TEMP_DIR/STATE.md"
  grep -q "Custom note.*preserved" "$TEST_TEMP_DIR/STATE.md"
}

# ============================================================
# persist-state-after-ship.sh — Memory persistence
# ============================================================

@test "persist-state-after-ship.sh preserves Memory section" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/milestones/default
  cat > .vbw-planning/milestones/default/STATE.md <<'EOF'
# State

**Project:** Test Project

## Current Phase
Phase: 2 of 2

## Decisions
- Use MuninnDB for memory

## Todos
None.

## Blockers
None

## Memory
**Vault:** test-vault
EOF

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/default/STATE.md .vbw-planning/STATE.md "Test Project"
  [ "$status" -eq 0 ]
  grep -q "## Memory" .vbw-planning/STATE.md
  grep -q "Vault.*test-vault" .vbw-planning/STATE.md
}

# ============================================================
# Agent files — unconditional MuninnDB instructions
# ============================================================

@test "all agents reference MuninnDB tools" {
  for agent in vbw-lead vbw-dev vbw-qa vbw-scout vbw-debugger vbw-architect vbw-docs; do
    local agent_file="$PROJECT_ROOT/agents/${agent}.md"
    [ -f "$agent_file" ] || { echo "MISSING: $agent_file"; return 1; }
    grep -q "muninn" "$agent_file" || { echo "NO muninn ref: $agent"; return 1; }
  done
}

@test "all agents reference muninn_guide" {
  for agent in vbw-lead vbw-dev vbw-qa vbw-scout vbw-debugger vbw-architect vbw-docs; do
    local agent_file="$PROJECT_ROOT/agents/${agent}.md"
    [ -f "$agent_file" ] || { echo "MISSING: $agent_file"; return 1; }
    grep -q "muninn_guide" "$agent_file" || { echo "NO muninn_guide: $agent"; return 1; }
  done
}

@test "compile-context.sh hint includes muninn_guide" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 lead ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "muninn_guide" ".vbw-planning/phases/01-test-phase/.context-lead.md"
}

@test "init.md references muninn_guide after vault creation" {
  grep -q "muninn_guide" "$PROJECT_ROOT/commands/init.md"
}

# ============================================================
# Cache context — ROLLING-CONTEXT.md is not part of fingerprint
# ============================================================

@test "cache-context.sh hash ignores ROLLING-CONTEXT.md file" {
  cd "$TEST_TEMP_DIR"
  echo "# Old rolling context" > "$TEST_TEMP_DIR/.vbw-planning/ROLLING-CONTEXT.md"

  run bash "$SCRIPTS_DIR/cache-context.sh" 01 dev \
    ".vbw-planning/config.json" \
    ".vbw-planning/phases/01-test-phase/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)

  rm "$TEST_TEMP_DIR/.vbw-planning/ROLLING-CONTEXT.md"

  run bash "$SCRIPTS_DIR/cache-context.sh" 01 dev \
    ".vbw-planning/config.json" \
    ".vbw-planning/phases/01-test-phase/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" = "$HASH2" ]
}

# ============================================================
# Phase-aware memory hint
# ============================================================

@test "compile-context.sh emits phase-aware warning for phase > 1" {
  cd "$TEST_TEMP_DIR"
  # Create phase 02 directory
  mkdir -p ".vbw-planning/phases/02-second-phase"
  # Update ROADMAP for phase 2
  cat >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
## Phase 2: Second Phase
**Goal:** Second goal
**Success:** Tests pass
**Reqs:** REQ-02
EOF

  run bash "$SCRIPTS_DIR/compile-context.sh" 02 lead ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Phase 02: if recall returns 0 results, report a warning" ".vbw-planning/phases/02-second-phase/.context-lead.md"
}

@test "compile-context.sh omits warning for phase 1" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 lead ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  ! grep -q "if recall returns 0 results, report a warning" ".vbw-planning/phases/01-test-phase/.context-lead.md"
}

@test "SUMMARY.md template has memory_recalled field" {
  grep -q "memory_recalled" "$PROJECT_ROOT/templates/SUMMARY.md"
}

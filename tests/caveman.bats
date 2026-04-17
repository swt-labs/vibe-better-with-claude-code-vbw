#!/usr/bin/env bats

# Tests for caveman language mode integration
# Verifies resolve-caveman-level.sh, config injection in session-start.sh,
# compile-context.sh, and compaction-instructions.sh

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase"
}

teardown() {
  teardown_temp_dir
}

# ---------------------------------------------------------------------------
# resolve-caveman-level.sh — passthrough for non-auto values
# ---------------------------------------------------------------------------

@test "resolve-caveman-level: non-auto value passes through unchanged (full)" {
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "full" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "full" ]
}

@test "resolve-caveman-level: non-auto value passes through unchanged (none)" {
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "none" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "none" ]
}

@test "resolve-caveman-level: non-auto value passes through unchanged (lite)" {
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "lite" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "lite" ]
}

@test "resolve-caveman-level: non-auto value passes through unchanged (ultra)" {
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "ultra" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "ultra" ]
}

# ---------------------------------------------------------------------------
# resolve-caveman-level.sh — auto mode with .context-usage
# ---------------------------------------------------------------------------

@test "resolve-caveman-level: auto with missing .context-usage defaults to none" {
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "none" ]
}

@test "resolve-caveman-level: auto at 40% context usage resolves to none" {
  echo "test-session|40|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "none" ]
}

@test "resolve-caveman-level: auto at 50% context usage resolves to lite" {
  echo "test-session|50|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "lite" ]
}

@test "resolve-caveman-level: auto at 60% context usage resolves to lite" {
  echo "test-session|60|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "lite" ]
}

@test "resolve-caveman-level: auto at 70% context usage resolves to full" {
  echo "test-session|70|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "full" ]
}

@test "resolve-caveman-level: auto at 75% context usage resolves to full" {
  echo "test-session|75|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "full" ]
}

@test "resolve-caveman-level: auto at 85% context usage resolves to ultra" {
  echo "test-session|85|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "ultra" ]
}

@test "resolve-caveman-level: auto at 90% context usage resolves to ultra" {
  echo "test-session|90|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "ultra" ]
}

@test "resolve-caveman-level: auto at 49% context usage resolves to none" {
  echo "test-session|49|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "none" ]
}

@test "resolve-caveman-level: auto at 69% context usage resolves to lite" {
  echo "test-session|69|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "lite" ]
}

@test "resolve-caveman-level: auto at 84% context usage resolves to full" {
  echo "test-session|84|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "full" ]
}

@test "resolve-caveman-level: auto handles legacy 2-field context-usage format" {
  echo "70|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "full" ]
}

# ---------------------------------------------------------------------------
# compile-context.sh — caveman directive injection
# ---------------------------------------------------------------------------

# Helper: create minimal ROADMAP and REQUIREMENTS for compile-context.sh
create_compile_context_fixtures() {
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
# Test Roadmap
## Phase 1: Test Phase
**Goal:** Test goal
**Success:** Tests pass
**Reqs:** REQ-01
EOF
  cat > "$TEST_TEMP_DIR/.vbw-planning/REQUIREMENTS.md" <<'EOF'
- [ ] REQ-01: Test requirement
EOF
}

# Helper: set caveman flags in config.json
set_caveman_config() {
  local style="${1:-full}" commit="${2:-false}" review="${3:-false}"
  jq --arg s "$style" --argjson c "$commit" --argjson r "$review" \
    '.caveman_style = $s | .caveman_commit = $c | .caveman_review = $r' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
}

@test "compile-context: caveman directive injected for dev when caveman_style=full" {
  create_compile_context_fixtures
  set_caveman_config "full" false false
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 dev .vbw-planning/phases
  [ "$status" -eq 0 ]
  grep -q "Caveman Language" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-dev.md"
}

@test "compile-context: no caveman directive when caveman_style=none" {
  create_compile_context_fixtures
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 dev .vbw-planning/phases
  [ "$status" -eq 0 ]
  ! grep -q "Caveman Language" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-dev.md"
}

@test "compile-context: commit ref injected for lead when caveman_commit=true" {
  create_compile_context_fixtures
  set_caveman_config "lite" true false
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 lead .vbw-planning/phases
  [ "$status" -eq 0 ]
  grep -q "caveman-commit" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-lead.md"
}

@test "compile-context: review ref injected for qa when caveman_review=true" {
  create_compile_context_fixtures
  set_caveman_config "full" false true
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 qa .vbw-planning/phases
  [ "$status" -eq 0 ]
  grep -q "caveman-review" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-qa.md"
}

@test "compile-context: no commit ref for qa role even when caveman_commit=true" {
  create_compile_context_fixtures
  set_caveman_config "full" true false
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 qa .vbw-planning/phases
  [ "$status" -eq 0 ]
  ! grep -q "caveman-commit" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-qa.md"
}

@test "compile-context: caveman directive injected for scout (no extra arg)" {
  create_compile_context_fixtures
  set_caveman_config "full" false false
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 scout .vbw-planning/phases
  [ "$status" -eq 0 ]
  grep -q "Caveman Language" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-scout.md"
}

@test "compile-context: caveman directive injected for debugger (no extra arg)" {
  create_compile_context_fixtures
  set_caveman_config "full" false false
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 debugger .vbw-planning/phases
  [ "$status" -eq 0 ]
  grep -q "Caveman Language" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-debugger.md"
}

@test "compile-context: caveman directive injected for architect (no extra arg)" {
  create_compile_context_fixtures
  set_caveman_config "full" false false
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 architect .vbw-planning/phases
  [ "$status" -eq 0 ]
  grep -q "Caveman Language" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-architect.md"
}

# ---------------------------------------------------------------------------
# compaction-instructions.sh — caveman preservation in PRIORITIES
# ---------------------------------------------------------------------------

@test "compaction-instructions: caveman in PRIORITIES when style=full" {
  set_caveman_config "full" false false
  export VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning"
  export VBW_AGENT_ROLE="dev"
  export VBW_COMPACTION_COUNT="1"
  run bash -c 'echo "{}" | bash "$1"' _ "$SCRIPTS_DIR/compaction-instructions.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CAVEMAN MODE"
}

@test "compaction-instructions: no caveman when style=none" {
  export VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning"
  export VBW_AGENT_ROLE="dev"
  export VBW_COMPACTION_COUNT="1"
  run bash -c 'echo "{}" | bash "$1"' _ "$SCRIPTS_DIR/compaction-instructions.sh"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "CAVEMAN MODE"
}

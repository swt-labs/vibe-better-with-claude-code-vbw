#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  # Create a minimal phase directory structure
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  # Create a minimal ROADMAP.md
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
# Test Roadmap
## Phase 2: Test Phase
**Goal:** Test goal
**Success:** Tests pass
**Reqs:** REQ-01
EOF
  # Create a minimal plan
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md" <<'EOF'
---
phase: 2
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

@test "cache-context.sh produces consistent hash for same inputs" {
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)

  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" = "$HASH2" ]
}

@test "cache-context.sh reports miss when no cache exists" {
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^miss "
}

@test "cache-context.sh reports hit when cache exists" {
  cd "$TEST_TEMP_DIR"
  # Get the hash from within the test dir (consistent git context)
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev ".vbw-planning/config.json" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  HASH=$(echo "$output" | cut -d' ' -f2)

  # Create cache entry with matching hash
  mkdir -p ".vbw-planning/.cache/context"
  echo "# cached" > ".vbw-planning/.cache/context/${HASH}.md"

  # Same call should now hit
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev ".vbw-planning/config.json" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^hit "
}

@test "cache-context.sh produces different hash when plan changes" {
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  HASH1=$(echo "$output" | cut -d' ' -f2)

  # Modify the plan
  echo "# Modified" >> "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md"

  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" != "$HASH2" ]
}

@test "compile-context.sh always uses cache (v3_context_cache graduated)" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 dev ".vbw-planning/phases" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  # Cache dir should always be created now that flag is graduated
  [ -d "$TEST_TEMP_DIR/.vbw-planning/.cache" ]
}

@test "compile-context.sh uses cache when v3_context_cache=true" {
  jq '.v3_context_cache = true' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.tmp" && mv "$TEST_TEMP_DIR/.vbw-planning/config.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  cd "$TEST_TEMP_DIR"
  # First run: cache miss, should write cache
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 dev ".vbw-planning/phases" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  # Cache dir should now exist with at least one file
  [ -d "$TEST_TEMP_DIR/.vbw-planning/.cache/context" ]
  CACHE_COUNT=$(ls "$TEST_TEMP_DIR/.vbw-planning/.cache/context/" | wc -l | tr -d ' ')
  [ "$CACHE_COUNT" -ge 1 ]
}

@test "compile-context.sh includes RESEARCH.md when present" {
  cd "$TEST_TEMP_DIR"
  echo -e "## Findings\n- Test finding" > ".vbw-planning/phases/02-test-phase/02-RESEARCH.md"
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 lead ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Research Findings" ".vbw-planning/phases/02-test-phase/.context-lead.md"
  grep -q "Test finding" ".vbw-planning/phases/02-test-phase/.context-lead.md"
}

@test "compile-context.sh works without RESEARCH.md" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 lead ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  ! grep -q "Research Findings" ".vbw-planning/phases/02-test-phase/.context-lead.md"
}

@test "compile-context.sh cache hit preserves metadata" {
  jq '.v3_context_cache = true' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.tmp" && mv "$TEST_TEMP_DIR/.vbw-planning/config.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  cd "$TEST_TEMP_DIR"
  # First run: cache miss, compiles fresh
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 lead ".vbw-planning/phases" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  grep -q "Test goal" ".vbw-planning/phases/02-test-phase/.context-lead.md"

  # Second run: cache hit, served from cache
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 lead ".vbw-planning/phases" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  # Cached output must still contain actual ROADMAP metadata, not "Not available"
  grep -q "Test goal" ".vbw-planning/phases/02-test-phase/.context-lead.md"
}


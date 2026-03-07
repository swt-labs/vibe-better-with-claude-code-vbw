#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# =============================================================================
# Bug #2: No destructive git commands in session-start.sh
# =============================================================================

@test "session-start.sh contains no destructive git commands" {
  # Destructive patterns: git reset --hard, git checkout ., git restore ., git clean -f/-fd
  run grep -E 'git (reset --hard|checkout \.|restore \.|clean -f)' "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 1 ]  # grep returns 1 = no matches found
}

@test "session-start.sh marketplace sync uses safe merge" {
  # Must use --ff-only (safe merge) and git diff --quiet (dirty-check guard)
  grep -q '\-\-ff-only' "$SCRIPTS_DIR/session-start.sh"
  grep -q 'git diff --quiet' "$SCRIPTS_DIR/session-start.sh"
}

# =============================================================================
# Bug #3: Atomic writes and locking in update-state.sh
# =============================================================================

@test "update-state.sh uses mkdir-based locking" {
  grep -q 'mkdir' "$SCRIPTS_DIR/update-state.sh"
  grep -q 'LOCK_DIR' "$SCRIPTS_DIR/update-state.sh"
}

@test "update-state.sh uses atomic write pattern (mktemp + mv)" {
  grep -q 'mktemp' "$SCRIPTS_DIR/update-state.sh"
  grep -q 'mv "$TMP"' "$SCRIPTS_DIR/update-state.sh"
}

@test "update-state.sh replace operation is atomic" {
  echo "old_value" > "$TEST_TEMP_DIR/state.txt"
  run bash "$SCRIPTS_DIR/update-state.sh" "$TEST_TEMP_DIR/state.txt" replace "old_value" "new_value"
  [ "$status" -eq 0 ]
  grep -q "new_value" "$TEST_TEMP_DIR/state.txt"
  # Lock directory should be cleaned up after operation
  [ ! -d "$TEST_TEMP_DIR/state.txt.lock" ]
}

# =============================================================================
# Bug #8: compile-context.sh handles all 6 roles
# =============================================================================

# Helper: set up minimal .vbw-planning structure for compile-context.sh
setup_compile_context() {
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  create_test_config

  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'ROADMAP'
## Phases

## Phase 1: Test Phase
**Goal:** Test the context compiler
**Reqs:** REQ-01
**Success:** All roles produce context files

---

## Phase 2: Future Phase
**Goal:** Placeholder for parser termination
**Reqs:** REQ-02
**Success:** Parser correctly terminates section
ROADMAP

  cat > "$TEST_TEMP_DIR/.vbw-planning/REQUIREMENTS.md" <<'REQS'
## Requirements
- [REQ-01] Sample requirement for testing
REQS

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'STATE'
## Status
Phase: 1 of 1 (Test Phase)
Status: executing
Progress: 50%

## Decisions
- Decided to test all roles
STATE
}

@test "compile-context.sh supports all 6 roles" {
  setup_compile_context
  cd "$TEST_TEMP_DIR"
  for role in lead dev qa scout debugger architect; do
    run bash "$SCRIPTS_DIR/compile-context.sh" "01" "$role" ".vbw-planning/phases"
    [ "$status" -eq 0 ]
    [ -f ".vbw-planning/phases/01-test/.context-${role}.md" ]
    # File must be non-empty
    [ -s ".vbw-planning/phases/01-test/.context-${role}.md" ]
  done
}

@test "compile-context.sh scout context includes requirements" {
  setup_compile_context
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "scout" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Research Context" ".vbw-planning/phases/01-test/.context-scout.md"
  grep -q "Requirements" ".vbw-planning/phases/01-test/.context-scout.md"
}

@test "compile-context.sh debugger context includes MuninnDB hint" {
  setup_compile_context
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Debug Context" ".vbw-planning/phases/01-test/.context-debugger.md"
  grep -q "Cross-Phase Memory" ".vbw-planning/phases/01-test/.context-debugger.md"
}

@test "compile-context.sh architect context includes full requirements" {
  setup_compile_context
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "architect" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Architecture Context" ".vbw-planning/phases/01-test/.context-architect.md"
  grep -q "Full Requirements" ".vbw-planning/phases/01-test/.context-architect.md"
}

@test "compile-context.sh extracts goal from ROADMAP" {
  setup_compile_context
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "lead" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  # Goal should be actual text from ROADMAP, not "Not available"
  grep -q "Test the context compiler" ".vbw-planning/phases/01-test/.context-lead.md"
  # Success criteria should also be extracted
  grep -q "All roles produce context files" ".vbw-planning/phases/01-test/.context-lead.md"
}

@test "compile-context.sh scout context includes conventions" {
  setup_compile_context
  cd "$TEST_TEMP_DIR"
  cat > "$TEST_TEMP_DIR/.vbw-planning/conventions.json" <<'CONV'
{
  "conventions": [
    {"tag": "style", "rule": "Commits follow type(scope): desc format"}
  ]
}
CONV
  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "scout" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Conventions" ".vbw-planning/phases/01-test/.context-scout.md"
  grep -q "Commits follow" ".vbw-planning/phases/01-test/.context-scout.md"
}

@test "compile-context.sh debugger context includes success criteria" {
  setup_compile_context
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Success Criteria" ".vbw-planning/phases/01-test/.context-debugger.md"
  grep -q "All roles produce context files" ".vbw-planning/phases/01-test/.context-debugger.md"
}

# =============================================================================
# Bug #10: compaction-instructions.sh role-specific priorities
# =============================================================================

@test "compaction-instructions.sh outputs role-specific priorities" {
  # Dev agent should get commit/file priorities
  run bash -c 'echo "{\"agent_name\":\"vbw-dev-01\",\"matcher\":\"auto\"}" | bash "'"$SCRIPTS_DIR"'/compaction-instructions.sh"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
  echo "$output" | grep -q "commit hashes"
  echo "$output" | grep -q "file paths modified"

  # Scout agent should get research priorities
  run bash -c 'echo "{\"agent_name\":\"vbw-scout-01\",\"matcher\":\"auto\"}" | bash "'"$SCRIPTS_DIR"'/compaction-instructions.sh"'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "research findings"
}

@test "compaction-instructions.sh writes compaction marker" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning
  run bash -c 'echo "{\"agent_name\":\"vbw-dev-01\",\"matcher\":\"auto\"}" | bash "'"$SCRIPTS_DIR"'/compaction-instructions.sh"'
  [ "$status" -eq 0 ]
  [ -f ".vbw-planning/.compaction-marker" ]
}

# =============================================================================
# Bug #11: Blocked agent notification in execute-protocol.md
# =============================================================================

@test "execute-protocol.md contains blocked agent notification" {
  grep -q "Blocked agent notification" "$PROJECT_ROOT/references/execute-protocol.md"
}

# =============================================================================
# Bug #14: task-verify.sh uses keyword matching, not header matching
# =============================================================================

@test "task-verify.sh uses keyword matching (not header matching)" {
  # Keyword-based matching present
  grep -qi "keyword" "$SCRIPTS_DIR/task-verify.sh"
  # No header-dependent patterns (### Task or ## Task)
  run grep -E '(### Task|## Task)' "$SCRIPTS_DIR/task-verify.sh"
  [ "$status" -eq 1 ]  # grep returns 1 = no matches
}

# =============================================================================
# Bug #16: route-monorepo.sh detects monorepo structures
# =============================================================================

# Helper: set up monorepo test structure
setup_monorepo() {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/phases/01-test
  create_test_config
  # Enable monorepo routing
  local TMP
  TMP=$(mktemp)
  jq '.monorepo_routing = true' .vbw-planning/config.json > "$TMP" && mv "$TMP" .vbw-planning/config.json
}

@test "route-monorepo.sh detects package roots" {
  setup_monorepo
  # Create monorepo structure
  mkdir -p packages/core apps/web
  echo '{}' > packages/core/package.json
  echo '{}' > apps/web/package.json
  echo '{}' > package.json

  # Create PLAN.md referencing packages/core (- **Files:** must start at column 0 for grep)
  cat > .vbw-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
phase: 1
plan: 1
title: "Test Plan"
---
### Task 1
- **Files:** `packages/core/src/index.ts`
PLAN

  run bash "$SCRIPTS_DIR/route-monorepo.sh" ".vbw-planning/phases/01-test"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. | length > 0' >/dev/null
  echo "$output" | grep -q "packages/core"
}

@test "route-monorepo.sh returns empty for non-monorepo" {
  setup_monorepo
  # Only root package.json, no sub-packages
  echo '{}' > package.json

  cat > .vbw-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
phase: 1
plan: 1
title: "Test Plan"
---
### Task 1
- **Files:** `src/index.ts`
PLAN

  run bash "$SCRIPTS_DIR/route-monorepo.sh" ".vbw-planning/phases/01-test"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "route-monorepo.sh detects multiple package markers" {
  setup_monorepo
  # Create mixed-language monorepo
  mkdir -p packages/api packages/worker
  echo 'module example.com/api' > packages/api/go.mod
  echo '[package]' > packages/worker/Cargo.toml
  echo '{}' > package.json

  # PLAN.md referencing both packages (- **Files:** must start at column 0)
  cat > .vbw-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
phase: 1
plan: 1
title: "Test Plan"
---
### Task 1
- **Files:** `packages/api/main.go`, `packages/worker/src/lib.rs`
PLAN

  run bash "$SCRIPTS_DIR/route-monorepo.sh" ".vbw-planning/phases/01-test"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. | length == 2' >/dev/null
  echo "$output" | grep -q "packages/api"
  echo "$output" | grep -q "packages/worker"
}

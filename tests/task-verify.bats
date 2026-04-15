#!/usr/bin/env bats

# Tests for issue #94: TaskCompleted hook false-positive blocks Dev agents
# after work is done, creating infinite loop.
#
# Covers:
# - Keyword matcher correctly matches team-mode task subjects against
#   conventional commit messages
# - Repetition circuit breaker allows completion after repeated blocks
# - Existing behavior preserved (no-commit block, analysis-only bypass,
#   role-only bypass)

load test_helper

setup() {
  setup_temp_dir
  create_test_config

  # Create a minimal git repo inside TEST_TEMP_DIR
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  # Seed commit so git log works
  echo "init" > init.txt
  git add init.txt
  git commit -q -m "chore: initial commit"
}

teardown() {
  teardown_temp_dir
}

# Helper: add a recent commit with given message
add_commit() {
  local msg="$1"
  echo "$RANDOM" >> "$TEST_TEMP_DIR/dummy.txt"
  git add dummy.txt
  git commit -q -m "$msg"
}

# Helper: run task-verify.sh with a given task subject via stdin JSON
run_task_verify() {
  local subject="$1"
  echo "{\"task_subject\": \"$subject\"}" | bash "$SCRIPTS_DIR/task-verify.sh"
}

# =============================================================================
# Bug #94: Team-mode task subjects don't match conventional commit messages
# =============================================================================

@test "team-mode subject 'Execute 07-01: Create StockLotDetailView' matches commit 'feat(07-01): create StockLotDetailView'" {
  cd "$TEST_TEMP_DIR"
  add_commit "feat(07-01): create StockLotDetailView"

  run run_task_verify "Execute 07-01: Create StockLotDetailView"
  [ "$status" -eq 0 ]
}

@test "team-mode subject 'Execute 07-02: Wire navigation to StockLotDetailView' matches commit 'feat(07-02): wire NavigationLink to StockLotDetailView'" {
  cd "$TEST_TEMP_DIR"
  add_commit "feat(07-02): wire NavigationLink to StockLotDetailView"

  run run_task_verify "Execute 07-02: Wire navigation to StockLotDetailView"
  [ "$status" -eq 0 ]
}

@test "team-mode subject with 'Execute' prefix matches commit (prefix filtered as stop word)" {
  cd "$TEST_TEMP_DIR"
  # Commit message has domain keywords but NOT "execute" or the plan ID format
  add_commit "refactor(03-01): update authentication middleware"

  run run_task_verify "Execute 03-01: Update authentication middleware"
  [ "$status" -eq 0 ]
}

@test "short task subject 'Execute 07-01: Fix bug' matches commit with domain keywords" {
  cd "$TEST_TEMP_DIR"
  add_commit "fix(07-01): resolve the bug in auth"

  # "fix" and "bug" are ≤3 chars → filtered. "execute" is a stop word.
  # Without domain keywords, fail-open (exit 0) should apply.
  run run_task_verify "Execute 07-01: Fix bug"
  [ "$status" -eq 0 ]
}

# =============================================================================
# Bug #94: Repetition circuit breaker — prevents infinite hook loop
# =============================================================================

@test "first block for a subject exits 2 (normal block)" {
  cd "$TEST_TEMP_DIR"
  # Commit that does NOT match the subject at all
  add_commit "docs: update README"
  rm -f "$TEST_TEMP_DIR/.vbw-planning/.task-verify-seen"

  run run_task_verify "Implement quantum flux capacitor"
  [ "$status" -eq 2 ]
}

@test "second block for same subject exits 0 (circuit breaker fires)" {
  cd "$TEST_TEMP_DIR"
  # Commit that does NOT match the subject
  add_commit "docs: update README"
  rm -f "$TEST_TEMP_DIR/.vbw-planning/.task-verify-seen"

  # First attempt — blocks
  run run_task_verify "Implement quantum flux capacitor"
  [ "$status" -eq 2 ]

  # Second attempt — circuit breaker should allow
  run run_task_verify "Implement quantum flux capacitor"
  [ "$status" -eq 0 ]
}

@test "circuit breaker is per-subject — different subject still blocks" {
  cd "$TEST_TEMP_DIR"
  add_commit "docs: update README"
  rm -f "$TEST_TEMP_DIR/.vbw-planning/.task-verify-seen"

  # Block first subject
  run run_task_verify "Implement quantum flux capacitor"
  [ "$status" -eq 2 ]

  # Different subject should still block (not benefit from first subject's counter)
  run run_task_verify "Build time machine"
  [ "$status" -eq 2 ]
}

# =============================================================================
# Existing behavior preserved: legitimate blocks still work
# =============================================================================

@test "no recent commits blocks with exit 2" {
  cd "$TEST_TEMP_DIR"
  rm -f "$TEST_TEMP_DIR/.vbw-planning/.task-verify-seen"
  # The initial commit is recent enough, but doesn't match
  run run_task_verify "Implement something entirely different"
  [ "$status" -eq 2 ]
}

@test "matching commit allows with exit 0" {
  cd "$TEST_TEMP_DIR"
  add_commit "feat(auth): implement login flow with OAuth2"

  run run_task_verify "Implement login flow"
  [ "$status" -eq 0 ]
}

# =============================================================================
# Existing bypasses still work
# =============================================================================

@test "analysis-only tag bypasses check" {
  cd "$TEST_TEMP_DIR"
  run run_task_verify "[analysis-only] Investigate race condition"
  [ "$status" -eq 0 ]
}

@test "no-commit tag bypasses check" {
  cd "$TEST_TEMP_DIR"
  run run_task_verify "Link Sentry issues to JIRA ticket CVX-5919 [no-commit]"
  [ "$status" -eq 0 ]
}

@test "no-commit tag bypasses even with no recent commits" {
  cd "$TEST_TEMP_DIR"
  run run_task_verify "Create feature branch fix/CVX-5919 [no-commit]"
  [ "$status" -eq 0 ]
}

@test "no-commit tag is case-insensitive" {
  cd "$TEST_TEMP_DIR"
  run run_task_verify "Assess sortTableData [No-Commit]"
  [ "$status" -eq 0 ]
}

@test "no-commit tag at start of subject bypasses check" {
  cd "$TEST_TEMP_DIR"
  run run_task_verify "[no-commit] Research codebase patterns"
  [ "$status" -eq 0 ]
}

@test "role-only subject bypasses check" {
  cd "$TEST_TEMP_DIR"
  run run_task_verify "dev-01"
  [ "$status" -eq 0 ]
}

@test "role-only subject with vbw prefix bypasses check" {
  cd "$TEST_TEMP_DIR"
  run run_task_verify "vbw-dev"
  [ "$status" -eq 0 ]
}

@test "empty task subject allows (fail-open)" {
  cd "$TEST_TEMP_DIR"
  add_commit "some commit"
  run bash -c 'echo "{}" | bash "'"$SCRIPTS_DIR"'/task-verify.sh"'
  [ "$status" -eq 0 ]
}

@test "no .vbw-planning dir allows (non-VBW context)" {
  cd "$TEST_TEMP_DIR"
  rm -rf .vbw-planning
  run run_task_verify "anything"
  [ "$status" -eq 0 ]
}

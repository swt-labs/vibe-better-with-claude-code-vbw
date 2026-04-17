#!/usr/bin/env bats

# Tests for TaskCompleted commit verification behavior.
#
# Covers:
# - Execute-protocol tasks still verify against recent commits
# - Manual/non-execute tasks are never blocked by commit heuristics
# - Execute-task mismatches become advisory instead of blocking
# - Existing analysis-only and role-only bypasses still work

load test_helper

setup() {
  setup_temp_dir
  create_test_config

  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > init.txt
  git add init.txt
  git commit -q -m "chore: initial commit"
}

teardown() {
  teardown_temp_dir
}

add_commit() {
  local msg="$1"
  echo "$RANDOM" >> "$TEST_TEMP_DIR/dummy.txt"
  git add dummy.txt
  git commit -q -m "$msg"
}

add_old_commit() {
  local msg="$1"
  echo "$RANDOM" >> "$TEST_TEMP_DIR/dummy.txt"
  git add dummy.txt
  GIT_AUTHOR_DATE="2020-01-01T00:00:00" GIT_COMMITTER_DATE="2020-01-01T00:00:00" \
    git commit -q -m "$msg"
}

run_task_verify() {
  local subject="$1"
  echo "{\"task_subject\": \"$subject\"}" | bash "$SCRIPTS_DIR/task-verify.sh"
}

run_task_verify_json() {
  local json="$1"
  printf '%s\n' "$json" | bash "$SCRIPTS_DIR/task-verify.sh"
}

assert_task_verify_advisory() {
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "TaskCompleted"' >/dev/null
  echo "$output" | jq -r '.hookSpecificOutput.additionalContext'
}

# =============================================================================
# Execute tasks still get checked when matching evidence exists
# =============================================================================

@test "team-mode subject 'Execute 07-01: Create StockLotDetailView' matches commit 'feat(07-01): create StockLotDetailView'" {
  cd "$TEST_TEMP_DIR"
  add_commit "feat(07-01): create StockLotDetailView"

  run run_task_verify "Execute 07-01: Create StockLotDetailView"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "team-mode subject 'Execute 07-02: Wire navigation to StockLotDetailView' matches commit 'feat(07-02): wire NavigationLink to StockLotDetailView'" {
  cd "$TEST_TEMP_DIR"
  add_commit "feat(07-02): wire NavigationLink to StockLotDetailView"

  run run_task_verify "Execute 07-02: Wire navigation to StockLotDetailView"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "team-mode subject with 'Execute' prefix matches commit (prefix filtered as stop word)" {
  cd "$TEST_TEMP_DIR"
  add_commit "refactor(03-01): update authentication middleware"

  run run_task_verify "Execute 03-01: Update authentication middleware"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "short execute task subject with no usable keywords still allows" {
  cd "$TEST_TEMP_DIR"
  add_commit "fix(07-01): resolve the bug in auth"

  run run_task_verify "Execute 07-01: Fix bug"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================================
# Issue #422: manual and non-commit tasks must not be blocked
# =============================================================================

@test "manual non-execute task with unrelated recent commit allows on first attempt" {
  cd "$TEST_TEMP_DIR"
  add_commit "docs: update README"

  run run_task_verify "Link Sentry issues to JIRA ticket CVX-5919"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "manual non-execute task with no recent commits allows on first attempt" {
  cd "$TEST_TEMP_DIR"
  rm -rf .git
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > init.txt
  git add init.txt
  GIT_AUTHOR_DATE="2020-01-01T00:00:00" GIT_COMMITTER_DATE="2020-01-01T00:00:00" \
    git commit -q -m "chore: ancient seed"

  run run_task_verify "Create feature branch from iw3_11_patches"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "execute task with no recent commits emits advisory and allows completion" {
  cd "$TEST_TEMP_DIR"
  rm -rf .git
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > init.txt
  git add init.txt
  GIT_AUTHOR_DATE="2020-01-01T00:00:00" GIT_COMMITTER_DATE="2020-01-01T00:00:00" \
    git commit -q -m "feat(07-01): create StockLotDetailView"

  run run_task_verify "Execute 07-01: Create StockLotDetailView"
  [ "$status" -eq 0 ]
  assert_task_verify_advisory | grep -q "recent commit in the configured window"
}

@test "execute task with mismatched recent commit emits advisory and allows completion" {
  cd "$TEST_TEMP_DIR"
  add_commit "fix(auth): guard null undefined dereferences in login-adjacent code"

  run run_task_verify "Execute 07-01: Fix validation removeIn null DOM access"
  [ "$status" -eq 0 ]
  assert_task_verify_advisory | grep -q "recent matching commit"
}

@test "execute task with matching commit allows with no advisory output" {
  cd "$TEST_TEMP_DIR"
  add_commit "feat(07-01): implement login flow with OAuth2"

  run run_task_verify "Execute 07-01: Implement login flow"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================================
# Existing bypasses still work
# =============================================================================

@test "analysis-only tag bypasses check" {
  cd "$TEST_TEMP_DIR"
  run run_task_verify "[analysis-only] Investigate race condition"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "analysis-only tag in task_description fallback bypasses check" {
  cd "$TEST_TEMP_DIR"
  run run_task_verify_json '{"task_description": "Investigate memory leak [analysis-only]"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "role-only subject bypasses check" {
  cd "$TEST_TEMP_DIR"
  run run_task_verify "dev-01"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "role-only subject with vbw prefix bypasses check" {
  cd "$TEST_TEMP_DIR"
  run run_task_verify "vbw-dev"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "empty task subject allows (fail-open)" {
  cd "$TEST_TEMP_DIR"
  add_commit "some commit"
  run run_task_verify_json '{}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no .vbw-planning dir allows (non-VBW context)" {
  cd "$TEST_TEMP_DIR"
  rm -rf .vbw-planning
  run run_task_verify "anything"
  [ "$status" -eq 0 ]
}

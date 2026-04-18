#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning"
  mkdir -p "$PLANNING_DIR"

  # Initialize a git repo so compile script can run git show
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "initial" > file.txt
  git add file.txt
  git commit -q -m "initial commit"
}

teardown() {
  teardown_temp_dir
}

# Helper: create a marker file from the current HEAD
create_marker() {
  bash "$SCRIPTS_DIR/write-fix-marker.sh" "$PLANNING_DIR" "${1:-}"
}

# ── basic context output ─────────────────────────────────

@test "outputs fix_context=available with valid marker" {
  echo "fix" > fix.sh
  git add fix.sh
  git commit -q -m "fix(ui): button crash"
  create_marker

  run bash "$SCRIPTS_DIR/compile-fix-commit-context.sh" "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "fix_context=available" ]]
  [[ "$output" == *"---"* ]]
  [[ "$output" == *"## Fix Commit QA Context"* ]]
  [[ "$output" == *"fix(ui): button crash"* ]]
  [[ "$output" == *"fix.sh"* ]]
}

@test "uat mode uses UAT title" {
  echo "fix" > fix.sh
  git add fix.sh
  git commit -q -m "fix: thing"
  create_marker

  run bash "$SCRIPTS_DIR/compile-fix-commit-context.sh" "$PLANNING_DIR" "uat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Fix Commit UAT Context"* ]]
}

@test "shows custom description when different from commit message" {
  echo "fix" > fix.sh
  git add fix.sh
  git commit -q -m "fix: thing"
  create_marker "Fixed the login crash"

  run bash "$SCRIPTS_DIR/compile-fix-commit-context.sh" "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Fixed the login crash"* ]]
}

# ── empty context cases ──────────────────────────────────

@test "outputs fix_context=empty when no marker exists" {
  run bash "$SCRIPTS_DIR/compile-fix-commit-context.sh" "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "fix_context=empty" ]]
  # Should be only one line
  [ "${#lines[@]}" -eq 1 ]
}

@test "outputs fix_context=empty when planning dir missing" {
  run bash "$SCRIPTS_DIR/compile-fix-commit-context.sh" "/nonexistent/dir"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "fix_context=empty" ]]
}

@test "outputs fix_context=empty for stale marker (>24h)" {
  echo "fix" > fix.sh
  git add fix.sh
  git commit -q -m "fix: old"
  create_marker

  # Backdate the marker by 25 hours
  if [[ "$OSTYPE" == darwin* ]]; then
    touch -t "$(date -v-25H '+%Y%m%d%H%M.%S')" "$PLANNING_DIR/.last-fix-commit"
  else
    touch -d "25 hours ago" "$PLANNING_DIR/.last-fix-commit"
  fi

  run bash "$SCRIPTS_DIR/compile-fix-commit-context.sh" "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "fix_context=empty" ]]
}

@test "outputs fix_context=empty when marker has no commit field" {
  echo "message=something" > "$PLANNING_DIR/.last-fix-commit"

  run bash "$SCRIPTS_DIR/compile-fix-commit-context.sh" "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "fix_context=empty" ]]
}

@test "outputs fix_context=empty when marker has future timestamp" {
  echo "fix" > fix.sh
  git add fix.sh
  git commit -q -m "fix: future"
  create_marker

  # Set marker timestamp 2 hours in the future (clock skew scenario)
  if [[ "$OSTYPE" == darwin* ]]; then
    touch -t "$(date -v+2H '+%Y%m%d%H%M.%S')" "$PLANNING_DIR/.last-fix-commit"
  else
    touch -d "2 hours" "$PLANNING_DIR/.last-fix-commit"
  fi

  run bash "$SCRIPTS_DIR/compile-fix-commit-context.sh" "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "fix_context=empty" ]]
}

# ── integration: write then compile ──────────────────────

@test "write-then-compile round trip produces valid context" {
  echo "fix" > button.sh
  git add button.sh
  git commit -q -m "fix(button): handle null ref"
  create_marker "Fixed null reference in button handler"

  run bash "$SCRIPTS_DIR/compile-fix-commit-context.sh" "$PLANNING_DIR" "qa"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "fix_context=available" ]]
  [[ "$output" == *"handle null ref"* ]]
  [[ "$output" == *"Fixed null reference in button handler"* ]]
  [[ "$output" == *"button.sh"* ]]
}

#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning"
  mkdir -p "$PLANNING_DIR"

  # Initialize a git repo so write-fix-marker.sh can read commit info
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

# ── basic marker creation ────────────────────────────────

@test "writes marker file with correct fields" {
  echo "fix content" > fix.sh
  git add fix.sh
  git commit -q -m "fix(button): handle null ref"

  run bash "$SCRIPTS_DIR/write-fix-marker.sh" "$PLANNING_DIR"
  [ "$status" -eq 0 ]

  [ -f "$PLANNING_DIR/.last-fix-commit" ]
  grep -q "^commit=" "$PLANNING_DIR/.last-fix-commit"
  grep -q "^message=fix(button): handle null ref" "$PLANNING_DIR/.last-fix-commit"
  grep -q "^timestamp=" "$PLANNING_DIR/.last-fix-commit"
  grep -q "^description=fix(button): handle null ref" "$PLANNING_DIR/.last-fix-commit"
  grep -q "^files=fix.sh" "$PLANNING_DIR/.last-fix-commit"
}

@test "uses custom description when provided" {
  echo "fix" > fix2.sh
  git add fix2.sh
  git commit -q -m "fix: quick patch"

  run bash "$SCRIPTS_DIR/write-fix-marker.sh" "$PLANNING_DIR" "Fixed the login crash"
  [ "$status" -eq 0 ]

  grep -q "^description=Fixed the login crash" "$PLANNING_DIR/.last-fix-commit"
  grep -q "^message=fix: quick patch" "$PLANNING_DIR/.last-fix-commit"
}

@test "overwrites existing marker" {
  echo "first" > a.txt
  git add a.txt
  git commit -q -m "first fix"
  bash "$SCRIPTS_DIR/write-fix-marker.sh" "$PLANNING_DIR"

  echo "second" > b.txt
  git add b.txt
  git commit -q -m "second fix"
  run bash "$SCRIPTS_DIR/write-fix-marker.sh" "$PLANNING_DIR"
  [ "$status" -eq 0 ]

  grep -q "^message=second fix" "$PLANNING_DIR/.last-fix-commit"
  # first fix message should be gone
  ! grep -q "^message=first fix" "$PLANNING_DIR/.last-fix-commit"
}

# ── graceful degradation ─────────────────────────────────

@test "exits 0 when planning dir does not exist" {
  run bash "$SCRIPTS_DIR/write-fix-marker.sh" "/nonexistent/path"
  [ "$status" -eq 0 ]
}

@test "exits 0 with default planning dir when called with no args" {
  # No .vbw-planning in cwd, so it exits gracefully
  local empty_cwd="$TEST_TEMP_DIR/no-default-planning"
  mkdir -p "$empty_cwd"
  cd "$empty_cwd"
  run bash "$SCRIPTS_DIR/write-fix-marker.sh"
  [ "$status" -eq 0 ]
}

@test "records multiple changed files" {
  echo "a" > alpha.txt
  echo "b" > beta.txt
  git add alpha.txt beta.txt
  git commit -q -m "multi-file fix"

  run bash "$SCRIPTS_DIR/write-fix-marker.sh" "$PLANNING_DIR"
  [ "$status" -eq 0 ]

  grep -q "alpha.txt" "$PLANNING_DIR/.last-fix-commit"
  grep -q "beta.txt" "$PLANNING_DIR/.last-fix-commit"
}

@test "records files for root commit" {
  # Create a fresh repo with only one commit (root commit)
  local root_dir="$TEST_TEMP_DIR/root-repo"
  mkdir -p "$root_dir"
  cd "$root_dir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  local planning="$root_dir/.vbw-planning"
  mkdir -p "$planning"
  echo "first" > first.txt
  git add first.txt
  git commit -q -m "initial fix"

  run bash "$SCRIPTS_DIR/write-fix-marker.sh" "$planning"
  [ "$status" -eq 0 ]
  grep -q "first.txt" "$planning/.last-fix-commit"
}

# ── fix.md integration contract ──────────────────────────

@test "fix.md calls write-fix-marker.sh before suggest-next.sh in both success paths" {
  local fix_md="$PROJECT_ROOT/commands/fix.md"
  # Both success paths must call write-fix-marker.sh before suggest-next.sh
  # Extract line numbers for each call pattern
  local marker_lines suggest_lines
  marker_lines=$(grep -n 'write-fix-marker\.sh' "$fix_md" | cut -d: -f1)
  suggest_lines=$(grep -n 'suggest-next\.sh' "$fix_md" | cut -d: -f1)

  # Must have at least 2 marker calls (one per success path)
  local marker_count
  marker_count=$(echo "$marker_lines" | wc -l | tr -d ' ')
  [ "$marker_count" -ge 2 ]

  # Each marker call must precede a suggest-next call
  for m_line in $marker_lines; do
    local found_after=false
    for s_line in $suggest_lines; do
      if [ "$s_line" -gt "$m_line" ]; then
        found_after=true
        break
      fi
    done
    [ "$found_after" = true ]
  done
}

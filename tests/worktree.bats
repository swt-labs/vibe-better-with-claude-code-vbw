#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# ---------------------------------------------------------------------------
# worktree-create.sh tests
# ---------------------------------------------------------------------------

@test "worktree-create: exits 0 with no arguments" {
  run bash "$SCRIPTS_DIR/worktree-create.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "worktree-create: idempotent when worktree dir already exists" {
  mkdir -p "$TEST_TEMP_DIR/.vbw-worktrees/01-01"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-create.sh" 01 01
  [ "$status" -eq 0 ]
  [[ "$output" == *".vbw-worktrees/01-01" ]]
}

@test "worktree-create: fail-open when not a git repo" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-create.sh" 01 01
  [ "$status" -eq 0 ]
}

@test "worktree-create: falls back to existing branch when -b path fails" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.name "VBW Test"
  git config user.email "vbw-test@example.com"
  echo "seed" > README.md
  git add README.md
  git commit -q -m "chore(init): seed"

  # Pre-create the target branch so `git worktree add -b` fails and fallback path is used.
  git branch "vbw/02-03"

  run bash "$SCRIPTS_DIR/worktree-create.sh" 02 03
  [ "$status" -eq 0 ]
  [[ "$output" == *".vbw-worktrees/02-03" ]]
  [ -d ".vbw-worktrees/02-03" ]

  run git -C ".vbw-worktrees/02-03" rev-parse --abbrev-ref HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "vbw/02-03" ]
}

# ---------------------------------------------------------------------------
# worktree-merge.sh tests
# ---------------------------------------------------------------------------

@test "worktree-merge: exits 0 with no arguments" {
  run bash "$SCRIPTS_DIR/worktree-merge.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "worktree-merge: outputs conflict when branch does not exist" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-merge.sh" 01 01
  [ "$status" -eq 0 ]
  [ "$output" = "conflict" ]
}

@test "worktree-merge: outputs conflict when not in a git repo" {
  local subdir="$TEST_TEMP_DIR/sub"
  mkdir -p "$subdir"
  cd "$subdir"
  run bash "$SCRIPTS_DIR/worktree-merge.sh" 01 01
  [ "$status" -eq 0 ]
  [ "$output" = "conflict" ]
}

# ---------------------------------------------------------------------------
# worktree-cleanup.sh tests
# ---------------------------------------------------------------------------

@test "worktree-cleanup: exits 0 with no arguments" {
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh"
  [ "$status" -eq 0 ]
}

@test "worktree-cleanup: exits 0 when worktree does not exist" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
}

@test "worktree-cleanup: removes residual worktree directory" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-worktrees/01-01/.vbw-planning
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
  [ ! -d ".vbw-worktrees/01-01" ]
}

@test "worktree-cleanup: removes empty parent .vbw-worktrees directory" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-worktrees/01-01/.vbw-planning
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
  [ ! -d ".vbw-worktrees" ]
}

@test "worktree-cleanup: keeps .vbw-worktrees when other worktrees exist" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-worktrees/01-01/.vbw-planning
  mkdir -p .vbw-worktrees/02-01
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
  [ ! -d ".vbw-worktrees/01-01" ]
  [ -d ".vbw-worktrees/02-01" ]
  [ -d ".vbw-worktrees" ]
}

@test "worktree-cleanup: clears agent-worktree JSON matching phase-plan" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/.agent-worktrees
  echo '{}' > .vbw-planning/.agent-worktrees/agent-01-01.json
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
  [ ! -f ".vbw-planning/.agent-worktrees/agent-01-01.json" ]
}

# ---------------------------------------------------------------------------
# worktree-status.sh tests
# ---------------------------------------------------------------------------

@test "worktree-status: exits 0" {
  run bash "$SCRIPTS_DIR/worktree-status.sh"
  [ "$status" -eq 0 ]
}

@test "worktree-status: outputs valid JSON array" {
  run bash "$SCRIPTS_DIR/worktree-status.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. | type == "array"'
}

@test "worktree-status: empty array when no VBW worktrees" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-status.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

# ---------------------------------------------------------------------------
# Integration tests
# ---------------------------------------------------------------------------

@test "worktree-status: filters out non-VBW worktrees in project root" {
  cd "$PROJECT_ROOT"
  run bash "$SCRIPTS_DIR/worktree-status.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.'
}

@test "worktree-agent-map integration: set and get round-trip with worktree path" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-agent-map.sh" set dev-01 "$TEST_TEMP_DIR/fake-path"
  [ "$status" -eq 0 ]
  run bash "$SCRIPTS_DIR/worktree-status.sh"
  [ "$status" -eq 0 ]
}

@test "worktree-create and worktree-agent-map: pipeline exits 0" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-create.sh" 02 03
  [ "$status" -eq 0 ]
  run bash "$SCRIPTS_DIR/worktree-agent-map.sh" set dev-03 "$TEST_TEMP_DIR/fake-path"
  [ "$status" -eq 0 ]
}

@test "worktree-cleanup: agent-map clear integration" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/worktree-agent-map.sh" set dev-01 "$TEST_TEMP_DIR/fake"
  mkdir -p .vbw-planning/.agent-worktrees
  echo '{}' > .vbw-planning/.agent-worktrees/dev-01-01-01.json
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
  [ ! -f ".vbw-planning/.agent-worktrees/dev-01-01-01.json" ]
  run bash "$SCRIPTS_DIR/worktree-agent-map.sh" get dev-01
  [ "$status" -eq 0 ]
}

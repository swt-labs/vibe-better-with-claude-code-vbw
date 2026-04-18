#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase"
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
# Test Roadmap
## Phase 2: Test Phase
**Goal:** Test goal
EOF
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
EOF
}

teardown() {
  teardown_temp_dir
}

setup_unrelated_git_repo() {
  local repo_dir="$1"

  mkdir -p "$repo_dir"
  cd "$repo_dir" || return 1
  git init -q
  git config user.name "VBW Test"
  git config user.email "vbw-tests@example.com"
  echo "initial" > unrelated.txt
  git add unrelated.txt
  git commit -qm "init"
}

@test "delta-files.sh outputs changed files in git repo" {
  cd "$PROJECT_ROOT"
  run bash "$SCRIPTS_DIR/delta-files.sh" "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase"
  [ "$status" -eq 0 ]
  # Should output at least some files (we have uncommitted changes or recent commits)
  # Just verify it doesn't error
}

@test "delta-files.sh handles non-git directory gracefully" {
  cd "$TEST_TEMP_DIR"
  # No SUMMARY.md files, no git — should output nothing and exit 0
  run bash "$SCRIPTS_DIR/delta-files.sh" ".vbw-planning/phases/02-test-phase"
  [ "$status" -eq 0 ]
}

@test "delta-files.sh extracts files from SUMMARY.md when no git" {
  cd "$TEST_TEMP_DIR"
  cat > ".vbw-planning/phases/02-test-phase/02-01-SUMMARY.md" <<'EOF'
---
phase: 2
plan: 1
title: "Test"
status: complete
---
# Summary
## Files Modified
- scripts/test.sh
- config/test.json (new)
## Deviations
EOF
  run bash "$SCRIPTS_DIR/delta-files.sh" ".vbw-planning/phases/02-test-phase"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "scripts/test.sh"
}

@test "delta-files.sh uses the target phase path instead of ambient git repo state" {
  local unrelated_repo="$TEST_TEMP_DIR/unrelated-git"

  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-SUMMARY.md" <<'EOF'
# Summary
## Files Modified
- scripts/test.sh
## Deviations
EOF

  setup_unrelated_git_repo "$unrelated_repo"
  echo "modified" >> unrelated.txt

  run bash "$SCRIPTS_DIR/delta-files.sh" "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase" \
    "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "scripts/test.sh"
  ! echo "$output" | grep -q "unrelated.txt"
}

@test "delta-files.sh uses recent commits for young untagged target repos off-root" {
  local unrelated_repo="$TEST_TEMP_DIR/unrelated-git"

  cd "$TEST_TEMP_DIR" || return 1
  git init -q
  git config user.name "VBW Test"
  git config user.email "vbw-tests@example.com"

  echo 'v1' > sample.txt
  git add .vbw-planning/config.json .vbw-planning/ROADMAP.md \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md sample.txt
  git commit -qm 'init target repo'

  echo 'v2' > sample.txt
  git add sample.txt
  git commit -qm 'update sample v2'

  setup_unrelated_git_repo "$unrelated_repo"
  cd "$unrelated_repo" || return 1

  run bash "$SCRIPTS_DIR/delta-files.sh" "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase" \
    "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "sample.txt"
}

@test "compile-context.sh resolves code slices against explicit target root off-root" {
  local unrelated_repo="$TEST_TEMP_DIR/unrelated-git"

  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-SUMMARY.md" <<'EOF'
# Summary
## Files Modified
- sample.txt
## Deviations
EOF
  echo 'sample body' > "$TEST_TEMP_DIR/sample.txt"

  setup_unrelated_git_repo "$unrelated_repo"

  cd "$unrelated_repo" || return 1
  run env VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" \
    bash "$SCRIPTS_DIR/compile-context.sh" 02 dev \
    "$TEST_TEMP_DIR/.vbw-planning/phases" \
    "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  grep -q '#### `sample.txt`' "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/.context-dev.md"
  grep -q 'sample body' "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/.context-dev.md"
}

@test "compile-context.sh resolves young untagged git delta code slices off-root" {
  local unrelated_repo
  unrelated_repo=$(mktemp -d "${TMPDIR:-/tmp}/vbw-unrelated.XXXXXX")

  cd "$TEST_TEMP_DIR" || return 1
  git init -q
  git config user.name "VBW Test"
  git config user.email "vbw-tests@example.com"

  echo 'v1 body' > sample.txt
  git add .vbw-planning/config.json .vbw-planning/ROADMAP.md \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md sample.txt
  git commit -qm 'init target repo'

  echo 'v2 body' > sample.txt
  git add sample.txt
  git commit -qm 'update sample v2'

  setup_unrelated_git_repo "$unrelated_repo"
  cd "$unrelated_repo" || return 1

  run env VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" \
    bash "$SCRIPTS_DIR/compile-context.sh" 02 dev \
    "$TEST_TEMP_DIR/.vbw-planning/phases" \
    "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  grep -q -- '- `sample.txt`' "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/.context-dev.md"
  grep -q '#### `sample.txt`' "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/.context-dev.md"
  grep -q 'v2 body' "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/.context-dev.md"

  rm -rf "$unrelated_repo"
}

@test "compile-context.sh resolves planning metadata from explicit target paths off-root" {
  local unrelated_repo="$TEST_TEMP_DIR/unrelated-git"

  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
# Test Roadmap
## Phase 2: Test Phase
**Goal:** Test goal
**Reqs:** REQ-01
**Success:** Tests pass
EOF

  cat > "$TEST_TEMP_DIR/.vbw-planning/REQUIREMENTS.md" <<'EOF'
## Requirements
- [REQ-01] Test requirement
EOF

  setup_unrelated_git_repo "$unrelated_repo"
  cd "$unrelated_repo" || return 1

  run bash "$SCRIPTS_DIR/compile-context.sh" 02 lead \
    "$TEST_TEMP_DIR/.vbw-planning/phases" \
    "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  grep -q 'Test goal' "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/.context-lead.md"
  grep -q 'Test requirement' "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/.context-lead.md"
}

@test "compile-context.sh includes delta files when v3_delta_context=true" {
  cd "$TEST_TEMP_DIR"

  # Create a SUMMARY with file list for delta source
  cat > ".vbw-planning/phases/02-test-phase/02-01-SUMMARY.md" <<'EOF'
# Summary
## Files Modified
- scripts/delta-test.sh
EOF

  run bash "$SCRIPTS_DIR/compile-context.sh" 02 dev ".vbw-planning/phases" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  # Should include Active Plan section (always included with delta)
  grep -q "Active Plan" ".vbw-planning/phases/02-test-phase/.context-dev.md"
}


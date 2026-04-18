#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.contracts"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.locks"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.events"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.metrics"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
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

setup_unrelated_git_repo_with_message() {
  local repo_dir="$1"
  local commit_message="$2"

  mkdir -p "$repo_dir"
  cd "$repo_dir" || return 1
  git init -q
  git config user.name "VBW Test"
  git config user.email "vbw-tests@example.com"
  echo "initial" > unrelated.txt
  git add unrelated.txt
  git commit -qm "$commit_message"
}

create_nested_control_plane_workspace() {
  NESTED_REPO_ROOT="$TEST_TEMP_DIR/mono"
  NESTED_WORKSPACE_ROOT="$NESTED_REPO_ROOT/apps/proj"
  NESTED_PLANNING_DIR="$NESTED_WORKSPACE_ROOT/.vbw-planning"
  NESTED_PHASE_DIR="$NESTED_PLANNING_DIR/phases/01-test"
  NESTED_PLAN_PATH="$NESTED_WORKSPACE_ROOT/test-plan.md"

  mkdir -p "$NESTED_PHASE_DIR"
  create_test_config "mono/apps/proj/.vbw-planning"
  cat > "$NESTED_PLAN_PATH" << 'PLAN'
---
phase: 1
plan: 1
title: Test Plan
wave: 1
depends_on: []
skills_used: []
must_haves:
  - "Feature A works"
---

# Plan

### Task 1: Do something
**Files:** `sample.txt`
PLAN
  cat > "$NESTED_PLANNING_DIR/ROADMAP.md" << 'ROAD'
## Phase 1: Test Phase
**Goal:** Test goal
**Reqs:** REQ-01
**Success:** Tests pass
ROAD
}

create_alternate_control_plane_workspace() {
  ALT_WORKSPACE_ROOT="$TEST_TEMP_DIR/alternate-workspace"
  ALT_PLANNING_DIR="$ALT_WORKSPACE_ROOT/.vbw-planning"
  ALT_PHASE_DIR="$ALT_PLANNING_DIR/phases/01-alt"
  ALT_PLAN_PATH="$ALT_WORKSPACE_ROOT/alt-plan.md"

  mkdir -p "$ALT_PHASE_DIR"
  create_test_config "alternate-workspace/.vbw-planning"
  cat > "$ALT_PLAN_PATH" << 'PLAN'
---
phase: 1
plan: 1
title: Alternate Plan
wave: 1
depends_on: []
skills_used: []
must_haves:
  - "Alternate feature works"
---

# Alternate Plan

### Task 1: Alternate task
**Files:** `alt.txt`
PLAN
  cat > "$ALT_PLANNING_DIR/ROADMAP.md" << 'ROAD'
## Phase 1: Alternate Phase
**Goal:** Goal from B
**Reqs:** REQ-99
**Success:** Alternate tests pass
ROAD
}

create_test_plan() {
  cat > "$TEST_TEMP_DIR/test-plan.md" << 'PLAN'
---
phase: 1
plan: 1
title: Test Plan
wave: 1
depends_on: []
skills_used: []
must_haves:
  - "Feature A works"
---

# Plan

### Task 1: Do something
**Files:** `src/a.js`

### Task 2: Do another thing
**Files:** `src/b.js`
PLAN
}

create_roadmap() {
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" << 'ROAD'
## Phase 1: Test Phase
**Goal:** Test goal
**Reqs:** REQ-01
**Success:** Tests pass
ROAD
}

create_guarded_plan() {
  cat > "$TEST_TEMP_DIR/test-plan.md" << 'PLAN'
---
phase: 1
plan: 1
title: Guarded Plan
wave: 1
depends_on: []
skills_used: []
must_haves:
  - "Feature A works"
forbidden_paths:
  - ".env"
---

# Plan

### Task 1: Do something
**Files:** `src/a.js`
PLAN
}

init_target_repo_with_commit() {
  local commit_message="$1"

  cd "$TEST_TEMP_DIR" || return 1
  git init -q
  git config user.name "VBW Test"
  git config user.email "vbw-tests@example.com"
  git add .
  git commit -qm "$commit_message"
}

enable_flags() {
  local flags="$1"
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq "$flags" ".vbw-planning/config.json" > "$tmp" && mv "$tmp" ".vbw-planning/config.json"
}

# --- No-op tests ---

@test "control-plane: pre-task without plan triggers gate failure" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/control-plane.sh" pre-task 1 1 1
  # Hard gates are graduated (always fire); without a plan, gate check fails
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.steps[] | select(.name == "contract") | .status == "skip"'
  echo "$output" | jq -e '.steps[] | select(.name == "gate_contract_compliance") | .status == "fail"'
}

@test "control-plane: post-task runs pipeline" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/control-plane.sh" post-task 1 1 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps | length > 0'
}

@test "control-plane: no-op when all flags OFF (compile)" {
  cd "$TEST_TEMP_DIR"
  enable_flags '.context_compiler = false | .token_budgets = false'
  run bash "$SCRIPTS_DIR/control-plane.sh" compile 1 1 1 --role=dev
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].name == "noop"'
}

@test "control-plane: full runs contract even with context_compiler=false" {
  cd "$TEST_TEMP_DIR"
  enable_flags '.context_compiler = false'
  run bash "$SCRIPTS_DIR/control-plane.sh" full 1 1 1
  [ "$status" -eq 0 ]
  # Contract is always-on (graduated), so full always runs
  echo "$output" | jq -e '.steps[] | select(.name == "contract") | .status == "skip"'
  echo "$output" | jq -e '.steps[] | select(.name == "context") | .status == "skip"'
}

# --- pre-task tests ---

@test "control-plane: pre-task sequences contract then gate" {
  create_test_plan
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/control-plane.sh" pre-task 1 1 1 --plan-path=test-plan.md --task-id=1-1-T1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "contract") | .status == "pass"'
  # Hard gates graduated — gate always runs
  echo "$output" | jq -e '.steps[] | select(.name == "gate_contract_compliance")'
}

@test "control-plane: pre-task uses lease-lock when lease_locks=true" {
  create_test_plan
  cd "$TEST_TEMP_DIR"
  enable_flags '.lease_locks = true'
  run bash "$SCRIPTS_DIR/control-plane.sh" pre-task 1 1 1 --plan-path=test-plan.md --task-id=1-1-T1 --claimed-files=src/a.js
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "lease_acquire") | .status == "pass"'
  # Verify lock file created
  [ -f ".vbw-planning/.locks/1-1-T1.lock" ]
  # Verify it has TTL (lease-lock adds expires_at)
  jq -e '.expires_at' ".vbw-planning/.locks/1-1-T1.lock"
}

@test "control-plane: pre-task off-root creates lock in target planning dir" {
  local unrelated_repo="$TEST_TEMP_DIR/unrelated-git"

  create_test_plan
  create_roadmap
  enable_flags '.lease_locks = true'
  setup_unrelated_git_repo "$unrelated_repo"
  cd "$unrelated_repo" || return 1

  run bash "$SCRIPTS_DIR/control-plane.sh" pre-task 1 1 1 \
    --plan-path="$TEST_TEMP_DIR/test-plan.md" \
    --phase-dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-test" \
    --task-id=1-1-T1 \
    --claimed-files=src/a.js
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "lease_acquire") | .status == "pass"'
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.locks/1-1-T1.lock" ]
  [ ! -e "$unrelated_repo/.vbw-planning/.locks/1-1-T1.lock" ]
}

@test "control-plane: pre-task off-root uses target staged files for protected-file gate" {
  local unrelated_repo="$TEST_TEMP_DIR/unrelated-git"

  create_guarded_plan
  create_roadmap
  enable_flags '.lease_locks = true'
  init_target_repo_with_commit 'fix(test): valid target baseline'
  echo 'SECRET=1' > "$TEST_TEMP_DIR/.env"
  git add .env

  setup_unrelated_git_repo_with_message "$unrelated_repo" 'fix(test): unrelated repo clean'
  cd "$unrelated_repo" || return 1

  run bash "$SCRIPTS_DIR/control-plane.sh" pre-task 1 1 1 \
    --plan-path="$TEST_TEMP_DIR/test-plan.md" \
    --phase-dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-test" \
    --task-id=1-1-T1 \
    --claimed-files=src/a.js
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.steps[] | select(.name == "gate_protected_file") | .status == "fail"'
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.locks/1-1-T1.lock" ]
  [ ! -e "$unrelated_repo/.vbw-planning/.locks/1-1-T1.lock" ]
}

# --- post-task tests ---

@test "control-plane: post-task releases lease" {
  cd "$TEST_TEMP_DIR"
  enable_flags '.lease_locks = true'
  # Create a lock file first
  echo '{"task_id":"1-1-T1","pid":"999","timestamp":"2024-01-01T00:00:00Z","files":["a.js"]}' > ".vbw-planning/.locks/1-1-T1.lock"
  [ -f ".vbw-planning/.locks/1-1-T1.lock" ]
  run bash "$SCRIPTS_DIR/control-plane.sh" post-task 1 1 1 --task-id=1-1-T1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "lease_release") | .status == "pass"'
  # Lock file should be removed
  [ ! -f ".vbw-planning/.locks/1-1-T1.lock" ]
}

@test "control-plane: post-task off-root releases target lock" {
  local unrelated_repo="$TEST_TEMP_DIR/unrelated-git"

  create_test_plan
  create_roadmap
  enable_flags '.lease_locks = true'
  init_target_repo_with_commit 'fix(test): valid target commit'
  echo '{"task_id":"1-1-T1","pid":"999","timestamp":"2024-01-01T00:00:00Z","files":["src/a.js"]}' > "$TEST_TEMP_DIR/.vbw-planning/.locks/1-1-T1.lock"

  setup_unrelated_git_repo_with_message "$unrelated_repo" 'fix(test): unrelated repo clean'
  cd "$unrelated_repo" || return 1

  run bash "$SCRIPTS_DIR/control-plane.sh" post-task 1 1 1 \
    --plan-path="$TEST_TEMP_DIR/test-plan.md" \
    --phase-dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-test" \
    --task-id=1-1-T1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "lease_release") | .status == "pass"'
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.locks/1-1-T1.lock" ]
  [ ! -e "$unrelated_repo/.vbw-planning/.locks/1-1-T1.lock" ]
}

@test "control-plane: post-task off-root uses target commit for commit-hygiene gate" {
  local unrelated_repo="$TEST_TEMP_DIR/unrelated-git"

  create_test_plan
  create_roadmap
  enable_flags '.lease_locks = true'
  init_target_repo_with_commit 'bad commit message'

  setup_unrelated_git_repo_with_message "$unrelated_repo" 'fix(test): unrelated repo clean'
  cd "$unrelated_repo" || return 1

  run bash "$SCRIPTS_DIR/control-plane.sh" post-task 1 1 1 \
    --plan-path="$TEST_TEMP_DIR/test-plan.md" \
    --phase-dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-test" \
    --task-id=1-1-T1
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.steps[] | select(.name == "gate_commit_hygiene") | .status == "fail"'
}

# --- compile tests ---

@test "control-plane: compile produces context file" {
  create_test_plan
  create_roadmap
  cd "$TEST_TEMP_DIR"
  # context_compiler is already true in test config
  run bash "$SCRIPTS_DIR/control-plane.sh" compile 1 1 1 --role=dev --phase-dir=.vbw-planning/phases/01-test --plan-path=test-plan.md
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "context") | .status == "pass"'
  [ -f ".vbw-planning/phases/01-test/.context-dev.md" ]
}

@test "control-plane: compile output includes context_path" {
  create_test_plan
  create_roadmap
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/control-plane.sh" compile 1 1 1 --role=dev --phase-dir=.vbw-planning/phases/01-test --plan-path=test-plan.md
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.context_path' | grep -q "context-dev.md"
}

@test "control-plane: compile honors explicit target planning dir off-root" {
  local unrelated_repo="$TEST_TEMP_DIR/unrelated-git"

  create_test_plan
  create_roadmap
  cat > "$TEST_TEMP_DIR/.vbw-planning/REQUIREMENTS.md" <<'EOF'
## Requirements
- [REQ-01] Test requirement
EOF

  setup_unrelated_git_repo "$unrelated_repo"
  cd "$unrelated_repo" || return 1

  run bash "$SCRIPTS_DIR/control-plane.sh" compile 1 1 1 \
    --role=lead \
    --phase-dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-test" \
    --plan-path="$TEST_TEMP_DIR/test-plan.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "context") | .status == "pass"'
  grep -q 'Test goal' "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/.context-lead.md"
}

@test "control-plane: compile honors explicit nested target planning dir off-root" {
  local unrelated_repo="$TEST_TEMP_DIR/unrelated-git"

  create_nested_control_plane_workspace
  cd "$NESTED_REPO_ROOT" || return 1
  git init -q
  git config user.name "VBW Test"
  git config user.email "vbw-tests@example.com"
  echo 'v1 body' > "$NESTED_WORKSPACE_ROOT/sample.txt"
  git add apps/proj
  git commit -qm 'init nested workspace'

  setup_unrelated_git_repo "$unrelated_repo"
  cd "$unrelated_repo" || return 1

  run bash "$SCRIPTS_DIR/control-plane.sh" compile 1 1 1 \
    --role=dev \
    --phase-dir="$NESTED_PHASE_DIR" \
    --plan-path="$NESTED_PLAN_PATH"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "context") | .status == "pass"'
  grep -q 'Test goal' "$NESTED_PHASE_DIR/.context-dev.md"
  grep -q 'v1 body' "$NESTED_PHASE_DIR/.context-dev.md"
}

# --- full action tests ---

@test "control-plane: full action runs contract then compile" {
  create_test_plan
  create_roadmap
  cd "$TEST_TEMP_DIR"
  # Contract-lite is graduated (always-on)
  run bash "$SCRIPTS_DIR/control-plane.sh" full 1 1 1 --plan-path=test-plan.md --role=dev --phase-dir=.vbw-planning/phases/01-test
  [ "$status" -eq 0 ]
  # Contract step should pass
  echo "$output" | jq -e '.steps[] | select(.name == "contract") | .status == "pass"'
  # Context step should pass
  echo "$output" | jq -e '.steps[] | select(.name == "context") | .status == "pass"'
  # Both artifacts exist
  [ -f ".vbw-planning/.contracts/1-1.json" ]
  [ -f ".vbw-planning/phases/01-test/.context-dev.md" ]
}

@test "control-plane: full honors explicit target planning dir off-root" {
  local unrelated_repo="$TEST_TEMP_DIR/unrelated-git"
  local canonical_root
  local actual_context
  local target_contract
  local target_context

  create_test_plan
  create_roadmap
  setup_unrelated_git_repo "$unrelated_repo"
  canonical_root=$(cd "$TEST_TEMP_DIR" && pwd -P)
  target_contract="$canonical_root/.vbw-planning/.contracts/1-1.json"
  target_context="$canonical_root/.vbw-planning/phases/01-test/.context-dev.md"
  cd "$unrelated_repo" || return 1

  run bash "$SCRIPTS_DIR/control-plane.sh" full 1 1 1 \
    --plan-path="$TEST_TEMP_DIR/test-plan.md" \
    --role=dev \
    --phase-dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "contract") | .status == "pass"'
  echo "$output" | jq -e '.steps[] | select(.name == "context") | .status == "pass"'
  echo "$output" | jq -e --arg p "$target_contract" '.contract_path == $p'
  actual_context=$(echo "$output" | jq -r '.context_path')
  actual_context="$(cd "$(dirname "$actual_context")" && pwd -P)/$(basename "$actual_context")"
  [ "$actual_context" = "$target_context" ]
  [ -f "$target_contract" ]
  [ -f "$target_context" ]
  [ ! -e "$unrelated_repo/.vbw-planning/.contracts/1-1.json" ]
}

@test "control-plane: explicit phase and plan beat conflicting VBW_PLANNING_DIR off-root" {
  local unrelated_repo="$TEST_TEMP_DIR/unrelated-git"
  local canonical_root
  local target_contract

  create_test_plan
  create_roadmap
  create_alternate_control_plane_workspace
  setup_unrelated_git_repo "$unrelated_repo"
  canonical_root=$(cd "$TEST_TEMP_DIR" && pwd -P)
  target_contract="$canonical_root/.vbw-planning/.contracts/1-1.json"
  cd "$unrelated_repo" || return 1

  run env VBW_PLANNING_DIR="$ALT_PLANNING_DIR" \
    bash "$SCRIPTS_DIR/control-plane.sh" full 1 1 1 \
    --plan-path="$TEST_TEMP_DIR/test-plan.md" \
    --role=dev \
    --phase-dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e --arg p "$target_contract" '.contract_path == $p'
  grep -q 'Test goal' "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/.context-dev.md"
  ! grep -q 'Goal from B' "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/.context-dev.md"
  [ ! -e "$ALT_PLANNING_DIR/.contracts/1-1.json" ]
}

# --- gate failure tests ---

@test "control-plane: gate failure returns exit 1" {
  cd "$TEST_TEMP_DIR"
  # No plan file and no contract -> gate should fail on missing contract
  run bash "$SCRIPTS_DIR/control-plane.sh" pre-task 1 1 1 --task-id=1-1-T1
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.steps[] | select(.name == "gate_contract_compliance") | .status == "fail"'
}

# --- individual scripts still callable ---

@test "control-plane: individual scripts still callable directly" {
  cd "$TEST_TEMP_DIR"
  # generate-contract.sh with no args -> usage, exit 0
  run bash "$SCRIPTS_DIR/generate-contract.sh"
  [ "$status" -eq 0 ]

  # lease-lock.sh with no args -> usage, exit 0
  run bash "$SCRIPTS_DIR/lease-lock.sh"
  [ "$status" -eq 0 ]

  # hard-gate.sh with no args -> exit 0 (insufficient args output)
  run bash "$SCRIPTS_DIR/hard-gate.sh"
  [ "$status" -eq 0 ]

  # compile-context.sh with no args -> exit 1 (usage)
  run bash "$SCRIPTS_DIR/compile-context.sh"
  [ "$status" -eq 1 ]
}

# --- usage tests ---

@test "control-plane: no args prints usage and exits 0" {
  run bash "$SCRIPTS_DIR/control-plane.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "control-plane: JSON output format correct" {
  create_test_plan
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/control-plane.sh" pre-task 1 1 1 --plan-path=test-plan.md --task-id=1-1-T1
  [ "$status" -eq 0 ]
  # Verify valid JSON with action and steps fields
  echo "$output" | jq -e '.action == "pre-task"'
  echo "$output" | jq -e '.steps | type == "array"'
  echo "$output" | jq -e '.steps | length > 0'
}

# --- Integration tests (protocol-level flow) ---

@test "control-plane: full plan lifecycle (contract + compile + pre-task + post-task)" {
  create_test_plan
  create_roadmap
  cd "$TEST_TEMP_DIR"
  # v3_contract_lite graduated — contracts always generated

  # Step 1: full action (once per plan) — generates contract + compiles context
  run bash "$SCRIPTS_DIR/control-plane.sh" full 1 1 1 \
    --plan-path=test-plan.md --role=dev --phase-dir=.vbw-planning/phases/01-test
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "contract") | .status == "pass"'
  echo "$output" | jq -e '.steps[] | select(.name == "context") | .status == "pass"'
  [ -f ".vbw-planning/.contracts/1-1.json" ]
  [ -f ".vbw-planning/phases/01-test/.context-dev.md" ]

  # Step 2: pre-task (before task 1) — acquires lock (requires lease_locks=true)
  enable_flags '.lease_locks = true'
  run bash "$SCRIPTS_DIR/control-plane.sh" pre-task 1 1 1 \
    --plan-path=test-plan.md --task-id=1-1-T1 --claimed-files=src/a.js
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "lease_acquire") | .status == "pass"'
  [ -f ".vbw-planning/.locks/1-1-T1.lock" ]

  # Step 3: post-task (after task 1) — releases lock
  run bash "$SCRIPTS_DIR/control-plane.sh" post-task 1 1 1 --task-id=1-1-T1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "lease_release") | .status == "pass"'
  [ ! -f ".vbw-planning/.locks/1-1-T1.lock" ]
}

@test "control-plane: fallback when dependency script missing" {
  create_test_plan
  create_roadmap
  cd "$TEST_TEMP_DIR"
  # v3_contract_lite graduated — contracts always generated

  # Create a local scripts dir with control-plane.sh but WITHOUT generate-contract.sh
  mkdir -p "$TEST_TEMP_DIR/scripts"
  cp "$SCRIPTS_DIR/control-plane.sh" "$TEST_TEMP_DIR/scripts/"
  # Copy supporting scripts except generate-contract.sh
  for s in compile-context.sh token-budget.sh lock-lite.sh lease-lock.sh hard-gate.sh auto-repair.sh; do
    [ -f "$SCRIPTS_DIR/$s" ] && cp "$SCRIPTS_DIR/$s" "$TEST_TEMP_DIR/scripts/"
  done

  # full action should still exit 0 (fail-open on missing generate-contract.sh)
  run bash "$TEST_TEMP_DIR/scripts/control-plane.sh" full 1 1 1 \
    --plan-path=test-plan.md --role=dev --phase-dir=.vbw-planning/phases/01-test
  [ "$status" -eq 0 ]
  # Contract step should fail gracefully (not crash)
  # Extract JSON from output (skip stderr lines that appear before JSON)
  local json_output
  json_output=$(echo "$output" | sed -n '/^{/,/^}/p')
  local contract_status
  contract_status=$(echo "$json_output" | jq -r '.steps[] | select(.name == "contract") | .status')
  [[ "$contract_status" == "fail" || "$contract_status" == "skip" ]]
}

@test "control-plane: multiple tasks in sequence without stale locks" {
  create_test_plan
  cd "$TEST_TEMP_DIR"
  enable_flags '.lease_locks = true'

  # Task 1: pre-task -> post-task (pass plan-path for contract generation)
  run bash "$SCRIPTS_DIR/control-plane.sh" pre-task 1 1 1 --plan-path=test-plan.md --task-id=1-1-T1 --claimed-files=src/a.js
  [ "$status" -eq 0 ]
  [ -f ".vbw-planning/.locks/1-1-T1.lock" ]

  run bash "$SCRIPTS_DIR/control-plane.sh" post-task 1 1 1 --task-id=1-1-T1
  [ "$status" -eq 0 ]
  [ ! -f ".vbw-planning/.locks/1-1-T1.lock" ]

  # Task 2: pre-task -> post-task (no stale lock from task 1)
  run bash "$SCRIPTS_DIR/control-plane.sh" pre-task 1 1 2 --plan-path=test-plan.md --task-id=1-1-T2 --claimed-files=src/b.js
  [ "$status" -eq 0 ]
  [ -f ".vbw-planning/.locks/1-1-T2.lock" ]
  # Task 1 lock should still be gone
  [ ! -f ".vbw-planning/.locks/1-1-T1.lock" ]

  run bash "$SCRIPTS_DIR/control-plane.sh" post-task 1 1 2 --task-id=1-1-T2
  [ "$status" -eq 0 ]
  [ ! -f ".vbw-planning/.locks/1-1-T2.lock" ]
}

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

create_nested_context_workspace() {
  NESTED_REPO_ROOT="$TEST_TEMP_DIR/mono"
  NESTED_WORKSPACE_ROOT="$NESTED_REPO_ROOT/apps/proj"
  NESTED_PLANNING_DIR="$NESTED_WORKSPACE_ROOT/.vbw-planning"
  NESTED_PHASE_DIR="$NESTED_PLANNING_DIR/phases/02-test-phase"
  NESTED_PLAN_PATH="$NESTED_PHASE_DIR/02-01-PLAN.md"

  mkdir -p "$NESTED_PHASE_DIR"
  create_test_config "mono/apps/proj/.vbw-planning"
  cat > "$NESTED_PLANNING_DIR/ROADMAP.md" <<'EOF'
# Nested Test Roadmap
## Phase 2: Nested Test Phase
**Goal:** Nested test goal
**Reqs:** REQ-01
**Success:** Tests pass
EOF
  cat > "$NESTED_PLAN_PATH" <<'EOF'
---
phase: 2
plan: 1
title: "Nested Test Plan"
wave: 1
depends_on: []
must_haves: ["test"]
---
# Nested Test Plan
EOF
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

@test "cache-context.sh: rolling summary fingerprint excluded when flag is false" {
  local unrelated_repo="$TEST_TEMP_DIR/unrelated-git"

  # Default config has rolling_summary=false.
  # Run from an unrelated git repo to prove explicit config/plan inputs ignore
  # both ambient repo dirtiness and rolling-context content changes.
  setup_unrelated_git_repo "$unrelated_repo"

  echo "# Rolling Context" > "$TEST_TEMP_DIR/.vbw-planning/ROLLING-CONTEXT.md"
  cd "$unrelated_repo" || return 1

  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev "$TEST_TEMP_DIR/.vbw-planning/config.json" \
    "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)

  echo "# Different Content" > "$TEST_TEMP_DIR/.vbw-planning/ROLLING-CONTEXT.md"
  echo "modified" >> unrelated.txt

  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev "$TEST_TEMP_DIR/.vbw-planning/config.json" \
    "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  HASH2=$(echo "$output" | cut -d' ' -f2)

  # Hash should be stable when flag is false (rolling context ignored)
  [ "$HASH1" = "$HASH2" ]
}

@test "cache-context.sh: rolling summary fingerprint changes hash when flag is true" {
  cd "$TEST_TEMP_DIR"
  # Enable rolling_summary in config
  jq '. + {"rolling_summary": true}' .vbw-planning/config.json > .vbw-planning/config.tmp \
    && mv .vbw-planning/config.tmp .vbw-planning/config.json
  echo "# Rolling Context v1" > .vbw-planning/ROLLING-CONTEXT.md
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)
  echo "# Rolling Context v2 (changed)" > .vbw-planning/ROLLING-CONTEXT.md
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  HASH2=$(echo "$output" | cut -d' ' -f2)
  # Hash must differ when rolling context content changes
  [ "$HASH1" != "$HASH2" ]
}

@test "cache-context.sh: delta content hash follows target repo off-root across committed content changes" {
  local unrelated_repo
  unrelated_repo=$(mktemp -d "${TMPDIR:-/tmp}/vbw-unrelated.XXXXXX")

  setup_unrelated_git_repo "$unrelated_repo"

  cd "$TEST_TEMP_DIR" || return 1
  git init -q
  git config user.name "VBW Test"
  git config user.email "vbw-tests@example.com"

  cat > .vbw-planning/phases/02-test-phase/02-01-SUMMARY.md <<'EOF'
# Summary
## Files Modified
- sample.txt
## Deviations
EOF

  echo 'v1' > sample.txt
  git add .vbw-planning/config.json .vbw-planning/ROADMAP.md \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md \
    .vbw-planning/phases/02-test-phase/02-01-SUMMARY.md sample.txt
  git commit -qm 'init target repo'

  echo 'v2' > sample.txt
  git add sample.txt
  git commit -qm 'update sample v2'

  cd "$unrelated_repo" || return 1
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev "$TEST_TEMP_DIR/.vbw-planning/config.json" \
    "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)

  cd "$TEST_TEMP_DIR" || return 1
  echo 'v3' > sample.txt
  git add sample.txt
  git commit -qm 'update sample v3'

  cd "$unrelated_repo" || return 1
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev "$TEST_TEMP_DIR/.vbw-planning/config.json" \
    "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  HASH2=$(echo "$output" | cut -d' ' -f2)

  rm -rf "$unrelated_repo"

  [ "$HASH1" != "$HASH2" ]
}

@test "cache-context.sh: nested workspace committed content changes alter hash off-root" {
  local unrelated_repo="$TEST_TEMP_DIR/unrelated-git"

  create_nested_context_workspace

  cd "$NESTED_REPO_ROOT" || return 1
  git init -q
  git config user.name "VBW Test"
  git config user.email "vbw-tests@example.com"

  echo 'v1' > "$NESTED_WORKSPACE_ROOT/sample.txt"
  git add apps/proj
  git commit -qm 'init nested workspace'

  echo 'v2' > "$NESTED_WORKSPACE_ROOT/sample.txt"
  git add apps/proj/sample.txt
  git commit -qm 'update nested sample v2'

  setup_unrelated_git_repo "$unrelated_repo"
  cd "$unrelated_repo" || return 1

  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev "$NESTED_PLANNING_DIR/config.json" "$NESTED_PLAN_PATH"
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)

  cd "$NESTED_REPO_ROOT" || return 1
  echo 'v3' > "$NESTED_WORKSPACE_ROOT/sample.txt"
  git add apps/proj/sample.txt
  git commit -qm 'update nested sample v3'

  cd "$unrelated_repo" || return 1
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev "$NESTED_PLANNING_DIR/config.json" "$NESTED_PLAN_PATH"
  [ "$status" -eq 0 ]
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" != "$HASH2" ]
}

@test "cache-context.sh: nested workspace hash ignores sibling repo noise off-root" {
  local unrelated_repo="$TEST_TEMP_DIR/unrelated-git"

  create_nested_context_workspace

  cd "$NESTED_REPO_ROOT" || return 1
  git init -q
  git config user.name "VBW Test"
  git config user.email "vbw-tests@example.com"

  echo 'v1' > "$NESTED_WORKSPACE_ROOT/sample.txt"
  git add apps/proj
  git commit -qm 'init nested workspace'

  echo 'v2' > "$NESTED_WORKSPACE_ROOT/sample.txt"
  git add apps/proj/sample.txt
  git commit -qm 'update nested sample v2'

  setup_unrelated_git_repo "$unrelated_repo"
  cd "$unrelated_repo" || return 1

  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev "$NESTED_PLANNING_DIR/config.json" "$NESTED_PLAN_PATH"
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)

  cd "$NESTED_REPO_ROOT" || return 1
  echo 'shared change' > shared.txt
  git add shared.txt
  git commit -qm 'update sibling noise'

  cd "$unrelated_repo" || return 1
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev "$NESTED_PLANNING_DIR/config.json" "$NESTED_PLAN_PATH"
  [ "$status" -eq 0 ]
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" = "$HASH2" ]
}

@test "cache-context.sh: milestone context fingerprint changes hash when CONTEXT.md changes" {
  cd "$TEST_TEMP_DIR"
  echo "# Milestone Context v1" > .vbw-planning/CONTEXT.md
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)

  echo "# Milestone Context v2" > .vbw-planning/CONTEXT.md
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" != "$HASH2" ]
}

@test "cache-context.sh: research fingerprint changes hash when phase path contains spaces" {
  SPACE_ROOT="$TEST_TEMP_DIR/space dir"
  mkdir -p "$SPACE_ROOT/.vbw-planning/phases/02-test phase"

  cat > "$SPACE_ROOT/.vbw-planning/config.json" <<'EOF'
{"v3_context_cache": true}
EOF
  cat > "$SPACE_ROOT/.vbw-planning/ROADMAP.md" <<'EOF'
# Roadmap
## Phase 2: Test Phase
**Goal:** Test goal
**Success:** Tests pass
**Reqs:** REQ-01
EOF
  cat > "$SPACE_ROOT/.vbw-planning/phases/02-test phase/02-01-PLAN.md" <<'EOF'
---
phase: 2
plan: 1
title: "Test Plan"
wave: 1
depends_on: []
must_haves: ["test"]
---
EOF
  echo "## Findings
- v1" > "$SPACE_ROOT/.vbw-planning/phases/02-test phase/02-RESEARCH.md"

  cd "$SPACE_ROOT"
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev .vbw-planning/config.json \
    ".vbw-planning/phases/02-test phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)

  echo "## Findings
- v2" > "$SPACE_ROOT/.vbw-planning/phases/02-test phase/02-RESEARCH.md"
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev .vbw-planning/config.json \
    ".vbw-planning/phases/02-test phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" != "$HASH2" ]
}

@test "cache-context.sh: roadmap fingerprint changes hash when ROADMAP.md changes" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)

  cat > .vbw-planning/ROADMAP.md <<'EOF'
# Test Roadmap
## Phase 2: Test Phase
**Goal:** Updated goal
**Success:** Tests pass
**Reqs:** REQ-01
EOF

  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" != "$HASH2" ]
}

@test "cache-context.sh: requirements fingerprint changes hash for lead role" {
  cd "$TEST_TEMP_DIR"
  echo "- [REQ-01] Original requirement" > .vbw-planning/REQUIREMENTS.md
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 lead .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)

  echo "- [REQ-01] Updated requirement" > .vbw-planning/REQUIREMENTS.md
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 lead .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" != "$HASH2" ]
}

@test "cache-context.sh: state fingerprint changes hash for lead role" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/STATE.md <<'EOF'
# State

## Key Decisions
| Decision | Date | Rationale |
|----------|------|-----------|
| Use API v1 | | |
EOF

  run bash "$SCRIPTS_DIR/cache-context.sh" 02 lead .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)

  cat > .vbw-planning/STATE.md <<'EOF'
# State

## Key Decisions
| Decision | Date | Rationale |
|----------|------|-----------|
| Use API v2 | | |
EOF

  run bash "$SCRIPTS_DIR/cache-context.sh" 02 lead .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" != "$HASH2" ]
}

@test "compile-context.sh: lead reads legacy Decisions heading for Active Decisions" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/STATE.md <<'EOF'
# State

## Decisions
- Keep feature flags conservative
EOF

  run bash "$SCRIPTS_DIR/compile-context.sh" 02 lead .vbw-planning/phases .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  grep -q 'Keep feature flags conservative' .vbw-planning/phases/02-test-phase/.context-lead.md
}

@test "compile-context.sh: lead active decisions strips legacy skills and pending todos" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/STATE.md <<'EOF'
# State

## Decisions
- Keep feature flags conservative

### skills   
**Installed:** foo, bar
**Suggested:** baz

### Pending Todos
- Migrate session store
EOF

  run bash "$SCRIPTS_DIR/compile-context.sh" 02 lead .vbw-planning/phases .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  grep -q 'Keep feature flags conservative' .vbw-planning/phases/02-test-phase/.context-lead.md
  ! grep -q 'Installed:' .vbw-planning/phases/02-test-phase/.context-lead.md
  ! grep -q 'Suggested:' .vbw-planning/phases/02-test-phase/.context-lead.md
  ! grep -q 'Migrate session store' .vbw-planning/phases/02-test-phase/.context-lead.md
}

@test "cache-context.sh: conventions fingerprint changes hash for dev role" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/conventions.json <<'EOF'
{"conventions":[{"tag":"STYLE","rule":"Use v1"}]}
EOF

  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)

  cat > .vbw-planning/conventions.json <<'EOF'
{"conventions":[{"tag":"STYLE","rule":"Use v2"}]}
EOF

  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" != "$HASH2" ]
}

@test "cache-context.sh: scout conventions fingerprint changes hash" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/conventions.json <<'EOF'
{"conventions":[{"tag":"STYLE","rule":"Scout v1"}]}
EOF

  run bash "$SCRIPTS_DIR/cache-context.sh" 02 scout .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)

  cat > .vbw-planning/conventions.json <<'EOF'
{"conventions":[{"tag":"STYLE","rule":"Scout v2"}]}
EOF

  run bash "$SCRIPTS_DIR/cache-context.sh" 02 scout .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" != "$HASH2" ]
}

@test "cache-context.sh: research fingerprint changes hash for dev role" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/phases/02-test-phase/02-RESEARCH.md <<'EOF'
## Findings
- Initial research
EOF

  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)

  cat > .vbw-planning/phases/02-test-phase/02-RESEARCH.md <<'EOF'
## Findings
- Updated research
EOF

  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" != "$HASH2" ]
}

@test "cache-context.sh: delta content fingerprint changes hash when file content changes but file list stays same" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/phases/02-test-phase/02-01-SUMMARY.md <<'EOF'
## Files Modified
- sample.txt
EOF
  echo 'v1' > sample.txt

  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)

  echo 'v2' > sample.txt
  run bash "$SCRIPTS_DIR/cache-context.sh" 02 dev .vbw-planning/config.json \
    .vbw-planning/phases/02-test-phase/02-01-PLAN.md
  [ "$status" -eq 0 ]
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" != "$HASH2" ]
}

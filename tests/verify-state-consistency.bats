#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

# Helper: scaffold a consistent .vbw-planning/ workspace
scaffold_consistent_workspace() {
  local root="$TEST_TEMP_DIR/.vbw-planning"

  cat > "$root/STATE.md" <<'EOF'
# State
**Project:** My Test Project
**Milestone:** MVP
Phase: 2 of 3 (Backend API)
Plans: 1/1
Progress: 50%
Status: running
EOF

  cat > "$root/PROJECT.md" <<'EOF'
# My Test Project
Core value proposition for testing.
EOF

  cat > "$root/ROADMAP.md" <<'EOF'
# Roadmap

- [x] Phase 1: Setup
- [ ] Phase 2: Backend API
- [ ] Phase 3: Frontend

### Phase 1: Setup
### Phase 2: Backend API
### Phase 3: Frontend
EOF

  mkdir -p "$root/phases/01-setup"
  echo "# Plan" > "$root/phases/01-setup/01-01-PLAN.md"
  cat > "$root/phases/01-setup/01-01-SUMMARY.md" <<'SUMMARY'
---
status: complete
---
# Summary
SUMMARY

  mkdir -p "$root/phases/02-backend-api"
  echo "# Plan" > "$root/phases/02-backend-api/02-01-PLAN.md"

  mkdir -p "$root/phases/03-frontend"
}

# ============================================================
# Happy path
# ============================================================

@test "all files consistent returns verdict pass" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "pass" ]

  local failed
  failed=$(echo "$output" | jq -r '.failed_checks | length')
  [ "$failed" -eq 0 ]
}

# ============================================================
# No project state
# ============================================================

@test "missing .vbw-planning returns verdict skip" {
  cd "$TEST_TEMP_DIR"
  rm -rf "$TEST_TEMP_DIR/.vbw-planning"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "skip" ]
}

@test "missing STATE.md returns verdict skip" {
  cd "$TEST_TEMP_DIR"
  rm -f "$TEST_TEMP_DIR/.vbw-planning/STATE.md"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "skip" ]
}

# ============================================================
# Check 1: STATE.md ↔ filesystem
# ============================================================

@test "state_vs_filesystem fails when phase total mismatches filesystem" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # STATE.md says 3 phases but add a 4th dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/04-extra"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]

  echo "$output" | jq -e '.failed_checks | index("state_vs_filesystem")' >/dev/null
  echo "$output" | jq -r '.checks.state_vs_filesystem.detail' | grep -q "phase total mismatch"
}

@test "state_vs_filesystem fails when active phase mismatches" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Change STATE.md to say phase 1 but phase 1 is already complete — active should be 2
  sed -i.bak 's/Phase: 2 of 3/Phase: 1 of 3/' "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  rm -f "$TEST_TEMP_DIR/.vbw-planning/STATE.md.bak"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]

  echo "$output" | jq -e '.failed_checks | index("state_vs_filesystem")' >/dev/null
  echo "$output" | jq -r '.checks.state_vs_filesystem.detail' | grep -q "active phase mismatch"
}

# ============================================================
# Check 2: ROADMAP.md ↔ SUMMARY.md (completion markers)
# ============================================================

@test "roadmap_vs_summaries fails when roadmap marks incomplete phase as done" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Mark phase 2 as [x] in roadmap but it has no SUMMARY.md
  sed -i.bak 's/\- \[ \] Phase 2: Backend API/- [x] Phase 2: Backend API/' "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  rm -f "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md.bak"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]

  echo "$output" | jq -e '.failed_checks | index("roadmap_vs_summaries")' >/dev/null
  echo "$output" | jq -r '.checks.roadmap_vs_summaries.detail' | grep -q "phase 2 marked \[x\] but incomplete"
}

@test "roadmap_vs_summaries fails when complete phase not marked done" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Phase 1 is complete (has SUMMARY with status:complete) but mark as [ ] in roadmap
  sed -i.bak 's/\- \[x\] Phase 1: Setup/- [ ] Phase 1: Setup/' "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  rm -f "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md.bak"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]

  echo "$output" | jq -e '.failed_checks | index("roadmap_vs_summaries")' >/dev/null
  echo "$output" | jq -r '.checks.roadmap_vs_summaries.detail' | grep -q "phase 1 marked \[ \] but all plans complete"
}

# ============================================================
# Check 3: .execution-state.json ↔ filesystem
# ============================================================

@test "exec_state_vs_filesystem skips when no exec state file" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local detail
  detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [ "$detail" = "skip: no .execution-state.json" ]

  local pass
  pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$pass" = "true" ]
}

@test "exec_state_vs_filesystem fails when phase dir not found" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'JSON'
{
  "phase": 5,
  "status": "running"
}
JSON

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.failed_checks | index("exec_state_vs_filesystem")' >/dev/null
  echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail' | grep -q "phase dir for phase 5 not found"
}

@test "exec_state_vs_filesystem fails when complete but plans incomplete" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'JSON'
{
  "phase": 2,
  "status": "complete"
}
JSON

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.failed_checks | index("exec_state_vs_filesystem")' >/dev/null
  echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail' | grep -q "status is 'complete' but phase 2 has incomplete plans"
}

# ============================================================
# Check 4: STATE.md ↔ ROADMAP.md (phase count)
# ============================================================

@test "state_vs_roadmap fails when phase count disagrees" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Add a 4th phase to ROADMAP but STATE still says 3
  cat >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
- [ ] Phase 4: Deployment

### Phase 4: Deployment
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]

  echo "$output" | jq -e '.failed_checks | index("state_vs_roadmap")' >/dev/null
  echo "$output" | jq -r '.checks.state_vs_roadmap.detail' | grep -q "STATE.md total=3"
}

# ============================================================
# Check 5: PROJECT.md ↔ STATE.md (project name)
# ============================================================

@test "project_vs_state fails when names differ" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  echo "# Different Project Name" > "$TEST_TEMP_DIR/.vbw-planning/PROJECT.md"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]

  echo "$output" | jq -e '.failed_checks | index("project_vs_state")' >/dev/null
}

@test "project_vs_state skips when no PROJECT.md" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace
  rm -f "$TEST_TEMP_DIR/.vbw-planning/PROJECT.md"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local detail
  detail=$(echo "$output" | jq -r '.checks.project_vs_state.detail')
  [ "$detail" = "skip: no PROJECT.md" ]
}

# ============================================================
# Exit code behavior
# ============================================================

@test "archive mode exits 2 on failure" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Create a mismatch
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/04-extra"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode archive
  [ "$status" -eq 2 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]

  local mode
  mode=$(echo "$output" | jq -r '.mode')
  [ "$mode" = "archive" ]
}

@test "advisory mode exits 0 on failure" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Create a mismatch
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/04-extra"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]

  local mode
  mode=$(echo "$output" | jq -r '.mode')
  [ "$mode" = "advisory" ]
}

@test "archive mode exits 0 when all pass" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode archive
  [ "$status" -eq 0 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "pass" ]
}

# ============================================================
# JSON structure
# ============================================================

@test "output contains all required JSON fields" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  # Validate all top-level fields
  echo "$output" | jq -e '.verdict' >/dev/null
  echo "$output" | jq -e '.mode' >/dev/null
  echo "$output" | jq -e '.checks' >/dev/null
  echo "$output" | jq -e '.failed_checks' >/dev/null

  # Validate all check fields
  echo "$output" | jq -e '.checks.state_vs_filesystem.pass' >/dev/null
  echo "$output" | jq -e '.checks.state_vs_filesystem.detail' >/dev/null
  echo "$output" | jq -e '.checks.roadmap_vs_summaries.pass' >/dev/null
  echo "$output" | jq -e '.checks.exec_state_vs_filesystem.pass' >/dev/null
  echo "$output" | jq -e '.checks.state_vs_roadmap.pass' >/dev/null
  echo "$output" | jq -e '.checks.project_vs_state.pass' >/dev/null
}

@test "default mode is advisory when --mode not specified" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$status" -eq 0 ]

  local mode
  mode=$(echo "$output" | jq -r '.mode')
  [ "$mode" = "advisory" ]
}

@test "state_vs_filesystem passes with non-contiguous phase dirs" {
  cd "$TEST_TEMP_DIR"
  local root="$TEST_TEMP_DIR/.vbw-planning"

  # STATE says Phase 3 of 2 — only 2 phase dirs but numbered 01 and 03
  cat > "$root/STATE.md" <<'EOF'
# State
**Project:** My Test Project
**Milestone:** MVP
Phase: 3 of 2 (Build)
Plans: 1/1
Progress: 50%
Status: running
EOF

  cat > "$root/PROJECT.md" <<'EOF'
# My Test Project
Core value proposition for testing.
EOF

  cat > "$root/ROADMAP.md" <<'EOF'
# Roadmap

- [x] Phase 1: Setup
- [ ] Phase 3: Build

### Phase 1: Setup
### Phase 3: Build
EOF

  # Non-contiguous: 01 and 03 (no 02)
  mkdir -p "$root/phases/01-setup"
  echo "# Plan" > "$root/phases/01-setup/01-01-PLAN.md"
  cat > "$root/phases/01-setup/01-01-SUMMARY.md" <<'SUMMARY'
---
status: complete
---
# Summary
SUMMARY

  mkdir -p "$root/phases/03-build"
  echo "# Plan" > "$root/phases/03-build/03-01-PLAN.md"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$root" --mode advisory
  [ "$status" -eq 0 ]

  # Active phase num is 3 (from 03-build prefix), STATE says phase 3 — should match
  local phase_pass
  phase_pass=$(echo "$output" | jq -r '.checks.state_vs_filesystem.pass')
  [ "$phase_pass" = "true" ]
}

@test "exec_state plan with only generic SUMMARY.md fails" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace
  local root="$TEST_TEMP_DIR/.vbw-planning"

  # Create exec state with a completed plan "02-01"
  cat > "$root/.execution-state.json" <<'JSON'
{
  "phase": 2,
  "status": "running",
  "plans": [
    {"id": "02-01", "status": "complete"}
  ]
}
JSON

  # Only generic SUMMARY.md exists, not plan-specific 02-01-SUMMARY.md
  cat > "$root/phases/02-backend-api/SUMMARY.md" <<'SUMMARY'
---
status: complete
---
# Summary
SUMMARY

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$root" --mode advisory
  [ "$status" -eq 0 ]

  local exec_pass
  exec_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$exec_pass" = "false" ]
}

@test "exec_state pending plan with no PLAN.md fails" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace
  local root="$TEST_TEMP_DIR/.vbw-planning"

  # Create exec state with a pending plan "02-02" that has no PLAN.md
  cat > "$root/.execution-state.json" <<'JSON'
{
  "phase": 2,
  "status": "running",
  "plans": [
    {"id": "02-01", "status": "running"},
    {"id": "02-02", "status": "pending"}
  ]
}
JSON

  # Only 02-01-PLAN.md exists — no 02-02-PLAN.md and no generic PLAN.md
  # (scaffold already created 02-01-PLAN.md; remove generic if any)
  rm -f "$root/phases/02-backend-api/PLAN.md"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$root" --mode advisory
  [ "$status" -eq 0 ]

  local exec_pass
  exec_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$exec_pass" = "false" ]
}

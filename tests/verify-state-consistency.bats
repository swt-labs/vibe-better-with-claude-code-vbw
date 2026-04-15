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

  # Advisory skip paths must still emit per-check JSON structure
  local c1_detail
  c1_detail=$(echo "$output" | jq -r '.checks.state_vs_filesystem.detail')
  [ "$c1_detail" = "not evaluated" ]

  local fc_count
  fc_count=$(echo "$output" | jq '.failed_checks | length')
  [ "$fc_count" -eq 0 ]
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

@test "exec_state pending plan with generic PLAN.md but no numbered plan fails" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace
  local root="$TEST_TEMP_DIR/.vbw-planning"

  # Create exec state with pending plan "02-02"
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

  # Generic PLAN.md exists but no 02-02-PLAN.md — should still fail
  echo "# Generic plan" > "$root/phases/02-backend-api/PLAN.md"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$root" --mode advisory
  [ "$status" -eq 0 ]

  local exec_pass
  exec_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$exec_pass" = "false" ]

  # Verify the detail mentions the specific plan
  echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail' | grep -q "02-02"
}

@test "archive mode fails when STATE.md is missing" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  create_test_config

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode archive
  [ "$status" -eq 2 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]

  echo "$output" | jq -r '.failed_checks[]' | grep -q "missing_state_md"
}

@test "archive mode fails when ROADMAP.md is missing" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  create_test_config

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State
**Project:** My Test Project
**Milestone:** MVP
Phase: 1 of 1 (Setup)
Plans: 0/0
Progress: 0%
Status: ready
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode archive
  [ "$status" -eq 2 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]

  echo "$output" | jq -r '.failed_checks[]' | grep -q "missing_roadmap_md"
}

@test "advisory mode skips when STATE.md is missing" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  create_test_config

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "skip" ]

  # Advisory skip paths must still emit per-check JSON structure
  local c1_detail
  c1_detail=$(echo "$output" | jq -r '.checks.state_vs_filesystem.detail')
  [ "$c1_detail" = "not evaluated" ]

  local fc_count
  fc_count=$(echo "$output" | jq '.failed_checks | length')
  [ "$fc_count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Malformed artifact handling (archive vs advisory)
# ---------------------------------------------------------------------------

@test "archive mode fails on malformed STATE.md Phase line" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Corrupt the Phase line so it can't be parsed
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State
**Project:** Test Project
**Milestone:** MVP
Phase: GARBAGE not a number
Plans: 0/0
Progress: 0%
Status: ready
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode archive
  [ "$status" -eq 2 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]

  # state_vs_filesystem and state_vs_roadmap should both fail
  echo "$output" | jq -r '.failed_checks[]' | grep -q "state_vs_filesystem"
  echo "$output" | jq -r '.failed_checks[]' | grep -q "state_vs_roadmap"

  local c1_detail
  c1_detail=$(echo "$output" | jq -r '.checks.state_vs_filesystem.detail')
  [[ "$c1_detail" == *"unparseable"* ]]
}

@test "advisory mode skips on malformed STATE.md Phase line" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Corrupt the Phase line
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State
**Project:** Test Project
**Milestone:** MVP
Phase: GARBAGE not a number
Plans: 0/0
Progress: 0%
Status: ready
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c1_detail
  c1_detail=$(echo "$output" | jq -r '.checks.state_vs_filesystem.detail')
  [[ "$c1_detail" == *"skip"* ]]

  local c1_pass
  c1_pass=$(echo "$output" | jq -r '.checks.state_vs_filesystem.pass')
  [ "$c1_pass" = "true" ]
}

@test "archive mode fails on invalid execution-state JSON" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Write invalid JSON
  echo "NOT JSON {{{" > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode archive
  [ "$status" -eq 2 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "false" ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [[ "$c3_detail" == *"invalid"* ]]
}

@test "advisory mode skips on invalid execution-state JSON" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  echo "NOT JSON {{{" > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "true" ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [[ "$c3_detail" == *"skip"* ]]
}

@test "exec_state pending plan with existing SUMMARY.md detects stale status" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Create an execution-state with a pending plan that already has a SUMMARY
  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'EOF'
{
  "phase": 2,
  "status": "running",
  "plans": [
    {"id": "stale-plan", "status": "pending"}
  ]
}
EOF

  # Create the plan file (required for pending) AND a summary (stale)
  touch "$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api/stale-plan-PLAN.md"
  touch "$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api/stale-plan-SUMMARY.md"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "false" ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [[ "$c3_detail" == *"stale status"* ]]
}

# ---------------------------------------------------------------------------
# Missing phases directory (archive vs advisory)
# ---------------------------------------------------------------------------

@test "archive mode fails when phases directory is missing" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  create_test_config

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State
**Project:** Test Project
**Milestone:** MVP
Phase: 1 of 2 (Setup)
Plans: 0/0
Progress: 0%
Status: ready
EOF

  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
# Roadmap
- [ ] Phase 1: Setup
- [ ] Phase 2: Build
### Phase 1: Setup
### Phase 2: Build
EOF

  # No phases/ directory created
  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode archive
  [ "$status" -eq 2 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]

  # Multiple checks should fail due to missing phases dir
  local c1_pass
  c1_pass=$(echo "$output" | jq -r '.checks.state_vs_filesystem.pass')
  [ "$c1_pass" = "false" ]
}

@test "advisory mode skips when phases directory is missing" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  create_test_config

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State
**Project:** Test Project
**Milestone:** MVP
Phase: 1 of 2 (Setup)
Plans: 0/0
Progress: 0%
Status: ready
EOF

  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
# Roadmap
- [ ] Phase 1: Setup
- [ ] Phase 2: Build
### Phase 1: Setup
### Phase 2: Build
EOF

  # No phases/ directory
  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c1_detail
  c1_detail=$(echo "$output" | jq -r '.checks.state_vs_filesystem.detail')
  [[ "$c1_detail" == *"skip"* ]]

  local c1_pass
  c1_pass=$(echo "$output" | jq -r '.checks.state_vs_filesystem.pass')
  [ "$c1_pass" = "true" ]
}

# ---------------------------------------------------------------------------
# Stale top-level execution status
# ---------------------------------------------------------------------------

@test "exec_state top-level running with all plans complete detects stale status" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Create execution-state saying "running" but all plans are complete
  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'EOF'
{
  "phase": 2,
  "status": "running",
  "plans": [
    {"id": "done-plan", "status": "complete"}
  ]
}
EOF

  # Plan has a PLAN.md and completed SUMMARY.md
  touch "$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api/done-plan-PLAN.md"
  touch "$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api/done-plan-SUMMARY.md"
  # Also complete the scaffold's default plan so all plans in phase 2 are done
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api/02-01-SUMMARY.md" <<'SUMMARY'
---
status: complete
---
# Summary
SUMMARY

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "false" ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [[ "$c3_detail" == *"all plans"* ]]
  [[ "$c3_detail" == *"complete"* ]]
}

# ---------------------------------------------------------------------------
# Early archive exit JSON structure
# ---------------------------------------------------------------------------

@test "archive missing STATE.md emits per-check structure in JSON" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  create_test_config

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode archive
  [ "$status" -eq 2 ]

  # Should have per-check entries (not empty checks:{})
  local c1_detail
  c1_detail=$(echo "$output" | jq -r '.checks.state_vs_filesystem.detail')
  [ "$c1_detail" = "not evaluated" ]

  echo "$output" | jq -r '.failed_checks[]' | grep -q "missing_state_md"
}

# ---------------------------------------------------------------------------
# Reverse plan check: on-disk plans not in .execution-state.json
# ---------------------------------------------------------------------------

@test "exec_state reverse check detects on-disk plan not in JSON plans array" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Create execution-state that only mentions one plan
  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'EOF'
{
  "phase": 2,
  "status": "running",
  "plans": [
    {"id": "02-01", "status": "running"}
  ]
}
EOF

  # Add a second plan on disk that is NOT in .plans[]
  echo "# Plan" > "$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api/extra-plan-PLAN.md"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "false" ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [[ "$c3_detail" == *"extra-plan"* ]]
  [[ "$c3_detail" == *"not found in .execution-state.json"* ]]
}

# ---------------------------------------------------------------------------
# Archive mode: unparseable project name
# ---------------------------------------------------------------------------

@test "archive mode fails on unparseable PROJECT.md project name" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Remove the heading from PROJECT.md so project name can't be parsed
  echo "No heading here" > "$TEST_TEMP_DIR/.vbw-planning/PROJECT.md"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode archive
  [ "$status" -eq 2 ]

  local c5_pass
  c5_pass=$(echo "$output" | jq -r '.checks.project_vs_state.pass')
  [ "$c5_pass" = "false" ]

  local c5_detail
  c5_detail=$(echo "$output" | jq -r '.checks.project_vs_state.detail')
  [[ "$c5_detail" == *"unparseable"* ]]
}

@test "advisory mode skips on unparseable PROJECT.md project name" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  echo "No heading here" > "$TEST_TEMP_DIR/.vbw-planning/PROJECT.md"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c5_pass
  c5_pass=$(echo "$output" | jq -r '.checks.project_vs_state.pass')
  [ "$c5_pass" = "true" ]

  local c5_detail
  c5_detail=$(echo "$output" | jq -r '.checks.project_vs_state.detail')
  [[ "$c5_detail" == *"skip"* ]]
}

# ---------------------------------------------------------------------------
# Reverse plan check with empty .plans[] array
# ---------------------------------------------------------------------------

@test "exec_state reverse check runs when plans array is empty" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Create execution-state with empty plans array but on-disk plan exists
  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'EOF'
{
  "phase": 2,
  "status": "running",
  "plans": []
}
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "false" ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  # Should detect on-disk plan not in .plans[] AND "running but no plans"
  [[ "$c3_detail" == *"not found in .execution-state.json"* ]]
}

@test "exec_state reverse check flags bare PLAN.md with empty plans array" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api"
  # Remove numbered plan artifacts, leave only bare PLAN.md
  rm -f "$phase_dir"/*-PLAN.md "$phase_dir"/*-SUMMARY.md
  echo "# Legacy plan" > "$phase_dir/PLAN.md"

  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'EOF'
{
  "phase": 2,
  "status": "running",
  "plans": []
}
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "false" ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [[ "$c3_detail" == *"bare PLAN.md"* ]]
}

@test "exec_state reverse check flags bare PLAN.md alongside named plans" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api"
  # Add a stale bare PLAN.md alongside the numbered plan
  echo "# Legacy plan" > "$phase_dir/PLAN.md"

  # Need exec state so check 3 actually runs
  printf '{"phase":2,"status":"running","plans":[{"id":"02-01","status":"running"}]}\n' > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "false" ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [[ "$c3_detail" == *"bare PLAN.md"* ]]
}

# ---------------------------------------------------------------------------
# ROADMAP references phase with no matching directory
# ---------------------------------------------------------------------------

@test "roadmap references phase with no matching dir fails in archive mode" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Add a phantom phase to ROADMAP that has no directory
  cat >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
### Phase 4: Phantom
- [ ] Phase 4: Phantom
EOF

  # Also update STATE.md to reflect 4 phases so other checks don't interfere
  sed -i.bak 's/Phase: 2 of 3/Phase: 2 of 4/' "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  rm -f "$TEST_TEMP_DIR/.vbw-planning/STATE.md.bak"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode archive
  [ "$status" -eq 2 ]

  local c2_pass
  c2_pass=$(echo "$output" | jq -r '.checks.roadmap_vs_summaries.pass')
  [ "$c2_pass" = "false" ]

  local c2_detail
  c2_detail=$(echo "$output" | jq -r '.checks.roadmap_vs_summaries.detail')
  [[ "$c2_detail" == *"no matching phase directory"* ]]
}

@test "roadmap references phase with no matching dir fails in advisory mode too" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Add a phantom phase to ROADMAP that has no directory
  cat >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
### Phase 4: Phantom
- [ ] Phase 4: Phantom
EOF

  sed -i.bak 's/Phase: 2 of 3/Phase: 2 of 4/' "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  rm -f "$TEST_TEMP_DIR/.vbw-planning/STATE.md.bak"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c2_pass
  c2_pass=$(echo "$output" | jq -r '.checks.roadmap_vs_summaries.pass')
  # Missing phase dir is drift — should be flagged in advisory mode too
  [ "$c2_pass" = "false" ]

  local c2_detail
  c2_detail=$(echo "$output" | jq -r '.checks.roadmap_vs_summaries.detail')
  [[ "$c2_detail" == *"no matching phase directory"* ]]
}

# ---------------------------------------------------------------------------
# Unrecognized status enum detection
# ---------------------------------------------------------------------------

@test "exec_state unrecognized top-level status detected" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'EOF'
{
  "phase": 2,
  "status": "banana",
  "plans": []
}
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "false" ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [[ "$c3_detail" == *"unrecognized"* ]]
  [[ "$c3_detail" == *"banana"* ]]
}

@test "exec_state unrecognized per-plan status detected" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'EOF'
{
  "phase": 2,
  "status": "running",
  "plans": [
    {"id": "02-01", "status": "exploded"}
  ]
}
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "false" ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [[ "$c3_detail" == *"unrecognized"* ]]
  [[ "$c3_detail" == *"exploded"* ]]
}

# ---------------------------------------------------------------------------
# Valid top-level statuses from recover-state.sh
# ---------------------------------------------------------------------------

@test "exec_state accepts failed as valid top-level status" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'EOF'
{
  "phase": 2,
  "status": "failed",
  "plans": [
    {"id": "02-01", "status": "failed"}
  ]
}
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  # Should NOT contain "unrecognized" for top-level status
  [[ "$c3_detail" != *"unrecognized top-level"* ]]
}

@test "exec_state accepts pending as valid top-level status" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'EOF'
{
  "phase": 2,
  "status": "pending",
  "plans": []
}
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  # Should NOT contain "unrecognized" for top-level status
  [[ "$c3_detail" != *"unrecognized top-level"* ]]
}

# ---------------------------------------------------------------------------
# Top-level status coherence: failed / pending
# ---------------------------------------------------------------------------

@test "exec_state fails when top-level failed but no failed plans on disk" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api"
  # Create a "complete" summary for plan 02-01
  printf -- '---\nstatus: complete\n---\n# Summary\n' > "$phase_dir/02-01-SUMMARY.md"

  printf '{"phase":2,"status":"failed","plans":[{"id":"02-01","status":"failed"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "false" ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [[ "$c3_detail" == *"no failed plans"* ]]
}

@test "exec_state passes when top-level failed matches on-disk failed summary" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api"
  printf -- '---\nstatus: failed\n---\n# Summary\n' > "$phase_dir/02-01-SUMMARY.md"

  printf '{"phase":2,"status":"failed","plans":[{"id":"02-01","status":"failed"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [[ "$c3_detail" != *"no failed plans"* ]]
}

@test "exec_state fails when top-level pending but phase has finalized plans" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api"
  printf -- '---\nstatus: complete\n---\n# Summary\n' > "$phase_dir/02-01-SUMMARY.md"

  printf '{"phase":2,"status":"pending","plans":[]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "false" ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [[ "$c3_detail" == *"pending"* ]]
}

# ---------------------------------------------------------------------------
# Per-plan summary frontmatter cross-reference
# ---------------------------------------------------------------------------

@test "exec_state detects per-plan summary frontmatter mismatch" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api"
  # JSON says complete, but summary frontmatter says failed
  printf -- '---\nstatus: failed\n---\n# Summary\n' > "$phase_dir/02-01-SUMMARY.md"

  printf '{"phase":2,"status":"running","plans":[{"id":"02-01","status":"complete"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "false" ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [[ "$c3_detail" == *"SUMMARY.md status"* ]]
}

@test "exec_state detects per-plan summary with no valid frontmatter" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api"
  # Summary with no frontmatter at all
  printf '# Summary\nSome content\n' > "$phase_dir/02-01-SUMMARY.md"

  printf '{"phase":2,"status":"running","plans":[{"id":"02-01","status":"complete"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "false" ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [[ "$c3_detail" == *"no valid frontmatter status"* ]]
}

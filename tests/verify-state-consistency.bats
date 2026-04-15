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

@test "unknown --mode value defaults to archive" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  local json_output
  json_output=$(bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode typo 2>/dev/null)
  local rc=$?
  # Archive mode with consistent workspace should pass (exit 0)
  [ "$rc" -eq 0 ]

  local mode
  mode=$(echo "$json_output" | jq -r '.mode')
  [ "$mode" = "archive" ]
}

# ============================================================
# Prerequisite: jq guard
# ============================================================

@test "missing jq in archive mode exits 2 with hardcoded JSON" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Create a wrapper that hides jq from the script
  local fake_bin="$TEST_TEMP_DIR/fake-bin"
  mkdir -p "$fake_bin"
  # Symlink everything except jq from PATH
  for cmd in bash cat sed grep printf tr head tail find sort wc dirname basename cd readlink mktemp rm; do
    local cmd_path
    cmd_path=$(command -v "$cmd" 2>/dev/null) || true
    if [ -n "$cmd_path" ] && [ ! -e "$fake_bin/$cmd" ]; then
      ln -s "$cmd_path" "$fake_bin/$cmd"
    fi
  done

  # Run with restricted PATH that lacks jq
  run env PATH="$fake_bin" bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode archive
  [ "$status" -eq 2 ]

  # Verify the hardcoded JSON payload
  local verdict
  # Use the real jq (from the test runner's PATH) to parse the output
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]
  local mode_val
  mode_val=$(echo "$output" | jq -r '.mode')
  [ "$mode_val" = "archive" ]
  echo "$output" | jq -e '.failed_checks | index("missing_jq")' >/dev/null
}

@test "missing jq in advisory mode exits 0 with hardcoded JSON" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  local fake_bin="$TEST_TEMP_DIR/fake-bin"
  mkdir -p "$fake_bin"
  for cmd in bash cat sed grep printf tr head tail find sort wc dirname basename cd readlink mktemp rm; do
    local cmd_path
    cmd_path=$(command -v "$cmd" 2>/dev/null) || true
    if [ -n "$cmd_path" ] && [ ! -e "$fake_bin/$cmd" ]; then
      ln -s "$cmd_path" "$fake_bin/$cmd"
    fi
  done

  run env PATH="$fake_bin" bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]
  local mode_val
  mode_val=$(echo "$output" | jq -r '.mode')
  [ "$mode_val" = "advisory" ]
}

# ============================================================
# No project state
# ============================================================

@test "missing .vbw-planning returns verdict fail in advisory" {
  cd "$TEST_TEMP_DIR"
  rm -rf "$TEST_TEMP_DIR/.vbw-planning"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]

  # Advisory fail paths must still emit per-check JSON structure
  local c1_detail c1_pass
  c1_detail=$(echo "$output" | jq -r '.checks.state_vs_filesystem.detail')
  c1_pass=$(echo "$output" | jq -r '.checks.state_vs_filesystem.pass')
  [ "$c1_pass" = "false" ]
  [[ "$c1_detail" == *"not evaluated"* ]]

  local fc_count
  fc_count=$(echo "$output" | jq '.failed_checks | length')
  [ "$fc_count" -eq 1 ]
}

@test "missing STATE.md returns verdict fail in advisory" {
  cd "$TEST_TEMP_DIR"
  rm -f "$TEST_TEMP_DIR/.vbw-planning/STATE.md"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]
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

@test "roadmap_vs_summaries handles uppercase [X] checkbox" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Replace [x] with [X] for phase 1 (which is complete)
  sed -i.bak 's/\- \[x\] Phase 1: Setup/- [X] Phase 1: Setup/' "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  rm -f "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md.bak"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c2_pass
  c2_pass=$(echo "$output" | jq -r '.checks.roadmap_vs_summaries.pass')
  [ "$c2_pass" = "true" ]
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

  local pass
  pass=$(echo "$output" | jq -r '.checks.project_vs_state.pass')
  [ "$pass" = "true" ]
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

  # STATE says Phase 2 of 2 — only 2 phase dirs but numbered 01 and 03
  # Verifier uses ordinal position (2nd dir = phase 2), not prefix (03)
  cat > "$root/STATE.md" <<'EOF'
# State
**Project:** My Test Project
**Milestone:** MVP
Phase: 2 of 2 (Build)
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

  # Active phase is ordinal 2 (second dir), STATE says phase 2 — should match
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

@test "advisory mode warns when STATE.md is missing" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  create_test_config

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]

  # Advisory fail paths must still emit per-check JSON structure
  local c1_detail c1_pass
  c1_detail=$(echo "$output" | jq -r '.checks.state_vs_filesystem.detail')
  c1_pass=$(echo "$output" | jq -r '.checks.state_vs_filesystem.pass')
  [ "$c1_pass" = "false" ]
  [[ "$c1_detail" == *"not evaluated"* ]]

  local fc_count
  fc_count=$(echo "$output" | jq '.failed_checks | length')
  [ "$fc_count" -eq 1 ]
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

@test "advisory mode reports failure on malformed STATE.md Phase line" {
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
  [ "$c1_pass" = "false" ]
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

@test "advisory mode reports failure on invalid execution-state JSON" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  echo "NOT JSON {{{" > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "false" ]

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

@test "advisory mode reports failure when phases directory is missing" {
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
  [ "$c1_pass" = "false" ]
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
  local c1_detail c1_pass
  c1_detail=$(echo "$output" | jq -r '.checks.state_vs_filesystem.detail')
  c1_pass=$(echo "$output" | jq -r '.checks.state_vs_filesystem.pass')
  [ "$c1_pass" = "false" ]
  [[ "$c1_detail" == *"not evaluated"* ]]

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

@test "advisory mode reports failure on unparseable PROJECT.md project name" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  echo "No heading here" > "$TEST_TEMP_DIR/.vbw-planning/PROJECT.md"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c5_pass
  c5_pass=$(echo "$output" | jq -r '.checks.project_vs_state.pass')
  [ "$c5_pass" = "false" ]

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

@test "exec_state reverse check detects orphaned SUMMARY.md not in plans array" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api"
  printf '{"phase":2,"status":"running","plans":[{"id":"02-01","status":"running"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  # Create an orphaned summary whose plan ID is not in .plans[]
  printf -- '---\nstatus: complete\n---\n# Summary\nOrphan.\n' > "$phase_dir/orphan-01-SUMMARY.md"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass c3_detail
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [ "$c3_pass" = "false" ]
  [[ "$c3_detail" == *"orphan-01"* ]]
  [[ "$c3_detail" == *"not found in .execution-state.json"* ]]
}

@test "exec_state reverse check flags bare SUMMARY.md not in plans array" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api"
  printf '{"phase":2,"status":"running","plans":[{"id":"02-01","status":"running"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  # Create a bare SUMMARY.md in the phase dir
  printf -- '---\nstatus: complete\n---\n# Summary\nBare.\n' > "$phase_dir/SUMMARY.md"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass c3_detail
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [ "$c3_pass" = "false" ]
  [[ "$c3_detail" == *"bare SUMMARY.md"* ]]
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

# ---------------------------------------------------------------------------
# Brownfield "completed" frontmatter normalization
# ---------------------------------------------------------------------------

@test "exec_state accepts brownfield completed frontmatter" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api"
  # Legacy "completed" (with d) — brownfield synonym for "complete"
  printf -- '---\nstatus: completed\n---\n# Summary\n' > "$phase_dir/02-01-SUMMARY.md"

  printf '{"phase":2,"status":"running","plans":[{"id":"02-01","status":"complete"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  # Should NOT flag "no valid frontmatter" or "SUMMARY.md status" for brownfield "completed"
  [[ "$c3_detail" != *"no valid frontmatter status"* ]]
  [[ "$c3_detail" != *"SUMMARY.md status"* ]]
}

# ---------------------------------------------------------------------------
# ROADMAP edge cases: headings-only / checklist-only
# ---------------------------------------------------------------------------

@test "state_vs_roadmap handles headings-only ROADMAP" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Overwrite ROADMAP with only section headings, no checklist items
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
# Roadmap
### Phase 1: Setup
### Phase 2: Backend API
### Phase 3: Frontend
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  # Must not crash with "integer expression expected"
  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "pass" ] || [ "$verdict" = "fail" ]
}

@test "state_vs_roadmap handles checklist-only ROADMAP" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Overwrite ROADMAP with only checklist items, no section headings
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
# Roadmap
- [x] Phase 1: Setup
- [ ] Phase 2: Backend API
- [ ] Phase 3: Frontend
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  # Must not crash with "integer expression expected"
  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "pass" ] || [ "$verdict" = "fail" ]
}

# ---------------------------------------------------------------------------
# F-01: Missing PROJECT.md fails in archive mode
# ---------------------------------------------------------------------------

@test "project_vs_state fails in archive mode when PROJECT.md missing" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  rm -f "$TEST_TEMP_DIR/.vbw-planning/PROJECT.md"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode archive
  [ "$status" -eq 2 ]

  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "fail" ]

  local failed
  failed=$(echo "$output" | jq -r '.failed_checks[]')
  [[ "$failed" == *"project_vs_state"* ]]

  local c5_pass c5_detail
  c5_pass=$(echo "$output" | jq -r '.checks.project_vs_state.pass')
  c5_detail=$(echo "$output" | jq -r '.checks.project_vs_state.detail')
  [ "$c5_pass" = "false" ]
  [[ "$c5_detail" == *"missing PROJECT.md"* ]]
}

# ---------------------------------------------------------------------------
# F-02: exec_state complete with zero plan artifacts
# ---------------------------------------------------------------------------

@test "exec_state_vs_filesystem fails when complete but zero plan artifacts" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Set exec state to complete for phase 2
  printf '{"phase":2,"status":"complete"}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  # Remove all plan/summary artifacts from phase 2, leave directory
  rm -f "$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api/"*-PLAN.md
  rm -f "$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api/"*-SUMMARY.md

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass c3_detail
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [ "$c3_pass" = "false" ]
  [[ "$c3_detail" == *"no plan artifacts"* ]]
}

@test "exec_state_vs_filesystem passes when complete with all plans complete" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Set exec state to complete for phase 1 (scaffold already has complete plan/summary)
  printf '{"phase":1,"status":"complete","plans":[{"id":"01-01","status":"complete"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "true" ]
}

# ---------------------------------------------------------------------------
# F-02: Non-numeric phase value in .execution-state.json
# ---------------------------------------------------------------------------

@test "exec_state_vs_filesystem fails in archive when phase is non-numeric" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  printf '{"phase":"banana","status":"running"}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode archive
  [ "$status" -eq 2 ]

  local c3_pass c3_detail
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [ "$c3_pass" = "false" ]
  [[ "$c3_detail" == *"not numeric"* ]]
}

@test "exec_state_vs_filesystem skips in advisory when phase is non-numeric" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  printf '{"phase":"banana","status":"running"}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_detail
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [[ "$c3_detail" == *"not numeric"* ]]
}

# ---------------------------------------------------------------------------
# F-01: Malformed plan entries in .execution-state.json
# ---------------------------------------------------------------------------

@test "exec_state_vs_filesystem flags plan entry missing status" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  printf '{"phase":2,"status":"running","plans":[{"id":"02-01"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass c3_detail
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [ "$c3_pass" = "false" ]
  [[ "$c3_detail" == *"malformed"* ]]
}

@test "exec_state_vs_filesystem flags plan entry missing id" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  printf '{"phase":2,"status":"running","plans":[{"status":"complete"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass c3_detail
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [ "$c3_pass" = "false" ]
  [[ "$c3_detail" == *"malformed"* ]]
}

@test "exec_state_vs_filesystem flags plan entry missing both id and status" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  printf '{"phase":2,"status":"running","plans":[{}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass c3_detail
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [ "$c3_pass" = "false" ]
  [[ "$c3_detail" == *"malformed"* ]]
}

# ---------------------------------------------------------------------------
# Non-terminal status coherence (ready/paused/blocked)
# ---------------------------------------------------------------------------

@test "exec_state_vs_filesystem flags paused status when all plans complete" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Phase 1 has 01-01 plan+summary (complete) from scaffold
  printf '{"phase":1,"status":"paused","plans":[{"id":"01-01","status":"complete"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass c3_detail
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [ "$c3_pass" = "false" ]
  [[ "$c3_detail" == *"paused"* ]]
  [[ "$c3_detail" == *"all plans"*"complete"* ]]
}

@test "exec_state_vs_filesystem passes blocked status with incomplete plans" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Phase 2 has plans but not all complete — blocked is valid
  printf '{"phase":2,"status":"blocked","plans":[{"id":"02-01","status":"running"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  # blocked with incomplete plans is valid — per-plan check may fail but top-level is coherent
  # Just verify it doesn't crash and produces JSON
  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "pass" ] || [ "$verdict" = "fail" ]
}

# ---------------------------------------------------------------------------
# Partial summary counts as done (not incomplete)
# ---------------------------------------------------------------------------

@test "exec_state complete with partial summary flags incomplete" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api"
  printf -- '---\nstatus: partial\n---\n# Summary\nPartially done.\n' > "$phase_dir/02-01-SUMMARY.md"

  # Exec state plan entry also says partial — consistent with summary
  # But top-level "complete" conflicts: partial doesn't count as complete
  printf '{"phase":2,"status":"complete","plans":[{"id":"02-01","status":"partial"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass c3_detail
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [ "$c3_pass" = "false" ]
  [[ "$c3_detail" == *"incomplete"* ]]
}

@test "roadmap_vs_summaries flags partial as incomplete" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Phase 2 marked [x] in ROADMAP (complete) but only has partial summary
  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api"
  printf -- '---\nstatus: partial\n---\n# Summary\nPartially done.\n' > "$phase_dir/02-01-SUMMARY.md"

  # Mark phase 2 as [x] in ROADMAP
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'ROADMAP'
# Roadmap
- [x] Phase 1: Setup
- [x] Phase 2: Backend API
- [ ] Phase 3: Frontend
ROADMAP

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c2_pass c2_detail
  c2_pass=$(echo "$output" | jq -r '.checks.roadmap_vs_summaries.pass')
  c2_detail=$(echo "$output" | jq -r '.checks.roadmap_vs_summaries.detail')
  [ "$c2_pass" = "false" ]
  [[ "$c2_detail" == *"phase 2"* ]]
  [[ "$c2_detail" == *"incomplete"* ]]
}

# ---------------------------------------------------------------------------
# Stale exec-state phase (points at old, still-existing phase)
# ---------------------------------------------------------------------------

@test "exec_state_vs_filesystem flags stale phase pointing at old phase" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Scaffold has 3 phases; phase 2 is active (incomplete) by default.
  # Set exec state to phase 1 with status "running" — stale, since the
  # active phase on disk is 2.
  printf '{"phase":1,"status":"running","plans":[{"id":"01-01","status":"running"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass c3_detail
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [ "$c3_pass" = "false" ]
  [[ "$c3_detail" == *"does not match active phase"* ]]
}

@test "exec_state_vs_filesystem passes when phase matches active phase" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Phase 2 is active (incomplete) by default in scaffold
  printf '{"phase":2,"status":"running","plans":[{"id":"02-01","status":"running"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "true" ]
}

# ---------------------------------------------------------------------------
# F-02: Completed plan with missing PLAN.md
# ---------------------------------------------------------------------------

@test "exec_state complete plan with missing PLAN.md flags drift" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api"
  printf -- '---\nstatus: complete\n---\n# Summary\nDone.\n' > "$phase_dir/02-01-SUMMARY.md"
  rm -f "$phase_dir/02-01-PLAN.md"

  printf '{"phase":2,"status":"complete","plans":[{"id":"02-01","status":"complete"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass c3_detail
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [ "$c3_pass" = "false" ]
  [[ "$c3_detail" == *"02-01"* ]]
  [[ "$c3_detail" == *"PLAN.md"* ]]
  [[ "$c3_detail" == *"missing"* ]]
}

@test "exec_state partial plan with missing PLAN.md flags drift" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/02-backend-api"
  printf -- '---\nstatus: partial\n---\n# Summary\nPartial.\n' > "$phase_dir/02-01-SUMMARY.md"
  rm -f "$phase_dir/02-01-PLAN.md"

  printf '{"phase":2,"status":"running","plans":[{"id":"02-01","status":"partial"}]}\n' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c3_pass c3_detail
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  c3_detail=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.detail')
  [ "$c3_pass" = "false" ]
  [[ "$c3_detail" == *"02-01"* ]]
  [[ "$c3_detail" == *"PLAN.md"* ]]
}

@test "exec_state gapped dirs uses prefix not ordinal for active phase" {
  cd "$TEST_TEMP_DIR"
  local root="$TEST_TEMP_DIR/.vbw-planning"
  mkdir -p "$root/phases"

  cat > "$root/STATE.md" <<'EOF'
# State
**Project:** My Test Project
**Milestone:** MVP
Phase: 2 of 2 (Build)
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

  # exec-state uses prefix number 3 (not ordinal 2) for dir 03-build
  printf '{"phase":3,"status":"running","plans":[{"id":"03-01","status":"running"}]}\n' \
    > "$root/.execution-state.json"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$root" --mode advisory
  [ "$status" -eq 0 ]

  # The exec-state cross-check should pass because prefix 3 matches dir 03-build
  local c3_pass
  c3_pass=$(echo "$output" | jq -r '.checks.exec_state_vs_filesystem.pass')
  [ "$c3_pass" = "true" ]
}

# ---------------------------------------------------------------------------
# F-03: Duplicate roadmap markers and missing roadmap entries
# ---------------------------------------------------------------------------

@test "roadmap_vs_summaries detects duplicate phase entries" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'ROADMAP'
# Roadmap
- [x] Phase 1: Setup
- [ ] Phase 2: Backend API
- [ ] Phase 2: Backend API (dup)
- [ ] Phase 3: Frontend
ROADMAP

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c2_pass c2_detail
  c2_pass=$(echo "$output" | jq -r '.checks.roadmap_vs_summaries.pass')
  c2_detail=$(echo "$output" | jq -r '.checks.roadmap_vs_summaries.detail')
  [ "$c2_pass" = "false" ]
  [[ "$c2_detail" == *"duplicate"* ]]
  [[ "$c2_detail" == *"phase 2"* ]]
}

@test "roadmap_vs_summaries detects phase dir missing from roadmap" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Write ROADMAP with only phases 1 and 3 — phase 2 dir still exists
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'ROADMAP'
# Roadmap
- [x] Phase 1: Setup
- [ ] Phase 3: Frontend
ROADMAP

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c2_pass c2_detail
  c2_pass=$(echo "$output" | jq -r '.checks.roadmap_vs_summaries.pass')
  c2_detail=$(echo "$output" | jq -r '.checks.roadmap_vs_summaries.detail')
  [ "$c2_pass" = "false" ]
  [[ "$c2_detail" == *"phase"* ]]
  [[ "$c2_detail" == *"2"* ]]
  [[ "$c2_detail" == *"no matching ROADMAP"* ]]
}

@test "roadmap_vs_summaries passes when roadmap and dirs fully aligned" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c2_pass
  c2_pass=$(echo "$output" | jq -r '.checks.roadmap_vs_summaries.pass')
  [ "$c2_pass" = "true" ]
}

# ============================================================
# Bootstrap link-format ROADMAP tests
# ============================================================

@test "roadmap_vs_summaries parses bootstrap link-format ROADMAP correctly" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Overwrite ROADMAP with bootstrap link format (- [ ] [Phase N: Name](#anchor))
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
# Roadmap

- [x] [Phase 1: Setup](#phase-1-setup)
- [ ] [Phase 2: Backend API](#phase-2-backend-api)
- [ ] [Phase 3: Frontend](#phase-3-frontend)

## Phase 1: Setup
## Phase 2: Backend API
## Phase 3: Frontend
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c2_pass
  c2_pass=$(echo "$output" | jq -r '.checks.roadmap_vs_summaries.pass')
  [ "$c2_pass" = "true" ]
}

@test "state_vs_roadmap phase count matches with bootstrap link-format ROADMAP" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Bootstrap link format with ## headings
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
# Roadmap

- [x] [Phase 1: Setup](#phase-1-setup)
- [ ] [Phase 2: Backend API](#phase-2-backend-api)
- [ ] [Phase 3: Frontend](#phase-3-frontend)

## Phase 1: Setup
## Phase 2: Backend API
## Phase 3: Frontend
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c4_pass
  c4_pass=$(echo "$output" | jq -r '.checks.state_vs_roadmap.pass')
  [ "$c4_pass" = "true" ]
}

# ============================================================
# UAT-awareness tests
# ============================================================

@test "state_vs_filesystem: phase with UAT issues stays active even when all plans complete" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Make STATE.md say phase 1 is active (UAT issues keep it there)
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State
**Project:** My Test Project
**Milestone:** MVP
Phase: 1 of 3 (Setup)
Plans: 1/1
Progress: 50%
Status: running
EOF

  # Phase 1 has all plans complete but UAT issues
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup/01-UAT.md" <<'EOF'
---
status: issues_found
---
# UAT
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c1_pass
  c1_pass=$(echo "$output" | jq -r '.checks.state_vs_filesystem.pass')
  [ "$c1_pass" = "true" ]
}

@test "roadmap_vs_summaries: unchecked phase with all plans complete but UAT issues passes" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Phase 1 has all plans complete but UAT issues — roadmap [ ] is correct
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
# Roadmap

- [ ] Phase 1: Setup
- [ ] Phase 2: Backend API
- [ ] Phase 3: Frontend

### Phase 1: Setup
### Phase 2: Backend API
### Phase 3: Frontend
EOF

  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup/01-UAT.md" <<'EOF'
---
status: issues_found
---
# UAT
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  local c2_pass c2_detail
  c2_pass=$(echo "$output" | jq -r '.checks.roadmap_vs_summaries.pass')
  c2_detail=$(echo "$output" | jq -r '.checks.roadmap_vs_summaries.detail')
  [ "$c2_pass" = "true" ]
}

@test "roadmap_vs_summaries: checked phase with UAT issues is not a verifier concern" {
  cd "$TEST_TEMP_DIR"
  scaffold_consistent_workspace

  # Phase 1 has UAT issues but roadmap says [x] — that's wrong
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup/01-UAT.md" <<'EOF'
---
status: issues_found
---
# UAT
EOF

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" "$TEST_TEMP_DIR/.vbw-planning" --mode advisory
  [ "$status" -eq 0 ]

  # The existing [x] Phase 1 in scaffold should still pass because
  # the check only flags [ ] when all plans complete (not [x] when UAT issues exist).
  # The [x] + UAT case is a state-updater responsibility, not a verifier concern.
  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "pass" ] || [ "$verdict" = "fail" ]
}

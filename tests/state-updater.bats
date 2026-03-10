#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

create_state_and_roadmap() {
  local root="$1"
  local phase_num="$2"

  cat > "$root/STATE.md" <<EOF
Phase: ${phase_num} of 4 (Service Utility Tests)
Plans: 0/0
Progress: 0%
Status: pending
EOF

  cat > "$root/ROADMAP.md" <<EOF
- [ ] Phase ${phase_num}: Service Utility Tests

| Phase | Progress | Status | Completed |
|------|----------|--------|-----------|
| ${phase_num} - Service Utility Tests | 0/0 | pending | - |
EOF
}

@test "summary update advances STATE/ROADMAP without execution-state file" {
  cd "$TEST_TEMP_DIR"
  create_state_and_roadmap "$TEST_TEMP_DIR/.vbw-planning" 3

  mkdir -p .vbw-planning/phases/03-service-utility-tests
  echo "# plan" > .vbw-planning/phases/03-service-utility-tests/03-01-PLAN.md
  cat > .vbw-planning/phases/03-service-utility-tests/03-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
# Summary
SUMMARY

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.vbw-planning/phases/03-service-utility-tests/03-01-SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  grep -q '^Plans: 1/1$' .vbw-planning/STATE.md
  grep -q '^Progress: 100%$' .vbw-planning/STATE.md
  grep -q '^- \[x\] Phase 3: Service Utility Tests$' .vbw-planning/ROADMAP.md
  grep -Eq '^\| 3 - Service Utility Tests \| 1/1 \| complete \| [0-9]{4}-[0-9]{2}-[0-9]{2} \|$' .vbw-planning/ROADMAP.md
}

@test "summary update patches execution state in .plans[] schema" {
  cd "$TEST_TEMP_DIR"
  create_state_and_roadmap "$TEST_TEMP_DIR/.vbw-planning" 3

  mkdir -p .vbw-planning/phases/03-service-utility-tests
  echo "# plan" > .vbw-planning/phases/03-service-utility-tests/03-01-PLAN.md
  cat > .vbw-planning/phases/03-service-utility-tests/03-01-SUMMARY.md <<'EOF'
---
phase: 3
plan: 1
status: complete
---

# Summary
EOF

  cat > .vbw-planning/.execution-state.json <<'EOF'
{
  "phase": 3,
  "phase_name": "service-utility-tests",
  "status": "running",
  "wave": 1,
  "total_waves": 1,
  "plans": [
    {"id": "03-01", "title": "test", "wave": 1, "status": "pending"}
  ]
}
EOF

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.vbw-planning/phases/03-service-utility-tests/03-01-SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]
  jq -e '.plans[0].status == "complete"' .vbw-planning/.execution-state.json >/dev/null
}

@test "PLAN trigger supports NN-PLAN naming and flips status ready to active" {
  cd "$TEST_TEMP_DIR"
  create_state_and_roadmap "$TEST_TEMP_DIR/.vbw-planning" 2
  sed -i.bak 's/^Status: .*/Status: ready/' .vbw-planning/STATE.md && rm -f .vbw-planning/STATE.md.bak

  mkdir -p .vbw-planning/phases/02-compat
  echo "# plan" > .vbw-planning/phases/02-compat/01-PLAN.md

  local plan_path input
  plan_path="$TEST_TEMP_DIR/.vbw-planning/phases/02-compat/01-PLAN.md"
  input=$(jq -nc --arg p "$plan_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  grep -q '^Plans: 0/1$' .vbw-planning/STATE.md
  grep -q '^Status: active$' .vbw-planning/STATE.md
}

@test "summary update is milestone-aware for state, roadmap, and execution-state" {
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/milestones/m1/phases/03-service-utility-tests

  # Root files should remain untouched
  cat > .vbw-planning/STATE.md <<'EOF'
Phase: 3 of 4 (Root)
Plans: 9/9
Progress: 100%
Status: complete
EOF
  cat > .vbw-planning/ROADMAP.md <<'EOF'
- [x] Phase 3: Root
| Phase | Progress | Status | Completed |
|------|----------|--------|-----------|
| 3 - Root | 9/9 | complete | 2026-01-01 |
EOF
  cat > .vbw-planning/.execution-state.json <<'EOF'
{"plans":[{"id":"03-01","status":"pending"}]}
EOF

  create_state_and_roadmap "$TEST_TEMP_DIR/.vbw-planning/milestones/m1" 3
  cat > .vbw-planning/milestones/m1/.execution-state.json <<'EOF'
{"plans":[{"id":"03-01","status":"pending"}]}
EOF

  echo "# plan" > .vbw-planning/milestones/m1/phases/03-service-utility-tests/03-01-PLAN.md
  cat > .vbw-planning/milestones/m1/phases/03-service-utility-tests/03-01-SUMMARY.md <<'EOF'
---
phase: 3
plan: 1
status: complete
---

# Summary
EOF

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.vbw-planning/milestones/m1/phases/03-service-utility-tests/03-01-SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  grep -q '^Plans: 1/1$' .vbw-planning/milestones/m1/STATE.md
  grep -q '^Plans: 9/9$' .vbw-planning/STATE.md

  jq -e '.plans[0].status == "complete"' .vbw-planning/milestones/m1/.execution-state.json >/dev/null
  jq -e '.plans[0].status == "pending"' .vbw-planning/.execution-state.json >/dev/null
}

@test "advance_phase sets needs_remediation when next phase has UAT issues" {
  cd "$TEST_TEMP_DIR"

  # Create 2 phases: phase 1 complete, phase 2 has UAT issues
  mkdir -p .vbw-planning/phases/01-setup
  mkdir -p .vbw-planning/phases/02-core

  cat > .vbw-planning/STATE.md <<'EOF'
Phase: 1 of 2 (Setup)
Plans: 0/1
Progress: 0%
Status: active
EOF

  cat > .vbw-planning/ROADMAP.md <<'EOF'
- [ ] Phase 1: Setup
- [ ] Phase 2: Core

| Phase | Progress | Status | Completed |
|------|----------|--------|-----------|
| 1 - Setup | 0/1 | active | - |
| 2 - Core | 0/0 | pending | - |
EOF

  # Phase 1: one plan, one summary (complete)
  echo "# plan" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
# summary
SUMMARY

  # Phase 2: one plan, one summary (complete), but has UAT issues
  echo "# plan" > .vbw-planning/phases/02-core/02-01-PLAN.md
  cat > .vbw-planning/phases/02-core/02-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
# summary
SUMMARY
  cat > .vbw-planning/phases/02-core/02-01-UAT.md <<'EOF'
---
status: issues_found
---

# UAT Issues
- Something broken
EOF

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup/01-01-SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  grep -q '^Status: needs_remediation$' .vbw-planning/STATE.md
  grep -q '^Phase: 2 of 2 (Core)$' .vbw-planning/STATE.md
}

@test "advance_phase ignores indented body status lines via shared uat-utils" {
  cd "$TEST_TEMP_DIR"

  # Create 2 phases: phase 1 complete, phase 2 has UAT with indented body status
  mkdir -p .vbw-planning/phases/01-setup
  mkdir -p .vbw-planning/phases/02-core

  cat > .vbw-planning/STATE.md <<'EOF'
Phase: 1 of 2 (Setup)
Plans: 0/1
Progress: 0%
Status: active
EOF

  cat > .vbw-planning/ROADMAP.md <<'EOF'
- [ ] Phase 1: Setup
- [ ] Phase 2: Core

| Phase | Progress | Status | Completed |
|------|----------|--------|-----------|
| 1 - Setup | 0/1 | active | - |
| 2 - Core | 0/0 | pending | - |
EOF

  echo "# plan" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
# summary
SUMMARY

  # Phase 2: complete but UAT has only indented status (should NOT be detected)
  echo "# plan" > .vbw-planning/phases/02-core/02-01-PLAN.md
  cat > .vbw-planning/phases/02-core/02-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
# summary
SUMMARY
  cat > .vbw-planning/phases/02-core/02-UAT.md <<'EOF'
---
phase: 02
---
Some UAT notes
  status: issues_found
EOF

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup/01-01-SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  # Indented body status should be ignored — all phases are complete
  grep -q '^Status: complete$' .vbw-planning/STATE.md
}

@test "advance_phase skips SOURCE-UAT files via shared uat-utils" {
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/phases/01-setup
  mkdir -p .vbw-planning/phases/02-core

  cat > .vbw-planning/STATE.md <<'EOF'
Phase: 1 of 2 (Setup)
Plans: 0/1
Progress: 0%
Status: active
EOF

  cat > .vbw-planning/ROADMAP.md <<'EOF'
- [ ] Phase 1: Setup
- [ ] Phase 2: Core

| Phase | Progress | Status | Completed |
|------|----------|--------|-----------|
| 1 - Setup | 0/1 | active | - |
| 2 - Core | 0/0 | pending | - |
EOF

  echo "# plan" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
# summary
SUMMARY
  echo "# plan" > .vbw-planning/phases/02-core/02-01-PLAN.md
  cat > .vbw-planning/phases/02-core/02-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
# summary
SUMMARY

  # Only SOURCE-UAT with issues — should be skipped by latest_non_source_uat
  cat > .vbw-planning/phases/02-core/02-SOURCE-UAT.md <<'EOF'
---
phase: 02
status: issues_found
---
Old issues from archive
EOF

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup/01-01-SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  # SOURCE-UAT should be ignored — all phases should be complete
  grep -q '^Status: complete$' .vbw-planning/STATE.md
}
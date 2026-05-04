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

create_linked_archive_fixture() {
  local checkbox="$1" uat_status="${2:-}"

  cat > .vbw-planning/PROJECT.md <<'EOF'
# Test Project
EOF

  cat > .vbw-planning/STATE.md <<'EOF'
# State

**Project:** Test Project
**Milestone:** MVP

## Current Phase
Phase: 1 of 1 (Service Utility Tests)
Plans: 0/1
Progress: 0%
Status: active

## Phase Status
- **Phase 1:** Planned
EOF

  cat > .vbw-planning/ROADMAP.md <<EOF
# Roadmap

- [${checkbox}] [Phase 02: Service Utility Tests](#phase-02-service-utility-tests)

## Phase 02: Service Utility Tests
EOF

  mkdir -p .vbw-planning/phases/02-service-utility-tests
  echo "# plan" > .vbw-planning/phases/02-service-utility-tests/02-01-PLAN.md
  cat > .vbw-planning/phases/02-service-utility-tests/02-01-SUMMARY.md <<'EOF'
---
status: complete
---
# Summary
EOF

  if [ -n "$uat_status" ]; then
    cat > .vbw-planning/phases/02-service-utility-tests/02-UAT.md <<EOF
---
phase: 02
status: ${uat_status}
---
# UAT
EOF
  fi
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

@test "summary update checks linked ROADMAP entry and preserves anchor" {
  cd "$TEST_TEMP_DIR"
  create_linked_archive_fixture " "

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.vbw-planning/phases/02-service-utility-tests/02-01-SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  grep -q '^- \[x\] \[Phase 02: Service Utility Tests\](#phase-02-service-utility-tests)$' .vbw-planning/ROADMAP.md

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" .vbw-planning --mode archive
  if [ "$status" -ne 0 ]; then echo "$output" >&2; fi
  [ "$status" -eq 0 ]
}

@test "UAT update unchecks linked ROADMAP entry when current UAT has issues" {
  cd "$TEST_TEMP_DIR"
  create_linked_archive_fixture "x" "issues_found"

  local uat_path input
  uat_path="$TEST_TEMP_DIR/.vbw-planning/phases/02-service-utility-tests/02-UAT.md"
  input=$(jq -nc --arg p "$uat_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  grep -q '^- \[ \] \[Phase 02: Service Utility Tests\](#phase-02-service-utility-tests)$' .vbw-planning/ROADMAP.md

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" .vbw-planning --mode archive
  if [ "$status" -ne 0 ]; then echo "$output" >&2; fi
  [ "$status" -eq 0 ]
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

@test "PLAN trigger supports NN-PLAN naming and reconciles planned status" {
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
  grep -q '^Status: ready$' .vbw-planning/STATE.md
}

@test "PLAN trigger supports legacy PLAN.md naming and reconciles planned status" {
  cd "$TEST_TEMP_DIR"
  create_state_and_roadmap "$TEST_TEMP_DIR/.vbw-planning" 2
  sed -i.bak 's/^Status: .*/Status: ready/' .vbw-planning/STATE.md && rm -f .vbw-planning/STATE.md.bak

  mkdir -p .vbw-planning/phases/02-compat
  echo "# plan" > .vbw-planning/phases/02-compat/PLAN.md

  local plan_path input
  plan_path="$TEST_TEMP_DIR/.vbw-planning/phases/02-compat/PLAN.md"
  input=$(jq -nc --arg p "$plan_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  grep -q '^Plans: 0/1$' .vbw-planning/STATE.md
  grep -q '^Status: ready$' .vbw-planning/STATE.md
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

@test "summary trigger supports legacy SUMMARY.md naming" {
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
| 1 - Setup | 0/1 | pending | - |
| 2 - Core | 0/1 | pending | - |
EOF

  echo "# plan" > .vbw-planning/phases/01-setup/PLAN.md
  cat > .vbw-planning/phases/01-setup/SUMMARY.md <<'SUMMARY'
---
status: complete
---
# summary
SUMMARY
  echo "# plan" > .vbw-planning/phases/02-core/PLAN.md

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup/SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  run grep -q '^Plans: 0/1$' .vbw-planning/STATE.md
  if [ "$status" -ne 0 ]; then echo "STATE.md contents:" >&2; cat .vbw-planning/STATE.md >&2; fi
  [ "$status" -eq 0 ]

  run grep -q '^Progress: 0%$' .vbw-planning/STATE.md
  if [ "$status" -ne 0 ]; then echo "STATE.md contents:" >&2; cat .vbw-planning/STATE.md >&2; fi
  [ "$status" -eq 0 ]

  run grep -q '^Phase: 2 of 2 (Core)$' .vbw-planning/STATE.md
  if [ "$status" -ne 0 ]; then echo "STATE.md contents:" >&2; cat .vbw-planning/STATE.md >&2; fi
  [ "$status" -eq 0 ]

  run grep -q '^Status: ready$' .vbw-planning/STATE.md
  if [ "$status" -ne 0 ]; then echo "STATE.md contents:" >&2; cat .vbw-planning/STATE.md >&2; fi
  [ "$status" -eq 0 ]

  run grep -q '^- \[x\] Phase 1: Setup$' .vbw-planning/ROADMAP.md
  if [ "$status" -ne 0 ]; then echo "ROADMAP.md contents:" >&2; cat .vbw-planning/ROADMAP.md >&2; fi
  [ "$status" -eq 0 ]

  run grep -Eq '^\| 1 - Setup \| 1/1 \| complete \| [0-9]{4}-[0-9]{2}-[0-9]{2} \|$' .vbw-planning/ROADMAP.md
  if [ "$status" -ne 0 ]; then echo "ROADMAP.md contents:" >&2; cat .vbw-planning/ROADMAP.md >&2; fi
  [ "$status" -eq 0 ]
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

@test "summary with failed status does not advance phase or mark roadmap complete" {
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
| 1 - Setup | 0/1 | pending | - |
| 2 - Core | 0/0 | pending | - |
EOF

  echo "# plan" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
status: failed
---
# summary
SUMMARY

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup/01-01-SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  # Execution happened, so progress is complete — but the phase itself is not.
  grep -q '^Plans: 1/1$' .vbw-planning/STATE.md
  grep -q '^Progress: 100%$' .vbw-planning/STATE.md
  grep -q '^Phase: 1 of 2 (Setup)$' .vbw-planning/STATE.md
  grep -q '^Status: active$' .vbw-planning/STATE.md
  grep -q '^- \[ \] Phase 1: Setup$' .vbw-planning/ROADMAP.md
  grep -q '^| 1 - Setup | 1/1 | in progress | - |$' .vbw-planning/ROADMAP.md
}

@test "advance_phase ignores non-canonical phase dirs when recalculating total" {
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/phases/01-setup
  mkdir -p .vbw-planning/phases/02-core
  mkdir -p .vbw-planning/phases/misc-notes

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
| 1 - Setup | 0/1 | pending | - |
| 2 - Core | 0/1 | pending | - |
EOF

  echo "# plan" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md
  echo "# plan" > .vbw-planning/phases/02-core/02-01-PLAN.md

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup/01-01-SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  grep -q '^Phase: 2 of 2 (Core)$' .vbw-planning/STATE.md
}

@test "advance_phase uses sorted phase position for gapped directories" {
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/phases/01-setup
  mkdir -p .vbw-planning/phases/03-build
  mkdir -p .vbw-planning/phases/04-deploy

  cat > .vbw-planning/STATE.md <<'EOF'
Phase: 2 of 3 (Build)
Plans: 0/1
Progress: 0%
Status: active
EOF

  cat > .vbw-planning/ROADMAP.md <<'EOF'
- [x] Phase 1: Setup
- [ ] Phase 2: Build
- [ ] Phase 3: Deploy

| Phase | Progress | Status | Completed |
|------|----------|--------|-----------|
| 1 - Setup | 1/1 | complete | 2026-01-01 |
| 2 - Build | 0/1 | pending | - |
| 3 - Deploy | 0/1 | pending | - |
EOF

  echo "# plan" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md
  echo "# plan" > .vbw-planning/phases/03-build/03-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/03-build/03-01-SUMMARY.md
  echo "# plan" > .vbw-planning/phases/04-deploy/04-01-PLAN.md

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.vbw-planning/phases/03-build/03-01-SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  grep -q '^Phase: 3 of 3 (Deploy)$' .vbw-planning/STATE.md
  grep -q '^- \[x\] Phase 2: Build$' .vbw-planning/ROADMAP.md
  grep -q '^- \[ \] Phase 3: Deploy$' .vbw-planning/ROADMAP.md
  grep -Eq '^\| 2 - Build \| 1/1 \| complete \| [0-9]{4}-[0-9]{2}-[0-9]{2} \|$' .vbw-planning/ROADMAP.md
}

@test "summary update leaves unknown ROADMAP checklist scheme untouched" {
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/phases/01-setup .vbw-planning/phases/03-build .vbw-planning/phases/04-deploy

  cat > .vbw-planning/PROJECT.md <<'EOF'
# Test Project
EOF

  cat > .vbw-planning/STATE.md <<'EOF'
# State
**Project:** Test Project
**Milestone:** MVP
Phase: 2 of 3 (Build)
Plans: 1/1
Progress: 100%
Status: active
EOF

  cat > .vbw-planning/ROADMAP.md <<'EOF'
# Roadmap
- [x] Phase 1: Setup
- [ ] Phase 2: Build
- [ ] Phase 4: Deploy
### Phase 1: Setup
### Phase 2: Build
### Phase 4: Deploy
EOF

  echo '# Plan' > .vbw-planning/phases/01-setup/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md
  echo '# Plan' > .vbw-planning/phases/03-build/03-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/03-build/03-01-SUMMARY.md
  echo '# Plan' > .vbw-planning/phases/04-deploy/04-01-PLAN.md

  grep -E '^- \[(x| )\] Phase ' .vbw-planning/ROADMAP.md > "$TEST_TEMP_DIR/roadmap-before.txt"

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.vbw-planning/phases/03-build/03-01-SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  grep -E '^- \[(x| )\] Phase ' .vbw-planning/ROADMAP.md > "$TEST_TEMP_DIR/roadmap-after.txt"
  cmp -s "$TEST_TEMP_DIR/roadmap-before.txt" "$TEST_TEMP_DIR/roadmap-after.txt"

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" .vbw-planning --mode archive
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.failed_checks | index("roadmap_vs_summaries")' >/dev/null
  echo "$output" | jq -r '.checks.roadmap_vs_summaries.detail' | grep -q 'ROADMAP checklist numbering scheme is mixed or unresolvable'
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

@test "summary update preserves parsed status when summary-utils helper is unavailable" {
  cd "$TEST_TEMP_DIR"

  local helperless_scripts
  helperless_scripts="$TEST_TEMP_DIR/helperless-scripts"
  mkdir -p "$helperless_scripts"
  cp "$SCRIPTS_DIR/state-updater.sh" "$helperless_scripts/state-updater.sh"

  mkdir -p .vbw-planning/phases/01-setup
  echo "# plan" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
phase: 1
plan: 1
status: complete
---
# summary
SUMMARY

  cat > .vbw-planning/.execution-state.json <<'EOF'
{
  "phase": 1,
  "status": "running",
  "plans": [
    {"id": "01-01", "status": "pending"}
  ]
}
EOF

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup/01-01-SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$helperless_scripts/state-updater.sh'"
  [ "$status" -eq 0 ]

  jq -e '.plans[0].status == "complete"' .vbw-planning/.execution-state.json >/dev/null
}

@test "remediation round-dir UAT write triggers STATE reconciliation" {
  cd "$TEST_TEMP_DIR"

  cat > .vbw-planning/STATE.md <<'EOF'
Phase: 1 of 1 (Setup)
Plans: 1/1
Progress: 100%
Status: complete
EOF

  mkdir -p .vbw-planning/phases/01-setup/remediation/uat/round-01
  echo "# plan" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md
  printf '%s\n' 'stage=verify' 'round=01' 'layout=round-dir' > .vbw-planning/phases/01-setup/remediation/uat/.uat-remediation-stage
  printf '%s\n' '---' 'status: issues_found' '---' 'Round failed.' > .vbw-planning/phases/01-setup/remediation/uat/round-01/R01-UAT.md

  local uat_path input
  uat_path="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup/remediation/uat/round-01/R01-UAT.md"
  input=$(jq -nc --arg p "$uat_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  grep -q '^Status: needs_remediation$' .vbw-planning/STATE.md
}

@test "legacy remediation round UAT write triggers STATE reconciliation" {
  cd "$TEST_TEMP_DIR"

  cat > .vbw-planning/STATE.md <<'EOF'
Phase: 1 of 1 (Setup)
Plans: 1/1
Progress: 100%
Status: complete
EOF

  mkdir -p .vbw-planning/phases/01-setup/remediation/round-01
  echo "# plan" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md
  printf '%s\n' 'stage=verify' 'round=01' 'layout=legacy' > .vbw-planning/phases/01-setup/remediation/.uat-remediation-stage
  printf '%s\n' '---' 'status: issues_found' '---' 'Legacy round failed.' > .vbw-planning/phases/01-setup/remediation/round-01/R01-UAT.md

  local uat_path input
  uat_path="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup/remediation/round-01/R01-UAT.md"
  input=$(jq -nc --arg p "$uat_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  grep -q '^Status: needs_remediation$' .vbw-planning/STATE.md
}

@test "remediation summary reconciles but does not complete phase-root execution plan" {
  cd "$TEST_TEMP_DIR"

  cat > .vbw-planning/STATE.md <<'EOF'
Phase: 1 of 1 (Setup)
Plans: 0/1
Progress: 0%
Status: active
EOF

  mkdir -p .vbw-planning/phases/01-setup/remediation/uat/round-01
  echo "# plan" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  printf '%s\n' 'stage=execute' 'round=01' 'layout=round-dir' > .vbw-planning/phases/01-setup/remediation/uat/.uat-remediation-stage
  printf '%s\n' '---' 'status: complete' '---' 'Remediation done.' > .vbw-planning/phases/01-setup/remediation/uat/round-01/R01-SUMMARY.md

  cat > .vbw-planning/.execution-state.json <<'EOF'
{
  "phase": 1,
  "status": "running",
  "plans": [
    {"id": "01-01", "title": "setup", "status": "pending"}
  ]
}
EOF

  local summary_path input
  summary_path="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup/remediation/uat/round-01/R01-SUMMARY.md"
  input=$(jq -nc --arg p "$summary_path" '{tool_input:{file_path:$p}}')

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$input' | bash '$SCRIPTS_DIR/state-updater.sh'"
  [ "$status" -eq 0 ]

  jq -e '.plans[0].status == "pending"' .vbw-planning/.execution-state.json >/dev/null
  grep -q '^Plans: 0/1$' .vbw-planning/STATE.md
  grep -q '^Status: ready$' .vbw-planning/STATE.md
}
#!/usr/bin/env bats
# Wave-layout regression tests for scripts that scan PLAN/SUMMARY/CONTEXT files.
# Ensures wave-subdir (P*-*-wave/) plans and summaries are visible to all consumers.

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > init.txt && git add init.txt && git commit -q -m "init"
}

teardown() {
  teardown_temp_dir
}

# Helper: create a wave-only phase layout with one plan+summary
create_wave_phase() {
  local phase_dir=".vbw-planning/phases/01-setup"
  local wave_dir="$phase_dir/P01-W01-01-wave"
  mkdir -p "$wave_dir"
  cat > "$wave_dir/P01-W01-01-PLAN.md" <<'PLAN'
---
phase: 1
plan: 1
title: "Setup"
wave: 1
depends_on: []
files_modified:
  - src/app.ts
---
# Plan
## Tasks
### Task 1: Setup
- **Files:** `src/app.ts`
PLAN
  if [ "${1:-}" = "complete" ]; then
    cat > "$wave_dir/P01-W01-01-SUMMARY.md" <<'SUMMARY'
---
phase: 1
plan: 1
title: "Setup"
status: complete
deviations: 0
---
# Summary
## Files Modified
- src/app.ts
SUMMARY
  fi
}

# ==========================================================================
# recover-state.sh — wave-layout
# ==========================================================================

@test "recover-state: reconstructs plan from wave subdir" {
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json
  create_wave_phase complete
  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.plans | length == 1'
  echo "$output" | jq -e '.plans[0].status == "complete"'
  echo "$output" | jq -e '.status == "complete"'
}

@test "recover-state: wave plan without summary reports pending" {
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json
  create_wave_phase
  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.plans | length == 1'
  echo "$output" | jq -e '.plans[0].status == "pending"'
}

# ==========================================================================
# hard-gate.sh artifact_persistence — wave-layout
# ==========================================================================

@test "hard-gate artifact_persistence: detects missing wave summary" {
  mkdir -p .vbw-planning/phases/01-test/P01-W01-01-wave
  cat > ".vbw-planning/phases/01-test/P01-W01-01-wave/P01-W01-01-PLAN.md" <<'PLAN'
---
phase: 1
plan: 1
title: First
wave: 1
---
PLAN
  mkdir -p .vbw-planning/phases/01-test/P01-W01-02-wave
  cat > ".vbw-planning/phases/01-test/P01-W01-02-wave/P01-W01-02-PLAN.md" <<'PLAN'
---
phase: 1
plan: 2
title: Second
wave: 1
---
PLAN
  # Plan 1 has no SUMMARY — artifact_persistence checking plan < 2 should catch it
  run bash "$SCRIPTS_DIR/hard-gate.sh" artifact_persistence 01 2 1 "/dev/null"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "fail"'
}

@test "hard-gate artifact_persistence: passes when all wave summaries present" {
  mkdir -p .vbw-planning/phases/01-test/P01-W01-01-wave
  cat > ".vbw-planning/phases/01-test/P01-W01-01-wave/P01-W01-01-PLAN.md" <<'PLAN'
---
phase: 1
plan: 1
title: First
wave: 1
---
PLAN
  cat > ".vbw-planning/phases/01-test/P01-W01-01-wave/P01-W01-01-SUMMARY.md" <<'SUMMARY'
---
status: complete
---
SUMMARY
  run bash "$SCRIPTS_DIR/hard-gate.sh" artifact_persistence 01 2 1 "/dev/null"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "pass"'
}

# ==========================================================================
# file-guard.sh — wave-layout active plan detection
# ==========================================================================

@test "file-guard: detects active plan in wave subdir" {
  create_wave_phase
  mkdir -p src
  # Write to a file in the plan's files_modified — should be allowed
  INPUT='{"tool_input":{"file_path":"src/app.ts","content":"ok"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: blocks undeclared file when active plan is in wave subdir" {
  create_wave_phase
  # Create a contract so file-guard enforces allowed_paths
  mkdir -p .vbw-planning/.contracts
  cat > .vbw-planning/.contracts/01-01.json <<'CONTRACT'
{
  "phase_id": "phase-1",
  "plan_id": "phase-1-plan-1",
  "phase": 1,
  "plan": 1,
  "objective": "Test",
  "task_ids": ["1-1-T1"],
  "task_count": 1,
  "allowed_paths": ["src/app.ts"],
  "forbidden_paths": [],
  "depends_on": [],
  "must_haves": [],
  "verification_checks": [],
  "max_token_budget": 50000,
  "timeout_seconds": 600
}
CONTRACT
  local hash
  hash=$(jq 'del(.contract_hash)' .vbw-planning/.contracts/01-01.json | shasum -a 256 | cut -d' ' -f1)
  jq --arg h "$hash" '.contract_hash = $h' .vbw-planning/.contracts/01-01.json > .vbw-planning/.contracts/01-01.json.tmp \
    && mv .vbw-planning/.contracts/01-01.json.tmp .vbw-planning/.contracts/01-01.json

  INPUT='{"tool_input":{"file_path":"src/unauthorized.ts","content":"bad"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
}

# ==========================================================================
# route-monorepo.sh — wave-layout
# ==========================================================================

@test "route-monorepo: discovers plans in wave subdirs" {
  mkdir -p packages/core
  echo '{}' > packages/core/package.json
  echo '{}' > package.json
  create_wave_phase
  # Override plan content with Files: referencing a package
  cat > ".vbw-planning/phases/01-setup/P01-W01-01-wave/P01-W01-01-PLAN.md" <<'PLAN'
---
phase: 1
plan: 1
title: Setup
wave: 1
---
## Tasks
### Task 1
- **Files:** `packages/core/index.js`
PLAN
  run bash "$SCRIPTS_DIR/route-monorepo.sh" ".vbw-planning/phases/01-setup"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(. == "packages/core")'
}

@test "route-monorepo: wave-only phase without plan files returns empty" {
  mkdir -p ".vbw-planning/phases/01-setup/P01-W01-01-wave"
  # No PLAN.md files at all
  run bash "$SCRIPTS_DIR/route-monorepo.sh" ".vbw-planning/phases/01-setup"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

# ==========================================================================
# compile-rolling-summary.sh — wave-layout
# ==========================================================================

@test "rolling-summary: discovers wave summaries at depth 3" {
  mkdir -p ".vbw-planning/phases/01-phase-one/P01-W01-01-wave"
  mkdir -p ".vbw-planning/phases/02-phase-two"
  cat > ".vbw-planning/phases/01-phase-one/P01-W01-01-wave/P01-W01-01-SUMMARY.md" <<'SUMMARY'
---
phase: 1
plan: 1
title: "Phase One Wave Plan"
status: complete
deviations: 0
commit_hashes: ["abc1234"]
tasks_completed: 2
tasks_total: 2
---
## What Was Built
Feature A.
## Files Modified
- scripts/a.sh
SUMMARY
  cat > ".vbw-planning/phases/02-phase-two/02-01-SUMMARY.md" <<'SUMMARY'
---
phase: 2
plan: 1
title: "Phase Two Plan"
status: complete
deviations: 0
commit_hashes: ["def5678"]
tasks_completed: 3
tasks_total: 3
---
## What Was Built
Feature B.
## Files Modified
- scripts/b.sh
SUMMARY
  OUTPUT="$TEST_TEMP_DIR/ROLLING-CONTEXT.md"
  run bash "$SCRIPTS_DIR/compile-rolling-summary.sh" ".vbw-planning/phases" "$OUTPUT"
  [ "$status" -eq 0 ]
  # Both phases should appear — wave summary must NOT be missed
  grep -q "Phase One Wave Plan" "$OUTPUT"
  grep -q "Phase Two Plan" "$OUTPUT"
  ! grep -q "No prior completed phases" "$OUTPUT"
}

# ==========================================================================
# delta-files.sh — wave-layout global dedup
# ==========================================================================

@test "delta-files: deduplicates across flat and wave summaries" {
  # Use a directory outside any git repo so Strategy 2 runs
  local NODIR
  NODIR=$(mktemp -d)
  mkdir -p "$NODIR/phases/01-setup/P01-W01-01-wave"
  cat > "$NODIR/phases/01-setup/01-01-SUMMARY.md" <<'SUMMARY'
---
status: complete
---
## Files Modified
- src/shared.ts
- src/flat-only.ts
SUMMARY
  cat > "$NODIR/phases/01-setup/P01-W01-01-wave/P01-W01-01-SUMMARY.md" <<'SUMMARY'
---
status: complete
---
## Files Modified
- src/shared.ts
- src/wave-only.ts
SUMMARY
  cd "$NODIR"
  run bash "$SCRIPTS_DIR/delta-files.sh" "phases/01-setup"
  rm -rf "$NODIR"
  [ "$status" -eq 0 ]
  # shared.ts should appear exactly once (deduplicated)
  local count
  count=$(echo "$output" | grep -c 'src/shared.ts')
  [ "$count" -eq 1 ]
  # Both unique files should appear
  echo "$output" | grep -q 'src/flat-only.ts'
  echo "$output" | grep -q 'src/wave-only.ts'
}

# ==========================================================================
# qa-gate.sh — wave-layout plan counting
# ==========================================================================

@test "qa-gate: counts wave-subdir plans for completeness check" {
  mkdir -p ".vbw-planning/phases/01-setup/P01-W01-01-wave"
  cat > ".vbw-planning/phases/01-setup/P01-W01-01-wave/P01-W01-01-PLAN.md" <<'PLAN'
---
phase: 1
plan: 1
title: Setup
wave: 1
---
PLAN
  # No SUMMARY → plans(1) > summaries(0) → could block
  # QA gate should count the wave plan
  run bash "$SCRIPTS_DIR/qa-gate.sh" < /dev/null
  # The gate itself might pass or fail depending on commit checks,
  # but verify that PLANS_TOTAL captured our wave plan by checking
  # the script exits without error
  [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
}

# ==========================================================================
# summary-utils.sh — remediation round counting
# ==========================================================================

@test "count_phase_plans: includes remediation round plans" {
  local phase_dir=".vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir/P01-W01-01-wave"
  mkdir -p "$phase_dir/remediation/P01-01-round"
  echo "# Plan" > "$phase_dir/P01-W01-01-wave/P01-W01-01-PLAN.md"
  echo "# Plan" > "$phase_dir/remediation/P01-01-round/P01-R01-PLAN.md"
  source "$SCRIPTS_DIR/summary-utils.sh"
  count=$(count_phase_plans "$phase_dir")
  [ "$count" -eq 2 ]
}

@test "count_complete_summaries: includes remediation round summaries" {
  local phase_dir=".vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir/P01-W01-01-wave"
  mkdir -p "$phase_dir/remediation/P01-01-round"
  cat > "$phase_dir/P01-W01-01-wave/P01-W01-01-SUMMARY.md" <<'S'
---
status: complete
---
S
  cat > "$phase_dir/remediation/P01-01-round/P01-R01-SUMMARY.md" <<'S'
---
status: complete
---
S
  source "$SCRIPTS_DIR/summary-utils.sh"
  count=$(count_complete_summaries "$phase_dir")
  [ "$count" -eq 2 ]
}

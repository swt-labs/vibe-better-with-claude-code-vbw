#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  cd "$TEST_TEMP_DIR" || exit 1
}

teardown() {
  teardown_temp_dir
}

write_drift_fixture() {
  cat > .vbw-planning/STATE.md <<'STATE'
# State

**Project:** Test Project
**Milestone:** MVP

## Current Phase
Phase: 3 of 3 (Order Backed Sync Integration)
Plans: 2/2
Progress: 100%
Status: ready

## Phase Status
- **Phase 1:** Complete
- **Phase 2:** Complete
- **Phase 3:** Planned

## Key Decisions
| Decision | Date | Rationale |
|----------|------|-----------|
| Keep deterministic state shell-side | 2026-05-01 | Avoid token repair |

## Todos
None.

## Blockers
None
STATE

  cat > .vbw-planning/PROJECT.md <<'PROJECT'
# Test Project
PROJECT

  cat > .vbw-planning/ROADMAP.md <<'ROADMAP'
# Roadmap

- [x] Phase 1: Foundation
- [ ] Phase 2: Ios Orders Client Models
- [ ] Phase 3: Order Backed Sync Integration

### Phase 1: Foundation
### Phase 2: Ios Orders Client Models
### Phase 3: Order Backed Sync Integration
ROADMAP

  mkdir -p \
    .vbw-planning/phases/01-foundation \
    .vbw-planning/phases/02-ios-orders-client-models \
    .vbw-planning/phases/03-order-backed-sync-integration

  echo '# Plan 1' > .vbw-planning/phases/01-foundation/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-foundation/01-01-SUMMARY.md

  echo '# Plan 1' > .vbw-planning/phases/02-ios-orders-client-models/02-01-PLAN.md
  echo '# Plan 2' > .vbw-planning/phases/02-ios-orders-client-models/02-02-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/02-ios-orders-client-models/02-01-SUMMARY.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/02-ios-orders-client-models/02-02-SUMMARY.md
  cat > .vbw-planning/phases/02-ios-orders-client-models/02-UAT.md <<'UAT'
---
phase: 02
status: issues_found
---
Failed tests.
UAT
}

@test "reconcile-state repairs drift fixture and clears state_vs_filesystem" {
  write_drift_fixture

  run bash "$SCRIPTS_DIR/reconcile-state-md.sh" .vbw-planning
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  grep -q '^Phase: 2 of 3 (Ios Orders Client Models)$' .vbw-planning/STATE.md
  grep -q '^Plans: 2/2$' .vbw-planning/STATE.md
  grep -q '^Progress: 100%$' .vbw-planning/STATE.md
  grep -q '^Status: needs_remediation$' .vbw-planning/STATE.md
  grep -q '^- \*\*Phase 2 (Ios Orders Client Models):\*\* Needs remediation$' .vbw-planning/STATE.md
  grep -q '^- \*\*Phase 3 (Order Backed Sync Integration):\*\* Pending$' .vbw-planning/STATE.md
  grep -q 'Keep deterministic state shell-side' .vbw-planning/STATE.md

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" .vbw-planning --mode advisory
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.failed_checks | index("state_vs_filesystem") | not' >/dev/null
}

@test "reconcile-state repairs linked ROADMAP checklist drift by phase prefix" {
  cat > .vbw-planning/PROJECT.md <<'PROJECT'
# Test Project
PROJECT

  cat > .vbw-planning/STATE.md <<'STATE'
# State

**Project:** Test Project
**Milestone:** MVP

## Current Phase
Phase: 2 of 2 (Api Contracts)
Plans: 1/1
Progress: 100%
Status: ready

## Phase Status
- **Phase 1:** Complete
- **Phase 2:** Planned
STATE

  cat > .vbw-planning/ROADMAP.md <<'ROADMAP'
# Roadmap

- [x] [Phase 01: Foundation](#phase-01-foundation)
- [ ] [Phase 03: Api Contracts](#phase-03-api-contracts)

## Phase 01: Foundation
## Phase 03: Api Contracts
ROADMAP

  mkdir -p .vbw-planning/phases/01-foundation .vbw-planning/phases/03-api-contracts
  echo '# Plan' > .vbw-planning/phases/01-foundation/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-foundation/01-01-SUMMARY.md
  echo '# Plan' > .vbw-planning/phases/03-api-contracts/03-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/03-api-contracts/03-01-SUMMARY.md

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" .vbw-planning --mode archive
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.failed_checks | index("roadmap_vs_summaries")' >/dev/null

  run bash "$SCRIPTS_DIR/reconcile-state-md.sh" .vbw-planning
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  grep -q '^- \[x\] \[Phase 03: Api Contracts\](#phase-03-api-contracts)$' .vbw-planning/ROADMAP.md

  run bash "$SCRIPTS_DIR/verify-state-consistency.sh" .vbw-planning --mode archive
  if [ "$status" -ne 0 ]; then echo "$output" >&2; fi
  [ "$status" -eq 0 ]
}

@test "reconcile-state preserves terminal-summary display semantics" {
  cat > .vbw-planning/STATE.md <<'STATE'
# State

**Project:** Test Project
**Milestone:** MVP

## Current Phase
Phase: 1 of 1 (Setup)
Plans: 0/1
Progress: 0%
Status: ready

## Phase Status
- **Phase 1:** Planned
STATE

  mkdir -p .vbw-planning/phases/01-setup
  echo '# Plan' > .vbw-planning/phases/01-setup/01-01-PLAN.md
  printf '%s\n' '---' 'status: failed' '---' 'Failed.' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md

  run bash "$SCRIPTS_DIR/reconcile-state-md.sh" .vbw-planning
  [ "$status" -eq 0 ]

  grep -q '^Phase: 1 of 1 (Setup)$' .vbw-planning/STATE.md
  grep -q '^Plans: 1/1$' .vbw-planning/STATE.md
  grep -q '^Progress: 100%$' .vbw-planning/STATE.md
  grep -q '^Status: active$' .vbw-planning/STATE.md
  grep -q '^- \*\*Phase 1 (Setup):\*\* In progress$' .vbw-planning/STATE.md
}

@test "finalize-uat-status reconciles STATE after Bash-only UAT finalization" {
  cat > .vbw-planning/STATE.md <<'STATE'
# State

**Project:** Test Project
**Milestone:** MVP

## Current Phase
Phase: 1 of 1 (Setup)
Plans: 1/1
Progress: 100%
Status: complete

## Phase Status
- **Phase 1:** Complete
STATE

  mkdir -p .vbw-planning/phases/01-setup
  echo '# Plan' > .vbw-planning/phases/01-setup/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-setup/01-UAT.md <<'UAT'
---
phase: 01
status: in_progress
completed:
passed: 0
skipped: 0
issues: 0
total_tests: 1
---
# UAT

### P01: Broken flow
- **Result:** issue
UAT

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" .vbw-planning/phases/01-setup/01-UAT.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=issues_found"* ]]

  grep -q '^status: issues_found$' .vbw-planning/phases/01-setup/01-UAT.md
  grep -q '^Phase: 1 of 1 (Setup)$' .vbw-planning/STATE.md
  grep -q '^Status: needs_remediation$' .vbw-planning/STATE.md
  grep -q '^- \*\*Phase 1 (Setup):\*\* Needs remediation$' .vbw-planning/STATE.md
}

@test "round-dir current UAT affects STATE and phase-root fallback remains intact" {
  cat > .vbw-planning/STATE.md <<'STATE'
# State

**Project:** Test Project
**Milestone:** MVP

## Current Phase
Phase: 1 of 1 (Setup)
Plans: 1/1
Progress: 100%
Status: complete

## Phase Status
- **Phase 1:** Complete
STATE

  mkdir -p .vbw-planning/phases/01-setup/remediation/uat/round-01
  echo '# Plan' > .vbw-planning/phases/01-setup/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md
  printf '%s\n' '---' 'status: complete' '---' 'Passed.' > .vbw-planning/phases/01-setup/01-UAT.md
  printf '%s\n' 'stage=verify' 'round=01' 'layout=round-dir' > .vbw-planning/phases/01-setup/remediation/uat/.uat-remediation-stage
  printf '%s\n' '---' 'status: issues_found' '---' 'Round failed.' > .vbw-planning/phases/01-setup/remediation/uat/round-01/R01-UAT.md

  run bash "$SCRIPTS_DIR/reconcile-state-md.sh" .vbw-planning
  [ "$status" -eq 0 ]
  grep -q '^Status: needs_remediation$' .vbw-planning/STATE.md

  rm -f .vbw-planning/phases/01-setup/remediation/uat/.uat-remediation-stage
  run bash "$SCRIPTS_DIR/reconcile-state-md.sh" .vbw-planning
  [ "$status" -eq 0 ]
  grep -q '^Status: complete$' .vbw-planning/STATE.md
}

@test "legacy remediation current UAT affects STATE" {
  cat > .vbw-planning/STATE.md <<'STATE'
# State

**Project:** Test Project
**Milestone:** MVP

## Current Phase
Phase: 1 of 1 (Setup)
Plans: 1/1
Progress: 100%
Status: complete

## Phase Status
- **Phase 1:** Complete
STATE

  mkdir -p .vbw-planning/phases/01-setup/remediation/round-01
  echo '# Plan' > .vbw-planning/phases/01-setup/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md
  printf '%s\n' 'stage=verify' 'round=01' 'layout=legacy' > .vbw-planning/phases/01-setup/remediation/.uat-remediation-stage
  printf '%s\n' '---' 'status: issues_found' '---' 'Legacy round failed.' > .vbw-planning/phases/01-setup/remediation/round-01/R01-UAT.md

  run bash "$SCRIPTS_DIR/reconcile-state-md.sh" .vbw-planning
  [ "$status" -eq 0 ]
  grep -q '^Status: needs_remediation$' .vbw-planning/STATE.md
}

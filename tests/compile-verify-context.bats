#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/phases/03-test-phase"
  mkdir -p "$PHASE_DIR"
}

teardown() {
  teardown_temp_dir
}

@test "compile-verify-context: multi-plan phase with summaries" {
  # Plan 01
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
phase: 03
plan: 01
title: Add login form
wave: 1
depends_on: []
must_haves:
  - Email field validates format
  - Password field has minimum length
---
<objective>Build login form</objective>
EOF

  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
phase: 03
plan: 01
title: Add login form
status: complete
completed: 2026-02-20
tasks_completed: 3
tasks_total: 3
---

Built the login form with validation.

## What Was Built

- Login form component with email/password fields
- Client-side validation for email format
- Password minimum length enforcement
- Error message display

## Files Modified

- `src/components/LoginForm.tsx` -- created: main form component
- `src/utils/validators.ts` -- modified: added email/password validators

## Deviations

None
EOF

  # Plan 02
  cat > "$PHASE_DIR/03-02-PLAN.md" <<'EOF'
---
phase: 03
plan: 02
title: Add auth API endpoint
wave: 1
depends_on: []
must_haves:
  - POST /api/auth returns JWT
  - Invalid credentials return 401
---
<objective>Build auth endpoint</objective>
EOF

  cat > "$PHASE_DIR/03-02-SUMMARY.md" <<'EOF'
---
phase: 03
plan: 02
title: Add auth API endpoint
status: complete
completed: 2026-02-20
tasks_completed: 2
tasks_total: 2
---

Built auth API endpoint with JWT.

## What Was Built

- POST /api/auth endpoint
- JWT token generation
- Credential validation

## Files Modified

- `src/api/auth.ts` -- created: auth endpoint handler
- `src/middleware/jwt.ts` -- created: JWT utilities

## Deviations

None
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"=== PLAN 01: Add login form ==="* ]]
  [[ "$output" == *"must_haves: Email field validates format; Password field has minimum length"* ]]
  [[ "$output" == *"Login form component"* ]]
  [[ "$output" == *"src/components/LoginForm.tsx"* ]]
  [[ "$output" == *"status: complete"* ]]
  [[ "$output" == *"=== PLAN 02: Add auth API endpoint ==="* ]]
  [[ "$output" == *"POST /api/auth returns JWT"* ]]
  [[ "$output" == *"src/api/auth.ts"* ]]
  [[ "$output" == *"verify_plan_count=2"* ]]
}

@test "compile-verify-context: plan without summary shows no_summary status" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
phase: 03
plan: 01
title: Incomplete plan
wave: 1
depends_on: []
must_haves:
  - Something important
---
<objective>Do something</objective>
EOF

  # No SUMMARY file for this plan

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"=== PLAN 01: Incomplete plan ==="* ]]
  [[ "$output" == *"status: no_summary"* ]]
  [[ "$output" == *"what_was_built: none"* ]]
  [[ "$output" == *"files_modified: none"* ]]
  [[ "$output" == *"verify_plan_count=1"* ]]
}

@test "compile-verify-context: empty dir returns verify_context=empty" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == "verify_context=empty" ]]
}

@test "compile-verify-context: nonexistent dir returns error marker" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$TEST_TEMP_DIR/nonexistent"

  [ "$status" -eq 0 ]
  [[ "$output" == "verify_context_error=no_phase_dir" ]]
}

@test "compile-verify-context: what_was_built limited to 5 lines" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
phase: 03
plan: 01
title: Big plan
wave: 1
must_haves:
  - Feature delivered
---
EOF

  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
phase: 03
plan: 01
title: Big plan
status: complete
---

Built many things.

## What Was Built

- Item one
- Item two
- Item three
- Item four
- Item five
- Item six should not appear
- Item seven should not appear

## Files Modified

- `src/a.ts` -- modified: something

## Deviations

None
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Item five"* ]]
  [[ "$output" != *"Item six"* ]]
  [[ "$output" != *"Item seven"* ]]
}

@test "compile-verify-context: must_haves with nested truths/artifacts" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
phase: 03
plan: 01
title: Structured must_haves
wave: 1
must_haves:
  truths:
    - "Invariant one holds"
    - "Invariant two holds"
  artifacts:
    - {path: "src/foo.ts", provides: "module", contains: "export"}
---
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Invariant one holds"* ]]
  [[ "$output" == *"Invariant two holds"* ]]
  [[ "$output" == *"src/foo.ts"* ]]
}

# --- --remediation-only tests ---

@test "compile-verify-context: --remediation-only with completed round emits only round plans" {
  # Phase-root plan (should be excluded)
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
phase: 03
plan: 01
title: Original login form
wave: 1
must_haves:
  - Email field validates format
---
EOF
  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
status: complete
---
## What Was Built
- Login form
## Files Modified
- `src/login.tsx` -- created
EOF

  # Remediation round-01 with both PLAN and SUMMARY
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-PLAN.md" <<'EOF'
---
phase: 03
plan: R01
title: Fix validation bug
wave: 1
must_haves:
  - Email validation no longer rejects valid addresses
---
EOF
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-SUMMARY.md" <<'EOF'
---
status: complete
---
## What Was Built
- Fixed email regex
## Files Modified
- `src/validators.ts` -- modified
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" --remediation-only "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_scope=remediation round=01"* ]]
  [[ "$output" == *"=== PLAN R01: Fix validation bug ==="* ]]
  [[ "$output" == *"Email validation no longer rejects valid addresses"* ]]
  # Phase-root plan should NOT appear
  [[ "$output" != *"Original login form"* ]]
  [[ "$output" == *"verify_plan_count=1"* ]]
}

@test "compile-verify-context: --remediation-only picks latest completed round" {
  # Round 01 — complete (has both PLAN and SUMMARY)
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-PLAN.md" <<'EOF'
---
plan: R01
title: Round 1 fix
must_haves:
  - Old fix
---
EOF
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-SUMMARY.md" <<'EOF'
---
status: complete
---
## What Was Built
- Round 1 work
EOF

  # Round 02 — complete (has both PLAN and SUMMARY)
  mkdir -p "$PHASE_DIR/remediation/uat/round-02"
  cat > "$PHASE_DIR/remediation/uat/round-02/R02-PLAN.md" <<'EOF'
---
plan: R02
title: Round 2 fix
must_haves:
  - Latest fix
---
EOF
  cat > "$PHASE_DIR/remediation/uat/round-02/R02-SUMMARY.md" <<'EOF'
---
status: complete
---
## What Was Built
- Round 2 work
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" --remediation-only "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_scope=remediation round=02"* ]]
  [[ "$output" == *"=== PLAN R02: Round 2 fix ==="* ]]
  [[ "$output" == *"Latest fix"* ]]
  # Round 01 should NOT appear
  [[ "$output" != *"Round 1 fix"* ]]
  [[ "$output" == *"verify_plan_count=1"* ]]
}

@test "compile-verify-context: --remediation-only falls back to full when no completed round" {
  # Phase-root plan
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Original plan
must_haves:
  - Something
---
EOF

  # Round 01 — incomplete (PLAN only, no SUMMARY)
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-PLAN.md" <<'EOF'
---
plan: R01
title: Incomplete round
must_haves:
  - Unfinished
---
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" --remediation-only "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_scope=full"* ]]
  # Falls back to full scope — both plans appear
  [[ "$output" == *"Original plan"* ]]
  [[ "$output" == *"Incomplete round"* ]]
}

@test "compile-verify-context: --remediation-only with empty remediation dir falls back to full" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Some plan
must_haves:
  - Feature
---
EOF

  mkdir -p "$PHASE_DIR/remediation/uat"

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" --remediation-only "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_scope=full"* ]]
  [[ "$output" == *"Some plan"* ]]
}

@test "compile-verify-context: no flag with remediation dirs emits all plans with full scope" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Phase-root plan
must_haves:
  - Original feature
---
EOF

  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-PLAN.md" <<'EOF'
---
plan: R01
title: Remediation plan
must_haves:
  - Fix something
---
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_scope=full"* ]]
  [[ "$output" == *"Phase-root plan"* ]]
  [[ "$output" == *"Remediation plan"* ]]
  [[ "$output" == *"verify_plan_count=2"* ]]
}

@test "compile-verify-context: full scope emits verify_scope=full header" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Basic plan
must_haves:
  - Something
---
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # First non-empty content line should contain verify_scope
  [[ "${lines[0]}" == "verify_scope=full" ]]
}

# --- uat_path emission tests ---

@test "compile-verify-context: full scope emits uat_path with phase number" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Plan for uat_path test
must_haves:
  - Something testable
---
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_path=03-UAT.md"* ]]
}

@test "compile-verify-context: remediation scope emits uat_path with round dir" {
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-PLAN.md" <<'EOF'
---
plan: R01
title: Round 1 remediation
must_haves:
  - Fix the issue
---
EOF
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-SUMMARY.md" <<'EOF'
---
status: complete
---
## What Was Built
- Fixed things
## Files Modified
- file.txt
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" --remediation-only "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_path=remediation/uat/round-01/R01-UAT.md"* ]]
}

@test "compile-verify-context: legacy remediation layout emits correct uat_path" {
  # Legacy layout: remediation/round-* (no uat/ sublevel)
  mkdir -p "$PHASE_DIR/remediation/round-01"
  cat > "$PHASE_DIR/remediation/round-01/R01-PLAN.md" <<'EOF'
---
plan: R01
title: Legacy round 1
must_haves:
  - Fix legacy issue
---
EOF
  cat > "$PHASE_DIR/remediation/round-01/R01-SUMMARY.md" <<'EOF'
---
status: complete
---
## What Was Built
- Fixed things
## Files Modified
- file.txt
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" --remediation-only "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # uat_path must NOT contain uat/ since the legacy layout has no uat/ sublevel
  [[ "$output" == *"uat_path=remediation/round-01/R01-UAT.md"* ]]
  [[ "$output" == *"verify_scope=remediation round=01"* ]]
}

@test "compile-verify-context: fallback full scope emits uat_path with phase number" {
  # Phase-root plan exists
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Fallback test
must_haves:
  - Feature
---
EOF

  # Remediation round with no SUMMARY (incomplete) — forces fallback to full
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-PLAN.md" <<'EOF'
---
plan: R01
title: Incomplete
must_haves:
  - Unfinished
---
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" --remediation-only "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_scope=full"* ]]
  [[ "$output" == *"uat_path=03-UAT.md"* ]]
}

@test "compile-verify-context: --remediation-only skips round with in-progress summary" {
  # Round 01 — complete
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-PLAN.md" <<'EOF'
---
plan: R01
title: Round 1 fix
must_haves:
  - Old fix
---
EOF
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-SUMMARY.md" <<'EOF'
---
status: complete
---
## What Was Built
- Round 1 work
EOF

  # Round 02 — in-progress (not terminal)
  mkdir -p "$PHASE_DIR/remediation/uat/round-02"
  cat > "$PHASE_DIR/remediation/uat/round-02/R02-PLAN.md" <<'EOF'
---
plan: R02
title: Round 2 fix
must_haves:
  - Latest fix
---
EOF
  cat > "$PHASE_DIR/remediation/uat/round-02/R02-SUMMARY.md" <<'EOF'
---
status: in-progress
tasks_completed: 1
tasks_total: 3
---
## Task 1: Done
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" --remediation-only "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # Should pick round 01 (terminal), not round 02 (in-progress)
  [[ "$output" == *"verify_scope=remediation round=01"* ]]
  [[ "$output" == *"Round 1 fix"* ]]
  [[ "$output" != *"Round 2 fix"* ]]
}

@test "compile-verify-context: --remediation-only accepts partial status as terminal" {
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-PLAN.md" <<'EOF'
---
plan: R01
title: Partial round
must_haves:
  - Partial fix
---
EOF
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-SUMMARY.md" <<'EOF'
---
status: partial
tasks_completed: 2
tasks_total: 3
---
## What Was Built
- Partial work
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" --remediation-only "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_scope=remediation round=01"* ]]
  [[ "$output" == *"Partial round"* ]]
}

@test "compile-verify-context: --remediation-only accepts failed status as terminal" {
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-PLAN.md" <<'EOF'
---
plan: R01
title: Failed round
must_haves:
  - Failed fix
---
EOF
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-SUMMARY.md" <<'EOF'
---
status: failed
tasks_completed: 0
tasks_total: 3
---
## What Was Built
- Nothing
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" --remediation-only "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_scope=remediation round=01"* ]]
  [[ "$output" == *"Failed round"* ]]
}

# --- Deviation extraction: body ## Deviations fallback ---

@test "compile-verify-context: extracts deviations from body when YAML frontmatter has none" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
phase: 03
plan: 01
title: Model with deviation
wave: 1
must_haves:
  - Feature works
---
EOF

  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
phase: 03
plan: 01
title: Model with deviation
status: complete
completed: 2026-03-27
tasks_completed: 3
tasks_total: 3
---

Built the model.

## What Was Built

- The model

## Files Modified

- `src/model.swift` -- created: model

## Deviations

- **Uniqueness test approach**: Changed from raw constraint test to upsert pattern test
- **Started before dependency completed**: Proceeded since API was on disk
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"deviations: Changed from raw constraint test to upsert pattern test; Proceeded since API was on disk"* ]]
}

@test "compile-verify-context: YAML frontmatter deviations take priority over body" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
phase: 03
plan: 01
title: Has both
wave: 1
must_haves:
  - Feature works
---
EOF

  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
phase: 03
plan: 01
title: Has both
status: complete
deviations:
  - "YAML deviation wins"
---

Built it.

## What Was Built

- Thing

## Deviations

- Body deviation should be ignored
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"deviations: YAML deviation wins"* ]]
  [[ "$output" != *"Body deviation should be ignored"* ]]
}

@test "compile-verify-context: body deviations section with None is treated as no deviations" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
phase: 03
plan: 01
title: No deviations
wave: 1
must_haves:
  - Something
---
EOF

  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
phase: 03
plan: 01
title: No deviations
status: complete
---

Built it.

## What Was Built

- Thing

## Deviations

None. All tasks implemented as specified.
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"deviations: none"* ]]
}

@test "compile-verify-context: body deviations bold-wrapped None is filtered" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
phase: 03
plan: 01
title: Bold none
wave: 1
must_haves:
  - Something
---
EOF

  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
phase: 03
plan: 01
title: Bold none
status: complete
---

## What Was Built

- Thing

## Deviations

- **None**: No deviations from plan
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"deviations: none"* ]]
}

@test "compile-verify-context: body deviations bold-wrapped N/A with explanation is filtered" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
phase: 03
plan: 01
title: Bold NA
wave: 1
must_haves:
  - Something
---
EOF

  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
phase: 03
plan: 01
title: Bold NA
status: complete
---

## What Was Built

- Thing

## Deviations

- **N/A**: not applicable
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"deviations: none"* ]]
}

# ============================================================
# QA remediation plan discovery
# ============================================================

@test "compile-verify-context: discovers QA remediation plans in full-scope mode" {
  # Phase-root plan
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
phase: 03
plan: 01
title: Original feature
must_haves:
  - Feature works
---
<objective>Build feature</objective>
EOF
  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
phase: 03
plan: 01
title: Original feature
status: complete
---
## What Was Built
- The feature
## Files Modified
- `src/feature.swift` -- created
EOF

  # QA remediation round plan + summary
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'EOF'
---
phase: 03
round: 01
title: Fix QA deviations
type: remediation
must_haves:
  - Deviation resolved
---
<objective>Fix deviations found by QA</objective>
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md" <<'EOF'
---
phase: 03
round: 01
title: Fix QA deviations
type: remediation
status: complete
---
## What Was Built
- Fixed the deviation
## Files Modified
- `src/feature.swift` -- modified
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # Should find both the regular plan and the QA remediation plan
  [[ "$output" == *"verify_plan_count=2"* ]]
  [[ "$output" == *"=== PLAN 01: Original feature ==="* ]]
  [[ "$output" == *"=== PLAN R01: Fix QA deviations ==="* ]]
}

@test "compile-verify-context: PLAN_ID falls back to round: for remediation plans" {
  # Only a QA remediation plan (no phase-root plans)
  mkdir -p "$PHASE_DIR/remediation/qa/round-02"
  cat > "$PHASE_DIR/remediation/qa/round-02/R02-PLAN.md" <<'EOF'
---
phase: 03
round: 02
title: Second QA fix round
type: remediation
must_haves:
  - All checks pass
---
<objective>Fix remaining QA issues</objective>
EOF
  cat > "$PHASE_DIR/remediation/qa/round-02/R02-SUMMARY.md" <<'EOF'
---
phase: 03
round: 02
title: Second QA fix round
type: remediation
status: complete
---
## What Was Built
- Fixed remaining issues
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"=== PLAN R02: Second QA fix round ==="* ]]
  [[ "$output" == *"status: complete"* ]]
}

@test "compile-verify-context: QA remediation summary deviations extracted" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'EOF'
---
phase: 03
round: 01
title: Fix deviations
type: remediation
must_haves:
  - API matches spec
---
<objective>Fix deviation</objective>
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md" <<'EOF'
---
phase: 03
round: 01
title: Fix deviations
type: remediation
status: complete
deviations:
  - "Used different endpoint naming"
---
## What Was Built
- Reimplemented the API layer
## Files Modified
- `src/api.swift` -- rewritten
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"deviations: Used different endpoint naming"* ]]
  [[ "$output" == *"files_modified: src/api.swift"* ]]
}

@test "compile-verify-context: --remediation-only excludes QA remediation plans" {
  # Phase-root plan
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
phase: 03
plan: 01
title: Original feature
must_haves:
  - Feature works
---
EOF
  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
phase: 03
plan: 01
title: Original feature
status: complete
---
## What Was Built
- Thing
EOF

  # UAT remediation round (should be found by --remediation-only)
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-PLAN.md" <<'EOF'
---
phase: 03
round: 01
title: Fix UAT issues
type: remediation
must_haves:
  - UAT issue fixed
---
EOF
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-SUMMARY.md" <<'EOF'
---
phase: 03
round: 01
title: Fix UAT issues
type: remediation
status: complete
---
## What Was Built
- Fixed UAT issue
EOF

  # QA remediation round (should NOT be found by --remediation-only)
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'EOF'
---
phase: 03
round: 01
title: Fix QA deviations
type: remediation
must_haves:
  - Deviation resolved
---
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md" <<'EOF'
---
phase: 03
round: 01
title: Fix QA deviations
type: remediation
status: complete
---
## What Was Built
- Fixed deviation
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" --remediation-only "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_scope=remediation"* ]]
  [[ "$output" == *"verify_plan_count=1"* ]]
  [[ "$output" == *"Fix UAT issues"* ]]
  [[ "$output" != *"Fix QA deviations"* ]]
}

@test "compile-verify-context: full-scope discovers phase-root + UAT + QA remediation plans" {
  # Phase-root plan
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
phase: 03
plan: 01
title: Original feature
must_haves:
  - Feature works
---
EOF
  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
phase: 03
plan: 01
title: Original feature
status: complete
---
## What Was Built
- The feature
EOF

  # UAT remediation plan
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-PLAN.md" <<'EOF'
---
phase: 03
round: 01
title: Fix UAT issues
type: remediation
must_haves:
  - UAT fixed
---
EOF
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-SUMMARY.md" <<'EOF'
---
phase: 03
round: 01
title: Fix UAT issues
type: remediation
status: complete
---
## What Was Built
- Fixed UAT
EOF

  # QA remediation plan
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'EOF'
---
phase: 03
round: 01
title: Fix QA deviations
type: remediation
must_haves:
  - QA fixed
---
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md" <<'EOF'
---
phase: 03
round: 01
title: Fix QA deviations
type: remediation
status: complete
---
## What Was Built
- Fixed QA deviation
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_scope=full"* ]]
  [[ "$output" == *"verify_plan_count=3"* ]]
  [[ "$output" == *"Original feature"* ]]
  [[ "$output" == *"Fix UAT issues"* ]]
  [[ "$output" == *"Fix QA deviations"* ]]
}

# --- VERIFICATION HISTORY ---

@test "compile-verify-context: emits verification history for phase-level VERIFICATION.md" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Test plan
must_haves:
  - Item one
---
EOF
  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
plan: 01
status: complete
---
## What Was Built
- Feature A
EOF
  cat > "$PHASE_DIR/03-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Item one | FAIL | Missing |
| MH-02 | must_have | Item two | PASS | Done |
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"=== VERIFICATION HISTORY ==="* ]]
  [[ "$output" == *"--- Phase VERIFICATION (FAIL) ---"* ]]
  [[ "$output" == *"FAIL"*"Missing"* ]]
  # PASS rows should NOT appear in history
  local fail_rows
  fail_rows=$(echo "$output" | grep -c "Item two.*PASS" || true)
  [ "$fail_rows" -eq 0 ]
}

@test "compile-verify-context: verification history compounds across rounds" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Test plan
must_haves:
  - Widget renders fast
---
EOF
  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
plan: 01
status: complete
---
## What Was Built
- Widget
EOF
  # Phase-level FAIL (original)
  cat > "$PHASE_DIR/03-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Widget renders within 200ms | FAIL | Measured 350ms |
| ART-03 | artifact | Test coverage | FAIL | No test file |
EOF

  # Round 01 VERIFICATION (partial fix)
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'EOF'
---
round: 01
title: Fix widget speed
must_haves:
  - Faster widget
---
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md" <<'EOF'
---
round: 01
status: complete
---
## What Was Built
- Optimized widget
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
result: PARTIAL
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Widget renders within 200ms | FAIL | Measured 210ms |
| ART-03 | artifact | Test coverage | PASS | Tests added |
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"=== VERIFICATION HISTORY ==="* ]]
  [[ "$output" == *"--- Phase VERIFICATION (FAIL) ---"* ]]
  [[ "$output" == *"350ms"* ]]
  [[ "$output" == *"--- Round 01 VERIFICATION (PARTIAL) ---"* ]]
  [[ "$output" == *"210ms"* ]]
}

@test "compile-verify-context: no verification history when no VERIFICATION.md exists" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Test plan
---
EOF
  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
plan: 01
status: complete
---
## What Was Built
- Feature
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # No VERIFICATION HISTORY block
  [[ "$output" != *"=== VERIFICATION HISTORY ==="* ]]
}

@test "compile-verify-context: verification history only extracts FAIL rows" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Test plan
---
EOF
  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
plan: 01
status: complete
---
## What Was Built
- Feature
EOF
  cat > "$PHASE_DIR/03-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Good thing | PASS | Works |
| MH-02 | must_have | Bad thing | FAIL | Broken |
| MH-03 | must_have | Also good | PASS | Fine |
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"=== VERIFICATION HISTORY ==="* ]]
  # Only FAIL row present
  [[ "$output" == *"Bad thing"*"FAIL"* ]]
  # Count lines with "Good thing" and "Also good" in verification history section
  # These are PASS rows and should not appear in the history
  local pass_in_history
  pass_in_history=$(echo "$output" | awk '/VERIFICATION HISTORY/,0' | grep -c "PASS" || true)
  [ "$pass_in_history" -eq 0 ]
}

@test "compile-verify-context: verification history with round-only (no phase-level VERIFICATION.md)" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Test plan
---
EOF
  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
plan: 01
status: complete
---
## What Was Built
- Feature
EOF

  # Round VERIFICATION.md only — no phase-level
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'EOF'
---
round: 01
title: Fix issues
---
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md" <<'EOF'
---
round: 01
status: complete
---
## What Was Built
- Fixes
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
result: PARTIAL
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Speed check | FAIL | Still slow |
| MH-02 | must_have | Test check | PASS | Tests added |
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"=== VERIFICATION HISTORY ==="* ]]
  [[ "$output" == *"--- Round 01 VERIFICATION (PARTIAL) ---"* ]]
  [[ "$output" == *"Still slow"* ]]
  # No phase verification section (since no phase-level file)
  [[ "$output" != *"--- Phase VERIFICATION"* ]]
}

@test "compile-verify-context: FAIL in description column not extracted as FAIL row" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Test plan
---
EOF
  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
plan: 01
status: complete
---
## What Was Built
- Feature
EOF
  cat > "$PHASE_DIR/03-VERIFICATION.md" <<'EOF'
---
result: PASS
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Verify FAIL message rendering | PASS | Works correctly |
| MH-02 | must_have | Error handling | PASS | All good |
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-verify-context.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"=== VERIFICATION HISTORY ==="* ]]
  # PASS row with "FAIL" in description should NOT appear as FAIL
  local false_fail
  false_fail=$(echo "$output" | awk '/VERIFICATION HISTORY/,0' | grep -c "FAIL message rendering" || true)
  [ "$false_fail" -eq 0 ]
}

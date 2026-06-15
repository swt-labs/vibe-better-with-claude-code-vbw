#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  mkdir -p "$PHASE_DIR"
}

teardown() {
  teardown_temp_dir
}

@test "resolve-verification-path phase prefers brownfield plain VERIFICATION over stale wave files" {
  cat > "$PHASE_DIR/VERIFICATION.md" <<'EOF'
---
result: PASS
---
EOF
  cat > "$PHASE_DIR/01-VERIFICATION-wave2.md" <<'EOF'
---
result: FAIL
---
EOF

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" phase "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/VERIFICATION.md" ]
}

@test "resolve-verification-path current ignores round verification before verify stage" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
result: PASS
---
EOF
  printf 'stage=plan\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" current "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/01-VERIFICATION.md" ]
}

@test "resolve-verification-path current uses round verification during verify stage" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
result: PASS
---
EOF
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" current "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" ]
}

@test "resolve-verification-path current returns round path after done even when artifact is missing" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
EOF
  printf 'stage=done\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" current "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" ]
}

@test "resolve-verification-path authoritative ignores corrupt stage values" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
result: PASS
---
EOF
  printf 'stage=garbage\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" authoritative "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/01-VERIFICATION.md" ]
}

@test "resolve-verification-path authoritative returns done-stage round path even when artifact is missing" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
EOF
  printf 'stage=done\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" authoritative "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/remediation/qa/round-02/R02-VERIFICATION.md" ]
}

@test "resolve-verification-path plan-input uses previous round verification for round 02 planning" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| R1-01 | must_have | Round-one failure persists | FAIL | Missing |
EOF
  printf 'stage=plan\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" plan-input "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" ]
}

@test "resolve-verification-path plan-input falls back to phase verification when previous round passed with no FAIL rows" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| PH-01 | must_have | Original failure persists | FAIL | Missing |
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
result: PASS
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Structural bookkeeping passed | PASS | Done |
EOF
  printf 'stage=plan\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" plan-input "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/01-VERIFICATION.md" ]
}

@test "resolve-verification-path plan-input uses nearest earlier round with FAIL rows" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01" "$PHASE_DIR/remediation/qa/round-02"
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| PH-01 | must_have | Phase failure | FAIL | Missing |
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| R1-01 | must_have | Round-one failure persists | FAIL | Missing |
EOF
  cat > "$PHASE_DIR/remediation/qa/round-02/R02-VERIFICATION.md" <<'EOF'
---
result: PASS
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Structural bookkeeping passed | PASS | Done |
EOF
  printf 'stage=plan\nround=03\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" plan-input "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" ]
}

@test "resolve-verification-path plan-input returns empty when previous round passed and carried-forward phase verification is missing" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
result: PASS
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Structural bookkeeping passed | PASS | Done |
EOF
  printf 'stage=plan\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" plan-input "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "resolve-verification-path plan-input returns empty when prior artifact is missing" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
EOF
  printf 'stage=plan\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" plan-input "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "resolve-verification-path plan-input falls back to phase verification for round 01" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| PH-01 | must_have | Original failure persists | FAIL | Missing |
EOF
  printf 'stage=plan\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" plan-input "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/01-VERIFICATION.md" ]
}

@test "resolve-verification-path plan-input returns empty when phase verification has no FAIL rows" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: PASS
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Structural bookkeeping passed | PASS | Done |
EOF
  printf 'stage=plan\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" plan-input "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "resolve-verification-path plan-input returns empty when previous round passed and phase verification has no FAIL rows" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: PASS
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Structural bookkeeping passed | PASS | Done |
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
result: PASS
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Structural bookkeeping passed | PASS | Done |
EOF
  printf 'stage=plan\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" plan-input "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# Issue #653: single-plan phase where the writer produced a per-plan
# {NN}-{MM}-VERIFICATION.md must resolve to that artifact, not a synthetic
# phase-level name the gate would read as missing.
@test "resolve-verification-path phase adopts the sole per-plan verification (issue #653 single-plan phase)" {
  cat > "$PHASE_DIR/01-01-VERIFICATION.md" <<'EOF'
---
result: PASS
plans_verified: [01-01]
---
EOF

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" phase "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/01-01-VERIFICATION.md" ]
}

@test "resolve-verification-path phase does NOT adopt per-plan files when more than one exists (ambiguous -> phase-level)" {
  cat > "$PHASE_DIR/01-01-VERIFICATION.md" <<'EOF'
---
result: PASS
---
EOF
  cat > "$PHASE_DIR/01-02-VERIFICATION.md" <<'EOF'
---
result: PASS
---
EOF

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" phase "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/01-VERIFICATION.md" ]
}

@test "resolve-verification-path phase prefers an on-disk phase-level artifact over a per-plan one" {
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: PASS
---
EOF
  cat > "$PHASE_DIR/01-01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
EOF

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" phase "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/01-VERIFICATION.md" ]
}

@test "resolve-verification-path phase prefers wave files over a per-plan one" {
  cat > "$PHASE_DIR/01-VERIFICATION-wave1.md" <<'EOF'
---
result: PASS
---
EOF
  cat > "$PHASE_DIR/01-01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
EOF

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" phase "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/01-VERIFICATION-wave1.md" ]
}

# Regression guard: a numbered phase with NO verification artifact of any kind
# must fall through the per-plan block and return the synthetic phase-level
# name (the pre-existing behavior the #653 block must not disturb).
@test "resolve-verification-path phase returns the synthetic phase-level name when no artifact exists" {
  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" phase "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/01-VERIFICATION.md" ]
}

# Issue #653 (round 1 hardening): the writer's `printf %02d` plan numbering
# yields 3-digit names for the 100th+ plan, so the per-plan fallback must adopt
# a sole {NN}-{MMM}-VERIFICATION.md, not just 2-digit MM.
@test "resolve-verification-path phase adopts a sole 3-digit per-plan verification (100+ plan numbers)" {
  cat > "$PHASE_DIR/01-100-VERIFICATION.md" <<'EOF'
---
result: PASS
plans_verified: [01-100]
---
EOF

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" phase "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/01-100-VERIFICATION.md" ]
}

# Issue #653 (QA round 2): the per-plan glob is greedy; a strict regex re-filter
# must reject non-canonical names whose MM segment is not purely numeric (e.g. a
# trailing letter or an extra `-segment-`), so they are NOT mistaken for the sole
# per-plan artifact. Such names fall through to the canonical phase-level name.
@test "resolve-verification-path phase does NOT adopt a non-canonical per-plan name (over-match guard)" {
  cat > "$PHASE_DIR/01-01a-VERIFICATION.md" <<'EOF'
---
result: PASS
---
EOF
  cat > "$PHASE_DIR/01-01-extra-VERIFICATION.md" <<'EOF'
---
result: PASS
---
EOF

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" phase "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/01-VERIFICATION.md" ]
}

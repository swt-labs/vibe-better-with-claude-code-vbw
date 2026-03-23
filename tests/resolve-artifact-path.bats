#!/usr/bin/env bats
# Tests for scripts/resolve-artifact-path.sh — deterministic artifact filename resolution.

SCRIPT="scripts/resolve-artifact-path.sh"

setup() {
  TEST_DIR=$(mktemp -d)
}

teardown() {
  rm -rf "$TEST_DIR"
}

# --- Per-phase types ---

@test "context: returns {NN}-CONTEXT.md" {
  mkdir -p "$TEST_DIR/03-auth"
  run bash "$SCRIPT" context "$TEST_DIR/03-auth"
  [ "$status" -eq 0 ]
  [ "$output" = "03-CONTEXT.md" ]
}

@test "uat: returns {NN}-UAT.md" {
  mkdir -p "$TEST_DIR/05-deploy"
  run bash "$SCRIPT" uat "$TEST_DIR/05-deploy"
  [ "$status" -eq 0 ]
  [ "$output" = "05-UAT.md" ]
}

@test "verification: returns {NN}-VERIFICATION.md" {
  mkdir -p "$TEST_DIR/01-setup"
  run bash "$SCRIPT" verification "$TEST_DIR/01-setup"
  [ "$status" -eq 0 ]
  [ "$output" = "01-VERIFICATION.md" ]
}

@test "per-phase types zero-pad single-digit phase numbers" {
  mkdir -p "$TEST_DIR/3-auth"
  run bash "$SCRIPT" context "$TEST_DIR/3-auth"
  [ "$status" -eq 0 ]
  [ "$output" = "03-CONTEXT.md" ]
}

@test "per-phase types handle double-digit phase numbers" {
  mkdir -p "$TEST_DIR/12-finalize"
  run bash "$SCRIPT" uat "$TEST_DIR/12-finalize"
  [ "$status" -eq 0 ]
  [ "$output" = "12-UAT.md" ]
}

# --- Plan type: next plan number auto-detection ---

@test "plan: empty dir returns {NN}-01-PLAN.md" {
  mkdir -p "$TEST_DIR/03-auth"
  run bash "$SCRIPT" plan "$TEST_DIR/03-auth"
  [ "$status" -eq 0 ]
  [ "$output" = "03-01-PLAN.md" ]
}

@test "plan: increments from existing new-format plans" {
  mkdir -p "$TEST_DIR/03-auth"
  touch "$TEST_DIR/03-auth/03-01-PLAN.md"
  touch "$TEST_DIR/03-auth/03-02-PLAN.md"
  run bash "$SCRIPT" plan "$TEST_DIR/03-auth"
  [ "$status" -eq 0 ]
  [ "$output" = "03-03-PLAN.md" ]
}

@test "plan: increments from existing legacy-format plans" {
  mkdir -p "$TEST_DIR/02-test"
  touch "$TEST_DIR/02-test/01-PLAN.md"
  touch "$TEST_DIR/02-test/02-PLAN.md"
  touch "$TEST_DIR/02-test/03-PLAN.md"
  run bash "$SCRIPT" plan "$TEST_DIR/02-test"
  [ "$status" -eq 0 ]
  [ "$output" = "02-04-PLAN.md" ]
}

@test "plan: handles mixed legacy and new-format plans" {
  mkdir -p "$TEST_DIR/01-setup"
  touch "$TEST_DIR/01-setup/01-PLAN.md"       # legacy format, plan 1
  touch "$TEST_DIR/01-setup/01-02-PLAN.md"    # new format, plan 2
  run bash "$SCRIPT" plan "$TEST_DIR/01-setup"
  [ "$status" -eq 0 ]
  [ "$output" = "01-03-PLAN.md" ]
}

@test "plan: explicit --plan-number returns that plan" {
  mkdir -p "$TEST_DIR/03-auth"
  run bash "$SCRIPT" plan "$TEST_DIR/03-auth" --plan-number 5
  [ "$status" -eq 0 ]
  [ "$output" = "03-05-PLAN.md" ]
}

@test "plan: explicit --plan-number=N returns that plan" {
  mkdir -p "$TEST_DIR/03-auth"
  run bash "$SCRIPT" plan "$TEST_DIR/03-auth" --plan-number=7
  [ "$status" -eq 0 ]
  [ "$output" = "03-07-PLAN.md" ]
}

@test "plan: zero-pads plan numbers to 2 digits" {
  mkdir -p "$TEST_DIR/01-setup"
  run bash "$SCRIPT" plan "$TEST_DIR/01-setup" --plan-number 1
  [ "$status" -eq 0 ]
  [ "$output" = "01-01-PLAN.md" ]
}

@test "plan: skips non-PLAN.md files in glob" {
  mkdir -p "$TEST_DIR/03-auth"
  touch "$TEST_DIR/03-auth/03-01-PLAN.md"
  touch "$TEST_DIR/03-auth/03-01-SUMMARY.md"
  touch "$TEST_DIR/03-auth/03-CONTEXT.md"
  touch "$TEST_DIR/03-auth/03-RESEARCH.md"
  run bash "$SCRIPT" plan "$TEST_DIR/03-auth"
  [ "$status" -eq 0 ]
  [ "$output" = "03-02-PLAN.md" ]
}

@test "plan: ignores PLAN.md without number prefix" {
  mkdir -p "$TEST_DIR/01-setup"
  touch "$TEST_DIR/01-setup/PLAN.md"
  run bash "$SCRIPT" plan "$TEST_DIR/01-setup"
  [ "$status" -eq 0 ]
  [ "$output" = "01-01-PLAN.md" ]
}

# --- Summary type ---

@test "summary: requires --plan-number" {
  mkdir -p "$TEST_DIR/03-auth"
  run bash "$SCRIPT" summary "$TEST_DIR/03-auth"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--plan-number is required"* ]]
}

@test "summary: returns {NN}-{MM}-SUMMARY.md" {
  mkdir -p "$TEST_DIR/03-auth"
  run bash "$SCRIPT" summary "$TEST_DIR/03-auth" --plan-number 2
  [ "$status" -eq 0 ]
  [ "$output" = "03-02-SUMMARY.md" ]
}

# --- Research type ---

@test "research: requires --plan-number" {
  mkdir -p "$TEST_DIR/03-auth"
  run bash "$SCRIPT" research "$TEST_DIR/03-auth"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--plan-number is required"* ]]
}

@test "research: returns {NN}-{MM}-RESEARCH.md" {
  mkdir -p "$TEST_DIR/05-deploy"
  run bash "$SCRIPT" research "$TEST_DIR/05-deploy" --plan-number 3
  [ "$status" -eq 0 ]
  [ "$output" = "05-03-RESEARCH.md" ]
}

# --- Error handling ---

@test "missing type exits 1 with usage" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "unknown type exits 1" {
  mkdir -p "$TEST_DIR/01-setup"
  run bash "$SCRIPT" bogus "$TEST_DIR/01-setup"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown type"* ]]
}

@test "missing phase-dir exits 1" {
  run bash "$SCRIPT" plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"required"* ]]
}

@test "nonexistent phase-dir exits 2" {
  run bash "$SCRIPT" plan "$TEST_DIR/does-not-exist"
  [ "$status" -eq 2 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "non-numeric phase dir prefix exits 1" {
  mkdir -p "$TEST_DIR/no-number"
  run bash "$SCRIPT" context "$TEST_DIR/no-number"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot extract phase number"* ]]
}

@test "trailing slash on phase-dir is handled" {
  mkdir -p "$TEST_DIR/03-auth"
  run bash "$SCRIPT" context "$TEST_DIR/03-auth/"
  [ "$status" -eq 0 ]
  [ "$output" = "03-CONTEXT.md" ]
}

@test "unknown option exits 1" {
  mkdir -p "$TEST_DIR/01-setup"
  run bash "$SCRIPT" plan "$TEST_DIR/01-setup" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option"* ]]
}

# --- Integration: round-trip with phase-state-utils consumers ---

@test "plan output matches count_phase_plans glob pattern" {
  mkdir -p "$TEST_DIR/03-auth"
  # Create a plan using the script's output filename
  PLAN_NAME=$(bash "$SCRIPT" plan "$TEST_DIR/03-auth")
  touch "$TEST_DIR/03-auth/$PLAN_NAME"
  # Verify phase-state-utils glob would find it
  count=$(find "$TEST_DIR/03-auth" -maxdepth 1 ! -name '.*' \( -name '[0-9]*-PLAN.md' -o -name 'PLAN.md' \) 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
}

@test "summary output matches hard-gate.sh derivation pattern" {
  mkdir -p "$TEST_DIR/03-auth"
  PLAN_NAME=$(bash "$SCRIPT" plan "$TEST_DIR/03-auth" --plan-number 2)
  SUMMARY_NAME=$(bash "$SCRIPT" summary "$TEST_DIR/03-auth" --plan-number 2)
  # hard-gate.sh derives SUMMARY from PLAN: ${plan%-PLAN.md}-SUMMARY.md
  DERIVED="${PLAN_NAME%-PLAN.md}-SUMMARY.md"
  [ "$DERIVED" = "$SUMMARY_NAME" ]
}

@test "plan number extraction matches hard-gate.sh sed pattern" {
  mkdir -p "$TEST_DIR/03-auth"
  PLAN_NAME=$(bash "$SCRIPT" plan "$TEST_DIR/03-auth" --plan-number 4)
  # hard-gate.sh: sed 's/^[0-9]*-\([0-9]*\)-.*/\1/'
  EXTRACTED=$(echo "$PLAN_NAME" | sed 's/^[0-9]*-\([0-9]*\)-.*/\1/')
  [ "$EXTRACTED" = "04" ]
}

# --- Contract: callsite wiring ---

@test "contract: vibe.md Plan mode calls resolve-artifact-path.sh" {
  count=$(grep -c 'resolve-artifact-path\.sh' commands/vibe.md)
  [ "$count" -ge 3 ]  # context, plan, research, turbo
}

@test "contract: vbw-lead.md references resolve-artifact-path.sh" {
  grep -q 'resolve-artifact-path\.sh\|RESOLVE_SCRIPT' agents/vbw-lead.md
}

@test "contract: execute-protocol.md calls resolve-artifact-path.sh" {
  grep -q 'resolve-artifact-path\.sh' references/execute-protocol.md
}

@test "contract: discussion-engine.md calls resolve-artifact-path.sh" {
  grep -q 'resolve-artifact-path\.sh' references/discussion-engine.md
}

@test "contract: compile-verify-context.sh calls resolve-artifact-path.sh" {
  grep -q 'resolve-artifact-path\.sh' scripts/compile-verify-context.sh
}

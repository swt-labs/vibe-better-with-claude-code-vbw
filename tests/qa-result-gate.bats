#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/qa-result-gate.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  # Use numbered phase-dir prefix to match production convention ({NN}-slug)
  PHASE_DIR="$TEST_DIR/01-test-phase"
  mkdir -p "$PHASE_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: create a VERIFICATION.md with given frontmatter fields and optional body
create_verif() {
  local writer="${1:-write-verification.sh}"
  local result="${2:-PASS}"
  local body="${3:-}"
  {
    echo "---"
    echo "phase: 01"
    echo "tier: full"
    echo "result: $result"
    echo "passed: 10"
    echo "failed: 0"
    echo "total: 10"
    echo "date: 2026-03-27"
    if [ "$writer" != "OMIT" ]; then
      echo "writer: $writer"
    fi
    echo "---"
    echo ""
    if [ -n "$body" ]; then
      printf '%s\n' "$body"
    fi
  } > "$PHASE_DIR/01-VERIFICATION.md"
}

# Helper: create a SUMMARY.md with YAML frontmatter deviations
create_summary_with_yaml_deviations() {
  local plan_id="${1}"
  local deviations="${2:-}"  # newline-separated deviation items
  {
    echo "---"
    echo "plan: $plan_id"
    if [ -n "$deviations" ]; then
      echo "deviations:"
      while IFS= read -r dev; do
        [ -n "$dev" ] && echo "  - \"$dev\""
      done <<< "$deviations"
    fi
    echo "---"
    echo ""
    echo "## Summary"
    echo "Work completed."
  } > "$PHASE_DIR/${plan_id}-SUMMARY.md"
}

# Helper: create a SUMMARY.md with body-only deviations (no YAML)
create_summary_with_body_deviations() {
  local plan_id="${1}"
  local deviations="${2:-}"  # newline-separated deviation items
  {
    echo "---"
    echo "plan: $plan_id"
    echo "---"
    echo ""
    echo "## Deviations"
    if [ -n "$deviations" ]; then
      while IFS= read -r dev; do
        [ -n "$dev" ] && echo "- $dev"
      done <<< "$deviations"
    else
      echo "- None"
    fi
    echo ""
    echo "## Summary"
    echo "Work completed."
  } > "$PHASE_DIR/${plan_id}-SUMMARY.md"
}

# Helper: create a PLAN.md stub
create_plan() {
  local plan_id="${1}"
  {
    echo "---"
    echo "plan: $plan_id"
    echo "---"
    echo ""
    echo "## Objective"
    echo "Test plan for $plan_id"
  } > "$PHASE_DIR/${plan_id}-PLAN.md"
}

@test "PASS with clean body → PROCEED_TO_UAT" {
  create_verif "write-verification.sh" "PASS" "## Must-Have Checks
| Check | Status |
|-------|--------|
| Feature works | PASS |"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
  [[ "$output" == *"qa_gate_writer=write-verification.sh"* ]]
  [[ "$output" == *"qa_gate_result=PASS"* ]]
  [[ "$output" == *"qa_gate_fail_count=0"* ]]
}

@test "PASS with FAIL rows in body → REMEDIATION_REQUIRED (override)" {
  create_verif "write-verification.sh" "PASS" "## Must-Have Checks
| Check | Status |
|-------|--------|
| Feature works | PASS |
| Edge case | FAIL |"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_fail_count=1"* ]]
}

@test "PARTIAL result → REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "PARTIAL"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_result=PARTIAL"* ]]
}

@test "FAIL result → REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "FAIL"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_result=FAIL"* ]]
}

@test "wrong writer → QA_RERUN_REQUIRED" {
  create_verif "manual-write" "PASS"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_writer=manual-write"* ]]
}

@test "missing writer field → QA_RERUN_REQUIRED" {
  create_verif "OMIT" "PASS"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_writer=missing"* ]]
}

@test "missing VERIFICATION.md → QA_RERUN_REQUIRED" {
  # Don't create any file
  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_result=missing"* ]]
}

@test "empty result field → QA_RERUN_REQUIRED" {
  # Create file with writer but empty result
  {
    echo "---"
    echo "phase: 01"
    echo "tier: full"
    echo "result: "
    echo "writer: write-verification.sh"
    echo "---"
  } > "$PHASE_DIR/01-VERIFICATION.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "unknown result value → QA_RERUN_REQUIRED" {
  create_verif "write-verification.sh" "UNKNOWN_VALUE"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "missing phase-dir argument → QA_RERUN_REQUIRED" {
  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "custom verif-name argument" {
  create_verif "write-verification.sh" "PASS"
  mv "$PHASE_DIR/01-VERIFICATION.md" "$PHASE_DIR/CUSTOM-VERIF.md"

  run bash "$SCRIPT" "$PHASE_DIR" "CUSTOM-VERIF.md"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "bold FAIL markers in body are counted" {
  create_verif "write-verification.sh" "PASS" "## Checks
| Check | Status |
|-------|--------|
| Feature | **FAIL** |
| Other | PASS |"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_fail_count=1"* ]]
}

@test "empty file → QA_RERUN_REQUIRED" {
  touch "$PHASE_DIR/01-VERIFICATION.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_writer=missing"* ]]
}

@test "no frontmatter delimiters → QA_RERUN_REQUIRED" {
  printf 'Just some text without frontmatter\n' > "$PHASE_DIR/01-VERIFICATION.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_writer=missing"* ]]
}

@test "FAIL result with multiple FAIL rows → correct count" {
  create_verif "write-verification.sh" "FAIL" "## Checks
| Check | Status |
|-------|--------|
| Feature A | FAIL |
| Feature B | FAIL |
| Feature C | PASS |"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_result=FAIL"* ]]
  [[ "$output" == *"qa_gate_fail_count=2"* ]]
}

@test "trailing whitespace in result field is stripped" {
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'VERIF'
---
result: PASS 
writer: write-verification.sh
---
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
  [[ "$output" == *"qa_gate_result=PASS"* ]]
}

@test "auto-resolves {NN}-VERIFICATION.md from phase-dir prefix" {
  # Phase dir is 01-test-phase, so gate should find 01-VERIFICATION.md
  create_verif "write-verification.sh" "PASS"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
  # Confirm the auto-resolved file was actually read (not a false positive from missing-file path)
  [[ "$output" == *"qa_gate_writer=write-verification.sh"* ]]
}

@test "brownfield fallback to plain VERIFICATION.md" {
  # Create a phase dir WITHOUT numbered prefix
  BROWNFIELD_DIR="$TEST_DIR/legacy-phase"
  mkdir -p "$BROWNFIELD_DIR"
  {
    echo "---"
    echo "result: PASS"
    echo "writer: write-verification.sh"
    echo "---"
  } > "$BROWNFIELD_DIR/VERIFICATION.md"

  run bash "$SCRIPT" "$BROWNFIELD_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
  [[ "$output" == *"qa_gate_writer=write-verification.sh"* ]]
}

@test "multi-digit phase number resolves correctly" {
  MULTI_DIR="$TEST_DIR/10-multi-digit-phase"
  mkdir -p "$MULTI_DIR"
  {
    echo "---"
    echo "result: PASS"
    echo "writer: write-verification.sh"
    echo "---"
  } > "$MULTI_DIR/10-VERIFICATION.md"

  run bash "$SCRIPT" "$MULTI_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
  [[ "$output" == *"qa_gate_writer=write-verification.sh"* ]]
}

@test "prefixed file takes priority over plain VERIFICATION.md" {
  # Both {NN}-VERIFICATION.md and VERIFICATION.md exist — prefixed wins
  {
    echo "---"
    echo "result: PASS"
    echo "writer: write-verification.sh"
    echo "---"
  } > "$PHASE_DIR/01-VERIFICATION.md"
  {
    echo "---"
    echo "result: FAIL"
    echo "writer: write-verification.sh"
    echo "---"
  } > "$PHASE_DIR/VERIFICATION.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # Should read the prefixed file (PASS), not the plain one (FAIL)
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
  [[ "$output" == *"qa_gate_result=PASS"* ]]
}

# ============================================================
# Deviation cross-check tests
# ============================================================

@test "PASS + YAML deviations in SUMMARY.md → QA_RERUN_REQUIRED with deviation_override" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Used different API than planned"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=1"* ]]
  [[ "$output" == *"qa_gate_deviation_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "PASS + body-only deviations in SUMMARY.md → QA_RERUN_REQUIRED" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_body_deviations "01-01" "Skipped error handling for edge case"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=1"* ]]
  [[ "$output" == *"qa_gate_deviation_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "PASS + placeholder deviations (None) → PROCEED_TO_UAT" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "None"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=0"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "PASS + placeholder deviations (N/A) → PROCEED_TO_UAT" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "N/A"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=0"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "PASS + body placeholder (**None**) → PROCEED_TO_UAT" {
  create_verif "write-verification.sh" "PASS"
  {
    echo "---"
    echo "plan: 01-01"
    echo "---"
    echo ""
    echo "## Deviations"
    echo "- **None**"
  } > "$PHASE_DIR/01-01-SUMMARY.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=0"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "FAIL + deviations → REMEDIATION_REQUIRED (deviations don't change FAIL routing)" {
  create_verif "write-verification.sh" "FAIL"
  create_summary_with_yaml_deviations "01-01" "Used different API than planned"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=1"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "PASS + multiple SUMMARY.md files with deviations → aggregated count" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Changed API endpoint"
  create_summary_with_body_deviations "01-02" "$(printf 'Skipped validation\nUsed different model')"
  create_summary_with_yaml_deviations "01-03" "None"  # placeholder — not counted

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=3"* ]]
  [[ "$output" == *"qa_gate_deviation_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "PASS + no SUMMARY.md files → PROCEED_TO_UAT (no deviation check)" {
  create_verif "write-verification.sh" "PASS"
  # No SUMMARY.md files — standalone QA or legacy phase

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=0"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "PASS + deviations with multiple items in YAML array → all counted" {
  create_verif "write-verification.sh" "PASS"
  {
    echo "---"
    echo "plan: 01-01"
    echo "deviations:"
    echo "  - \"Changed error handling approach\""
    echo "  - \"Skipped optional caching layer\""
    echo "  - \"Used URLSession instead of Alamofire\""
    echo "---"
    echo ""
    echo "## Summary"
    echo "Work completed."
  } > "$PHASE_DIR/01-01-SUMMARY.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=3"* ]]
  [[ "$output" == *"qa_gate_deviation_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "diagnostic fields always present even with no deviations or plans" {
  create_verif "write-verification.sh" "PASS"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=0"* ]]
  [[ "$output" == *"qa_gate_plan_count=0"* ]]
  [[ "$output" == *"qa_gate_plans_verified_count=0"* ]]
}

# ============================================================
# Plan coverage tests
# ============================================================

@test "PASS + plans_verified < plan_count → QA_RERUN_REQUIRED" {
  # Create 3 PLAN.md files but VERIFICATION.md only lists 2 plans_verified
  create_plan "01-01"
  create_plan "01-02"
  create_plan "01-03"
  {
    echo "---"
    echo "phase: 01"
    echo "result: PASS"
    echo "passed: 10"
    echo "failed: 0"
    echo "total: 10"
    echo "writer: write-verification.sh"
    echo "plans_verified:"
    echo "  - 01-01"
    echo "  - 01-02"
    echo "---"
  } > "$PHASE_DIR/01-VERIFICATION.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_plan_count=3"* ]]
  [[ "$output" == *"qa_gate_plans_verified_count=2"* ]]
  [[ "$output" == *"qa_gate_plan_coverage=2/3"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "PASS + plans_verified == plan_count → PROCEED_TO_UAT" {
  create_plan "01-01"
  create_plan "01-02"
  {
    echo "---"
    echo "phase: 01"
    echo "result: PASS"
    echo "passed: 10"
    echo "failed: 0"
    echo "total: 10"
    echo "writer: write-verification.sh"
    echo "plans_verified:"
    echo "  - 01-01"
    echo "  - 01-02"
    echo "---"
  } > "$PHASE_DIR/01-VERIFICATION.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_plan_count=2"* ]]
  [[ "$output" == *"qa_gate_plans_verified_count=2"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "PASS + plans_verified absent (brownfield) → PROCEED_TO_UAT" {
  create_plan "01-01"
  create_plan "01-02"
  # No plans_verified in frontmatter — brownfield compat
  create_verif "write-verification.sh" "PASS"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_plan_count=2"* ]]
  [[ "$output" == *"qa_gate_plans_verified_count=0"* ]]
  # Brownfield: plans_verified_count=0 means field absent → skip check
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "PASS + no PLAN.md files → PROCEED_TO_UAT (no coverage check)" {
  # Standalone QA — no plans to cover
  create_verif "write-verification.sh" "PASS"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_plan_count=0"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "FAIL + incomplete plan coverage → REMEDIATION_REQUIRED (plan coverage doesn't change FAIL routing)" {
  create_plan "01-01"
  create_plan "01-02"
  {
    echo "---"
    echo "phase: 01"
    echo "result: FAIL"
    echo "passed: 8"
    echo "failed: 2"
    echo "total: 10"
    echo "writer: write-verification.sh"
    echo "plans_verified:"
    echo "  - 01-01"
    echo "---"
  } > "$PHASE_DIR/01-VERIFICATION.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "deviation override takes priority over plan coverage check" {
  # Both deviation and plan coverage would trigger — deviation fires first
  create_plan "01-01"
  create_plan "01-02"
  create_summary_with_yaml_deviations "01-01" "Changed approach"
  {
    echo "---"
    echo "phase: 01"
    echo "result: PASS"
    echo "passed: 10"
    echo "failed: 0"
    echo "total: 10"
    echo "writer: write-verification.sh"
    echo "plans_verified:"
    echo "  - 01-01"
    echo "---"
  } > "$PHASE_DIR/01-VERIFICATION.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

# ============================================================
# Remediation-awareness tests (F-01)
# ============================================================

@test "PASS + deviations during active remediation → PROCEED_TO_UAT (deviation override suppressed)" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Changed API approach"
  # Simulate active remediation cycle
  mkdir -p "$PHASE_DIR/remediation/qa"
  echo "stage=verify" > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=1"* ]]
  # Deviation override should NOT fire during remediation
  [[ "$output" != *"qa_gate_deviation_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "PASS + deviations without remediation → QA_RERUN_REQUIRED (deviation override fires)" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Changed API approach"
  # No .qa-remediation-stage file → not in remediation

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=1"* ]]
  [[ "$output" == *"qa_gate_deviation_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "FAIL during remediation still routes to REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "FAIL"
  create_summary_with_yaml_deviations "01-01" "Changed API approach"
  mkdir -p "$PHASE_DIR/remediation/qa"
  echo "stage=verify" > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "deviation starting with None-word is counted (not filtered as placeholder)" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "None of the planned endpoints were implemented"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=1"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "PASS + deviations + incomplete plan coverage → both diagnostics emitted" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Changed API design"
  # 2 plans but verification only covers 1
  create_plan "01-01"
  create_plan "01-02"
  # Add plans_verified to VERIFICATION.md frontmatter (only plan 01-01)
  local vf="$PHASE_DIR/01-VERIFICATION.md"
  sed -i '' '/^result:/a\
plans_verified: 01-01' "$vf"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_override=true"* ]]
  [[ "$output" == *"qa_gate_plan_coverage=1/2"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

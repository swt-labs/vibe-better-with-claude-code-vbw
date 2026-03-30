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
  local verified_at_commit="${4:-}"
  {
    echo "---"
    echo "phase: 01"
    echo "tier: full"
    echo "result: $result"
    echo "passed: 10"
    echo "failed: 0"
    echo "total: 10"
    echo "date: 2026-03-27"
    if [ -n "$verified_at_commit" ]; then
      echo "verified_at_commit: $verified_at_commit"
    fi
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

init_git_repo() {
  git -C "$TEST_DIR" init -q
  git -C "$TEST_DIR" config user.email "test@example.com"
  git -C "$TEST_DIR" config user.name "VBW Test"
}

commit_repo_file() {
  local relative_path="${1}"
  local content="${2:-content}"
  mkdir -p "$(dirname "$TEST_DIR/$relative_path")"
  printf '%s\n' "$content" > "$TEST_DIR/$relative_path"
  git -C "$TEST_DIR" add "$relative_path"
  git -C "$TEST_DIR" commit -q -m "add $relative_path"
  git -C "$TEST_DIR" rev-parse HEAD
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

@test "plan-amendment does not accept sibling-phase traversal path" {
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-0101 | must_have | Plan must be amended | FAIL | Missing rationale |"
  create_plan "01-01"
  mkdir -p "$TEST_DIR/02-other-phase"
  cat > "$TEST_DIR/02-other-phase/02-01-PLAN.md" <<'PLAN'
---
plan: 02-01
---

## Objective
Sibling phase plan
PLAN

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "../02-other-phase/02-01-PLAN.md"
  - ".vbw-planning/phases/01-test-phase/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Sibling phase traversal is not a valid plan amendment
fail_classifications:
  - {id: "FAIL-0101", type: "plan-amendment", rationale: "Original plan should be updated", source_plan: "../02-other-phase/02-01-PLAN.md"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Notes updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "plan-amendment requires actual round diff to include the original plan when git evidence is available" {
  init_git_repo
  mkdir -p "$TEST_DIR/docs"
  baseline_commit=$(commit_repo_file "01-test-phase/01-01-PLAN.md" "original plan")
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-0101 | must_have | Plan must be amended | FAIL | Missing rationale |" "$baseline_commit"
  commit_repo_file "README.md" "docs-only follow-up" >/dev/null

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\nround_started_at_commit=%s\n' "$baseline_commit" > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "01-01-PLAN.md"
  - "README.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Claimed plan amendment must be corroborated by the round diff
fail_classifications:
  - {id: "FAIL-0101", type: "plan-amendment", rationale: "Original plan should be updated", source_plan: "01-01-PLAN.md"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Documentation updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
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

@test "PASS with FAIL in non-status column does not trigger fail override" {
  create_verif "write-verification.sh" "PASS" "## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| CHK-01 | must_have | Contains FAIL token in description | PASS | Done |
| CHK-02 | must_have | Clean status | PASS | FAIL |"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_fail_count=0"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "PASS with flow-style YAML deviations → QA_RERUN_REQUIRED" {
  create_verif "write-verification.sh" "PASS"
  cat > "$PHASE_DIR/01-01-SUMMARY.md" <<'SUMMARY'
---
plan: 01-01
deviations: ["Changed API contract", 'Moved tests to existing file']
---

## Summary
Work completed.
SUMMARY

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=2"* ]]
  [[ "$output" == *"qa_gate_deviation_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
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

@test "during remediation verify stage gate reads current round verification" {
  create_verif "write-verification.sh" "FAIL"
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "src/Feature.swift"'
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'EOF'
---
round: 01
title: Current round verification should be authoritative
fail_classifications:
  - {id: "FAIL-01", type: "process-exception", rationale: "Current round verification fixture uses a synthetic FAIL source with no stable table IDs"}
---
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
phase: 01
tier: full
result: PASS
passed: 10
failed: 0
total: 10
date: 2026-03-27
writer: write-verification.sh
plans_verified:
  - R01
---

## Must-Have Checks
| Check | Status |
|-------|--------|
| Feature works | PASS |
EOF
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_result=PASS"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "during remediation plan stage gate ignores stale round verification" {
  create_verif "write-verification.sh" "FAIL"
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
phase: 01
tier: full
result: PASS
passed: 10
failed: 0
total: 10
date: 2026-03-27
writer: write-verification.sh
---

## Must-Have Checks
| Check | Status |
|-------|--------|
| Feature works | PASS |
EOF
  printf 'stage=plan\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_result=FAIL"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "corrupt remediation stage does not suppress deviation override" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Used different API than planned"
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=garbage\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=1"* ]]
  [[ "$output" == *"qa_gate_deviation_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "during remediation verify stage missing round verification fails closed" {
  create_verif "write-verification.sh" "PASS"
  mkdir -p "$PHASE_DIR/remediation/qa/round-02"
  printf 'stage=verify\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_result=missing"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
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

@test "legacy PLAN.md and SUMMARY.md count toward gate plan and deviation checks" {
  cat > "$PHASE_DIR/PLAN.md" <<'PLAN'
---
plan: 01
title: Legacy plan
---
PLAN
  cat > "$PHASE_DIR/SUMMARY.md" <<'SUMMARY'
---
plan: 01
deviations:
  - "Legacy deviation"
---

## Summary
Legacy work completed.
SUMMARY
  create_verif "write-verification.sh" "PASS"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_plan_count=1"* ]]
  [[ "$output" == *"qa_gate_deviation_count=1"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "PASS + plans_verified absent → QA_RERUN_REQUIRED" {
  create_plan "01-01"
  create_plan "01-02"
  # No plans_verified in frontmatter — invalid when plan files exist
  create_verif "write-verification.sh" "PASS"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_plan_count=2"* ]]
  [[ "$output" == *"qa_gate_plans_verified_count=0"* ]]
  [[ "$output" == *"qa_gate_plan_coverage=0/2"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
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
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "src/Fix.swift"'
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Fix | PASS | Done |
VERIF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Fix
fail_classifications:
  - {id: "DEV-0101-COMMIT", type: "process-exception", rationale: "Historical git topology cannot be safely rewritten"}
---
PLAN

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # Historical phase-root deviations are ignored during active remediation when
  # the current round verification is authoritative.
  [[ "$output" == *"qa_gate_deviation_count=0"* ]]
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
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: FAIL
plans_verified:
  - R01
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Fix | FAIL | Broken |
VERIF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Fix
fail_classifications:
  - {id: "DEV-0101-COMMIT", type: "process-exception", rationale: "Historical git topology cannot be safely rewritten"}
---
PLAN

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
  create_summary_with_yaml_deviations "01-01" "Changed API design"
  # 2 plans but verification only covers 1
  create_plan "01-01"
  create_plan "01-02"
  # Write VERIFICATION.md with proper YAML array for plans_verified (only plan 01-01)
  cat > "$PHASE_DIR/01-VERIFICATION.md" << 'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - 01-01
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Test | PASS | ok |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_override=true"* ]]
  [[ "$output" == *"qa_gate_plan_coverage=1/2"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "unreadable VERIFICATION.md → QA_RERUN_REQUIRED" {
  create_verif "write-verification.sh" "PASS"
  chmod 000 "$PHASE_DIR/01-VERIFICATION.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_result=unreadable"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]

  # Restore permissions for cleanup
  chmod 644 "$PHASE_DIR/01-VERIFICATION.md"
}

# --- Round VERIFICATION.md auto-discovery ---

@test "gate reads round VERIFICATION.md when remediation active" {
  # Phase-level VERIFICATION.md with original FAIL
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Widget | FAIL | Broken |"

  # Active QA remediation with round-01 VERIFICATION.md that PASSes
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "src/Widget.swift"'
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" << 'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Widget | PASS | Fixed |
VERIF
  # Round-dir plan for plan coverage alignment
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" << 'PLAN'
---
round: 01
title: Fix widget
fail_classifications:
  - {id: "MH-01", type: "code-fix", rationale: "Widget code changed to resolve the failing must-have"}
---
PLAN

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_result=PASS"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "gate reads phase-level when no remediation active" {
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Widget | FAIL | Broken |"

  # No .qa-remediation-stage file

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_result=FAIL"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "plan coverage scoped to round dir during remediation" {
  create_verif "write-verification.sh" "PASS"
  # Phase-level: 3 plans
  create_plan "01-01"
  create_plan "01-02"
  create_plan "01-03"

  # Active remediation with 1 round plan
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "src/Fix.swift"'
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" << 'PLAN'
---
round: 01
title: Fix issues
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" << 'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Fix | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # Plan count should be 1 (round dir), not 3 (phase dir)
  [[ "$output" == *"qa_gate_plan_count=1"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "gate falls back to phase-level if round VERIFICATION.md missing" {
  # Phase-level VERIFICATION.md
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Widget | FAIL | Broken |"

  # Active remediation but NO round VERIFICATION.md yet
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=execute\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # Falls back to phase-level (FAIL)
  [[ "$output" == *"qa_gate_result=FAIL"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "gate reads round-02 VERIFICATION.md correctly" {
  # Phase-level VERIFICATION.md with original FAIL
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Widget | FAIL | Broken |"

  # Active QA remediation at round 02
  mkdir -p "$PHASE_DIR/remediation/qa/round-01" "$PHASE_DIR/remediation/qa/round-02"
  printf 'stage=verify\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" << 'VERIF'
---
writer: write-verification.sh
result: FAIL
plans_verified:
  - R01
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Widget | FAIL | Still broken |
VERIF
  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-02" "02" \
    '  - "src/Widget.swift"'
  cat > "$PHASE_DIR/remediation/qa/round-02/R02-VERIFICATION.md" << 'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R02
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Widget | PASS | Fixed |
VERIF
  cat > "$PHASE_DIR/remediation/qa/round-02/R02-PLAN.md" << 'PLAN'
---
round: 02
title: Fix widget again
fail_classifications:
  - {id: "MH-01", type: "code-fix", rationale: "Widget code changed again to resolve the remaining failing must-have"}
---
PLAN

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_result=PASS"* ]]
  [[ "$output" == *"qa_gate_plan_count=1"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "gate handles unpadded round number in state file" {
  # Phase-level FAIL
  create_verif "write-verification.sh" "FAIL"

  # State file with unpadded round=2 (brownfield/corruption)
  mkdir -p "$PHASE_DIR/remediation/qa/round-01" "$PHASE_DIR/remediation/qa/round-02"
  printf 'stage=verify\nround=2\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" << 'VERIF'
---
writer: write-verification.sh
result: FAIL
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Test | FAIL | still broken |
VERIF
  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-02" "02" \
    '  - "src/Fix.swift"'
  cat > "$PHASE_DIR/remediation/qa/round-02/R02-VERIFICATION.md" << 'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R02
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Test | PASS | ok |
VERIF
  cat > "$PHASE_DIR/remediation/qa/round-02/R02-PLAN.md" << 'PLAN'
---
round: 02
title: Fix
fail_classifications:
  - {id: "MH-01", type: "code-fix", rationale: "Round-02 code change resolves the prior failing must-have"}
---
PLAN

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # Should find round-02 file despite unpadded round=2 in state
  [[ "$output" == *"qa_gate_result=PASS"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "gate handles non-numeric round in state file gracefully" {
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Widget | FAIL | Broken |"

  # State file with corrupt non-numeric round
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=verify\nround=abc\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPT" "$PHASE_DIR"

  # Must exit 0 (gate contract) and fail closed because the implied round-01
  # verification artifact is missing.
  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_result=missing"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "current-round deviations during remediation still require QA rerun" {
  # Historical phase-level verification stays frozen as FAIL
  create_verif "write-verification.sh" "FAIL"
  create_summary_with_yaml_deviations "01-01" "Historical deviation"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Fix regression
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md" <<'SUMMARY'
---
plan: R01
status: complete
files_modified:
  - src/Fix.swift
deviations:
  - "Used alternate fix path"
---

## Summary
Remediation applied.
SUMMARY
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Regression fixed | PASS | ok |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=1"* ]]
  [[ "$output" == *"qa_gate_deviation_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "explicit verif-name override is preserved during active remediation" {
  create_verif "write-verification.sh" "FAIL"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Regression fixed | PASS | ok |
VERIF
  cat > "$PHASE_DIR/CUSTOM-VERIF.md" <<'VERIF'
---
writer: write-verification.sh
result: FAIL
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-99 | must_have | Custom override | FAIL | forced |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR" "CUSTOM-VERIF.md"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_result=FAIL"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

# --- Metadata-only round detection tests ---

# Helper: create a round SUMMARY.md with files_modified in YAML frontmatter
create_round_summary_with_files() {
  local round_dir="${1}"
  local round="${2}"
  local files_yaml="${3:-}"  # pre-formatted YAML lines for files_modified
  local commits_yaml="${4:-}"  # pre-formatted YAML lines for commit_hashes
  {
    echo "---"
    echo "plan: R${round}"
    echo "status: complete"
    if [ -n "$commits_yaml" ]; then
      echo "commit_hashes:"
      echo "$commits_yaml"
    else
      echo "commit_hashes: []"
    fi
    if [ -n "$files_yaml" ]; then
      echo "files_modified:"
      echo "$files_yaml"
    else
      echo "files_modified: []"
    fi
    echo "deviations: []"
    echo "---"
    echo ""
    echo "## Summary"
    echo "Work done."
  } > "${round_dir}/R${round}-SUMMARY.md"
}

@test "metadata-only round with phase-level deviations → REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "PASS"
  # Phase-level SUMMARY.md has real deviations
  create_summary_with_yaml_deviations "01-01" "Changed API approach"

  # Set up active remediation
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  # Round SUMMARY.md modifies ONLY .vbw-planning/ files — no code changes
  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".vbw-planning/phases/01-test/01-01-SUMMARY.md"
  - ".vbw-planning/phases/01-test/01-03-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Document deviations
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Deviations documented | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_phase_deviation_count=1"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "metadata-only round with zero phase-level deviations → PROCEED_TO_UAT" {
  create_verif "write-verification.sh" "PASS"
  # Phase-level SUMMARY.md has NO deviations
  create_summary_with_yaml_deviations "01-01" "None"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".vbw-planning/phases/01-test/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Fix
fail_classifications:
  - {id: "DEV-0101-COMMIT", type: "process-exception", rationale: "Historical git topology cannot be safely rewritten"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Fix done | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "metadata-only round with only process-exception classifications → PROCEED_TO_UAT" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Historical batched commit"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".vbw-planning/phases/01-test/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Document process exception
fail_classifications:
  - {id: "DEV-0101-COMMIT", type: "process-exception", rationale: "Historical git topology cannot be safely rewritten"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Process exception documented | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "metadata-only round with missing fail_classifications → REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Historical orchestration issue"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".vbw-planning/phases/01-test/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Missing classifications should fail closed
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Remediation documented | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "metadata-only round with inline fail_classifications process-exception → PROCEED_TO_UAT" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Historical batched commit"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".vbw-planning/phases/01-test/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Inline classifications
fail_classifications: [{id: "DEV-0101-COMMIT", type: "process-exception", rationale: "Historical git topology cannot be safely rewritten"}]
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Process exception documented | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "metadata-only round with code-fix classification and zero deviations → REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "None"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".vbw-planning/phases/01-test/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Metadata-only round cannot satisfy code fix
fail_classifications:
  - {id: "FAIL-0101", type: "code-fix", rationale: "Code must change to match the plan"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Documentation updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "plan-amendment without required source plan edit → REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-0101 | must_have | Plan must be amended | FAIL | Missing rationale |"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "README.md"
  - ".vbw-planning/phases/01-test/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Plan amendment requires plan edit
fail_classifications:
  - {id: "FAIL-0101", type: "plan-amendment", rationale: "Original plan should reflect actual approach", source_plan: "01-01-PLAN.md"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Notes updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "metadata-only round with plan-amendment and original plan edit → PROCEED_TO_UAT" {
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-0101 | must_have | Plan must be amended | FAIL | Missing rationale |"
  create_plan "01-01"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    "  - \"$PHASE_DIR/01-01-PLAN.md\"
  - \"$PHASE_DIR/01-01-SUMMARY.md\""

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Valid plan amendment
fail_classifications:
  - {id: "FAIL-0101", type: "plan-amendment", rationale: "Original plan updated with actual approach", source_plan: "01-01-PLAN.md"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Plan updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "metadata-only round with no-ID source verification can pass via count-based process-exception coverage" {
  create_verif "write-verification.sh" "FAIL" "## Checks
| Category | Description | Status | Evidence |
|----------|-------------|--------|----------|
| must_have | Historical process issue | FAIL | Missing justification |"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".vbw-planning/phases/01-test-phase/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Brownfield no-ID verification
fail_classifications:
  - {id: "FAIL-ROW-01", type: "process-exception", rationale: "Historical process issue cannot be retroactively fixed"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Exception documented | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "metadata-only round with mixed ID and no-ID source FAIL rows requires full classification coverage" {
  create_verif "write-verification.sh" "FAIL" "## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-01 | must_have | First issue | FAIL | Missing |
|  | must_have | Legacy no-ID issue | FAIL | Missing |"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".vbw-planning/phases/01-test-phase/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Mixed ID coverage must fail closed
fail_classifications:
  - {id: "FAIL-01", type: "process-exception", rationale: "Only one FAIL classified"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Partial remediation documented | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "missing remediation round summary → REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "PASS"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Missing summary should fail closed
fail_classifications:
  - {id: "FAIL-01", type: "process-exception", rationale: "Summary artifact missing"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Verification exists | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_round_summary_missing=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "missing remediation round plan → REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "PASS"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "src/Fix.swift"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified: []
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Verification exists | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "missing files_modified + unresolved commit hashes → REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "PASS"
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md" <<'SUMMARY'
---
plan: R01
status: complete
commit_hashes:
  - deadbeef
deviations: []
---

## Task 1: Unknown change evidence
SUMMARY

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Missing files_modified must fail closed
fail_classifications:
  - {id: "FAIL-01", type: "process-exception", rationale: "Need change evidence to trust this round"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Verification exists | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_round_change_evidence_unavailable=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "mixed valid and invalid commit hashes fail closed" {
  create_verif "write-verification.sh" "PASS"
  init_git_repo
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  valid_commit=$(commit_repo_file "src/Fix.swift" "real code change")

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md" <<EOF
---
plan: R01
status: complete
commit_hashes:
  - "$valid_commit"
  - deadbeef
deviations: []
---

## Task 1: Mixed provenance should fail closed
EOF

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Mixed provenance must fail closed
fail_classifications:
  - {id: "FAIL-01", type: "code-fix", rationale: "Need complete change evidence"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Verification exists | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_round_change_evidence_unavailable=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "empty change evidence plus process-exception still fails closed" {
  create_verif "write-verification.sh" "PASS"
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md" <<'SUMMARY'
---
plan: R01
status: complete
commit_hashes: []
files_modified: []
deviations: []
---

## Task 1: No-op round
SUMMARY

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Empty evidence should fail closed
fail_classifications:
  - {id: "FAIL-01", type: "process-exception", rationale: "Need actual documented change evidence"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Verification exists | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_round_change_evidence_empty=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "task-level remediation deviations still trigger QA rerun" {
  create_verif "write-verification.sh" "PASS"
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md" <<'SUMMARY'
---
plan: R01
status: complete
commit_hashes:
  - abc123
files_modified:
  - src/Fix.swift
deviations: []
---

## Task 1: Implement fix

### Deviations
- Used a different helper function than planned
SUMMARY

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Task-level deviations should count
fail_classifications:
  - {id: "FAIL-01", type: "process-exception", rationale: "Round-local deviation still needs QA rerun"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Verification exists | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "plain-text task-level remediation deviations still trigger QA rerun" {
  create_verif "write-verification.sh" "PASS"
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md" <<'SUMMARY'
---
plan: R01
status: complete
commit_hashes:
  - abc123
files_modified:
  - src/Fix.swift
deviations: []
---

## Task 1: Implement fix

### Deviations
Used a different helper function than planned
SUMMARY

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Plain-text task deviation should count
fail_classifications:
  - {id: "FAIL-01", type: "process-exception", rationale: "Round-local deviation still needs QA rerun"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Verification exists | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "metadata-only detection tolerates dot-slash and backticks in files_modified" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Changed API"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md" <<'SUMMARY'
---
plan: R01
status: complete
commit_hashes: []
files_modified:
  - `./.vbw-planning/phases/01-test-phase/01-01-SUMMARY.md`
deviations: []
---

## Task 1: Metadata-only change
SUMMARY

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Metadata formatting variants
fail_classifications:
  - {id: "FAIL-01", type: "process-exception", rationale: "Metadata-only round should still be recognized"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Verification exists | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" != *"qa_gate_round_change_evidence_unavailable=true"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "plan-amendment accepts short original plan filename" {
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-0101 | must_have | Plan must be amended | FAIL | Missing rationale |"
  create_plan "01-01"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "01-01-PLAN.md"
  - ".vbw-planning/phases/01-test-phase/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Short filename plan amendment
fail_classifications:
  - {id: "FAIL-0101", type: "plan-amendment", rationale: "Original plan updated with actual approach", source_plan: "01-01-PLAN.md"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Plan updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "plan-amendment does not accept unrelated bare plan filename" {
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-0101 | must_have | Plan must be amended | FAIL | Missing rationale |"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "99-99-PLAN.md"
  - ".vbw-planning/phases/01-test-phase/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Unrelated bare plan filename is not enough
fail_classifications:
  - {id: "FAIL-0101", type: "plan-amendment", rationale: "Original plan should be updated", source_plan: "01-01-PLAN.md"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Notes updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "plan-amendment does not accept archived milestone plan path" {
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-0101 | must_have | Plan must be amended | FAIL | Missing rationale |"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".vbw-planning/milestones/v1/phases/01-test-phase/01-01-PLAN.md"
  - ".vbw-planning/phases/01-test-phase/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Archived milestone plan path is not enough
fail_classifications:
  - {id: "FAIL-0101", type: "plan-amendment", rationale: "Original plan should be updated", source_plan: "01-01-PLAN.md"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Notes updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "nonterminal remediation summary → REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "PASS"
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md" <<'SUMMARY'
---
plan: R01
status: in-progress
commit_hashes: []
files_modified:
  - src/Fix.swift
deviations: []
---

## Task 1: In-progress remediation
SUMMARY

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: In-progress summary should fail closed
fail_classifications:
  - {id: "FAIL-01", type: "code-fix", rationale: "Production code still needs to change"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Verification exists | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_round_summary_nonterminal=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "round-01 missing phase verification → REMEDIATION_REQUIRED" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".vbw-planning/phases/01-test-phase/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Missing source verification should fail closed
fail_classifications:
  - {id: "FAIL-01", type: "process-exception", rationale: "Cannot validate without original verification"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Verification exists | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_source_verification_missing=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "plan-amendment does not accept bare remediation plan filename" {
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-0101 | must_have | Plan must be amended | FAIL | Missing rationale |"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "R01-PLAN.md"
  - ".vbw-planning/phases/01-test-phase/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Bare remediation plan filename is not enough
fail_classifications:
  - {id: "FAIL-0101", type: "plan-amendment", rationale: "Original plan should be updated", source_plan: "01-01-PLAN.md"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Notes updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "round-02 missing previous verification → REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "PASS"
  mkdir -p "$PHASE_DIR/remediation/qa/round-02"
  printf 'stage=verify\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-02" "02" \
    '  - ".vbw-planning/phases/01-test-phase/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-02/R02-PLAN.md" <<'PLAN'
---
round: 02
title: Missing previous verification should fail closed
fail_classifications:
  - {id: "FAIL-01", type: "process-exception", rationale: "Cannot validate without previous round verification"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-02/R02-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R02
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Verification exists | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_source_verification_missing=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "round-02 missing previous verification still fails closed with non-metadata edits" {
  create_verif "write-verification.sh" "PASS"
  mkdir -p "$PHASE_DIR/remediation/qa/round-02"
  printf 'stage=verify\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-02" "02" \
    '  - "src/Fix.swift"'

  cat > "$PHASE_DIR/remediation/qa/round-02/R02-PLAN.md" <<'PLAN'
---
round: 02
title: Missing previous verification must fail closed
fail_classifications:
  - {id: "FAIL-01", type: "process-exception", rationale: "Cannot validate without previous round verification"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-02/R02-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R02
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Verification exists | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_source_verification_missing=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "round-02 docs-only pass still fails closed when previous round passed but original FAILs remain" {
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-01 | must_have | Original failure still needs remediation | FAIL | Missing |
| MH-02 | must_have | Other check | PASS | Done |"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01" "$PHASE_DIR/remediation/qa/round-02"
  printf 'stage=verify\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Structural bookkeeping passed | PASS | Done |
VERIF

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-02" "02" \
    '  - "README.md"
  - "docs/remediation-notes.md"'

  cat > "$PHASE_DIR/remediation/qa/round-02/R02-PLAN.md" <<'PLAN'
---
round: 02
title: Round two still needs the original fail classifications
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-02/R02-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R02
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Docs updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "round-02 source verification missing still fails closed when previous round passed structurally" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01" "$PHASE_DIR/remediation/qa/round-02"
  printf 'stage=verify\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Structural bookkeeping passed | PASS | Done |
VERIF

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-02" "02" \
    '  - "README.md"
  - "docs/remediation-notes.md"'

  cat > "$PHASE_DIR/remediation/qa/round-02/R02-PLAN.md" <<'PLAN'
---
round: 02
title: Missing carried-forward source verification must fail closed
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-02/R02-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R02
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Docs updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_source_verification_missing=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "bare summary artifact path still counts as metadata-only" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Changed API"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Bare summary path is still metadata
fail_classifications:
  - {id: "FAIL-01", type: "code-fix", rationale: "Production code still needs to change"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Summary updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "bare UAT CONTEXT and RESEARCH artifact paths still count as metadata-only" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Changed API"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "01-UAT.md"
  - "01-CONTEXT.md"
  - "01-01-RESEARCH.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Bare non-code artifacts are still metadata-only
fail_classifications:
  - {id: "FAIL-01", type: "code-fix", rationale: "Production code still needs to change"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Artifact docs updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_phase_deviation_count=1"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "bare root planning basenames still count as metadata-only" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Changed API"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "STATE.md"
  - "ROADMAP.md"
  - "PROJECT.md"
  - "REQUIREMENTS.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Bare planning docs are still metadata-only
fail_classifications:
  - {id: "FAIL-01", type: "code-fix", rationale: "Production code still needs to change"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Planning docs updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_phase_deviation_count=1"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "done-stage missing round verification → QA_RERUN_REQUIRED" {
  create_verif "write-verification.sh" "PASS"
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=done\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_result=missing"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "tests-only code-fix round fails closed without production code edits" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Changed approach"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "tests/qa-result-gate.bats"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Tests-only code-fix should fail closed
fail_classifications:
  - {id: "FAIL-01", type: "code-fix", rationale: "Real production code still needs to change"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Tests updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "repo-hygiene dotfile does not satisfy code-fix evidence" {
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-01 | must_have | Production code still differs from the plan | FAIL | Missing fix |"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".gitignore"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Dotfile-only round cannot satisfy a code fix
fail_classifications:
  - {id: "FAIL-01", type: "code-fix", rationale: "Production code still needs to change"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Repo hygiene updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "absolute support-only paths do not satisfy code-fix evidence" {
  init_git_repo
  mkdir -p "$TEST_DIR/docs" "$TEST_DIR/tests"
  : > "$TEST_DIR/README.md"
  : > "$TEST_DIR/docs/remediation-notes.md"
  : > "$TEST_DIR/tests/qa-result-gate.bats"

  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-01 | must_have | Production code still differs from the plan | FAIL | Missing fix |"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    "  - \"$TEST_DIR/README.md\"
  - \"$TEST_DIR/docs/remediation-notes.md\"
  - \"$TEST_DIR/tests/qa-result-gate.bats\""

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Absolute support paths cannot satisfy a code fix
fail_classifications:
  - {id: "FAIL-01", type: "code-fix", rationale: "Production code still needs to change"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Support files updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "absolute support-only paths do not satisfy code-fix evidence outside git repos" {
  mkdir -p "$TEST_DIR/docs" "$TEST_DIR/tests"
  : > "$TEST_DIR/README.md"
  : > "$TEST_DIR/docs/remediation-notes.md"
  : > "$TEST_DIR/tests/qa-result-gate.bats"

  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-01 | must_have | Production code still differs from the plan | FAIL | Missing fix |"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    "  - \"$TEST_DIR/README.md\"
  - \"$TEST_DIR/docs/remediation-notes.md\"
  - \"$TEST_DIR/tests/qa-result-gate.bats\""

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Absolute support paths cannot satisfy a code fix outside git repos
fail_classifications:
  - {id: "FAIL-01", type: "code-fix", rationale: "Production code still needs to change"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Support files updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "claimed code path must be corroborated by the round diff when git evidence is available" {
  init_git_repo
  baseline_commit=$(commit_repo_file "src/Baseline.swift" "baseline")
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-01 | must_have | Production code still differs from the plan | FAIL | Missing fix |" "$baseline_commit"
  commit_repo_file "README.md" "docs-only follow-up" >/dev/null

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\nround_started_at_commit=%s\n' "$baseline_commit" > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "src/MyService.swift"
  - "README.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Claimed code fix must be corroborated by the round diff
fail_classifications:
  - {id: "FAIL-01", type: "code-fix", rationale: "Production code still needs to change"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Documentation updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "unrecorded post-anchor code diff does not satisfy code-fix evidence" {
  init_git_repo
  baseline_commit=$(commit_repo_file "src/Baseline.swift" "baseline")
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-01 | must_have | Production code still differs from the plan | FAIL | Missing fix |" "$baseline_commit"
  commit_repo_file "src/Unrelated.swift" "unrecorded follow-up change" >/dev/null

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\nround_started_at_commit=%s\n' "$baseline_commit" > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".vbw-planning/phases/01-test-phase/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Unrecorded post-anchor code must not satisfy remediation
fail_classifications:
  - {id: "FAIL-01", type: "code-fix", rationale: "Production code still needs to change"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Summary updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_round_change_evidence_unavailable=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "unrecorded post-anchor original plan diff does not satisfy plan-amendment evidence" {
  init_git_repo
  baseline_commit=$(commit_repo_file "01-test-phase/01-01-PLAN.md" "original plan")
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-0101 | must_have | Plan must be amended | FAIL | Missing rationale |" "$baseline_commit"
  commit_repo_file "01-test-phase/01-01-PLAN.md" "updated plan outside recorded summary evidence" >/dev/null

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\nround_started_at_commit=%s\n' "$baseline_commit" > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".vbw-planning/phases/01-test-phase/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Unrecorded post-anchor plan edits must not satisfy plan amendments
fail_classifications:
  - {id: "FAIL-0101", type: "plan-amendment", rationale: "Original plan should be updated", source_plan: "01-01-PLAN.md"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Summary updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_round_change_evidence_unavailable=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "flow-style plans_verified still enforces plan coverage" {
  create_verif "write-verification.sh" "PASS"
  create_plan "01-01"
  create_plan "01-02"
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'VERIF'
---
phase: 01
tier: full
result: PASS
passed: 10
failed: 0
total: 10
date: 2026-03-27
writer: write-verification.sh
plans_verified: ["01-01"]
---

## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | First plan verified | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_plan_coverage=1/2"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "docs-only round with process-exception is treated as delivered content rather than metadata-only" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "None"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "README.md"
  - "docs/remediation-notes.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Docs-only round cannot satisfy code fix
fail_classifications:
  - {id: "FAIL-0101", type: "process-exception", rationale: "Delivered content fix is documented outside planning metadata"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Docs updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "docs-only round without fail_classifications still fails closed when source FAILs exist" {
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-0101 | must_have | Remediation must classify the original failure | FAIL | Missing classification |"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "README.md"
  - "docs/remediation-notes.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Missing classifications should fail closed even for docs-only rounds
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Docs updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "metadata-only round with partial fail classification coverage → REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-01 | must_have | First issue | FAIL | Missing |
| FAIL-02 | must_have | Second issue | FAIL | Missing |"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".vbw-planning/phases/01-test/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Partial coverage should fail closed
fail_classifications:
  - {id: "FAIL-01", type: "process-exception", rationale: "Only one FAIL was classified"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Partial remediation documented | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "metadata-only round with invalid classification type → REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-01 | must_have | First issue | FAIL | Missing |"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".vbw-planning/phases/01-test/01-01-SUMMARY.md"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Invalid type should fail closed
fail_classifications:
  - {id: "FAIL-01", type: "documentation-only", rationale: "Invalid enum value"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Invalid type documented | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "round with real code changes + phase deviations → PROCEED_TO_UAT (existing behavior)" {
  create_verif "write-verification.sh" "PASS"
  # Phase-level SUMMARY.md has deviations
  create_summary_with_yaml_deviations "01-01" "Changed API approach"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  # Round SUMMARY.md modifies real code files (not metadata-only)
  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "src/MyService.swift"
  - ".vbw-planning/phases/01-test/01-01-SUMMARY.md"' \
    '  - "abc1234"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Fix code
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Code fixed | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "mixed files_modified with some .vbw-planning/ and some code → not metadata-only" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Changed approach"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".vbw-planning/phases/01-test/01-01-SUMMARY.md"
  - "Sources/Calculator.swift"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Fix
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Fixed | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "empty change evidence round with empty files_modified and no commits → REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Batch commit deviation"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  # Empty files_modified and empty commit_hashes
  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" "" ""

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Document deviations
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Documented | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_round_change_evidence_empty=true"* ]]
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" != *"qa_gate_phase_deviation_count="* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "inline YAML array with mixed paths correctly detects code changes" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Changed approach"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  # Use inline YAML array format instead of list format
  {
    echo "---"
    echo "plan: R01"
    echo "status: complete"
    echo "commit_hashes: [\"abc1234\"]"
    echo 'files_modified: [".vbw-planning/phases/01-test/01-01-SUMMARY.md", "src/MyService.swift"]'
    echo "deviations: []"
    echo "---"
    echo ""
    echo "## Summary"
    echo "Work done."
  } > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md"

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Fix code
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Code fixed | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # Contains real code file → not metadata-only
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "inline YAML array with only metadata paths is metadata-only" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Changed API"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  # Inline YAML array with only .vbw-planning/ paths
  {
    echo "---"
    echo "plan: R01"
    echo "status: complete"
    echo "commit_hashes: []"
    echo 'files_modified: [".vbw-planning/phases/01-test/01-01-SUMMARY.md", ".vbw-planning/STATE.md"]'
    echo "deviations: []"
    echo "---"
    echo ""
    echo "## Summary"
    echo "Work done."
  } > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md"

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Document
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Documented | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "single-quoted inline files_modified array is metadata-only" {
  create_verif "write-verification.sh" "PASS"
  create_summary_with_yaml_deviations "01-01" "Changed API"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  {
    echo "---"
    echo "plan: R01"
    echo "status: complete"
    echo "commit_hashes: []"
    echo "files_modified: ['.vbw-planning/phases/01-test/01-01-SUMMARY.md', '.vbw-planning/STATE.md']"
    echo "deviations: []"
    echo "---"
    echo
    echo "## Summary"
    echo "Work done."
  } > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md"

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Document
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Documented | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "empty files_modified but commits present → not metadata-only" {
  init_git_repo
  baseline_commit=$(commit_repo_file "src/Baseline.swift" "verified code state")
  create_verif "write-verification.sh" "PASS" "" "$baseline_commit"
  create_summary_with_yaml_deviations "01-01" "Changed approach"

  code_commit=$(commit_repo_file "src/MyService.swift" "real code change")

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\nround_started_at_commit=%s\n' "$baseline_commit" > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  # files_modified is empty but commit_hashes has entries → real work happened
  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    "" \
    "  - \"$code_commit\""

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Fix code
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Fixed | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # Has commits → not metadata-only despite empty files_modified
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "missing files_modified + valid commit hashes but no round_started_at_commit → REMEDIATION_REQUIRED" {
  init_git_repo
  baseline_commit=$(commit_repo_file "src/Baseline.swift" "verified code state")
  create_verif "write-verification.sh" "PASS" "" "$baseline_commit"

  code_commit=$(commit_repo_file "src/MyService.swift" "real code change")

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    "" \
    "  - \"$code_commit\""

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Commit-only evidence requires a verified_at_commit baseline
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Fixed | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_round_change_evidence_unavailable=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "files_modified in git repo without round_started_at_commit → REMEDIATION_REQUIRED" {
  init_git_repo
  baseline_commit=$(commit_repo_file "src/Baseline.swift" "verified code state")
  create_verif "write-verification.sh" "FAIL" "## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-01 | must_have | Production code still differs from the plan | FAIL | Missing fix |" "$baseline_commit"
  commit_repo_file "src/MyService.swift" "real code change" >/dev/null

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - "src/MyService.swift"'

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: files_modified requires a round anchor in git repos
fail_classifications:
  - {id: "FAIL-01", type: "code-fix", rationale: "Production code still needs to change"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Summary updated | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_round_change_evidence_unavailable=true"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "missing files_modified falls back to commit paths for metadata-only detection" {
  init_git_repo
  baseline_commit=$(commit_repo_file "src/Baseline.swift" "verified code state")
  create_verif "write-verification.sh" "PASS" "" "$baseline_commit"
  create_summary_with_yaml_deviations "01-01" "Changed approach"

  meta_commit=$(commit_repo_file ".vbw-planning/STATE.md" "metadata only change")

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\nround_started_at_commit=%s\n' "$baseline_commit" > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md" <<EOF
---
plan: R01
status: complete
commit_hashes:
  - "$meta_commit"
deviations: []
---

## Summary
Work done.
EOF

  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Document
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Documented | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_phase_deviation_count=1"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "metadata-only round with zero deviations but incomplete plan coverage → QA_RERUN_REQUIRED" {
  create_verif "write-verification.sh" "PASS"
  # Phase-level SUMMARY.md has NO deviations
  create_summary_with_yaml_deviations "01-01" "None"

  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  # Metadata-only files_modified
  create_round_summary_with_files "$PHASE_DIR/remediation/qa/round-01" "01" \
    '  - ".vbw-planning/phases/01-test/01-01-SUMMARY.md"'

  # Two plans in the round dir but verification only covers one
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'PLAN'
---
round: 01
title: Fix part A
fail_classifications:
  - {id: "DEV-0101-COMMIT", type: "process-exception", rationale: "Historical git topology cannot be safely rewritten"}
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-02-PLAN.md" <<'PLAN'
---
round: 01
title: Fix part B
---
PLAN
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'VERIF'
---
writer: write-verification.sh
result: PASS
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Fix done | PASS | Done |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # No deviations so metadata_only_override doesn't fire,
  # but incomplete plan coverage triggers QA_RERUN_REQUIRED
  [[ "$output" != *"qa_gate_metadata_only_override=true"* ]]
  [[ "$output" == *"qa_gate_plan_coverage="* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

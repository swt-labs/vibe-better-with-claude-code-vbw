#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/qa-result-gate.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  PHASE_DIR="$TEST_DIR/phase"
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
  } > "$PHASE_DIR/VERIFICATION.md"
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
  } > "$PHASE_DIR/VERIFICATION.md"

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
  mv "$PHASE_DIR/VERIFICATION.md" "$PHASE_DIR/CUSTOM-VERIF.md"

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
  touch "$PHASE_DIR/VERIFICATION.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_writer=missing"* ]]
}

@test "no frontmatter delimiters → QA_RERUN_REQUIRED" {
  printf 'Just some text without frontmatter\n' > "$PHASE_DIR/VERIFICATION.md"

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
  cat > "$PHASE_DIR/VERIFICATION.md" <<'VERIF'
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

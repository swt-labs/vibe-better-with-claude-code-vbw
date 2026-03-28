#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

@test "extract-verified-items exits 0 with no output for missing phase dir" {
  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "/nonexistent/path"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "extract-verified-items exits 0 with no output when no VERIFICATION.md exists" {
  local phase_dir="$TEST_TEMP_DIR/phases/01-core"
  mkdir -p "$phase_dir"

  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$phase_dir"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "extract-verified-items reads phase-level VERIFICATION.md" {
  local phase_dir="$TEST_TEMP_DIR/phases/01-core"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/01-VERIFICATION.md" <<'EOF'
---
result: PASS
passed: 10
failed: 0
total: 10
---

## Must-Have Checks

| # | ID | Description | Status | Evidence |
|---|---|---|---|---|
| 1 | MH-01 | Build passes | **PASS** | No errors |
| 2 | MH-02 | Tests pass | **PASS** | All green |
EOF

  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$phase_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"QA-VERIFIED ITEMS"* ]]
  [[ "$output" == *"MH-01"* ]]
  [[ "$output" == *"MH-02"* ]]
}

@test "extract-verified-items includes round VERIFICATION.md when stage=done" {
  local phase_dir="$TEST_TEMP_DIR/phases/03-ui"
  mkdir -p "$phase_dir/remediation/qa/round-02"
  # Phase-level frozen as FAIL
  cat > "$phase_dir/03-VERIFICATION.md" <<'EOF'
---
result: FAIL
passed: 8
failed: 2
total: 10
---

## Must-Have Checks

| # | ID | Description | Status | Evidence |
|---|---|---|---|---|
| 1 | MH-01 | Build passes | **FAIL** | Error |
| 2 | MH-02 | Tests pass | **FAIL** | Red |
EOF
  # Round file has PASS
  cat > "$phase_dir/remediation/qa/round-02/R02-VERIFICATION.md" <<'EOF'
---
result: PASS
passed: 10
failed: 0
total: 10
---

## Must-Have Checks

| # | ID | Description | Status | Evidence |
|---|---|---|---|---|
| 1 | MH-01 | Build passes | **PASS** | Fixed |
| 2 | MH-02 | Tests pass | **PASS** | Fixed |
EOF
  printf 'stage=done\nround=2\n' > "$phase_dir/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$phase_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"QA-VERIFIED ITEMS"* ]]
  # Both phase-level FAIL items and round PASS items should appear
  [[ "$output" == *"PASS"* ]]
}

@test "extract-verified-items falls back to phase-level when round file missing (brownfield)" {
  local phase_dir="$TEST_TEMP_DIR/phases/03-ui"
  mkdir -p "$phase_dir/remediation/qa"
  cat > "$phase_dir/03-VERIFICATION.md" <<'EOF'
---
result: PASS
passed: 10
failed: 0
total: 10
---

## Must-Have Checks

| # | ID | Description | Status | Evidence |
|---|---|---|---|---|
| 1 | MH-01 | Build passes | **PASS** | OK |
EOF
  printf 'stage=done\nround=1\n' > "$phase_dir/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$phase_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"QA-VERIFIED ITEMS"* ]]
  [[ "$output" == *"MH-01"* ]]
}

@test "extract-verified-items handles non-numeric round gracefully" {
  local phase_dir="$TEST_TEMP_DIR/phases/03-ui"
  mkdir -p "$phase_dir/remediation/qa/round-01"
  cat > "$phase_dir/03-VERIFICATION.md" <<'EOF'
---
result: PASS
---
EOF
  cat > "$phase_dir/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
result: PASS
---
EOF
  printf 'stage=done\nround=abc\n' > "$phase_dir/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$phase_dir"

  [ "$status" -eq 0 ]
  # Non-numeric round defaults to 01, should still find round-01 file
}

@test "extract-verified-items does not read round file when stage is not done" {
  local phase_dir="$TEST_TEMP_DIR/phases/03-ui"
  mkdir -p "$phase_dir/remediation/qa/round-01"
  cat > "$phase_dir/03-VERIFICATION.md" <<'EOF'
---
result: FAIL
---

## Must-Have Checks

| # | ID | Description | Status | Evidence |
|---|---|---|---|---|
| 1 | MH-01 | Build passes | **FAIL** | Error |
EOF
  cat > "$phase_dir/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
result: PASS
---

## Must-Have Checks

| # | ID | Description | Status | Evidence |
|---|---|---|---|---|
| 1 | MH-01 | Build passes | **PASS** | Fixed |
EOF
  printf 'stage=verify\nround=1\n' > "$phase_dir/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$phase_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"QA-VERIFIED ITEMS"* ]]
  # Only phase-level FAIL, round file should NOT be included (stage != done)
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" != *"Fixed"* ]]
}

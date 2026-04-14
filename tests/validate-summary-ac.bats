#!/usr/bin/env bats
# Tests for ac_results validation in validate-summary.sh
# Covers conditional advisory check: ac_results presence when plan has must_haves,
# verdict value validation, and no false positives when plan lacks must_haves.

load test_helper

setup() {
  setup_temp_dir
  cd "$TEST_TEMP_DIR" || exit 1
  mkdir -p .vbw-planning/phases/01-test
}

teardown() {
  teardown_temp_dir
}

@test "validate-summary-ac: no advisory when ac_results present and plan has must_haves" {
  cat > .vbw-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
must_haves:
  truths:
    - "Widget renders correctly"
  artifacts: []
  key_links: []
---
PLAN

  cat > .vbw-planning/phases/01-test/01-01-SUMMARY.md <<'SUMMARY'
---
phase: 1
plan: 1
status: complete
ac_results:
  - criterion: "Widget renders correctly"
    verdict: pass
    evidence: "src/widget.ts line 42"
---
## What Was Built
A widget

## Files Modified
- src/widget.ts
SUMMARY

  local input
  input=$(jq -n --arg fp "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-SUMMARY.md" '{"tool_input":{"file_path":$fp}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Missing"* ]]
  [[ "$output" != *"Invalid"* ]]
}

@test "validate-summary-ac: advisory when ac_results missing and plan has must_haves" {
  cat > .vbw-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
must_haves:
  truths:
    - "Widget renders correctly"
  artifacts: []
  key_links: []
---
PLAN

  cat > .vbw-planning/phases/01-test/01-01-SUMMARY.md <<'SUMMARY'
---
phase: 1
plan: 1
status: complete
---
## What Was Built
A widget

## Files Modified
- src/widget.ts
SUMMARY

  local input
  input=$(jq -n --arg fp "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-SUMMARY.md" '{"tool_input":{"file_path":$fp}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Missing 'ac_results'"* ]]
}

@test "validate-summary-ac: no advisory when plan has empty must_haves" {
  cat > .vbw-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
must_haves:
  truths: []
  artifacts: []
  key_links: []
---
PLAN

  cat > .vbw-planning/phases/01-test/01-01-SUMMARY.md <<'SUMMARY'
---
phase: 1
plan: 1
status: complete
---
## What Was Built
A widget

## Files Modified
- src/widget.ts
SUMMARY

  local input
  input=$(jq -n --arg fp "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-SUMMARY.md" '{"tool_input":{"file_path":$fp}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ac_results"* ]]
}

@test "validate-summary-ac: no advisory when plan has no must_haves key" {
  cat > .vbw-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
title: "Build widget"
tasks:
  - name: "Create widget"
---
PLAN

  cat > .vbw-planning/phases/01-test/01-01-SUMMARY.md <<'SUMMARY'
---
phase: 1
plan: 1
status: complete
---
## What Was Built
A widget

## Files Modified
- src/widget.ts
SUMMARY

  local input
  input=$(jq -n --arg fp "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-SUMMARY.md" '{"tool_input":{"file_path":$fp}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ac_results"* ]]
}

@test "validate-summary-ac: no advisory when no PLAN.md exists" {
  cat > .vbw-planning/phases/01-test/01-01-SUMMARY.md <<'SUMMARY'
---
phase: 1
plan: 1
status: complete
---
## What Was Built
A widget

## Files Modified
- src/widget.ts
SUMMARY

  # No PLAN.md created — should not flag ac_results

  local input
  input=$(jq -n --arg fp "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-SUMMARY.md" '{"tool_input":{"file_path":$fp}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ac_results"* ]]
}

@test "validate-summary-ac: advisory on invalid verdict value" {
  cat > .vbw-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
must_haves:
  truths:
    - "Widget renders correctly"
  artifacts: []
  key_links: []
---
PLAN

  cat > .vbw-planning/phases/01-test/01-01-SUMMARY.md <<'SUMMARY'
---
phase: 1
plan: 1
status: complete
ac_results:
  - criterion: "Widget renders correctly"
    verdict: PASS
    evidence: "src/widget.ts line 42"
---
## What Was Built
A widget

## Files Modified
- src/widget.ts
SUMMARY

  local input
  input=$(jq -n --arg fp "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-SUMMARY.md" '{"tool_input":{"file_path":$fp}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Invalid ac_results verdict"* ]]
}

@test "validate-summary-ac: no advisory with valid pass/fail/partial verdicts" {
  cat > .vbw-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
must_haves:
  truths:
    - "Widget renders correctly"
    - "Tests pass"
  artifacts:
    - path: src/widget.ts
      provides: "Widget component"
  key_links: []
---
PLAN

  cat > .vbw-planning/phases/01-test/01-01-SUMMARY.md <<'SUMMARY'
---
phase: 1
plan: 1
status: complete
ac_results:
  - criterion: "Widget renders correctly"
    verdict: pass
    evidence: "src/widget.ts line 42"
  - criterion: "Tests pass"
    verdict: fail
    evidence: "test suite has 2 failures"
  - criterion: "Widget component at src/widget.ts"
    verdict: partial
    evidence: "file exists but missing export"
---
## What Was Built
A widget

## Files Modified
- src/widget.ts
SUMMARY

  local input
  input=$(jq -n --arg fp "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-SUMMARY.md" '{"tool_input":{"file_path":$fp}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Invalid"* ]]
}

@test "validate-summary-ac: advisory when ac_results missing and plan has flow-style must_haves" {
  cat > .vbw-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
must_haves:
  truths: ["Widget renders correctly"]
  artifacts: [{path: "src/widget.ts", provides: "Widget component", contains: "export"}]
  key_links: []
---
PLAN

  cat > .vbw-planning/phases/01-test/01-01-SUMMARY.md <<'SUMMARY'
---
phase: 1
plan: 1
status: complete
---
## What Was Built
A widget

## Files Modified
- src/widget.ts
SUMMARY

  local input
  input=$(jq -n --arg fp "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-SUMMARY.md" '{"tool_input":{"file_path":$fp}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Missing 'ac_results'"* ]]
}

@test "validate-summary-ac: no advisory when plan has flow-style empty must_haves" {
  cat > .vbw-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
must_haves:
  truths: []
  artifacts: []
  key_links: []
---
PLAN

  cat > .vbw-planning/phases/01-test/01-01-SUMMARY.md <<'SUMMARY'
---
phase: 1
plan: 1
status: complete
---
## What Was Built
A widget

## Files Modified
- src/widget.ts
SUMMARY

  local input
  input=$(jq -n --arg fp "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-SUMMARY.md" '{"tool_input":{"file_path":$fp}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ac_results"* ]]
}

@test "validate-summary-ac: no advisory when empty must_haves followed by flow-style top-level key" {
  cat > .vbw-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
must_haves:
  truths: []
  artifacts: []
  key_links: []
outputs: ["report.md"]
---
PLAN

  cat > .vbw-planning/phases/01-test/01-01-SUMMARY.md <<'SUMMARY'
---
phase: 1
plan: 1
status: complete
---
## What Was Built
A widget

## Files Modified
- src/widget.ts
SUMMARY

  local input
  input=$(jq -n --arg fp "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-SUMMARY.md" '{"tool_input":{"file_path":$fp}}')
  run bash -c "echo '$input' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ac_results"* ]]
}

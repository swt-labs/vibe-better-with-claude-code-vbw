#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  ROUND_DIR="$PHASE_DIR/remediation/uat/round-01"
  mkdir -p "$ROUND_DIR"
}

teardown() {
  teardown_temp_dir
}

write_valid_summary() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
---
phase: 1
round: 1
title: Remediation summary
type: remediation
status: complete
completed: 2026-05-03
tasks_completed: 1
tasks_total: 1
commit_hashes:
  - abc123
files_modified:
  - src/example.swift
deviations: []
known_issue_outcomes:
  - '{"test":"UAT-1","file":"01-UAT.md","error":"example","disposition":"resolved","rationale":"fixed"}'
---

Completed remediation.
EOF
}

@test "validator accepts a complete summary at the expected absolute host path" {
  local summary_path="$ROUND_DIR/R01-SUMMARY.md"
  write_valid_summary "$summary_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" summary "$summary_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifact_valid=true"* ]]
  [[ "$output" == *"artifact_type=summary"* ]]
  [[ "$output" == *"artifact_path=$summary_path"* ]]
}

@test "validator rejects relative artifact paths" {
  local summary_path="$ROUND_DIR/R01-SUMMARY.md"
  write_valid_summary "$summary_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" summary ".vbw-planning/phases/01-test/remediation/uat/round-01/R01-SUMMARY.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"artifact path must be absolute"* ]]
}

@test "validator rejects Claude sidechain artifact paths" {
  local sidechain_summary="$TEST_TEMP_DIR/repo/.claude/worktrees/agent-test/.vbw-planning/phases/01-test/remediation/uat/round-01/R01-SUMMARY.md"
  write_valid_summary "$sidechain_summary"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" summary "$sidechain_summary"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"Claude sidechain"* ]]
}

@test "validator rejects in-progress summaries before state advance" {
  local summary_path="$ROUND_DIR/R01-SUMMARY.md"
  write_valid_summary "$summary_path"
  sed -i.bak 's/^status: complete$/status: in-progress/' "$summary_path"
  rm -f "$summary_path.bak"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" summary "$summary_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"summary artifact status must be complete, partial, or failed"* ]]
}

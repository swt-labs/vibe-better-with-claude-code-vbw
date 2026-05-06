#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  ROUND_DIR="$PHASE_DIR/remediation/uat/round-01"
  QA_ROUND_DIR="$PHASE_DIR/remediation/qa/round-01"
  mkdir -p "$ROUND_DIR" "$QA_ROUND_DIR"
}

write_valid_research() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
---
phase: 1
round: 1
title: Remediation research
type: remediation-research
confidence: high
date: 2026-05-03
---

# Phase 1: Test — Remediation Research (Round 01)

## Findings

The issue is reproduced.

## Prior Fix Analysis

No prior fix exists.

## Root Cause Assessment

The root cause is path selection.

## Recommendations

Use the state-selected artifact.
EOF
}

write_valid_plan() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
---
phase: 1
round: 1
plan: R01
title: Remediation plan
type: remediation
autonomous: true
effort_override: balanced
skills_used: []
files_modified: []
forbidden_commands: []
fail_classifications:
  - {id: "UAT-1", type: "code-fix", rationale: "example"}
known_issues_input:
  - '{"test":"UAT-1","file":"01-UAT.md","error":"example"}'
known_issue_resolutions:
  - '{"test":"UAT-1","file":"01-UAT.md","error":"example","disposition":"resolved","rationale":"fixed"}'
must_haves:
  truths: ["state-selected artifact is valid"]
  artifacts: []
  key_links: []
---
<objective>
Fix the issue.
</objective>
<tasks>
<task type="auto">
  <name>Fix</name>
  <files>
    scripts/example.sh
  </files>
  <action>
Do the work.
  </action>
  <verify>
Run tests.
  </verify>
  <done>
Tests pass.
  </done>
</task>
</tasks>
<verification>
1. Run tests.
</verification>
<success_criteria>
- Tests pass.
</success_criteria>
EOF
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

@test "validator rejects relative research artifact paths" {
  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" research ".vbw-planning/phases/01-test/remediation/uat/round-01/R01-RESEARCH.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"artifact path must be absolute"* ]]
}

@test "validator rejects relative plan artifact paths" {
  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan ".vbw-planning/phases/01-test/remediation/uat/round-01/R01-PLAN.md"
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

@test "validator rejects Claude sidechain research artifact paths" {
  local sidechain_research="$TEST_TEMP_DIR/repo/.claude/worktrees/agent-test/.vbw-planning/phases/01-test/remediation/uat/round-01/R01-RESEARCH.md"
  write_valid_research "$sidechain_research"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" research "$sidechain_research"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"Claude sidechain"* ]]
}

@test "validator rejects Claude sidechain plan artifact paths" {
  local sidechain_plan="$TEST_TEMP_DIR/repo/.claude/worktrees/agent-test/.vbw-planning/phases/01-test/remediation/uat/round-01/R01-PLAN.md"
  write_valid_plan "$sidechain_plan"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$sidechain_plan"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"Claude sidechain"* ]]
}

@test "validator accepts canonical UAT round-dir plan path" {
  local plan_path="$ROUND_DIR/R01-PLAN.md"
  write_valid_plan "$plan_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifact_valid=true"* ]]
  [[ "$output" == *"artifact_path=$plan_path"* ]]
}

@test "validator accepts UAT plan without known issue arrays for backward compatibility" {
  local plan_path="$ROUND_DIR/R01-PLAN.md"
  write_valid_plan "$plan_path"
  sed -i.bak '/^known_issues_input:/,/^must_haves:/ { /^must_haves:/!d; }' "$plan_path"
  rm -f "$plan_path.bak"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifact_valid=true"* ]]
}

@test "validator accepts canonical QA round-dir plan path" {
  local plan_path="$QA_ROUND_DIR/R01-PLAN.md"
  write_valid_plan "$plan_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifact_valid=true"* ]]
  [[ "$output" == *"artifact_path=$plan_path"* ]]
}

@test "validator rejects QA plan whose frontmatter round mismatches round directory" {
  local plan_path="$QA_ROUND_DIR/R01-PLAN.md"
  write_valid_plan "$plan_path"
  sed -i.bak 's/^round: 1$/round: 2/' "$plan_path"
  rm -f "$plan_path.bak"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"frontmatter round must match round directory"* ]]
}

@test "validator rejects QA round-dir plan without known_issue_resolutions" {
  local plan_path="$QA_ROUND_DIR/R01-PLAN.md"
  mkdir -p "$(dirname "$plan_path")"
  cat > "$plan_path" <<'EOF'
---
phase: 1
round: 1
title: Fail-only remediation plan
type: remediation
fail_classifications:
  - {id: "FAIL-1", type: "code-fix", rationale: "test failure needs fix"}
known_issues_input: []
---
<objective>
Fix the test failure.
</objective>
<tasks>
<task type="auto">
  <name>Fix</name>
  <files>
    src/example.sh
  </files>
  <action>
Apply the fix.
  </action>
  <verify>
Run tests.
  </verify>
  <done>
Tests pass.
  </done>
</task>
</tasks>
<verification>
1. Run tests.
</verification>
<success_criteria>
- Tests pass.
</success_criteria>
EOF

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"known_issue_resolutions"* ]]
}

@test "validator rejects QA plan absolute paths containing traversal aliases" {
  local plan_path alias_path
  plan_path="$QA_ROUND_DIR/R01-PLAN.md"
  alias_path="$QA_ROUND_DIR/../round-01/R01-PLAN.md"
  write_valid_plan "$plan_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$alias_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"exact canonical host path"* ]]
}

@test "validator rejects UAT plan absolute paths containing traversal aliases" {
  local plan_path alias_path
  plan_path="$ROUND_DIR/R01-PLAN.md"
  alias_path="$ROUND_DIR/../round-01/R01-PLAN.md"
  write_valid_plan "$plan_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$alias_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"exact canonical host path"* ]]
}

@test "validator rejects host-looking QA plan symlink that resolves into Claude sidechain" {
  local host_plan sidechain_plan
  host_plan="$QA_ROUND_DIR/R01-PLAN.md"
  sidechain_plan="$TEST_TEMP_DIR/repo/.claude/worktrees/agent-test/.vbw-planning/phases/01-test/remediation/qa/round-01/R01-PLAN.md"
  write_valid_plan "$sidechain_plan"
  ln -s "$sidechain_plan" "$host_plan"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$host_plan"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"Claude sidechain"* ]]
}

@test "validator rejects host-looking UAT plan symlink that resolves into Claude sidechain" {
  local host_plan sidechain_plan
  host_plan="$ROUND_DIR/R01-PLAN.md"
  sidechain_plan="$TEST_TEMP_DIR/repo/.claude/worktrees/agent-test/.vbw-planning/phases/01-test/remediation/uat/round-01/R01-PLAN.md"
  write_valid_plan "$sidechain_plan"
  ln -s "$sidechain_plan" "$host_plan"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$host_plan"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"Claude sidechain"* ]]
}

@test "validator accepts QA plan_path emitted from relative QA remediation state input" {
  local host_root host_phase_dir plan_path
  host_root="$TEST_TEMP_DIR/host"
  create_test_vbw_workspace "$host_root"
  mkdir -p "$host_root/.vbw-planning/phases/01-relative"
  host_root=$(cd "$host_root" && pwd -P)
  host_phase_dir="$host_root/.vbw-planning/phases/01-relative"

  run bash -c 'cd "$1" && bash "$2/qa-remediation-state.sh" get-or-init ".vbw-planning/phases/01-relative"' _ "$host_root" "$SCRIPTS_DIR"
  [ "$status" -eq 0 ]
  plan_path=$(awk -F= '/^plan_path=/ { print $2; exit }' <<< "$output")
  [ "$plan_path" = "$host_phase_dir/remediation/qa/round-01/R01-PLAN.md" ]
  write_valid_plan "$plan_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifact_valid=true"* ]]
  [[ "$output" == *"artifact_path=$plan_path"* ]]
}

@test "validator accepts QA plan_path emitted from Claude sidechain QA remediation state input" {
  local host_root host_phase_dir sidechain_dir plan_path
  host_root="$TEST_TEMP_DIR/host"
  create_test_vbw_workspace "$host_root"
  mkdir -p "$host_root/.vbw-planning/phases/01-sidechain" "$host_root/.claude/worktrees/agent-test"
  host_root=$(cd "$host_root" && pwd -P)
  host_phase_dir="$host_root/.vbw-planning/phases/01-sidechain"
  sidechain_dir="$host_root/.claude/worktrees/agent-test"

  run bash -c 'cd "$1" && bash "$2/qa-remediation-state.sh" get-or-init ".vbw-planning/phases/01-sidechain"' _ "$sidechain_dir" "$SCRIPTS_DIR"
  [ "$status" -eq 0 ]
  plan_path=$(awk -F= '/^plan_path=/ { print $2; exit }' <<< "$output")
  [ "$plan_path" = "$host_phase_dir/remediation/qa/round-01/R01-PLAN.md" ]
  write_valid_plan "$plan_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifact_valid=true"* ]]
  [[ "$output" == *"artifact_path=$plan_path"* ]]
  [ ! -d "$sidechain_dir/.vbw-planning/phases/01-sidechain/remediation" ]
}

@test "validator rejects QA round-dir research artifacts" {
  local research_path="$QA_ROUND_DIR/R01-RESEARCH.md"
  write_valid_research "$research_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" research "$research_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"QA remediation validation currently supports plan artifacts only"* ]]
}

@test "validator rejects QA round-dir summary artifacts" {
  local summary_path="$QA_ROUND_DIR/R01-SUMMARY.md"
  write_valid_summary "$summary_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" summary "$summary_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"QA remediation validation currently supports plan artifacts only"* ]]
}

@test "validator rejects non-canonical QA plan filenames" {
  local plan_path="$QA_ROUND_DIR/R01-CUSTOM-PLAN.md"
  write_valid_plan "$plan_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"QA remediation plan filename shape"* ]]
}

@test "validator rejects QA plan round token that does not match round directory" {
  local plan_path="$QA_ROUND_DIR/R02-PLAN.md"
  write_valid_plan "$plan_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"round token must match round directory"* ]]
}

@test "validator rejects UAT plan round token that does not match round directory" {
  local plan_path="$ROUND_DIR/R02-PLAN.md"
  write_valid_plan "$plan_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"round token must match round directory"* ]]
}

@test "validator rejects QA plan paths under non-canonical round-1 directory" {
  local plan_path="$PHASE_DIR/remediation/qa/round-1/R01-PLAN.md"
  write_valid_plan "$plan_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"QA remediation plan filename shape"* ]]
}

@test "validator rejects UAT plan paths under non-canonical round-001 directory" {
  local plan_path="$PHASE_DIR/remediation/uat/round-001/R01-PLAN.md"
  write_valid_plan "$plan_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"expected round-dir PLAN filename shape"* ]]
}

@test "validator rejects missing canonical QA plan artifacts" {
  local plan_path="$QA_ROUND_DIR/R01-PLAN.md"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"artifact file does not exist"* ]]
}

@test "validator rejects empty canonical QA plan artifacts" {
  local plan_path="$QA_ROUND_DIR/R01-PLAN.md"
  mkdir -p "$(dirname "$plan_path")"
  : > "$plan_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"artifact file is empty"* ]]
}

@test "validator rejects malformed canonical QA plan artifacts" {
  local plan_path="$QA_ROUND_DIR/R01-PLAN.md"
  mkdir -p "$(dirname "$plan_path")"
  printf '%s\n' '# Missing frontmatter' > "$plan_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"artifact missing YAML frontmatter"* ]]
}

@test "validator rejects Claude sidechain QA plan artifact paths" {
  local sidechain_plan="$TEST_TEMP_DIR/repo/.claude/worktrees/agent-test/.vbw-planning/phases/01-test/remediation/qa/round-01/R01-PLAN.md"
  write_valid_plan "$sidechain_plan"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$sidechain_plan"
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

@test "validator accepts legacy phase-root research selected by layout=legacy" {
  local research_path="$PHASE_DIR/01-RESEARCH.md"
  mkdir -p "$PHASE_DIR/remediation/uat"
  printf 'stage=plan\nround=01\nlayout=legacy\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  write_valid_research "$research_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" research "$research_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifact_valid=true"* ]]
  [[ "$output" == *"artifact_path=$research_path"* ]]
}

@test "validator accepts highest legacy per-plan research selected by state metadata" {
  local stale_research="$PHASE_DIR/01-02-RESEARCH.md"
  local selected_research="$PHASE_DIR/01-03-RESEARCH.md"
  mkdir -p "$PHASE_DIR/remediation/uat"
  printf 'stage=plan\nround=01\nlayout=legacy\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  write_valid_research "$stale_research"
  write_valid_research "$selected_research"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" research "$selected_research"
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifact_valid=true"* ]]
}

@test "validator accepts highest legacy plan selected by state metadata" {
  local stale_plan="$PHASE_DIR/01-01-PLAN.md"
  local selected_plan="$PHASE_DIR/01-02-PLAN.md"
  mkdir -p "$PHASE_DIR/remediation/uat"
  printf 'stage=execute\nround=01\nlayout=legacy\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  write_valid_plan "$stale_plan"
  write_valid_plan "$selected_plan"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$selected_plan"
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifact_valid=true"* ]]
}

@test "validator rejects legacy phase-root artifacts for round-dir layout" {
  local research_path="$PHASE_DIR/01-RESEARCH.md"
  mkdir -p "$PHASE_DIR/remediation/uat"
  printf 'stage=plan\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  write_valid_research "$research_path"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" research "$research_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"legacy phase-root artifacts require layout=legacy"* ]]
}

@test "validator rejects stale lower legacy research when a higher one is selected" {
  local stale_research="$PHASE_DIR/01-02-RESEARCH.md"
  local selected_research="$PHASE_DIR/01-03-RESEARCH.md"
  mkdir -p "$PHASE_DIR/remediation/uat"
  printf 'stage=plan\nround=01\nlayout=legacy\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  write_valid_research "$stale_research"
  write_valid_research "$selected_research"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" research "$stale_research"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"legacy artifact is stale; expected $selected_research"* ]]
}

@test "validator rejects legacy research when round-dir research would be selected" {
  local legacy_research="$PHASE_DIR/01-RESEARCH.md"
  local round_research="$ROUND_DIR/R01-RESEARCH.md"
  mkdir -p "$PHASE_DIR/remediation/uat"
  printf 'stage=plan\nround=01\nlayout=legacy\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  write_valid_research "$legacy_research"
  write_valid_research "$round_research"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" research "$legacy_research"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"legacy artifact is stale; expected $round_research"* ]]
}

@test "validator accepts state-selected legacy plan after inferred round advances" {
  local stale_round_plan="$ROUND_DIR/R01-PLAN.md"
  local selected_plan selected_plan_physical plan_path
  selected_plan="$PHASE_DIR/01-02-PLAN.md"
  mkdir -p "$PHASE_DIR/remediation/uat"
  printf 'stage=execute\nround=01\nlayout=legacy\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  touch "$PHASE_DIR/01-UAT-round-01.md"
  write_valid_plan "$stale_round_plan"
  write_valid_plan "$selected_plan"
  selected_plan_physical="$(cd "$PHASE_DIR" && pwd -P)/01-02-PLAN.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [[ "$output" == *"round=02"* ]]
  [[ "$output" == *"plan_path=$selected_plan_physical"* ]]
  plan_path=$(awk -F= '/^plan_path=/ { print $2; exit }' <<< "$output")

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifact_valid=true"* ]]
  [[ "$output" == *"artifact_path=$selected_plan_physical"* ]]
}

@test "validator accepts legacy artifacts for digit-starting phase slug" {
  local digit_phase_dir digit_plan digit_research
  digit_phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-2024-refactor"
  digit_plan="$digit_phase_dir/01-04-PLAN.md"
  digit_research="$digit_phase_dir/01-03-RESEARCH.md"
  mkdir -p "$digit_phase_dir/remediation/uat"
  printf 'stage=execute\nround=01\nlayout=legacy\n' > "$digit_phase_dir/remediation/uat/.uat-remediation-stage"
  write_valid_plan "$digit_plan"
  write_valid_research "$digit_research"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$digit_plan"
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifact_valid=true"* ]]

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" research "$digit_research"
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifact_valid=true"* ]]
}

@test "validator accepts state-selected legacy plan for digit-starting phase slug" {
  local digit_phase_dir selected_plan selected_plan_physical plan_path
  digit_phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-2024-refactor"
  selected_plan="$digit_phase_dir/01-04-PLAN.md"
  mkdir -p "$digit_phase_dir/remediation/uat"
  printf 'stage=execute\nround=01\nlayout=legacy\n' > "$digit_phase_dir/remediation/uat/.uat-remediation-stage"
  write_valid_plan "$selected_plan"
  selected_plan_physical="$(cd "$digit_phase_dir" && pwd -P)/01-04-PLAN.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$digit_phase_dir" "major"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plan_path=$selected_plan_physical"* ]]
  plan_path=$(awk -F= '/^plan_path=/ { print $2; exit }' <<< "$output")

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" plan "$plan_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifact_valid=true"* ]]
  [[ "$output" == *"artifact_path=$selected_plan_physical"* ]]
}

@test "validator rejects legacy-looking summary path" {
  local legacy_summary="$PHASE_DIR/01-SUMMARY.md"
  mkdir -p "$PHASE_DIR/remediation/uat"
  printf 'stage=done\nround=01\nlayout=legacy\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  write_valid_summary "$legacy_summary"

  run bash "$SCRIPTS_DIR/validate-uat-remediation-artifact.sh" summary "$legacy_summary"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_valid=false"* ]]
  [[ "$output" == *"summary artifacts must use the round-dir layout"* ]]
}

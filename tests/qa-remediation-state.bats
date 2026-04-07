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

init_git_repo() {
  git -C "$TEST_TEMP_DIR" init -q
  git -C "$TEST_TEMP_DIR" config user.email "test@example.com"
  git -C "$TEST_TEMP_DIR" config user.name "VBW Test"
}

commit_repo_file() {
  local relative_path="${1}"
  local content="${2:-content}"
  mkdir -p "$(dirname "$TEST_TEMP_DIR/$relative_path")"
  printf '%s\n' "$content" > "$TEST_TEMP_DIR/$relative_path"
  git -C "$TEST_TEMP_DIR" add "$relative_path"
  git -C "$TEST_TEMP_DIR" commit -q -m "add $relative_path"
  git -C "$TEST_TEMP_DIR" rev-parse HEAD
}

write_phase_verification() {
  local result="$1"
  local body="$2"
  {
    echo '---'
    echo 'phase: 01'
    echo 'tier: standard'
    echo "result: ${result}"
    echo 'passed: 1'
    echo 'failed: 0'
    echo 'total: 1'
    echo 'date: 2026-04-06'
    echo 'writer: write-verification.sh'
    echo 'plans_verified:'
    echo '  - 01'
    echo '---'
    echo
    printf '%s\n' "$body"
  } > "$PHASE_DIR/01-VERIFICATION.md"
}

write_known_issues_file() {
  cat > "$PHASE_DIR/known-issues.json" <<'EOF'
{
  "schema_version": 1,
  "phase": "01",
  "issues": [
    {
      "test": "FIGIRegistryServiceTests",
      "file": "Tests/FIGIRegistryServiceTests.swift",
      "error": "compositeFigi missing",
      "first_seen_in": "01-01-SUMMARY.md",
      "last_seen_in": "01-VERIFICATION.md",
      "first_seen_round": 0,
      "last_seen_round": 0,
      "times_seen": 2
    }
  ]
}
EOF
}

# --- get command ---

@test "get returns none when no state file exists" {
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "get returns persisted stage" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=plan\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "plan" ]
}

@test "get emits metadata when stage is active" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=execute\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get "$PHASE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^round=02$"
  echo "$output" | grep -q "^round_dir=.*remediation/qa/round-02$"
}

@test "get canonicalizes unpadded round metadata on resume" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=verify\nround=2\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get "$PHASE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^round=02$"
  echo "$output" | grep -q "^round_dir=.*remediation/qa/round-02$"
  echo "$output" | grep -q "^plan_path=.*remediation/qa/round-02/R02-PLAN.md$"
  echo "$output" | grep -q "^summary_path=.*remediation/qa/round-02/R02-SUMMARY.md$"
  echo "$output" | grep -q "^verification_path=.*remediation/qa/round-02/R02-VERIFICATION.md$"
}

# --- init command ---

@test "init creates state file and round-01 dir" {
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "plan" ]
  [ -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ]
  grep -q "^stage=plan$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  grep -q "^round=01$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  [ -d "$PHASE_DIR/remediation/qa/round-01" ]
}

@test "init emits plan metadata" {
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$PHASE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^round=01$"
  echo "$output" | grep -q "^round_dir=.*remediation/qa/round-01$"
  echo "$output" | grep -q "^plan_path=.*R01-PLAN.md$"
}

@test "init emits known-issues-only input mode when PASS verification has tracked issues" {
  write_phase_verification "PASS" $'## Must-Have Checks\n| # | ID | Truth/Condition | Status | Evidence |\n|---|-----|-----------------|--------|----------|\n| 1 | MH-01 | Fixture check | PASS | Done |'
  write_known_issues_file

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *$'plan\n'* ]]
  [[ "$output" == *"source_verification_path="* ]]
  [[ "$output" == *"source_fail_count=0"* ]]
  [[ "$output" == *"known_issues_path=$PHASE_DIR/known-issues.json"* ]]
  [[ "$output" == *"known_issues_count=1"* ]]
  [[ "$output" == *"input_mode=known-issues"* ]]
}

@test "get reports both verification fails and known issues" {
  write_phase_verification "FAIL" $'## Must-Have Checks\n| # | ID | Truth/Condition | Status | Evidence |\n|---|-----|-----------------|--------|----------|\n| 1 | MH-01 | Fixture check | FAIL | Missing |'
  write_known_issues_file
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=plan\nround=01\nround_started_at_commit=abc123\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *$'plan\n'* ]]
  [[ "$output" == *"source_verification_path=$PHASE_DIR/01-VERIFICATION.md"* ]]
  [[ "$output" == *"source_fail_count=1"* ]]
  [[ "$output" == *"known_issues_count=1"* ]]
  [[ "$output" == *"input_mode=both"* ]]
}

@test "init captures round_started_at_commit from current git HEAD" {
  init_git_repo
  head_commit=$(commit_repo_file "src/base.txt" "baseline")

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$PHASE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^round_started_at_commit=${head_commit}$"
  grep -q "^round_started_at_commit=${head_commit}$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

# --- get-or-init command ---

@test "get-or-init initializes when no state exists" {
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get-or-init "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "plan" ]
  [ -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ]
  [ -d "$PHASE_DIR/remediation/qa/round-01" ]
}

@test "get-or-init returns existing stage without reinitializing" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-02"
  printf 'stage=execute\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get-or-init "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "execute" ]
  # Round preserved, not reset to 01
  echo "$output" | grep -q "^round=02$"
  grep -q "^stage=execute$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  grep -q "^round=02$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

# --- advance command ---

@test "advance chain: plan -> execute -> verify -> done" {
  bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$PHASE_DIR" >/dev/null

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR"
  [ "$(echo "$output" | head -1)" = "execute" ]
  grep -q "^stage=execute$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR"
  [ "$(echo "$output" | head -1)" = "verify" ]
  grep -q "^stage=verify$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR"
  [ "$(echo "$output" | head -1)" = "done" ]
  grep -q "^stage=done$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

@test "advance from done stays at done" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=done\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "done" ]
  grep -q "^stage=done$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

@test "advance preserves round number" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=plan\nround=03\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR"
  [ "$(echo "$output" | head -1)" = "execute" ]
  grep -q "^round=03$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

@test "advance with no active state errors" {
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR"
  [ "$status" -eq 1 ]
}

# --- needs-round command ---

@test "needs-round starts round-02 from done state" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=done\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "plan" ]
  echo "$output" | grep -q "^round=02$"
  [ -d "$PHASE_DIR/remediation/qa/round-02" ]
  grep -q "^stage=plan$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  grep -q "^round=02$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

@test "needs-round increments to round-03" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-02"
  printf 'stage=done\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^round=03$"
  [ -d "$PHASE_DIR/remediation/qa/round-03" ]
}

@test "needs-round refreshes round_started_at_commit to current HEAD" {
  init_git_repo
  first_commit=$(commit_repo_file "src/first.txt" "first")
  bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$PHASE_DIR" >/dev/null
  bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR" >/dev/null
  bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR" >/dev/null
  bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR" >/dev/null
  second_commit=$(commit_repo_file "src/second.txt" "second")

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^round=02$'
  echo "$output" | grep -q "^round_started_at_commit=${second_commit}$"
  grep -q "^round_started_at_commit=${second_commit}$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  [ "$first_commit" != "$second_commit" ]
}

@test "needs-round from verify stage succeeds" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "plan" ]
  echo "$output" | grep -q "^round=02$"
}

@test "needs-round from plan stage errors" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=plan\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 1 ]
}

@test "needs-round from execute stage errors" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=execute\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 1 ]
}

# --- reset command ---

@test "reset removes state file" {
  bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$PHASE_DIR" >/dev/null

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" reset "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
  [ ! -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ]
}

# --- error handling ---

@test "missing arguments exits with error" {
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh"
  [ "$status" -eq 1 ]

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get
  [ "$status" -eq 1 ]
}

@test "unknown command exits with error" {
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" bogus "$PHASE_DIR"
  [ "$status" -eq 1 ]
}

@test "archived milestone path is rejected" {
  ARCHIVED_DIR="$TEST_TEMP_DIR/.vbw-planning/milestones/v1/phases/01-test"
  mkdir -p "$ARCHIVED_DIR"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$ARCHIVED_DIR"
  [ "$status" -eq 1 ]
}

@test "needs-round with corrupt round value errors" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=done\nround=abc\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 1 ]
}

@test "advance with unknown stage errors" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=garbage\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR"
  [ "$status" -eq 1 ]
}

@test "get normalizes unknown stage to none" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=garbage\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "init overwrites existing state" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-02"
  printf 'stage=execute\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$PHASE_DIR"
  [ "$status" -eq 0 ]
  grep -q "^stage=plan$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  grep -q "^round=01$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

@test "needs-round exceeding max rounds exits with code 2" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-03"
  printf 'stage=done\nround=03\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 2 ]
}

# --- verification_path metadata ---

@test "emit_metadata includes verification_path on init" {
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$PHASE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^source_verification_path=$'
  echo "$output" | grep -q "^verification_path=.*remediation/qa/round-01/R01-VERIFICATION.md$"
}

@test "emit_metadata keeps source_verification_path empty when phase verification has no FAIL rows" {
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: PASS
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Structural bookkeeping passed | PASS | Done |
EOF

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$PHASE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^source_verification_path=$'
}

@test "emit_metadata includes verification_path on get" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf '%s\n' '---' 'result: FAIL' '---' '## Checks' '| ID | Category | Description | Status | Evidence |' '|----|----------|-------------|--------|----------|' '| R1-01 | must_have | Round 01 failed | FAIL | Missing |' > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md"
  printf 'stage=execute\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get "$PHASE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^source_verification_path=.*remediation/qa/round-01/R01-VERIFICATION.md$"
  echo "$output" | grep -q "^verification_path=.*remediation/qa/round-02/R02-VERIFICATION.md$"
}

@test "emit_metadata includes verification_path on get-or-init" {
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get-or-init "$PHASE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^verification_path=.*remediation/qa/round-01/R01-VERIFICATION.md$"
}

@test "verification_path updates after needs-round" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=done\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  printf '%s\n' '---' 'result: FAIL' '---' '## Checks' '| ID | Category | Description | Status | Evidence |' '|----|----------|-------------|--------|----------|' '| R1-01 | must_have | Round 01 failed | FAIL | Missing |' > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^round=02$"
  echo "$output" | grep -q "^source_verification_path=.*remediation/qa/round-01/R01-VERIFICATION.md$"
  # After needs-round, get should show round-02 verification_path
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get "$PHASE_DIR"
  echo "$output" | grep -q "^source_verification_path=.*remediation/qa/round-01/R01-VERIFICATION.md$"
  echo "$output" | grep -q "^verification_path=.*remediation/qa/round-02/R02-VERIFICATION.md$"
}

@test "verification_path updates after needs-round but leaves source_verification_path empty when no FAIL source remains" {
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
  printf 'stage=done\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  printf '%s\n' '---' 'result: PASS' '---' '## Checks' '| ID | Category | Description | Status | Evidence |' '|----|----------|-------------|--------|----------|' '| MH-01 | must_have | Structural bookkeeping passed | PASS | Done |' > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^source_verification_path=$'
  echo "$output" | grep -q "^verification_path=.*remediation/qa/round-02/R02-VERIFICATION.md$"
}

@test "verification_path preserved through advance" {
  bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$PHASE_DIR" >/dev/null
  bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR" >/dev/null

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get "$PHASE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^verification_path=.*remediation/qa/round-01/R01-VERIFICATION.md$"
}

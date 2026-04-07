#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/phases/03-test-phase"
  SCRIPT="$SCRIPTS_DIR/track-known-issues.sh"
  mkdir -p "$PHASE_DIR"
}

teardown() {
  teardown_temp_dir
}

write_summary_with_preexisting() {
  local file_name="$1"
  local plan_id="$2"
  local issues="$3"
  {
    echo '---'
    echo "phase: 03"
    echo "plan: ${plan_id}"
    echo 'status: complete'
    echo '---'
    echo
    echo '## What Was Built'
    echo '- Something useful'
    if [ -n "$issues" ]; then
      echo
      echo '## Pre-existing Issues'
      while IFS= read -r issue; do
        [ -n "$issue" ] && printf '%s\n' "- $issue"
      done <<< "$issues"
    fi
  } > "$PHASE_DIR/$file_name"
}

write_verification_with_issues() {
  local relative_path="$1"
  local rows="$2"
  local plans_verified='03-01'
  local base
  base=$(basename "$relative_path")
  if [[ "$base" =~ ^R([0-9]+)-VERIFICATION\.md$ ]]; then
    plans_verified="R${BASH_REMATCH[1]}"
  fi
  mkdir -p "$(dirname "$PHASE_DIR/$relative_path")"
  {
    echo '---'
    echo 'phase: 03'
    echo 'tier: standard'
    echo 'result: PASS'
    echo 'passed: 1'
    echo 'failed: 0'
    echo 'total: 1'
    echo 'date: 2026-04-06'
    echo 'writer: write-verification.sh'
    echo 'plans_verified:'
    echo "  - ${plans_verified}"
    echo '---'
    echo
    echo '## Must-Have Checks'
    echo '| # | ID | Truth/Condition | Status | Evidence |'
    echo '|---|-----|-----------------|--------|----------|'
    echo '| 1 | MH-01 | Fixture check | PASS | Done |'
    if [ -n "$rows" ]; then
      echo
      echo '## Pre-existing Issues'
      echo
      echo '| Test | File | Error |'
      echo '|------|------|-------|'
      while IFS=$'\t' read -r test file error; do
        [ -n "$test" ] || continue
        printf '| %s | %s | %s |\n' "$test" "$file" "$error"
      done <<< "$rows"
    fi
  } > "$PHASE_DIR/$relative_path"
}

@test "track-known-issues: sync-summaries creates registry and de-duplicates by test+file" {
  write_summary_with_preexisting "03-01-SUMMARY.md" "03-01" $'TransferMatchingServiceTests (Tests/TransferMatchingServiceTests.swift): debugTestConfiguration missing\nFIGIRegistryServiceTests.swift: compositeFigi missing'
  write_summary_with_preexisting "03-02-SUMMARY.md" "03-02" $'TransferMatchingServiceTests (Tests/TransferMatchingServiceTests.swift): newer duplicate error text'

  run bash "$SCRIPT" sync-summaries "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"known_issues_status=present"* ]]
  [[ "$output" == *"known_issues_count=2"* ]]
  [ -f "$PHASE_DIR/known-issues.json" ]
  run jq -r '.issues | length' "$PHASE_DIR/known-issues.json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
  run jq -r '.issues[] | select(.test == "TransferMatchingServiceTests") | .error' "$PHASE_DIR/known-issues.json"
  [ "$status" -eq 0 ]
  [ "$output" = "debugTestConfiguration missing" ]
}

@test "track-known-issues: phase-level verification merges new issues without clearing summary backlog" {
  write_summary_with_preexisting "03-01-SUMMARY.md" "03-01" 'TransferMatchingServiceTests.swift: debugTestConfiguration missing'
  bash "$SCRIPT" sync-summaries "$PHASE_DIR" >/dev/null
  write_verification_with_issues "03-VERIFICATION.md" $'FIGIRegistryServiceTests\tTests/FIGIRegistryServiceTests.swift\tcompositeFigi missing'

  run bash "$SCRIPT" sync-verification "$PHASE_DIR" "$PHASE_DIR/03-VERIFICATION.md"

  [ "$status" -eq 0 ]
  [[ "$output" == *"known_issues_count=2"* ]]
  run jq -r '.issues | sort_by(.test, .file) | map(.test) | join(",")' "$PHASE_DIR/known-issues.json"
  [ "$status" -eq 0 ]
  [ "$output" = "FIGIRegistryServiceTests,TransferMatchingServiceTests.swift" ]
}

@test "track-known-issues: round verification prunes resolved issues and keeps unresolved ones" {
  write_summary_with_preexisting "03-01-SUMMARY.md" "03-01" $'TransferMatchingServiceTests.swift: debugTestConfiguration missing\nFIGIRegistryServiceTests.swift: compositeFigi missing'
  bash "$SCRIPT" sync-summaries "$PHASE_DIR" >/dev/null
  write_verification_with_issues "remediation/qa/round-01/R01-VERIFICATION.md" $'FIGIRegistryServiceTests\tTests/FIGIRegistryServiceTests.swift\tcompositeFigi missing'

  run bash "$SCRIPT" sync-verification "$PHASE_DIR" "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md"

  [ "$status" -eq 0 ]
  [[ "$output" == *"known_issues_count=1"* ]]
  run jq -r '.issues[0].test' "$PHASE_DIR/known-issues.json"
  [ "$status" -eq 0 ]
  [ "$output" = "FIGIRegistryServiceTests" ]
}

@test "track-known-issues: round verification with no issues clears registry" {
  write_summary_with_preexisting "03-01-SUMMARY.md" "03-01" 'TransferMatchingServiceTests.swift: debugTestConfiguration missing'
  bash "$SCRIPT" sync-summaries "$PHASE_DIR" >/dev/null
  write_verification_with_issues "remediation/qa/round-01/R01-VERIFICATION.md" ''

  run bash "$SCRIPT" sync-verification "$PHASE_DIR" "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md"

  [ "$status" -eq 0 ]
  [[ "$output" == *"known_issues_status=missing"* ]]
  [[ "$output" == *"known_issues_count=0"* ]]
  [ ! -f "$PHASE_DIR/known-issues.json" ]
}

@test "track-known-issues: status reports malformed registry" {
  printf '%s\n' '{not-json' > "$PHASE_DIR/known-issues.json"

  run bash "$SCRIPT" status "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"known_issues_status=malformed"* ]]
  [[ "$output" == *"known_issues_count=0"* ]]
}
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
  local issue test file error issue_json
  {
    echo '---'
    echo "phase: 03"
    echo "plan: ${plan_id}"
    echo 'status: complete'
    if [ -n "$issues" ]; then
      echo 'pre_existing_issues:'
      while IFS= read -r issue; do
        [ -n "$issue" ] || continue
        if [[ "$issue" =~ ^(.+)[[:space:]]+\(([^()]+)\):[[:space:]]*(.+)$ ]]; then
          test="${BASH_REMATCH[1]}"
          file="${BASH_REMATCH[2]}"
          error="${BASH_REMATCH[3]}"
        elif [[ "$issue" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
          test="${BASH_REMATCH[1]}"
          file="$test"
          error="${BASH_REMATCH[2]}"
        else
          continue
        fi
        issue_json=$(jq -cn --arg test "$test" --arg file "$file" --arg error "$error" '{test:$test,file:$file,error:$error}')
        printf "%s\n" "  - '$issue_json'"
      done <<< "$issues"
    else
      echo 'pre_existing_issues: []'
    fi
    echo '---'
    echo
    echo '## What Was Built'
    echo '- Something useful'
  } > "$PHASE_DIR/$file_name"
}

write_legacy_summary_with_preexisting() {
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

write_round_summary_with_known_issue_outcomes() {
  local relative_path="$1"
  local outcomes_json="$2"
  mkdir -p "$(dirname "$PHASE_DIR/$relative_path")"
  {
    echo '---'
    echo 'phase: 03'
    echo 'round: 01'
    echo 'title: Round summary with known issue outcomes'
    echo 'type: remediation'
    echo 'status: complete'
    echo 'completed: 2026-04-08'
    echo 'tasks_completed: 1'
    echo 'tasks_total: 1'
    echo 'commit_hashes: []'
    echo 'files_modified:'
    printf '  - "%s"\n' "03-test-phase/${relative_path}"
    echo 'deviations: []'
    echo 'known_issue_outcomes:'
    while IFS= read -r outcome; do
      [ -n "$outcome" ] || continue
      printf "  - '%s'\n" "$outcome"
    done <<< "$outcomes_json"
    echo '---'
    echo
    echo '## Task 1: Document known issue outcomes'
    echo
    echo '### What Was Built'
    echo '- Captured the carried known-issue disposition for this round'
  } > "$PHASE_DIR/$relative_path"
}

@test "track-known-issues: sync-summaries creates registry and de-duplicates by test+file+error" {
  write_summary_with_preexisting "03-01-SUMMARY.md" "03-01" $'TransferMatchingServiceTests (Tests/TransferMatchingServiceTests.swift): debugTestConfiguration missing\nFIGIRegistryServiceTests.swift: compositeFigi missing'
  write_summary_with_preexisting "03-02-SUMMARY.md" "03-02" $'TransferMatchingServiceTests (Tests/TransferMatchingServiceTests.swift): debugTestConfiguration missing'

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

@test "track-known-issues: missing registry restore from phase-level verification preserves summary backlog" {
  write_summary_with_preexisting "03-01-SUMMARY.md" "03-01" 'TransferMatchingServiceTests.swift: debugTestConfiguration missing'
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

@test "track-known-issues: round verification with no issues clears existing registry" {
  write_summary_with_preexisting "03-01-SUMMARY.md" "03-01" 'TransferMatchingServiceTests.swift: debugTestConfiguration missing'
  bash "$SCRIPT" sync-summaries "$PHASE_DIR" >/dev/null
  write_verification_with_issues "remediation/qa/round-01/R01-VERIFICATION.md" ''

  run bash "$SCRIPT" sync-verification "$PHASE_DIR" "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md"

  [ "$status" -eq 0 ]
  [[ "$output" == *"known_issues_status=missing"* ]]
  [[ "$output" == *"known_issues_count=0"* ]]
  [ ! -f "$PHASE_DIR/known-issues.json" ]
}

@test "track-known-issues: round verification with no prior registry and no issues stays empty" {
  write_verification_with_issues "remediation/qa/round-01/R01-VERIFICATION.md" ''

  run bash "$SCRIPT" sync-verification "$PHASE_DIR" "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md"

  [ "$status" -eq 0 ]
  [[ "$output" == *"known_issues_status=missing"* ]]
  [[ "$output" == *"known_issues_count=0"* ]]
  [ ! -f "$PHASE_DIR/known-issues.json" ]
}

@test "track-known-issues: issues differing only by error are kept distinct" {
  local ver_path="remediation/qa/round-01/R01-VERIFICATION.md"
  local issue_rows
  issue_rows=$'TestCrash\tCrashTests.swift\tsignal trap\nTestCrash\tCrashTests.swift\tnull pointer'
  write_verification_with_issues "$ver_path" "$issue_rows"

  run bash "$SCRIPT" sync-verification "$PHASE_DIR" "$PHASE_DIR/$ver_path"

  [ "$status" -eq 0 ]
  [[ "$output" == *"known_issues_count=2"* ]]
  run jq -r '.issues | length' "$PHASE_DIR/known-issues.json"
  [ "$output" = "2" ]
  run jq -r '.issues[0].error' "$PHASE_DIR/known-issues.json"
  [ "$output" = "null pointer" ]
  run jq -r '.issues[1].error' "$PHASE_DIR/known-issues.json"
  [ "$output" = "signal trap" ]
}

@test "track-known-issues: status reports malformed registry" {
  printf '%s\n' '{not-json' > "$PHASE_DIR/known-issues.json"

  run bash "$SCRIPT" status "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"known_issues_status=malformed"* ]]
  [[ "$output" == *"known_issues_count=0"* ]]
}

@test "track-known-issues: sync-summaries still supports legacy body sections" {
  write_legacy_summary_with_preexisting "03-01-SUMMARY.md" "03-01" 'LegacyIssueTests.swift: legacy fallback still works'

  run bash "$SCRIPT" sync-summaries "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"known_issues_count=1"* ]]
  run jq -r '.issues[0].test' "$PHASE_DIR/known-issues.json"
  [ "$status" -eq 0 ]
  [ "$output" = "LegacyIssueTests.swift" ]
}

@test "track-known-issues: explicit empty frontmatter suppresses stale legacy body fallback" {
  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'EOF'
---
phase: 03
plan: 03-01
status: complete
pre_existing_issues: []
---

## What Was Built
- Something useful

## Pre-existing Issues
- GhostIssueTests.swift: stale body issue must be ignored
EOF

  run bash "$SCRIPT" sync-summaries "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"known_issues_status=missing"* ]]
  [[ "$output" == *"known_issues_count=0"* ]]
  [ ! -f "$PHASE_DIR/known-issues.json" ]
}

@test "track-known-issues: repeated sync-summaries is idempotent for unchanged summaries" {
  write_summary_with_preexisting "03-01-SUMMARY.md" "03-01" 'TransferMatchingServiceTests.swift: debugTestConfiguration missing'

  bash "$SCRIPT" sync-summaries "$PHASE_DIR" >/dev/null
  first_state=$(jq -cS '.issues[0]' "$PHASE_DIR/known-issues.json")

  run bash "$SCRIPT" sync-summaries "$PHASE_DIR"

  [ "$status" -eq 0 ]
  second_state=$(jq -cS '.issues[0]' "$PHASE_DIR/known-issues.json")
  [ "$first_state" = "$second_state" ]
}

# --- promote-todos tests ---

write_state_md_with_todos() {
  local content="${1:-None.}"
  {
    echo '# Project State'
    echo ''
    echo '## Decisions'
    echo 'None.'
    echo ''
    echo '## Todos'
    echo "$content"
    echo ''
    echo '## Blockers'
    echo 'None.'
  } > "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

write_legacy_state_md_with_todos() {
  local content="${1:-None.}"
  {
    echo '# Project State'
    echo ''
    echo '## Decisions'
    echo 'None.'
    echo ''
    echo '## Todos'
    echo ''
    echo '### Pending Todos'
    echo "$content"
    echo ''
    echo '### Completed Todos'
    echo 'None.'
    echo ''
    echo '## Blockers'
    echo 'None.'
  } > "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

write_known_issues_registry() {
  local phase_num="$1"
  shift
  local issues_json="[]"
  for issue_json in "$@"; do
    issues_json=$(echo "$issues_json" | jq --argjson i "$issue_json" '. + [$i]')
  done
  jq -n --arg p "$phase_num" --argjson iss "$issues_json" \
    '{schema_version:1, phase:$p, issues:$iss}' > "$PHASE_DIR/known-issues.json"
}

@test "track-known-issues: promote-todos with empty registry promotes nothing" {
  write_state_md_with_todos "None."
  echo '{"schema_version":1,"phase":"03","issues":[]}' > "$PHASE_DIR/known-issues.json"

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"promoted_count=0"* ]]
  [[ "$output" == *"total_known_issues=0"* ]]
  grep -q "None\." "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-known-issues: promote-todos adds new issues to STATE.md" {
  write_state_md_with_todos "None."
  write_known_issues_registry "03" \
    '{"test":"TestCrash","file":"CrashTests.swift","error":"signal trap","first_seen_in":"03-01","last_seen_in":"03-02","first_seen_round":1,"last_seen_round":2,"times_seen":3}'

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"promoted_count=1"* ]]
  [[ "$output" == *"total_known_issues=1"* ]]
  # None. placeholder must be removed from Todos section
  run bash -c 'awk "/^## Todos?$/{f=1;next} f&&/^##/{exit} f" "$1" | grep -q "^None\\.$"' -- "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  [ "$status" -ne 0 ]
  # Entry must exist with [KNOWN-ISSUE] tag
  grep -q "\[KNOWN-ISSUE\]" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "TestCrash" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "CrashTests.swift" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  # Source traceability from last_seen_in field
  grep -q "(see 03-02)" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-known-issues: promote-todos deduplicates existing entries" {
  write_state_md_with_todos "- [KNOWN-ISSUE] TestCrash (CrashTests.swift): signal trap (phase 03, seen 2x) (see 03-01) (added 2025-01-01)"
  write_known_issues_registry "03" \
    '{"test":"TestCrash","file":"CrashTests.swift","error":"signal trap","first_seen_in":"03-01","last_seen_in":"03-02","first_seen_round":1,"last_seen_round":2,"times_seen":3}'

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # Existing ref-less lines are healed in place with a stable ref/signature payload.
  [[ "$output" == *"promoted_count=1"* ]]
  [[ "$output" == *"already_tracked_count=0"* ]]
  # Only one [KNOWN-ISSUE] line (no duplicate) and the healed line now carries a ref.
  local count
  count=$(grep -c "\[KNOWN-ISSUE\]" "$TEST_TEMP_DIR/.vbw-planning/STATE.md")
  [ "$count" -eq 1 ]
  grep -q '(ref:' "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-known-issues: promote-todos replaces None placeholder" {
  write_state_md_with_todos "None."
  write_known_issues_registry "03" \
    '{"test":"TestA","file":"A.swift","error":"err","first_seen_in":"03-01","last_seen_in":"03-01","first_seen_round":1,"last_seen_round":1,"times_seen":1}'

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # None. placeholder must be removed from Todos section
  run bash -c 'awk "/^## Todos?$/{f=1;next} f&&/^##/{exit} f" "$1" | grep -q "^None\\.$"' -- "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  [ "$status" -ne 0 ]
  grep -q "\[KNOWN-ISSUE\] TestA (A.swift)" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-known-issues: promote-todos handles multiple issues" {
  write_state_md_with_todos "- [HIGH] Existing high-pri todo (added 2025-01-01)"
  write_known_issues_registry "03" \
    '{"test":"TestA","file":"A.swift","error":"err A","first_seen_in":"03-01","last_seen_in":"03-01","first_seen_round":1,"last_seen_round":1,"times_seen":1}' \
    '{"test":"TestB","file":"B.swift","error":"err B","first_seen_in":"03-02","last_seen_in":"03-02","first_seen_round":2,"last_seen_round":2,"times_seen":2}'

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"promoted_count=2"* ]]
  # Original high-pri todo preserved
  grep -q "\[HIGH\]" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  # Both new entries present
  grep -q "TestA" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "TestB" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-known-issues: promote-todos works with legacy Pending Todos layout" {
  write_legacy_state_md_with_todos "None."
  write_known_issues_registry "03" \
    '{"test":"TestCrash","file":"CrashTests.swift","error":"signal trap","first_seen_in":"03-01","last_seen_in":"03-01","first_seen_round":1,"last_seen_round":1,"times_seen":1}'

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"promoted_count=1"* ]]
  # None. placeholder must be removed from Pending Todos section
  run bash -c 'awk "/^### Pending Todos$/{f=1;next} f&&/^##/{exit} f" "$1" | grep -q "^None\\.$"' -- "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  [ "$status" -ne 0 ]
  grep -q "\[KNOWN-ISSUE\] TestCrash (CrashTests.swift)" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  # Legacy section structure preserved
  grep -q "### Pending Todos" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "### Completed Todos" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-known-issues: promote-todos appends to non-empty legacy Pending Todos" {
  write_legacy_state_md_with_todos "- [HIGH] Fix login bug"
  write_known_issues_registry "03" \
    '{"test":"TestCrash","file":"CrashTests.swift","error":"signal trap","first_seen_in":"03-01","last_seen_in":"03-01","first_seen_round":1,"last_seen_round":1,"times_seen":1}'

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"promoted_count=1"* ]]
  # Original entry preserved
  grep -q "\[HIGH\] Fix login bug" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  # New entry added under Pending Todos
  grep -q "\[KNOWN-ISSUE\] TestCrash (CrashTests.swift)" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  # Completed Todos section preserved and not contaminated
  grep -q "### Completed Todos" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  # Known issue appears before Completed Todos, not after
  run bash -c 'awk "/^### Completed Todos/{exit} /KNOWN-ISSUE/{found=1} END{exit !found}" "$1"' -- "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  [ "$status" -eq 0 ]
}

@test "track-known-issues: promote-todos dedup uses exact key not substring" {
  # testFoo exists but we're promoting testFooBar — must NOT be suppressed
  write_state_md_with_todos "- [KNOWN-ISSUE] testFoo (path/a.swift): err (phase 03, seen 1x) (added 2025-01-01)"
  write_known_issues_registry "03" \
    '{"test":"testFooBar","file":"path/a.swift","error":"different err","first_seen_in":"03-01","last_seen_in":"03-01","first_seen_round":1,"last_seen_round":1,"times_seen":1}'

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"promoted_count=1"* ]]
  [[ "$output" == *"already_tracked_count=0"* ]]
  # Both entries present
  grep -q "testFoo " "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "testFooBar" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-known-issues: promote-todos includes accepted non-blocking round outcomes when registry is empty" {
  write_state_md_with_todos "None."
  echo '{"schema_version":1,"phase":"03","issues":[]}' > "$PHASE_DIR/known-issues.json"
  write_round_summary_with_known_issue_outcomes "remediation/qa/round-01/R01-SUMMARY.md" '{"test":"OptionAdjustmentE2ETests (all 10)","file":"OptionAdjustmentE2ETests.swift","error":"Signal Trap","disposition":"accepted-process-exception","rationale":"Pre-existing SwiftData crash accepted for this phase"}'

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"promoted_count=1"* ]]
  grep -q "\[KNOWN-ISSUE\] OptionAdjustmentE2ETests (all 10) (OptionAdjustmentE2ETests.swift): Signal Trap" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "accepted as process-exception" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "(see remediation/qa/round-01/R01-SUMMARY.md)" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-known-issues: promote-todos updates already-tracked issue with accepted disposition" {
  # Issue already tracked in STATE.md without disposition annotation
  write_state_md_with_todos "- [KNOWN-ISSUE] SignalTrapTests (SignalTrapTests.swift): SwiftData signal trap (phase 03, seen 1x) (added 2026-04-01)"
  # Same issue in registry
  write_known_issues_registry "03" \
    '{"test":"SignalTrapTests","file":"SignalTrapTests.swift","error":"SwiftData signal trap","last_seen_in":"03-01-SUMMARY.md","last_seen_round":1,"times_seen":1}'
  # Round summary now accepts it as process-exception
  write_round_summary_with_known_issue_outcomes "remediation/qa/round-02/R02-SUMMARY.md" \
    '{"test":"SignalTrapTests","file":"SignalTrapTests.swift","error":"SwiftData signal trap","disposition":"accepted-process-exception","rationale":"Pre-existing SwiftData crash accepted for this phase"}'

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"promoted_count=1"* ]]
  # The existing line should be rewritten with the accepted annotation
  grep -q "accepted as process-exception" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  # The old un-annotated line should be gone
  ! grep -q "\[KNOWN-ISSUE\] SignalTrapTests (SignalTrapTests.swift): SwiftData signal trap (phase 03, seen 1x) (added 2026-04-01)" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-known-issues: promote-todos aggregates accepted outcomes across multiple remediation rounds" {
  # R01 accepts an issue, R02 has no known_issue_outcomes → promote-todos must still see R01's acceptance
  write_state_md_with_todos "None."
  echo '{"schema_version":1,"phase":"03","issues":[]}' > "$PHASE_DIR/known-issues.json"

  # R01 summary with accepted-process-exception outcome
  write_round_summary_with_known_issue_outcomes "remediation/qa/round-01/R01-SUMMARY.md" \
    '{"test":"SignalTrapTests","file":"SignalTrapTests.swift","error":"SwiftData signal trap","disposition":"accepted-process-exception","rationale":"Pre-existing crash accepted for this phase"}'

  # R02 summary with no known_issue_outcomes (separate code fix, no carried issues)
  mkdir -p "$PHASE_DIR/remediation/qa/round-02"
  printf '%s\n' \
    '---' \
    'phase: 03' \
    'round: 02' \
    'title: Code fix round' \
    'type: remediation' \
    'status: complete' \
    'completed: 2026-04-09' \
    'tasks_completed: 1' \
    'tasks_total: 1' \
    'commit_hashes: []' \
    'files_modified:' \
    '  - "src/Fix.swift"' \
    'deviations: []' \
    '---' \
    '' \
    '## Task 1: Code fix' \
    '' \
    '### What Was Built' \
    '- Fixed unrelated code issue' \
    > "$PHASE_DIR/remediation/qa/round-02/R02-SUMMARY.md"

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"promoted_count=1"* ]]
  grep -q "\[KNOWN-ISSUE\] SignalTrapTests (SignalTrapTests.swift): SwiftData signal trap" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "accepted as process-exception" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  # Source artifact should reference R01, not R02
  grep -q "(see remediation/qa/round-01/R01-SUMMARY.md)" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-known-issues: promote-todos later resolved disposition overrides earlier acceptance and prevents promotion" {
  # R01 accepts issue as process-exception, R02 resolves it → both dispositions
  # enter the aggregator via "all" filter, merge_issue_sets gives R02's "resolved"
  # priority, and the post-merge filter excludes non-accepted-process-exception entries
  write_state_md_with_todos "None."
  echo '{"schema_version":1,"phase":"03","issues":[]}' > "$PHASE_DIR/known-issues.json"

  # R01 accepts the issue
  write_round_summary_with_known_issue_outcomes "remediation/qa/round-01/R01-SUMMARY.md" \
    '{"test":"SignalTrapTests","file":"SignalTrapTests.swift","error":"SwiftData signal trap","disposition":"accepted-process-exception","rationale":"Accepted for this phase"}'

  # R02 resolves the same issue (enters accumulator via "all" filter, filtered post-merge)
  mkdir -p "$PHASE_DIR/remediation/qa/round-02"
  printf '%s\n' \
    '---' \
    'phase: 03' \
    'round: 02' \
    'title: Fix round' \
    'type: remediation' \
    'status: complete' \
    'completed: 2026-04-09' \
    'tasks_completed: 1' \
    'tasks_total: 1' \
    'commit_hashes: []' \
    'files_modified:' \
    '  - "src/Fix.swift"' \
    'deviations: []' \
    "known_issue_outcomes:" \
    "  - '{\"test\":\"SignalTrapTests\",\"file\":\"SignalTrapTests.swift\",\"error\":\"SwiftData signal trap\",\"disposition\":\"resolved\",\"rationale\":\"Fixed the crash\"}'" \
    '---' \
    '' \
    '## Task 1: Fix crash' \
    '' \
    '### What Was Built' \
    '- Fixed the SwiftData signal trap' \
    > "$PHASE_DIR/remediation/qa/round-02/R02-SUMMARY.md"

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # R02's "resolved" disposition enters the accumulator (parser uses "all" filter during
  # aggregation), merge_issue_sets propagates R02's non-empty disposition over R01's
  # accepted-process-exception. The post-merge filter then excludes the now-"resolved"
  # entry. Result: nothing is promoted because the issue was resolved in a later round.
  [[ "$output" == *"promoted_count=0"* ]]
  # STATE.md should still have the placeholder — no promotion occurred
  grep -q "None\." "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-known-issues: promote-todos aggregates when later round has explicit empty known_issue_outcomes" {
  # Like the multi-round test but R02 has known_issue_outcomes: [] explicitly instead of omitting the key
  write_state_md_with_todos "None."
  echo '{"schema_version":1,"phase":"03","issues":[]}' > "$PHASE_DIR/known-issues.json"

  # R01 summary with accepted-process-exception outcome
  write_round_summary_with_known_issue_outcomes "remediation/qa/round-01/R01-SUMMARY.md" \
    '{"test":"SignalTrapTests","file":"SignalTrapTests.swift","error":"SwiftData signal trap","disposition":"accepted-process-exception","rationale":"Pre-existing crash accepted for this phase"}'

  # R02 summary with explicit empty known_issue_outcomes array
  mkdir -p "$PHASE_DIR/remediation/qa/round-02"
  printf '%s\n' \
    '---' \
    'phase: 03' \
    'round: 02' \
    'title: Code fix round' \
    'type: remediation' \
    'status: complete' \
    'completed: 2026-04-09' \
    'tasks_completed: 1' \
    'tasks_total: 1' \
    'commit_hashes: []' \
    'files_modified:' \
    '  - "src/Fix.swift"' \
    'deviations: []' \
    'known_issue_outcomes: []' \
    '---' \
    '' \
    '## Task 1: Code fix' \
    '' \
    '### What Was Built' \
    '- Fixed unrelated code issue' \
    > "$PHASE_DIR/remediation/qa/round-02/R02-SUMMARY.md"

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"promoted_count=1"* ]]
  grep -q "\[KNOWN-ISSUE\] SignalTrapTests (SignalTrapTests.swift): SwiftData signal trap" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "accepted as process-exception" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "(see remediation/qa/round-01/R01-SUMMARY.md)" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-known-issues: promote-todos ignores invalid disposition in later round during aggregation" {
  # R01 accepts an issue, R02 has a misspelled disposition for the same issue.
  # The parser's IN() validation rejects the invalid disposition, so R01's
  # accepted-process-exception survives because the invalid entry never enters the accumulator.
  write_state_md_with_todos "None."
  echo '{"schema_version":1,"phase":"03","issues":[]}' > "$PHASE_DIR/known-issues.json"

  # R01 accepts the issue
  write_round_summary_with_known_issue_outcomes "remediation/qa/round-01/R01-SUMMARY.md" \
    '{"test":"SignalTrapTests","file":"SignalTrapTests.swift","error":"SwiftData signal trap","disposition":"accepted-process-exception","rationale":"Accepted for this phase"}'

  # R02 has the same issue with a misspelled disposition
  mkdir -p "$PHASE_DIR/remediation/qa/round-02"
  printf '%s\n' \
    '---' \
    'phase: 03' \
    'round: 02' \
    'title: Fix round' \
    'type: remediation' \
    'status: complete' \
    'completed: 2026-04-09' \
    'tasks_completed: 1' \
    'tasks_total: 1' \
    'commit_hashes: []' \
    'files_modified:' \
    '  - "src/Fix.swift"' \
    'deviations: []' \
    "known_issue_outcomes:" \
    "  - '{\"test\":\"SignalTrapTests\",\"file\":\"SignalTrapTests.swift\",\"error\":\"SwiftData signal trap\",\"disposition\":\"reoslved\",\"rationale\":\"Typo disposition\"}'" \
    '---' \
    '' \
    '## Task 1: Fix' \
    '' \
    '### What Was Built' \
    '- Attempted fix' \
    > "$PHASE_DIR/remediation/qa/round-02/R02-SUMMARY.md"

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # The invalid disposition "reoslved" is rejected by the IN() filter, so R01's
  # accepted-process-exception survives and the issue is promoted
  [[ "$output" == *"promoted_count=1"* ]]
  grep -q "\[KNOWN-ISSUE\] SignalTrapTests (SignalTrapTests.swift): SwiftData signal trap" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "accepted as process-exception" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-known-issues: promote-todos honors suppression store across registry and accepted outcomes" {
  write_state_md_with_todos "None."
  write_known_issues_registry "03" \
    '{"test":"SignalTrapTests","file":"SignalTrapTests.swift","error":"SwiftData signal trap","last_seen_in":"03-01-SUMMARY.md","last_seen_round":1,"times_seen":1,"source_kind":"registry"}'
  write_round_summary_with_known_issue_outcomes "remediation/qa/round-01/R01-SUMMARY.md" \
    '{"test":"SignalTrapTests","file":"SignalTrapTests.swift","error":"SwiftData signal trap","disposition":"accepted-process-exception","rationale":"Accepted for this phase"}'

  jq -n --arg phase_dir "$PHASE_DIR" '
    {
      schema_version: 1,
      phase: "03",
      suppressions: [
        {
          phase: "03",
          phase_dir: $phase_dir,
          test: "SignalTrapTests",
          file: "SignalTrapTests.swift",
          error: "SwiftData signal trap",
          source_kind: "registry",
          disposition: "unresolved",
          source_path: "03-01-SUMMARY.md"
        }
      ]
    }
  ' > "$PHASE_DIR/known-issue-suppressions.json"

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"promoted_count=0"* ]]
  [[ "$output" == *"promote_status=empty_registry"* ]]
  grep -q '^None\.$' "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-known-issues: promote-todos fails safe when suppression storage is unavailable" {
  write_state_md_with_todos "None."
  write_known_issues_registry "03" \
    '{"test":"SignalTrapTests","file":"SignalTrapTests.swift","error":"SwiftData signal trap","last_seen_in":"03-01-SUMMARY.md","last_seen_round":1,"times_seen":1,"source_kind":"registry"}'

  chmod u-w "$PHASE_DIR"
  run bash "$SCRIPT" promote-todos "$PHASE_DIR"
  chmod u+w "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"promoted_count=0"* ]]
  [[ "$output" == *"promote_status=suppression_unavailable"* ]]
  grep -q '^None\.$' "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-known-issues: lookup-signature resolves a unique legacy registry issue" {
  write_known_issues_registry "03" \
    '{"test":"SignalTrapTests","file":"SignalTrapTests.swift","error":"SwiftData signal trap","last_seen_in":"03-VERIFICATION.md","last_seen_round":1,"times_seen":1,"source_kind":"registry"}'

  QUERY=$(jq -cn '{test:"SignalTrapTests",file:"SignalTrapTests.swift",error:"SwiftData signal trap",disposition:"unresolved",source_path:"03-VERIFICATION.md"}')
  run bash -lc 'printf "%s" "$1" | bash "$2" lookup-signature "$3"' -- "$QUERY" "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
  [ "$(echo "$output" | jq -r '.signature.test')" = "SignalTrapTests" ]
  [ "$(echo "$output" | jq -r '.signature.file')" = "SignalTrapTests.swift" ]
  [ "$(echo "$output" | jq -r '.signature.error')" = "SwiftData signal trap" ]
}

@test "track-known-issues: promote-todos does not collapse distinct long errors with same visible prefix" {
  local long_prefix
  local err_one
  local err_two
  long_prefix=$(printf 'prefix%.0s' {1..20})
  err_one="${long_prefix}-first-distinct-tail"
  err_two="${long_prefix}-second-distinct-tail"

  write_state_md_with_todos "None."
  write_known_issues_registry "03" \
    "$(jq -cn --arg error "$err_one" '{test:"SameTest",file:"Same.swift",error:$error,last_seen_in:"03-01-SUMMARY.md",last_seen_round:1,times_seen:1,source_kind:"registry"}')" \
    "$(jq -cn --arg error "$err_two" '{test:"SameTest",file:"Same.swift",error:$error,last_seen_in:"03-02-SUMMARY.md",last_seen_round:2,times_seen:1,source_kind:"registry"}')"

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"promoted_count=2"* ]]
  [ "$(grep -c '\[KNOWN-ISSUE\] SameTest (Same.swift):' "$TEST_TEMP_DIR/.vbw-planning/STATE.md")" -eq 2 ]
}
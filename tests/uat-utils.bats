#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/phases/03-test-phase"
  mkdir -p "$PHASE_DIR"
  # Source the shared helpers so current_uat and latest_non_source_uat are available
  . "$SCRIPTS_DIR/uat-utils.sh"
}

teardown() {
  teardown_temp_dir
}

@test "current_uat: returns round-dir UAT when layout=round-dir and R{RR}-UAT.md exists" {
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  printf 'stage=reverify\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  touch "$PHASE_DIR/remediation/uat/round-01/R01-UAT.md"

  result=$(current_uat "$PHASE_DIR")
  [[ "$result" == *"remediation/uat/round-01/R01-UAT.md" ]]
}

@test "current_uat: returns phase-root UAT when round-dir UAT does not exist" {
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  printf 'stage=reverify\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  # No R01-UAT.md in the round dir — fall back to phase-root UAT
  touch "$PHASE_DIR/03-UAT.md"

  result=$(current_uat "$PHASE_DIR")
  [[ "$result" == *"03-UAT.md" ]]
  [[ "$result" != *"remediation"* ]]
}

@test "current_uat: returns phase-root UAT when no remediation state file" {
  touch "$PHASE_DIR/03-UAT.md"

  result=$(current_uat "$PHASE_DIR")
  [[ "$result" == *"03-UAT.md" ]]
}

@test "current_uat: returns empty when no UAT files exist" {
  result=$(current_uat "$PHASE_DIR")
  [ -z "$result" ]
}

@test "current_uat: handles trailing slash on phase dir" {
  mkdir -p "$PHASE_DIR/remediation/uat/round-02"
  printf 'stage=reverify\nround=02\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  touch "$PHASE_DIR/remediation/uat/round-02/R02-UAT.md"

  result=$(current_uat "$PHASE_DIR/")
  [[ "$result" == *"remediation/uat/round-02/R02-UAT.md" ]]
}

@test "current_uat: returns phase-root UAT when layout is not round-dir" {
  mkdir -p "$PHASE_DIR/remediation/uat"
  printf 'stage=done\nround=01\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  touch "$PHASE_DIR/03-UAT.md"

  result=$(current_uat "$PHASE_DIR")
  [[ "$result" == *"03-UAT.md" ]]
  [[ "$result" != *"remediation"* ]]
}

@test "current_uat: returns previous round UAT when current round UAT missing" {
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  mkdir -p "$PHASE_DIR/remediation/uat/round-02"
  printf 'stage=research\nround=02\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  touch "$PHASE_DIR/remediation/uat/round-01/R01-UAT.md"

  result=$(current_uat "$PHASE_DIR")
  [[ "$result" == *"remediation/uat/round-01/R01-UAT.md" ]]
}

@test "current_uat: returns highest previous round UAT when multiple exist" {
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  mkdir -p "$PHASE_DIR/remediation/uat/round-02"
  mkdir -p "$PHASE_DIR/remediation/uat/round-03"
  printf 'stage=research\nround=03\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  touch "$PHASE_DIR/remediation/uat/round-01/R01-UAT.md"
  touch "$PHASE_DIR/remediation/uat/round-02/R02-UAT.md"

  result=$(current_uat "$PHASE_DIR")
  [[ "$result" == *"remediation/uat/round-02/R02-UAT.md" ]]
}

@test "current_uat: round-dir round=01 with no UATs returns empty" {
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  printf 'stage=research\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"

  result=$(current_uat "$PHASE_DIR")
  [ -z "$result" ]
}

@test "current_uat: round=02 no previous round UATs falls to phase root" {
  mkdir -p "$PHASE_DIR/remediation/uat/round-02"
  printf 'stage=research\nround=02\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  touch "$PHASE_DIR/03-UAT.md"

  result=$(current_uat "$PHASE_DIR")
  [[ "$result" == *"03-UAT.md" ]]
}

@test "current_uat: legacy remediation state file returns legacy round UAT" {
  mkdir -p "$PHASE_DIR/remediation/round-01"
  printf 'stage=verify\nround=01\nlayout=legacy\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"
  touch "$PHASE_DIR/remediation/round-01/R01-UAT.md"

  result=$(current_uat "$PHASE_DIR")
  [[ "$result" == *"remediation/round-01/R01-UAT.md" ]]
}

@test "current_uat: legacy current round missing falls back to latest legacy round UAT" {
  mkdir -p "$PHASE_DIR/remediation/round-01" "$PHASE_DIR/remediation/round-02"
  printf 'stage=research\nround=02\nlayout=legacy\n' > "$PHASE_DIR/.uat-remediation-stage"
  touch "$PHASE_DIR/remediation/round-01/R01-UAT.md"

  result=$(current_uat "$PHASE_DIR")
  [[ "$result" == *"remediation/round-01/R01-UAT.md" ]]
}

# --- normalize_uat_status tests ---

@test "normalize_uat_status: all_pass maps to complete" {
  result=$(normalize_uat_status "all_pass")
  [ "$result" = "complete" ]
}

@test "normalize_uat_status: passed maps to complete" {
  result=$(normalize_uat_status "passed")
  [ "$result" = "complete" ]
}

@test "normalize_uat_status: pass maps to complete" {
  result=$(normalize_uat_status "pass")
  [ "$result" = "complete" ]
}

@test "normalize_uat_status: all_passed maps to complete" {
  result=$(normalize_uat_status "all_passed")
  [ "$result" = "complete" ]
}

@test "normalize_uat_status: verified maps to complete" {
  result=$(normalize_uat_status "verified")
  [ "$result" = "complete" ]
}

@test "normalize_uat_status: no_issues maps to complete" {
  result=$(normalize_uat_status "no_issues")
  [ "$result" = "complete" ]
}

@test "normalize_uat_status: canonical values pass through unchanged" {
  [ "$(normalize_uat_status "complete")" = "complete" ]
  [ "$(normalize_uat_status "issues_found")" = "issues_found" ]
  [ "$(normalize_uat_status "in_progress")" = "in_progress" ]
  [ "$(normalize_uat_status "pending")" = "pending" ]
}

@test "normalize_uat_status: failed maps to issues_found" {
  result=$(normalize_uat_status "failed")
  [ "$result" = "issues_found" ]
}

@test "normalize_uat_status: empty input returns empty" {
  result=$(normalize_uat_status "")
  [ "$result" = "" ]
}

@test "normalize_uat_status: unknown values pass through unchanged" {
  [ "$(normalize_uat_status "success")" = "success" ]
  [ "$(normalize_uat_status "done")" = "done" ]
  [ "$(normalize_uat_status "aborted")" = "aborted" ]
}

# --- extract_status_value normalization integration ---

@test "extract_status_value: normalizes all_pass in frontmatter to complete" {
  cat > "$PHASE_DIR/03-UAT.md" <<'EOF'
---
phase: 03
status: all_pass
---
All tests passed.
EOF
  result=$(extract_status_value "$PHASE_DIR/03-UAT.md")
  [ "$result" = "complete" ]
}

@test "extract_status_value: normalizes passed in frontmatter to complete" {
  cat > "$PHASE_DIR/03-UAT.md" <<'EOF'
---
phase: 03
status: passed
---
All tests passed.
EOF
  result=$(extract_status_value "$PHASE_DIR/03-UAT.md")
  [ "$result" = "complete" ]
}

@test "extract_status_value: normalizes all_pass in body fallback to complete" {
  cat > "$PHASE_DIR/03-UAT.md" <<'EOF'
# UAT Report
status: all_pass
EOF
  result=$(extract_status_value "$PHASE_DIR/03-UAT.md")
  [ "$result" = "complete" ]
}

@test "extract_status_value: issues_found passes through unchanged" {
  cat > "$PHASE_DIR/03-UAT.md" <<'EOF'
---
phase: 03
status: issues_found
---
Issues found.
EOF
  result=$(extract_status_value "$PHASE_DIR/03-UAT.md")
  [ "$result" = "issues_found" ]
}

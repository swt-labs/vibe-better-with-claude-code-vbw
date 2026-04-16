#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

run_resolver() {
  bash "$SCRIPTS_DIR/resolve-uat-remediation-round-limit.sh" "$@"
}

@test "resolver defaults missing config to unlimited" {
  run run_resolver "$TEST_TEMP_DIR/.vbw-planning/missing.json"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "resolver returns unlimited for absent key in existing config" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced"
}
EOF

  run run_resolver "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "resolver preserves positive integer from new key" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "max_uat_remediation_rounds": 5
}
EOF

  run run_resolver "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]
}

@test "resolver preserves oversized positive integer exactly" {
  local huge_cap="9223372036854775808"

  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<EOF
{
  "max_uat_remediation_rounds": ${huge_cap}
}
EOF

  run run_resolver "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$huge_cap" ]
}

@test "resolver ignores nested new key and preserves oversized top-level new key" {
  local huge_cap="9223372036854775808"

  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<EOF
{
  "nested": {
    "max_uat_remediation_rounds": 7
  },
  "max_uat_remediation_rounds": ${huge_cap}
}
EOF

  run run_resolver "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$huge_cap" ]
}

@test "resolver treats false and zero as unlimited" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "max_uat_remediation_rounds": false
}
EOF

  run run_resolver "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]

  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "max_uat_remediation_rounds": 0
}
EOF

  run run_resolver "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "resolver falls back to legacy positive integer when new key absent" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "max_remediation_rounds": 5
}
EOF

  run run_resolver "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]
}

@test "resolver ignores nested legacy key when top-level legacy key is absent" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "nested": {
    "max_remediation_rounds": 5
  }
}
EOF

  run run_resolver "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "resolver treats malformed persisted values as unlimited" {
  local raw
  for raw in '"oops"' 'true' '-1' '3.5' '{"bad":true}' '[1,2,3]' 'null'; do
    cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<EOF
{
  "max_uat_remediation_rounds": ${raw}
}
EOF

    run run_resolver "$TEST_TEMP_DIR/.vbw-planning/config.json"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
  done
}

@test "resolver lets malformed new key win over valid legacy key by failing open to unlimited" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "max_uat_remediation_rounds": "oops",
  "max_remediation_rounds": 7
}
EOF

  run run_resolver "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "normalize-json emits canonical json literal" {
  run run_resolver --normalize-json false
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run run_resolver --normalize-json 0
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run run_resolver --normalize-json 05
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]

  run run_resolver --normalize-json 9223372036854775808
  [ "$status" -eq 0 ]
  [ "$output" = "9223372036854775808" ]

  run run_resolver --normalize-json '"oops"'
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "validate-input accepts false zero and positive integers" {
  run run_resolver --validate-input false
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run run_resolver --validate-input 0
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run run_resolver --validate-input 007
  [ "$status" -eq 0 ]
  [ "$output" = "7" ]

  run run_resolver --validate-input 9223372036854775808
  [ "$status" -eq 0 ]
  [ "$output" = "9223372036854775808" ]
}

@test "validate-input rejects malformed interactive values" {
  local raw
  for raw in true -1 3.5 bad null unlimited; do
    run run_resolver --validate-input "$raw"
    [ "$status" -eq 1 ]
  done
}

@test "next-round decision reports cap reached for exact finite boundary" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "max_uat_remediation_rounds": 1
}
EOF

  run run_resolver --next-round-decision "$TEST_TEMP_DIR/.vbw-planning/config.json" 01
  [ "$status" -eq 0 ]
  [[ "$output" == *"current_round=01"* ]]
  [[ "$output" == *"next_round=02"* ]]
  [[ "$output" == *"max_rounds=1"* ]]
  [[ "$output" == *"cap_reached=true"* ]]
  [[ "$output" == *"unlimited=false"* ]]
}

@test "next-round decision reports under-cap finite path" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "max_uat_remediation_rounds": 3
}
EOF

  run run_resolver --next-round-decision "$TEST_TEMP_DIR/.vbw-planning/config.json" 01
  [ "$status" -eq 0 ]
  [[ "$output" == *"cap_reached=false"* ]]
  [[ "$output" == *"max_rounds=3"* ]]
}

@test "next-round decision treats unlimited cases as uncapped" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "max_uat_remediation_rounds": false
}
EOF

  run run_resolver --next-round-decision "$TEST_TEMP_DIR/.vbw-planning/config.json" 09
  [ "$status" -eq 0 ]
  [[ "$output" == *"cap_reached=false"* ]]
  [[ "$output" == *"unlimited=true"* ]]
  [[ "$output" == *"max_rounds="* ]]
}

@test "next-round decision falls back to legacy finite cap" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "max_remediation_rounds": 2
}
EOF

  run run_resolver --next-round-decision "$TEST_TEMP_DIR/.vbw-planning/config.json" 01
  [ "$status" -eq 0 ]
  [[ "$output" == *"max_rounds=2"* ]]
  [[ "$output" == *"cap_reached=false"* ]]
}

@test "next-round decision rejects malformed current round input" {
  run run_resolver --next-round-decision "$TEST_TEMP_DIR/.vbw-planning/config.json" round-01
  [ "$status" -eq 1 ]
}
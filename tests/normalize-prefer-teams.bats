#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

run_normalizer() {
  bash "$SCRIPTS_DIR/normalize-prefer-teams.sh" "$@"
}

@test "normalizer defaults missing config to auto" {
  run run_normalizer "$TEST_TEMP_DIR/.vbw-planning/missing.json"
  [ "$status" -eq 0 ]
  [ "$output" = "auto" ]
}

@test "normalizer canonicalizes when_parallel config value to auto" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "prefer_teams": "when_parallel"
}
EOF

  run run_normalizer "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "auto" ]
}

@test "normalizer preserves canonical values" {
  local value
  for value in always auto never; do
    run run_normalizer --value "$value"
    [ "$status" -eq 0 ]
    [ "$output" = "$value" ]
  done
}

@test "normalizer maps boolean-like legacy values" {
  run run_normalizer --value true
  [ "$status" -eq 0 ]
  [ "$output" = "always" ]

  run run_normalizer --value false
  [ "$status" -eq 0 ]
  [ "$output" = "auto" ]
}
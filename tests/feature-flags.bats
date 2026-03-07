#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "graduated flags absent from defaults.json" {
  # Only truly graduated flags should be absent from defaults.json
  run jq -r 'has("v2_hard_contracts") or has("v2_hard_gates") or has("v2_typed_protocol") or has("v2_role_isolation") or has("v3_event_log") or has("v3_delta_context") or has("v3_context_cache") or has("v3_plan_research_persist") or has("v3_schema_validation") or has("v3_contract_lite") or has("v3_lock_lite")' "$CONFIG_DIR/defaults.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "configurable flags present in defaults.json under unprefixed names" {
  # Restored flags should be in defaults.json under new unprefixed names
  run jq -r 'has("token_budgets") and has("two_phase_completion") and has("metrics") and has("smart_routing") and has("validation_gates") and has("snapshot_resume") and has("lease_locks") and has("event_recovery") and has("monorepo_routing")' "$CONFIG_DIR/defaults.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "old prefixed flag names absent from defaults.json" {
  # Old v2_/v3_ prefixed names should NOT be in defaults.json
  run jq -r 'has("v2_token_budgets") or has("v2_two_phase_completion") or has("v3_metrics") or has("v3_smart_routing") or has("v3_validation_gates") or has("v3_snapshot_resume") or has("v3_lease_locks") or has("v3_event_recovery") or has("v3_monorepo_routing")' "$CONFIG_DIR/defaults.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "configurable flags present in test config" {
  # Verify unprefixed flag names are present in test config
  run jq -r 'has("token_budgets") and has("two_phase_completion") and has("metrics")' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "config flags can be toggled via jq" {
  # Test with a still-live flag (context_compiler)
  jq '.context_compiler = false' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.tmp" && mv "$TEST_TEMP_DIR/.vbw-planning/config.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run jq -r '.context_compiler' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

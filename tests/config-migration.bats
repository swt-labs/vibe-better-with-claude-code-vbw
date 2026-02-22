#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# Helper: Run the shared migration script
run_migration() {
  bash "$SCRIPTS_DIR/migrate-config.sh" "$TEST_TEMP_DIR/.vbw-planning/config.json"
}

@test "migration handles empty config" {
  # Create config with only non-flag keys
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "autonomy": "standard"
}
EOF

  run_migration

  # Verify graduated flags are NOT present (prefixed names stripped)
  run jq -r 'has("v3_delta_context") or has("v3_context_cache") or has("v3_plan_research_persist") or has("v3_event_log") or has("v3_schema_validation")' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  # Verify still-live flags are present
  run jq '[
    has("context_compiler"),
    has("model_overrides"), has("prefer_teams")
  ] | map(select(.)) | length' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]

  # Verify context_compiler defaults to true
  run jq -r '.context_compiler' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "migration handles partial config" {
  # Create config with some flags present
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "context_compiler": false,
  "v3_delta_context": true,
  "v2_hard_contracts": true
}
EOF

  run_migration

  # Verify still-live flags are present
  run jq '[
    has("context_compiler"),
    has("model_overrides"), has("prefer_teams")
  ] | map(select(.)) | length' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]

  # Verify all defaults.json keys are present (34 defaults keys)
  run jq 'keys | length' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "34" ]

  # Verify existing values were preserved
  run jq -r '.context_compiler' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  # Graduated flags should be stripped by migration
  run jq -r 'has("v3_delta_context")' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run jq -r 'has("v2_hard_contracts")' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "migration handles full config" {
  # Create config with all flags present
  create_test_config

  # Record normalized content
  BEFORE=$(jq -S . "$TEST_TEMP_DIR/.vbw-planning/config.json")

  run_migration

  # Verify no changes (idempotent when all flags present)
  AFTER=$(jq -S . "$TEST_TEMP_DIR/.vbw-planning/config.json")
  [ "$BEFORE" = "$AFTER" ]
}

@test "migration is idempotent" {
  # Start with empty config
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced"
}
EOF

  # Run migration once
  run_migration
  AFTER_FIRST=$(cat "$TEST_TEMP_DIR/.vbw-planning/config.json")

  # Run migration again
  run_migration
  AFTER_SECOND=$(cat "$TEST_TEMP_DIR/.vbw-planning/config.json")

  # Both runs should produce identical result
  [ "$AFTER_FIRST" = "$AFTER_SECOND" ]

  # Verify flag count is correct (34 total, graduated flags removed)
  run jq 'keys | length' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "34" ]
}

@test "migration detects malformed JSON" {
  # Create malformed JSON
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  invalid json here
}
EOF

  # Migration should fail gracefully
  run run_migration
  [ "$status" -ne 0 ]

  # Temp file should be cleaned up (tested implicitly by not checking for it)
}

@test "EXPECTED_FLAG_COUNT matches defaults.json" {
  # Count all keys in defaults.json (these are the keys migrate-config adds to a fresh config)
  DEFAULTS_COUNT=$(jq 'keys | length' "$CONFIG_DIR/defaults.json")

  # Extract EXPECTED_FLAG_COUNT from session-start.sh
  SCRIPT_COUNT=$(grep 'EXPECTED_FLAG_COUNT=' "$SCRIPTS_DIR/session-start.sh" | grep -oE '[0-9]+' | head -1)

  # Debug output for test failure
  if [ "$DEFAULTS_COUNT" != "$SCRIPT_COUNT" ]; then
    echo "MISMATCH: defaults.json has $DEFAULTS_COUNT keys, session-start.sh expects $SCRIPT_COUNT"
  fi

  [ "$DEFAULTS_COUNT" = "$SCRIPT_COUNT" ]
}

@test "migration adds missing prefer_teams with default value" {
  # Create config without prefer_teams
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "autonomy": "standard"
}
EOF

  run_migration

  # Verify prefer_teams was added with "always" default
  run jq -r '.prefer_teams' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "always" ]
}

@test "migration adds planning_tracking and auto_push defaults" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced"
}
EOF

  run_migration

  run jq -r '.planning_tracking' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "manual" ]

  run jq -r '.auto_push' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "never" ]
}

@test "migration preserves existing planning_tracking and auto_push values" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "planning_tracking": "commit",
  "auto_push": "after_phase"
}
EOF

  run_migration

  run jq -r '.planning_tracking' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "commit" ]

  run jq -r '.auto_push' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "after_phase" ]
}

@test "migration preserves existing prefer_teams value" {
  # Create config with prefer_teams set to "never"
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "prefer_teams": "never"
}
EOF

  run_migration

  # Verify prefer_teams value was NOT overwritten
  run jq -r '.prefer_teams' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "never" ]
}

@test "migration adds missing agent_max_turns defaults" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced"
}
EOF

  run_migration

  run jq -r '.agent_max_turns.scout' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "15" ]

  run jq -r '.agent_max_turns.debugger' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "80" ]
}

@test "migration preserves existing agent_max_turns values" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "agent_max_turns": {
    "debugger": 120,
    "dev": 90
  }
}
EOF

  run_migration

  run jq -r '.agent_max_turns.debugger' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "120" ]

  run jq -r '.agent_max_turns.dev' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "90" ]
}

@test "migration renames agent_teams to prefer_teams and removes stale key" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "agent_teams": true
}
EOF

  run_migration

  run jq -r '.prefer_teams' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "always" ]

  run jq -r 'has("agent_teams")' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "migration removes stale agent_teams when prefer_teams already exists" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "prefer_teams": "when_parallel",
  "agent_teams": false
}
EOF

  run_migration

  run jq -r '.prefer_teams' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "when_parallel" ]

  run jq -r 'has("agent_teams")' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "migration maps agent_teams false to prefer_teams auto" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "agent_teams": false
}
EOF

  run_migration

  run jq -r '.prefer_teams' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "auto" ]
}

@test "migration backfills all missing defaults keys" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced"
}
EOF

  run jq -s '.[0] as $d | .[1] as $c | [$d | keys[] | select($c[.] == null)] | length' "$CONFIG_DIR/defaults.json" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  BEFORE_MISSING="$output"
  [ "$BEFORE_MISSING" -gt 0 ]

  run_migration

  run jq -s '.[0] as $d | .[1] as $c | [$d | keys[] | select($c[.] == null)] | length' "$CONFIG_DIR/defaults.json" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "migration --print-added returns number of inserted defaults" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced"
}
EOF

  run jq -s '.[0] as $d | .[1] as $c | [$d | keys[] | select($c[.] == null)] | length' "$CONFIG_DIR/defaults.json" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  EXPECTED_ADDED="$output"

  run bash "$SCRIPTS_DIR/migrate-config.sh" --print-added "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$EXPECTED_ADDED" ]
}

@test "EXPECTED_FLAG_COUNT is 34 after partial flag restoration" {
  # Verify session-start.sh has EXPECTED_FLAG_COUNT=34
  SCRIPT_COUNT=$(grep 'EXPECTED_FLAG_COUNT=' "$SCRIPTS_DIR/session-start.sh" | grep -oE '[0-9]+' | head -1)
  [ "$SCRIPT_COUNT" = "34" ]
}

@test "migration strips all graduated V2/V3 flags from brownfield config" {
  # Create config with every graduated flag present
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "v3_delta_context": true,
  "v3_context_cache": false,
  "v3_plan_research_persist": true,
  "v3_contract_lite": true,
  "v3_lock_lite": false,
  "v3_event_log": true,
  "v3_schema_validation": false,
  "v2_hard_contracts": true,
  "v2_hard_gates": false,
  "v2_typed_protocol": true,
  "v2_role_isolation": false,
  "v3_metrics": false,
  "v3_smart_routing": true,
  "v3_validation_gates": false,
  "v3_snapshot_resume": true,
  "v3_lease_locks": false,
  "v3_event_recovery": true,
  "v3_monorepo_routing": false,
  "v2_two_phase_completion": true,
  "v2_token_budgets": false
}
EOF

  run_migration

  # All v2_/v3_ prefixed flags should be removed (graduated or renamed)
  run jq '[keys[] | select(startswith("v2_") or startswith("v3_"))] | length' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  # Non-graduated keys should still be present
  run jq -r '.effort' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "balanced" ]

  # Renamed flags should preserve prior values under new names
  run jq -r '.metrics' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run jq -r '.smart_routing' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.two_phase_completion' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.token_budgets' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "migration keeps new flag value when legacy and new keys disagree" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "monorepo_routing": true,
  "v3_monorepo_routing": false
}
EOF

  run_migration

  run jq -r '.monorepo_routing' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r 'has("v3_monorepo_routing")' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "migration keeps unprefixed value and removes legacy key for all renamed flag pairs" {
  local mappings=(
    "v2_token_budgets token_budgets"
    "v2_two_phase_completion two_phase_completion"
    "v3_metrics metrics"
    "v3_smart_routing smart_routing"
    "v3_validation_gates validation_gates"
    "v3_snapshot_resume snapshot_resume"
    "v3_lease_locks lease_locks"
    "v3_event_recovery event_recovery"
    "v3_monorepo_routing monorepo_routing"
    "v3_rolling_summary rolling_summary"
  )

  local legacy_key new_key
  for mapping in "${mappings[@]}"; do
    read -r legacy_key new_key <<< "$mapping"

    cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<EOF
{
  "effort": "balanced",
  "${new_key}": false,
  "${legacy_key}": true
}
EOF

    run_migration

    run jq -r --arg k "$new_key" '.[$k]' "$TEST_TEMP_DIR/.vbw-planning/config.json"
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]

    run jq -r --arg k "$legacy_key" 'has($k)' "$TEST_TEMP_DIR/.vbw-planning/config.json"
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
  done
}

@test "migration defaults worktree_isolation to off for brownfield configs" {
  # Simulate older initialized repo config with no worktree_isolation key.
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "autonomy": "standard",
  "v3_metrics": true
}
EOF

  run_migration

  run jq -r '.worktree_isolation' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "off" ]
}

#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
  rm -f /tmp/vbw-model-* 2>/dev/null
}

@test "resolves dev model from quality profile" {
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "opus" ]
}

@test "resolves scout model from quality profile" {
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" scout "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}

@test "resolves dev model from balanced profile" {
  jq '.model_profile = "balanced"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}

@test "respects per-agent override" {
  jq '.model_overrides.dev = "opus"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "opus" ]
}

@test "rejects invalid agent name" {
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" invalid "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 1 ]
}

@test "rejects missing config file" {
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "/nonexistent/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 1 ]
}

@test "uses cache on second call" {
  # First call populates cache
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "opus" ]

  # Verify cache file exists
  MTIME=$(stat -c %Y "$TEST_TEMP_DIR/.vbw-planning/config.json" 2>/dev/null || stat -f %m "$TEST_TEMP_DIR/.vbw-planning/config.json" 2>/dev/null)
  [ -f "/tmp/vbw-model-dev-${MTIME}" ]
}

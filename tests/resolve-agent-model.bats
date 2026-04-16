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
  PROFILES_MTIME=$(stat -c %Y "$CONFIG_DIR/model-profiles.json" 2>/dev/null || stat -f %m "$CONFIG_DIR/model-profiles.json" 2>/dev/null)
  CACHE_HASH=$(vbw_hash_path "$TEST_TEMP_DIR/.vbw-planning/config.json|$CONFIG_DIR/model-profiles.json")
  [ -f "/tmp/vbw-model-dev-${MTIME}-${PROFILES_MTIME}-${CACHE_HASH}" ]
}

@test "cache is isolated by config path even when mtimes match" {
  local alt_dir="$TEST_TEMP_DIR-alt"
  mkdir -p "$alt_dir/.vbw-planning"
  cp "$TEST_TEMP_DIR/.vbw-planning/config.json" "$alt_dir/.vbw-planning/config.json"

  jq '.model_profile = "balanced"' "$alt_dir/.vbw-planning/config.json" > "$alt_dir/.vbw-planning/config.json.tmp"
  mv "$alt_dir/.vbw-planning/config.json.tmp" "$alt_dir/.vbw-planning/config.json"

  touch -t 202601010101 "$TEST_TEMP_DIR/.vbw-planning/config.json" "$alt_dir/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "opus" ]

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$alt_dir/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}

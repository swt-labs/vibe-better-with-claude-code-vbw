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

  # Verify cache file exists — use the same hash priority as the script:
  # md5sum (Linux) → md5 (macOS) → cksum (fallback)
  _fingerprint() {
    if command -v md5sum >/dev/null 2>&1; then
      md5sum "$1" | awk '{print $1}' | cut -c1-8
    elif command -v md5 >/dev/null 2>&1; then
      md5 -q "$1" | cut -c1-8
    else
      cksum "$1" | awk '{print $1}'
    fi
  }
  CONFIG_HASH=$(_fingerprint "$TEST_TEMP_DIR/.vbw-planning/config.json")
  PROFILES_HASH=$(_fingerprint "$CONFIG_DIR/model-profiles.json")
  PATH_HASH=$(vbw_hash_path "$TEST_TEMP_DIR/.vbw-planning/config.json|$CONFIG_DIR/model-profiles.json")
  [ -f "/tmp/vbw-model-dev-${PATH_HASH}-${CONFIG_HASH}-${PROFILES_HASH}" ]
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

@test "cache invalidates for same-path config edits within the same second" {
  touch -t 202601010101 "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "opus" ]

  jq '.model_profile = "balanced"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  touch -t 202601010101 "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}

@test "cache invalidates when profiles file changes within the same second" {
  local profiles_copy="$TEST_TEMP_DIR/model-profiles.json"
  cp "$CONFIG_DIR/model-profiles.json" "$profiles_copy"
  touch -t 202601010101 "$profiles_copy"

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$profiles_copy"
  [ "$status" -eq 0 ]
  [ "$output" = "opus" ]

  jq '.quality.dev = "sonnet"' "$profiles_copy" > "$profiles_copy.tmp"
  mv "$profiles_copy.tmp" "$profiles_copy"
  touch -t 202601010101 "$profiles_copy"

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$profiles_copy"
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}

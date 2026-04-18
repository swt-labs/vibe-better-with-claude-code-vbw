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

@test "resolve-agent-settings emits shell-safe assignments for model and max turns" {
  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json" turbo
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_AGENT='dev'"* ]]
  [[ "$output" == *"RESOLVED_MODEL='opus'"* ]]
  [[ "$output" == *"RESOLVED_EFFORT='turbo'"* ]]

  eval "$output"
  [ "$RESOLVED_AGENT" = "dev" ]
  [ "$RESOLVED_MODEL" = "opus" ]
  [ "$RESOLVED_MAX_TURNS" = "45" ]
  [ "$RESOLVED_EFFORT" = "turbo" ]
}

@test "resolve-agent-settings falls back to config effort when explicit effort omitted" {
  jq '.effort = "thorough"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" qa "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]

  eval "$output"
  [ "$RESOLVED_MODEL" = "sonnet" ]
  [ "$RESOLVED_MAX_TURNS" = "38" ]
  [ "$RESOLVED_EFFORT" = "thorough" ]
}

@test "resolve-agent-settings normalizes legacy effort aliases" {
  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" debugger "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json" high
  [ "$status" -eq 0 ]

  eval "$output"
  [ "$RESOLVED_MODEL" = "opus" ]
  [ "$RESOLVED_MAX_TURNS" = "120" ]
  [ "$RESOLVED_EFFORT" = "thorough" ]
}

@test "resolve-agent-settings preserves disabled max-turn budgets as empty output" {
  jq '.agent_max_turns.dev = false' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json" turbo
  [ "$status" -eq 0 ]

  eval "$output"
  [ "$RESOLVED_MODEL" = "opus" ]
  [ "$RESOLVED_MAX_TURNS" = "" ]
}

@test "resolve-agent-settings rejects invalid agent names" {
  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" invalid "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json" balanced
  [ "$status" -eq 1 ]
}

@test "resolve-agent-settings surfaces model resolver errors" {
  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" dev "$TEST_TEMP_DIR/.vbw-planning/missing.json" "$CONFIG_DIR/model-profiles.json" balanced
  [ "$status" -eq 1 ]
  [[ "$output" == *"Config not found at $TEST_TEMP_DIR/.vbw-planning/missing.json"* ]]
}

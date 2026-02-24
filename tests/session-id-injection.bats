#!/usr/bin/env bats

load test_helper

# session-start.sh — session_id extraction from hook stdin JSON
# Verifies that session_id is captured and written to CLAUDE_ENV_FILE

@test "session-start: extracts session_id from stdin JSON and writes to CLAUDE_ENV_FILE" {
  setup_temp_dir
  create_test_config

  local env_file="$TEST_TEMP_DIR/.claude-env"
  : > "$env_file"

  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"session_id\":\"abc-123-def\"}' | CLAUDE_ENV_FILE='$env_file' bash '$SCRIPTS_DIR/session-start.sh'"
  [ "$status" -eq 0 ]
  grep -q '^export CLAUDE_SESSION_ID="abc-123-def"$' "$env_file"
  teardown_temp_dir
}

@test "session-start: does not duplicate session_id if already in CLAUDE_ENV_FILE" {
  setup_temp_dir
  create_test_config

  local env_file="$TEST_TEMP_DIR/.claude-env"
  echo 'export CLAUDE_SESSION_ID="existing-id"' > "$env_file"

  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"session_id\":\"new-id\"}' | CLAUDE_ENV_FILE='$env_file' bash '$SCRIPTS_DIR/session-start.sh'"
  [ "$status" -eq 0 ]
  # Should still have original, not new
  grep -q 'existing-id' "$env_file"
  # Should not have duplicate entries
  local count
  count=$(grep -c 'CLAUDE_SESSION_ID' "$env_file")
  [ "$count" -eq 1 ]
  teardown_temp_dir
}

@test "session-start: skips env injection when CLAUDE_ENV_FILE is unset" {
  setup_temp_dir
  create_test_config

  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"session_id\":\"abc-123\"}' | env -u CLAUDE_ENV_FILE bash '$SCRIPTS_DIR/session-start.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "session-start: handles stdin with no session_id field" {
  setup_temp_dir
  create_test_config

  local env_file="$TEST_TEMP_DIR/.claude-env"
  : > "$env_file"

  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"other_field\":\"value\"}' | CLAUDE_ENV_FILE='$env_file' bash '$SCRIPTS_DIR/session-start.sh'"
  [ "$status" -eq 0 ]
  # Should not write anything to env file
  ! grep -q 'CLAUDE_SESSION_ID' "$env_file"
  teardown_temp_dir
}

@test "session-start: handles empty stdin gracefully" {
  setup_temp_dir
  create_test_config

  local env_file="$TEST_TEMP_DIR/.claude-env"
  : > "$env_file"

  run bash -c "cd '$TEST_TEMP_DIR' && echo '' | CLAUDE_ENV_FILE='$env_file' bash '$SCRIPTS_DIR/session-start.sh'"
  [ "$status" -eq 0 ]
  ! grep -q 'CLAUDE_SESSION_ID' "$env_file"
  teardown_temp_dir
}

@test "session-start: handles UUID-format session_id" {
  setup_temp_dir
  create_test_config

  local env_file="$TEST_TEMP_DIR/.claude-env"
  : > "$env_file"

  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"session_id\":\"a4b692e2-8f3a-4c71-b5d1-9e2f8a3c6d4e\"}' | CLAUDE_ENV_FILE='$env_file' bash '$SCRIPTS_DIR/session-start.sh'"
  [ "$status" -eq 0 ]
  grep -q '^export CLAUDE_SESSION_ID="a4b692e2-8f3a-4c71-b5d1-9e2f8a3c6d4e"$' "$env_file"
  teardown_temp_dir
}

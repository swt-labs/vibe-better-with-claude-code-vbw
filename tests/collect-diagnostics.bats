#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/.claude"
  mkdir -p "$CLAUDE_CONFIG_DIR/debug"
  mkdir -p "$CLAUDE_CONFIG_DIR/plugins/cache/vbw-marketplace/vbw"
}

teardown() {
  unset CLAUDE_CONFIG_DIR
  unset CLAUDE_SESSION_ID
  unset CLAUDE_PLUGIN_ROOT
  teardown_temp_dir
}

run_collector() {
  run bash "$SCRIPTS_DIR/collect-diagnostics.sh" "$PROJECT_ROOT" "$TEST_TEMP_DIR"
}

# --- Invariant: always exits 0 ---

@test "collect-diagnostics: exits 0 with no project artifacts" {
  rm -rf "$TEST_TEMP_DIR/.vbw-planning"
  run_collector
  [ "$status" -eq 0 ]
}

@test "collect-diagnostics: exits 0 with full project artifacts" {
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.events"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.metrics"
  echo '{"ts":"2025-01-01"}' > "$TEST_TEMP_DIR/.vbw-planning/.session-log.jsonl"
  echo '{"event":"test"}' > "$TEST_TEMP_DIR/.vbw-planning/.events/event-log.jsonl"
  echo '{"metric":"test"}' > "$TEST_TEMP_DIR/.vbw-planning/.metrics/run-metrics.jsonl"
  echo '{"profile":"balanced"}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  printf '# STATE\nphase: 01\n' > "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  run_collector
  [ "$status" -eq 0 ]
}

# --- Redaction ---

@test "collect-diagnostics: redacts home directory paths" {
  run_collector
  [[ "$output" != *"$HOME"* ]] || [[ "$HOME" == "$TEST_TEMP_DIR" ]]
}

@test "collect-diagnostics: redacts API key patterns" {
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo '{"api_key":"sk-abcdefghij1234567890abcdefghij"}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run_collector
  [ "$status" -eq 0 ]
  [[ "$output" != *"sk-abcdefghij1234567890abcdefghij"* ]]
}

# --- New section: Debug Log Summary ---

@test "collect-diagnostics: includes Debug Log Summary section" {
  run_collector
  [[ "$output" == *"--- Debug Log Summary ---"* ]]
}

@test "collect-diagnostics: debug log summary shows not found when no debug log" {
  run_collector
  [[ "$output" == *"debug_log: not found"* ]]
}

@test "collect-diagnostics: debug log summary parses hook counts from fixture" {
  # Create a fake debug log
  cat > "$CLAUDE_CONFIG_DIR/debug/test-session.txt" <<'EOF'
[DEBUG] Getting matching hook commands for PreToolUse with query: Bash
[DEBUG] Matched 2 unique hooks for PreToolUse
[DEBUG] Hook vbw-hook success: {"result":"ok"}
[DEBUG] Getting matching hook commands for PostToolUse with query: Bash
[DEBUG] Hook vbw-hook2 success: {"result":"ok"}
[DEBUG] Loading hooks from plugin: /path/to/vbw
[DEBUG] Registered 21 hooks from vbw
EOF
  ln -sf "$CLAUDE_CONFIG_DIR/debug/test-session.txt" "$CLAUDE_CONFIG_DIR/debug/latest"
  run_collector
  [ "$status" -eq 0 ]
  [[ "$output" == *"hook_lookups: 2"* ]]
  [[ "$output" == *"hook_successes: 2"* ]]
  [[ "$output" == *"hook_error_lines: 0"* ]]
  [[ "$output" == *"plugin_loading_lines:"* ]]
}

# --- New section: Session Artifacts ---

@test "collect-diagnostics: includes Session Artifacts section" {
  run_collector
  [[ "$output" == *"--- Session Artifacts ---"* ]]
}

@test "collect-diagnostics: shows session_id unset when not set" {
  unset CLAUDE_SESSION_ID 2>/dev/null || true
  run_collector
  [[ "$output" == *"session_id: (unset)"* ]]
}

@test "collect-diagnostics: shows session_id when set" {
  export CLAUDE_SESSION_ID="test-session-123"
  run_collector
  [[ "$output" == *"session_id: test-session-123"* ]]
}

@test "collect-diagnostics: shows session link existence" {
  run_collector
  [[ "$output" == *"session_link_exists:"* ]]
}

@test "collect-diagnostics: shows hook_resolution" {
  run_collector
  [[ "$output" == *"hook_resolution:"* ]]
}

@test "collect-diagnostics: shows welcome_marker status" {
  run_collector
  [[ "$output" == *"welcome_marker:"* ]]
}

@test "collect-diagnostics: shows config_cache and update_cache status" {
  run_collector
  [[ "$output" == *"config_cache_exists:"* ]]
  [[ "$output" == *"update_cache_exists:"* ]]
}

# --- New section: Marketplace Status ---

@test "collect-diagnostics: includes Marketplace Status section" {
  run_collector
  [[ "$output" == *"--- Marketplace Status ---"* ]]
}

@test "collect-diagnostics: shows cache_root_exists" {
  run_collector
  [[ "$output" == *"cache_root_exists:"* ]]
}

@test "collect-diagnostics: shows local_link status" {
  run_collector
  [[ "$output" == *"local_link:"* ]]
}

@test "collect-diagnostics: detects marketplace registry with jq" {
  if ! command -v jq >/dev/null 2>&1; then
    skip "jq not available"
  fi
  echo '{"plugins":{"vbw@vbw-marketplace":[{"scope":"user"}]}}' > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  run_collector
  [ "$status" -eq 0 ]
  [[ "$output" == *"registry_entry: vbw@vbw-marketplace"* ]]
}

# --- Graceful degradation ---

@test "collect-diagnostics: degrades gracefully with missing optional files" {
  rm -rf "$TEST_TEMP_DIR/.vbw-planning"
  rm -rf "$CLAUDE_CONFIG_DIR/debug"
  run_collector
  [ "$status" -eq 0 ]
  [[ "$output" == *"Debug Log Summary"* ]]
  [[ "$output" == *"Session Artifacts"* ]]
  [[ "$output" == *"Marketplace Status"* ]]
  [[ "$output" == *"Doctor Checks"* ]]
}

#!/usr/bin/env bats

load test_helper

# --- Task 1: Heredoc commit validation ---

@test "heredoc commit validation extracts correct message" {
  INPUT='{"tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\nfeat(core): add heredoc feature\n\nCo-Authored-By: Test\nEOF\n)\""}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  [ "$status" -eq 0 ]
  # Should NOT contain "does not match format" since feat(core): is valid
  [[ "$output" != *"does not match format"* ]]
}

@test "heredoc commit does not get overwritten by -m extraction" {
  # Heredoc with valid format followed by -m with invalid format
  # If heredoc is correctly prioritized, it should use the heredoc message
  INPUT='{"tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\nfeat(test): valid heredoc\nEOF\n)\""}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"does not match format"* ]]
}

@test "invalid heredoc commit is flagged" {
  # Build input with actual newlines in the heredoc body
  local input
  input=$(printf '{"tool_input":{"command":"git commit -m \\"$(cat <<EOF)\\"\\nbad commit no type\\nEOF"}}')
  run bash -c "printf '%s' '$input' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "does not match format"
}

# --- Task 4: Stack detection expansion ---

@test "detect-stack finds Rust via Cargo.toml" {
  local tmpdir
  tmpdir=$(mktemp -d)
  touch "$tmpdir/Cargo.toml"
  run bash "$SCRIPTS_DIR/detect-stack.sh" "$tmpdir"
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.detected_stack | index("rust")' >/dev/null
}

@test "detect-stack finds Go via go.mod" {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo "module example.com/test" > "$tmpdir/go.mod"
  run bash "$SCRIPTS_DIR/detect-stack.sh" "$tmpdir"
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.detected_stack | index("go")' >/dev/null
}

@test "detect-stack finds Python via pyproject.toml" {
  local tmpdir
  tmpdir=$(mktemp -d)
  touch "$tmpdir/pyproject.toml"
  run bash "$SCRIPTS_DIR/detect-stack.sh" "$tmpdir"
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.detected_stack | index("python")' >/dev/null
}

# --- Task 5: Security filter hardening ---

@test "security-filter allows .vbw-planning/ write when VBW marker present" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.vbw-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "security-filter blocks .env file access" {
  INPUT='{"tool_input":{"file_path":".env"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "sensitive file"
}

# --- Directory pattern path-component anchoring (issue #402) ---

@test "security-filter blocks build/ as path component (relative)" {
  INPUT='{"tool_input":{"file_path":"build/output.js"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
}

@test "security-filter blocks build/ as path component (absolute)" {
  INPUT='{"tool_input":{"file_path":"/home/user/project/build/output.js"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
}

@test "security-filter blocks dist/ as path component" {
  INPUT='{"tool_input":{"file_path":"dist/bundle.js"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
}

@test "security-filter blocks node_modules/ as path component" {
  INPUT='{"tool_input":{"file_path":"node_modules/lodash/index.js"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
}

@test "security-filter blocks .git/ as path component" {
  INPUT='{"tool_input":{"file_path":".git/config"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
}

@test "security-filter allows file when parent dir contains build substring" {
  INPUT='{"tool_input":{"file_path":"/home/user/corvex-build/src/app.js"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
}

@test "security-filter allows file named build-something" {
  INPUT='{"tool_input":{"file_path":"build-orbstack.sh"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
}

@test "security-filter allows file when parent dir contains dist substring" {
  INPUT='{"tool_input":{"file_path":"/home/user/redistribution/src/main.js"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
}

@test "security-filter allows file when parent dir contains node_modules substring" {
  INPUT='{"tool_input":{"file_path":"/home/user/my-node_modules-archive/readme.md"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
}

# --- Task 3: Session config cache ---

@test "session config cache file is written at session start" {
  setup_temp_dir
  create_test_config
  CACHE_FILE="$TEST_TEMP_DIR/vbw-config-cache"
  rm -f "$CACHE_FILE" 2>/dev/null
  run env VBW_CONFIG_CACHE="$CACHE_FILE" bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/session-start.sh'"
  [ -f "$CACHE_FILE" ]
  grep -q "VBW_EFFORT=" "$CACHE_FILE"
  grep -q "VBW_AUTONOMY=" "$CACHE_FILE"
  teardown_temp_dir
}

# --- Task 2: zsh glob guard ---

@test "file-guard exits 0 when no plan files exist" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases"
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/src/index.ts"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

# --- Isolation marker lifecycle (fix/isolation-marker-lifecycle) ---

@test "security-filter allows write with only .vbw-session (no .active-agent)" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  # No .active-agent
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.vbw-planning/milestones/default/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "security-filter resolves markers from FILE_PATH project root" {
  setup_temp_dir
  local REPO_A="$TEST_TEMP_DIR/repo-a"
  local REPO_B="$TEST_TEMP_DIR/repo-b"
  mkdir -p "$REPO_A/.vbw-planning" "$REPO_B/.vbw-planning"
  touch "$REPO_A/.vbw-planning/.gsd-isolation"
  # Repo A has no markers — would block if CWD-based
  # Repo B has .gsd-isolation AND .vbw-session — should allow
  touch "$REPO_B/.vbw-planning/.gsd-isolation"
  echo "session" > "$REPO_B/.vbw-planning/.vbw-session"
  INPUT='{"tool_input":{"file_path":"'"$REPO_B"'/.vbw-planning/STATE.md"}}'
  run bash -c "cd '$REPO_A' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "security-filter allows .vbw-planning write even without markers (self-blocking removed)" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  # No .active-agent, no .vbw-session — still allowed since v1.21.13
  # Self-blocking caused false blocks (orchestrator after team deletion, agents before markers set)
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.vbw-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "agent-start handles vbw: prefixed agent_type" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{"agent_type":"vbw:vbw-scout"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "scout" ]
  teardown_temp_dir
}

@test "agent-start prefers native agent_type over conflicting legacy aliases" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{"agent_type":"vbw-dev","agent_name":"team-lead"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "dev" ]
  teardown_temp_dir
}

@test "agent-start falls back to legacy name when native fields are absent" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{"name":"vbw-qa"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "qa" ]
  teardown_temp_dir
}

@test "agent-start falls back to legacy agentName when native fields are absent" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{"agentName":"vbw-docs"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "docs" ]
  teardown_temp_dir
}

@test "agent-start ignores non-VBW agent_type payloads" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{"agent_type":"helper-agent"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-start ignores bare native agent_type even inside a VBW session" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  INPUT='{"agent_type":"dev","name":"dev-01"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-start falls back to explicit legacy name when native agent_type is non-VBW" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{"agent_type":"dev","agent_name":"vbw-dev-01"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "dev" ]
  teardown_temp_dir
}

@test "agent-start creates count file for reference counting" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  # Start two agents
  echo '{"agent_type":"vbw-scout"}' | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  echo '{"agent_type":"vbw-lead"}' | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "2" ]
  teardown_temp_dir
}

@test "agent-stop decrements count and preserves marker when agents remain" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "lead" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "2" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  # Marker should still exist (one agent remaining)
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  teardown_temp_dir
}

@test "agent-stop removes marker when last agent stops" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  # Both marker and count should be gone
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "prompt-preflight creates .vbw-session for expanded command content" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  # Simulate expanded slash command with YAML frontmatter containing name: vbw:vibe
  INPUT='{"prompt":"---\nname: vbw:vibe\ndescription: Main entry point\n---\n# VBW Vibe\nPlan mode..."}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]
  teardown_temp_dir
}

@test "prompt-preflight does NOT delete .vbw-session on plain text follow-up" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  # Plain text follow-up (e.g., user answering a question)
  INPUT='{"prompt":"yes, go ahead"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  # Marker should still exist
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]
  teardown_temp_dir
}

@test "prompt-preflight preserves .vbw-session on non-VBW slash command" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  # Non-VBW slash command — marker persists since v1.21.13
  # Removal caused false blocks when users sent follow-up messages
  INPUT='{"prompt":"/gsd:status"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  # Marker should still exist (removal handled by session-stop.sh)
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]
  teardown_temp_dir
}

@test "prompt-preflight does NOT create .vbw-session from plain text containing name: vbw:" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  INPUT='{"prompt":"Please explain this YAML fragment: name: vbw:vibe"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]
  teardown_temp_dir
}

@test "agent-start does nothing when agent fields are missing" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-start resets non-numeric count and increments safely" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "abc" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  INPUT='{"agent_type":"vbw-scout"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "scout" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  teardown_temp_dir
}

@test "agent-start accepts team-lead alias when VBW session marker exists" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  INPUT='{"agent_name":"team-lead"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "lead" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  teardown_temp_dir
}

@test "agent-start ignores team-lead alias without VBW context markers" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{"agent_name":"team-lead"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop cleans up when count is non-numeric" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "abc" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop ignores bare native agent_type even inside a VBW session" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  echo "dev" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"agent_type\":\"dev\"}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop falls back to explicit legacy name when native agent_type is non-VBW" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "dev" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  INPUT='{"agent_type":"helper-agent","agent_name":"vbw-dev-01"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop falls back to explicit legacy agentName when native agent_type is non-VBW" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "dev" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  INPUT='{"agent_type":"helper-agent","agentName":"vbw-dev-01"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop two sequential stops from count=2 fully clean up markers" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "2" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  # First stop: 2 -> 1, marker preserved
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  # Second stop: 1 -> 0, full cleanup
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "security-filter resolves .planning marker checks from FILE_PATH root" {
  setup_temp_dir
  local REPO_A="$TEST_TEMP_DIR/repo-a"
  local REPO_B="$TEST_TEMP_DIR/repo-b"
  mkdir -p "$REPO_A/.vbw-planning" "$REPO_B/.planning" "$REPO_B/.vbw-planning"
  touch "$REPO_A/.vbw-planning/.active-agent"
  INPUT='{"tool_input":{"file_path":"'"$REPO_B"'/.planning/STATE.md"}}'
  run bash -c "cd '$REPO_A' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "security-filter blocks .planning write when target repo has active marker" {
  setup_temp_dir
  local REPO_A="$TEST_TEMP_DIR/repo-a"
  local REPO_B="$TEST_TEMP_DIR/repo-b"
  mkdir -p "$REPO_A/.vbw-planning" "$REPO_B/.planning" "$REPO_B/.vbw-planning"
  touch "$REPO_B/.vbw-planning/.active-agent"
  INPUT='{"tool_input":{"file_path":"'"$REPO_B"'/.planning/STATE.md"}}'
  run bash -c "cd '$REPO_A' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
  teardown_temp_dir
}

@test "security-filter allows .vbw-planning writes regardless of marker staleness" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  touch -t 202401010101 "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  # Self-blocking removed in v1.21.13 — stale markers no longer matter
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.vbw-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "session-stop preserves .vbw-session and removes transient agent markers" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "2" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/session-stop.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "vbw session marker survives Stop and non-VBW slash commands" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/milestones/default/phases/05-migration-preview-completeness"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"

  # Start VBW flow
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"prompt\":\"/vbw:verify 5\"}' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]

  # Session Stop between turns should not clear .vbw-session
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/session-stop.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]

  # Plain-text follow-up should keep marker and allow .vbw-planning write
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"prompt\":\"it says 16 positions to move\"}' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]

  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.vbw-planning/milestones/default/phases/05-migration-preview-completeness/05-UAT.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]

  # Non-VBW slash command should NOT clear marker (removal handled by session-stop.sh)
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"prompt\":\"/gsd:status\"}' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]

  # .vbw-planning writes still allowed (self-blocking removed in v1.21.13)
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "task-verify allows role-only task subjects like Lead" {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "chore(test): seed commit"
  run bash -c "echo '{\"task_subject\":\"Lead\"}' | bash '$SCRIPTS_DIR/task-verify.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "security-filter falls back to CWD for relative FILE_PATH" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  # Relative path — derive_project_root falls back to ".", CWD-relative marker check
  INPUT='{"tool_input":{"file_path":".vbw-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "security-filter allows relative .vbw-planning FILE_PATH without markers" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  # No markers — still allowed since self-blocking removed in v1.21.13
  INPUT='{"tool_input":{"file_path":".vbw-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "prompt-preflight does NOT delete .vbw-session when prompt is a file path" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  INPUT='{"prompt":"/home/user/project/file.txt"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]
  teardown_temp_dir
}

@test "session-stop cleans up stale lock directory" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count.lock"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/session-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count.lock" ]
  teardown_temp_dir
}

@test "task-verify allows [analysis-only] tag in task_subject" {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p .vbw-planning
  # Seed commit is old (no recent commits match)
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "chore(test): seed commit"
  # Task subject with [analysis-only] tag should be allowed even without matching commit
  run bash -c "echo '{\"task_subject\":\"Hypothesis 1: race condition in sync [analysis-only]\"}' | bash '$SCRIPTS_DIR/task-verify.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "task-verify allows [analysis-only] tag in task_description fallback" {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p .vbw-planning
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "chore(test): seed commit"
  # Tag in description (subject empty) should also be allowed
  run bash -c "echo '{\"task_description\":\"Investigate memory leak [analysis-only]\"}' | bash '$SCRIPTS_DIR/task-verify.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "task-verify still blocks normal tasks without matching commit" {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p .vbw-planning
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "chore(test): seed commit"
  # Normal task without [analysis-only] and no matching commit should block
  run bash -c "echo '{\"task_subject\":\"Implement caching layer for database queries\"}' | bash '$SCRIPTS_DIR/task-verify.sh'"
  [ "$status" -eq 2 ]
  teardown_temp_dir
}

@test "task-verify allows [analysis-only] even with no recent commits" {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p .vbw-planning
  # Seed commit with a backdated timestamp (well outside 2-hour window)
  echo "hello" > file.txt
  git add file.txt
  GIT_AUTHOR_DATE="2020-01-01T00:00:00" GIT_COMMITTER_DATE="2020-01-01T00:00:00" \
    git commit -q -m "chore(test): ancient seed commit"
  # Without the fix, this would exit 2 ("No recent commits found") before
  # reaching the [analysis-only] check
  run bash -c "echo '{\"task_subject\":\"Hypothesis 2: deadlock in worker pool [analysis-only]\"}' | bash '$SCRIPTS_DIR/task-verify.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "hooks matcher includes prefixed VBW agent names" {
  run bash -c "grep -q 'vbw:vbw-scout' '$PROJECT_ROOT/hooks/hooks.json'"
  [ "$status" -eq 0 ]
}

@test "hooks matcher includes team role aliases" {
  run bash -c "grep -q 'team-lead' '$PROJECT_ROOT/hooks/hooks.json'"
  [ "$status" -eq 0 ]
}

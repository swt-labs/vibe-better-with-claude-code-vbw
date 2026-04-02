#!/usr/bin/env bats

# Tests for worktree boundary enforcement in file-guard.sh,
# worktree context injection in compaction-instructions.sh and post-compact.sh,
# stale worktree cleanup in session-stop.sh, and worktree scan in doctor-cleanup.sh.

load test_helper

setup() {
  setup_temp_dir
  create_test_config

  cd "$TEST_TEMP_DIR"

  # Git repo needed for file-guard.sh
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > init.txt
  git add init.txt
  git commit -q -m "chore: init"

  # Create an active plan so file-guard doesn't fail-open for plan checks
  mkdir -p .vbw-planning/phases/01-test
  cat > .vbw-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
phase: 1
plan: 1
title: Test
wave: 1
depends_on: []
files_modified:
  - src/app.ts
  - src/widget.ts
---
PLAN
}

teardown() {
  teardown_temp_dir
}

# Helper: run file-guard.sh with env vars and JSON input
run_file_guard() {
  local role="$1" agent_name="$2" file_path="$3"
  jq -n --arg fp "$file_path" '{"tool_input":{"file_path":$fp}}' > "$TEST_TEMP_DIR/.test-input.json"
  run env VBW_AGENT_ROLE="$role" VBW_AGENT_NAME="$agent_name" bash -c "cat '$TEST_TEMP_DIR/.test-input.json' | bash '$SCRIPTS_DIR/file-guard.sh'"
}

set_stale_mtime_3h() {
  local target="$1"
  local stamp=""
  if [ "$(uname)" = "Darwin" ]; then
    stamp=$(date -v-3H '+%Y%m%d%H%M.%S' 2>/dev/null) || return 1
  else
    stamp=$(date -d '3 hours ago' '+%Y%m%d%H%M.%S' 2>/dev/null) || return 1
  fi
  touch -t "$stamp" "$target"
}

# ===========================================================================
# file-guard.sh — Worktree Boundary Enforcement
# ===========================================================================

@test "file-guard worktree: write inside worktree allowed" {
  # Enable worktree isolation
  jq '.worktree_isolation = "on"' .vbw-planning/config.json > .vbw-planning/config.json.tmp
  mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  # Create agent-worktrees mapping pointing to project root (simulates worktree = repo)
  mkdir -p .vbw-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$TEST_TEMP_DIR\"}" > .vbw-planning/.agent-worktrees/dev-01.json

  run_file_guard dev vbw-dev-01 "$TEST_TEMP_DIR/src/app.ts"
  [ "$status" -eq 0 ]
}

@test "file-guard worktree: write outside worktree blocked" {
  jq '.worktree_isolation = "on"' .vbw-planning/config.json > .vbw-planning/config.json.tmp
  mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  mkdir -p .vbw-planning/.agent-worktrees
  local wt_path="$TEST_TEMP_DIR/.vbw-worktrees/01-01"
  mkdir -p "$wt_path"
  echo "{\"worktree_path\":\"$wt_path\"}" > .vbw-planning/.agent-worktrees/dev-01.json

  run_file_guard dev vbw-dev-01 /some/other/path/app.ts
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside worktree boundary"* ]]
}

@test "file-guard worktree: relative path inside mapped worktree allowed" {
  jq '.worktree_isolation = "on"' .vbw-planning/config.json > .vbw-planning/config.json.tmp
  mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  mkdir -p .vbw-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$TEST_TEMP_DIR\"}" > .vbw-planning/.agent-worktrees/dev-01.json

  run_file_guard dev vbw-dev-01 src/app.ts
  [ "$status" -eq 0 ]
}

@test "file-guard worktree: relative path escaping mapped worktree is blocked" {
  jq '.worktree_isolation = "on"' .vbw-planning/config.json > .vbw-planning/config.json.tmp
  mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  mkdir -p .vbw-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$TEST_TEMP_DIR\"}" > .vbw-planning/.agent-worktrees/dev-01.json

  run_file_guard dev vbw-dev-01 ../outside.ts
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside worktree boundary"* ]]
}

@test "file-guard worktree: non-dev role bypasses boundary check" {
  jq '.worktree_isolation = "on"' .vbw-planning/config.json > .vbw-planning/config.json.tmp
  mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  mkdir -p .vbw-planning/.agent-worktrees
  local wt_path="$TEST_TEMP_DIR/.vbw-worktrees/qa-01"
  mkdir -p "$wt_path"
  echo "{\"worktree_path\":\"$wt_path\"}" > .vbw-planning/.agent-worktrees/qa-01.json

  # QA role gets blocked by role isolation (can't write non-planning files), not by worktree
  local input
  input=$(jq -n '{"tool_input":{"file_path":".vbw-planning/test.md"}}')
  run bash -c "VBW_AGENT_ROLE=qa VBW_AGENT_NAME=vbw-qa-01 echo '$input' | VBW_AGENT_ROLE=qa VBW_AGENT_NAME=vbw-qa-01 bash '$SCRIPTS_DIR/file-guard.sh'"
  # Planning path is exempted, so exit 0
  [ "$status" -eq 0 ]
}

@test "file-guard worktree: worktree_isolation=off bypasses boundary check" {
  jq '.worktree_isolation = "off"' .vbw-planning/config.json > .vbw-planning/config.json.tmp
  mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  mkdir -p .vbw-planning/.agent-worktrees
  local wt_path="$TEST_TEMP_DIR/.vbw-worktrees/01-01"
  mkdir -p "$wt_path"
  echo "{\"worktree_path\":\"$wt_path\"}" > .vbw-planning/.agent-worktrees/dev-01.json

  # Dev role with worktree_isolation=off — boundary check skipped, proceeds to plan check
  run_file_guard dev vbw-dev-01 "$TEST_TEMP_DIR/src/app.ts"
  # src/app.ts is in the plan's files_modified, so allowed
  [ "$status" -eq 0 ]
}

@test "file-guard worktree: no agent-worktrees mapping fails open" {
  jq '.worktree_isolation = "on"' .vbw-planning/config.json > .vbw-planning/config.json.tmp
  mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  # No .agent-worktrees directory — should fail open

  run_file_guard dev vbw-dev-01 "$TEST_TEMP_DIR/src/app.ts"
  # No mapping file → worktree check skipped → falls through to plan check
  # src/app.ts is in files_modified → allowed
  [ "$status" -eq 0 ]
}

@test "file-guard worktree: debugger also gets boundary enforced" {
  jq '.worktree_isolation = "on"' .vbw-planning/config.json > .vbw-planning/config.json.tmp
  mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  mkdir -p .vbw-planning/.agent-worktrees
  local wt_path="$TEST_TEMP_DIR/.vbw-worktrees/debugger"
  mkdir -p "$wt_path"
  echo "{\"worktree_path\":\"$wt_path\"}" > .vbw-planning/.agent-worktrees/debugger.json

  run_file_guard debugger vbw-debugger /outside/path/file.ts
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside worktree boundary"* ]]
}

# ===========================================================================
# compaction-instructions.sh — Worktree Context Injection
# ===========================================================================

@test "compaction-instructions: dev with worktree mapping includes CRITICAL path" {
  local wt_path="$TEST_TEMP_DIR/.vbw-worktrees/01-01"
  mkdir -p "$wt_path"
  mkdir -p .vbw-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$wt_path\"}" > .vbw-planning/.agent-worktrees/dev-01.json

  run bash -c 'echo "{\"agent_name\":\"vbw-dev-01\",\"matcher\":\"auto\"}" | bash "'"$SCRIPTS_DIR"'/compaction-instructions.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"CRITICAL"* ]]
  [[ "$output" == *"$wt_path"* ]]
}

@test "compaction-instructions: native agent_id and agent_type resolve worktree mapping" {
  local wt_path="$TEST_TEMP_DIR/.vbw-worktrees/01-02"
  mkdir -p "$wt_path"
  mkdir -p .vbw-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$wt_path\"}" > .vbw-planning/.agent-worktrees/dev-01.json

  run bash -c 'echo "{\"agent_type\":\"vbw-dev\",\"agent_id\":\"dev-01\",\"matcher\":\"auto\"}" | bash "'"$SCRIPTS_DIR"'/compaction-instructions.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$wt_path"* ]]
}

@test "compaction-instructions: dev without worktree mapping omits path" {
  run bash -c 'echo "{\"agent_name\":\"vbw-dev-01\",\"matcher\":\"auto\"}" | bash "'"$SCRIPTS_DIR"'/compaction-instructions.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"CRITICAL: Your working directory"* ]]
}

@test "compaction-instructions: non-dev agent never gets worktree context" {
  local wt_path="$TEST_TEMP_DIR/.vbw-worktrees/qa-01"
  mkdir -p "$wt_path"
  mkdir -p .vbw-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$wt_path\"}" > .vbw-planning/.agent-worktrees/qa.json

  run bash -c 'echo "{\"agent_name\":\"vbw-qa\",\"matcher\":\"auto\"}" | bash "'"$SCRIPTS_DIR"'/compaction-instructions.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"CRITICAL: Your working directory"* ]]
}

# ===========================================================================
# post-compact.sh — Worktree Context Injection
# ===========================================================================

@test "post-compact: dev with worktree mapping includes worktree path" {
  local wt_path="$TEST_TEMP_DIR/.vbw-worktrees/01-01"
  mkdir -p "$wt_path"
  mkdir -p .vbw-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$wt_path\"}" > .vbw-planning/.agent-worktrees/dev-01.json

  run bash -c 'echo "{\"agent_name\":\"vbw-dev-01\"}" | bash "'"$SCRIPTS_DIR"'/post-compact.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$wt_path"* ]]
  [[ "$output" == *"Worktree working directory"* ]]
}

@test "post-compact: native agent_id and agent_type resolve worktree path" {
  local wt_path="$TEST_TEMP_DIR/.vbw-worktrees/01-02"
  mkdir -p "$wt_path"
  mkdir -p .vbw-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$wt_path\"}" > .vbw-planning/.agent-worktrees/dev-01.json

  run bash -c 'echo "{\"agent_type\":\"vbw-dev\",\"agent_id\":\"dev-01\"}" | bash "'"$SCRIPTS_DIR"'/post-compact.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$wt_path"* ]]
  [[ "$output" == *"Worktree working directory"* ]]
}

@test "post-compact: dev without worktree mapping omits path" {
  run bash -c 'echo "{\"agent_name\":\"vbw-dev-01\"}" | bash "'"$SCRIPTS_DIR"'/post-compact.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"Worktree working directory"* ]]
}

@test "post-compact: non-dev agent never gets worktree context" {
  local wt_path="$TEST_TEMP_DIR/.vbw-worktrees/lead-01"
  mkdir -p "$wt_path"
  mkdir -p .vbw-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$wt_path\"}" > .vbw-planning/.agent-worktrees/lead.json

  run bash -c 'echo "{\"agent_name\":\"vbw-lead\"}" | bash "'"$SCRIPTS_DIR"'/post-compact.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"Worktree working directory"* ]]
}

# ===========================================================================
# session-stop.sh — Stale Worktree Cleanup
# ===========================================================================

@test "session-stop: cleans stale worktree directories (>2hrs)" {
  # Create a real git worktree so cleanup outcome can be asserted.
  git worktree add .vbw-worktrees/01-01 -b vbw/01-01 >/dev/null
  set_stale_mtime_3h .vbw-worktrees/01-01
  [ "$?" -eq 0 ]

  echo '{"cost_usd":0,"duration_ms":0,"tokens_in":0,"tokens_out":0,"model":"test"}' | bash "$SCRIPTS_DIR/session-stop.sh"

  [ ! -d ".vbw-worktrees/01-01" ]
  run git branch --list "vbw/01-01"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "session-stop: preserves fresh worktree directories (<2hrs)" {
  mkdir -p .vbw-worktrees/01-01
  # Just created — should not be cleaned

  echo '{"cost_usd":0,"duration_ms":0,"tokens_in":0,"tokens_out":0,"model":"test"}' | bash "$SCRIPTS_DIR/session-stop.sh"
  # Fresh worktree should still exist
  [ -d ".vbw-worktrees/01-01" ]
}

@test "session-stop: handles no worktrees directory gracefully" {
  [ ! -d ".vbw-worktrees" ]
  run bash -c 'echo "{\"cost_usd\":0,\"duration_ms\":0,\"tokens_in\":0,\"tokens_out\":0,\"model\":\"test\"}" | bash "'"$SCRIPTS_DIR"'/session-stop.sh"'
  [ "$status" -eq 0 ]
}

# ===========================================================================
# doctor-cleanup.sh — Stale Worktree Scan
# ===========================================================================

@test "doctor-cleanup scan: detects stale worktree" {
  mkdir -p .vbw-worktrees/02-01
  set_stale_mtime_3h .vbw-worktrees/02-01
  [ "$?" -eq 0 ]

  run bash "$SCRIPTS_DIR/doctor-cleanup.sh" scan
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale_worktree|02-01"* ]]
}

@test "doctor-cleanup scan: ignores fresh worktree" {
  mkdir -p .vbw-worktrees/01-01
  # Just created — not stale

  run bash "$SCRIPTS_DIR/doctor-cleanup.sh" scan
  [ "$status" -eq 0 ]
  [[ "$output" != *"stale_worktree|01-01"* ]]
}

@test "doctor-cleanup scan: handles no worktrees directory" {
  [ ! -d ".vbw-worktrees" ]
  run bash "$SCRIPTS_DIR/doctor-cleanup.sh" scan
  [ "$status" -eq 0 ]
  [[ "$output" != *"stale_worktree"* ]]
}

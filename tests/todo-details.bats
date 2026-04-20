#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  DETAILS_PATH="$TEST_TEMP_DIR/.vbw-planning/todo-details.json"
}

teardown() {
  teardown_temp_dir
}

# --- add subcommand ---

@test "add creates new entry in empty registry" {
  cd "$TEST_TEMP_DIR"
  printf '{"schema_version":1,"items":{}}\n' > "$DETAILS_PATH"

  local detail='{"summary":"Fix parser bug","context":"The parser fails on empty input","files":["src/parser.ts"],"added":"2026-04-12","source":"user"}'
  run bash "$SCRIPTS_DIR/todo-details.sh" add "a1b2c3d4" "$detail" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  local stored
  stored=$(jq -r '.items.a1b2c3d4.summary' "$DETAILS_PATH")
  [ "$stored" = "Fix parser bug" ]
}

@test "add creates registry file if missing" {
  cd "$TEST_TEMP_DIR"
  rm -f "$DETAILS_PATH"

  local detail='{"summary":"New todo","context":"Some context","files":[],"added":"2026-04-12","source":"user"}'
  run bash "$SCRIPTS_DIR/todo-details.sh" add "deadbeef" "$detail" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  [ -f "$DETAILS_PATH" ]
  local version
  version=$(jq -r '.schema_version' "$DETAILS_PATH")
  [ "$version" = "1" ]
}

@test "add writes only canonical registry and does not create legacy fallback file" {
  cd "$TEST_TEMP_DIR"
  rm -f "$DETAILS_PATH"
  rm -rf "$TEST_TEMP_DIR/.vbw-planning/todo-details"

  local detail='{"summary":"Canonical only","context":"Stored in registry only","files":[],"added":"2026-04-12","source":"user"}'
  run bash "$SCRIPTS_DIR/todo-details.sh" add "feedcafe" "$detail" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  [ -f "$DETAILS_PATH" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/todo-details/feedcafe.json" ]
}

@test "add upserts existing entry" {
  cd "$TEST_TEMP_DIR"
  printf '{"schema_version":1,"items":{"a1b2c3d4":{"summary":"Old","context":"Old context","files":[],"added":"2026-01-01","source":"user"}}}\n' > "$DETAILS_PATH"

  local detail='{"summary":"Updated","context":"New context","files":["new.ts"],"added":"2026-04-12","source":"user"}'
  run bash "$SCRIPTS_DIR/todo-details.sh" add "a1b2c3d4" "$detail" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  local stored
  stored=$(jq -r '.items.a1b2c3d4.summary' "$DETAILS_PATH")
  [ "$stored" = "Updated" ]
}

@test "add truncates context exceeding 2000 chars" {
  cd "$TEST_TEMP_DIR"
  printf '{"schema_version":1,"items":{}}\n' > "$DETAILS_PATH"

  # Create a context string longer than 2000 chars
  local long_context
  long_context=$(printf 'x%.0s' $(seq 1 2500))
  local detail
  detail=$(jq -n --arg ctx "$long_context" '{"summary":"Long","context":$ctx,"files":[],"added":"2026-04-12","source":"user"}')

  run bash "$SCRIPTS_DIR/todo-details.sh" add "12345678" "$detail" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  local ctx_len
  ctx_len=$(jq -r '.items["12345678"].context | length' "$DETAILS_PATH")
  [ "$ctx_len" -le 2012 ]  # 2000 + "(truncated)" marker
}

# --- get subcommand ---

@test "get retrieves existing entry" {
  cd "$TEST_TEMP_DIR"
  printf '{"schema_version":1,"items":{"a1b2c3d4":{"summary":"Test","context":"Detail here","files":["a.ts"],"added":"2026-04-12","source":"user"}}}\n' > "$DETAILS_PATH"

  run bash "$SCRIPTS_DIR/todo-details.sh" get "a1b2c3d4" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  local result_status summary
  result_status=$(echo "$output" | jq -r '.status')
  summary=$(echo "$output" | jq -r '.detail.summary')
  [ "$result_status" = "ok" ]
  [ "$summary" = "Test" ]
}

@test "get returns not_found for missing hash" {
  cd "$TEST_TEMP_DIR"
  printf '{"schema_version":1,"items":{}}\n' > "$DETAILS_PATH"

  run bash "$SCRIPTS_DIR/todo-details.sh" get "deadbeef" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  local result_status
  result_status=$(echo "$output" | jq -r '.status')
  [ "$result_status" = "not_found" ]
}

@test "get returns error for missing registry file" {
  cd "$TEST_TEMP_DIR"
  rm -f "$DETAILS_PATH"

  run bash "$SCRIPTS_DIR/todo-details.sh" get "a1b2c3d4" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  local result_status
  result_status=$(echo "$output" | jq -r '.status')
  [ "$result_status" = "not_found" ]
}

@test "get falls back to legacy per-file detail when canonical registry entry is missing" {
  cd "$TEST_TEMP_DIR"
  rm -f "$DETAILS_PATH"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/todo-details"
  cat > "$TEST_TEMP_DIR/.vbw-planning/todo-details/a1b2c3d4.json" <<'EOF'
{"summary":"Legacy summary","context":"Legacy context","files":["legacy.ts"],"added":"2026-04-12","source":"user"}
EOF

  run bash "$SCRIPTS_DIR/todo-details.sh" get "a1b2c3d4" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
  [ "$(echo "$output" | jq -r '.detail.summary')" = "Legacy summary" ]
}

# --- remove subcommand ---

@test "remove deletes existing entry" {
  cd "$TEST_TEMP_DIR"
  printf '{"schema_version":1,"items":{"a1b2c3d4":{"summary":"Test","context":"Detail","files":[],"added":"2026-04-12","source":"user"}}}\n' > "$DETAILS_PATH"

  run bash "$SCRIPTS_DIR/todo-details.sh" remove "a1b2c3d4" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  local has_key
  has_key=$(jq 'has("items") and (.items | has("a1b2c3d4"))' "$DETAILS_PATH")
  [ "$has_key" = "false" ]
}

@test "remove is no-op for missing hash" {
  cd "$TEST_TEMP_DIR"
  printf '{"schema_version":1,"items":{"other":{"summary":"Keep","context":"","files":[],"added":"2026-04-12","source":"user"}}}\n' > "$DETAILS_PATH"

  run bash "$SCRIPTS_DIR/todo-details.sh" remove "deadbeef" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  # Other entry still present
  local kept
  kept=$(jq -r '.items.other.summary' "$DETAILS_PATH")
  [ "$kept" = "Keep" ]
}

@test "remove deletes legacy fallback alongside canonical registry entry" {
  cd "$TEST_TEMP_DIR"
  printf '{"schema_version":1,"items":{"deadbeef":{"summary":"Canonical","context":"Registry copy","files":[],"added":"2026-04-12","source":"user"}}}\n' > "$DETAILS_PATH"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/todo-details"
  cat > "$TEST_TEMP_DIR/.vbw-planning/todo-details/deadbeef.json" <<'EOF'
{"summary":"Legacy","context":"Legacy copy","files":[],"added":"2026-04-12","source":"user"}
EOF

  run bash "$SCRIPTS_DIR/todo-details.sh" remove "deadbeef" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  [ "$(jq -r '.items | has("deadbeef")' "$DETAILS_PATH")" = "false" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/todo-details/deadbeef.json" ]

  run bash "$SCRIPTS_DIR/todo-details.sh" get "deadbeef" "$DETAILS_PATH"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "not_found" ]
}

@test "remove deletes legacy fallback even when canonical registry is malformed" {
  cd "$TEST_TEMP_DIR"
  printf 'not json\n' > "$DETAILS_PATH"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/todo-details"
  cat > "$TEST_TEMP_DIR/.vbw-planning/todo-details/deadbeef.json" <<'EOF'
{"summary":"Legacy only","context":"Cleanup should still happen","files":[],"added":"2026-04-12","source":"user"}
EOF

  run bash "$SCRIPTS_DIR/todo-details.sh" remove "deadbeef" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
  [ "$(echo "$output" | jq -r '.action')" = "removed" ]
  [ "$(echo "$output" | jq -r '.canonical_status')" = "malformed" ]
  [ "$(echo "$output" | jq -r '.legacy_removed')" = "true" ]
  [[ "$(echo "$output" | jq -r '.warning')" == *'Malformed todo-details.json'* ]]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/todo-details/deadbeef.json" ]
  [ "$(cat "$DETAILS_PATH")" = "not json" ]
}

# --- list subcommand ---

@test "list returns all entries" {
  cd "$TEST_TEMP_DIR"
  printf '{"schema_version":1,"items":{"aaa":{"summary":"A","context":"","files":[],"added":"2026-01-01","source":"user"},"bbb":{"summary":"B","context":"","files":[],"added":"2026-01-02","source":"known-issue"}}}\n' > "$DETAILS_PATH"

  run bash "$SCRIPTS_DIR/todo-details.sh" list "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  local count
  count=$(echo "$output" | jq -r '.count')
  [ "$count" = "2" ]
}

@test "list returns empty for no entries" {
  cd "$TEST_TEMP_DIR"
  printf '{"schema_version":1,"items":{}}\n' > "$DETAILS_PATH"

  run bash "$SCRIPTS_DIR/todo-details.sh" list "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  local count
  count=$(echo "$output" | jq -r '.count')
  [ "$count" = "0" ]
}

# --- gc subcommand ---

@test "gc removes orphaned entries not in STATE.md" {
  cd "$TEST_TEMP_DIR"
  local state_path="$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  cat > "$state_path" <<'EOF'
# State
## Todos
- Fix parser bug (added 2026-04-12) (ref:a1b2c3d4)
- Simple todo (added 2026-04-12)
EOF

  printf '{"schema_version":1,"items":{"a1b2c3d4":{"summary":"Keep","context":"","files":[],"added":"2026-04-12","source":"user"},"deadbeef":{"summary":"Orphan","context":"","files":[],"added":"2026-04-12","source":"user"}}}\n' > "$DETAILS_PATH"

  run bash "$SCRIPTS_DIR/todo-details.sh" gc "$state_path" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  local kept orphan
  kept=$(jq 'has("items") and (.items | has("a1b2c3d4"))' "$DETAILS_PATH")
  orphan=$(jq 'has("items") and (.items | has("deadbeef"))' "$DETAILS_PATH")
  [ "$kept" = "true" ]
  [ "$orphan" = "false" ]
}

@test "gc preserves all entries when all referenced" {
  cd "$TEST_TEMP_DIR"
  local state_path="$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  cat > "$state_path" <<'EOF'
# State
## Todos
- Bug A (ref:aaaa1111)
- Bug B (ref:bbbb2222)
EOF

  printf '{"schema_version":1,"items":{"aaaa1111":{"summary":"A","context":"","files":[],"added":"2026-04-12","source":"user"},"bbbb2222":{"summary":"B","context":"","files":[],"added":"2026-04-12","source":"user"}}}\n' > "$DETAILS_PATH"

  run bash "$SCRIPTS_DIR/todo-details.sh" gc "$state_path" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  local count
  count=$(jq '.items | length' "$DETAILS_PATH")
  [ "$count" = "2" ]
}

@test "gc handles legacy Pending Todos heading" {
  cd "$TEST_TEMP_DIR"
  local state_path="$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  cat > "$state_path" <<'EOF'
# State
### Pending Todos
- Bug A (ref:aaaa1111)
- Bug C (ref:cccc3333)
EOF

  printf '{"schema_version":1,"items":{"aaaa1111":{"summary":"A","context":"","files":[],"added":"2026-04-12","source":"user"},"bbbb2222":{"summary":"B","context":"","files":[],"added":"2026-04-12","source":"user"},"cccc3333":{"summary":"C","context":"","files":[],"added":"2026-04-12","source":"user"}}}\n' > "$DETAILS_PATH"

  run bash "$SCRIPTS_DIR/todo-details.sh" gc "$state_path" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  # bbbb2222 should be removed (not in STATE.md), aaaa1111 and cccc3333 preserved
  local count
  count=$(jq '.items | length' "$DETAILS_PATH")
  [ "$count" = "2" ]
  [ "$(jq -r '.items | has("aaaa1111")' "$DETAILS_PATH")" = "true" ]
  [ "$(jq -r '.items | has("cccc3333")' "$DETAILS_PATH")" = "true" ]
  [ "$(jq -r '.items | has("bbbb2222")' "$DETAILS_PATH")" = "false" ]
}

# --- error handling ---

@test "add accepts JSON from stdin when detail arg is dash" {
  cd "$TEST_TEMP_DIR"
  printf '{"schema_version":1,"items":{}}\n' > "$DETAILS_PATH"

  # Build JSON with apostrophes via jq (handles all escaping) and write to temp file
  jq -n '{"summary":"User'\''s repro doesn'\''t work","context":"The user'\''s test doesn'\''t pass","files":[],"added":"2026-04-12","source":"user"}' > "$TEST_TEMP_DIR/detail.json"

  run bash -c "bash \"$SCRIPTS_DIR/todo-details.sh\" add abcd1234 - \"$DETAILS_PATH\" < \"$TEST_TEMP_DIR/detail.json\""
  [ "$status" -eq 0 ]

  local stored
  stored=$(jq -r '.items.abcd1234.summary' "$DETAILS_PATH")
  [ "$stored" = "User's repro doesn't work" ]
}

@test "error output is valid JSON when message contains special characters" {
  cd "$TEST_TEMP_DIR"

  # Pass a hash containing double quotes and backslashes (will fail validation)
  run bash "$SCRIPTS_DIR/todo-details.sh" get 'a"b\c' "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  # Output must parse as valid JSON
  echo "$output" | jq empty
  local result_status
  result_status=$(echo "$output" | jq -r '.status')
  [ "$result_status" = "not_found" ]
}

@test "handles malformed JSON registry gracefully" {
  cd "$TEST_TEMP_DIR"
  echo "not json" > "$DETAILS_PATH"

  run bash "$SCRIPTS_DIR/todo-details.sh" get "a1b2c3d4" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  local result_status
  result_status=$(echo "$output" | jq -r '.status')
  [ "$result_status" = "not_found" ]
}

@test "add recovers from malformed registry" {
  cd "$TEST_TEMP_DIR"
  echo "not json" > "$DETAILS_PATH"

  local detail='{"summary":"Recover","context":"New","files":[],"added":"2026-04-12","source":"user"}'
  run bash "$SCRIPTS_DIR/todo-details.sh" add "a1b2c3d4" "$detail" "$DETAILS_PATH"
  [ "$status" -eq 0 ]

  local stored
  stored=$(jq -r '.items.a1b2c3d4.summary' "$DETAILS_PATH")
  [ "$stored" = "Recover" ]
}

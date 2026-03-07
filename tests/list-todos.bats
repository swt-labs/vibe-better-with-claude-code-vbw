#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

create_state_with_todos() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
# VBW State

**Project:** Test
**Status:** Active

## Todos
- Fix bug in parser (added 2026-01-15)
- [HIGH] Refactor auth module (added 2026-02-01)
- [low] Update docs (added 2026-02-10)

## Memory
**Vault:** test-vault
EOF
}

@test "reads todos from root STATE.md (no ACTIVE)" {
  cd "$TEST_TEMP_DIR"
  create_state_with_todos ".vbw-planning/STATE.md"

  run bash "$SCRIPTS_DIR/list-todos.sh"
  [ "$status" -eq 0 ]

  local count
  count=$(echo "$output" | jq -r '.count')
  [ "$count" -eq 3 ]
}

@test "falls back to milestones/ when no root STATE.md" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/milestones/default
  create_state_with_todos ".vbw-planning/milestones/default/STATE.md"

  run bash "$SCRIPTS_DIR/list-todos.sh"
  [ "$status" -eq 0 ]

  local state_path status_val
  state_path=$(echo "$output" | jq -r '.state_path')
  status_val=$(echo "$output" | jq -r '.status')
  [ "$status_val" = "ok" ]
  [ "$state_path" = ".vbw-planning/milestones/default/STATE.md" ]
}

@test "errors when no STATE.md exists anywhere" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/milestones

  run bash "$SCRIPTS_DIR/list-todos.sh"
  [ "$status" -eq 0 ]

  local status_val
  status_val=$(echo "$output" | jq -r '.status')
  [ "$status_val" = "error" ]
}

@test "priority filter works with milestone fallback" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/milestones/default
  create_state_with_todos ".vbw-planning/milestones/default/STATE.md"

  run bash "$SCRIPTS_DIR/list-todos.sh" high
  [ "$status" -eq 0 ]

  local count
  count=$(echo "$output" | jq -r '.count')
  [ "$count" -eq 1 ]

  local pri
  pri=$(echo "$output" | jq -r '.items[0].priority')
  [ "$pri" = "high" ]
}

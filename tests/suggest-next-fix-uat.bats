#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  echo '# Project' > "$TEST_TEMP_DIR/.vbw-planning/PROJECT.md"
  cd "$TEST_TEMP_DIR"
}

teardown() {
  teardown_temp_dir
}

# Helper: create a .last-fix-commit marker
create_fix_marker() {
  cat > "$TEST_TEMP_DIR/.vbw-planning/.last-fix-commit" <<'EOF'
commit=abc1234
message=fix(button): handle null ref
timestamp=2025-01-01T12:00:00+00:00
description=Fixed the button crash
files=src/button.sh
EOF
}

# Helper: enable auto_uat in config
enable_auto_uat() {
  local cfg="$TEST_TEMP_DIR/.vbw-planning/config.json"
  local tmp
  tmp=$(mktemp)
  jq '.auto_uat = true' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
}

# ── fix branch: non-debug suggestions ────────────────────

@test "fix suggests verify-the-fix and continue-building by default" {
  run bash "$SCRIPTS_DIR/suggest-next.sh" fix pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"Verify the fix"* ]]
  [[ "$output" == *"Continue building"* ]]
}

@test "fix does not suggest UAT when auto_uat is false" {
  create_fix_marker
  run bash "$SCRIPTS_DIR/suggest-next.sh" fix pass
  [ "$status" -eq 0 ]
  [[ "$output" != *"Run UAT on the fix"* ]]
}

@test "fix does not suggest UAT when auto_uat is true but no marker" {
  enable_auto_uat
  run bash "$SCRIPTS_DIR/suggest-next.sh" fix pass
  [ "$status" -eq 0 ]
  [[ "$output" != *"Run UAT on the fix"* ]]
}

@test "fix suggests UAT when auto_uat is true and marker exists" {
  enable_auto_uat
  create_fix_marker
  run bash "$SCRIPTS_DIR/suggest-next.sh" fix pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"Run UAT on the fix"* ]]
  [[ "$output" == *"Verify the fix"* ]]
  [[ "$output" == *"Continue building"* ]]
}

@test "fix does not suggest UAT when marker is stale (>24h)" {
  enable_auto_uat
  create_fix_marker
  # Backdate marker by 25 hours
  if [[ "$OSTYPE" == darwin* ]]; then
    touch -t "$(date -v-25H '+%Y%m%d%H%M.%S')" "$TEST_TEMP_DIR/.vbw-planning/.last-fix-commit"
  else
    touch -d "25 hours ago" "$TEST_TEMP_DIR/.vbw-planning/.last-fix-commit"
  fi
  run bash "$SCRIPTS_DIR/suggest-next.sh" fix pass
  [ "$status" -eq 0 ]
  [[ "$output" != *"Run UAT on the fix"* ]]
  # Should still have other suggestions
  [[ "$output" == *"Verify the fix"* ]]
  [[ "$output" == *"Continue building"* ]]
}

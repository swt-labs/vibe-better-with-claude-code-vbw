#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning"
  mkdir -p "$VBW_PLANNING_DIR"
  # Init a git repo so base_commit works
  git -C "$TEST_TEMP_DIR" init --quiet 2>/dev/null || true
  git -C "$TEST_TEMP_DIR" config user.email "test@test.com" 2>/dev/null || true
  git -C "$TEST_TEMP_DIR" config user.name "Test" 2>/dev/null || true
  touch "$TEST_TEMP_DIR/dummy"
  git -C "$TEST_TEMP_DIR" add dummy 2>/dev/null || true
  git -C "$TEST_TEMP_DIR" commit -m "init" --quiet 2>/dev/null || true
}

teardown() {
  teardown_temp_dir
}

# ── start ────────────────────────────────────────────────

@test "start creates research file in research/ directory" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/research-session-state.sh" start "$VBW_PLANNING_DIR" "test-topic"
  [ "$status" -eq 0 ]

  # Should output research_id and research_file
  [[ "$output" == *"research_id="* ]]
  [[ "$output" == *"research_file="* ]]

  # Research directory should exist
  [ -d "$VBW_PLANNING_DIR/research" ]

  # Session file should exist
  eval "$output"
  [ -f "$research_file" ]
  [[ "$research_file" == *"/research/"* ]]

  # File should have correct frontmatter
  grep -q '^status: active$' "$research_file"
  grep -q '^type: standalone-research$' "$research_file"
  grep -q '^base_commit:' "$research_file"
}

@test "start sanitizes slug to lowercase with dashes" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/research-session-state.sh" start "$VBW_PLANNING_DIR" "My Research Has Spaces & Symbols!"
  [ "$status" -eq 0 ]
  eval "$output"
  # Slug should be sanitized
  [[ "$research_id" == *"-my-research-has-spaces-symbols"* ]]
}

@test "start truncates slug at 50 chars" {
  cd "$TEST_TEMP_DIR"
  LONG_SLUG="this-is-a-very-long-slug-that-exceeds-fifty-characters-and-should-be-truncated"
  run bash "$SCRIPTS_DIR/research-session-state.sh" start "$VBW_PLANNING_DIR" "$LONG_SLUG"
  [ "$status" -eq 0 ]
  eval "$output"
  # The slug portion (after YYYYMMDD-HHMMSS-) should be max 50 chars
  slug_part="${research_id#*-*-}"  # strip YYYYMMDD-HHMMSS-
  [ "${#slug_part}" -le 50 ]
}

@test "start fails without slug" {
  run bash "$SCRIPTS_DIR/research-session-state.sh" start "$VBW_PLANNING_DIR"
  [ "$status" -eq 1 ]
}

@test "start records base_commit from git HEAD" {
  cd "$TEST_TEMP_DIR"
  EXPECTED_COMMIT=$(git rev-parse HEAD)
  eval "$(bash "$SCRIPTS_DIR/research-session-state.sh" start "$VBW_PLANNING_DIR" "commit-test")"
  BASE=$(grep '^base_commit:' "$research_file" | sed 's/^base_commit:[[:space:]]*//')
  [ "$BASE" = "$EXPECTED_COMMIT" ]
}

# ── complete ─────────────────────────────────────────────

@test "complete marks session as complete" {
  cd "$TEST_TEMP_DIR"
  eval "$(bash "$SCRIPTS_DIR/research-session-state.sh" start "$VBW_PLANNING_DIR" "complete-test")"

  run bash "$SCRIPTS_DIR/research-session-state.sh" complete "$VBW_PLANNING_DIR" "$research_id"
  [ "$status" -eq 0 ]
  [[ "$output" == "complete" ]]

  # Status in frontmatter should be complete
  grep -q '^status: complete$' "$research_file"
}

@test "complete fails for nonexistent session" {
  run bash "$SCRIPTS_DIR/research-session-state.sh" complete "$VBW_PLANNING_DIR" "nonexistent-id"
  [ "$status" -eq 1 ]
}

# ── list ─────────────────────────────────────────────────

@test "list returns empty when no research exists" {
  run bash "$SCRIPTS_DIR/research-session-state.sh" list "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "list returns JSON for each research session" {
  cd "$TEST_TEMP_DIR"
  eval "$(bash "$SCRIPTS_DIR/research-session-state.sh" start "$VBW_PLANNING_DIR" "list-test-one")"
  eval "$(bash "$SCRIPTS_DIR/research-session-state.sh" start "$VBW_PLANNING_DIR" "list-test-two")"

  run bash "$SCRIPTS_DIR/research-session-state.sh" list "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  # Should have 2 lines of JSON
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 2 ]
  [[ "$output" == *'"status":"active"'* ]]
}

@test "list filters by status" {
  cd "$TEST_TEMP_DIR"
  eval "$(bash "$SCRIPTS_DIR/research-session-state.sh" start "$VBW_PLANNING_DIR" "active-one")"
  local active_id="$research_id"
  eval "$(bash "$SCRIPTS_DIR/research-session-state.sh" start "$VBW_PLANNING_DIR" "complete-one")"
  bash "$SCRIPTS_DIR/research-session-state.sh" complete "$VBW_PLANNING_DIR" "$research_id" > /dev/null

  # Filter for complete only
  run bash "$SCRIPTS_DIR/research-session-state.sh" list "$VBW_PLANNING_DIR" --status complete
  [ "$status" -eq 0 ]
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 1 ]
  [[ "$output" == *'"status":"complete"'* ]]

  # Filter for active only
  run bash "$SCRIPTS_DIR/research-session-state.sh" list "$VBW_PLANNING_DIR" --status active
  [ "$status" -eq 0 ]
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 1 ]
  [[ "$output" == *'"status":"active"'* ]]
}

# ── get ──────────────────────────────────────────────────

@test "get returns session metadata" {
  cd "$TEST_TEMP_DIR"
  eval "$(bash "$SCRIPTS_DIR/research-session-state.sh" start "$VBW_PLANNING_DIR" "get-test")"

  run bash "$SCRIPTS_DIR/research-session-state.sh" get "$VBW_PLANNING_DIR" "$research_id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"research_id="* ]]
  [[ "$output" == *"research_status=active"* ]]
  [[ "$output" == *"research_base_commit="* ]]
}

@test "get fails for nonexistent session" {
  run bash "$SCRIPTS_DIR/research-session-state.sh" get "$VBW_PLANNING_DIR" "nonexistent"
  [ "$status" -eq 1 ]
}

# ── latest ───────────────────────────────────────────────

@test "latest returns empty research_file when no sessions exist" {
  run bash "$SCRIPTS_DIR/research-session-state.sh" latest "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"research_file="* ]]
}

@test "latest returns most recent session" {
  cd "$TEST_TEMP_DIR"
  eval "$(bash "$SCRIPTS_DIR/research-session-state.sh" start "$VBW_PLANNING_DIR" "first")"
  sleep 1
  eval "$(bash "$SCRIPTS_DIR/research-session-state.sh" start "$VBW_PLANNING_DIR" "second")"
  local second_id="$research_id"

  run bash "$SCRIPTS_DIR/research-session-state.sh" latest "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$second_id"* ]]
}

# ── migrate ──────────────────────────────────────────────

@test "migrate moves root-level RESEARCH-*.md files into research/" {
  # Create a root-level research file
  cat > "$VBW_PLANNING_DIR/RESEARCH-old-topic.md" << 'EOF'
# Old Research
Some findings.
EOF

  run bash "$SCRIPTS_DIR/research-session-state.sh" migrate "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"migrated=1"* ]]

  # Original should be gone
  [ ! -f "$VBW_PLANNING_DIR/RESEARCH-old-topic.md" ]

  # Should exist under research/
  [ -d "$VBW_PLANNING_DIR/research" ]
  file_count=$(find "$VBW_PLANNING_DIR/research" -name "*.md" | wc -l | tr -d ' ')
  [ "$file_count" -eq 1 ]

  # Migrated file should have frontmatter injected
  local migrated_file
  migrated_file=$(find "$VBW_PLANNING_DIR/research" -name "*.md" | head -1)
  head -1 "$migrated_file" | grep -q '^---$'
  grep -q '^status: complete$' "$migrated_file"
  grep -q '^type: standalone-research$' "$migrated_file"
  grep -q '^base_commit: unknown$' "$migrated_file"
}

@test "migrate handles no files gracefully" {
  run bash "$SCRIPTS_DIR/research-session-state.sh" migrate "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"migrated=0"* ]]
}

@test "migrate skips non-RESEARCH files" {
  # Create files that should NOT be migrated
  echo "state" > "$VBW_PLANNING_DIR/STATE.md"
  echo "not-research" > "$VBW_PLANNING_DIR/OTHER-topic.md"

  run bash "$SCRIPTS_DIR/research-session-state.sh" migrate "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"migrated=0"* ]]

  # Original files should still be there
  [ -f "$VBW_PLANNING_DIR/STATE.md" ]
  [ -f "$VBW_PLANNING_DIR/OTHER-topic.md" ]
}

@test "migrate preserves existing frontmatter and sets status complete" {
  cat > "$VBW_PLANNING_DIR/RESEARCH-has-fm.md" << 'EOF'
---
title: Has Frontmatter
type: standalone-research
status: active
confidence: high
base_commit: abc123
---

# Has Frontmatter
Some findings.
EOF

  run bash "$SCRIPTS_DIR/research-session-state.sh" migrate "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"migrated=1"* ]]

  local migrated_file
  migrated_file=$(find "$VBW_PLANNING_DIR/research" -name "*.md" | head -1)
  # Should still start with frontmatter
  head -1 "$migrated_file" | grep -q '^---$'
  # Status should be updated to complete
  grep -q '^status: complete$' "$migrated_file"
  # Original fields should be preserved
  grep -q '^base_commit: abc123$' "$migrated_file"
  grep -q '^title: Has Frontmatter$' "$migrated_file"
}

@test "migrate backfills missing status and base_commit in existing frontmatter" {
  cat > "$VBW_PLANNING_DIR/RESEARCH-partial-fm.md" << 'EOF'
---
title: Partial Frontmatter
confidence: high
---

# Partial Frontmatter
Has frontmatter but missing status and base_commit fields.
EOF

  run bash "$SCRIPTS_DIR/research-session-state.sh" migrate "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"migrated=1"* ]]

  local migrated_file
  migrated_file=$(find "$VBW_PLANNING_DIR/research" -name "*partial-fm*" | head -1)
  # Should have frontmatter
  head -1 "$migrated_file" | grep -q '^---$'
  # Should have backfilled status
  grep -q '^status: complete$' "$migrated_file"
  # Should have backfilled base_commit
  grep -q '^base_commit: unknown$' "$migrated_file"
  # Should have backfilled type
  grep -q '^type: standalone-research$' "$migrated_file"
  # Original fields should be preserved
  grep -q '^title: Partial Frontmatter$' "$migrated_file"
  grep -q '^confidence: high$' "$migrated_file"
}

@test "migrate backfills missing fields even when body contains matching tokens" {
  cat > "$VBW_PLANNING_DIR/RESEARCH-bodytoken.md" << 'EOF'
---
title: Body Token Test
confidence: high
---

# Body Token Test
This body mentions status: active and base_commit: abc123 in prose.
EOF

  run bash "$SCRIPTS_DIR/research-session-state.sh" migrate "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"migrated=1"* ]]

  local migrated_file
  migrated_file=$(find "$VBW_PLANNING_DIR/research" -name "*bodytoken*" | head -1)
  # Frontmatter should have the injected fields (not confused by body content)
  # Read only frontmatter to verify
  local fm_status fm_base_commit
  fm_status=$(awk '/^---$/ { if (!s) { s=1; next } if (s) exit } s && /^status:/ { sub(/^status:[[:space:]]*/, ""); print }' "$migrated_file")
  fm_base_commit=$(awk '/^---$/ { if (!s) { s=1; next } if (s) exit } s && /^base_commit:/ { sub(/^base_commit:[[:space:]]*/, ""); print }' "$migrated_file")
  [ "$fm_status" = "complete" ]
  [ "$fm_base_commit" = "unknown" ]
}

@test "migrate extracts title from heading when no frontmatter" {
  cat > "$VBW_PLANNING_DIR/RESEARCH-titled.md" << 'EOF'
# My Custom Title
Some content here.
EOF

  run bash "$SCRIPTS_DIR/research-session-state.sh" migrate "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]

  local migrated_file
  migrated_file=$(find "$VBW_PLANNING_DIR/research" -name "*.md" | head -1)
  grep -q '^title: "My Custom Title"$' "$migrated_file"
}

# ── validate_session_name ────────────────────────────────

@test "get rejects invalid session name with path traversal" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/research-session-state.sh" get "$VBW_PLANNING_DIR" "../../etc/passwd"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid session name"* ]]
}

@test "complete rejects invalid session name with path traversal" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/research-session-state.sh" complete "$VBW_PLANNING_DIR" "../foo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid session name"* ]]
}

@test "get rejects malformed session name format" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/research-session-state.sh" get "$VBW_PLANNING_DIR" "not-valid-format"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid session name"* ]]
}

# ── start triggers opportunistic migration ───────────────

@test "start automatically migrates root-level RESEARCH files" {
  cd "$TEST_TEMP_DIR"
  cat > "$VBW_PLANNING_DIR/RESEARCH-legacy.md" << 'EOF'
# Legacy Research
Old findings.
EOF

  eval "$(bash "$SCRIPTS_DIR/research-session-state.sh" start "$VBW_PLANNING_DIR" "new-session")"

  # Legacy file should be migrated
  [ ! -f "$VBW_PLANNING_DIR/RESEARCH-legacy.md" ]
  # New session should exist
  [ -f "$research_file" ]
  # Research dir should have both files
  file_count=$(find "$VBW_PLANNING_DIR/research" -name "*.md" | wc -l | tr -d ' ')
  [ "$file_count" -eq 2 ]
}

# ── error handling ───────────────────────────────────────

@test "fails with unknown command" {
  run bash "$SCRIPTS_DIR/research-session-state.sh" bogus "$VBW_PLANNING_DIR"
  [ "$status" -eq 1 ]
}

@test "fails without planning dir" {
  run bash "$SCRIPTS_DIR/research-session-state.sh" start
  [ "$status" -eq 1 ]
}

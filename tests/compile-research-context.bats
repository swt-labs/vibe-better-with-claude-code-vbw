#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  setup_temp_dir
  export VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning"
  mkdir -p "$VBW_PLANNING_DIR"

  # Init a git repo for staleness checks
  cd "$TEST_TEMP_DIR"
  git init --quiet
  git config user.email "test@test.com"
  git config user.name "Test"
  touch dummy
  git add dummy
  git commit -m "init" --quiet
}

teardown() {
  teardown_temp_dir
}

# Helper: create a completed research file with known base_commit
create_research_file() {
  local slug="${1:-test-topic}"
  local title="${2:-$slug}"
  cd "$TEST_TEMP_DIR"
  eval "$(bash "$SCRIPTS_DIR/research-session-state.sh" start "$VBW_PLANNING_DIR" "$slug")"
  # Write actual findings content
  cat > "$research_file" << ENDCONTENT
---
title: ${title}
type: standalone-research
status: complete
confidence: high
created: $(date '+%Y-%m-%d %H:%M:%S')
updated: $(date '+%Y-%m-%d %H:%M:%S')
base_commit: $(git -C "$TEST_TEMP_DIR" rev-parse HEAD)
linked_sessions: []
---

# Research: ${title}

## Summary

Research findings about ${title}.

## Findings

Found something important.
ENDCONTENT
  echo "$research_file"
}

# ── Empty cases ──────────────────────────────────────────

@test "outputs nothing when no research exists" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR" "some bug"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "outputs nothing when no description and multiple files exist" {
  cd "$TEST_TEMP_DIR"
  create_research_file "topic-one" "topic-one"
  create_research_file "topic-two" "topic-two"

  run bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "outputs nothing when research is active (not complete)" {
  cd "$TEST_TEMP_DIR"
  eval "$(bash "$SCRIPTS_DIR/research-session-state.sh" start "$VBW_PLANNING_DIR" "active-only")"
  # Don't complete it — leave as active

  run bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR" "active only"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── Single file discovery ────────────────────────────────

@test "outputs nothing for single completed research without description" {
  cd "$TEST_TEMP_DIR"
  create_research_file "only-topic" "only-topic"

  run bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  # No description = no match = no output (AC#6: no recency fallback)
  [ -z "$output" ]
}

@test "returns single completed research with 2+ keyword match" {
  cd "$TEST_TEMP_DIR"
  create_research_file "api-design" "api-design"

  # 2+ keywords match: "api" and "design" both appear in title
  run bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR" "api design issue"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Research findings about"* ]]
}

@test "outputs nothing for single file with only 1 keyword match" {
  cd "$TEST_TEMP_DIR"
  create_research_file "api-design" "api-design"

  # Only 1 keyword matches: "api" matches but "crash" does not
  run bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR" "api crash report"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── Keyword matching ─────────────────────────────────────

@test "matches research by keyword hits in title (2+ required)" {
  cd "$TEST_TEMP_DIR"
  create_research_file "swift-concurrency-patterns" "swift-concurrency-patterns"
  create_research_file "python-web-server" "python-web-server"

  # Description with 2+ keywords matching first file
  run bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR" "swift concurrency issue"
  [ "$status" -eq 0 ]
  [[ "$output" == *"swift-concurrency-patterns"* ]]
}

@test "outputs nothing when only 1 keyword matches" {
  cd "$TEST_TEMP_DIR"
  create_research_file "swift-concurrency-patterns" "swift-concurrency-patterns"
  create_research_file "python-web-server" "python-web-server"

  # Only 1 keyword match
  run bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR" "swift memory leak"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "outputs nothing when no keywords match" {
  cd "$TEST_TEMP_DIR"
  create_research_file "topic-alpha" "topic-alpha"
  create_research_file "topic-beta" "topic-beta"

  run bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR" "something completely unrelated"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── Explicit file override ───────────────────────────────

@test "explicit file override returns content directly" {
  cd "$TEST_TEMP_DIR"
  local rfile
  rfile=$(create_research_file "override-test" "override-test")

  run bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR" --file "$rfile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Research findings about"* ]]
}

@test "explicit file override bypasses staleness" {
  cd "$TEST_TEMP_DIR"
  local rfile
  rfile=$(create_research_file "stale-override" "stale-override")

  # Add many commits to make it stale
  for i in $(seq 1 15); do
    echo "change $i" >> "$TEST_TEMP_DIR/dummy"
    git -C "$TEST_TEMP_DIR" add dummy
    git -C "$TEST_TEMP_DIR" commit -m "commit $i" --quiet
  done

  # With --file, should still return content despite staleness
  run bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR" --file "$rfile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Research findings about"* ]]
}

@test "explicit file override returns empty for nonexistent file" {
  run --separate-stderr bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR" --file "/nonexistent/path.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── Staleness checks ────────────────────────────────────

@test "fresh research is returned without warning" {
  cd "$TEST_TEMP_DIR"
  create_research_file "fresh-topic" "fresh-topic"

  run bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR" "fresh topic"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Research findings about"* ]]
  # Should NOT contain staleness warning
  [[ "$output" != *"commits have landed"* ]]
}

@test "moderately stale research includes warning" {
  cd "$TEST_TEMP_DIR"
  create_research_file "warn-topic" "warn-topic"

  # Add commits within warn threshold (5 commits, under STALE_WARN_THRESHOLD=10)
  for i in $(seq 1 5); do
    echo "change $i" >> "$TEST_TEMP_DIR/dummy"
    git -C "$TEST_TEMP_DIR" add dummy
    git -C "$TEST_TEMP_DIR" commit -m "commit $i" --quiet
  done

  run bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR" "warn topic"
  [ "$status" -eq 0 ]
  # Should contain both the warning and the content
  [[ "$output" == *"commits have landed"* ]]
  [[ "$output" == *"Research findings about"* ]]
}

@test "very stale research is skipped entirely" {
  cd "$TEST_TEMP_DIR"
  create_research_file "stale-topic" "stale-topic"

  # Add many commits to exceed STALE_SKIP_THRESHOLD=11
  for i in $(seq 1 15); do
    echo "change $i" >> "$TEST_TEMP_DIR/dummy"
    git -C "$TEST_TEMP_DIR" add dummy
    git -C "$TEST_TEMP_DIR" commit -m "commit $i" --quiet
  done

  run --separate-stderr bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR" "stale topic"
  [ "$status" -eq 0 ]
  # Should produce no stdout content
  [ -z "$output" ]
}

@test "staleness ignores commits in .vbw-planning" {
  cd "$TEST_TEMP_DIR"
  create_research_file "planning-ignore" "planning-ignore"

  # Add commits only touching .vbw-planning
  for i in $(seq 1 15); do
    echo "change $i" >> "$TEST_TEMP_DIR/.vbw-planning/state-change-$i"
    git -C "$TEST_TEMP_DIR" add .vbw-planning
    git -C "$TEST_TEMP_DIR" commit -m "planning change $i" --quiet
  done

  run bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR" "planning ignore"
  [ "$status" -eq 0 ]
  # Should still be fresh — .vbw-planning commits are excluded
  [[ "$output" == *"Research findings about"* ]]
  [[ "$output" != *"commits have landed"* ]]
}

# ── Edge cases ───────────────────────────────────────────

@test "exits 0 with empty output when planning dir missing" {
  run bash "$SCRIPTS_DIR/compile-research-context.sh" "/nonexistent/dir" "some query"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "handles short keywords gracefully" {
  cd "$TEST_TEMP_DIR"
  create_research_file "api-design" "api-design"
  create_research_file "ui-layout" "ui-layout"

  # All keywords < 3 chars should be filtered out
  run bash "$SCRIPTS_DIR/compile-research-context.sh" "$VBW_PLANNING_DIR" "an is at"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

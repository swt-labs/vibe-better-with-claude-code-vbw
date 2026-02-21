#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  mkdir -p "$PHASE_DIR"
}

teardown() {
  teardown_temp_dir
}

@test "get returns none when no state file exists" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "init major creates plan stage" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [ "$output" = "plan" ]
  [ -f "$PHASE_DIR/.uat-remediation-stage" ]
  [ "$(cat "$PHASE_DIR/.uat-remediation-stage")" = "plan" ]
}

@test "init minor creates fix stage" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "minor"
  [ "$status" -eq 0 ]
  [ "$output" = "fix" ]
  [ "$(cat "$PHASE_DIR/.uat-remediation-stage")" = "fix" ]
}

@test "init unknown severity defaults to plan" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "unknown"
  [ "$status" -eq 0 ]
  [ "$output" = "plan" ]
}

@test "advance major chain: plan -> execute -> done" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "execute" ]

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "done" ]
}

@test "advance minor chain: fix -> done" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "minor" >/dev/null

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "done" ]
}

@test "advance from done stays done" {
  echo "done" > "$PHASE_DIR/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "done" ]
}

@test "get returns persisted stage after advance" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR" >/dev/null

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get "$PHASE_DIR"
  [ "$output" = "execute" ]
}

@test "reset removes state file" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" reset "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
  [ ! -f "$PHASE_DIR/.uat-remediation-stage" ]
}

@test "missing arguments exits with error" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh"
  [ "$status" -eq 1 ]

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get
  [ "$status" -eq 1 ]
}

@test "init without severity exits with error" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR"
  [ "$status" -eq 1 ]
}

# --- CONTEXT.md pre-seeding tests ---

@test "init appends UAT to existing CONTEXT and adds pre_seeded frontmatter" {
  # Create existing CONTEXT with frontmatter
  cat > "$PHASE_DIR/01-CONTEXT.md" <<'EOF'
---
phase: 01
title: Test phase
---

# Original Context

Some discussion content here.
EOF
  # Create UAT report
  cat > "$PHASE_DIR/01-UAT.md" <<'EOF'
# UAT Report
- Issue 1: Something broken
EOF

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]

  # Original content preserved
  grep -q "# Original Context" "$PHASE_DIR/01-CONTEXT.md"
  grep -q "Some discussion content here" "$PHASE_DIR/01-CONTEXT.md"

  # pre_seeded added to frontmatter
  grep -q "^pre_seeded: true" "$PHASE_DIR/01-CONTEXT.md"

  # UAT content appended
  grep -q "## UAT Remediation Issues" "$PHASE_DIR/01-CONTEXT.md"
  grep -q "Issue 1: Something broken" "$PHASE_DIR/01-CONTEXT.md"
}

@test "init adds frontmatter to CONTEXT without existing frontmatter" {
  # Create CONTEXT without frontmatter
  cat > "$PHASE_DIR/01-CONTEXT.md" <<'EOF'
# Original Context

No frontmatter here.
EOF
  cat > "$PHASE_DIR/01-UAT.md" <<'EOF'
# UAT Report
- Bug found
EOF

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]

  # Frontmatter was prepended
  head -1 "$PHASE_DIR/01-CONTEXT.md" | grep -q '^---$'
  grep -q "^pre_seeded: true" "$PHASE_DIR/01-CONTEXT.md"

  # Original content preserved
  grep -q "# Original Context" "$PHASE_DIR/01-CONTEXT.md"
  grep -q "No frontmatter here" "$PHASE_DIR/01-CONTEXT.md"

  # UAT appended
  grep -q "Bug found" "$PHASE_DIR/01-CONTEXT.md"
}

@test "init creates CONTEXT from UAT when no CONTEXT exists" {
  cat > "$PHASE_DIR/01-UAT.md" <<'EOF'
# UAT Report
- New issue
EOF

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]

  [ -f "$PHASE_DIR/01-CONTEXT.md" ]
  grep -q "^pre_seeded: true" "$PHASE_DIR/01-CONTEXT.md"
  grep -q "New issue" "$PHASE_DIR/01-CONTEXT.md"
}

@test "init is idempotent — does not duplicate UAT on second init" {
  cat > "$PHASE_DIR/01-CONTEXT.md" <<'EOF'
---
phase: 01
---

# Context
EOF
  cat > "$PHASE_DIR/01-UAT.md" <<'EOF'
# UAT
- Issue X
EOF

  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null

  # Second init should not re-append
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null

  count=$(grep -c "## UAT Remediation Issues" "$PHASE_DIR/01-CONTEXT.md")
  [ "$count" -eq 1 ]
}

@test "init without UAT file does not modify CONTEXT" {
  cat > "$PHASE_DIR/01-CONTEXT.md" <<'EOF'
---
phase: 01
---

# Context
EOF

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]

  # No pre_seeded added when there's no UAT report to append
  ! grep -q "pre_seeded" "$PHASE_DIR/01-CONTEXT.md"
}

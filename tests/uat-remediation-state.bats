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

@test "init major creates research stage" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "research" ]
  [ -f "$PHASE_DIR/.uat-remediation-stage" ]
  [ "$(cat "$PHASE_DIR/.uat-remediation-stage")" = "research" ]
}

@test "init minor creates fix stage" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "minor"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "fix" ]
  [ "$(cat "$PHASE_DIR/.uat-remediation-stage")" = "fix" ]
}

@test "init unknown severity defaults to research" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "unknown"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "research" ]
}

@test "advance major chain: research -> plan -> execute -> done" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "plan" ]

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

@test "advance from research goes to plan" {
  echo "research" > "$PHASE_DIR/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "plan" ]
}

@test "legacy plan stage still advances to execute" {
  # Backward compat: existing .uat-remediation-stage files with "plan"
  echo "plan" > "$PHASE_DIR/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "execute" ]
}

@test "get returns persisted stage after advance" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR" >/dev/null

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get "$PHASE_DIR"
  [ "$output" = "plan" ]
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

  # init emits CONTEXT.md content in output after ---CONTEXT--- separator
  echo "$output" | grep -q "^---CONTEXT---$"
  echo "$output" | grep -q "Issue 1: Something broken"
  echo "$output" | grep -q "pre_seeded: true"
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

  # Second init with same UAT should not duplicate
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null

  count=$(grep -c "## UAT Remediation Issues" "$PHASE_DIR/01-CONTEXT.md")
  [ "$count" -eq 1 ]
  # Content still present
  grep -q "Issue X" "$PHASE_DIR/01-CONTEXT.md"
}

@test "init replaces stale UAT content on subsequent remediation turn" {
  # Simulate first remediation turn: CONTEXT gets pre-seeded with round-01 UAT
  cat > "$PHASE_DIR/01-CONTEXT.md" <<'EOF'
---
phase: 01
title: Milestone UAT remediation
source_milestone: test-milestone
pre_seeded: true
---

This phase remediates unresolved UAT issues.

---

## UAT Remediation Issues

# Round 1 UAT
- Old issue from round 1
EOF

  # New UAT after re-verification (round 2) — different content
  cat > "$PHASE_DIR/01-UAT.md" <<'EOF'
# Round 2 UAT
- New issue A from round 2
- New issue B from round 2
EOF

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]

  # Old UAT content should be gone
  ! grep -q "Old issue from round 1" "$PHASE_DIR/01-CONTEXT.md"
  ! grep -q "Round 1 UAT" "$PHASE_DIR/01-CONTEXT.md"

  # New UAT content should be present
  grep -q "New issue A from round 2" "$PHASE_DIR/01-CONTEXT.md"
  grep -q "New issue B from round 2" "$PHASE_DIR/01-CONTEXT.md"

  # Original preamble preserved
  grep -q "This phase remediates unresolved UAT issues" "$PHASE_DIR/01-CONTEXT.md"
  grep -q "pre_seeded: true" "$PHASE_DIR/01-CONTEXT.md"

  # Only one UAT section
  count=$(grep -c "## UAT Remediation Issues" "$PHASE_DIR/01-CONTEXT.md")
  [ "$count" -eq 1 ]

  # init emits updated CONTEXT.md content with new UAT, not old
  echo "$output" | grep -q "^---CONTEXT---$"
  echo "$output" | grep -q "New issue A from round 2"
  ! echo "$output" | grep -q "Old issue from round 1"
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

  # No CONTEXT emitted in output when no UAT file exists
  ! echo "$output" | grep -q "^---CONTEXT---$"
}

# --- get-or-init tests ---

@test "get-or-init initializes when no state file exists" {
  cat > "$PHASE_DIR/01-UAT.md" <<'EOF'
# UAT Report
- Issue found
EOF

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "research" ]
  # State file was created
  [ -f "$PHASE_DIR/.uat-remediation-stage" ]
  [ "$(cat "$PHASE_DIR/.uat-remediation-stage")" = "research" ]
  # Plan metadata emitted
  echo "$output" | grep -q "^next_plan=01$"
  echo "$output" | grep -q "^research_path=$"
  echo "$output" | grep -q "^plan_path=$"
  # CONTEXT emitted after metadata
  echo "$output" | grep -q "^---CONTEXT---$"
  echo "$output" | grep -q "Issue found"
}

@test "get-or-init returns existing stage without side effects" {
  echo "plan" > "$PHASE_DIR/.uat-remediation-stage"
  cat > "$PHASE_DIR/01-UAT.md" <<'EOF'
# UAT Report
- Should not be emitted
EOF

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "plan" ]
  # Plan metadata emitted even on resume
  echo "$output" | grep -q "^next_plan=01$"
  echo "$output" | grep -q "^research_path=$"
  echo "$output" | grep -q "^plan_path=$"
  # State file unchanged
  [ "$(cat "$PHASE_DIR/.uat-remediation-stage")" = "plan" ]
  # No CONTEXT emitted on resume
  ! echo "$output" | grep -q "^---CONTEXT---$"
}

@test "get-or-init returns done when stage is done" {
  echo "done" > "$PHASE_DIR/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "done" ]
}

@test "get-or-init minor initializes fix stage" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "minor"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "fix" ]
  [ "$(cat "$PHASE_DIR/.uat-remediation-stage")" = "fix" ]
}

@test "get-or-init without severity exits with error" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR"
  [ "$status" -eq 1 ]
}

# --- plan metadata tests ---

@test "get-or-init next_plan=01 when no plans exist" {
  echo "research" > "$PHASE_DIR/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^next_plan=01$"
  echo "$output" | grep -q "^plan_path=$"
}

@test "get-or-init next_plan increments from existing plans" {
  echo "research" > "$PHASE_DIR/.uat-remediation-stage"
  touch "$PHASE_DIR/01-01-PLAN.md" "$PHASE_DIR/01-02-PLAN.md" "$PHASE_DIR/01-03-PLAN.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^next_plan=04$"
  echo "$output" | grep -q "^plan_path=$"
}

@test "get-or-init next_plan handles many plans (14 -> 15)" {
  echo "research" > "$PHASE_DIR/.uat-remediation-stage"
  for i in $(seq -w 1 14); do
    touch "$PHASE_DIR/01-${i}-PLAN.md"
  done

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^next_plan=15$"
}

@test "get-or-init research_path empty when no research exists" {
  echo "research" > "$PHASE_DIR/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^research_path=$"
  echo "$output" | grep -q "^plan_path=$"
}

@test "get-or-init research_path finds per-plan research" {
  echo "research" > "$PHASE_DIR/.uat-remediation-stage"
  touch "$PHASE_DIR/01-01-PLAN.md" "$PHASE_DIR/01-02-PLAN.md"
  touch "$PHASE_DIR/01-03-RESEARCH.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  # next_plan=03, per-plan research at 01-03-RESEARCH.md
  echo "$output" | grep -q "^next_plan=03$"
  echo "$output" | grep -q "^research_path=.*01-03-RESEARCH.md$"
  echo "$output" | grep -q "^plan_path=$"
}

@test "get-or-init research_path finds legacy research" {
  echo "research" > "$PHASE_DIR/.uat-remediation-stage"
  touch "$PHASE_DIR/01-RESEARCH.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^research_path=.*01-RESEARCH.md$"
}

@test "get-or-init per-plan research takes priority over legacy" {
  echo "plan" > "$PHASE_DIR/.uat-remediation-stage"
  touch "$PHASE_DIR/01-01-PLAN.md"
  touch "$PHASE_DIR/01-02-RESEARCH.md"
  touch "$PHASE_DIR/01-RESEARCH.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^next_plan=02$"
  echo "$output" | grep -q "^research_path=.*01-02-RESEARCH.md$"
  echo "$output" | grep -q "^plan_path=$"
}

@test "get-or-init metadata emitted before CONTEXT block" {
  cat > "$PHASE_DIR/01-UAT.md" <<'EOF'
# UAT Report
- Issue
EOF

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]

  # Find line numbers: metadata must come before ---CONTEXT---
  local meta_line context_line
  meta_line=$(echo "$output" | grep -n "^next_plan=" | head -1 | cut -d: -f1)
  context_line=$(echo "$output" | grep -n "^---CONTEXT---$" | head -1 | cut -d: -f1)
  [ -n "$meta_line" ]
  [ -n "$context_line" ]
  [ "$meta_line" -lt "$context_line" ]
}

# --- stage-aware plan metadata edge cases ---

@test "get-or-init plan stage: session died after writing plan — next_plan reuses research MM" {
  # Scenario: research created 01-04-RESEARCH.md, plan created 01-04-PLAN.md,
  # but session died before advancing to execute. Stage is still "plan".
  echo "plan" > "$PHASE_DIR/.uat-remediation-stage"
  touch "$PHASE_DIR/01-01-PLAN.md" "$PHASE_DIR/01-02-PLAN.md" "$PHASE_DIR/01-03-PLAN.md"
  touch "$PHASE_DIR/01-04-PLAN.md"
  touch "$PHASE_DIR/01-04-RESEARCH.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "plan" ]
  # Should use research MM=04, NOT highest_plan+1=05
  echo "$output" | grep -q "^next_plan=04$"
  echo "$output" | grep -q "^research_path=.*01-04-RESEARCH.md$"
  echo "$output" | grep -q "^plan_path=.*01-04-PLAN.md$"
}

@test "get-or-init plan stage: research done, plan not yet written" {
  # Scenario: research created 01-02-RESEARCH.md, session died before plan was written.
  echo "plan" > "$PHASE_DIR/.uat-remediation-stage"
  touch "$PHASE_DIR/01-01-PLAN.md"
  touch "$PHASE_DIR/01-02-RESEARCH.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  # Should use research MM=02
  echo "$output" | grep -q "^next_plan=02$"
  echo "$output" | grep -q "^research_path=.*01-02-RESEARCH.md$"
  echo "$output" | grep -q "^plan_path=$"
}

@test "get-or-init execute stage: uses research-plan correlation" {
  # Scenario: stage=execute, plan 04 exists with matching research
  echo "execute" > "$PHASE_DIR/.uat-remediation-stage"
  touch "$PHASE_DIR/01-01-PLAN.md" "$PHASE_DIR/01-02-PLAN.md" "$PHASE_DIR/01-03-PLAN.md"
  touch "$PHASE_DIR/01-04-PLAN.md"
  touch "$PHASE_DIR/01-04-RESEARCH.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^next_plan=04$"
  echo "$output" | grep -q "^plan_path=.*01-04-PLAN.md$"
}

@test "get-or-init research stage: always uses highest_plan+1 even with matching research" {
  # Scenario: second round of remediation. Plans 01+02 exist, research 02 exists.
  # Research stage should compute next_plan=03 (for the new remediation round),
  # NOT use research MM=02.
  echo "research" > "$PHASE_DIR/.uat-remediation-stage"
  touch "$PHASE_DIR/01-01-PLAN.md" "$PHASE_DIR/01-02-PLAN.md"
  touch "$PHASE_DIR/01-02-RESEARCH.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^next_plan=03$"
  echo "$output" | grep -q "^plan_path=$"
}

@test "get-or-init plan stage: no per-plan research falls back to plan+1" {
  # Scenario: only legacy research exists, no per-plan research files.
  # Falls back to highest_plan+1 since no per-plan research to correlate.
  echo "plan" > "$PHASE_DIR/.uat-remediation-stage"
  touch "$PHASE_DIR/01-01-PLAN.md" "$PHASE_DIR/01-02-PLAN.md"
  touch "$PHASE_DIR/01-RESEARCH.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^next_plan=03$"
  echo "$output" | grep -q "^research_path=.*01-RESEARCH.md$"
  echo "$output" | grep -q "^plan_path=$"
}

@test "get-or-init plan_path empty when plan does not exist" {
  echo "research" > "$PHASE_DIR/.uat-remediation-stage"
  touch "$PHASE_DIR/01-01-PLAN.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^next_plan=02$"
  echo "$output" | grep -q "^plan_path=$"
}

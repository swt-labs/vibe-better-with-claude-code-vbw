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

# --- Helper functions ---

# Read stage from new state file location
get_stage_from_file() {
  local sf="$PHASE_DIR/remediation/.uat-remediation-stage"
  if [ -f "$sf" ]; then
    grep '^stage=' "$sf" | head -1 | sed 's/^stage=//' | tr -d '[:space:]'
  else
    echo "none"
  fi
}

# Read round from new state file location
get_round_from_file() {
  local sf="$PHASE_DIR/remediation/.uat-remediation-stage"
  if [ -f "$sf" ]; then
    grep '^round=' "$sf" | head -1 | sed 's/^round=//' | tr -d '[:space:]'
  else
    echo ""
  fi
}

# --- Basic get/init/advance tests ---

@test "get returns none when no state file exists" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "init major creates research stage in remediation/ subdir" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "research" ]
  # State file at new location
  [ -f "$PHASE_DIR/remediation/.uat-remediation-stage" ]
  [ "$(get_stage_from_file)" = "research" ]
  [ "$(get_round_from_file)" = "01" ]
  # Legacy location should NOT exist
  [ ! -f "$PHASE_DIR/.uat-remediation-stage" ]
}

@test "init minor creates fix stage" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "minor"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "fix" ]
  [ "$(get_stage_from_file)" = "fix" ]
}

@test "init unknown severity defaults to research" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "unknown"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "research" ]
}

@test "init creates round directory" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null
  [ -d "$PHASE_DIR/remediation/P01-01-round" ]
}

@test "advance major chain: research -> plan -> execute -> verify -> uat -> done" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "plan" ]

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "execute" ]

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "verify" ]

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "uat" ]

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "done" ]
}

@test "advance minor chain: fix -> done" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "minor" >/dev/null

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "done" ]
}

@test "advance from done stays done" {
  mkdir -p "$PHASE_DIR/remediation"
  printf 'stage=done\nround=01\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "done" ]
}

@test "advance from research goes to plan" {
  mkdir -p "$PHASE_DIR/remediation"
  printf 'stage=research\nround=01\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "plan" ]
}

@test "get returns persisted stage after advance" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR" >/dev/null

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get "$PHASE_DIR"
  [ "$(echo "$output" | head -1)" = "plan" ]
}

@test "reset removes state file from both locations" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" reset "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
  [ ! -f "$PHASE_DIR/remediation/.uat-remediation-stage" ]
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

# --- needs-round command ---

@test "needs-round sets state and preserves round" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null
  # Advance through to uat
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR" >/dev/null  # plan
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR" >/dev/null  # execute
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR" >/dev/null  # verify
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR" >/dev/null  # uat

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "needs-round" ]
  echo "$output" | grep -q "^round=01$"
  [ "$(get_stage_from_file)" = "needs-round" ]
}

# --- CONTEXT.md pre-seeding tests ---

@test "init appends UAT to existing CONTEXT and adds pre_seeded frontmatter" {
  cat > "$PHASE_DIR/01-CONTEXT.md" <<'EOF'
---
phase: 01
title: Test phase
---

# Original Context

Some discussion content here.
EOF
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

  head -1 "$PHASE_DIR/01-CONTEXT.md" | grep -q '^---$'
  grep -q "^pre_seeded: true" "$PHASE_DIR/01-CONTEXT.md"
  grep -q "# Original Context" "$PHASE_DIR/01-CONTEXT.md"
  grep -q "No frontmatter here" "$PHASE_DIR/01-CONTEXT.md"
  grep -q "Bug found" "$PHASE_DIR/01-CONTEXT.md"
}

@test "init creates CONTEXT with P-prefix when no CONTEXT exists" {
  cat > "$PHASE_DIR/01-UAT.md" <<'EOF'
# UAT Report
- New issue
EOF

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]

  # P-prefix CONTEXT created (not legacy 01-CONTEXT.md)
  [ -f "$PHASE_DIR/P01-CONTEXT.md" ]
  grep -q "^pre_seeded: true" "$PHASE_DIR/P01-CONTEXT.md"
  grep -q "New issue" "$PHASE_DIR/P01-CONTEXT.md"
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
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null

  count=$(grep -c "## UAT Remediation Issues" "$PHASE_DIR/01-CONTEXT.md")
  [ "$count" -eq 1 ]
  grep -q "Issue X" "$PHASE_DIR/01-CONTEXT.md"
}

@test "init replaces stale UAT content on subsequent remediation turn" {
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

  cat > "$PHASE_DIR/01-UAT.md" <<'EOF'
# Round 2 UAT
- New issue A from round 2
- New issue B from round 2
EOF

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]

  ! grep -q "Old issue from round 1" "$PHASE_DIR/01-CONTEXT.md"
  ! grep -q "Round 1 UAT" "$PHASE_DIR/01-CONTEXT.md"
  grep -q "New issue A from round 2" "$PHASE_DIR/01-CONTEXT.md"
  grep -q "New issue B from round 2" "$PHASE_DIR/01-CONTEXT.md"
  grep -q "This phase remediates unresolved UAT issues" "$PHASE_DIR/01-CONTEXT.md"
  grep -q "pre_seeded: true" "$PHASE_DIR/01-CONTEXT.md"

  count=$(grep -c "## UAT Remediation Issues" "$PHASE_DIR/01-CONTEXT.md")
  [ "$count" -eq 1 ]

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

  ! grep -q "pre_seeded" "$PHASE_DIR/01-CONTEXT.md"
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
  # State file at new location
  [ -f "$PHASE_DIR/remediation/.uat-remediation-stage" ]
  [ "$(get_stage_from_file)" = "research" ]
  # Round metadata emitted (new format)
  echo "$output" | grep -q "^round=01$"
  echo "$output" | grep -q "^round_dir="
  echo "$output" | grep -q "^research_path=$"
  echo "$output" | grep -q "^plan_path=$"
  # CONTEXT emitted
  echo "$output" | grep -q "^---CONTEXT---$"
  echo "$output" | grep -q "Issue found"
}

@test "get-or-init returns existing stage without side effects" {
  mkdir -p "$PHASE_DIR/remediation"
  printf 'stage=plan\nround=01\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"
  cat > "$PHASE_DIR/01-UAT.md" <<'EOF'
# UAT Report
- Should not be emitted
EOF

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "plan" ]
  # Round metadata emitted even on resume
  echo "$output" | grep -q "^round=01$"
  echo "$output" | grep -q "^round_dir="
  echo "$output" | grep -q "^research_path="
  echo "$output" | grep -q "^plan_path="
  # State file unchanged
  [ "$(get_stage_from_file)" = "plan" ]
  # No CONTEXT emitted on resume
  ! echo "$output" | grep -q "^---CONTEXT---$"
}

@test "get-or-init returns done when stage is done" {
  mkdir -p "$PHASE_DIR/remediation"
  printf 'stage=done\nround=01\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "done" ]
}

@test "get-or-init minor initializes fix stage" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "minor"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "fix" ]
  [ "$(get_stage_from_file)" = "fix" ]
}

@test "get-or-init without severity exits with error" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR"
  [ "$status" -eq 1 ]
}

# --- Round metadata tests ---

@test "get-or-init round=01 with round_dir when no round dirs exist" {
  mkdir -p "$PHASE_DIR/remediation"
  printf 'stage=research\nround=01\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^round=01$"
  echo "$output" | grep -q "^round_dir=.*P01-01-round$"
  echo "$output" | grep -q "^research_path=$"
  echo "$output" | grep -q "^plan_path=$"
}

@test "get-or-init research_path finds P-prefix research in round dir" {
  mkdir -p "$PHASE_DIR/remediation/P01-01-round"
  printf 'stage=plan\nround=01\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"
  touch "$PHASE_DIR/remediation/P01-01-round/P01-R01-RESEARCH.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^research_path=.*P01-R01-RESEARCH.md$"
  echo "$output" | grep -q "^plan_path=$"
}

@test "get-or-init plan_path finds P-prefix plan in round dir" {
  mkdir -p "$PHASE_DIR/remediation/P01-01-round"
  printf 'stage=execute\nround=01\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"
  touch "$PHASE_DIR/remediation/P01-01-round/P01-R01-RESEARCH.md"
  touch "$PHASE_DIR/remediation/P01-01-round/P01-R01-PLAN.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^research_path=.*P01-R01-RESEARCH.md$"
  echo "$output" | grep -q "^plan_path=.*P01-R01-PLAN.md$"
}

@test "get-or-init round metadata emitted before CONTEXT block" {
  cat > "$PHASE_DIR/01-UAT.md" <<'EOF'
# UAT Report
- Issue
EOF

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]

  local meta_line context_line
  meta_line=$(echo "$output" | grep -n "^round=" | head -1 | cut -d: -f1)
  context_line=$(echo "$output" | grep -n "^---CONTEXT---$" | head -1 | cut -d: -f1)
  [ -n "$meta_line" ]
  [ -n "$context_line" ]
  [ "$meta_line" -lt "$context_line" ]
}

# --- needs-round -> get-or-init creates next round ---

@test "get-or-init creates next round when needs-round is set" {
  mkdir -p "$PHASE_DIR/remediation/P01-01-round"
  printf 'stage=needs-round\nround=01\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"
  cat > "$PHASE_DIR/01-UAT.md" <<'EOF'
# UAT Report
- Recurring issue
EOF
  cat > "$PHASE_DIR/01-CONTEXT.md" <<'EOF'
---
pre_seeded: true
---

## UAT Remediation Issues

Old UAT content
EOF

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "research" ]
  echo "$output" | grep -q "^round=02$"
  echo "$output" | grep -q "^round_dir=.*P01-02-round$"
  # Round 2 directory created
  [ -d "$PHASE_DIR/remediation/P01-02-round" ]
  # Stage file updated
  [ "$(get_stage_from_file)" = "research" ]
  [ "$(get_round_from_file)" = "02" ]
  # CONTEXT re-seeded with new UAT
  echo "$output" | grep -q "^---CONTEXT---$"
  echo "$output" | grep -q "Recurring issue"
}

# --- Legacy backward compatibility tests ---

@test "legacy single-word stage file still works for get" {
  echo "plan" > "$PHASE_DIR/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get "$PHASE_DIR"
  [ "$(echo "$output" | head -1)" = "plan" ]
}

@test "legacy single-word stage file still works for advance" {
  echo "plan" > "$PHASE_DIR/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "execute" ]
  # After advance, state file migrated to new location
  [ -f "$PHASE_DIR/remediation/.uat-remediation-stage" ]
  # Legacy file removed
  [ ! -f "$PHASE_DIR/.uat-remediation-stage" ]
}

@test "get-or-init reads legacy single-word state file" {
  echo "research" > "$PHASE_DIR/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "research" ]
  # Round defaults to 01 when no round info
  echo "$output" | grep -q "^round=01$"
}

@test "advance from legacy writes to new location and removes legacy" {
  echo "research" > "$PHASE_DIR/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "plan" ]
  [ -f "$PHASE_DIR/remediation/.uat-remediation-stage" ]
  [ ! -f "$PHASE_DIR/.uat-remediation-stage" ]
}

# --- Milestone path guard ---

@test "refuses to operate on milestone paths" {
  local milestone_phase="$TEST_TEMP_DIR/.vbw-planning/milestones/v1/phases/01-test"
  mkdir -p "$milestone_phase"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$milestone_phase" "major"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "refusing to operate on archived milestone path"
}

# --- Multi-round lifecycle integration ---

@test "full remediation lifecycle: init -> advance through -> needs-round -> new round" {
  cat > "$PHASE_DIR/01-UAT.md" <<'EOF'
# UAT Report
- Issue A
EOF

  # Init
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$(echo "$output" | head -1)" = "research" ]
  echo "$output" | grep -q "^round=01$"

  # Advance through full chain
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR" >/dev/null  # plan
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR" >/dev/null  # execute
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR" >/dev/null  # verify
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR" >/dev/null  # uat

  # UAT has issues — signal needs-round
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$(echo "$output" | head -1)" = "needs-round" ]

  # Next get-or-init creates round 02
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$(echo "$output" | head -1)" = "research" ]
  echo "$output" | grep -q "^round=02$"
  [ -d "$PHASE_DIR/remediation/P01-02-round" ]
  [ "$(get_stage_from_file)" = "research" ]
  [ "$(get_round_from_file)" = "02" ]
}

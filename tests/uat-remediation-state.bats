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

@test "init major creates research stage in round dir" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "research" ]
  [ -f "$PHASE_DIR/remediation/.uat-remediation-stage" ]
  grep -q "^stage=research$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  grep -q "^round=01$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  grep -q "^layout=round-dir$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  [ -d "$PHASE_DIR/remediation/round-01" ]
}

@test "init minor creates fix stage in round dir" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "minor"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "fix" ]
  grep -q "^stage=fix$" "$PHASE_DIR/remediation/.uat-remediation-stage"
}

@test "init unknown severity defaults to research" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "unknown"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "research" ]
}

@test "init removes legacy state file" {
  echo "research" > "$PHASE_DIR/.uat-remediation-stage"
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [ ! -f "$PHASE_DIR/.uat-remediation-stage" ]
  [ -f "$PHASE_DIR/remediation/.uat-remediation-stage" ]
}

@test "advance major chain: research -> plan -> execute -> done" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "plan" ]
  grep -q "^stage=plan$" "$PHASE_DIR/remediation/.uat-remediation-stage"

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

@test "advance from done transitions to verify" {
  mkdir -p "$PHASE_DIR/remediation"
  printf 'stage=done\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "verify" ]
  grep -q "^stage=verify$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  # Round is preserved
  grep -q "^round=01$" "$PHASE_DIR/remediation/.uat-remediation-stage"
}

@test "advance from verify stays at verify" {
  mkdir -p "$PHASE_DIR/remediation"
  printf 'stage=verify\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "verify" ]
}

@test "advance preserves round number" {
  mkdir -p "$PHASE_DIR/remediation"
  printf 'stage=research\nround=03\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "plan" ]
  grep -q "^round=03$" "$PHASE_DIR/remediation/.uat-remediation-stage"
}

@test "legacy state file at phase root is read correctly" {
  echo "research" > "$PHASE_DIR/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get "$PHASE_DIR"
  [ "$output" = "research" ]
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

@test "reset removes both state files" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null
  # Also put a legacy file to test both are removed
  echo "research" > "$PHASE_DIR/.uat-remediation-stage"

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

@test "init normalizes quoted phase/round in UAT frontmatter" {
  cat > "$PHASE_DIR/01-CONTEXT.md" <<'EOF'
---
phase: 01
---

# Context
EOF
  cat > "$PHASE_DIR/01-UAT.md" <<'EOF'
---
phase: "01"
round: "03"
severity: major
---

# UAT Report
- Quoted phase and round values
EOF

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]

  # Quoted values should be normalized to bare integers
  grep -q '^phase: 01$' "$PHASE_DIR/01-CONTEXT.md"
  grep -q '^round: 03$' "$PHASE_DIR/01-CONTEXT.md"
  # Should not contain quoted versions
  ! grep -q 'phase: "01"' "$PHASE_DIR/01-CONTEXT.md"
  ! grep -q 'round: "03"' "$PHASE_DIR/01-CONTEXT.md"
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
  # State file was created in round-dir location
  [ -f "$PHASE_DIR/remediation/.uat-remediation-stage" ]
  grep -q "^stage=research$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  grep -q "^round=01$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  # Round directory created
  [ -d "$PHASE_DIR/remediation/round-01" ]
  # Plan metadata emitted
  echo "$output" | grep -q "^round=01$"
  echo "$output" | grep -q "^round_dir=.*remediation/round-01$"
  echo "$output" | grep -q "^research_path=$"
  echo "$output" | grep -q "^plan_path=$"
  # CONTEXT emitted after metadata
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
  # Plan metadata emitted even on resume
  echo "$output" | grep -q "^round=01$"
  echo "$output" | grep -q "^round_dir=.*remediation/round-01$"
  echo "$output" | grep -q "^research_path=$"
  echo "$output" | grep -q "^plan_path=$"
  # State file unchanged
  grep -q "^stage=plan$" "$PHASE_DIR/remediation/.uat-remediation-stage"
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
  grep -q "^stage=fix$" "$PHASE_DIR/remediation/.uat-remediation-stage"
}

@test "get-or-init without severity exits with error" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR"
  [ "$status" -eq 1 ]
}

# --- round-dir plan metadata tests ---

@test "get-or-init round=01 and round_dir on fresh init" {
  mkdir -p "$PHASE_DIR/remediation"
  printf 'stage=research\nround=01\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^round=01$"
  echo "$output" | grep -q "^round_dir=.*remediation/round-01$"
  echo "$output" | grep -q "^plan_path=$"
}

@test "get-or-init research_path finds file in round dir" {
  mkdir -p "$PHASE_DIR/remediation/round-01"
  printf 'stage=research\nround=01\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"
  echo "# Research" > "$PHASE_DIR/remediation/round-01/R01-RESEARCH.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^research_path=.*remediation/round-01/R01-RESEARCH.md$"
}

@test "get-or-init plan_path finds file in round dir" {
  mkdir -p "$PHASE_DIR/remediation/round-01"
  printf 'stage=plan\nround=01\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"
  echo "# Plan" > "$PHASE_DIR/remediation/round-01/R01-PLAN.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^plan_path=.*remediation/round-01/R01-PLAN.md$"
}

@test "get-or-init research_path falls back to legacy phase root when layout=legacy" {
  mkdir -p "$PHASE_DIR/remediation"
  printf 'stage=research\nround=01\nlayout=legacy\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"
  touch "$PHASE_DIR/01-RESEARCH.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^research_path=.*01-RESEARCH.md$"
}

@test "get-or-init per-plan research at phase root found as legacy fallback when layout=legacy" {
  mkdir -p "$PHASE_DIR/remediation"
  printf 'stage=plan\nround=01\nlayout=legacy\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"
  touch "$PHASE_DIR/01-01-PLAN.md" "$PHASE_DIR/01-02-PLAN.md"
  touch "$PHASE_DIR/01-03-RESEARCH.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^research_path=.*01-03-RESEARCH.md$"
}

@test "get-or-init round-dir research takes priority over legacy" {
  mkdir -p "$PHASE_DIR/remediation/round-01"
  printf 'stage=plan\nround=01\nlayout=legacy\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"
  echo "# Round research" > "$PHASE_DIR/remediation/round-01/R01-RESEARCH.md"
  touch "$PHASE_DIR/01-RESEARCH.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^research_path=.*remediation/round-01/R01-RESEARCH.md$"
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
  meta_line=$(echo "$output" | grep -n "^round=" | head -1 | cut -d: -f1)
  context_line=$(echo "$output" | grep -n "^---CONTEXT---$" | head -1 | cut -d: -f1)
  [ -n "$meta_line" ]
  [ -n "$context_line" ]
  [ "$meta_line" -lt "$context_line" ]
}

# --- legacy state migration tests ---

@test "get-or-init migrates legacy state file to new location with layout=legacy" {
  echo "plan" > "$PHASE_DIR/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "plan" ]
  # Legacy file removed
  [ ! -f "$PHASE_DIR/.uat-remediation-stage" ]
  # New file created
  [ -f "$PHASE_DIR/remediation/.uat-remediation-stage" ]
  grep -q "^stage=plan$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  grep -q "^round=01$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  grep -q "^layout=legacy$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  # Round dir created
  [ -d "$PHASE_DIR/remediation/round-01" ]
}

@test "legacy migration enables phase-root fallback for research_path" {
  echo "research" > "$PHASE_DIR/.uat-remediation-stage"
  touch "$PHASE_DIR/01-RESEARCH.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  # Legacy migration sets layout=legacy, enabling phase-root fallback
  echo "$output" | grep -q "^research_path=.*01-RESEARCH.md$"
}

@test "fresh init ignores legacy phase-root files (brownfield regression)" {
  # Simulate brownfield: prior round left many plan/research files at phase root
  touch "$PHASE_DIR/01-01-PLAN.md" "$PHASE_DIR/01-02-PLAN.md" "$PHASE_DIR/01-15-PLAN.md"
  touch "$PHASE_DIR/01-13-RESEARCH.md" "$PHASE_DIR/01-15-RESEARCH.md"
  cat > "$PHASE_DIR/01-UAT.md" <<'EOF'
# UAT Report
- Issue from latest round
EOF

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  # Fresh init writes layout=round-dir — legacy phase-root files must NOT appear
  echo "$output" | grep -q "^research_path=$"
  echo "$output" | grep -q "^plan_path=$"
  grep -q "^layout=round-dir$" "$PHASE_DIR/remediation/.uat-remediation-stage"
}

@test "get-or-init fresh round ignores stale phase-root files" {
  # New-format state file with round-dir layout (created by init or needs-round)
  mkdir -p "$PHASE_DIR/remediation/round-01"
  printf 'stage=research\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"
  # Stale legacy files from prior completed rounds
  touch "$PHASE_DIR/01-15-PLAN.md" "$PHASE_DIR/01-15-RESEARCH.md"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  # Must NOT return stale phase-root files
  echo "$output" | grep -q "^research_path=$"
  echo "$output" | grep -q "^plan_path=$"
}

@test "legacy done stage migrates correctly" {
  echo "done" > "$PHASE_DIR/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "done" ]
}

# --- needs-round tests ---

@test "needs-round creates new round directory and resets to research" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null
  # Advance through to done
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR" >/dev/null
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR" >/dev/null
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR" >/dev/null

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "research" ]
  echo "$output" | grep -q "^round=02$"
  echo "$output" | grep -q "^round_dir=.*remediation/round-02$"
  [ -d "$PHASE_DIR/remediation/round-02" ]
  grep -q "^stage=research$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  grep -q "^round=02$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  grep -q "^layout=round-dir$" "$PHASE_DIR/remediation/.uat-remediation-stage"
}

@test "needs-round from legacy-only state creates remediation dir and round-02" {
  # Legacy state file at phase root — no remediation/ directory exists
  echo "done" > "$PHASE_DIR/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "research" ]
  # Legacy get_round() returns "01" → increment to "02"
  echo "$output" | grep -q "^round=02$"
  echo "$output" | grep -q "^round_dir=.*remediation/round-02$"
  # remediation/ dir and round-02 sub-dir created by mkdir -p
  [ -d "$PHASE_DIR/remediation/round-02" ]
  # New-format state file written with round-dir layout (new round = fresh start)
  [ -f "$PHASE_DIR/remediation/.uat-remediation-stage" ]
  grep -q "^stage=research$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  grep -q "^round=02$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  grep -q "^layout=round-dir$" "$PHASE_DIR/remediation/.uat-remediation-stage"
}

@test "get-or-init plan_path empty when plan does not exist in round dir" {
  mkdir -p "$PHASE_DIR/remediation/round-01"
  printf 'stage=research\nround=01\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get-or-init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^plan_path=$"
}

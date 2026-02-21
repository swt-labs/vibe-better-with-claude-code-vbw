#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  # Enable require_phase_discussion for all tests in this file
  local cfg="$TEST_TEMP_DIR/.vbw-planning/config.json"
  local tmp; tmp=$(mktemp)
  jq '.require_phase_discussion = true' "$cfg" > "$tmp" && mv "$tmp" "$cfg"

  # Create a completed phase 01 so suggest-next can detect progress
  local p1="$TEST_TEMP_DIR/.vbw-planning/phases/01-core"
  mkdir -p "$p1"
  printf -- '---\nphase: 01\nplan: 01-01\n---\n' > "$p1/01-01-PLAN.md"
  printf -- '---\nstatus: complete\ndeviations: 0\n---\n' > "$p1/01-01-SUMMARY.md"
  echo '# Project' > "$TEST_TEMP_DIR/.vbw-planning/PROJECT.md"
}

teardown() {
  teardown_temp_dir
}

# --- pre_seeded frontmatter detection ---

@test "suggest-next vibe routes pre-seeded phase to plan-from-UAT suggestion" {
  cd "$TEST_TEMP_DIR"
  local p2="$TEST_TEMP_DIR/.vbw-planning/phases/02-remediate"
  mkdir -p "$p2"
  cat > "$p2/02-CONTEXT.md" <<'EOF'
---
phase: 02
title: Milestone UAT remediation
pre_seeded: true
---
# Context
EOF

  run bash "$SCRIPTS_DIR/suggest-next.sh" vibe pass

  [ "$status" -eq 0 ]
  [[ "$output" == *"discussion pre-seeded from UAT"* ]]
  [[ "$output" != *"Discuss phase before planning"* ]]
}

@test "suggest-next vibe routes undiscussed phase to discuss suggestion" {
  cd "$TEST_TEMP_DIR"
  local p2="$TEST_TEMP_DIR/.vbw-planning/phases/02-build"
  mkdir -p "$p2"
  # No CONTEXT.md at all

  run bash "$SCRIPTS_DIR/suggest-next.sh" vibe pass

  [ "$status" -eq 0 ]
  [[ "$output" == *"Discuss phase before planning"* ]]
  [[ "$output" != *"discussion pre-seeded from UAT"* ]]
}

@test "suggest-next vibe routes user-discussed phase to continue suggestion" {
  cd "$TEST_TEMP_DIR"
  local p2="$TEST_TEMP_DIR/.vbw-planning/phases/02-build"
  mkdir -p "$p2"
  # User-discussed CONTEXT.md (no pre_seeded field)
  cat > "$p2/02-CONTEXT.md" <<'EOF'
---
phase: 02
title: Build the thing
---
# Context
EOF

  run bash "$SCRIPTS_DIR/suggest-next.sh" vibe pass

  [ "$status" -eq 0 ]
  [[ "$output" != *"Discuss phase before planning"* ]]
  [[ "$output" != *"discussion pre-seeded from UAT"* ]]
}

@test "suggest-next detects pre_seeded:true without space after colon" {
  cd "$TEST_TEMP_DIR"
  local p2="$TEST_TEMP_DIR/.vbw-planning/phases/02-remediate"
  mkdir -p "$p2"
  cat > "$p2/02-CONTEXT.md" <<'EOF'
---
phase: 02
pre_seeded:true
---
# Context
EOF

  run bash "$SCRIPTS_DIR/suggest-next.sh" vibe pass

  [ "$status" -eq 0 ]
  [[ "$output" == *"discussion pre-seeded from UAT"* ]]
}

@test "suggest-next detects pre_seeded: \"true\" with quotes" {
  cd "$TEST_TEMP_DIR"
  local p2="$TEST_TEMP_DIR/.vbw-planning/phases/02-remediate"
  mkdir -p "$p2"
  cat > "$p2/02-CONTEXT.md" <<'EOF'
---
phase: 02
pre_seeded: "true"
---
# Context
EOF

  run bash "$SCRIPTS_DIR/suggest-next.sh" vibe pass

  [ "$status" -eq 0 ]
  [[ "$output" == *"discussion pre-seeded from UAT"* ]]
}

@test "suggest-next ignores pre_seeded: true outside frontmatter" {
  cd "$TEST_TEMP_DIR"
  local p2="$TEST_TEMP_DIR/.vbw-planning/phases/02-build"
  mkdir -p "$p2"
  # pre_seeded: true appears but NOT in frontmatter
  cat > "$p2/02-CONTEXT.md" <<'EOF'
---
phase: 02
title: Build
---
# Context

pre_seeded: true
EOF

  run bash "$SCRIPTS_DIR/suggest-next.sh" vibe pass

  [ "$status" -eq 0 ]
  # Should NOT detect pre-seeded since it's outside frontmatter
  [[ "$output" != *"discussion pre-seeded from UAT"* ]]
}

# --- qa pass path ---

@test "suggest-next qa pass routes pre-seeded phase to plan-from-UAT suggestion" {
  cd "$TEST_TEMP_DIR"
  local p2="$TEST_TEMP_DIR/.vbw-planning/phases/02-remediate"
  mkdir -p "$p2"
  cat > "$p2/02-CONTEXT.md" <<'EOF'
---
phase: 02
pre_seeded: true
---
# Context
EOF

  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass

  [ "$status" -eq 0 ]
  [[ "$output" == *"discussion pre-seeded from UAT"* ]]
}

@test "suggest-next qa pass routes undiscussed phase to discuss suggestion" {
  cd "$TEST_TEMP_DIR"
  local p2="$TEST_TEMP_DIR/.vbw-planning/phases/02-build"
  mkdir -p "$p2"

  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass

  [ "$status" -eq 0 ]
  [[ "$output" == *"Discuss phase before planning"* ]]
}

# --- status path ---

@test "suggest-next status routes pre-seeded phase to plan-from-UAT suggestion" {
  cd "$TEST_TEMP_DIR"
  local p2="$TEST_TEMP_DIR/.vbw-planning/phases/02-remediate"
  mkdir -p "$p2"
  cat > "$p2/02-CONTEXT.md" <<'EOF'
---
phase: 02
pre_seeded: true
---
# Context
EOF

  run bash "$SCRIPTS_DIR/suggest-next.sh" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"discussion pre-seeded from UAT"* ]]
}

@test "suggest-next status routes undiscussed phase to discuss suggestion" {
  cd "$TEST_TEMP_DIR"
  local p2="$TEST_TEMP_DIR/.vbw-planning/phases/02-build"
  mkdir -p "$p2"

  run bash "$SCRIPTS_DIR/suggest-next.sh" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Discuss phase before planning"* ]]
}

# --- feature disabled ---

@test "suggest-next vibe skips pre-seeded routing when require_phase_discussion is false" {
  cd "$TEST_TEMP_DIR"
  # Disable the feature
  local cfg="$TEST_TEMP_DIR/.vbw-planning/config.json"
  local tmp; tmp=$(mktemp)
  jq '.require_phase_discussion = false' "$cfg" > "$tmp" && mv "$tmp" "$cfg"

  local p2="$TEST_TEMP_DIR/.vbw-planning/phases/02-remediate"
  mkdir -p "$p2"
  cat > "$p2/02-CONTEXT.md" <<'EOF'
---
phase: 02
pre_seeded: true
---
# Context
EOF

  run bash "$SCRIPTS_DIR/suggest-next.sh" vibe pass

  [ "$status" -eq 0 ]
  # With feature disabled, should not show pre-seeded or discuss hints
  [[ "$output" != *"discussion pre-seeded from UAT"* ]]
  [[ "$output" != *"Discuss phase before planning"* ]]
}

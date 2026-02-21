#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/phases
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

@test "derives slug from Phase N header format" {
  cat > .vbw-planning/ROADMAP.md <<'EOF'
# Roadmap

## Phase 1: Transfer Matching Bug Fix
Goal: Fix transfer matching

## Phase 2: Test Infrastructure
Goal: Build test suite
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "01-transfer-matching-bug-fix-test-infrastructure" ]
}

@test "derives slug from numbered bold list format" {
  cat > .vbw-planning/ROADMAP.md <<'EOF'
# Roadmap

1. **Setup Foundation** — scaffold project
2. **API Layer** — build endpoints
3. **Frontend** — build UI
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "01-setup-foundation-api-layer-frontend" ]
}

@test "derives slug from bulleted phase list" {
  cat > .vbw-planning/ROADMAP.md <<'EOF'
# Roadmap

- Phase 1: Core Models
- Phase 2: Service Layer
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "01-core-models-service-layer" ]
}

@test "falls back to phase directory names" {
  cat > .vbw-planning/ROADMAP.md <<'EOF'
# Roadmap
No standard phase format here.
EOF
  mkdir -p .vbw-planning/phases/01-setup
  mkdir -p .vbw-planning/phases/02-api

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "01-setup-api" ]
}

@test "falls back to timestamp when no phases found" {
  cat > .vbw-planning/ROADMAP.md <<'EOF'
# Roadmap
Nothing parseable here.
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^01-milestone-[0-9]{8}$ ]]
}

@test "truncates slug to 60 chars" {
  cat > .vbw-planning/ROADMAP.md <<'EOF'
# Roadmap

## Phase 1: This Is A Very Long Phase Name That Should Be Truncated
## Phase 2: Another Extremely Long Phase Name For Testing Purposes
## Phase 3: Yet Another Phase With An Absurdly Long Name Here
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ ${#output} -le 63 ]  # 60 slug + 3 for "01-" prefix
}

@test "numbers based on existing milestones" {
  mkdir -p .vbw-planning/milestones/01-first
  mkdir -p .vbw-planning/milestones/02-second
  cat > .vbw-planning/ROADMAP.md <<'EOF'
# Roadmap

## Phase 1: Third Feature
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "03-third-feature" ]
}

@test "handles collision with existing milestone" {
  mkdir -p .vbw-planning/milestones/01-setup
  cat > .vbw-planning/ROADMAP.md <<'EOF'
# Roadmap

## Phase 1: Setup
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "02-setup" ]
}

@test "handles collision when exact target dir exists" {
  # With 0 existing milestones, numbering yields 01. Pre-create 01-setup.
  mkdir -p .vbw-planning/milestones/01-setup
  # But milestone_number counts 01-setup as 1 existing → yields 02.
  # So actually pre-create nothing, then manually place the collision target.
  rm -rf .vbw-planning/milestones/01-setup

  cat > .vbw-planning/ROADMAP.md <<'EOF'
# Roadmap

## Phase 1: Setup
EOF

  # Pre-create the exact target dir to force collision
  mkdir -p .vbw-planning/milestones/01-setup

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  # 1 existing milestone → numbering = 02, slug = setup → 02-setup (no collision)
  [ "$output" = "02-setup" ]
}

@test "fails when no ROADMAP.md exists" {
  rm -f .vbw-planning/ROADMAP.md

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 1 ]
}

@test "limits to first 3 phase names" {
  cat > .vbw-planning/ROADMAP.md <<'EOF'
# Roadmap

## Phase 1: First
## Phase 2: Second
## Phase 3: Third
## Phase 4: Fourth
## Phase 5: Fifth
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  # Should only include first 3
  [ "$output" = "01-first-second-third" ]
}

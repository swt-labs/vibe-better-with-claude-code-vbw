#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

create_archived_milestone() {
  local name="${1:-test-milestone}"
  local milestone_dir=".vbw-planning/milestones/$name"
  mkdir -p "$milestone_dir/phases/01-setup" "$milestone_dir/phases/02-build"
  touch "$milestone_dir/phases/01-setup/01-01-PLAN.md"
  touch "$milestone_dir/phases/01-setup/01-01-SUMMARY.md"
  touch "$milestone_dir/phases/02-build/02-01-PLAN.md"
  touch "$milestone_dir/phases/02-build/02-01-SUMMARY.md"

  cat > "$milestone_dir/ROADMAP.md" <<'EOF'
# Roadmap
## Phase 1: Setup
## Phase 2: Build
EOF

  cat > "$milestone_dir/STATE.md" <<'EOF'
# VBW State

**Project:** Test Project
Phase: 2 of 2 (Build)
Status: complete

## Key Decisions
- Use REST API for backend
- PostgreSQL for data store

## Todos
- Upgrade deps after milestone
- [HIGH] Add monitoring dashboard
EOF

  cat > "$milestone_dir/SHIPPED.md" <<'EOF'
# Shipped
Date: 2026-02-15
Phases: 2
EOF
}

create_root_state() {
  cat > ".vbw-planning/STATE.md" <<'EOF'
# VBW State

**Project:** Test Project
Phase: -
Status: shipped

## Key Decisions
- Use REST API for backend

## Todos
- [HIGH] Add monitoring dashboard
- Write API docs
EOF
}

@test "merges todos with dedup (same item in both → one copy)" {
  create_archived_milestone "foundation"
  create_root_state

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  # Phases should be restored to root
  [ -d ".vbw-planning/phases/01-setup" ]
  [ -d ".vbw-planning/phases/02-build" ]

  # ROADMAP should be at root
  [ -f ".vbw-planning/ROADMAP.md" ]

  # STATE.md should exist with merged todos
  [ -f ".vbw-planning/STATE.md" ]

  # Deduplicated: "Add monitoring dashboard" appears in both → one copy
  local count
  count=$(grep -c 'Add monitoring dashboard' ".vbw-planning/STATE.md")
  [ "$count" -eq 1 ]

  # Items unique to each source should be present
  grep -q 'Upgrade deps after milestone' ".vbw-planning/STATE.md"
  grep -q 'Write API docs' ".vbw-planning/STATE.md"
}

@test "merges todos with disjoint items (all preserved)" {
  create_archived_milestone "foundation"

  # Root state with completely different todos
  cat > ".vbw-planning/STATE.md" <<'EOF'
# VBW State

**Project:** Test Project

## Todos
- New todo added post-archive
- Another new item
EOF

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  # All items from both sources preserved
  grep -q 'Upgrade deps after milestone' ".vbw-planning/STATE.md"
  grep -q 'Add monitoring dashboard' ".vbw-planning/STATE.md"
  grep -q 'New todo added post-archive' ".vbw-planning/STATE.md"
  grep -q 'Another new item' ".vbw-planning/STATE.md"
}

@test "merges decisions with dedup" {
  create_archived_milestone "foundation"
  create_root_state

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  # "Use REST API for backend" is in both → one copy
  local count
  count=$(grep -c 'Use REST API for backend' ".vbw-planning/STATE.md")
  [ "$count" -eq 1 ]

  # "PostgreSQL for data store" only in archived → preserved
  grep -q 'PostgreSQL for data store' ".vbw-planning/STATE.md"
}

@test "handles empty root STATE.md (no post-archive additions)" {
  create_archived_milestone "foundation"

  # Root state with empty sections
  cat > ".vbw-planning/STATE.md" <<'EOF'
# VBW State

**Project:** Test Project

## Todos
None.

## Key Decisions
None.
EOF

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  # Archived todos should be restored
  grep -q 'Upgrade deps after milestone' ".vbw-planning/STATE.md"
  grep -q 'Add monitoring dashboard' ".vbw-planning/STATE.md"
}

@test "handles missing root STATE.md (only archived copy)" {
  create_archived_milestone "foundation"
  # No root STATE.md at all

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  # Archived state becomes root
  [ -f ".vbw-planning/STATE.md" ]
  grep -q 'Upgrade deps after milestone' ".vbw-planning/STATE.md"
}

@test "cleans up milestone dir after unarchive" {
  create_archived_milestone "foundation"

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  # SHIPPED.md should be deleted
  [ ! -f ".vbw-planning/milestones/foundation/SHIPPED.md" ]

  # Milestone dir should be removed if empty
  [ ! -d ".vbw-planning/milestones/foundation" ]
}

@test "exits 1 on missing milestone dir" {
  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/nonexistent" ".vbw-planning"
  [ "$status" -eq 1 ]
}

@test "merges table-formatted decisions with list-formatted decisions" {
  create_archived_milestone "foundation"

  # Root state with table-formatted decisions
  cat > ".vbw-planning/STATE.md" <<'EOF'
# VBW State

**Project:** Test Project

## Key Decisions
| Use REST API for backend | 2026-02-15 | Performance requirements |
| Add caching layer | 2026-02-16 | Reduce latency |

## Todos
None.
EOF

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  # Table-format "Add caching layer" from root should survive merge
  grep -q 'caching layer' ".vbw-planning/STATE.md"
  grep -q '| Use REST API for backend | 2026-02-15 | Performance requirements |' ".vbw-planning/STATE.md"

  # List-format "PostgreSQL for data store" from archive should survive
  grep -q 'PostgreSQL for data store' ".vbw-planning/STATE.md"
}

@test "aborts when root phases/ has active work" {
  create_archived_milestone "foundation"
  mkdir -p ".vbw-planning/phases/01-current"
  echo "# Active plan" > ".vbw-planning/phases/01-current/PLAN.md"

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 1 ]
  [[ "$output" == *"root phases/ directory contains active milestone artifacts"* ]]

  # Root phases should be untouched
  [ -f ".vbw-planning/phases/01-current/PLAN.md" ]

  # Archived milestone should still exist
  [ -d ".vbw-planning/milestones/foundation/phases" ]
}

@test "aborts when root phases/ contains empty scoped milestone dirs" {
  create_archived_milestone "foundation"
  mkdir -p ".vbw-planning/phases/01-new-scope"
  cat > ".vbw-planning/ROADMAP.md" <<'EOF'
# Roadmap
## Phase 1: New Scope
EOF
  cat > ".vbw-planning/CONTEXT.md" <<'EOF'
# New Scope — Milestone Context

## Scope Boundary
Fresh scoped work
EOF

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 1 ]
  [[ "$output" == *"root phases/ directory contains active milestone artifacts"* ]]

  [ -d ".vbw-planning/phases/01-new-scope" ]
  [ -f ".vbw-planning/ROADMAP.md" ]
  [ -f ".vbw-planning/CONTEXT.md" ]
  [ -d ".vbw-planning/milestones/foundation/phases" ]
}

@test "aborts when root roadmap or context exists without phases" {
  create_archived_milestone "foundation"
  cat > ".vbw-planning/ROADMAP.md" <<'EOF'
# Roadmap
## Phase 1: New Scope
EOF
  cat > ".vbw-planning/CONTEXT.md" <<'EOF'
# New Scope — Milestone Context

## Scope Boundary
Fresh scoped work
EOF

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 1 ]
  [[ "$output" == *"root ROADMAP.md or CONTEXT.md exists"* ]]

  [ -f ".vbw-planning/ROADMAP.md" ]
  [ -f ".vbw-planning/CONTEXT.md" ]
  [ -d ".vbw-planning/milestones/foundation/phases" ]
}

@test "ignores hidden placeholder files in root phases/" {
  create_archived_milestone "foundation"
  mkdir -p ".vbw-planning/phases"
  touch ".vbw-planning/phases/.DS_Store"
  touch ".vbw-planning/phases/.gitkeep"

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  [ -d ".vbw-planning/phases/01-setup" ]
  [ -f ".vbw-planning/ROADMAP.md" ]
}

@test "ignores empty phase dirs when no roadmap or context exists" {
  create_archived_milestone "foundation"
  mkdir -p ".vbw-planning/phases/01-stale-empty"

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  [ -d ".vbw-planning/phases/01-setup" ]
  [ -f ".vbw-planning/ROADMAP.md" ]
}

@test "restores key decisions with canonical table header" {
  create_archived_milestone "foundation"

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  grep -q '^| Decision | Date | Rationale |$' ".vbw-planning/STATE.md"
  grep -q '^|----------|------|-----------|$' ".vbw-planning/STATE.md"
  grep -q 'Use REST API for backend' ".vbw-planning/STATE.md"
}

@test "unarchive ignores empty decision placeholders when merging real decisions" {
  create_archived_milestone "foundation"

  cat > ".vbw-planning/STATE.md" <<'EOF'
# State

**Project:** Test Project

## Key Decisions
- _(No decisions yet)_

## Todos
None.
EOF

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]
  ! grep -q '_(No decisions yet)_' ".vbw-planning/STATE.md"
  grep -q 'Use REST API for backend' ".vbw-planning/STATE.md"
}

@test "unarchive rewrites placeholder-only decisions to canonical empty table" {
  mkdir -p ".vbw-planning/milestones/empty/phases/01-setup"
  touch ".vbw-planning/milestones/empty/phases/01-setup/01-01-PLAN.md"
  touch ".vbw-planning/milestones/empty/phases/01-setup/01-01-SUMMARY.md"
  cat > ".vbw-planning/milestones/empty/ROADMAP.md" <<'EOF'
# Roadmap
## Phase 1: Setup
EOF
  cat > ".vbw-planning/milestones/empty/STATE.md" <<'EOF'
# State

**Project:** Test Project

## Key Decisions
- _(No decisions yet)_

## Todos
None.
EOF
  cat > ".vbw-planning/milestones/empty/SHIPPED.md" <<'EOF'
# Shipped
EOF

  cat > ".vbw-planning/STATE.md" <<'EOF'
# State

**Project:** Test Project

## Key Decisions
None.

## Todos
None.
EOF

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/empty" ".vbw-planning"
  [ "$status" -eq 0 ]
  grep -q '^| Decision | Date | Rationale |$' ".vbw-planning/STATE.md"
  grep -q '^| _(No decisions yet)_ | | |$' ".vbw-planning/STATE.md"
  ! grep -q '^- _(No decisions yet)_' ".vbw-planning/STATE.md"
  ! awk '
    /^## Key Decisions$/ { in_section=1; next }
    in_section && /^## / { in_section=0 }
    in_section { print }
  ' ".vbw-planning/STATE.md" | grep -q '^None\.$'
}

@test "dedups todos with varied priority tag formats" {
  create_archived_milestone "foundation"

  # Root state with same todo but different priority tag casing/format
  cat > ".vbw-planning/STATE.md" <<'EOF'
# VBW State

**Project:** Test Project

## Todos
- [high] Add monitoring dashboard
- [MEDIUM] Write integration tests

## Key Decisions
None.
EOF

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  # "[HIGH] Add monitoring dashboard" (archive) and "[high] Add monitoring dashboard" (root)
  # should dedup to one copy
  local count
  count=$(grep -c -i 'add monitoring dashboard' ".vbw-planning/STATE.md")
  [ "$count" -eq 1 ]

  # "[MEDIUM] Write integration tests" (root-only) should survive
  grep -q 'integration tests' ".vbw-planning/STATE.md"
}

@test "preserves root decisions when root uses legacy Decisions heading" {
  create_archived_milestone "foundation"

  cat > ".vbw-planning/STATE.md" <<'EOF'
# VBW State

**Project:** Test Project

## Decisions
- Keep production feature flag defaults conservative

## Todos
None.
EOF

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  grep -q 'PostgreSQL for data store' ".vbw-planning/STATE.md"
  grep -q 'feature flag defaults conservative' ".vbw-planning/STATE.md"
}

@test "merges decisions across Decisions and Key Decisions headings" {
  create_archived_milestone "foundation"

  cat > ".vbw-planning/milestones/foundation/STATE.md" <<'EOF'
# VBW State

**Project:** Test Project

## Decisions
- Use REST API for backend
- PostgreSQL for data store

## Todos
- Upgrade deps after milestone
EOF

  cat > ".vbw-planning/STATE.md" <<'EOF'
# VBW State

**Project:** Test Project

## Key Decisions
- Keep an append-only migration log

## Todos
None.
EOF

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  grep -q 'PostgreSQL for data store' ".vbw-planning/STATE.md"
  grep -q 'append-only migration log' ".vbw-planning/STATE.md"
}

@test "merges legacy Pending Todos subsection from root state" {
  create_archived_milestone "foundation"

  cat > ".vbw-planning/STATE.md" <<'EOF'
# VBW State

**Project:** Test Project

### Pending Todos
- Document migration edge-cases
EOF

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  grep -q 'Upgrade deps after milestone' ".vbw-planning/STATE.md"
  grep -q 'Document migration edge-cases' ".vbw-planning/STATE.md"
}

@test "merges compact table decisions without space after pipe" {
  create_archived_milestone "foundation"

  cat > ".vbw-planning/STATE.md" <<'EOF'
# VBW State

**Project:** Test Project

## Key Decisions
|Add caching layer|2026-02-16|Reduce latency|

## Todos
None.
EOF

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  grep -q 'Add caching layer' ".vbw-planning/STATE.md"
  grep -q 'PostgreSQL for data store' ".vbw-planning/STATE.md"
}

@test "preserves root blockers and codebase profile when unarchiving" {
  create_archived_milestone "foundation"

  cat > ".vbw-planning/STATE.md" <<'EOF'
# State

**Project:** Test Project

## Blockers
- Root blocker from active notes

## Codebase Profile
- Root codebase profile note
EOF

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]
  grep -q 'Root blocker from active notes' ".vbw-planning/STATE.md"
  grep -q 'Root codebase profile note' ".vbw-planning/STATE.md"
}

@test "unarchive does not preserve Blockers None placeholder alongside real blockers" {
  create_archived_milestone "foundation"

  cat > ".vbw-planning/milestones/foundation/STATE.md" <<'EOF'
# VBW State

**Project:** Test Project

## Key Decisions
- Use REST API for backend

## Todos
- Upgrade deps after milestone

## Blockers
None
EOF

  cat > ".vbw-planning/STATE.md" <<'EOF'
# State

**Project:** Test Project

## Blockers
- Root blocker from active notes
EOF

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]
  grep -q 'Root blocker from active notes' ".vbw-planning/STATE.md"
  ! awk '
    /^## Blockers$/ { in_section=1; next }
    in_section && /^## / { in_section=0 }
    in_section { print }
  ' ".vbw-planning/STATE.md" | grep -q '^None$'
}

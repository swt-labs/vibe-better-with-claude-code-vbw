#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

# Helper: create a realistic STATE.md with all sections
create_full_state() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
# State

**Project:** Test Project

## Current Phase
Phase: 3 of 3 (Final cleanup)
Plans: 2/2
Progress: 100%
Status: complete

## Decisions
- Enabled VBW init scaffolding + codebase map
- Use SwiftUI for all new views

## Todos
- Fix auth module regression (added 2026-02-10)
- [HIGH] Migrate to new API (added 2026-02-11)
- [low] Update README (added 2026-02-12)

## Blockers
None

## Activity Log
- 2026-02-12: Phase 3 built
- 2026-02-11: Phase 2 built
- 2026-02-10: Phase 1 built

## Codebase Profile
- Brownfield: true
- Tracked files (approx): 137
- Primary languages: Swift
EOF
}

# Helper: create STATE.md with Skills section (real-world format)
create_state_with_skills() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
# State

**Project:** Skills Project

## Current Phase
Phase: 2 of 2 (Polish)
Plans: 1/1
Progress: 100%
Status: complete

## Decisions
- Use Core Data

### Skills
**Installed:** swiftui-expert-skill, xcodebuildmcp-cli
**Suggested:** None
**Stack detected:** Swift (iOS)
**Registry available:** yes

## Todos
- Explore dark mode (added 2026-02-15)

## Blockers
None

## Activity Log
- 2026-02-15: Phase 2 built
EOF
}

# --- Unit tests for persist-state-after-ship.sh ---

@test "creates root STATE.md with project-level sections after ship" {
  cd "$TEST_TEMP_DIR"
  create_full_state ".vbw-planning/STATE.md"

  # Simulate what Ship mode does: move STATE.md to archive
  mkdir -p .vbw-planning/milestones/default
  cp .vbw-planning/STATE.md .vbw-planning/milestones/default/STATE.md

  # Run the script — it should create a new root STATE.md from the archived one
  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/default/STATE.md .vbw-planning/STATE.md "Test Project"
  [ "$status" -eq 0 ]

  # Root STATE.md should exist
  [ -f .vbw-planning/STATE.md ]

  # Should contain project-level sections
  grep -q "## Todos" .vbw-planning/STATE.md
  grep -q "Fix auth module regression" .vbw-planning/STATE.md
  grep -q "Migrate to new API" .vbw-planning/STATE.md
  grep -q "## Decisions" .vbw-planning/STATE.md
  grep -q "## Blockers" .vbw-planning/STATE.md
}

@test "excludes milestone-level sections from persisted STATE.md" {
  cd "$TEST_TEMP_DIR"
  create_full_state ".vbw-planning/STATE.md"

  mkdir -p .vbw-planning/milestones/default
  cp .vbw-planning/STATE.md .vbw-planning/milestones/default/STATE.md

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/default/STATE.md .vbw-planning/STATE.md "Test Project"
  [ "$status" -eq 0 ]

  # Should NOT contain milestone-specific data
  ! grep -q "## Current Phase" .vbw-planning/STATE.md
  ! grep -q "Phase: 3 of 3" .vbw-planning/STATE.md
  ! grep -q "## Activity Log" .vbw-planning/STATE.md
  ! grep -q "Phase 3 built" .vbw-planning/STATE.md
}

@test "preserves Codebase Profile section" {
  cd "$TEST_TEMP_DIR"
  create_full_state ".vbw-planning/STATE.md"

  mkdir -p .vbw-planning/milestones/default
  cp .vbw-planning/STATE.md .vbw-planning/milestones/default/STATE.md

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/default/STATE.md .vbw-planning/STATE.md "Test Project"
  [ "$status" -eq 0 ]

  grep -q "## Codebase Profile" .vbw-planning/STATE.md
  grep -q "Brownfield: true" .vbw-planning/STATE.md
  grep -q "Primary languages: Swift" .vbw-planning/STATE.md
}

@test "strips stale Skills subsection from Decisions during persist" {
  cd "$TEST_TEMP_DIR"
  create_state_with_skills ".vbw-planning/STATE.md"

  mkdir -p .vbw-planning/milestones/default
  cp .vbw-planning/STATE.md .vbw-planning/milestones/default/STATE.md

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/default/STATE.md .vbw-planning/STATE.md "Skills Project"
  [ "$status" -eq 0 ]

  # Decisions content should survive
  grep -q "## Decisions" .vbw-planning/STATE.md
  grep -q "Use Core Data" .vbw-planning/STATE.md
  # Skills subsection should be stripped
  ! grep -q "### Skills" .vbw-planning/STATE.md
  ! grep -q "swiftui-expert-skill" .vbw-planning/STATE.md
}

@test "handles STATE.md with no todos (None. placeholder)" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/milestones/default
  cat > ".vbw-planning/milestones/default/STATE.md" <<'EOF'
# State

**Project:** Empty Project

## Current Phase
Phase: 1 of 1 (Setup)
Plans: 1/1
Progress: 100%
Status: complete

## Decisions
- Initial setup

## Todos
None.

## Blockers
None

## Activity Log
- 2026-02-18: Phase 1 built
EOF

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/default/STATE.md .vbw-planning/STATE.md "Empty Project"
  [ "$status" -eq 0 ]

  [ -f .vbw-planning/STATE.md ]
  grep -q "## Todos" .vbw-planning/STATE.md
  grep -q "None." .vbw-planning/STATE.md
}

@test "fails gracefully when archived STATE.md does not exist" {
  cd "$TEST_TEMP_DIR"

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/default/STATE.md .vbw-planning/STATE.md "Test"
  [ "$status" -eq 1 ]
}

# --- Integration tests: session-start migration for brownfield ---

@test "session-start migration recovers root STATE.md from archived milestone" {
  cd "$TEST_TEMP_DIR"
  create_full_state ".vbw-planning/milestones/default/STATE.md"
  # No root STATE.md, no ACTIVE — simulates post-ship brownfield state

  # Run the migration script
  run bash "$SCRIPTS_DIR/migrate-orphaned-state.sh" .vbw-planning
  [ "$status" -eq 0 ]

  # Root STATE.md should now exist
  [ -f .vbw-planning/STATE.md ]

  # Should have project-level sections
  grep -q "## Todos" .vbw-planning/STATE.md
  grep -q "Fix auth module regression" .vbw-planning/STATE.md
}

@test "session-start migration is idempotent (skips if root STATE.md exists)" {
  cd "$TEST_TEMP_DIR"
  create_full_state ".vbw-planning/STATE.md"
  create_full_state ".vbw-planning/milestones/default/STATE.md"

  local before_hash
  before_hash=$(md5 -q .vbw-planning/STATE.md 2>/dev/null || md5sum .vbw-planning/STATE.md | cut -d' ' -f1)

  run bash "$SCRIPTS_DIR/migrate-orphaned-state.sh" .vbw-planning
  [ "$status" -eq 0 ]

  local after_hash
  after_hash=$(md5 -q .vbw-planning/STATE.md 2>/dev/null || md5sum .vbw-planning/STATE.md | cut -d' ' -f1)

  [ "$before_hash" = "$after_hash" ]
}

@test "session-start migration runs even with stale ACTIVE file present" {
  cd "$TEST_TEMP_DIR"
  create_full_state ".vbw-planning/milestones/m1/STATE.md"
  echo "m1" > .vbw-planning/ACTIVE

  run bash "$SCRIPTS_DIR/migrate-orphaned-state.sh" .vbw-planning
  [ "$status" -eq 0 ]

  # Should create root STATE.md — ACTIVE guard was removed
  [ -f .vbw-planning/STATE.md ]
}

@test "migration picks latest milestone by modification time" {
  cd "$TEST_TEMP_DIR"
  # z-old: alphabetically last but chronologically older
  mkdir -p .vbw-planning/milestones/z-old
  cat > ".vbw-planning/milestones/z-old/STATE.md" <<'EOF'
# State

**Project:** Test

## Todos
- Old todo from z-old (added 2026-01-01)

## Blockers
None
EOF
  touch -t 202602010000 ".vbw-planning/milestones/z-old/STATE.md"

  # a-new: alphabetically first but chronologically newer
  mkdir -p .vbw-planning/milestones/a-new
  cat > ".vbw-planning/milestones/a-new/STATE.md" <<'EOF'
# State

**Project:** Test

## Todos
- New todo from a-new (added 2026-02-15)

## Blockers
None
EOF
  touch -t 202602150000 ".vbw-planning/milestones/a-new/STATE.md"

  run bash "$SCRIPTS_DIR/migrate-orphaned-state.sh" .vbw-planning
  [ "$status" -eq 0 ]

  [ -f .vbw-planning/STATE.md ]
  # Should pick a-new (newer by mtime), not z-old (alphabetically later)
  grep -q "New todo from a-new" .vbw-planning/STATE.md
  ! grep -q "Old todo from z-old" .vbw-planning/STATE.md
}

# --- Finding 11: Additional edge-case coverage ---

# Finding 1/10: "## Key Decisions" heading variant (bootstrap-state.sh uses this)
@test "persist script handles '## Key Decisions' heading" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/milestones/m1
  cat > ".vbw-planning/milestones/m1/STATE.md" <<'EOF'
# State

**Project:** Key Dec Project

## Current Phase
Phase: 1 of 1
Status: complete

## Key Decisions
| Decision | Date | Rationale |
|----------|------|-----------|
| Use REST over GraphQL | 2026-02-14 | Simpler for MVP |

## Todos
- Write changelog (added 2026-02-14)

## Blockers
None

## Activity Log
- 2026-02-14: Phase 1 built
EOF

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/m1/STATE.md .vbw-planning/STATE.md "Key Dec Project"
  [ "$status" -eq 0 ]

  [ -f .vbw-planning/STATE.md ]
  # Should preserve either Decisions or Key Decisions heading
  grep -q "Decisions" .vbw-planning/STATE.md
  grep -q "Use REST over GraphQL" .vbw-planning/STATE.md
  # Should still have todos
  grep -q "Write changelog" .vbw-planning/STATE.md
  # Should NOT have milestone sections
  ! grep -q "## Current Phase" .vbw-planning/STATE.md
  ! grep -q "## Activity Log" .vbw-planning/STATE.md
}

# Finding 3: Trailing whitespace on headings
@test "persist script handles trailing whitespace on section headings" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/milestones/m1
  # Create STATE.md with trailing spaces/tabs on headings
  printf '# State\n\n**Project:** Whitespace Project\n\n## Current Phase\nPhase: 1 of 1\nStatus: complete\n\n## Todos \t \n- Trailing space todo (added 2026-02-14)\n\n## Blockers  \nNone\n\n## Activity Log\n- 2026-02-14: Done\n' \
    > ".vbw-planning/milestones/m1/STATE.md"

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/m1/STATE.md .vbw-planning/STATE.md "Whitespace Project"
  [ "$status" -eq 0 ]

  [ -f .vbw-planning/STATE.md ]
  grep -q "Trailing space todo" .vbw-planning/STATE.md
  grep -q "## Blockers" .vbw-planning/STATE.md
}

# Finding 5: migrate-orphaned-state.sh with milestones dir but no STATE.md files inside
@test "migration exits cleanly when milestones dir exists but contains no STATE.md" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/milestones/empty-milestone
  # No STATE.md inside the milestone dir

  run bash "$SCRIPTS_DIR/migrate-orphaned-state.sh" .vbw-planning
  [ "$status" -eq 0 ]

  # Should not create root STATE.md
  [ ! -f .vbw-planning/STATE.md ]
}

# Finding 7: bootstrap-state.sh preserves existing Todos across re-bootstrap
@test "bootstrap preserves existing todos from prior milestone" {
  cd "$TEST_TEMP_DIR"
  # Simulate a persisted root STATE.md with carried-forward todos
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State

**Project:** Carry Forward

## Decisions
- Use SwiftUI

## Todos
- Fix auth regression (added 2026-02-10)
- [HIGH] API migration (added 2026-02-11)

## Blockers
None
EOF

  # Bootstrap a new milestone — should carry forward existing todos
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    "$TEST_TEMP_DIR/.vbw-planning/STATE.md" "Carry Forward" "New Milestone" 2
  [ "$status" -eq 0 ]

  [ -f "$TEST_TEMP_DIR/.vbw-planning/STATE.md" ]
  # Existing todos should survive
  grep -q "Fix auth regression" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "API migration" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  # New milestone metadata should be present
  grep -q "New Milestone" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "Phase 1" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

# Finding 7: bootstrap-state.sh preserves existing Key Decisions
@test "bootstrap preserves existing decisions from prior milestone" {
  cd "$TEST_TEMP_DIR"
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State

**Project:** Decisions Test

## Key Decisions
| Decision | Date | Rationale |
|----------|------|-----------|
| REST API | 2026-02-10 | Simpler |

## Todos
None.

## Blockers
None
EOF

  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    "$TEST_TEMP_DIR/.vbw-planning/STATE.md" "Decisions Test" "Milestone 2" 3
  [ "$status" -eq 0 ]

  # Existing decisions should survive (under whatever heading bootstrap uses)
  grep -q "REST API" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "Simpler" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

# Finding 7: fresh bootstrap (no prior STATE.md) uses defaults
@test "bootstrap creates default todos and decisions when no prior state exists" {
  cd "$TEST_TEMP_DIR"
  # No existing STATE.md

  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    "$TEST_TEMP_DIR/.vbw-planning/STATE.md" "Fresh Project" "First Milestone" 2
  [ "$status" -eq 0 ]

  [ -f "$TEST_TEMP_DIR/.vbw-planning/STATE.md" ]
  grep -q "## Key Decisions" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "No decisions yet" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "## Todos" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "None." "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

# Finding 6: list-todos prefers root STATE.md over archived milestones
@test "list-todos reads from root STATE.md when both root and archived milestone exist" {
  cd "$TEST_TEMP_DIR"
  # Root STATE.md with project-level todos
  cat > ".vbw-planning/STATE.md" <<'EOF'
# State

**Project:** Split Brain Test

## Todos
- Root todo item (added 2026-02-15)

## Blockers
None
EOF

  # Archived milestone with different todos
  mkdir -p .vbw-planning/milestones/m2
  cat > ".vbw-planning/milestones/m2/STATE.md" <<'EOF'
# State

**Project:** Split Brain Test

## Todos
- Milestone-scoped todo (added 2026-02-16)

## Blockers
None
EOF

  run bash "$SCRIPTS_DIR/list-todos.sh"
  [ "$status" -eq 0 ]

  # Should find the root todo, not the milestone one
  echo "$output" | grep -q "Root todo item"
  ! echo "$output" | grep -q "Milestone-scoped todo"
}

# Finding 2: Empty sections get fallback placeholders instead of bare headings
@test "persist script uses fallback placeholders for empty sections" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/milestones/m1
  cat > ".vbw-planning/milestones/m1/STATE.md" <<'EOF'
# State

**Project:** Empty Sections

## Current Phase
Phase: 1 of 1
Status: complete

## Decisions

## Todos

## Blockers

## Activity Log
- 2026-02-18: Phase 1 built
EOF

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/m1/STATE.md .vbw-planning/STATE.md "Empty Sections"
  [ "$status" -eq 0 ]

  [ -f .vbw-planning/STATE.md ]
  # Should have fallback placeholders, not bare headings
  grep -q "No decisions yet" .vbw-planning/STATE.md
  grep -q "None\." .vbw-planning/STATE.md
}

# Duplicate ## Todos — second group's items should be merged into output
@test "persist script merges content from duplicate section headings" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/milestones/m1
  cat > ".vbw-planning/milestones/m1/STATE.md" <<'EOF'
# State

**Project:** Dup Headings

## Decisions
- decision one

## Todos

## Blockers
None

## Todos
- second section todo (added 2026-02-18)

## Activity Log
- done
EOF

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/m1/STATE.md .vbw-planning/STATE.md "Dup Headings"
  [ "$status" -eq 0 ]

  [ -f .vbw-planning/STATE.md ]
  # Should preserve the todo from the second ## Todos section
  grep -q "second section todo" .vbw-planning/STATE.md
}

# Case-insensitive heading matching
@test "persist script extracts sections with non-standard casing" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/milestones/m1
  cat > ".vbw-planning/milestones/m1/STATE.md" <<'EOF'
# State

**Project:** Casing Test

## decisions
- lowercase heading decision

## TODOS
- uppercase todo (added 2026-02-18)

## blockers
None

## Activity Log
- done
EOF

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/m1/STATE.md .vbw-planning/STATE.md "Casing Test"
  [ "$status" -eq 0 ]

  [ -f .vbw-planning/STATE.md ]
  grep -q "lowercase heading decision" .vbw-planning/STATE.md
  grep -q "uppercase todo" .vbw-planning/STATE.md
}

# Finding 5 (QA R4): Extra spaces between ## and heading word
@test "persist script handles extra spaces after ## in section headings" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/milestones/m1
  # Create STATE.md where headings have multiple spaces after ##
  cat > ".vbw-planning/milestones/m1/STATE.md" <<'EOF'
# State

**Project:** Spacing Test

##   Current Phase
Phase: 1 of 1
Status: complete

##   Decisions
- extra-space decision

##    Todos
- extra-space todo (added 2026-02-18)

##  Blockers
- blocker with two spaces

##   Activity Log
- done
EOF

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/m1/STATE.md .vbw-planning/STATE.md "Spacing Test"
  [ "$status" -eq 0 ]

  [ -f .vbw-planning/STATE.md ]
  grep -q "extra-space decision" .vbw-planning/STATE.md
  grep -q "extra-space todo" .vbw-planning/STATE.md
  grep -q "blocker with two spaces" .vbw-planning/STATE.md
  # Milestone sections should still be excluded
  ! grep -qi "Current Phase" .vbw-planning/STATE.md
  ! grep -qi "Activity Log" .vbw-planning/STATE.md
}

# Finding 5 (QA R4): bootstrap-state.sh also tolerates extra spaces
@test "bootstrap preserves todos with extra-space headings in existing STATE.md" {
  cd "$TEST_TEMP_DIR"
  # Create existing STATE.md with extra spaces in headings
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State

**Project:** Extra Space Bootstrap

##   Key Decisions
| Decision | Date | Rationale |
|----------|------|-----------|
| Use GraphQL | 2026-02-18 | Flexible |

##    Todos
- spaced heading todo (added 2026-02-18)

## Blockers
None
EOF

  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    "$TEST_TEMP_DIR/.vbw-planning/STATE.md" "Extra Space Bootstrap" "M2" 2
  [ "$status" -eq 0 ]

  [ -f "$TEST_TEMP_DIR/.vbw-planning/STATE.md" ]
  grep -q "spaced heading todo" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -q "Use GraphQL" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

# Finding 6 (QA R4): list-todos fallback picks most recent milestone by mtime
@test "list-todos fallback picks most recently modified milestone" {
  cd "$TEST_TEMP_DIR"
  # No root STATE.md, no ACTIVE — simulates fully-archived brownfield
  # z-old: alphabetically last but older
  mkdir -p .vbw-planning/milestones/z-old
  cat > ".vbw-planning/milestones/z-old/STATE.md" <<'EOF'
# State

**Project:** Test

## Todos
- Old stale todo from z-old (added 2026-01-01)

## Blockers
None
EOF
  touch -t 202602010000 ".vbw-planning/milestones/z-old/STATE.md"

  # a-new: alphabetically first but newer
  mkdir -p .vbw-planning/milestones/a-new
  cat > ".vbw-planning/milestones/a-new/STATE.md" <<'EOF'
# State

**Project:** Test

## Todos
- Fresh todo from a-new (added 2026-02-15)

## Blockers
None
EOF
  touch -t 202602150000 ".vbw-planning/milestones/a-new/STATE.md"

  run bash "$SCRIPTS_DIR/list-todos.sh"
  [ "$status" -eq 0 ]

  # Should pick a-new (newer by mtime), not z-old (alphabetically later)
  echo "$output" | grep -q "Fresh todo from a-new"
  ! echo "$output" | grep -q "Old stale todo from z-old"
}

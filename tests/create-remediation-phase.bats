#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  cd "$TEST_TEMP_DIR"
  git init --quiet
  git config user.email "test@test.com"
  git config user.name "Test"
  touch dummy && git add dummy && git commit -m "init" --quiet
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

@test "create-remediation-phase creates next numbered phase and copies source UAT" {
  mkdir -p .vbw-planning/phases/01-foundation
  mkdir -p .vbw-planning/milestones/02-archive/phases/08-cost-basis

  cat > .vbw-planning/milestones/02-archive/phases/08-cost-basis/08-UAT.md <<'EOF'
---
phase: 08
status: issues_found
---
Severity: major
EOF

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/02-archive/phases/08-cost-basis

  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^phase=02$'
  echo "$output" | grep -q '^phase_dir=.vbw-planning/phases/02-remediate-02-archive-cost-basis$'
  [ -f .vbw-planning/phases/02-remediate-02-archive-cost-basis/02-CONTEXT.md ]
  [ -f .vbw-planning/phases/02-remediate-02-archive-cost-basis/02-SOURCE-UAT.md ]
  # Gap 5: .remediated marker prevents re-triggering
  [ -f .vbw-planning/milestones/02-archive/phases/08-cost-basis/.remediated ]
}

@test "create-remediation-phase works when source UAT file is missing" {
  mkdir -p .vbw-planning/milestones/legacy/phases/03-api

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/legacy/phases/03-api

  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^phase=01$'
  echo "$output" | grep -q '^source_uat=none$'
}

@test "create-remediation-phase truncates slug to 60 chars" {
  mkdir -p .vbw-planning/milestones/01-very-long-milestone-name-that-goes-on-and-on-forever/phases/08-also-a-very-long-phase-name-that-keeps-going

  cat > ".vbw-planning/milestones/01-very-long-milestone-name-that-goes-on-and-on-forever/phases/08-also-a-very-long-phase-name-that-keeps-going/08-UAT.md" <<'EOF'
---
status: issues_found
---
EOF

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    ".vbw-planning/milestones/01-very-long-milestone-name-that-goes-on-and-on-forever/phases/08-also-a-very-long-phase-name-that-keeps-going"

  [ "$status" -eq 0 ]
  # Extract phase_dir from output and check slug length (excluding NN- prefix)
  phase_dir=$(echo "$output" | grep '^phase_dir=' | sed 's/^phase_dir=//')
  slug=$(basename "$phase_dir" | sed 's/^[0-9]*-//')
  slug_len=${#slug}
  [ "$slug_len" -le 60 ]
}

@test "create-remediation-phase writes .remediated marker with target dir" {
  mkdir -p .vbw-planning/milestones/01-arch/phases/03-api

  cat > .vbw-planning/milestones/01-arch/phases/03-api/03-UAT.md <<'EOF'
---
status: issues_found
---
EOF

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/01-arch/phases/03-api

  [ "$status" -eq 0 ]
  [ -f .vbw-planning/milestones/01-arch/phases/03-api/.remediated ]
  # Marker contains the target remediation phase dir
  grep -q 'phases/01-remediate' .vbw-planning/milestones/01-arch/phases/03-api/.remediated
}

@test "create-remediation-phase is idempotent for already-remediated source phase" {
  mkdir -p .vbw-planning/milestones/01-arch/phases/03-api

  cat > .vbw-planning/milestones/01-arch/phases/03-api/03-UAT.md <<'EOF'
---
status: issues_found
---
EOF

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/01-arch/phases/03-api
  [ "$status" -eq 0 ]
  first_phase_dir=$(echo "$output" | grep '^phase_dir=' | sed 's/^phase_dir=//')

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/01-arch/phases/03-api
  [ "$status" -eq 0 ]
  second_phase_dir=$(echo "$output" | grep '^phase_dir=' | sed 's/^phase_dir=//')

  [ "$first_phase_dir" = "$second_phase_dir" ]
  # Ensure no second numbered remediation phase directory was created.
  [ -d .vbw-planning/phases/01-remediate-01-arch-api ]
  [ ! -d .vbw-planning/phases/02-remediate-01-arch-api ]
}

@test "create-remediation-phase writes UAT content verbatim without shell expansion" {
  mkdir -p .vbw-planning/milestones/01-arch/phases/03-api

  # UAT content with shell metacharacters that must NOT be expanded
  cat > .vbw-planning/milestones/01-arch/phases/03-api/03-UAT.md <<'TESTEOF'
---
status: issues_found
---
## Issue 1
The `$HOME` variable and `$(whoami)` command in the code snippet:
```bash
echo $PATH
result=$(ls -la)
```
User $USER saw errors with backtick `command` syntax.
TESTEOF

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/01-arch/phases/03-api

  [ "$status" -eq 0 ]
  ctx_file=".vbw-planning/phases/01-remediate-01-arch-api/01-CONTEXT.md"
  [ -f "$ctx_file" ]

  # Verify shell metacharacters were preserved verbatim
  grep -qF '$(whoami)' "$ctx_file"
  grep -qF '$HOME' "$ctx_file"
  grep -qF '$PATH' "$ctx_file"
  grep -qF '$(ls -la)' "$ctx_file"
  grep -qF '$USER' "$ctx_file"
}

@test "create-remediation-phase CONTEXT.md has pre_seeded frontmatter" {
  mkdir -p .vbw-planning/milestones/01-arch/phases/03-api

  cat > .vbw-planning/milestones/01-arch/phases/03-api/03-UAT.md <<'EOF'
---
status: issues_found
---
Minor issue found.
EOF

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/01-arch/phases/03-api

  [ "$status" -eq 0 ]
  ctx_file=".vbw-planning/phases/01-remediate-01-arch-api/01-CONTEXT.md"
  [ -f "$ctx_file" ]
  grep -q '^pre_seeded: true' "$ctx_file"
}

@test "create-remediation-phase seeds ROADMAP.md and STATE.md for remediation flow" {
  mkdir -p .vbw-planning/milestones/01-arch/phases/03-api
  cat > .vbw-planning/PROJECT.md <<'EOF'
# Options Wheel Tracker
EOF

  cat > .vbw-planning/milestones/01-arch/phases/03-api/03-UAT.md <<'EOF'
---
status: issues_found
---
Severity: major
EOF

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/01-arch/phases/03-api

  [ "$status" -eq 0 ]
  [ -f .vbw-planning/ROADMAP.md ]
  [ -f .vbw-planning/STATE.md ]

  grep -q '^# UAT Remediation Roadmap$' .vbw-planning/ROADMAP.md
  grep -q '^\*\*Milestone:\*\* UAT Remediation$' .vbw-planning/STATE.md
  grep -q '^\*\*Project:\*\* Options Wheel Tracker$' .vbw-planning/STATE.md
}

@test "create-remediation-phase keeps remediation ROADMAP.md in sync across multiple phases" {
  mkdir -p .vbw-planning/milestones/01-arch/phases/03-api
  mkdir -p .vbw-planning/milestones/01-arch/phases/04-ui

  cat > .vbw-planning/milestones/01-arch/phases/03-api/03-UAT.md <<'EOF'
---
status: issues_found
---
Severity: major
EOF

  cat > .vbw-planning/milestones/01-arch/phases/04-ui/04-UAT.md <<'EOF'
---
status: issues_found
---
Severity: major
EOF

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/01-arch/phases/03-api
  [ "$status" -eq 0 ]

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/01-arch/phases/04-ui
  [ "$status" -eq 0 ]

  [ -f .vbw-planning/ROADMAP.md ]
  [ "$(grep -Ec '^## Phase [0-9]+:' .vbw-planning/ROADMAP.md | tr -d ' ')" -eq 2 ]
  grep -q '^| 1 | Pending | 0 | 0 | 0 |$' .vbw-planning/ROADMAP.md
  grep -q '^| 2 | Pending | 0 | 0 | 0 |$' .vbw-planning/ROADMAP.md
  grep -q '^- \*\*Phase 2:\*\* Pending$' .vbw-planning/STATE.md
}

@test "create-remediation-phase preserves existing ROADMAP.md progress on re-entry" {
  mkdir -p .vbw-planning/milestones/01-arch/phases/03-api
  cat > .vbw-planning/PROJECT.md <<'EOF'
# Test Project
EOF

  cat > .vbw-planning/milestones/01-arch/phases/03-api/03-UAT.md <<'EOF'
---
status: issues_found
---
Severity: major
EOF

  # First invocation creates the remediation phase
  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/01-arch/phases/03-api
  [ "$status" -eq 0 ]

  # Simulate progress by editing ROADMAP.md progress row
  sed -i.bak 's/| 1 | Pending | 0 | 0 | 0 |/| 1 | In Progress | 2 | 5 | 3 |/' .vbw-planning/ROADMAP.md && rm -f .vbw-planning/ROADMAP.md.bak

  # Re-entry (idempotent): should preserve progress
  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/01-arch/phases/03-api
  [ "$status" -eq 0 ]

  # Progress row must be preserved, not reset
  grep -q '^| 1 | In Progress | 2 | 5 | 3 |$' .vbw-planning/ROADMAP.md
  ! grep -q '^| 1 | Pending | 0 | 0 | 0 |$' .vbw-planning/ROADMAP.md
}

@test "create-remediation-phase preserves phase 1 progress when adding phase 2" {
  mkdir -p .vbw-planning/milestones/01-arch/phases/03-api
  mkdir -p .vbw-planning/milestones/01-arch/phases/04-ui
  cat > .vbw-planning/PROJECT.md <<'EOF'
# Test Project
EOF

  cat > .vbw-planning/milestones/01-arch/phases/03-api/03-UAT.md <<'EOF'
---
status: issues_found
---
Severity: major
EOF

  cat > .vbw-planning/milestones/01-arch/phases/04-ui/04-UAT.md <<'EOF'
---
status: issues_found
---
Severity: major
EOF

  # Create phase 1
  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/01-arch/phases/03-api
  [ "$status" -eq 0 ]

  # Simulate progress on phase 1
  sed -i.bak 's/| 1 | Pending | 0 | 0 | 0 |/| 1 | Complete | 3 | 8 | 5 |/' .vbw-planning/ROADMAP.md && rm -f .vbw-planning/ROADMAP.md.bak
  # Simulate state progress
  sed -i.bak 's/Phase 1:\*\* Pending planning/Phase 1:** Complete/' .vbw-planning/STATE.md && rm -f .vbw-planning/STATE.md.bak

  # Create phase 2 — should NOT clobber phase 1 progress
  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/01-arch/phases/04-ui
  [ "$status" -eq 0 ]

  # Phase 1 progress preserved in ROADMAP.md
  grep -q '^| 1 | Complete | 3 | 8 | 5 |$' .vbw-planning/ROADMAP.md
  # Phase 2 added as Pending
  grep -q '^| 2 | Pending | 0 | 0 | 0 |$' .vbw-planning/ROADMAP.md
  # Phase 1 status preserved in STATE.md
  grep -q '^- \*\*Phase 1:\*\* Complete$' .vbw-planning/STATE.md
  # Phase 2 added as Pending in STATE.md
  grep -q '^- \*\*Phase 2:\*\* Pending$' .vbw-planning/STATE.md
}

@test "create-remediation-phase preserves non-canonical ROADMAP progress row formats" {
  mkdir -p .vbw-planning/milestones/01-arch/phases/03-api

  cat > .vbw-planning/milestones/01-arch/phases/03-api/03-UAT.md <<'EOF'
---
status: issues_found
---
Severity: major
EOF

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/01-arch/phases/03-api
  [ "$status" -eq 0 ]

  # Simulate brownfield formatting variance: leading spaces + zero-padded phase id
  sed -i.bak 's/| 1 | Pending | 0 | 0 | 0 |/  | 01 | In Progress | 2 | 5 | 3 |/' .vbw-planning/ROADMAP.md && rm -f .vbw-planning/ROADMAP.md.bak

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/01-arch/phases/03-api
  [ "$status" -eq 0 ]

  grep -q '^  | 01 | In Progress | 2 | 5 | 3 |$' .vbw-planning/ROADMAP.md
  ! grep -q '^| 1 | Pending | 0 | 0 | 0 |$' .vbw-planning/ROADMAP.md
}

@test "create-remediation-phase repairs missing STATE phase bullets for remediation milestone" {
  mkdir -p .vbw-planning/milestones/01-arch/phases/03-api

  cat > .vbw-planning/milestones/01-arch/phases/03-api/03-UAT.md <<'EOF'
---
status: issues_found
---
Severity: major
EOF

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/01-arch/phases/03-api
  [ "$status" -eq 0 ]

  # Simulate malformed/brownfield STATE.md: remediation milestone, no phase bullets.
  cat > .vbw-planning/STATE.md <<'EOF'
# VBW State

**Project:** Test Project
**Milestone:** UAT Remediation

## Phase Status

## Key Decisions
| Decision | Date | Rationale |
|----------|------|-----------|
| _(No decisions yet)_ | | |
EOF

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/01-arch/phases/03-api

  [ "$status" -eq 0 ]
  [[ "$output" != *"integer expression expected"* ]]
  grep -q '^- \*\*Phase 1:\*\* Pending$' .vbw-planning/STATE.md
}

@test "create-remediation-phase prefers canonical UAT over SOURCE-UAT" {
  mkdir -p .vbw-planning/phases/01-foundation
  mkdir -p .vbw-planning/milestones/02-archive/phases/05-api

  # SOURCE-UAT (copy from earlier remediation) — should be skipped
  cat > .vbw-planning/milestones/02-archive/phases/05-api/05-SOURCE-UAT.md <<'EOF'
---
phase: 05
status: issues_found
---
Old stale issues
EOF

  # Canonical UAT — should be selected
  cat > .vbw-planning/milestones/02-archive/phases/05-api/05-UAT.md <<'EOF'
---
phase: 05
status: issues_found
---
Real issues here
EOF

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/02-archive/phases/05-api

  [ "$status" -eq 0 ]
  # SOURCE-UAT copy in target should contain content from canonical UAT, not SOURCE-UAT
  grep -q 'Real issues here' .vbw-planning/phases/02-*/02-SOURCE-UAT.md
  ! grep -q 'Old stale issues' .vbw-planning/phases/02-*/02-SOURCE-UAT.md
}

@test "create-remediation-phase skips SOURCE-UAT-only dir gracefully" {
  mkdir -p .vbw-planning/phases/01-foundation
  mkdir -p .vbw-planning/milestones/02-archive/phases/05-api

  # Only a SOURCE-UAT exists — no canonical
  cat > .vbw-planning/milestones/02-archive/phases/05-api/05-SOURCE-UAT.md <<'EOF'
---
phase: 05
status: issues_found
---
Old stale issues
EOF

  run bash "$SCRIPTS_DIR/create-remediation-phase.sh" \
    .vbw-planning \
    .vbw-planning/milestones/02-archive/phases/05-api

  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^source_uat=none$'
  # CONTEXT.md should note no UAT report found
  grep -q 'No UAT report found' .vbw-planning/phases/02-*/02-CONTEXT.md
}

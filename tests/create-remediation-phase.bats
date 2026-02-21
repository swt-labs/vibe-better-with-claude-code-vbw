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
  # Ensure no second remediation phase directory was created.
  [ "$(find .vbw-planning/phases -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" -eq 1 ]
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
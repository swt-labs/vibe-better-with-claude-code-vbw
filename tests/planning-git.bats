#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir

  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.name "VBW Test"
  git config user.email "vbw-test@example.com"

  echo "seed" > README.md
  git add README.md
  git commit -q -m "chore(init): seed"
}

teardown() {
  teardown_temp_dir
}

@test "sync-ignore adds .vbw-planning to root gitignore when planning_tracking=ignore" {
  cat > .vbw-planning/config.json <<'EOF'
{
  "planning_tracking": "ignore",
  "auto_push": "never"
}
EOF

  run bash "$SCRIPTS_DIR/planning-git.sh" sync-ignore .vbw-planning/config.json
  [ "$status" -eq 0 ]

  run grep -qx '\.vbw-planning/' .gitignore
  [ "$status" -eq 0 ]
}

@test "sync-ignore removes root ignore and writes transient planning ignore when commit mode" {
  cat > .gitignore <<'EOF'
.vbw-planning/
EOF

  cat > .vbw-planning/config.json <<'EOF'
{
  "planning_tracking": "commit",
  "auto_push": "never"
}
EOF

  run bash "$SCRIPTS_DIR/planning-git.sh" sync-ignore .vbw-planning/config.json
  [ "$status" -eq 0 ]

  run grep -qx '\.vbw-planning/' .gitignore
  [ "$status" -ne 0 ]

  run grep -q '^\.execution-state\.json$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]

  run grep -q '^\.context-\*\.md$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]
}

@test "sync-ignore includes all transient runtime artifacts in commit mode" {
  cat > .vbw-planning/config.json <<'EOF'
{
  "planning_tracking": "commit",
  "auto_push": "never"
}
EOF

  run bash "$SCRIPTS_DIR/planning-git.sh" sync-ignore .vbw-planning/config.json
  [ "$status" -eq 0 ]

  # Session & agent tracking
  run grep -q '^\.vbw-session$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]
  run grep -q '^\.agent-pids$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]
  run grep -q '^\.active-agent$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]
  run grep -q '^\.active-agent-count$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]
  run grep -q '^\.active-agent-count\.lock$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]

  # Metrics & cost
  run grep -q '^\.metrics/$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]
  run grep -q '^\.cost-ledger\.json$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]

  # Cache, artifacts, events, snapshots
  run grep -q '^\.cache/$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]
  run grep -q '^\.artifacts/$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]
  run grep -q '^\.events/$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]
  run grep -q '^\.snapshots/$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]

  # Logging & markers
  run grep -q '^\.hook-errors\.log$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]
  run grep -q '^\.compaction-marker$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]
  run grep -q '^\.session-log\.jsonl$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]

  # Codebase mapping
  run grep -q '^codebase/$' .vbw-planning/.gitignore
  [ "$status" -eq 0 ]
}

@test "commit-boundary excludes transient files from commit" {
  cat > .vbw-planning/config.json <<'EOF'
{
  "planning_tracking": "commit",
  "auto_push": "never"
}
EOF

  # Create a legitimate planning artifact
  cat > .vbw-planning/STATE.md <<'EOF'
# State
Updated
EOF

  # Create transient runtime files that should be excluded
  echo "12345" > .vbw-planning/.agent-pids
  echo "session-abc" > .vbw-planning/.vbw-session
  echo "lead" > .vbw-planning/.active-agent
  mkdir -p .vbw-planning/.metrics
  echo '{}' > .vbw-planning/.metrics/run-metrics.jsonl

  run bash "$SCRIPTS_DIR/planning-git.sh" commit-boundary "phase complete" .vbw-planning/config.json
  [ "$status" -eq 0 ]

  # STATE.md should be committed
  run git show HEAD -- .vbw-planning/STATE.md
  [ "$status" -eq 0 ]

  # Transient files should NOT be committed
  run git show HEAD -- .vbw-planning/.agent-pids
  [ "$output" = "" ] || [[ "$output" != *"12345"* ]]
  run git show HEAD -- .vbw-planning/.vbw-session
  [ "$output" = "" ] || [[ "$output" != *"session-abc"* ]]
}

@test "commit-boundary creates planning artifacts commit in commit mode" {
  cat > .vbw-planning/config.json <<'EOF'
{
  "planning_tracking": "commit",
  "auto_push": "never"
}
EOF

  cat > .vbw-planning/STATE.md <<'EOF'
# State

Updated
EOF

  cat > CLAUDE.md <<'EOF'
# CLAUDE

Updated
EOF

  run bash "$SCRIPTS_DIR/planning-git.sh" commit-boundary "bootstrap project" .vbw-planning/config.json
  [ "$status" -eq 0 ]

  run git log -1 --pretty=%s
  [ "$status" -eq 0 ]
  [ "$output" = "chore(vbw): bootstrap project" ]
}

@test "commit-boundary is no-op in manual mode" {
  cat > .vbw-planning/config.json <<'EOF'
{
  "planning_tracking": "manual",
  "auto_push": "never"
}
EOF

  cat > .vbw-planning/STATE.md <<'EOF'
# State

Updated
EOF

  BEFORE=$(git rev-list --count HEAD)

  run bash "$SCRIPTS_DIR/planning-git.sh" commit-boundary "phase update" .vbw-planning/config.json
  [ "$status" -eq 0 ]

  AFTER=$(git rev-list --count HEAD)
  [ "$BEFORE" = "$AFTER" ]
}
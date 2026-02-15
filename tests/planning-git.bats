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

  expected_entries=(
    '.execution-state.json'
    '.execution-state.json.tmp'
    '.context-*.md'
    '.contracts/'
    '.locks/'
    '.token-state/'
    '.vbw-session'
    '.active-agent'
    '.active-agent-count'
    '.active-agent-count.lock/'
    '.agent-pids'
    '.metrics/'
    '.cost-ledger.json'
    '.cache/'
    '.artifacts/'
    '.events/'
    '.event-log.jsonl'
    '.snapshots/'
    '.hook-errors.log'
    '.compaction-marker'
    '.session-log.jsonl'
    '.session-log.jsonl.tmp'
    '.notification-log.jsonl'
    '.watchdog-pid'
    '.watchdog.log'
    '.claude-md-migrated'
    '.tmux-mode-patched'
    '.baselines/'
    'codebase/'
  )

  for entry in "${expected_entries[@]}"; do
    run grep -Fqx "$entry" .vbw-planning/.gitignore
    [ "$status" -eq 0 ]
  done

  actual_entries="$(grep -Ev '^(#|$)' .vbw-planning/.gitignore | sort)"
  expected_entries_sorted="$(printf '%s\n' "${expected_entries[@]}" | sort)"
  [ "$actual_entries" = "$expected_entries_sorted" ]
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
  echo "migrated" > .vbw-planning/.claude-md-migrated
  echo "patched" > .vbw-planning/.tmux-mode-patched
  echo "99999" > .vbw-planning/.watchdog-pid
  echo "watchdog started" > .vbw-planning/.watchdog.log
  echo '{"type":"info"}' > .vbw-planning/.notification-log.jsonl
  echo '{"status":"running"}' > .vbw-planning/.execution-state.json.tmp
  mkdir -p .vbw-planning/.metrics
  echo '{}' > .vbw-planning/.metrics/run-metrics.jsonl
  mkdir -p .vbw-planning/.baselines
  echo '{"baseline":1}' > .vbw-planning/.baselines/token-baseline.json
  mkdir -p .vbw-planning/.active-agent-count.lock
  echo 'stale' > .vbw-planning/.active-agent-count.lock/stale.lock

  run bash "$SCRIPTS_DIR/planning-git.sh" commit-boundary "phase complete" .vbw-planning/config.json
  [ "$status" -eq 0 ]

  # STATE.md should be committed
  run git cat-file -e 'HEAD:.vbw-planning/STATE.md'
  [ "$status" -eq 0 ]

  # Transient files should NOT be committed
  transient_paths=(
    '.agent-pids'
    '.vbw-session'
    '.active-agent'
    '.claude-md-migrated'
    '.tmux-mode-patched'
    '.watchdog-pid'
    '.watchdog.log'
    '.notification-log.jsonl'
    '.execution-state.json.tmp'
    '.metrics/run-metrics.jsonl'
    '.baselines/token-baseline.json'
    '.active-agent-count.lock/stale.lock'
  )

  for path in "${transient_paths[@]}"; do
    run git cat-file -e "HEAD:.vbw-planning/$path"
    [ "$status" -ne 0 ]
  done
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
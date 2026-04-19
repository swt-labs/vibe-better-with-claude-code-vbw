#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "post-archive-hook: no config key no-ops and writes milestone event" {
  cd "$TEST_TEMP_DIR"
  root_real=$(pwd -P)

  run bash "$SCRIPTS_DIR/post-archive-hook.sh" \
    "01-demo" \
    ".vbw-planning/milestones/01-demo" \
    "milestone/01-demo"

  [ "$status" -eq 0 ]
  [ -f .vbw-planning/.events/event-log.jsonl ]

  run jq -r '.event + ":" + .phase + ":" + .data.slug + ":" + .data.archive_path + ":" + .data.tag' .vbw-planning/.events/event-log.jsonl
  [ "$output" = "milestone_shipped:archive:01-demo:$root_real/.vbw-planning/milestones/01-demo:milestone/01-demo" ]
}

@test "post-archive-hook: missing hook file warns and succeeds" {
  cd "$TEST_TEMP_DIR"
  jq '.hooks = {"post_archive": "scripts/hooks/missing.sh"}' .vbw-planning/config.json > .vbw-planning/config.json.tmp
  mv .vbw-planning/config.json.tmp .vbw-planning/config.json

  run bash "$SCRIPTS_DIR/post-archive-hook.sh" \
    "01-demo" \
    ".vbw-planning/milestones/01-demo" \
    "milestone/01-demo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"configured post_archive hook not found"* ]]
}

@test "post-archive-hook: resolves project-relative hook path" {
  cd "$TEST_TEMP_DIR"
  root_real=$(pwd -P)
  mkdir -p scripts/hooks
  cat > scripts/hooks/post-archive.sh <<EOF
#!/usr/bin/env bash
printf 'slug=%s\narchive=%s\ntag=%s\n' "\$1" "\$2" "\$3" > "$TEST_TEMP_DIR/hook-args.txt"
EOF

  jq '.hooks = {"post_archive": "scripts/hooks/post-archive.sh"}' .vbw-planning/config.json > .vbw-planning/config.json.tmp
  mv .vbw-planning/config.json.tmp .vbw-planning/config.json

  run bash "$SCRIPTS_DIR/post-archive-hook.sh" \
    "01-demo" \
    ".vbw-planning/milestones/01-demo" \
    "milestone/01-demo"

  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/hook-args.txt" ]

  run cat "$TEST_TEMP_DIR/hook-args.txt"
  expected=$(printf 'slug=%s\narchive=%s\ntag=%s' "01-demo" "$root_real/.vbw-planning/milestones/01-demo" "milestone/01-demo")
  [ "$output" = "$expected" ]
}

@test "post-archive-hook: hook failure warns and still succeeds" {
  cd "$TEST_TEMP_DIR"
  mkdir -p scripts/hooks
  cat > scripts/hooks/post-archive.sh <<'EOF'
#!/usr/bin/env bash
echo "hook exploded" >&2
exit 17
EOF

  jq '.hooks = {"post_archive": "scripts/hooks/post-archive.sh"}' .vbw-planning/config.json > .vbw-planning/config.json.tmp
  mv .vbw-planning/config.json.tmp .vbw-planning/config.json

  run bash "$SCRIPTS_DIR/post-archive-hook.sh" \
    "01-demo" \
    ".vbw-planning/milestones/01-demo" \
    "milestone/01-demo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"hook exploded"* ]]
  [[ "$output" == *"configured post_archive hook failed"* ]]
}

@test "post-archive-hook: preserves empty tag argument" {
  cd "$TEST_TEMP_DIR"
  root_real=$(pwd -P)
  mkdir -p scripts/hooks
  cat > scripts/hooks/post-archive.sh <<EOF
#!/usr/bin/env bash
printf 'slug=%s\narchive=%s\ntag=%s\n' "\$1" "\$2" "\$3" > "$TEST_TEMP_DIR/hook-args.txt"
EOF

  jq '.hooks = {"post_archive": "scripts/hooks/post-archive.sh"}' .vbw-planning/config.json > .vbw-planning/config.json.tmp
  mv .vbw-planning/config.json.tmp .vbw-planning/config.json

  run bash "$SCRIPTS_DIR/post-archive-hook.sh" \
    "01-demo" \
    ".vbw-planning/milestones/01-demo" \
    ""

  [ "$status" -eq 0 ]

  run cat "$TEST_TEMP_DIR/hook-args.txt"
  expected=$(printf 'slug=%s\narchive=%s\ntag=%s' "01-demo" "$root_real/.vbw-planning/milestones/01-demo" "")
  [ "$output" = "$expected" ]
}

@test "post-archive-hook: absolute config path anchors relative hook off-root" {
  cd "$TEST_TEMP_DIR"
  root_real=$(pwd -P)
  mkdir -p scripts/hooks "$TEST_TEMP_DIR/outside"
  cat > scripts/hooks/post-archive.sh <<EOF
#!/usr/bin/env bash
printf 'slug=%s\narchive=%s\ntag=%s\n' "\$1" "\$2" "\$3" > "$TEST_TEMP_DIR/hook-args.txt"
EOF

  jq '.hooks = {"post_archive": "scripts/hooks/post-archive.sh"}' .vbw-planning/config.json > .vbw-planning/config.json.tmp
  mv .vbw-planning/config.json.tmp .vbw-planning/config.json

  run bash -c "cd '$TEST_TEMP_DIR/outside' && bash '$SCRIPTS_DIR/post-archive-hook.sh' '01-demo' '.vbw-planning/milestones/01-demo' 'milestone/01-demo' '$TEST_TEMP_DIR/.vbw-planning/config.json'"

  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/hook-args.txt" ]

  run cat "$TEST_TEMP_DIR/hook-args.txt"
  expected=$(printf 'slug=%s\narchive=%s\ntag=%s' "01-demo" "$root_real/.vbw-planning/milestones/01-demo" "milestone/01-demo")
  [ "$output" = "$expected" ]
}

@test "post-archive-hook: runs user hook from project root when invoked in subdir" {
  cd "$TEST_TEMP_DIR"
  root_real=$(pwd -P)
  mkdir -p scripts/hooks subdir
  cat > scripts/hooks/post-archive.sh <<EOF
#!/usr/bin/env bash
printf 'pwd=%s\nslug=%s\narchive=%s\ntag=%s\nroot_file=%s\n' "\$(pwd -P)" "\$1" "\$2" "\$3" "\$(if [ -f scripts/hooks/post-archive.sh ]; then echo yes; else echo no; fi)" > "$TEST_TEMP_DIR/hook-context.txt"
EOF

  jq '.hooks = {"post_archive": "scripts/hooks/post-archive.sh"}' .vbw-planning/config.json > .vbw-planning/config.json.tmp
  mv .vbw-planning/config.json.tmp .vbw-planning/config.json

  run bash -c "cd '$TEST_TEMP_DIR/subdir' && bash '$SCRIPTS_DIR/post-archive-hook.sh' '01-demo' '.vbw-planning/milestones/01-demo' 'milestone/01-demo'"

  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/hook-context.txt" ]

  run cat "$TEST_TEMP_DIR/hook-context.txt"
  expected=$(printf 'pwd=%s\nslug=%s\narchive=%s\ntag=%s\nroot_file=%s' "$root_real" "01-demo" "$root_real/.vbw-planning/milestones/01-demo" "milestone/01-demo" "yes")
  [ "$output" = "$expected" ]
}

@test "post-archive-hook: invalid archive context writes no milestone event" {
  cd "$TEST_TEMP_DIR"

  run bash "$SCRIPTS_DIR/post-archive-hook.sh" \
    "" \
    ".vbw-planning/milestones/01-demo" \
    "milestone/01-demo"

  [ "$status" -eq 0 ]
  [ ! -f .vbw-planning/.events/event-log.jsonl ]
}
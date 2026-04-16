#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export LC_ALL=en_US.UTF-8
  export LANG=en_US.UTF-8
}

teardown() {
  unset LC_ALL LANG
  teardown_temp_dir
}

@test "parse-uat-issues awk lowercasing preserves non-ASCII uppercase characters" {
  local probe="$TEST_TEMP_DIR/parse-probe.awk"
  cat > "$probe" <<'EOF'
BEGIN { print tolower_str("ÜMAJOR"); exit }
EOF

  run /usr/bin/awk -f "$SCRIPTS_DIR/parse-uat-issues.awk" -f "$probe" /dev/null

  [ "$status" -eq 0 ]
  [ "$output" = "Ümajor" ]
}

@test "extract-round-issue-ids awk lowercasing preserves non-ASCII uppercase characters" {
  local probe="$TEST_TEMP_DIR/round-probe.awk"
  cat > "$probe" <<'EOF'
BEGIN { print tolower_str("ÜFAIL"); exit }
EOF

  run /usr/bin/awk -f "$SCRIPTS_DIR/extract-round-issue-ids.awk" -f "$probe" /dev/null

  [ "$status" -eq 0 ]
  [ "$output" = "Üfail" ]
}
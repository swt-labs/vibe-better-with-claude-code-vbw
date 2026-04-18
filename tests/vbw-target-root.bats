#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

@test "vbw-target-root: target root fails when git toplevel probe returns empty" {
  local probe_root script_path
  probe_root=$(mktemp -d)
  mkdir -p "$probe_root/bad"
  script_path="$TEST_TEMP_DIR/vbw-target-root-empty.sh"

  cat > "$script_path" <<EOF
#!/usr/bin/env bash
source "$SCRIPTS_DIR/lib/vbw-target-root.sh"
git() {
  if [ "\$1" = "-C" ] && [ "\$3" = "rev-parse" ] && [ "\$4" = "--is-inside-work-tree" ]; then
    return 0
  fi
  if [ "\$1" = "-C" ] && [ "\$3" = "rev-parse" ] && [ "\$4" = "--show-toplevel" ]; then
    return 0
  fi
  return 1
}
vbw_resolve_target_root 1 "$probe_root/bad"
EOF

  run bash "$script_path"
  rm -rf "$probe_root"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "vbw-target-root: target git root skips empty candidate and uses later valid candidate" {
  local probe_root script_path expected
  probe_root=$(mktemp -d)
  mkdir -p "$probe_root/bad" "$probe_root/good"
  script_path="$TEST_TEMP_DIR/vbw-target-root-good.sh"
  expected="$(cd "$probe_root/good" && pwd -P)"

  cat > "$script_path" <<EOF
#!/usr/bin/env bash
source "$SCRIPTS_DIR/lib/vbw-target-root.sh"
git() {
  if [ "\$1" = "-C" ] && [ "\$3" = "rev-parse" ] && [ "\$4" = "--is-inside-work-tree" ]; then
    return 0
  fi
  if [ "\$1" = "-C" ] && [ "\$3" = "rev-parse" ] && [ "\$4" = "--show-toplevel" ]; then
    if [[ "\$2" == *bad ]]; then
      return 0
    fi
    printf '%s\n' "\$2"
    return 0
  fi
  return 1
}
vbw_resolve_target_git_root 1 "$probe_root/bad" "$probe_root/good"
EOF

  run bash "$script_path"
  rm -rf "$probe_root"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}
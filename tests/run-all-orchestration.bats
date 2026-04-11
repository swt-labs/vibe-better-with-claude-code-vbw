#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export ORIG_PATH="$PATH"
}

teardown() {
  export PATH="$ORIG_PATH"
  teardown_temp_dir
}

create_stub_script() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$path"
}

create_stub_workspace() {
  local root="$1"
  local name path
  mkdir -p "$root/testing" "$root/scripts" "$root/tests" "$root/bin"
  cp "$PROJECT_ROOT/testing/run-all.sh" "$root/testing/run-all.sh"
  cp "$PROJECT_ROOT/testing/list-bats-files.sh" "$root/testing/list-bats-files.sh"
  cp "$PROJECT_ROOT/testing/run-bats-shard.sh" "$root/testing/run-bats-shard.sh"
  cp "$PROJECT_ROOT/testing/list-contract-tests.sh" "$root/testing/list-contract-tests.sh"

  cat > "$root/bin/bats" <<'SH'
#!/usr/bin/env bash
: "${BATS_LOG:?}"
printf '%s\n' "$*" >> "$BATS_LOG"
i=1
for arg in "$@"; do
  printf 'ok %d %s\n' "$i" "$(basename "$arg")"
  i=$((i + 1))
done
SH
  chmod +x "$root/bin/bats"

  # Lint stub
  create_stub_script "$root/testing/run-lint.sh"

  # Contract test stubs — discovered from the shared registry
  while IFS=$'\t' read -r name path; do
    [[ -z "$name" ]] && continue
    create_stub_script "$root/$path"
  done < <(bash "$PROJECT_ROOT/testing/list-contract-tests.sh")

  touch "$root/tests/alpha.bats" "$root/tests/beta.bats" "$root/tests/statusline-cache-isolation.bats"
}

create_failing_stub_script() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'SH'
#!/usr/bin/env bash
echo "TOTAL: 48 PASS, 1 FAIL"
exit 1
SH
  chmod +x "$path"
}

link_runtime_tool() {
  local root="$1"
  local tool_name="$2"
  local tool_path

  tool_path="$(command -v "$tool_name")"
  ln -sf "$tool_path" "$root/bin/$tool_name"
}

link_run_all_system_tools() {
  local root="$1"
  local tool_name

  for tool_name in bash cat dirname find grep jq ls mktemp rm sort; do
    link_runtime_tool "$root" "$tool_name"
  done
}

@test "invalid BATS_WORKERS falls back and keeps serial bats files out of worker batches" {
  local root="$TEST_TEMP_DIR/stub-repo"
  create_stub_workspace "$root"
  export BATS_LOG="$TEST_TEMP_DIR/bats.log"
  export PATH="$root/bin:$PATH"

  run env bash -c "cd '$root' && BATS_WORKERS=banana bash testing/run-all.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Invalid BATS_WORKERS=banana'
  echo "$output" | grep -q 'Running serial bats files'

  [ "$(grep -c 'statusline-cache-isolation.bats' "$BATS_LOG")" -eq 1 ]
  grep 'statusline-cache-isolation.bats' "$BATS_LOG" | grep -vq 'alpha.bats\|beta.bats'
}

@test "overall summary prints after all contract output finishes" {
  local root="$TEST_TEMP_DIR/stub-repo-fail"
  local output_file="$TEST_TEMP_DIR/run-all-output.txt"
  create_stub_workspace "$root"
  create_failing_stub_script "$root/testing/verify-lsp-first-policy.sh"
  export BATS_LOG="$TEST_TEMP_DIR/bats-fail.log"
  export PATH="$root/bin:$PATH"

  run env bash -c "cd '$root' && bash testing/run-all.sh"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" > "$output_file"

  local pass_line fail_begin_line fail_total_line fail_end_line lint_summary_line summary_line
  local total_contracts expected_passed
  total_contracts=$(bash "$PROJECT_ROOT/testing/list-contract-tests.sh" | wc -l | tr -d ' ')
  expected_passed=$((total_contracts - 1))
  pass_line=$(grep -n '^PASS: qa-persistence-contract$' "$output_file" | cut -d: -f1)
  fail_begin_line=$(grep -n '^--- begin lsp-first-policy output ---$' "$output_file" | cut -d: -f1)
  fail_total_line=$(grep -n '^TOTAL: 48 PASS, 1 FAIL$' "$output_file" | cut -d: -f1)
  fail_end_line=$(grep -n '^--- end lsp-first-policy output ---$' "$output_file" | cut -d: -f1)
  lint_summary_line=$(grep -n '^Lint checks: 1/1 passed$' "$output_file" | cut -d: -f1)
  summary_line=$(grep -n "^Contract checks: ${expected_passed}/${total_contracts} passed$" "$output_file" | cut -d: -f1)

  [ -n "$pass_line" ]
  [ -n "$fail_begin_line" ]
  [ -n "$fail_total_line" ]
  [ -n "$fail_end_line" ]
  [ -n "$lint_summary_line" ]
  [ -n "$summary_line" ]

  [ "$pass_line" -lt "$fail_begin_line" ]
  [ "$fail_begin_line" -lt "$fail_total_line" ]
  [ "$fail_total_line" -lt "$fail_end_line" ]
  [ "$fail_end_line" -lt "$lint_summary_line" ]
  [ "$lint_summary_line" -lt "$summary_line" ]
}

@test "lint failures are surfaced as a separate run-all section" {
  local root="$TEST_TEMP_DIR/stub-repo-lint-fail"
  create_stub_workspace "$root"
  create_failing_stub_script "$root/testing/run-lint.sh"
  export BATS_LOG="$TEST_TEMP_DIR/bats-lint-fail.log"
  export PATH="$root/bin:$PATH"

  run env bash -c "cd '$root' && bash testing/run-all.sh"
  [ "$status" -eq 1 ]

  echo "$output" | grep -q '^FAIL: shell-lint$'
  echo "$output" | grep -q '^--- begin shell-lint output ---$'
  echo "$output" | grep -q '^Lint checks: 0/1 passed$'
}

@test "run-all fails when shellcheck is unavailable for CI-parity lint" {
  local root="$TEST_TEMP_DIR/stub-repo-no-shellcheck"
  local host_bash
  create_stub_workspace "$root"
  cp "$PROJECT_ROOT/testing/run-lint.sh" "$root/testing/run-lint.sh"
  chmod +x "$root/testing/run-lint.sh"
  link_run_all_system_tools "$root"
  host_bash="$(command -v bash)"
  export BATS_LOG="$TEST_TEMP_DIR/bats-no-shellcheck.log"

  run env PATH="$root/bin" "$host_bash" -c "cd '$root' && bash testing/run-all.sh"
  [ "$status" -eq 1 ]

  echo "$output" | grep -q '^FAIL: shell-lint$'
  echo "$output" | grep -q 'shellcheck is required for CI-parity local verification'
  echo "$output" | grep -q '^Lint checks: 0/1 passed$'
}

@test "run-all fails when bats is unavailable for CI-parity verification" {
  local root="$TEST_TEMP_DIR/stub-repo-no-bats"
  local host_bash
  create_stub_workspace "$root"
  rm -f "$root/bin/bats"
  link_run_all_system_tools "$root"
  host_bash="$(command -v bash)"

  run env PATH="$root/bin" "$host_bash" -c "cd '$root' && bash testing/run-all.sh"
  [ "$status" -eq 1 ]

  echo "$output" | grep -q 'bats is required for CI-parity local verification'
  echo "$output" | grep -q '^BATS: unavailable (bats is required for CI parity)$'
}

@test "run-all fails when jq is unavailable for CI-parity verification" {
  local root="$TEST_TEMP_DIR/stub-repo-no-jq"
  local host_bash
  create_stub_workspace "$root"
  link_run_all_system_tools "$root"
  rm -f "$root/bin/jq"
  host_bash="$(command -v bash)"

  run env PATH="$root/bin" "$host_bash" -c "cd '$root' && bash testing/run-all.sh"
  [ "$status" -eq 1 ]

  echo "$output" | grep -q 'jq is required for CI-parity local verification'
}

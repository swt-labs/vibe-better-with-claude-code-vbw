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
if [ -n "${BATS_HOLD_UNTIL_FILE:-}" ]; then
  while [ ! -f "$BATS_HOLD_UNTIL_FILE" ]; do
    sleep 0.1
  done
fi
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

create_stub_git_worktree_pair() {
  local primary_root="$1"
  local linked_root="$2"

  git -C "$primary_root" init -q
  git -C "$primary_root" config user.email test@example.com
  git -C "$primary_root" config user.name 'Test User'
  git -C "$primary_root" add .
  git -C "$primary_root" commit -q -m 'test: seed stub workspace'
  git -C "$primary_root" branch linked-worktree
  git -C "$primary_root" worktree add "$linked_root" linked-worktree >/dev/null
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

  for tool_name in bash cat dirname find git grep jq ls mkdir mktemp ps rm sort; do
    link_runtime_tool "$root" "$tool_name"
  done
}

wait_for_file_contains() {
  local needle="$1"
  local file="$2"
  local attempt

  for attempt in {1..100}; do
    if [ -f "$file" ] && grep -q "$needle" "$file"; then
      return 0
    fi
    sleep 0.1
  done

  return 1
}

@test "default local worker count auto-tunes when a real peer suite overlaps" {
  local root="$TEST_TEMP_DIR/stub-repo-auto-tune"
  local linked_root="$TEST_TEMP_DIR/stub-repo-auto-tune-worktree"
  local state_dir="$TEST_TEMP_DIR/run-all-state"
  local release_file="$TEST_TEMP_DIR/release-first-run"
  local first_output="$TEST_TEMP_DIR/first-run.log"
  local first_bats_log="$TEST_TEMP_DIR/first-bats.log"
  local second_bats_log="$TEST_TEMP_DIR/second-bats.log"
  local first_pid
  create_stub_workspace "$root"
  create_stub_git_worktree_pair "$root" "$linked_root"
  export PATH="$root/bin:$PATH"

  env RUN_ALL_STATE_DIR="$state_dir" BATS_LOG="$first_bats_log" BATS_HOLD_UNTIL_FILE="$release_file" bash -c "cd '$root' && bash testing/run-all.sh" >"$first_output" 2>&1 &
  first_pid=$!
  wait_for_file_contains 'Launched' "$first_output"

  run env RUN_ALL_STATE_DIR="$state_dir" BATS_LOG="$second_bats_log" bash -c "cd '$linked_root' && bash testing/run-all.sh"
  [ "$status" -eq 0 ]

  touch "$release_file"
  wait "$first_pid"

  echo "$output" | grep -q 'Auto-tuned BATS_WORKERS from 8 to 4 for 2 concurrent local test suite(s)'
}

@test "explicit BATS_WORKERS overrides auto-tuning during real overlap" {
  local root="$TEST_TEMP_DIR/stub-repo-pinned-workers"
  local linked_root="$TEST_TEMP_DIR/stub-repo-pinned-workers-worktree"
  local state_dir="$TEST_TEMP_DIR/run-all-state-pinned"
  local release_file="$TEST_TEMP_DIR/release-pinned-run"
  local first_output="$TEST_TEMP_DIR/pinned-first-run.log"
  local first_bats_log="$TEST_TEMP_DIR/pinned-first-bats.log"
  local second_bats_log="$TEST_TEMP_DIR/pinned-second-bats.log"
  local first_pid
  create_stub_workspace "$root"
  create_stub_git_worktree_pair "$root" "$linked_root"
  export PATH="$root/bin:$PATH"

  env RUN_ALL_STATE_DIR="$state_dir" BATS_LOG="$first_bats_log" BATS_HOLD_UNTIL_FILE="$release_file" bash -c "cd '$root' && bash testing/run-all.sh" >"$first_output" 2>&1 &
  first_pid=$!
  wait_for_file_contains 'Launched' "$first_output"

  run env RUN_ALL_STATE_DIR="$state_dir" BATS_LOG="$second_bats_log" BATS_WORKERS=7 bash -c "cd '$linked_root' && bash testing/run-all.sh"
  [ "$status" -eq 0 ]

  touch "$release_file"
  wait "$first_pid"

  [[ "$output" != *'Auto-tuned BATS_WORKERS'* ]]
  echo "$output" | grep -q '7 bats workers'
}

@test "stray token file is ignored and does not self-throttle a lone suite" {
  local root="$TEST_TEMP_DIR/stub-repo-stray-token"
  local state_root="$TEST_TEMP_DIR/run-all-state-stray"
  local repo_key
  create_stub_workspace "$root"
  export BATS_LOG="$TEST_TEMP_DIR/bats-stray.log"
  export PATH="$root/bin:$PATH"

  repo_key=$(printf '%s' "$root/.git" | jq -sRr @uri)
  mkdir -p "$state_root/$repo_key"
  printf '{"pid":"%s","repo_key":"%s"}\n' "$$" "$repo_key" > "$state_root/$repo_key/suite.$$.fake.token"

  run env RUN_ALL_STATE_DIR="$state_root" bash -c "cd '$root' && bash testing/run-all.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *'Auto-tuned BATS_WORKERS'* ]]
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

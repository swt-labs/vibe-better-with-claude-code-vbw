#!/usr/bin/env bash
set -euo pipefail

# run-all.sh — Single entrypoint for repo verification checks
# Launches shared lint, contract checks, and bats workers concurrently, then collects results.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIST_BATS_FILES="$ROOT/testing/list-bats-files.sh"
LIST_CONTRACT_TESTS="$ROOT/testing/list-contract-tests.sh"

TMPDIR_JOBS="$(mktemp -d)"
RUN_ALL_STATE_ROOT="${RUN_ALL_STATE_DIR:-${TMPDIR:-/tmp}/vbw-run-all-suites}"
RUN_ALL_STATE_DIR=""
RUN_ALL_TOKEN=""
RUN_ALL_REPO_KEY=""
RUN_ALL_PROCESS_START=""
RUN_ALL_PROCESS_COMMAND=""

declare -a JOB_NAMES=()
declare -a JOB_PIDS=()
declare -a JOB_TYPES=()  # "lint", "contract", or "bats"
declare -a JOB_EXIT_CODES=()
declare -a serial_bats_files=()

cleanup_run_all() {
  local job_pid

  for job_pid in "${JOB_PIDS[@]}"; do
    [ -n "$job_pid" ] || continue
    kill "$job_pid" 2>/dev/null || true
  done
  for job_pid in "${JOB_PIDS[@]}"; do
    [ -n "$job_pid" ] || continue
    wait "$job_pid" 2>/dev/null || true
  done
  rm -rf "$TMPDIR_JOBS"
  if [ -n "$RUN_ALL_TOKEN" ]; then
    rm -f "$RUN_ALL_TOKEN"
  fi
}

trap cleanup_run_all EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for CI-parity local verification (install with: brew install jq)."
  exit 1
fi

run_job() {
  local type="$1" name="$2"
  shift 2
  JOB_NAMES+=("$name")
  JOB_TYPES+=("$type")
  "$@" > "$TMPDIR_JOBS/$name.out" 2>&1 &
  JOB_PIDS+=("$!")
}

initialize_run_all_state() {
  local repo_identity

  repo_identity="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null || printf '%s/.git' "$ROOT")"
  case "$repo_identity" in
    /*) ;;
    *) repo_identity="$ROOT/$repo_identity" ;;
  esac
  repo_identity="$(cd "$repo_identity" 2>/dev/null && pwd || printf '%s' "$repo_identity")"
  RUN_ALL_REPO_KEY="$(printf '%s' "$repo_identity" | jq -sRr @uri 2>/dev/null || true)"
  RUN_ALL_STATE_DIR="$RUN_ALL_STATE_ROOT"
  if [ -n "$RUN_ALL_REPO_KEY" ]; then
    RUN_ALL_STATE_DIR="$RUN_ALL_STATE_ROOT/$RUN_ALL_REPO_KEY"
  fi
  RUN_ALL_PROCESS_START="$(ps -o lstart= -p $$ 2>/dev/null || true)"
  RUN_ALL_PROCESS_COMMAND="$(ps -o command= -p $$ 2>/dev/null || true)"
}

run_all_token_is_valid() {
  local entry="$1"
  local pid repo_key process_start process_command current_start current_command

  [ -f "$entry" ] || return 1

  pid="$(jq -r '.pid // empty' "$entry" 2>/dev/null || true)"
  repo_key="$(jq -r '.repo_key // empty' "$entry" 2>/dev/null || true)"
  process_start="$(jq -r '.process_start // empty' "$entry" 2>/dev/null || true)"
  process_command="$(jq -r '.process_command // empty' "$entry" 2>/dev/null || true)"

  case "$pid" in
    ''|*[!0-9]*)
      rm -f "$entry"
      return 1
      ;;
  esac

  if [ -z "$repo_key" ] || [ -z "$process_start" ] || [ -z "$process_command" ]; then
    rm -f "$entry"
    return 1
  fi

  if [ "$repo_key" != "$RUN_ALL_REPO_KEY" ]; then
    rm -f "$entry"
    return 1
  fi

  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$entry"
    return 1
  fi

  current_start="$(ps -o lstart= -p "$pid" 2>/dev/null || true)"
  current_command="$(ps -o command= -p "$pid" 2>/dev/null || true)"

  if [ -z "$current_start" ] || [ -z "$current_command" ]; then
    rm -f "$entry"
    return 1
  fi

  if [ "$process_start" != "$current_start" ] || [ "$process_command" != "$current_command" ]; then
    rm -f "$entry"
    return 1
  fi

  case "$current_command" in
    *"testing/run-all.sh"*)
      return 0
      ;;
  esac

  rm -f "$entry"
  return 1
}

prune_run_all_tokens() {
  local entry

  [ -d "$RUN_ALL_STATE_DIR" ] || return 0

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    run_all_token_is_valid "$entry" >/dev/null 2>&1 || true
  done < <(find "$RUN_ALL_STATE_DIR" -maxdepth 1 -type f -name 'suite.*.token' -print 2>/dev/null)
}

count_run_all_tokens() {
  local count=0 entry

  [ -d "$RUN_ALL_STATE_DIR" ] || {
    echo 0
    return 0
  }

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    if run_all_token_is_valid "$entry"; then
      count=$((count + 1))
    fi
  done < <(find "$RUN_ALL_STATE_DIR" -maxdepth 1 -type f -name 'suite.*.token' -print 2>/dev/null)

  echo "$count"
}

count_run_all_tokens_with_grace() {
  local attempt current_count observed_count=0

  for attempt in 1 2 3 4; do
    current_count="$(count_run_all_tokens)"
    if [ "$current_count" -gt "$observed_count" ]; then
      observed_count="$current_count"
    fi
    if [ "$observed_count" -gt 1 ] || [ "$attempt" -eq 4 ]; then
      break
    fi
    sleep 0.05
  done

  echo "$observed_count"
}

register_run_all_token() {
  local final_token

  [ -n "$RUN_ALL_REPO_KEY" ] || return 1
  [ -n "$RUN_ALL_PROCESS_START" ] || return 1
  [ -n "$RUN_ALL_PROCESS_COMMAND" ] || return 1
  mkdir -p "$RUN_ALL_STATE_DIR" 2>/dev/null || return 1
  prune_run_all_tokens
  RUN_ALL_TOKEN="$(mktemp "$RUN_ALL_STATE_DIR/suite.$$.XXXXXX.token.tmp" 2>/dev/null)" || {
    RUN_ALL_TOKEN=""
    return 1
  }
  if ! jq -n \
    --arg pid "$$" \
    --arg repo_key "$RUN_ALL_REPO_KEY" \
    --arg process_start "$RUN_ALL_PROCESS_START" \
    --arg process_command "$RUN_ALL_PROCESS_COMMAND" \
    '{pid: $pid, repo_key: $repo_key, process_start: $process_start, process_command: $process_command}' > "$RUN_ALL_TOKEN"; then
    rm -f "$RUN_ALL_TOKEN"
    RUN_ALL_TOKEN=""
    return 1
  fi
  final_token="${RUN_ALL_TOKEN%.tmp}"
  if ! mv "$RUN_ALL_TOKEN" "$final_token"; then
    rm -f "$RUN_ALL_TOKEN"
    RUN_ALL_TOKEN=""
    return 1
  fi
  RUN_ALL_TOKEN="$final_token"
}

auto_tune_bats_workers() {
  local requested="$1" active_suites="$2" tuned="$1"

  if [ "$active_suites" -gt 1 ]; then
    tuned=$(((requested + active_suites - 1) / active_suites))
    [ "$tuned" -lt 2 ] && tuned=2
  fi

  echo "$tuned"
}

initialize_run_all_state
register_run_all_token

# --- Launch shell lint ---
run_job lint "shell-lint"                bash "$ROOT/testing/run-lint.sh"

# --- Launch contract checks (discovered from shared registry) ---
CONTRACT_TESTS_OUTPUT="$(bash "$LIST_CONTRACT_TESTS")"
if [[ -z "$CONTRACT_TESTS_OUTPUT" ]]; then
  echo "ERROR: No contract tests discovered from $LIST_CONTRACT_TESTS"
  exit 1
fi

while IFS=$'\t' read -r name path; do
  [[ -z "$name" ]] && continue
  run_job contract "$name" bash "$ROOT/$path"
done <<< "$CONTRACT_TESTS_OUTPUT"

# --- Launch bats workers concurrently with contract checks ---
BATS_WORKERS_FROM_ENV=false
if [ -n "${BATS_WORKERS:-}" ]; then
  BATS_WORKERS_FROM_ENV=true
fi
BATS_WORKERS="${BATS_WORKERS:-8}"
case "$BATS_WORKERS" in
  ''|*[!0-9]*)
    echo "Invalid BATS_WORKERS=$BATS_WORKERS — falling back to CI shard count (4 workers)."
    BATS_WORKERS=4
    ;;
  0)
    echo "Invalid BATS_WORKERS=0 — falling back to CI shard count (4 workers)."
    BATS_WORKERS=4
    ;;
esac
ACTIVE_RUN_ALL_SUITES=0
if [ -n "$RUN_ALL_TOKEN" ]; then
  ACTIVE_RUN_ALL_SUITES="$(count_run_all_tokens_with_grace)"
fi

if [ "$BATS_WORKERS_FROM_ENV" = false ] && [ "${GITHUB_ACTIONS:-false}" != "true" ]; then
  tuned_bats_workers="$(auto_tune_bats_workers "$BATS_WORKERS" "$ACTIVE_RUN_ALL_SUITES")"
  if [ "$tuned_bats_workers" -ne "$BATS_WORKERS" ]; then
    echo "Auto-tuned BATS_WORKERS from $BATS_WORKERS to $tuned_bats_workers for $ACTIVE_RUN_ALL_SUITES concurrent local test suite(s). Override with BATS_WORKERS=N."
    BATS_WORKERS="$tuned_bats_workers"
  fi
fi
bats_launched=false
bats_missing=false
if ! command -v bats &>/dev/null && ls "$ROOT/tests/"*.bats &>/dev/null 2>&1; then
  echo "ERROR: bats is required for CI-parity local verification (install bats-core)."
  bats_missing=true
elif command -v bats &>/dev/null && ls "$ROOT/tests/"*.bats &>/dev/null 2>&1; then
  bats_files=()
  while IFS= read -r bats_file; do
    [ -n "$bats_file" ] || continue
    bats_files+=("$bats_file")
  done < <(bash "$LIST_BATS_FILES" --shardable)

  serial_bats_files=()
  while IFS= read -r bats_file; do
    [ -n "$bats_file" ] || continue
    serial_bats_files+=("$bats_file")
  done < <(bash "$LIST_BATS_FILES" --serial)
  total_files="${#bats_files[@]}"
  bats_launched=true

  if [ "$total_files" -gt 0 ] && { [ "$BATS_WORKERS" -le 1 ] || [ "$total_files" -le 1 ]; }; then
    run_job bats "bats-all" bats "${bats_files[@]}"
  elif [ "$total_files" -gt 0 ]; then
    for ((w=0; w<BATS_WORKERS; w++)); do
      worker_files=()
      while IFS= read -r worker_file; do
        [ -n "$worker_file" ] || continue
        worker_files+=("$worker_file")
      done < <(bash "$ROOT/testing/run-bats-shard.sh" "$w" "$BATS_WORKERS" --print-files "${bats_files[@]}")
      if [ "${#worker_files[@]}" -gt 0 ]; then
        run_job bats "bats-worker-$w" bats "${worker_files[@]}"
      fi
    done
  fi
fi

bats_label="0 bats"
if [ "$bats_launched" = true ]; then
  bats_label="$BATS_WORKERS bats workers"
  [ "${#serial_bats_files[@]}" -gt 0 ] && bats_label="$bats_label + ${#serial_bats_files[@]} serial file(s)"
fi
contract_count=0
for _jt in "${JOB_TYPES[@]}"; do [ "$_jt" = contract ] && contract_count=$((contract_count + 1)); done
lint_count=0
for _jt in "${JOB_TYPES[@]}"; do [ "$_jt" = lint ] && lint_count=$((lint_count + 1)); done
echo "Launched ${#JOB_PIDS[@]} parallel jobs ($lint_count lint + $contract_count contract + $bats_label)..."
echo ""

# --- Wait for all jobs, collect results ---
lint_pass=0 lint_fail=0
contract_pass=0 contract_fail=0
bats_pass=0 bats_fail=0 bats_workers_failed=0

for i in "${!JOB_PIDS[@]}"; do
  name="${JOB_NAMES[$i]}"
  type="${JOB_TYPES[$i]}"

  if wait "${JOB_PIDS[$i]}"; then
    JOB_EXIT_CODES[$i]=0
    if [ "$type" = "lint" ]; then
      lint_pass=$((lint_pass + 1))
    elif [ "$type" = "contract" ]; then
      contract_pass=$((contract_pass + 1))
    fi
  else
    JOB_EXIT_CODES[$i]=1
    if [ "$type" = "lint" ]; then
      lint_fail=$((lint_fail + 1))
    elif [ "$type" = "contract" ]; then
      contract_fail=$((contract_fail + 1))
    else
      bats_workers_failed=1
    fi
  fi

  # Aggregate bats counts
  if [ "$type" = "bats" ]; then
    wp=$(grep -c '^ok ' "$TMPDIR_JOBS/$name.out" 2>/dev/null || true)
    wf=$(grep -c '^not ok ' "$TMPDIR_JOBS/$name.out" 2>/dev/null || true)
    bats_pass=$((bats_pass + ${wp:-0}))
    bats_fail=$((bats_fail + ${wf:-0}))
  fi
done

for i in "${!JOB_PIDS[@]}"; do
  name="${JOB_NAMES[$i]}"
  type="${JOB_TYPES[$i]}"
  [ "$type" = "lint" ] || continue
  if [ "${JOB_EXIT_CODES[$i]:-1}" -eq 0 ]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name"
  fi
done

for i in "${!JOB_PIDS[@]}"; do
  name="${JOB_NAMES[$i]}"
  type="${JOB_TYPES[$i]}"
  [ "$type" = "contract" ] || continue
  if [ "${JOB_EXIT_CODES[$i]:-1}" -eq 0 ]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name"
  fi
done

for i in "${!JOB_PIDS[@]}"; do
  name="${JOB_NAMES[$i]}"
  type="${JOB_TYPES[$i]}"
  [ "${JOB_EXIT_CODES[$i]:-1}" -ne 0 ] || continue

  if [ "$type" = "contract" ] || [ "$type" = "lint" ]; then
    echo "--- begin $name output ---"
    cat "$TMPDIR_JOBS/$name.out"
    echo "--- end $name output ---"
    echo ""
  else
    echo "--- $name FAILURES ---"
    grep -E '^not ok|^# ' "$TMPDIR_JOBS/$name.out" || true
    echo ""
  fi
done

if [ "${#serial_bats_files[@]}" -gt 0 ]; then
  echo "Running serial bats files..."
  if ! bats "${serial_bats_files[@]}" > "$TMPDIR_JOBS/bats-serial.out" 2>&1; then
    bats_workers_failed=1
    echo "--- bats-serial FAILURES ---"
    grep -E '^not ok|^# ' "$TMPDIR_JOBS/bats-serial.out" || true
    echo ""
  fi
  wp=$(grep -c '^ok ' "$TMPDIR_JOBS/bats-serial.out" 2>/dev/null || true)
  wf=$(grep -c '^not ok ' "$TMPDIR_JOBS/bats-serial.out" 2>/dev/null || true)
  bats_pass=$((bats_pass + ${wp:-0}))
  bats_fail=$((bats_fail + ${wf:-0}))
fi

# --- Summary ---
total_lint=$((lint_pass + lint_fail))
total_contracts=$((contract_pass + contract_fail))
echo ""
echo "==============================="
if [ "$total_lint" -gt 0 ]; then
  echo "Lint checks: ${lint_pass}/${total_lint} passed"
fi
echo "Contract checks: ${contract_pass}/${total_contracts} passed"
if [ "$bats_launched" = true ]; then
  echo "BATS: $bats_pass passed, $bats_fail failed"
elif [ "$bats_missing" = true ]; then
  echo "BATS: unavailable (bats is required for CI parity)"
else
  echo "BATS: skipped (bats not installed or no .bats files found)"
fi
echo "==============================="

any_failure=0
[ "$lint_fail" -gt 0 ] && any_failure=1
[ "$contract_fail" -gt 0 ] && any_failure=1
[ "$bats_missing" = true ] && any_failure=1
[ "$bats_workers_failed" -ne 0 ] && any_failure=1

if [ "$any_failure" -ne 0 ]; then
  exit 1
fi

echo ""
echo "All checks completed."

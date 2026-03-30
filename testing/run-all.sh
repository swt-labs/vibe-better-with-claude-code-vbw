#!/usr/bin/env bash
set -euo pipefail

# run-all.sh — Single entrypoint for repo verification checks
# Launches shared lint, contract checks, and bats workers concurrently, then collects results.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

TMPDIR_JOBS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_JOBS"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for CI-parity local verification (install with: brew install jq)."
  exit 1
fi

# --- Shared parallel job infrastructure ---
declare -a JOB_NAMES=()
declare -a JOB_PIDS=()
declare -a JOB_TYPES=()  # "lint", "contract", or "bats"
declare -a JOB_EXIT_CODES=()
declare -a serial_bats_files=()
declare -a SERIAL_BATS_FILES=(
  "$ROOT/tests/statusline-cache-isolation.bats"
)

is_serial_bats_file() {
  local candidate="$1" serial_file
  for serial_file in "${SERIAL_BATS_FILES[@]}"; do
    [ "$candidate" = "$serial_file" ] && return 0
  done
  return 1
}

default_bats_workers() {
  local cpu_count
  cpu_count=""

  if command -v sysctl >/dev/null 2>&1; then
    cpu_count=$(sysctl -n hw.ncpu 2>/dev/null || true)
  fi
  if [ -z "$cpu_count" ] && command -v nproc >/dev/null 2>&1; then
    cpu_count=$(nproc 2>/dev/null || true)
  fi

  case "$cpu_count" in
    ''|*[!0-9]*) cpu_count=4 ;;
  esac

  # Cap at 8 to avoid diminishing returns and temp-file contention.
  if [ "$cpu_count" -gt 8 ]; then
    cpu_count=8
  fi
  if [ "$cpu_count" -lt 2 ]; then
    cpu_count=2
  fi

  echo "$cpu_count"
}

run_job() {
  local type="$1" name="$2"
  shift 2
  JOB_NAMES+=("$name")
  JOB_TYPES+=("$type")
  "$@" > "$TMPDIR_JOBS/$name.out" 2>&1 &
  JOB_PIDS+=("$!")
}

# --- Launch shell lint ---
run_job lint "shell-lint"                bash "$ROOT/testing/run-lint.sh"

# --- Launch contract checks ---
run_job contract "init-todo"                bash "$ROOT/scripts/verify-init-todo.sh"
run_job contract "claude-bootstrap"         bash "$ROOT/scripts/verify-claude-bootstrap.sh"
run_job contract "bash-scripts-contract"    bash "$ROOT/testing/verify-bash-scripts-contract.sh"
run_job contract "commands-contract"        bash "$ROOT/testing/verify-commands-contract.sh"
run_job contract "no-inline-exec-spans"     bash "$ROOT/testing/verify-no-inline-exec-spans.sh"
run_job contract "plugin-root-resolution"   bash "$ROOT/testing/verify-plugin-root-resolution.sh"
run_job contract "hook-event-name"          bash "$ROOT/testing/verify-hook-event-name.sh"
run_job contract "plan-filename-convention" bash "$ROOT/testing/verify-plan-filename-convention.sh"
run_job contract "skill-activation"         bash "$ROOT/testing/verify-skill-activation.sh"
run_job contract "permission-mode-contract" bash "$ROOT/testing/verify-permission-mode-contract.sh"
run_job contract "delegation-guard"         bash "$ROOT/testing/verify-delegation-guard.sh"
run_job contract "summary-status-contract"  bash "$ROOT/testing/verify-summary-status-contract.sh"
run_job contract "summary-utils-contract"   bash "$ROOT/testing/verify-summary-utils-contract.sh"
run_job contract "exec-state-reconciliation" bash "$ROOT/testing/verify-exec-state-reconciliation.sh"
run_job contract "statusline-qa-lifecycle"  bash "$ROOT/testing/verify-statusline-qa-lifecycle.sh"
run_job contract "statusline-429-backoff"   bash "$ROOT/testing/verify-statusline-429-backoff.sh"
run_job contract "uat-recurrence"           bash "$ROOT/testing/verify-uat-recurrence.sh"
run_job contract "lead-research-conditional" bash "$ROOT/testing/verify-lead-research-conditional.sh"
run_job contract "lsp-setup"                bash "$ROOT/testing/verify-lsp-setup.sh"
run_job contract "lsp-first-policy"         bash "$ROOT/testing/verify-lsp-first-policy.sh"
run_job contract "claude-md-staleness"      bash "$ROOT/testing/verify-claude-md-staleness.sh"
run_job contract "dev-recovery-guidance"    bash "$ROOT/testing/verify-dev-recovery-guidance.sh"
run_job contract "live-validation-policy"   bash "$ROOT/testing/verify-live-validation-policy.sh"
run_job contract "ghost-team-cleanup"       bash "$ROOT/testing/verify-ghost-team-cleanup.sh"
run_job contract "ci-workflow-contract"     bash "$ROOT/testing/verify-ci-workflow-contract.sh"
run_job contract "qa-persistence-contract"  bash "$ROOT/testing/verify-qa-persistence-contract.sh"

# --- Launch bats workers concurrently with contract checks ---
BATS_WORKERS="${BATS_WORKERS:-$(default_bats_workers)}"
case "$BATS_WORKERS" in
  ''|*[!0-9]*)
    echo "Invalid BATS_WORKERS=$BATS_WORKERS — falling back to auto-detected worker count."
    BATS_WORKERS="$(default_bats_workers)"
    ;;
  0)
    echo "Invalid BATS_WORKERS=0 — falling back to auto-detected worker count."
    BATS_WORKERS="$(default_bats_workers)"
    ;;
esac
bats_launched=false
bats_missing=false
if ! command -v bats &>/dev/null && ls "$ROOT/tests/"*.bats &>/dev/null 2>&1; then
  echo "ERROR: bats is required for CI-parity local verification (install bats-core)."
  bats_missing=true
elif command -v bats &>/dev/null && ls "$ROOT/tests/"*.bats &>/dev/null 2>&1; then
  all_bats_files=("$ROOT/tests/"*.bats)
  bats_files=()
  serial_bats_files=()
  for bats_file in "${all_bats_files[@]}"; do
    if is_serial_bats_file "$bats_file"; then
      serial_bats_files+=("$bats_file")
    else
      bats_files+=("$bats_file")
    fi
  done
  total_files="${#bats_files[@]}"
  bats_launched=true

  if [ "$total_files" -gt 0 ] && { [ "$BATS_WORKERS" -le 1 ] || [ "$total_files" -le 1 ]; }; then
    run_job bats "bats-all" bats "${bats_files[@]}"
  elif [ "$total_files" -gt 0 ]; then
    for ((w=0; w<BATS_WORKERS; w++)); do
      worker_files=()
      for ((f=w; f<total_files; f+=BATS_WORKERS)); do
        worker_files+=("${bats_files[$f]}")
      done
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
if [ "${RUN_VIBE_VERIFY:-0}" = "1" ]; then
  echo "Running vibe consolidation checks..."
  bash "$ROOT/scripts/verify-vibe.sh"
else
  echo "Skipping scripts/verify-vibe.sh (set RUN_VIBE_VERIFY=1 to enable)."
fi

echo ""
echo "All selected checks completed."

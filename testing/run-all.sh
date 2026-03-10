#!/usr/bin/env bash
set -euo pipefail

# run-all.sh — Single entrypoint for repo verification checks

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Running init/todo contract checks..."
bash "$ROOT/scripts/verify-init-todo.sh"

echo ""
echo "Running CLAUDE bootstrap contract checks..."
bash "$ROOT/scripts/verify-claude-bootstrap.sh"

echo ""
echo "Running bash script contract checks..."
bash "$ROOT/testing/verify-bash-scripts-contract.sh"

echo ""
echo "Running command contract checks..."
bash "$ROOT/testing/verify-commands-contract.sh"

echo ""
echo "Running inline execution span checks..."
bash "$ROOT/testing/verify-no-inline-exec-spans.sh"

echo ""
echo "Running plugin root resolution checks..."
bash "$ROOT/testing/verify-plugin-root-resolution.sh"

echo ""
echo "Running hook hookEventName checks..."
bash "$ROOT/testing/verify-hook-event-name.sh"

echo ""
echo "Running plan filename convention checks..."
bash "$ROOT/testing/verify-plan-filename-convention.sh"

echo ""
echo "Running skill activation pipeline checks..."
bash "$ROOT/testing/verify-skill-activation.sh"

echo ""
echo "Running delegation guard checks..."
bash "$ROOT/testing/verify-delegation-guard.sh"

echo ""
echo "Running summary status contract checks..."
bash "$ROOT/testing/verify-summary-status-contract.sh"

echo ""
echo "Running summary-utils contract checks..."
bash "$ROOT/testing/verify-summary-utils-contract.sh"

echo ""
echo "Running execution-state reconciliation checks..."
bash "$ROOT/testing/verify-exec-state-reconciliation.sh"
echo ""
echo "Running statusline QA/UAT lifecycle checks..."
bash "$ROOT/testing/verify-statusline-qa-lifecycle.sh"
echo ""
echo "Running UAT recurrence tracking checks..."
bash "$ROOT/testing/verify-uat-recurrence.sh"
echo ""
echo "Running Lead research-conditional checks..."
bash "$ROOT/testing/verify-lead-research-conditional.sh"
echo ""
echo "Running LSP setup pipeline checks..."
bash "$ROOT/testing/verify-lsp-setup.sh"
echo ""
echo "Running LSP-first policy checks..."
bash "$ROOT/testing/verify-lsp-first-policy.sh"
echo ""
echo "Running CLAUDE.md staleness checks..."
bash "$ROOT/testing/verify-claude-md-staleness.sh"
echo ""
echo "Running dev recovery guidance checks..."
bash "$ROOT/testing/verify-dev-recovery-guidance.sh"

echo ""
echo "Running live validation policy checks..."
bash "$ROOT/testing/verify-live-validation-policy.sh"

echo ""
echo "Running ghost team cleanup checks..."
bash "$ROOT/testing/verify-ghost-team-cleanup.sh"

echo ""
if command -v bats &>/dev/null && ls "$ROOT/tests/"*.bats &>/dev/null; then
  echo "Running bats test suites..."
  bats_pass=0
  bats_fail=0
  for f in "$ROOT/tests/"*.bats; do
    if bats "$f"; then
      bats_pass=$((bats_pass + 1))
    else
      bats_fail=$((bats_fail + 1))
    fi
  done
  echo ""
  echo "==============================="
  echo "BATS: $bats_pass files passed, $bats_fail files failed"
  echo "==============================="
  [ "$bats_fail" -eq 0 ] || exit 1
else
  echo "Skipping bats tests (bats not installed or no .bats files found)."
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

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
  local file
  mkdir -p "$root/testing" "$root/scripts" "$root/tests" "$root/bin"
  cp "$PROJECT_ROOT/testing/run-all.sh" "$root/testing/run-all.sh"

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

  for file in \
    scripts/verify-init-todo.sh \
    scripts/verify-claude-bootstrap.sh \
    testing/verify-bash-scripts-contract.sh \
    testing/verify-commands-contract.sh \
    testing/verify-no-inline-exec-spans.sh \
    testing/verify-plugin-root-resolution.sh \
    testing/verify-hook-event-name.sh \
    testing/verify-plan-filename-convention.sh \
    testing/verify-skill-activation.sh \
    testing/verify-permission-mode-contract.sh \
    testing/verify-delegation-guard.sh \
    testing/verify-summary-status-contract.sh \
    testing/verify-summary-utils-contract.sh \
    testing/verify-exec-state-reconciliation.sh \
    testing/verify-statusline-qa-lifecycle.sh \
    testing/verify-statusline-429-backoff.sh \
    testing/verify-uat-recurrence.sh \
    testing/verify-lead-research-conditional.sh \
    testing/verify-lsp-setup.sh \
    testing/verify-lsp-first-policy.sh \
    testing/verify-claude-md-staleness.sh \
    testing/verify-dev-recovery-guidance.sh \
    testing/verify-live-validation-policy.sh \
    testing/verify-ghost-team-cleanup.sh \
    testing/verify-qa-persistence-contract.sh; do
    create_stub_script "$root/$file"
  done

  touch "$root/tests/alpha.bats" "$root/tests/beta.bats" "$root/tests/statusline-cache-isolation.bats"
}

@test "invalid BATS_WORKERS falls back and keeps serial bats files out of worker batches" {
  local root="$TEST_TEMP_DIR/stub-repo"
  create_stub_workspace "$root"
  export BATS_LOG="$TEST_TEMP_DIR/bats.log"
  export PATH="$root/bin:$PATH"

  run env RUN_VIBE_VERIFY=0 bash -c "cd '$root' && BATS_WORKERS=banana bash testing/run-all.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Invalid BATS_WORKERS=banana'
  echo "$output" | grep -q 'Running serial bats files'

  [ "$(grep -c 'statusline-cache-isolation.bats' "$BATS_LOG")" -eq 1 ]
  grep 'statusline-cache-isolation.bats' "$BATS_LOG" | grep -vq 'alpha.bats\|beta.bats'
}

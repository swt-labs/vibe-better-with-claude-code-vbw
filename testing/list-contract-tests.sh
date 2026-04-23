#!/usr/bin/env bash
set -euo pipefail
# list-contract-tests.sh — Single source of truth for the contract test registry.
#
# Output: tab-separated name<TAB>relative-path pairs, one per line.
# Paths are relative to the repo root.
#
# Used by: testing/run-all.sh, .github/workflows/ci.yml,
#          testing/verify-ci-workflow-contract.sh
#
# To add a contract test: add a line here and create the script. Both local
# and CI runners will automatically discover it — no other files need editing.

printf '%s\t%s\n' \
  init-todo                    scripts/verify-init-todo.sh \
  claude-bootstrap             scripts/verify-claude-bootstrap.sh \
  bash-scripts-contract        testing/verify-bash-scripts-contract.sh \
  commands-contract            testing/verify-commands-contract.sh \
  no-inline-exec-spans         testing/verify-no-inline-exec-spans.sh \
  issue-157-migration          testing/verify-issue-157-migration-contract.sh \
  plugin-root-resolution       testing/verify-plugin-root-resolution.sh \
  hook-event-name              testing/verify-hook-event-name.sh \
  github-fix-workflow-contract testing/verify-github-fix-workflow-contract.sh \
  plan-filename-convention     testing/verify-plan-filename-convention.sh \
  skill-activation             testing/verify-skill-activation.sh \
  permission-mode-contract     testing/verify-permission-mode-contract.sh \
  delegation-guard             testing/verify-delegation-guard.sh \
  agent-spawn-guard            testing/verify-agent-spawn-guard.sh \
  summary-status-contract      testing/verify-summary-status-contract.sh \
  summary-utils-contract       testing/verify-summary-utils-contract.sh \
  exec-state-reconciliation    testing/verify-exec-state-reconciliation.sh \
  statusline-qa-lifecycle      testing/verify-statusline-qa-lifecycle.sh \
  statusline-429-backoff       testing/verify-statusline-429-backoff.sh \
  uat-recurrence               testing/verify-uat-recurrence.sh \
  uat-autocontinue             testing/verify-uat-autocontinue.sh \
  human-only-uat-contract      testing/verify-human-only-uat-contract.sh \
  lead-research-conditional    testing/verify-lead-research-conditional.sh \
  lsp-setup                    testing/verify-lsp-setup.sh \
  lsp-first-policy             testing/verify-lsp-first-policy.sh \
  claude-md-staleness          testing/verify-claude-md-staleness.sh \
  dev-recovery-guidance        testing/verify-dev-recovery-guidance.sh \
  live-validation-policy       testing/verify-live-validation-policy.sh \
  ghost-team-cleanup           testing/verify-ghost-team-cleanup.sh \
  ci-workflow-contract         testing/verify-ci-workflow-contract.sh \
  run-all-execution-contract   testing/verify-run-all-execution-contract.sh \
  discord-release-workflow     testing/verify-discord-release-workflow-contract.sh \
  prefer-teams-canonicalization testing/verify-prefer-teams-canonicalization.sh \
  qa-persistence-contract      testing/verify-qa-persistence-contract.sh \
  report-template-contract     testing/verify-report-template-contract.sh \
  report-diag-handoff          testing/verify-report-diag-handoff.sh \
  discussion-engine-contract   testing/verify-discussion-engine-contract.sh \
  debug-session-contract       testing/verify-debug-session-contract.sh \
  todo-pickup-contract         testing/verify-todo-pickup-contract.sh \
  debug-target-docs            testing/verify-debug-target-docs.sh \
  askuserquestion-contract     testing/verify-askuserquestion-contract.sh \
  research-storage-contract    testing/verify-research-storage-contract.sh \
  readme-config-reference      testing/verify-readme-config-reference.sh \
  config-defaults-sync         testing/verify-config-defaults-sync.sh \
  caveman-contract             testing/verify-caveman-contract.sh \
  verify-vibe                  scripts/verify-vibe.sh

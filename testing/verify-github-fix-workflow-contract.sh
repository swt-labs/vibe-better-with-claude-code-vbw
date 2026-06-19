#!/usr/bin/env bash
set -euo pipefail

# verify-github-fix-workflow-contract.sh — Contract checks for local GH fix workflow helpers

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL_GUARD="$ROOT/.github/hooks/copilot-tool-guard.sh"
STOP_GUARD="$ROOT/.github/hooks/fix-issue-stop-guard.sh"
WAIT_GITHUB="$ROOT/.github/scripts/wait-github.py"
RECORD_STATE="$ROOT/.github/scripts/fix-issue-record-state.sh"
FIX_SKILL="$ROOT/.agents/skills/vbw-fix-issue/SKILL.md"
ISSUE_INTAKE_REF="$ROOT/.agents/skills/vbw-fix-issue/references/issue-intake.md"
PR_CI_GATE_REF="$ROOT/.agents/skills/vbw-fix-issue/references/pr-ci-gate.md"
RECOVERY_REF="$ROOT/.agents/skills/vbw-fix-issue/references/recovery.md"
PLANNER_AGENT="$ROOT/.codex/agents/vbw-fix-planner.toml"
REVIEW_AGENT="$ROOT/.codex/agents/vbw-contributor-pr-reviewer.toml"
QA_REVIEW_WORKFLOW="$ROOT/.github/workflows/qa-review.yml"
CONTRIBUTING_DOC="$ROOT/CONTRIBUTING.md"
PR_TEMPLATE="$ROOT/.github/PULL_REQUEST_TEMPLATE.md"

PASS=0
FAIL=0
TMPDIR_BASE=""

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

setup_tmpdir() {
  TMPDIR_BASE=$(mktemp -d)
}

cleanup() {
  [ -n "$TMPDIR_BASE" ] && rm -rf "$TMPDIR_BASE" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== GitHub Fix Workflow Contract Verification ==="

test_copilot_tool_guard_allows_wait_github() {
  local input output rc
  input=$(jq -n \
    '{
      hookEventName: "PreToolUse",
      tool_name: "run_in_terminal",
      tool_input: {
        command: "python3 .github/scripts/wait-github.py wait-ci --repo swt-labs/vibe-better-with-claude-code-vbw --sha deadbeef"
      }
    }')

  output=$(bash "$TOOL_GUARD" <<< "$input" 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 0 ] && ! grep -q 'permissionDecision' <<<"$output"; then
    pass "copilot tool guard allows wait-github helper"
  else
    fail "copilot tool guard should allow wait-github helper (rc=$rc, output=$output)"
  fi
}
test_copilot_tool_guard_allows_wait_github

test_review_contributor_agent_avoids_heredoc() {
  if grep -qF 'scripts/adopt-contributor-pr.sh' "$REVIEW_AGENT" \
    && ! grep -q '<<EOF' "$REVIEW_AGENT"; then
    pass "contributor PR reviewer uses repo helpers instead of heredoc snippets"
  else
    fail "contributor PR reviewer should prefer repo helpers and avoid heredoc snippets"
  fi
}
test_review_contributor_agent_avoids_heredoc

test_fix_issue_record_state_validates_numeric_args() {
  local output rc
  output=$(bash "$RECORD_STATE" abc branch /tmp 123 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 1 ] && grep -q 'pr_number must be a non-negative integer' <<<"$output"; then
    pass "fix-issue-record-state rejects non-numeric PR numbers"
  else
    fail "fix-issue-record-state should reject non-numeric PR numbers (rc=$rc, output=$output)"
  fi

  output=$(bash "$RECORD_STATE" 123 branch /tmp xyz 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 1 ] && grep -q 'issue_number must be a non-negative integer' <<<"$output"; then
    pass "fix-issue-record-state rejects non-numeric issue numbers"
  else
    fail "fix-issue-record-state should reject non-numeric issue numbers (rc=$rc, output=$output)"
  fi
}
test_fix_issue_record_state_validates_numeric_args

test_stop_guard_debug_capture_is_opt_in() {
  if grep -qF 'if [ "${FIX_ISSUE_HOOK_DEBUG:-}" = "1" ]; then' "$STOP_GUARD" \
    && grep -qF 'umask 077' "$STOP_GUARD" \
    && grep -qF 'chmod 700 "$debug_dir"' "$STOP_GUARD" \
    && grep -qF 'chmod 600 "$debug_file"' "$STOP_GUARD"; then
    pass "stop guard debug capture is opt-in and permission-restricted"
  else
    fail "stop guard debug capture should be opt-in with restrictive permissions"
  fi
}
test_stop_guard_debug_capture_is_opt_in

test_stop_guard_ci_gate_uses_exact_head_sha() {
  if grep -qF 'commits/${head_sha}/check-runs?per_page=100' "$STOP_GUARD" \
    && grep -qF 'Remote CI failed on PR #${pr_number}' "$STOP_GUARD" \
    && grep -qF 'Remote CI still running on PR #${pr_number}' "$STOP_GUARD"; then
    pass "stop guard validates remote CI against the exact worktree HEAD SHA"
  else
    fail "stop guard should validate remote CI against exact worktree HEAD SHA"
  fi
}
test_stop_guard_ci_gate_uses_exact_head_sha

test_stop_guard_does_not_require_legacy_bot_review() {
  if ! grep -qF 'latest_matching_copilot_review' "$STOP_GUARD" \
    && ! grep -qF 'copilot-pull-request-reviewer' "$STOP_GUARD" \
    && ! grep -qi 'request a copilot review' "$STOP_GUARD" \
    && ! grep -qi 'fresh copilot review' "$STOP_GUARD"; then
    pass "stop guard no longer requires a legacy bot review gate"
  else
    fail "stop guard should not require or request legacy bot PR reviews"
  fi
}
test_stop_guard_does_not_require_legacy_bot_review

test_fix_issue_pr_gate_requests_codex_review_comment() {
  if grep -qF "gh pr comment <pr-number> --repo swt-labs/vibe-better-with-claude-code-vbw --body '@codex review'" "$PR_CI_GATE_REF" \
    && grep -qF 'Post one Codex review request comment per current head' "$PR_CI_GATE_REF" \
    && grep -qF 'current head commit timestamp' "$PR_CI_GATE_REF" \
    && grep -qF 'Codex remote review request status' "$FIX_SKILL"; then
    pass "Codex fix issue PR gate requests remote Codex review by PR comment"
  else
    fail "Codex fix issue PR gate should request remote Codex review with an @codex review PR comment"
  fi
}
test_fix_issue_pr_gate_requests_codex_review_comment

test_stop_guard_requires_fresh_codex_review_comment() {
  if grep -qF 'comments(last:100)' "$STOP_GUARD" \
    && grep -qF 'gsub("^[[:space:]]+|[[:space:]]+$"; "")) == "@codex review"' "$STOP_GUARD" \
    && grep -qF 'head_commit_ts=$(git show -s --format=%ct HEAD' "$STOP_GUARD" \
    && grep -qF 'does not have an @codex review request comment at or after current HEAD' "$STOP_GUARD" \
    && grep -qF "gh pr comment \${pr_number} --repo \${OWNER}/\${REPO} --body '@codex review'" "$STOP_GUARD"; then
    pass "stop guard requires a fresh @codex review request comment for current HEAD"
  else
    fail "stop guard should block until a fresh @codex review request comment exists for current HEAD"
  fi
}
test_stop_guard_requires_fresh_codex_review_comment

test_recovery_documents_codex_review_request_command() {
  if grep -qF "gh pr comment <pr-number> --repo swt-labs/vibe-better-with-claude-code-vbw --body '@codex review'" "$RECOVERY_REF"; then
    pass "recovery docs include exact Codex remote review request command"
  else
    fail "recovery docs should include the @codex review PR comment recovery command"
  fi
}
test_recovery_documents_codex_review_request_command

test_contributor_pr_review_documents_codex_comment_trigger() {
  if grep -qF "gh pr comment <pr-number> --repo swt-labs/vibe-better-with-claude-code-vbw --body '@codex review'" "$REVIEW_AGENT" \
    && grep -qF 'blind-baseline' "$REVIEW_AGENT"; then
    pass "contributor PR review documents Codex comment trigger without replacing local verdict"
  else
    fail "contributor PR review should document @codex review as the remote review trigger"
  fi
}
test_contributor_pr_review_documents_codex_comment_trigger

test_stop_guard_block_reasons_include_worktree() {
  # All block() calls that reference a PR number should include the worktree path
  # in the human-readable reason text (issue #478).
  local pr_blocks_without_worktree
  # Verify the first quoted argument (reason string) mentions the worktree.
  # Some blocks say "(worktree: ...)" after PR#, others say "worktree '...'" before PR#.
  pr_blocks_without_worktree=$(grep -n 'block ".*PR #' "$STOP_GUARD" \
    | grep -vE 'block "[^"]*worktree[^"]*PR #|block "[^"]*PR #[^"]*worktree' || true)
  if [ -z "$pr_blocks_without_worktree" ]; then
    pass "all PR-referencing block reasons include worktree path in reason string"
  else
    fail "block reasons referencing PR should mention the worktree path in the first quoted reason string: $pr_blocks_without_worktree"
  fi
}
test_stop_guard_block_reasons_include_worktree

test_fix_issue_agent_has_ambient_context_antipattern() {
  if grep -qF 'sole source of truth' "$FIX_SKILL" \
    && grep -qF 'Do not follow ambient terminal context' "$FIX_SKILL" \
    && grep -qF 'unrelated open PRs' "$FIX_SKILL"; then
    pass "Codex fix-issue skill has ambient context and cross-thread contamination guards"
  else
    fail "Codex fix-issue skill should guard against ambient terminal context and cross-thread contamination"
  fi
}
test_fix_issue_agent_has_ambient_context_antipattern

test_fix_issue_agent_reuses_user_authored_plans() {
  if grep -qF 'If the user supplied an execution plan, preserve it as the draft contract' "$ISSUE_INTAKE_REF" \
    && grep -qF 'audit and refine that same plan instead of starting over' "$ISSUE_INTAKE_REF" \
    && grep -qF 'When the caller supplies an existing plan' "$PLANNER_AGENT" \
    && grep -qF 'refine the same plan instead of discarding it' "$PLANNER_AGENT"; then
    pass "Codex fix workflow preserves user-authored plans and audits the same plan"
  else
    fail "Codex fix workflow should preserve user-authored plans and audit the same plan instead of forking a new one"
  fi
}
test_fix_issue_agent_reuses_user_authored_plans

test_fix_planner_agent_supports_existing_plan_audit_mode() {
  if grep -qF 'When the caller supplies an existing plan' "$PLANNER_AGENT" \
    && grep -qF 'audit that plan first' "$PLANNER_AGENT" \
    && grep -qF 'preserve accepted decisions' "$PLANNER_AGENT" \
    && grep -qF 'refine the same plan instead of discarding it' "$PLANNER_AGENT"; then
    pass "Codex fix-planner supports audit mode for existing plans"
  else
    fail "Codex fix-planner should audit existing plans instead of forking a separate refined path"
  fi
}
test_fix_planner_agent_supports_existing_plan_audit_mode

test_qa_review_workflow_has_maintainer_author_bypass() {
  if grep -q 'github.event.pull_request.user.login' "$QA_REVIEW_WORKFLOW" \
    && grep -q 'dpearson2699' "$QA_REVIEW_WORKFLOW" \
    && grep -q 'maintainer_author' "$QA_REVIEW_WORKFLOW"; then
    pass "qa-review workflow skips QA evidence for maintainer-authored PRs"
  else
    fail "qa-review workflow should detect maintainer-authored PRs by login and set a maintainer_author skip reason"
  fi
}
test_qa_review_workflow_has_maintainer_author_bypass

test_qa_review_workflow_has_explicit_maintainer_skip_notice() {
  if grep -q 'Maintainer author skip notice' "$QA_REVIEW_WORKFLOW" \
    && grep -q 'Skipping QA review evidence for PR author @dpearson2699.' "$QA_REVIEW_WORKFLOW"; then
    pass "qa-review workflow emits an explicit maintainer skip notice"
  else
    fail "qa-review workflow should emit an explicit maintainer skip notice"
  fi
}
test_qa_review_workflow_has_explicit_maintainer_skip_notice

test_public_docs_do_not_advertise_private_author_qa_exception() {
  local private_actor_terms exception_terms advertised_exceptions
  private_actor_terms='(maintainer|author|owner|member|collaborator|admin|user|login|actor|dpearson2699|@[[:alnum:]_-]+)'
  exception_terms='(skip|skips|skipping|exempt|exempted|bypass|bypasses|exception|not required|do not require|without QA evidence)'
  advertised_exceptions=$(grep -nEi "(${private_actor_terms}.{0,80}${exception_terms}|${exception_terms}.{0,80}${private_actor_terms})" \
    "$CONTRIBUTING_DOC" "$PR_TEMPLATE" || true)
  if [ -z "$advertised_exceptions" ]; then
    pass "public docs do not advertise private author-based QA exceptions"
  else
    fail "public contributor docs must not advertise private author/identity-based QA evidence exceptions: $advertised_exceptions"
  fi
}
test_public_docs_do_not_advertise_private_author_qa_exception

test_contributing_docs_document_public_pr_automation_statuses() {
  if grep -qF 'What PR automation enforces' "$CONTRIBUTING_DOC" \
    && grep -qF '`Linked Issue Check`' "$CONTRIBUTING_DOC" \
    && grep -qF '`Lint`' "$CONTRIBUTING_DOC" \
    && grep -qF '`Contract Tests`' "$CONTRIBUTING_DOC" \
    && grep -qF '`Bats Tests (shard 0)` through `Bats Tests (shard 7)`' "$CONTRIBUTING_DOC" \
    && grep -qF '`Bats Tests (serial)`' "$CONTRIBUTING_DOC" \
    && grep -qF 'aggregate `Test`' "$CONTRIBUTING_DOC" \
    && grep -qF '`QA Review Evidence`' "$CONTRIBUTING_DOC"; then
    pass "CONTRIBUTING.md documents public PR automation status checks"
  else
    fail "CONTRIBUTING.md should document the public PR automation status checks"
  fi
}
test_contributing_docs_document_public_pr_automation_statuses

test_contributing_docs_document_issue_not_pr_requirement() {
  if grep -qF 'link an actual issue, not just another PR' "$CONTRIBUTING_DOC"; then
    pass "CONTRIBUTING.md distinguishes issue links from PR-only references"
  else
    fail "CONTRIBUTING.md should state that ordinary PRs must link an actual issue, not just another PR"
  fi
}
test_contributing_docs_document_issue_not_pr_requirement

test_contributing_docs_document_qa_evidence_path_rule() {
  if grep -qF 'Docs-only and repo-metadata-only PRs skip QA evidence' "$CONTRIBUTING_DOC" \
    && grep -qF '`.github/workflows/` and `config/` changes are QA-relevant' "$CONTRIBUTING_DOC"; then
    pass "CONTRIBUTING.md documents QA evidence path relevance"
  else
    fail "CONTRIBUTING.md should document docs/repo-metadata skips and workflow/config QA relevance"
  fi
}
test_contributing_docs_document_qa_evidence_path_rule

test_contributing_docs_document_qa_evidence_commit_gate() {
  if grep -qF 'at least 3 QA evidence commits' "$CONTRIBUTING_DOC" \
    && grep -qF 'fix(scope): address QA round N' "$CONTRIBUTING_DOC" \
    && grep -qF 'Clean QA rounds still need an empty evidence commit' "$CONTRIBUTING_DOC"; then
    pass "CONTRIBUTING.md documents the three-commit QA evidence gate"
  else
    fail "CONTRIBUTING.md should document three QA evidence commits, exact pattern, and clean-round empty commits"
  fi
}
test_contributing_docs_document_qa_evidence_commit_gate

test_pr_template_documents_qa_evidence_commit_gate() {
  if grep -qF '3 QA evidence commits' "$PR_TEMPLATE" \
    && grep -qF 'fix(scope): address QA round N' "$PR_TEMPLATE" \
    && grep -qF 'Clean rounds still need an evidence commit' "$PR_TEMPLATE"; then
    pass "PR template documents the three-commit QA evidence gate"
  else
    fail "PR template should document three QA evidence commits, exact pattern, and clean-round evidence commits"
  fi
}
test_pr_template_documents_qa_evidence_commit_gate

test_public_docs_reject_lower_minimum_qa_guidance() {
  local stale_guidance
  stale_guidance=$(grep -nEi '2[–-]4|2 to 4|two to four|at least 2[[:space:]]+QA|minimum 2[[:space:]]+QA|2[[:space:]]+QA[[:space:]]+(review|round|evidence)' \
    "$CONTRIBUTING_DOC" "$PR_TEMPLATE" || true)
  if [ -z "$stale_guidance" ]; then
    pass "public docs do not contain stale lower-minimum QA guidance"
  else
    fail "public docs should not contain stale lower-minimum QA guidance: $stale_guidance"
  fi
}
test_public_docs_reject_lower_minimum_qa_guidance

test_wait_github_fails_fast_on_gh_errors() {
  setup_tmpdir
  cat > "$TMPDIR_BASE/gh" <<'EOF'
#!/usr/bin/env bash
printf 'authentication failed\n' >&2
exit 1
EOF
  chmod +x "$TMPDIR_BASE/gh"

  local output rc
  output=$(PATH="$TMPDIR_BASE:$PATH" python3 "$WAIT_GITHUB" wait-ci --repo swt-labs/vibe-better-with-claude-code-vbw --sha deadbeef 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 3 ] \
    && grep -q 'GH_API_ERROR' <<<"$output" \
    && grep -q 'authentication failed' <<<"$output"; then
    pass "wait-github fails fast with actionable gh api errors"
  else
    fail "wait-github should fail fast on gh api errors (rc=$rc, output=$output)"
  fi

  cleanup
  TMPDIR_BASE=""
}
test_wait_github_fails_fast_on_gh_errors

test_wait_github_treats_non_success_completed_checks_as_failures() {
  setup_tmpdir
  cat > "$TMPDIR_BASE/gh" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
HTTP/2 200
etag: "abc123"

{"total_count":1,"check_runs":[{"name":"ci","status":"completed","conclusion":"timed_out"}]}
OUT
EOF
  chmod +x "$TMPDIR_BASE/gh"

  local output rc
  output=$(PATH="$TMPDIR_BASE:$PATH" python3 "$WAIT_GITHUB" wait-ci --repo swt-labs/vibe-better-with-claude-code-vbw --sha deadbeef 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 2 ] \
    && grep -q 'CI_FAILURE' <<<"$output" \
    && grep -q 'FAILED: ci' <<<"$output"; then
    pass "wait-github treats timed_out check runs as failures"
  else
    fail "wait-github should treat timed_out check runs as failures (rc=$rc, output=$output)"
  fi

  cleanup
  TMPDIR_BASE=""
}
test_wait_github_treats_non_success_completed_checks_as_failures

echo ""
echo "==============================="
echo "--- Fork-aware push timestamp resolution (issue #480) ---"

test_enumerate_queries_fork_metadata() {
  echo "  [contract] enumerate_open_pr_worktrees queries headRepository and headRepositoryOwner"
  local stop_guard="$STOP_GUARD"
  if grep -q 'headRepository' "$stop_guard" \
    && grep -q 'headRepositoryOwner' "$stop_guard"; then
    pass "enumerate_open_pr_worktrees queries fork metadata fields"
  else
    fail "enumerate_open_pr_worktrees must query headRepository and headRepositoryOwner for fork-aware push resolution"
  fi
}
test_enumerate_queries_fork_metadata

test_record_state_accepts_fork_args() {
  echo "  [contract] fix-issue-record-state.sh accepts optional fork_owner and fork_repo args"
  local record_script="$RECORD_STATE"
  if grep -q 'fork_owner' "$record_script" \
    && grep -q 'fork_repo' "$record_script"; then
    pass "fix-issue-record-state.sh handles fork_owner and fork_repo"
  else
    fail "fix-issue-record-state.sh must accept optional fork_owner and fork_repo arguments"
  fi
}
test_record_state_accepts_fork_args

test_enumerate_emits_head_ref_name() {
  echo "  [contract] enumerate_open_pr_worktrees includes headRefName in --json and emits 7-field pipe output"
  local stop_guard="$STOP_GUARD"
  if grep -q 'headRefName' "$stop_guard" \
    && grep -Fq "%s|%s|%s|%s|%s|%s|%s" "$stop_guard"; then
    pass "enumerate emits headRefName as field 7"
  else
    fail "enumerate_open_pr_worktrees must fetch headRefName and emit 7-field pipe output"
  fi
}
test_enumerate_emits_head_ref_name

test_record_state_accepts_head_ref_name() {
  echo "  [contract] fix-issue-record-state.sh accepts optional head_ref_name arg"
  local record_script="$RECORD_STATE"
  if grep -q 'head_ref_name' "$record_script"; then
    pass "fix-issue-record-state.sh handles head_ref_name"
  else
    fail "fix-issue-record-state.sh must accept optional head_ref_name argument"
  fi
}
test_record_state_accepts_head_ref_name
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All GitHub fix workflow contract checks passed."

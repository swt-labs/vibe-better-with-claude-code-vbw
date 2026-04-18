#!/usr/bin/env bash
set -euo pipefail

# verify-github-fix-workflow-contract.sh — Contract checks for local GH fix workflow helpers

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL_GUARD="$ROOT/.github/hooks/copilot-tool-guard.sh"
STOP_GUARD="$ROOT/.github/hooks/fix-issue-stop-guard.sh"
WAIT_GITHUB="$ROOT/.github/scripts/wait-github.py"
RECORD_STATE="$ROOT/.github/scripts/fix-issue-record-state.sh"
REVIEW_AGENT="$ROOT/.github/agents/review-contributor-pr.agent.md"

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
  if [ "$rc" -eq 0 ] && ! printf '%s' "$output" | grep -q 'permissionDecision'; then
    pass "copilot tool guard allows wait-github helper"
  else
    fail "copilot tool guard should allow wait-github helper (rc=$rc, output=$output)"
  fi
}
test_copilot_tool_guard_allows_wait_github

test_review_contributor_agent_avoids_heredoc() {
  if grep -qF 'done < <(git worktree list --porcelain 2>/dev/null)' "$REVIEW_AGENT" \
    && ! grep -q '<<EOF' "$REVIEW_AGENT"; then
    pass "review-contributor agent uses process substitution instead of heredoc"
  else
    fail "review-contributor agent should avoid heredoc in worktree discovery snippet"
  fi
}
test_review_contributor_agent_avoids_heredoc

test_fix_issue_record_state_validates_numeric_args() {
  local output rc
  output=$(bash "$RECORD_STATE" abc branch /tmp 123 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 1 ] && printf '%s' "$output" | grep -q 'pr_number must be a non-negative integer'; then
    pass "fix-issue-record-state rejects non-numeric PR numbers"
  else
    fail "fix-issue-record-state should reject non-numeric PR numbers (rc=$rc, output=$output)"
  fi

  output=$(bash "$RECORD_STATE" 123 branch /tmp xyz 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 1 ] && printf '%s' "$output" | grep -q 'issue_number must be a non-negative integer'; then
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

test_stop_guard_uses_push_derived_timestamp() {
  if grep -q 'pushedDate' "$STOP_GUARD" \
    && ! grep -qF '.commit.committer.date' "$STOP_GUARD"; then
    pass "stop guard uses push-derived timestamps for stale review checks"
  else
    fail "stop guard should prefer push-derived timestamps and avoid commit committer date fallback"
  fi
}
test_stop_guard_uses_push_derived_timestamp

test_stop_guard_matches_review_commit_to_head_sha() {
  if grep -qF 'pulls/${pr_number}/reviews?per_page=100' "$STOP_GUARD" \
    && grep -qF 'select((.commit_id // "") == $head_sha)' "$STOP_GUARD"; then
    pass "stop guard requires Copilot review commit to match current head SHA"
  else
    fail "stop guard should match Copilot review commit_id to head_sha"
  fi
}
test_stop_guard_matches_review_commit_to_head_sha

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
  local agent_file="${ROOT}/.github/agents/fix-issue.agent.md"
  if grep -qF 'Anti-pattern: following ambient terminal context' "$agent_file" \
    && grep -qF 'sole source of truth' "$agent_file" \
    && grep -qF 'Cross-thread contamination guard' "$agent_file"; then
    pass "fix-issue agent has ambient context anti-pattern and cross-thread contamination guards"
  else
    fail "fix-issue agent should contain ambient context anti-pattern warning and cross-thread contamination guard"
  fi
}
test_fix_issue_agent_has_ambient_context_antipattern

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
    && printf '%s' "$output" | grep -q 'GH_API_ERROR' \
    && printf '%s' "$output" | grep -q 'authentication failed'; then
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
    && printf '%s' "$output" | grep -q 'CI_FAILURE' \
    && printf '%s' "$output" | grep -q 'FAILED: ci'; then
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

test_latest_branch_push_at_accepts_four_params() {
  echo "  [contract] latest_branch_push_at accepts ref_owner and ref_repo params"
  local stop_guard=".github/hooks/fix-issue-stop-guard.sh"
  if grep -q 'local ref_owner=.*{3:-' "$stop_guard" \
    && grep -q 'local ref_repo=.*{4:-' "$stop_guard"; then
    pass "latest_branch_push_at accepts ref_owner (\$3) and ref_repo (\$4)"
  else
    fail "latest_branch_push_at must accept ref_owner (\$3) and ref_repo (\$4) for fork-aware push resolution"
  fi
}
test_latest_branch_push_at_accepts_four_params

test_enumerate_queries_fork_metadata() {
  echo "  [contract] enumerate_open_pr_worktrees queries headRepository and headRepositoryOwner"
  local stop_guard=".github/hooks/fix-issue-stop-guard.sh"
  if grep -q 'headRepository' "$stop_guard" \
    && grep -q 'headRepositoryOwner' "$stop_guard"; then
    pass "enumerate_open_pr_worktrees queries fork metadata fields"
  else
    fail "enumerate_open_pr_worktrees must query headRepository and headRepositoryOwner for fork-aware push resolution"
  fi
}
test_enumerate_queries_fork_metadata

test_validate_pr_accepts_fork_params() {
  echo "  [contract] validate_pr accepts head_owner and head_repo params"
  local stop_guard=".github/hooks/fix-issue-stop-guard.sh"
  if grep -q 'local head_owner=.*{5:-' "$stop_guard" \
    && grep -q 'local head_repo=.*{6:-' "$stop_guard"; then
    pass "validate_pr accepts head_owner (\$5) and head_repo (\$6)"
  else
    fail "validate_pr must accept head_owner (\$5) and head_repo (\$6) for fork-aware push resolution"
  fi
}
test_validate_pr_accepts_fork_params

test_record_state_accepts_fork_args() {
  echo "  [contract] fix-issue-record-state.sh accepts optional fork_owner and fork_repo args"
  local record_script=".github/scripts/fix-issue-record-state.sh"
  if grep -q 'fork_owner' "$record_script" \
    && grep -q 'fork_repo' "$record_script"; then
    pass "fix-issue-record-state.sh handles fork_owner and fork_repo"
  else
    fail "fix-issue-record-state.sh must accept optional fork_owner and fork_repo arguments"
  fi
}
test_record_state_accepts_fork_args

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All GitHub fix workflow contract checks passed."

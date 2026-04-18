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
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All GitHub fix workflow contract checks passed."

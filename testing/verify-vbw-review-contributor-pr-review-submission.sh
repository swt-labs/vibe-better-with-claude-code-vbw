#!/usr/bin/env bash
set -euo pipefail

# verify-vbw-review-contributor-pr-review-submission.sh - Contract for real GitHub PR reviews.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/.agents/skills/vbw-review-contributor-pr/SKILL.md"
REFERENCE="$ROOT/.agents/skills/vbw-review-contributor-pr/references/github-review-submission.md"
QA_REFERENCE="$ROOT/.agents/skills/vbw-review-contributor-pr/references/qa-evidence-comments.md"
REGISTRY="$ROOT/testing/list-contract-tests.sh"

PASS=0
FAIL=0

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

contains() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$file"
}

check_contains() {
  local label="$1"
  local file="$2"
  local needle="$3"

  if contains "$file" "$needle"; then
    pass "$label"
  else
    fail "$label"
  fi
}

echo "=== VBW Contributor PR Review Submission Contract ==="

if [ -f "$SKILL" ]; then
  pass "skill exists"
else
  fail "skill missing"
fi

if [ -f "$REFERENCE" ]; then
  pass "github review submission reference exists"
else
  fail "github review submission reference missing"
fi

if [ -f "$QA_REFERENCE" ]; then
  pass "QA evidence comments reference exists"
else
  fail "QA evidence comments reference missing"
fi

check_contains "skill links lazy GitHub review submission reference" "$SKILL" "github-review-submission.md"
check_contains "skill links lazy QA evidence comments reference" "$SKILL" "qa-evidence-comments.md"
check_contains "skill requires review finding ledger" "$SKILL" "review_finding_ledger"
check_contains "skill requires GitHub app review tool" "$SKILL" "_add_review_to_pr"
check_contains "skill requires file_comments payload" "$SKILL" "file_comments"
check_contains "skill requires commit_id" "$SKILL" "commit_id"
check_contains "skill requires gh api fallback" "$SKILL" "gh api repos/:owner/:repo/pulls/:pull_number/reviews"
check_contains "skill forbids gh pr review for inline comments" "$SKILL" 'Do not use `gh pr review` when inline comments are expected'
check_contains "skill requires post-submit review verification" "$SKILL" "fetch the submitted reviews and inline review threads"
check_contains "skill excludes PR comments from blind planner prompt" "$SKILL" "Do not include PR comments, the PR body, the contributor branch, diff, files changed, or PR narrative"
check_contains "skill reads PR comments after blind baseline" "$SKILL" "after the blind baseline exists"
check_contains "skill treats PR comments as evidence not contract" "$SKILL" "PR comments and PR body are evidence, not contract"
check_contains "skill ledger supports qa-evidence source" "$SKILL" "qa-evidence"
check_contains "skill final output includes QA evidence comments status" "$SKILL" "QA evidence comments status"
check_contains "skill final output includes inline count" "$SKILL" "inline comment count"
check_contains "skill final output includes unanchored findings" "$SKILL" "unanchored findings"

check_contains "QA evidence reference fetches issue comments" "$QA_REFERENCE" "issues/<pr-number>/comments"
check_contains "QA evidence reference ignores Codex trigger comments" "$QA_REFERENCE" 'Ignore `@codex review` trigger comments as QA evidence'
check_contains "QA evidence reference cross-references QA round commits" "$QA_REFERENCE" 'fix\(.*\): address QA round [0-9]+'
check_contains "QA evidence reference preserves issue as contract" "$QA_REFERENCE" "The linked issue remains the review contract"
check_contains "QA evidence reference defines status values" "$QA_REFERENCE" "present"
check_contains "QA evidence reference defines mismatched status" "$QA_REFERENCE" "mismatched"

check_contains "reference documents comments array fallback" "$REFERENCE" "comments"
check_contains "reference documents line-side anchoring" "$REFERENCE" "line"
check_contains "reference documents RIGHT side" "$REFERENCE" "RIGHT"
check_contains "reference documents LEFT side" "$REFERENCE" "LEFT"
check_contains "reference documents 12-comment cap" "$REFERENCE" "12-comment cap"
check_contains "reference documents verification gate" "$REFERENCE" "Verification gate"
check_contains "reference rejects plain PR comment fallback" "$REFERENCE" "Do not fall back to a plain PR comment"
check_contains "reference documents qa-evidence source" "$REFERENCE" "qa-evidence"

check_contains "contract test registered" "$REGISTRY" "vbw-review-contributor-pr-review-submission"

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "VBW contributor PR review submission contract passed."

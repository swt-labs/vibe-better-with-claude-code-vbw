#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

AGENTS_MD="$ROOT/AGENTS.md"
CLAUDE_MD="$ROOT/CLAUDE.md"
CONTRIB="$ROOT/CONTRIBUTING.md"

echo "=== Debug Target Docs Contract Verification ==="

if [ -f "$AGENTS_MD" ]; then
  pass "AGENTS.md exists"
else
  fail "AGENTS.md missing"
fi

if git -C "$ROOT" ls-files --error-unmatch -- AGENTS.md >/dev/null 2>&1; then
  pass "AGENTS.md is tracked"
else
  fail "AGENTS.md is not tracked"
fi

if grep -q 'vbw-debug-target.txt' "$AGENTS_MD" 2>/dev/null; then
  pass "AGENTS.md documents the local debug target file"
else
  fail "AGENTS.md missing vbw-debug-target.txt guidance"
fi

if grep -q 'resolve-debug-target.sh' "$AGENTS_MD" 2>/dev/null; then
  pass "AGENTS.md references resolve-debug-target.sh"
else
  fail "AGENTS.md missing resolve-debug-target.sh guidance"
fi

if grep -q 'resolve-claude-dir.sh' "$AGENTS_MD" 2>/dev/null; then
  pass "AGENTS.md references canonical Claude config resolution"
else
  fail "AGENTS.md missing canonical Claude config resolution guidance"
fi

if grep -E '(/Users/[^/[:space:]]+|~/repos/[^[:space:]]+|projects/-Users-[^/[:space:]]+)' "$AGENTS_MD" >/dev/null 2>&1; then
  fail "AGENTS.md still contains maintainer-specific debug target paths"
else
  pass "AGENTS.md contains no maintainer-specific debug target paths"
fi

if grep -q 'vbw-debug-target.txt' "$CONTRIB" 2>/dev/null; then
  pass "CONTRIBUTING.md documents local debug target setup"
else
  fail "CONTRIBUTING.md missing local debug target setup"
fi

if grep -q 'resolve-claude-dir.sh' "$CONTRIB" 2>/dev/null; then
  pass "CONTRIBUTING.md references canonical Claude config resolution"
else
  fail "CONTRIBUTING.md missing canonical Claude config resolution guidance"
fi

if grep -Fq '${CLAUDE_CONFIG_DIR:-$HOME/.claude}/vbw/debug-target.txt' "$AGENTS_MD" 2>/dev/null; then
  fail "AGENTS.md still documents the stale debug-target global fallback path"
else
  pass "AGENTS.md documents the canonical debug-target global fallback path"
fi

if grep -Fq '${CLAUDE_CONFIG_DIR:-$HOME/.claude}/vbw/debug-target.txt' "$CONTRIB" 2>/dev/null; then
  fail "CONTRIBUTING.md still documents the stale debug-target global fallback path"
else
  pass "CONTRIBUTING.md documents the canonical debug-target global fallback path"
fi

if git -C "$ROOT" check-ignore --no-index -q -- AGENTS.md; then
  fail ".gitignore still ignores AGENTS.md"
else
  pass ".gitignore allows AGENTS.md to be tracked"
fi

if git -C "$ROOT" ls-files --error-unmatch -- CLAUDE.md >/dev/null 2>&1; then
  pass "CLAUDE.md is tracked"
else
  fail "CLAUDE.md is not tracked"
fi

if [ -L "$CLAUDE_MD" ]; then
  pass "CLAUDE.md is a symlink"
else
  fail "CLAUDE.md is not a symlink"
fi

if [ -L "$CLAUDE_MD" ] && [ "$(readlink "$CLAUDE_MD")" = "AGENTS.md" ]; then
  pass "CLAUDE.md points to AGENTS.md"
else
  fail "CLAUDE.md does not point to AGENTS.md"
fi

if [ "$(git -C "$ROOT" ls-files -s -- CLAUDE.md 2>/dev/null | awk 'NR == 1 { print $1 }')" = "120000" ]; then
  pass "CLAUDE.md is tracked as a symlink"
else
  fail "CLAUDE.md is not tracked with symlink mode"
fi

if git -C "$ROOT" check-ignore --no-index -q -- CLAUDE.md; then
  fail ".gitignore still ignores CLAUDE.md"
else
  pass ".gitignore allows CLAUDE.md to be tracked"
fi

if git -C "$ROOT" check-ignore --no-index -q -- .claude/vbw-debug-target.txt; then
  pass ".claude/vbw-debug-target.txt remains gitignored"
else
  fail ".claude/vbw-debug-target.txt is no longer gitignored"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

[[ "$FAIL" -eq 0 ]] || exit 1
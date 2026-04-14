#!/usr/bin/env bash
# verify-research-storage-contract.sh — Contract tests for research storage feature.
# Validates structural invariants: script existence, template fields, command references.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1" >&2; }

echo "=== Research Storage Contract ==="

# ── Scripts exist and are executable ─────────────────────

echo ""
echo "Scripts:"

if [ -f "$REPO_ROOT/scripts/research-session-state.sh" ]; then
  pass "scripts/research-session-state.sh exists"
else
  fail "scripts/research-session-state.sh missing"
fi

if [ -x "$REPO_ROOT/scripts/research-session-state.sh" ] || head -1 "$REPO_ROOT/scripts/research-session-state.sh" 2>/dev/null | grep -q 'bash'; then
  pass "research-session-state.sh is a bash script"
else
  fail "research-session-state.sh is not a bash script"
fi

if [ -f "$REPO_ROOT/scripts/compile-research-context.sh" ]; then
  pass "scripts/compile-research-context.sh exists"
else
  fail "scripts/compile-research-context.sh missing"
fi

if [ -x "$REPO_ROOT/scripts/compile-research-context.sh" ] || head -1 "$REPO_ROOT/scripts/compile-research-context.sh" 2>/dev/null | grep -q 'bash'; then
  pass "compile-research-context.sh is a bash script"
else
  fail "compile-research-context.sh is not a bash script"
fi

# ── research-session-state.sh has required subcommands ───

echo ""
echo "Subcommands:"

for cmd in start complete list get latest migrate; do
  if grep -q "^  $cmd)" "$REPO_ROOT/scripts/research-session-state.sh" 2>/dev/null || \
     grep -q "\"$cmd\"" "$REPO_ROOT/scripts/research-session-state.sh" 2>/dev/null || \
     grep -q "  ${cmd}[)|]" "$REPO_ROOT/scripts/research-session-state.sh" 2>/dev/null; then
    pass "research-session-state.sh has '$cmd' subcommand"
  else
    fail "research-session-state.sh missing '$cmd' subcommand"
  fi
done

# ── Template exists with required frontmatter fields ─────

echo ""
echo "Template:"

TEMPLATE="$REPO_ROOT/templates/STANDALONE-RESEARCH.md"
if [ -f "$TEMPLATE" ]; then
  pass "templates/STANDALONE-RESEARCH.md exists"
else
  fail "templates/STANDALONE-RESEARCH.md missing"
fi

for field in title type status confidence base_commit linked_sessions; do
  if grep -q "^${field}:" "$TEMPLATE" 2>/dev/null; then
    pass "template has '$field' frontmatter field"
  else
    fail "template missing '$field' frontmatter field"
  fi
done

# ── Commands reference the new scripts ───────────────────

echo ""
echo "Command references:"

if grep -q 'research-session-state.sh' "$REPO_ROOT/commands/research.md" 2>/dev/null; then
  pass "commands/research.md references research-session-state.sh"
else
  fail "commands/research.md does not reference research-session-state.sh"
fi

if grep -q 'compile-research-context.sh' "$REPO_ROOT/commands/debug.md" 2>/dev/null; then
  pass "commands/debug.md references compile-research-context.sh"
else
  fail "commands/debug.md does not reference compile-research-context.sh"
fi

if grep -q 'compile-research-context.sh' "$REPO_ROOT/commands/fix.md" 2>/dev/null; then
  pass "commands/fix.md references compile-research-context.sh"
else
  fail "commands/fix.md does not reference compile-research-context.sh"
fi

# ── Scripts use set -euo pipefail ────────────────────────

echo ""
echo "Script conventions:"

for script in research-session-state.sh compile-research-context.sh; do
  if grep -q 'set -euo pipefail' "$REPO_ROOT/scripts/$script" 2>/dev/null; then
    pass "$script uses set -euo pipefail"
  else
    fail "$script missing set -euo pipefail"
  fi
done

# ── Summary ──────────────────────────────────────────────

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

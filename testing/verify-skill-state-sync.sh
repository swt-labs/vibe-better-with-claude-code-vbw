#!/usr/bin/env bash
set -euo pipefail

# verify-skill-state-sync.sh — Verify sync-skill-state.sh contract
#
# Checks:
# 1. Script exists and is executable
# 2. Uses jq (not grep/sed on JSON)
# 3. References detect-stack.sh
# 4. Handles STATE.md (### Skills, STATE.md)
# 5. Handles CLAUDE.md (Installed Skills, CLAUDE.md)
# 6. Atomic writes (mv pattern)
# 7. commands/map.md references sync-skill-state.sh
# 8. commands/skills.md references sync-skill-state.sh
# 9. Functional: mock STATE.md with stale ### Skills → verify updated
# 10. Functional: STATE.md without ### Skills but with ## Decisions → verify injected
# 11. Functional: mock CLAUDE.md with placeholder → verify replaced

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

echo "=== Skill State Sync Verification ==="

SCRIPT="$ROOT/scripts/sync-skill-state.sh"

# --- 1. Script exists and is executable ---

if [ -f "$SCRIPT" ]; then
  pass "sync-skill-state.sh: exists"
else
  fail "sync-skill-state.sh: missing"
fi

if [ -x "$SCRIPT" ]; then
  pass "sync-skill-state.sh: is executable"
else
  fail "sync-skill-state.sh: not executable"
fi

# --- 2. Uses jq (not grep/sed on JSON) ---

if grep -q 'jq ' "$SCRIPT"; then
  pass "sync-skill-state.sh: uses jq for JSON parsing"
else
  fail "sync-skill-state.sh: does not use jq"
fi

# --- 3. References detect-stack.sh ---

if grep -q 'detect-stack.sh' "$SCRIPT"; then
  pass "sync-skill-state.sh: references detect-stack.sh"
else
  fail "sync-skill-state.sh: missing detect-stack.sh reference"
fi

# --- 4. Handles STATE.md ---

if grep -q '### Skills' "$SCRIPT" && grep -q 'STATE.md' "$SCRIPT"; then
  pass "sync-skill-state.sh: handles STATE.md ### Skills section"
else
  fail "sync-skill-state.sh: missing STATE.md ### Skills handling"
fi

# --- 5. Handles CLAUDE.md ---

if grep -q 'Installed Skills' "$SCRIPT" && grep -q 'CLAUDE.md' "$SCRIPT"; then
  pass "sync-skill-state.sh: handles CLAUDE.md ## Installed Skills section"
else
  fail "sync-skill-state.sh: missing CLAUDE.md ## Installed Skills handling"
fi

# --- 6. Atomic writes (mv pattern) ---

if grep -q 'mv ' "$SCRIPT"; then
  pass "sync-skill-state.sh: uses atomic mv for writes"
else
  fail "sync-skill-state.sh: missing atomic mv pattern"
fi

# --- 7. commands/map.md references sync-skill-state.sh ---

if grep -q 'sync-skill-state.sh' "$ROOT/commands/map.md"; then
  pass "map.md: references sync-skill-state.sh"
else
  fail "map.md: missing sync-skill-state.sh reference"
fi

# --- 8. commands/skills.md references sync-skill-state.sh ---

if grep -q 'sync-skill-state.sh' "$ROOT/commands/skills.md"; then
  pass "skills.md: references sync-skill-state.sh"
else
  fail "skills.md: missing sync-skill-state.sh reference"
fi

# --- Functional tests ---

FUNC_TMP=$(mktemp -d)
trap 'rm -rf "$FUNC_TMP"' EXIT

# Create mock JSON fixture
cat > "$FUNC_TMP/mock-stack.json" << 'FIXTURE'
{
  "detected_stack": ["swift", "swiftui"],
  "installed": {
    "global": ["find-skills"],
    "project": ["swiftui-expert-skill"],
    "agents": []
  },
  "recommended_skills": ["swiftui-expert-skill", "xcodebuildmcp-cli"],
  "suggestions": ["xcodebuildmcp-cli"],
  "find_skills_available": true
}
FIXTURE

# --- 9. Functional: stale ### Skills → verify updated ---

mkdir -p "$FUNC_TMP/proj9/.vbw-planning"
cat > "$FUNC_TMP/proj9/.vbw-planning/STATE.md" << 'STATE9'
# VBW State

**Project:** TestProject

## Decisions

### Skills
**Installed:** old-skill-1, old-skill-2
**Suggested:** old-suggestion
**Stack detected:** old-stack
**Registry available:** no

## Todos
None.
STATE9

bash "$SCRIPT" "$FUNC_TMP/proj9" "$FUNC_TMP/mock-stack.json" 2>/dev/null

if grep -qF '**Installed:** find-skills, swiftui-expert-skill' "$FUNC_TMP/proj9/.vbw-planning/STATE.md"; then
  pass "functional: stale ### Skills updated with fresh data"
else
  fail "functional: stale ### Skills not updated"
fi

if grep -qF '**Stack detected:** swift, swiftui' "$FUNC_TMP/proj9/.vbw-planning/STATE.md"; then
  pass "functional: stack detected line updated"
else
  fail "functional: stack detected line not updated"
fi

# Verify ## Todos survived the update
if grep -q '## Todos' "$FUNC_TMP/proj9/.vbw-planning/STATE.md"; then
  pass "functional: ## Todos preserved after update"
else
  fail "functional: ## Todos lost during update"
fi

# --- 10. Functional: no ### Skills but ## Decisions exists → inject ---

mkdir -p "$FUNC_TMP/proj10/.vbw-planning"
cat > "$FUNC_TMP/proj10/.vbw-planning/STATE.md" << 'STATE10'
# VBW State

**Project:** TestProject

## Decisions
| Decision | Date | Rationale |
|----------|------|-----------|

## Todos
None.
STATE10

bash "$SCRIPT" "$FUNC_TMP/proj10" "$FUNC_TMP/mock-stack.json" 2>/dev/null

if grep -q '### Skills' "$FUNC_TMP/proj10/.vbw-planning/STATE.md"; then
  pass "functional: ### Skills injected under ## Decisions"
else
  fail "functional: ### Skills not injected"
fi

if grep -qF '**Installed:** find-skills, swiftui-expert-skill' "$FUNC_TMP/proj10/.vbw-planning/STATE.md"; then
  pass "functional: injected section has correct installed data"
else
  fail "functional: injected section has wrong installed data"
fi

# Verify ## Todos still exists after injection
if grep -q '## Todos' "$FUNC_TMP/proj10/.vbw-planning/STATE.md"; then
  pass "functional: ## Todos preserved after injection"
else
  fail "functional: ## Todos lost during injection"
fi

# --- 11. Functional: CLAUDE.md placeholder → replaced ---

mkdir -p "$FUNC_TMP/proj11/.vbw-planning"
# Minimal STATE.md so script doesn't skip
cat > "$FUNC_TMP/proj11/.vbw-planning/STATE.md" << 'STATE11'
# VBW State

**Project:** TestProject

## Decisions

### Skills
**Installed:** old
**Suggested:** old
**Stack detected:** old
**Registry available:** no
STATE11

cat > "$FUNC_TMP/proj11/CLAUDE.md" << 'CLAUDE11'
# My Project

Some existing content.

## Installed Skills

_(Run /vbw:skills to list)_

## Commands

Run /vbw:status for current progress.
CLAUDE11

bash "$SCRIPT" "$FUNC_TMP/proj11" "$FUNC_TMP/mock-stack.json" 2>/dev/null

if grep -q 'find-skills, swiftui-expert-skill' "$FUNC_TMP/proj11/CLAUDE.md"; then
  pass "functional: CLAUDE.md ## Installed Skills updated with skill names"
else
  fail "functional: CLAUDE.md ## Installed Skills not updated"
fi

# Verify non-VBW content preserved
if grep -q '# My Project' "$FUNC_TMP/proj11/CLAUDE.md"; then
  pass "functional: CLAUDE.md non-VBW content preserved"
else
  fail "functional: CLAUDE.md non-VBW content lost"
fi

# Verify ## Commands still present
if grep -q '## Commands' "$FUNC_TMP/proj11/CLAUDE.md"; then
  pass "functional: CLAUDE.md ## Commands preserved"
else
  fail "functional: CLAUDE.md ## Commands lost"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All skill state sync checks passed."
exit 0

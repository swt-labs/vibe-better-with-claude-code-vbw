#!/usr/bin/env bash
set -euo pipefail

# verify-lead-research-conditional.sh — Verify Lead agent research-conditional Stage 1 + LSP preference

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

echo "=== Lead Agent Research-Conditional Stage 1 Verification ==="

LEAD="$ROOT/agents/vbw-lead.md"
COMPILE="$ROOT/scripts/compile-context.sh"
CACHE="$ROOT/scripts/cache-context.sh"

# --- vbw-lead.md: Research-conditional scanning ---

if grep -q "If RESEARCH.md exists" "$LEAD"; then
  pass "lead: research-available fast path present"
else
  fail "lead: missing research-available fast path"
fi

if grep -q "If no RESEARCH.md exists" "$LEAD"; then
  pass "lead: no-research scanning path present"
else
  fail "lead: missing no-research scanning path"
fi

if grep -q "Do NOT do broad exploratory scanning" "$LEAD"; then
  pass "lead: broad-scan prohibition when research exists"
else
  fail "lead: missing broad-scan prohibition when research exists"
fi

if grep -q "Trust the research" "$LEAD"; then
  pass "lead: trust-research directive present"
else
  fail "lead: missing trust-research directive"
fi

# NOTE: Lead LSP preference checks moved to verify-lsp-first-policy.sh (repo-wide coverage)

# --- vbw-lead.md: unconditional "Scan codebase via Glob/Grep" must be gone ---

if grep -q "^Read:.*Scan codebase via Glob/Grep" "$LEAD"; then
  fail "lead: old unconditional 'Scan codebase via Glob/Grep' still present"
else
  pass "lead: old unconditional scan removed"
fi

# --- compile-context.sh: codebase mapping hint conditional on research ---

LEAD_SECTION=$(sed -n '/^  lead)/,/^  ;;$/p' "$COMPILE")
if echo "$LEAD_SECTION" | grep -B5 "emit_codebase_mapping_hint ARCHITECTURE CONCERNS STRUCTURE" | grep -q "else"; then
  pass "compile-context: hint is in else branch of research check"
else
  fail "compile-context: hint not in else branch of research check"
fi

if echo "$LEAD_SECTION" | grep -q "no research exists"; then
  pass "compile-context: codebase mapping hint conditional on no-research"
else
  fail "compile-context: codebase mapping hint not conditional on research"
fi

# --- cache-context.sh: research file hash for lead role ---

if grep -q 'ROLE.*=.*"lead"' "$CACHE" && grep -q 'research=' "$CACHE"; then
  pass "cache-context: lead role includes research in hash"
else
  fail "cache-context: lead role missing research in hash"
fi

if grep -q 'research=none' "$CACHE"; then
  pass "cache-context: hash differentiates no-research vs research-present"
else
  fail "cache-context: hash does not differentiate no-research case"
fi

# NOTE: Per-agent LSP preference checks moved to verify-lsp-first-policy.sh (repo-wide coverage)

# --- Behavioral: compile-context.sh cache invalidation for research ---

echo ""
echo "=== Behavioral Tests (compile-context + cache) ==="

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Scaffold minimal VBW structure
mkdir -p "$TMP/.vbw-planning/phases/02-build"
mkdir -p "$TMP/.vbw-planning/.cache/context"
cat > "$TMP/.vbw-planning/config.json" <<'CONF'
{"project_name": "test"}
CONF
cat > "$TMP/.vbw-planning/ROADMAP.md" <<'ROAD'
## Phase 2: Build
**Goal:** Build things
**Success Criteria:** It works
**Requirements:** REQ-01
ROAD
cat > "$TMP/.vbw-planning/REQUIREMENTS.md" <<'REQ'
- [ ] REQ-01: Build something
REQ

# Test 1: Compile without research — should include codebase mapping hint
(cd "$TMP" && bash "$ROOT/scripts/compile-context.sh" 02 lead .vbw-planning/phases > /dev/null 2>&1) || true
if [ -f "$TMP/.vbw-planning/phases/02-build/.context-lead.md" ]; then
  CTX1="$TMP/.vbw-planning/phases/02-build/.context-lead.md"
  if grep -q "Research Findings" "$CTX1"; then
    fail "behavioral: no-research compile should not have Research Findings"
  else
    pass "behavioral: no-research compile has no Research Findings"
  fi
else
  fail "behavioral: compile-context.sh did not produce .context-lead.md"
fi

# Test 2: Get cache hash without research
HASH1=$(cd "$TMP" && bash "$ROOT/scripts/cache-context.sh" 02 lead .vbw-planning/config.json 2>/dev/null | awk '{print $2}') || HASH1="error1"

# Test 3: Add research file, recompile — should include Research Findings
cat > "$TMP/.vbw-planning/phases/02-build/02-RESEARCH.md" <<'RES'
## Research
Scout found things.
RES

(cd "$TMP" && bash "$ROOT/scripts/compile-context.sh" 02 lead .vbw-planning/phases > /dev/null 2>&1) || true
CTX2="$TMP/.vbw-planning/phases/02-build/.context-lead.md"
if [ -f "$CTX2" ] && grep -q "Research Findings" "$CTX2"; then
  pass "behavioral: research-present compile includes Research Findings"
else
  fail "behavioral: research-present compile missing Research Findings"
fi

# Test 4: Research present should suppress codebase mapping hint
if [ -f "$CTX2" ] && grep -q "bootstrap codebase understanding" "$CTX2"; then
  fail "behavioral: research-present compile should not have mapping hint"
else
  pass "behavioral: research-present compile suppresses mapping hint"
fi

# Test 5: Cache hash should differ after research added
HASH2=$(cd "$TMP" && bash "$ROOT/scripts/cache-context.sh" 02 lead .vbw-planning/config.json 2>/dev/null | awk '{print $2}') || HASH2="error2"
if [ "$HASH1" != "$HASH2" ] && [ "$HASH1" != "error1" ] && [ "$HASH2" != "error2" ]; then
  pass "behavioral: cache hash changes when research appears"
else
  fail "behavioral: cache hash unchanged after research added (was=$HASH1, now=$HASH2)"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS passed, $FAIL failed"
echo "==============================="

[[ "$FAIL" -eq 0 ]]

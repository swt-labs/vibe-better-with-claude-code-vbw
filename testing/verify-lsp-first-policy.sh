#!/usr/bin/env bash
set -euo pipefail

# verify-lsp-first-policy.sh — Verify all LSP-capable agents follow the repo-wide LSP-first policy

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

echo "=== Repo-Wide LSP-First Policy Verification ==="

# --- Shared reference document ---

POLICY="$ROOT/references/lsp-first-policy.md"

if [[ -f "$POLICY" ]]; then
  pass "references/lsp-first-policy.md exists"
else
  fail "references/lsp-first-policy.md missing"
fi

if grep -q "LSP.*first\|prefer LSP\|Prefer.*LSP" "$POLICY" 2>/dev/null; then
  pass "policy doc states LSP-first rule"
else
  fail "policy doc missing LSP-first rule"
fi

if grep -q "Search/Grep/Glob" "$POLICY" 2>/dev/null; then
  pass "policy doc covers Search/Grep/Glob fallback scope"
else
  fail "policy doc missing Search/Grep/Glob fallback scope"
fi

if grep -q "LSP is unavailable\|LSP.*error" "$POLICY" 2>/dev/null; then
  pass "policy doc covers LSP unavailable fallback"
else
  fail "policy doc missing LSP unavailable fallback"
fi

# --- All LSP-capable agents: LSP-first guidance ---

echo ""
echo "--- Agent LSP-first guidance checks ---"

# Agents with LSP in their tools list
LSP_AGENTS=("vbw-scout" "vbw-architect" "vbw-lead" "vbw-dev" "vbw-qa" "vbw-debugger" "vbw-docs")

for agent in "${LSP_AGENTS[@]}"; do
  AGENT_FILE="$ROOT/agents/${agent}.md"
  SHORT_NAME="${agent#vbw-}"

  if [[ ! -f "$AGENT_FILE" ]]; then
    fail "${SHORT_NAME}: agent file missing"
    continue
  fi

  # Verify LSP is in the tools list (or inherited via context for Dev)
  if head -10 "$AGENT_FILE" | grep -q "LSP"; then
    pass "${SHORT_NAME}: LSP in tools list"
  elif [[ "$agent" == "vbw-dev" ]] && grep -q "Prefer.*LSP\|prefer.*LSP" "$AGENT_FILE"; then
    pass "${SHORT_NAME}: LSP inherited (tools via context), LSP guidance present"
  else
    fail "${SHORT_NAME}: LSP missing from tools list"
  fi

  # Verify LSP-first preference wording (case-insensitive)
  if grep -qi "Prefer.*LSP.*(go-to-definition, find-references" "$AGENT_FILE"; then
    pass "${SHORT_NAME}: LSP-first preference instruction present"
  else
    fail "${SHORT_NAME}: missing LSP-first preference instruction"
  fi

  # Verify LSP unavailable/error fallback guard
  if grep -q "LSP is unavailable or errors.*fall back immediately" "$AGENT_FILE"; then
    pass "${SHORT_NAME}: LSP unavailable fallback guard present"
  else
    fail "${SHORT_NAME}: missing LSP unavailable fallback guard"
  fi

  # Verify explicit Search/Grep/Glob fallback boundaries
  if grep -q "Search/Grep/Glob" "$AGENT_FILE"; then
    pass "${SHORT_NAME}: explicit Search/Grep/Glob fallback boundaries"
  else
    fail "${SHORT_NAME}: missing explicit Search/Grep/Glob fallback boundaries"
  fi

  # Verify reference to shared policy doc
  if grep -q "lsp-first-policy.md" "$AGENT_FILE"; then
    pass "${SHORT_NAME}: references lsp-first-policy.md"
  else
    fail "${SHORT_NAME}: missing reference to lsp-first-policy.md"
  fi
done

# --- Lead-specific: research-present path ---

echo ""
echo "--- Lead research-present path LSP checks ---"

LEAD="$ROOT/agents/vbw-lead.md"

if grep -q "If RESEARCH.md exists" "$LEAD"; then
  pass "lead: research-available fast path present"
else
  fail "lead: missing research-available fast path"
fi

# Research-present path should still allow targeted LSP
if grep -A5 "If RESEARCH.md exists" "$LEAD" | grep -q "prefer.*LSP\|LSP.*(go-to-definition"; then
  pass "lead: research-present path allows targeted LSP validation"
else
  fail "lead: research-present path missing targeted LSP validation"
fi

# Research-present path should prohibit broad scans
if grep -q "Do NOT do broad exploratory scanning" "$LEAD"; then
  pass "lead: broad-scan prohibition when research exists"
else
  fail "lead: missing broad-scan prohibition when research exists"
fi

if grep -q "If no RESEARCH.md exists" "$LEAD"; then
  pass "lead: no-research scanning path present"
else
  fail "lead: missing no-research scanning path"
fi

# --- Bootstrap / init: Code Intelligence guidance ---

echo ""
echo "--- Bootstrap & init LSP guidance checks ---"

BOOTSTRAP="$ROOT/scripts/bootstrap/bootstrap-claude.sh"
CLAUDE_LIB="$ROOT/scripts/lib/claude-md-vbw-sections.sh"
INIT="$ROOT/commands/init.md"

# Shared CLAUDE section helper is the source of truth for generated Code Intelligence content.
if grep -q "Search/Grep/Glob" "$CLAUDE_LIB"; then
  pass "bootstrap: Code Intelligence uses Search/Grep/Glob fallback language"
else
  fail "bootstrap: Code Intelligence missing Search/Grep/Glob fallback language"
fi

if grep -q "Prefer LSP over Search/Grep/Glob" "$CLAUDE_LIB"; then
  pass "bootstrap: Code Intelligence has LSP-first-over-Search language"
else
  fail "bootstrap: Code Intelligence missing LSP-first-over-Search language"
fi

# Init should delegate generation to bootstrap and describe the non-destructive Code Intelligence rule.
if grep -q "bootstrap-claude.sh" "$INIT"; then
  pass "init: delegates CLAUDE generation to bootstrap-claude.sh"
else
  fail "init: missing bootstrap-claude.sh delegation for CLAUDE generation"
fi

if grep -q "Code Intelligence heading/guidance already exists" "$INIT"; then
  pass "init: documents no-duplicate Code Intelligence rule"
else
  fail "init: missing no-duplicate Code Intelligence rule"
fi

# --- Contributor docs: LSP-first convention ---

echo ""
echo "--- Contributor docs LSP-first convention checks ---"

AGENTS_MD="$ROOT/AGENTS.md"
CONTRIB="$ROOT/CONTRIBUTING.md"

if grep -q "LSP-first.*code navigation\|lsp-first-policy.md" "$AGENTS_MD"; then
  pass "AGENTS.md: LSP-first convention documented"
else
  fail "AGENTS.md: missing LSP-first convention"
fi

if grep -q "LSP-first.*policy\|lsp-first-policy.md" "$CONTRIB"; then
  pass "CONTRIBUTING.md: LSP-first policy referenced"
else
  fail "CONTRIBUTING.md: missing LSP-first policy reference"
fi

# --- Summary ---

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

[[ "$FAIL" -eq 0 ]] || exit 1

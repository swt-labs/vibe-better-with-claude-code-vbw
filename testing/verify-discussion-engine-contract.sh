#!/usr/bin/env bash
set -euo pipefail

# verify-discussion-engine-contract.sh — Verify discussion engine structural contracts

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

require_file_literal() {
  local desc="$1"
  local needle="$2"
  local file="$3"

  if [ -f "$file" ] && grep -Fq -- "$needle" "$file"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

require_file_regex() {
  local desc="$1"
  local pattern="$2"
  local file="$3"

  if [ -f "$file" ] && grep -Eq -- "$pattern" "$file"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

require_text_literal() {
  local desc="$1"
  local needle="$2"
  local text="$3"

  if grep -Fq -- "$needle" <<< "$text"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

require_text_regex() {
  local desc="$1"
  local pattern="$2"
  local text="$3"

  if grep -Eq -- "$pattern" <<< "$text"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

extract_heading_block() {
  local file="$1"
  local heading="$2"
  local end_regex="$3"

  awk -v h="$heading" -v end_re="$end_regex" '
    function trim_line(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }

    {
      line=$0
      gsub(/\r/, "", line)
      trimmed=trim_line(line)

      if (trimmed == h) {
        found=1
        print line
        next
      }

      if (found && trimmed ~ end_re) {
        exit
      }

      if (found) {
        print line
      }
    }
  ' "$file"
}

echo "=== Discussion Engine Contract Verification ==="

ENGINE="$ROOT/references/discussion-engine.md"

# --- Confidence indicators in A5 presentation ---

for indicator in "✓ confirmed" "⚡ validated" "? resolved" "✗ corrected" "○ expanded"; do
  if grep -q "$indicator" "$ENGINE"; then
    pass "engine: contains confidence indicator '$indicator'"
  else
    fail "engine: missing confidence indicator '$indicator'"
  fi
done

# --- A5 has user-facing presentation instruction ---

if grep -q "present a summary" "$ENGINE"; then
  pass "engine: A5 has user-facing presentation instruction"
else
  fail "engine: A5 missing user-facing presentation instruction"
fi

# --- Step 1.7 exists ---

if grep -q "Step 1.7" "$ENGINE"; then
  pass "engine: Step 1.7 (Assumptions Path) exists"
else
  fail "engine: Step 1.7 (Assumptions Path) missing"
fi

# --- Codebase map guard ---

if grep -q "META.md" "$ENGINE"; then
  pass "engine: codebase map guard references META.md"
else
  fail "engine: codebase map guard missing META.md reference"
fi

# --- Shared AskUserQuestion contract and local structured/freeform boundary ---

SHARED_BLOCK="$(extract_heading_block "$ENGINE" "## Shared interaction contract" '^## ' || true)"

if [ -n "$SHARED_BLOCK" ]; then
  pass "engine: shared interaction contract block extracted"
else
  fail "engine: shared interaction contract block extracted"
fi

require_text_literal "engine: shared block points to ask-user-question reference" "references/ask-user-question.md" "$SHARED_BLOCK"
require_file_regex "engine: documents bounded choices as structured AskUserQuestion" 'bounded (discussion )?decisions?.*structured AskUserQuestion|structured AskUserQuestion.*bounded (discussion )?decisions?' "$ENGINE"
require_file_regex "engine: documents larger selections as freeform/no-options" '(5[-–]6|more than four|exceed four).*freeform|freeform.*(5[-–]6|more than four|exceed four)' "$ENGINE"
require_file_literal "engine: freeform selection forbids options array" 'do NOT use `options` array' "$ENGINE"
require_file_regex "engine: Step 2 distinguishes 1-4 vs 5-6 gray areas" '1[-–]4 gray areas.*structured|5[-–]6 gray areas.*freeform|1[-–]4.*structured multi-select|5[-–]6.*numbered/freeform' "$ENGINE"
require_file_literal "engine: Let me explain stops AskUserQuestion" 'stop using AskUserQuestion' "$ENGINE"
require_file_regex "engine: Let me explain asks plain-text follow-up and waits" 'plain-text follow-up.*wait|wait.*plain-text follow-up' "$ENGINE"
require_file_regex "engine: Builder sample is clearly marked as an example" '<example[^>]*Builder|label="Builder"' "$ENGINE"
require_file_regex "engine: Architect sample is clearly marked as an example" '<example[^>]*Architect|label="Architect"' "$ENGINE"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

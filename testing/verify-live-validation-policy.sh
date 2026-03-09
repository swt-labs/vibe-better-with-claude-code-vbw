#!/usr/bin/env bash
set -euo pipefail

# verify-live-validation-policy.sh — Verify live-validation and API tool-choice policy
#
# Checks:
# - execute-protocol.md has validation-before-code hard gate
# - execute-protocol.md routes authenticated API validation to Bash
# - vbw-scout.md distinguishes public WebFetch vs authenticated validation
# - vbw-scout.md handles empty/contradictory results
# - commands/vibe.md does not over-prescribe WebFetch for auth-required APIs

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXEC_PROTO="$ROOT/references/execute-protocol.md"
SCOUT_FILE="$ROOT/agents/vbw-scout.md"
VIBE_FILE="$ROOT/commands/vibe.md"

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

echo "=== Live Validation Policy Verification ==="

# --- execute-protocol.md checks ---

# 1. Validation-before-code hard gate
if grep -qi 'validation.*gate\|validation.*before.*code\|pre.code.*validation\|validation.*must.*pass.*before' "$EXEC_PROTO"; then
  pass "execute-protocol.md: validation-before-code gate present"
else
  fail "execute-protocol.md: missing validation-before-code gate"
fi

# 2. Contradictory/empty results trigger blocker
if grep -qi 'contradictory.*blocker\|contradictory.*escalat\|empty.*result.*blocker\|empty.*result.*escalat\|contradiction.*remains.*blocker\|empty.*result.*contradictory\|empty.*not.*success' "$EXEC_PROTO"; then
  pass "execute-protocol.md: contradictory/empty results trigger blocker"
else
  fail "execute-protocol.md: missing contradictory/empty result escalation"
fi

# 3. Authenticated API routed to Bash
if grep -qi 'authenticated.*bash\|private.*API.*bash\|auth.*API.*bash\|curl\|bash.*helper.*script' "$EXEC_PROTO"; then
  pass "execute-protocol.md: authenticated APIs routed to Bash"
else
  fail "execute-protocol.md: missing authenticated API → Bash routing"
fi

# --- vbw-scout.md checks ---

# 4. Public vs authenticated distinction
if grep -qi 'public.*WebFetch\|anonymous.*WebFetch\|authenticated.*live.*validation\|REQUIRES.*AUTHENTICATED\|private.*API' "$SCOUT_FILE"; then
  pass "vbw-scout.md: distinguishes public vs authenticated validation"
else
  fail "vbw-scout.md: missing public-vs-authenticated distinction"
fi

# 5. Empty/contradictory response handling
if grep -qi 'empty.*response\|empty.*result\|contradictory.*finding\|contradiction.*explicit\|broaden.*query' "$SCOUT_FILE"; then
  pass "vbw-scout.md: handles empty/contradictory responses"
else
  fail "vbw-scout.md: missing empty/contradictory response handling"
fi

# --- commands/vibe.md checks ---

# 6. Remediation path does not blanket-prescribe WebFetch for auth APIs
#    (Positive check: vibe.md mentions the auth-vs-public distinction somewhere)
if grep -qi 'authenticated.*live.*validation\|REQUIRES.*AUTHENTICATED\|auth.*API.*bash\|private.*API.*Dev\|bash.capable.*execution' "$VIBE_FILE"; then
  pass "commands/vibe.md: mentions authenticated validation routing"
else
  fail "commands/vibe.md: missing authenticated-validation routing guidance"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="
[ "$FAIL" -eq 0 ] || exit 1

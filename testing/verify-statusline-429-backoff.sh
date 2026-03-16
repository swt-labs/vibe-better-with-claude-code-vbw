#!/usr/bin/env bash
set -euo pipefail

# verify-statusline-429-backoff.sh — Contract tests for #249
# Verifies: 429 → stale status, failure backoff (300s), DISABLE_NONESSENTIAL_TRAFFIC

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SL="$ROOT/scripts/vbw-statusline.sh"

PASS=0
FAIL=0

pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL + 1)); }

# --- Test 1: 429 handled distinctly from generic failure ---
if grep -q 'HTTP_CODE.*=.*"429"' "$SL" && grep -q 'FETCH_OK="stale"' "$SL"; then
  pass "429 maps to FETCH_OK=stale (not fail)"
else
  fail "429 maps to FETCH_OK=stale (not fail)"
fi

# --- Test 2: stale state renders actionable message ---
if grep -q 'FETCH_OK.*=.*"stale"' "$SL" && grep -q 'token stale.*re-login' "$SL"; then
  pass "stale state renders actionable re-login message"
else
  fail "stale state renders actionable re-login message"
fi

# --- Test 3: backoff reads previous FETCH_OK from slow cache ---
if grep -q '_PREV_STATUS.*awk.*SLOW_CF' "$SL"; then
  pass "backoff reads previous status from slow cache"
else
  fail "backoff reads previous status from slow cache"
fi

# --- Test 4: backoff escalates TTL on fail or stale ---
if grep -q '_PREV_STATUS.*=.*"fail"\|_PREV_STATUS.*=.*"stale"' "$SL" && grep -q '_SLOW_TTL=300' "$SL"; then
  pass "backoff escalates TTL to 300s on persistent failure/stale"
else
  fail "backoff escalates TTL to 300s on persistent failure/stale"
fi

# --- Test 5: default slow TTL is 60s ---
if grep -q '_SLOW_TTL=60' "$SL"; then
  pass "default slow cache TTL is 60s"
else
  fail "default slow cache TTL is 60s"
fi

# --- Test 6: CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC respected ---
if grep -q 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC' "$SL"; then
  pass "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC is checked"
else
  fail "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC is checked"
fi

# --- Test 7: notraffic skips usage fetch entirely ---
if grep -q 'FETCH_OK="notraffic"' "$SL" && grep -q '"$FETCH_OK" = "notraffic"' "$SL"; then
  pass "notraffic status skips usage fetch"
else
  fail "notraffic status skips usage fetch"
fi

# --- Test 8: notraffic renders informational message ---
if grep -q 'nonessential traffic disabled' "$SL"; then
  pass "notraffic state renders informational message"
else
  fail "notraffic state renders informational message"
fi

# --- Test 9: stale retry message says 5m (not 60s) ---
if grep -q 'retry in 5m' "$SL" && ! grep -q 'retry in 60s' "$SL"; then
  pass "retry message says 5m (not 60s) for both fail and stale"
else
  fail "retry message says 5m (not 60s) for both fail and stale"
fi

echo ""
echo "TOTAL: $PASS PASS, $FAIL FAIL"
[ "$FAIL" -eq 0 ] || exit 1

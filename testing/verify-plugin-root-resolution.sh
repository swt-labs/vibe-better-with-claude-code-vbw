#!/usr/bin/env bash
set -euo pipefail

# verify-plugin-root-resolution.sh — Ensure CLAUDE_PLUGIN_ROOT resolves deterministically
#
# Problem: ${CLAUDE_PLUGIN_ROOT} is available in Claude Code's process env (for @ file
# references) but NOT in the Bash tool's shell environment or !` backtick subprocesses.
# Model-executed bash commands that reference ${CLAUDE_PLUGIN_ROOT} expand to empty.
#
# Fix: Each command file resolves the plugin root ONCE at load time (via !` backtick with
# a fallback ls chain), creates a per-session symlink at a deterministic path:
#   /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}
# Subsequent load-time references construct this same path independently via echo — no
# shared mutable temp file is involved.
#
# Safe contexts (all refs must be in one of these):
#   - echo /tmp/.vbw-plugin-root-link-... (deterministic path construction — standard reader)
#   - LINK="/tmp/.vbw-plugin-root-link-*" (canonical no-space symlink in preamble)
#   - !`...${CLAUDE_PLUGIN_ROOT:-...}...` (resolve line with fallback)
#   - @${CLAUDE_PLUGIN_ROOT}/...         (file inclusion at load time)
#   - Plugin root: ...                   (preamble resolve+write line)
#   - Runtime resolver guard line in execute-protocol.md:
#       if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]
#       VBW_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
#
# Unsafe (must not exist):
#   - bare ${CLAUDE_PLUGIN_ROOT} in model-executed text (resolves to empty in bash)
#   - `!`echo $CLAUDE_PLUGIN_ROOT` without fallback (resolves to empty in subshell)
#   - cat /tmp/.vbw-plugin-root (legacy shared temp file read — eliminated)
#   - printf.*> /tmp/.vbw-plugin-root (legacy shared temp file write — eliminated)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMANDS_DIR="$ROOT/commands"
REFERENCES_DIR="$ROOT/references"

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

echo "=== Plugin Root Inline Resolution Verification ==="

for file in "$COMMANDS_DIR"/*.md "$REFERENCES_DIR"/*.md; do
  base="$(basename "$file" .md)"

  # Skip files with no CLAUDE_PLUGIN_ROOT references at all
  if ! grep -q 'CLAUDE_PLUGIN_ROOT' "$file"; then
    pass "$base: no CLAUDE_PLUGIN_ROOT references"
    continue
  fi

  # Count total references
  total_refs=$(grep -c 'CLAUDE_PLUGIN_ROOT' "$file" || true)

  # Count lines with CLAUDE_PLUGIN_ROOT that are NOT in any safe context.
  # Safe contexts: !` backtick expressions, @ file references, Plugin root: preamble,
  # and inline `!`echo $CLAUDE_PLUGIN_ROOT` resolution patterns.
  unsafe_count=$(grep 'CLAUDE_PLUGIN_ROOT' "$file" \
    | grep -v '!`[^`]*CLAUDE_PLUGIN_ROOT' \
    | grep -v '@${CLAUDE_PLUGIN_ROOT}' \
    | grep -v 'Plugin root:' \
    | grep -v 'if \[ -n "${CLAUDE_PLUGIN_ROOT:-}" \] && \[ -[df] "${CLAUDE_PLUGIN_ROOT}' \
    | grep -v 'VBW_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"' \
    | grep -v 'checked CLAUDE_PLUGIN_ROOT' \
    | grep -vc '`!`echo .*CLAUDE_PLUGIN_ROOT' || true)

  if [ "$unsafe_count" -eq 0 ]; then
    pass "$base: all $total_refs references are in safe contexts (inline !-backtick or @ file ref)"
  else
    fail "$base: $unsafe_count CLAUDE_PLUGIN_ROOT refs in model-executed context (not inline-resolved)"
    # Show the offending lines for debugging
    grep -n 'CLAUDE_PLUGIN_ROOT' "$file" \
      | grep -v '!`[^`]*CLAUDE_PLUGIN_ROOT' \
      | grep -v '@${CLAUDE_PLUGIN_ROOT}' \
      | grep -v 'Plugin root:' \
      | grep -v 'if \[ -n "${CLAUDE_PLUGIN_ROOT:-}" \] && \[ -[df] "${CLAUDE_PLUGIN_ROOT}' \
      | grep -v 'VBW_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"' \
      | grep -v 'checked CLAUDE_PLUGIN_ROOT' \
      | grep -v '`!`echo .*CLAUDE_PLUGIN_ROOT' \
      | while IFS= read -r line; do echo "      $line"; done
  fi
done

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All plugin root inline resolution checks passed."
echo ""

# --- Phase 2: Verify preamble !` backtick expansions have CLAUDE_CONFIG_DIR fallback ---
echo "=== Preamble Fallback Verification ==="
echo "(Ensures preamble !-backtick CLAUDE_PLUGIN_ROOT refs include :-fallback for non-standard installs)"

PASS2=0
FAIL2=0

for file in "$COMMANDS_DIR"/*.md "$REFERENCES_DIR"/*.md; do
  base="$(basename "$file" .md)"

  # Only check preamble !` backtick expressions (those using ${CLAUDE_PLUGIN_ROOT} with braces).
  # These are resolve-and-write lines that resolve the plugin root with a fallback chain
  # and write the result to /tmp/.vbw-plugin-root for subsequent use.
  backtick_lines=$(grep -n 'CLAUDE_PLUGIN_ROOT' "$file" \
    | grep '!`[^`]*\${CLAUDE_PLUGIN_ROOT' || true)

  [ -z "$backtick_lines" ] && continue

  # For each matching line, check it uses the :- fallback pattern
  has_bare=0
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    if echo "$match" | grep -q 'CLAUDE_PLUGIN_ROOT:-'; then
      : # has fallback, safe
    else
      has_bare=1
      lineno="${match%%:*}"
      echo "  BARE  $base:$lineno — missing :-fallback in preamble !-backtick expansion"
    fi
  done <<< "$backtick_lines"

  if [ "$has_bare" -eq 0 ]; then
    echo "PASS  $base: all preamble !-backtick CLAUDE_PLUGIN_ROOT refs have :-fallback"
    PASS2=$((PASS2 + 1))
  else
    fail "$base: has preamble !-backtick CLAUDE_PLUGIN_ROOT without :-fallback"
    FAIL2=$((FAIL2 + 1))
  fi
done

if [ "$PASS2" -eq 0 ] && [ "$FAIL2" -eq 0 ]; then
  echo "(no preamble !-backtick CLAUDE_PLUGIN_ROOT expansions found — nothing to check)"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS2 PASS, $FAIL2 FAIL"
echo "==============================="

if [ "$FAIL2" -gt 0 ]; then
  exit 1
fi

echo "All preamble fallback checks passed."

# --- Phase 3: Runtime resolver safety ---
echo ""
echo "=== Runtime Resolver Safety Verification ==="

# Reset counters so Phase 3 TOTAL reflects only Phase 3 results
PASS=0
FAIL=0

EXECUTE_PROTOCOL="$REFERENCES_DIR/execute-protocol.md"
PHASE_DETECTION="$REFERENCES_DIR/phase-detection.md"

# Check 1: No direct $(cat /tmp/.vbw-plugin-root) execution path
if grep -R -n '\$(cat /tmp/.vbw-plugin-root)' "$COMMANDS_DIR" "$REFERENCES_DIR" >/tmp/.vbw-plugin-runtime-grep 2>/dev/null; then
  fail "runtime docs contain direct \$(cat /tmp/.vbw-plugin-root) execution path"
  while IFS= read -r line; do echo "      $line"; done </tmp/.vbw-plugin-runtime-grep
else
  pass "runtime docs avoid direct \$(cat /tmp/.vbw-plugin-root) execution path"
fi

# Check 2: No legacy cat /tmp/.vbw-plugin-root reader pattern (eliminated)
if grep -R -n 'cat /tmp/.vbw-plugin-root' "$COMMANDS_DIR" | grep -v 'vbw-plugin-root-link-' >/tmp/.vbw-plugin-legacy-cat 2>/dev/null; then
  fail "commands still use legacy cat /tmp/.vbw-plugin-root reader"
  while IFS= read -r line; do echo "      $line"; done </tmp/.vbw-plugin-legacy-cat
else
  pass "no legacy cat /tmp/.vbw-plugin-root readers in commands"
fi

# Check 3: No legacy temp file write (printf to /tmp/.vbw-plugin-root)
if grep -R -n "printf.*> /tmp/.vbw-plugin-root" "$COMMANDS_DIR" >/tmp/.vbw-plugin-legacy-write 2>/dev/null; then
  fail "commands still write to legacy /tmp/.vbw-plugin-root temp file"
  while IFS= read -r line; do echo "      $line"; done </tmp/.vbw-plugin-legacy-write
else
  pass "no legacy temp file writes in commands"
fi

# Check 4: Canonical no-space link path exists in resolver preambles
canonical_count=$(grep -R -c 'LINK="/tmp/.vbw-plugin-root-link-' "$COMMANDS_DIR" "$REFERENCES_DIR" 2>/dev/null | awk -F: '{s+=$NF} END{print s+0}')
if [ "$canonical_count" -ge 1 ]; then
  pass "resolver preambles emit canonical no-space link path"
else
  fail "resolver preambles missing canonical no-space link path"
fi

# Check 5: All command files with reader callsites have a preamble
for file in "$COMMANDS_DIR"/*.md; do
  base="$(basename "$file" .md)"
  reader_count=$(grep -c 'echo /tmp/.vbw-plugin-root-link-' "$file" 2>/dev/null || true)
  if [ "$reader_count" -gt 0 ]; then
    if grep -q 'LINK="/tmp/.vbw-plugin-root-link-' "$file"; then
      pass "$base: has preamble for $reader_count reader callsites"
    else
      fail "$base: $reader_count reader callsites but NO preamble"
    fi
  fi
done

# Check 6: Deterministic reader pattern uses CLAUDE_SESSION_ID
reader_without_session=$(grep -R -n 'echo /tmp/.vbw-plugin-root-link-' "$COMMANDS_DIR" | grep -v 'CLAUDE_SESSION_ID' || true)
if [ -z "$reader_without_session" ]; then
  pass "all readers use CLAUDE_SESSION_ID for session isolation"
else
  fail "readers missing CLAUDE_SESSION_ID"
  echo "$reader_without_session" | while IFS= read -r line; do echo "      $line"; done
fi

# Check 7: execute-protocol.md resolver policy checks
for needle in \
  'if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then' \
  '[ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]' \
  "grep -E '^[0-9]+(\\.[0-9]+)*$'" \
  'sort -t. -k1,1n -k2,2n -k3,3n' \
  'FALLBACK_DIR=$(ls -1d "${VBW_CACHE_ROOT}"/* 2>/dev/null | awk -F/ '\''{print $NF}'\'' | sort | tail -1)' \
  'ps axww -o args=' \
  'if [ -z "$VBW_PLUGIN_ROOT" ] || [ ! -d "$VBW_PLUGIN_ROOT" ]; then' \
  'exit 1'
do
  if grep -Fq "$needle" "$EXECUTE_PROTOCOL"; then
    pass "execute-protocol contains resolver policy: $needle"
  else
    fail "execute-protocol missing resolver policy: $needle"
  fi
done

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All runtime resolver safety checks passed."
exit 0

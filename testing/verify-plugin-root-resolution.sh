#!/usr/bin/env bash
set -euo pipefail

# verify-plugin-root-resolution.sh — Ensure CLAUDE_PLUGIN_ROOT resolves deterministically
#
# Problem: ${CLAUDE_PLUGIN_ROOT} is available in Claude Code's process env (for @ file
# references) but NOT in the Bash tool's shell environment or !` backtick subprocesses.
# Model-executed bash commands that reference ${CLAUDE_PLUGIN_ROOT} expand to empty.
#
# Fix: Each command file resolves the plugin root ONCE at load time (via !` backtick with
# a fallback ls chain) and writes it to /tmp/.vbw-plugin-root. All subsequent references
# use `!`cat /tmp/.vbw-plugin-root` (load-time) or $(cat /tmp/.vbw-plugin-root) (runtime).
#
# Safe contexts (all refs must be in one of these):
#   - cat /tmp/.vbw-plugin-root           (temp file read — standard pattern)
#   - !`...${CLAUDE_PLUGIN_ROOT:-...}...` (resolve line with fallback)
#   - @${CLAUDE_PLUGIN_ROOT}/...         (file inclusion at load time)
#   - Plugin root: ...                   (preamble resolve+write line)
#   - printf.*vbw-plugin-root            (write to temp file)
#   - Runtime resolver guard line in execute-protocol.md:
#       if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}" ]
#       VBW_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
#
# Unsafe (must not exist):
#   - bare ${CLAUDE_PLUGIN_ROOT} in model-executed text (resolves to empty in bash)
#   - `!`echo $CLAUDE_PLUGIN_ROOT` without fallback (resolves to empty in subshell)

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
    | grep -v 'if \[ -n "${CLAUDE_PLUGIN_ROOT:-}" \] && \[ -d "${CLAUDE_PLUGIN_ROOT}" \]' \
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
      | grep -v 'if \[ -n "${CLAUDE_PLUGIN_ROOT:-}" \] && \[ -d "${CLAUDE_PLUGIN_ROOT}" \]' \
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

# --- Phase 3: Runtime resolver safety for execute protocol ---
echo ""
echo "=== Runtime Resolver Safety Verification ==="

EXECUTE_PROTOCOL="$REFERENCES_DIR/execute-protocol.md"
PHASE_DETECTION="$REFERENCES_DIR/phase-detection.md"

if grep -q '\$(cat /tmp/.vbw-plugin-root)' "$EXECUTE_PROTOCOL" "$PHASE_DETECTION"; then
  fail "runtime docs contain direct \$(cat /tmp/.vbw-plugin-root) execution path"
  grep -n '\$(cat /tmp/.vbw-plugin-root)' "$EXECUTE_PROTOCOL" "$PHASE_DETECTION" | while IFS= read -r line; do echo "      $line"; done
else
  pass "runtime docs avoid direct \$(cat /tmp/.vbw-plugin-root) execution path"
fi

for needle in \
  'if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}" ]; then' \
  'elif [ -d "${VBW_CACHE_ROOT}/local" ]; then' \
  "grep -E '^[0-9]+(\\.[0-9]+)*$'" \
  'sort -t. -k1,1n -k2,2n -k3,3n' \
  'FALLBACK_DIR=$(ls -1d "${VBW_CACHE_ROOT}"/* 2>/dev/null | awk -F/ '\''{print $NF}'\'' | sort | tail -1)' \
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

#!/usr/bin/env bash
set -euo pipefail

# verify-plugin-root-resolution.sh — Ensure CLAUDE_PLUGIN_ROOT resolves deterministically
#
# Problem: ${CLAUDE_PLUGIN_ROOT} is available in Claude Code's process env (for @ file
# references) but NOT in the Bash tool's shell environment or !` backtick subprocesses.
# Model-executed bash commands that reference ${CLAUDE_PLUGIN_ROOT} expand to empty.
#
# Fix: Each command file resolves the plugin root ONCE at load time, creates a
# per-session symlink at a deterministic path:
#   /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}
# Resolution order for the symlink steps is:
#   1. exact current-session symlink path (SESSION_LINK)
#   2. generic symlink discovery via `find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*'`
# Subsequent load-time references construct the same deterministic session path
# independently via echo — no shared mutable temp file is involved.
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
#   - ${CLAUDE_PLUGIN_ROOT:+...}          (conditional-if-set expansion — safe, only expands when set)
#   - (CLAUDE_PLUGIN_ROOT ...)            (literal text mention in diagnostic output, not a var ref)
#
# Unsafe (must not exist):
#   - bare ${CLAUDE_PLUGIN_ROOT} in model-executed text (resolves to empty in bash)
#   - `!`echo $CLAUDE_PLUGIN_ROOT` without fallback (resolves to empty in subshell)
#   - cat /tmp/.vbw-plugin-root (legacy shared temp file read — eliminated)
#   - printf.*> /tmp/.vbw-plugin-root (legacy shared temp file write — eliminated)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMANDS_DIR="$ROOT/commands"
REFERENCES_DIR="$ROOT/references"
EXECUTE_PROTOCOL="$REFERENCES_DIR/execute-protocol.md"

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

is_tracked_repo_file() {
  local abs="$1"
  git -C "$ROOT" ls-files --error-unmatch "${abs#$ROOT/}" >/dev/null 2>&1
}

tracked_files_for_pattern() {
  local rel
  git -C "$ROOT" ls-files -- "$@" | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    printf '%s\n' "$ROOT/$rel"
  done
}

TRACKED_COMMAND_FILES=()
while IFS= read -r file; do
  [ -n "$file" ] || continue
  TRACKED_COMMAND_FILES+=("$file")
done < <(tracked_files_for_pattern 'commands/*.md')

TRACKED_REFERENCE_FILES=()
while IFS= read -r file; do
  [ -n "$file" ] || continue
  TRACKED_REFERENCE_FILES+=("$file")
done < <(tracked_files_for_pattern 'references/*.md')

TRACKED_COMMAND_REFERENCE_FILES=("${TRACKED_COMMAND_FILES[@]}" "${TRACKED_REFERENCE_FILES[@]}")
TRACKED_COMMAND_EXECUTE_PROTOCOL_FILES=("${TRACKED_COMMAND_FILES[@]}" "$EXECUTE_PROTOCOL")

echo "=== Plugin Root Inline Resolution Verification ==="

for file in "$COMMANDS_DIR"/*.md "$REFERENCES_DIR"/*.md "$ROOT/internal"/*.md; do
  [ -f "$file" ] || continue
  is_tracked_repo_file "$file" || continue
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
  # inline `!`echo $CLAUDE_PLUGIN_ROOT` resolution patterns, :+ conditional expansion
  # (only expands when var is set), and literal text mentions (no $ prefix).
  unsafe_count=$(grep 'CLAUDE_PLUGIN_ROOT' "$file" \
    | grep -v '!`[^`]*CLAUDE_PLUGIN_ROOT' \
    | grep -v '@${CLAUDE_PLUGIN_ROOT}' \
    | grep -v 'Plugin root:' \
    | grep -v 'if \[ -n "${CLAUDE_PLUGIN_ROOT:-}" \] && \[ -[df] "${CLAUDE_PLUGIN_ROOT}' \
    | grep -v 'if \[ -z "\$R" \] && \[ -n "${CLAUDE_PLUGIN_ROOT:-}" \] && \[ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" \]; then R="${CLAUDE_PLUGIN_ROOT}"; fi' \
    | grep -v 'VBW_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"' \
    | grep -v 'checked CLAUDE_PLUGIN_ROOT' \
    | grep -v 'CLAUDE_PLUGIN_ROOT:+' \
    | grep -v '(CLAUDE_PLUGIN_ROOT ' \
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
      | grep -v 'if \[ -z "\$R" \] && \[ -n "${CLAUDE_PLUGIN_ROOT:-}" \] && \[ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" \]; then R="${CLAUDE_PLUGIN_ROOT}"; fi' \
      | grep -v 'VBW_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"' \
      | grep -v 'checked CLAUDE_PLUGIN_ROOT' \
      | grep -v 'CLAUDE_PLUGIN_ROOT:+' \
      | grep -v '(CLAUDE_PLUGIN_ROOT ' \
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

for file in "$COMMANDS_DIR"/*.md "$REFERENCES_DIR"/*.md "$ROOT/internal"/*.md; do
  [ -f "$file" ] || continue
  is_tracked_repo_file "$file" || continue
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

PHASE_DETECTION="$REFERENCES_DIR/phase-detection.md"

# Check 1: No direct $(cat /tmp/.vbw-plugin-root) execution path
if grep -n '\$(cat /tmp/.vbw-plugin-root)' "${TRACKED_COMMAND_REFERENCE_FILES[@]}" >/tmp/.vbw-plugin-runtime-grep 2>/dev/null; then
  fail "runtime docs contain direct \$(cat /tmp/.vbw-plugin-root) execution path"
  while IFS= read -r line; do echo "      $line"; done </tmp/.vbw-plugin-runtime-grep
else
  pass "runtime docs avoid direct \$(cat /tmp/.vbw-plugin-root) execution path"
fi

# Check 2: No legacy cat /tmp/.vbw-plugin-root reader pattern (eliminated)
if grep -n 'cat /tmp/.vbw-plugin-root' "${TRACKED_COMMAND_FILES[@]}" 2>/dev/null | grep -v 'vbw-plugin-root-link-' >/tmp/.vbw-plugin-legacy-cat; then
  fail "commands still use legacy cat /tmp/.vbw-plugin-root reader"
  while IFS= read -r line; do echo "      $line"; done </tmp/.vbw-plugin-legacy-cat
else
  pass "no legacy cat /tmp/.vbw-plugin-root readers in commands"
fi

# Check 3: No legacy temp file write (printf to /tmp/.vbw-plugin-root)
if grep -n "printf.*> /tmp/.vbw-plugin-root" "${TRACKED_COMMAND_FILES[@]}" >/tmp/.vbw-plugin-legacy-write 2>/dev/null; then
  fail "commands still write to legacy /tmp/.vbw-plugin-root temp file"
  while IFS= read -r line; do echo "      $line"; done </tmp/.vbw-plugin-legacy-write
else
  pass "no legacy temp file writes in commands"
fi

# Check 4: Canonical no-space link path exists in resolver preambles
canonical_count=$(grep -c 'LINK="/tmp/.vbw-plugin-root-link-' "${TRACKED_COMMAND_REFERENCE_FILES[@]}" 2>/dev/null | awk -F: '{s+=$NF} END{print s+0}')
if [ "$canonical_count" -ge 1 ]; then
  pass "resolver preambles emit canonical no-space link path"
else
  fail "resolver preambles missing canonical no-space link path"
fi

# Check 5: All command files with reader callsites have a preamble
for file in "$COMMANDS_DIR"/*.md; do
  [ -f "$file" ] || continue
  is_tracked_repo_file "$file" || continue
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
reader_without_session=$(grep -n 'echo /tmp/.vbw-plugin-root-link-' "${TRACKED_COMMAND_FILES[@]}" 2>/dev/null | grep -v 'CLAUDE_SESSION_ID' || true)
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
  'FALLBACK_DIR=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '\''{print $NF}'\'' | sort | tail -1)' \
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

# Check 8: All command preambles use pwd -P for canonical symlink resolution
for file in "$COMMANDS_DIR"/*.md; do
  [ -f "$file" ] || continue
  is_tracked_repo_file "$file" || continue
  base="$(basename "$file" .md)"
  if grep -q 'LINK="/tmp/.vbw-plugin-root-link-' "$file"; then
    if grep -q 'cd "$R" 2>/dev/null && pwd -P' "$file"; then
      pass "$base: uses canonical pwd -P resolution"
    else
      fail "$base: missing canonical pwd -P resolution in preamble"
    fi
  fi
done

# Check 8b: All command preambles use the link helper with REAL_R (dynamic coverage)
for file in "$COMMANDS_DIR"/*.md; do
  [ -f "$file" ] || continue
  is_tracked_repo_file "$file" || continue
  base="$(basename "$file" .md)"
  if grep -q 'LINK="/tmp/.vbw-plugin-root-link-' "$file"; then
    if grep -q 'ensure-plugin-root-link.sh" "$LINK" "$REAL_R"' "$file"; then
      pass "$base: uses ensure-plugin-root-link helper with REAL_R"
    else
      fail "$base: missing ensure-plugin-root-link helper call with REAL_R"
    fi
  fi
done

# Check 9: execute-protocol.md uses canonical pwd -P resolution with safe fallback
if grep -q 'cd "$VBW_PLUGIN_ROOT" 2>/dev/null && pwd -P' "$EXECUTE_PROTOCOL"; then
  pass "execute-protocol uses canonical pwd -P resolution"
else
  fail "execute-protocol missing canonical pwd -P resolution"
fi

# Check 10: execute-protocol.md preserves original value on cd failure
if grep -q 'pwd -P) || true' "$EXECUTE_PROTOCOL"; then
  fail "execute-protocol uses || true fallback (blanks VBW_PLUGIN_ROOT on cd failure)"
elif grep -q 'pwd -P || echo "\$VBW_PLUGIN_ROOT"' "$EXECUTE_PROTOCOL"; then
  pass "execute-protocol preserves VBW_PLUGIN_ROOT on cd failure"
else
  fail "execute-protocol missing safe fallback for canonicalization failure"
fi

# Check 11: targeted command preambles use CLAUDE_SESSION_ID:-default session key
# todo.md and list-todos.md intentionally have no shell preamble (fix for #201) — skip from preamble checks
TARGET_COMMANDS=(
  config.md debug.md discuss.md fix.md help.md init.md map.md qa.md
  report.md research.md resume.md rtk.md skills.md status.md update.md verify.md vibe.md whats-new.md
)
for rel in "${TARGET_COMMANDS[@]}"; do
  file="$COMMANDS_DIR/$rel"
  [ -f "$file" ] || continue
  is_tracked_repo_file "$file" || continue
  base="$(basename "$rel" .md)"
  if grep -q 'SESSION_KEY="${CLAUDE_SESSION_ID:-default}"' "$file"; then
    pass "$base: preamble uses CLAUDE_SESSION_ID:-default session key"
  else
    fail "$base: missing CLAUDE_SESSION_ID:-default session key in preamble"
  fi
done

# Check 12: no SHA1 session key derivation in commands (reverted pattern)
sha1_session_count=$({ grep -c 'SESSION_BASE.*shasum\|shasum.*SESSION' "${TRACKED_COMMAND_FILES[@]}" 2>/dev/null || true; } | awk -F: '{s+=$NF} END{print s+0}')
if [ "$sha1_session_count" -eq 0 ]; then
  pass "no SHA1 session key derivation in commands"
else
  fail "$sha1_session_count SHA1 session key derivation(s) still present in commands"
fi

# Check 13: All command preambles include exact current-session symlink fallback
for rel in "${TARGET_COMMANDS[@]}"; do
  file="$COMMANDS_DIR/$rel"
  [ -f "$file" ] || continue
  is_tracked_repo_file "$file" || continue
  base="$(basename "$rel" .md)"
  if grep -qF '[ -f "${SESSION_LINK}/scripts/hook-wrapper.sh" ]' "$file"; then
    pass "$base: preamble includes exact current-session symlink fallback"
  else
    fail "$base: preamble missing exact current-session symlink fallback"
  fi
done

# Check 13b: All command preambles include generic find-based symlink fallback
for rel in "${TARGET_COMMANDS[@]}"; do
  file="$COMMANDS_DIR/$rel"
  [ -f "$file" ] || continue
  is_tracked_repo_file "$file" || continue
  base="$(basename "$rel" .md)"
  if grep -qF "command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*'" "$file"; then
    pass "$base: preamble includes find-based symlink fallback"
  else
    fail "$base: preamble missing find-based symlink fallback"
  fi
done

# Check 13c: execute-protocol.md includes exact-session and find-based fallback
if grep -qF '[ -f "${SESSION_LINK}/scripts/hook-wrapper.sh" ]' "$EXECUTE_PROTOCOL"; then
  pass "execute-protocol: includes exact current-session symlink fallback"
else
  fail "execute-protocol: missing exact current-session symlink fallback"
fi

if grep -qF "command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*'" "$EXECUTE_PROTOCOL"; then
  pass "execute-protocol: includes find-based symlink fallback"
else
  fail "execute-protocol: missing find-based symlink fallback"
fi

# Check 14: All command preambles use robust grep -oE for ps extraction (not fragile sed)
# The old sed pattern: sed -n 's/.*--plugin-dir  *\([^ ]*\).*/\1/p'
# is whitespace-sensitive and breaks with different spacing. The hooks.json pattern:
# grep -oE -- "--plugin-dir [^ ]+" is more robust.
for rel in "${TARGET_COMMANDS[@]}"; do
  file="$COMMANDS_DIR/$rel"
  [ -f "$file" ] || continue
  is_tracked_repo_file "$file" || continue
  base="$(basename "$rel" .md)"
  if grep -q 'sed.*--plugin-dir' "$file"; then
    fail "$base: uses fragile sed pattern for --plugin-dir extraction"
  else
    pass "$base: does not use fragile sed pattern"
  fi
done

# Check 14b: execute-protocol.md uses robust grep pattern
if grep -q 'sed.*--plugin-dir' "$EXECUTE_PROTOCOL"; then
  fail "execute-protocol: uses fragile sed pattern for --plugin-dir extraction"
else
  pass "execute-protocol: does not use fragile sed pattern"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All runtime resolver safety checks passed."

# --- Phase 3b: Drift detection — ensure TARGET_COMMANDS covers all preamble commands ---
echo ""
echo "=== Preamble Coverage Drift Detection ==="

# Known non-preamble commands (no shell preamble by design)
NON_PREAMBLE_COMMANDS="todo.md list-todos.md doctor.md pause.md profile.md teach.md uninstall.md"

DRIFT_FAIL=0
for file in "$COMMANDS_DIR"/*.md; do
  base="$(basename "$file")"
  is_tracked_repo_file "$file" || continue
  # Skip known non-preamble commands
  case " $NON_PREAMBLE_COMMANDS " in
    *" $base "*) continue ;;
  esac
  # If this command has a preamble (pwd -P pattern), it should be in TARGET_COMMANDS
  if grep -q 'cd "$R" 2>/dev/null && pwd -P' "$file"; then
    found=0
    for rel in "${TARGET_COMMANDS[@]}"; do
      if [ "$rel" = "$base" ]; then found=1; break; fi
    done
    if [ "$found" -eq 0 ]; then
      fail "$base: has preamble but is NOT in TARGET_COMMANDS — add it or add to NON_PREAMBLE_COMMANDS"
      DRIFT_FAIL=1
    fi
  fi
done

if [ "$DRIFT_FAIL" -eq 0 ]; then
  pass "all preamble commands are covered in TARGET_COMMANDS (no drift)"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All preamble coverage drift detection checks passed."

# --- Phase 3c: todo.md non-preamble helper resolution contract ---
echo ""
echo "=== Todo Command Non-Preamble Resolver Contract ==="

PASS=0
FAIL=0

TODO_CMD="$COMMANDS_DIR/todo.md"

if grep -Fq 'bash "${PLUGIN_ROOT}/scripts/todo-details.sh" add HASH -' "$TODO_CMD"; then
  pass "todo.md uses canonical helper add command shape via PLUGIN_ROOT"
else
  fail "todo.md missing canonical helper add command shape via PLUGIN_ROOT"
fi

if grep -Fq 'bash "${PLUGIN_ROOT}/scripts/planning-git.sh" commit-boundary "add todo item" .vbw-planning/config.json' "$TODO_CMD"; then
  pass "todo.md uses canonical planning-git command shape via PLUGIN_ROOT"
else
  fail "todo.md missing canonical planning-git command shape via PLUGIN_ROOT"
fi

if grep -Fq 'Store the resolved path as `PLUGIN_ROOT`' "$TODO_CMD"; then
  pass "todo.md defines a PLUGIN_ROOT resolver step before helper writes"
else
  fail "todo.md missing PLUGIN_ROOT resolver step before helper writes"
fi

resolver_line=$(grep -nF 'Store the resolved path as `PLUGIN_ROOT`' "$TODO_CMD" | head -1 | cut -d: -f1 || true)
add_line=$(grep -nF 'bash "${PLUGIN_ROOT}/scripts/todo-details.sh" add HASH -' "$TODO_CMD" | head -1 | cut -d: -f1 || true)
planning_line=$(grep -nF 'bash "${PLUGIN_ROOT}/scripts/planning-git.sh" commit-boundary "add todo item" .vbw-planning/config.json' "$TODO_CMD" | head -1 | cut -d: -f1 || true)
if [ -n "$resolver_line" ] && [ -n "$add_line" ]; then
  if [ "$resolver_line" -lt "$add_line" ]; then
    pass "todo.md places the PLUGIN_ROOT resolver before helper add usage"
  else
    fail "todo.md places helper add usage before the PLUGIN_ROOT resolver"
  fi
else
  fail "todo.md ordering check missing resolver or helper add anchor"
fi

if [ -n "$resolver_line" ] && [ -n "$planning_line" ]; then
  if [ "$resolver_line" -lt "$planning_line" ]; then
    pass "todo.md places the PLUGIN_ROOT resolver before planning-git usage"
  else
    fail "todo.md places planning-git usage before the PLUGIN_ROOT resolver"
  fi
else
  fail "todo.md ordering check missing resolver or planning-git anchor"
fi

for needle in \
  'The `local/` subdirectory under the plugin cache root' \
  'The numerically highest versioned directory under the plugin cache root' \
  'Any other (non-versioned) subdirectory under the plugin cache root' \
  'The session symlink `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`' \
  'Extract `--plugin-dir <path>` from the process tree (`ps axww`)'
do
  if grep -Fq "$needle" "$TODO_CMD"; then
    pass "todo.md resolver documents fallback tier: $needle"
  else
    fail "todo.md resolver missing fallback tier: $needle"
  fi
done

if grep -Fq '/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/todo-details.sh' "$TODO_CMD"; then
  fail "todo.md still hard-codes the session symlink helper path"
else
  pass "todo.md no longer hard-codes the session symlink helper path"
fi

if grep -Fq '/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh' "$TODO_CMD"; then
  fail "todo.md still hard-codes the session symlink planning-git path"
else
  pass "todo.md no longer hard-codes the session symlink planning-git path"
fi

case " $NON_PREAMBLE_COMMANDS " in
  *" todo.md "*)
    pass "todo.md remains in the non-preamble allowlist"
    ;;
  *)
    fail "todo.md missing from the non-preamble allowlist"
    ;;
esac

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "Todo command non-preamble resolver contract checks passed."

# --- Phase 4: Behavioral verification of resolution mechanisms ---
echo ""
echo "=== Behavioral Resolution Verification ==="
echo "(Exercises exact-session fallback, find-based symlink discovery, and grep -oE extraction in controlled sandboxes)"

PASS=0
FAIL=0

# Trap-based cleanup for Phase 4 temp artifacts — uses array to handle paths safely
BTEST_CLEANUP_LIST=()
btest_cleanup() { for item in "${BTEST_CLEANUP_LIST[@]}"; do rm -rf "$item" 2>/dev/null; done; }
trap btest_cleanup EXIT

# Check 15: exact session-link fallback resolves a valid symlink target
BTEST_DIR=$(mktemp -d)
BTEST_CLEANUP_LIST+=("$BTEST_DIR")
mkdir -p "$BTEST_DIR/scripts"
echo "#!/bin/bash" > "$BTEST_DIR/scripts/hook-wrapper.sh"
BTEST_LINK="/tmp/.vbw-plugin-root-link-test-behavioral-$$"
ln -s "$BTEST_DIR" "$BTEST_LINK"
BTEST_CLEANUP_LIST+=("$BTEST_LINK")
resolved=""
SESSION_LINK="$BTEST_LINK"
[ -f "$SESSION_LINK/scripts/hook-wrapper.sh" ] && resolved="$SESSION_LINK"
rm -f "$BTEST_LINK"
rm -rf "$BTEST_DIR"
if [ "$resolved" = "$BTEST_LINK" ]; then
  pass "exact session-link fallback resolves valid symlink target"
else
  fail "exact session-link fallback: got '$resolved' instead of fixture '$BTEST_LINK'"
fi

# Check 15b: find-based fallback returns empty when no symlinks exist in the search root
BTEST_FIND_ROOT=$(mktemp -d)
BTEST_CLEANUP_LIST+=("$BTEST_FIND_ROOT")
resolved=""
resolved=$(command find "$BTEST_FIND_ROOT" -maxdepth 1 -type l -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | head -1 || true)
rm -rf "$BTEST_FIND_ROOT"
if [ -z "$resolved" ]; then
  pass "find-based fallback returns empty when no symlinks exist"
else
  fail "find-based fallback unexpectedly resolved: $resolved"
fi

# Check 15c: find-based fallback skips stale symlinks and discovers a later valid symlink
BTEST_FIND_ROOT=$(mktemp -d)
BTEST_CLEANUP_LIST+=("$BTEST_FIND_ROOT")
BTEST_STALE_MIX="$BTEST_FIND_ROOT/.vbw-plugin-root-link-test-stale-$$"
BTEST_CLEANUP_LIST+=("$BTEST_STALE_MIX")
ln -s "/nonexistent/path/$$" "$BTEST_STALE_MIX"
BTEST_VALID_DIR=$(mktemp -d)
BTEST_CLEANUP_LIST+=("$BTEST_VALID_DIR")
mkdir -p "$BTEST_VALID_DIR/scripts"
echo "#!/bin/bash" > "$BTEST_VALID_DIR/scripts/hook-wrapper.sh"
BTEST_VALID_MIX="$BTEST_FIND_ROOT/.vbw-plugin-root-link-test-valid-$$"
ln -s "$BTEST_VALID_DIR" "$BTEST_VALID_MIX"
BTEST_CLEANUP_LIST+=("$BTEST_VALID_MIX")
resolved=""
resolved=$(command find "$BTEST_FIND_ROOT" -maxdepth 1 -type l -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r link; do
  if [ -f "$link/scripts/hook-wrapper.sh" ]; then
    printf '%s\n' "$link"
    break
  fi
done || true)
rm -f "$BTEST_STALE_MIX" "$BTEST_VALID_MIX"
rm -rf "$BTEST_VALID_DIR" "$BTEST_FIND_ROOT"
if [ "$resolved" = "$BTEST_VALID_MIX" ]; then
  pass "find-based fallback skips stale symlinks and discovers a later valid symlink"
else
  fail "find-based fallback resolved to '$resolved' instead of '$BTEST_VALID_MIX'"
fi

# Check 16: grep -oE extracts --plugin-dir value from ps-style output
BTEST_PS_LINE="node /path/to/claude --plugin-dir /Users/test/my-plugin --other-flag"
extracted=$(echo "$BTEST_PS_LINE" | grep -oE -- "--plugin-dir [^ ]+" | head -1)
if [ "$extracted" = "--plugin-dir /Users/test/my-plugin" ]; then
  pass "grep -oE correctly extracts --plugin-dir value from ps output"
else
  fail "grep -oE extraction failed: expected '--plugin-dir /Users/test/my-plugin', got '$extracted'"
fi

# Check 16b: Prefix stripping yields clean path after grep -oE extraction
D="$extracted"
D="${D#--plugin-dir }"
if [ "$D" = "/Users/test/my-plugin" ]; then
  pass "prefix stripping yields clean path after grep -oE"
else
  fail "prefix stripping failed: expected '/Users/test/my-plugin', got '$D'"
fi

# Check 17: no command preamble or execute doc retains the old shell-expanded symlink glob fallback
old_glob_uses=$(grep -n '/tmp/.vbw-plugin-root-link-\*/scripts/hook-wrapper.sh' "${TRACKED_COMMAND_EXECUTE_PROTOCOL_FILES[@]}" 2>/dev/null || true)
if [ -z "$old_glob_uses" ]; then
  pass "command preambles and execute-protocol no longer use shell-expanded symlink globs"
else
  fail "found old shell-expanded symlink glob fallback"
  echo "$old_glob_uses" | while IFS= read -r line; do echo "      $line"; done
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All behavioral resolution checks passed."

# --- Phase 5: phase-detect self-healing regression checks ---
echo ""
echo "=== Phase-Detect Self-Healing Regression Checks ==="

PASS=0
FAIL=0

PHASE_DETECT_COMMANDS=(vibe.md verify.md status.md resume.md qa.md discuss.md)

# Check 18: targeted commands define a self-healing refresh helper in
# phase-detect readers, except vibe.md which now uses guarded live reads with
# temp-file fallback to avoid stale same-session cache reuse.
for rel in "${PHASE_DETECT_COMMANDS[@]}"; do
  file="$COMMANDS_DIR/$rel"
  base="$(basename "$rel" .md)"
  if [ "$rel" = "vibe.md" ]; then
    live_count=$(grep -cF 'bash "$L/scripts/phase-detect.sh"' "$file" || true)
    if [ "${live_count:-0}" -ge 3 ]; then
      pass "$base: phase-detect reader uses guarded live reads"
    else
      fail "$base: missing guarded live phase-detect reads"
    fi
  elif grep -q '_refresh_phase_detect()' "$file"; then
    pass "$base: phase-detect reader defines _refresh_phase_detect()"
  else
    fail "$base: missing _refresh_phase_detect() self-healing helper"
  fi
done

vibe_link_repair_count=$(grep -cF 'bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$L" "$REAL_R"' "$COMMANDS_DIR/vibe.md" || true)
if [ "${vibe_link_repair_count:-0}" -ge 3 ]; then
  pass "vibe.md: guarded readers repair the session link before live refresh"
else
  fail "vibe.md: expected guarded readers to repair the session link before live refresh"
fi

# Check 19: targeted commands no longer use link-order-dependent wait-loop fallback
# Old race-prone form (same line or adjacent lines):
#   if [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ -L "$L" ]; then
#     i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do ...
for rel in "${PHASE_DETECT_COMMANDS[@]}"; do
  file="$COMMANDS_DIR/$rel"
  base="$(basename "$rel" .md)"
  if awk '
    /phase_detect_error=true/ && /\[ -L "\$L" \]/ {
      if (/while \[ ! -L "\$L" \] && \[ \$i -lt 20 \]/) {
        found=1; exit
      }
      armed=1
      next
    }
    armed && /while \[ ! -L "\$L" \] && \[ \$i -lt 20 \]/ {
      found=1; exit
    }
    { armed=0 }
    END { exit found ? 0 : 1 }
  ' "$file"; then
    fail "$base: still uses race-prone wait-for-link phase-detect fallback"
  else
    pass "$base: does not use race-prone wait-for-link phase-detect fallback"
  fi
done

# Check 20: helper-based readers include the exact-session and find-based fallback
# steps. vibe.md has no helper and is validated via its preamble.
for rel in "${PHASE_DETECT_COMMANDS[@]}"; do
  file="$COMMANDS_DIR/$rel"
  base="$(basename "$rel" .md)"
  if [ "$rel" = "vibe.md" ]; then
    if grep -qF '[ -f "${SESSION_LINK}/scripts/hook-wrapper.sh" ]' "$file" \
      && grep -qF "command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*'" "$file"; then
      pass "$base: preamble includes exact-session and find-based fallback"
    else
      fail "$base: missing exact-session or find-based fallback in preamble"
    fi
    continue
  fi
  func_count=$(grep -c '_refresh_phase_detect()' "$file" || true)
  session_link_count=$(grep -cF '[ -f "$SESSION_LINK/scripts/hook-wrapper.sh" ]' "$file" || true)
  find_fallback_count=$(grep -cF "command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*'" "$file" || true)
  if [ "$session_link_count" -ge "$func_count" ] && [ "$find_fallback_count" -ge "$func_count" ]; then
    pass "$base: _refresh_phase_detect() includes exact-session and find-based fallback"
  else
    fail "$base: _refresh_phase_detect() missing exact-session or find-based fallback ($session_link_count session checks, $find_fallback_count find fallbacks for $func_count functions)"
  fi
done

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All phase-detect self-healing regression checks passed."
exit 0

#!/usr/bin/env bash
set -euo pipefail

# verify-summary-utils-contract.sh — Tests for scripts/summary-utils.sh
#
# Verifies the runtime functions that all runtime scripts now source:
# - is_summary_complete (complete|completed only)
# - is_summary_terminal (complete|completed|partial|failed)
# - is_valid_summary_status (canonical runtime statuses only)
# - count_complete_summaries (count completion-status files)
# - count_terminal_summaries (count any-terminal-status files)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/scripts/summary-utils.sh"

PASS=0
FAIL=0
TMPDIR_BASE=""

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

cleanup() {
  [ -n "$TMPDIR_BASE" ] && rm -rf "$TMPDIR_BASE" 2>/dev/null || true
}
trap cleanup EXIT

# Source the library under test
if [ ! -f "$LIB" ]; then
  echo "ERROR: $LIB not found"
  exit 1
fi
# shellcheck source=../scripts/summary-utils.sh
source "$LIB"

echo "=== Summary Utils Contract Tests ==="

# ===== is_summary_complete =====

echo ""
echo "--- is_summary_complete ---"

TMPDIR_BASE=$(mktemp -d)

# status: complete -> true
cat > "$TMPDIR_BASE/complete.md" <<'EOF'
---
phase: 01
plan: 01
status: complete
---

Done.
EOF

if is_summary_complete "$TMPDIR_BASE/complete.md"; then
  pass "is_summary_complete: status: complete -> 0"
else
  fail "is_summary_complete: status: complete -> expected 0, got 1"
fi

# status: completed -> true (backward compat)
cat > "$TMPDIR_BASE/completed.md" <<'EOF'
---
phase: 01
plan: 01
status: completed
---

Done.
EOF

if is_summary_complete "$TMPDIR_BASE/completed.md"; then
  pass "is_summary_complete: status: completed -> 0 (backward compat)"
else
  fail "is_summary_complete: status: completed -> expected 0, got 1"
fi

# status: partial -> false
cat > "$TMPDIR_BASE/partial.md" <<'EOF'
---
phase: 01
plan: 01
status: partial
---

Partial.
EOF

if is_summary_complete "$TMPDIR_BASE/partial.md"; then
  fail "is_summary_complete: status: partial -> expected 1, got 0"
else
  pass "is_summary_complete: status: partial -> 1 (not complete)"
fi

# status: failed -> false
cat > "$TMPDIR_BASE/failed.md" <<'EOF'
---
phase: 01
plan: 01
status: failed
---

Failed.
EOF

if is_summary_complete "$TMPDIR_BASE/failed.md"; then
  fail "is_summary_complete: status: failed -> expected 1, got 0"
else
  pass "is_summary_complete: status: failed -> 1 (not complete)"
fi

# status: pending -> false
cat > "$TMPDIR_BASE/pending.md" <<'EOF'
---
phase: 01
plan: 01
status: pending
---

Stub.
EOF

if is_summary_complete "$TMPDIR_BASE/pending.md"; then
  fail "is_summary_complete: status: pending -> expected 1, got 0"
else
  pass "is_summary_complete: status: pending -> 1"
fi

# Non-existent file -> false
if is_summary_complete "$TMPDIR_BASE/does-not-exist.md"; then
  fail "is_summary_complete: non-existent file -> expected 1, got 0"
else
  pass "is_summary_complete: non-existent file -> 1"
fi

# No status field -> false
cat > "$TMPDIR_BASE/nostatus.md" <<'EOF'
---
phase: 01
plan: 01
title: Test Plan
---

No status.
EOF

if is_summary_complete "$TMPDIR_BASE/nostatus.md"; then
  fail "is_summary_complete: no status field -> expected 1, got 0"
else
  pass "is_summary_complete: no status field -> 1"
fi

# No frontmatter -> false
cat > "$TMPDIR_BASE/nofm.md" <<'EOF'
# Just markdown

No frontmatter.
EOF

if is_summary_complete "$TMPDIR_BASE/nofm.md"; then
  fail "is_summary_complete: no frontmatter -> expected 1, got 0"
else
  pass "is_summary_complete: no frontmatter -> 1"
fi

# Quoted status value -> true
cat > "$TMPDIR_BASE/quoted.md" <<'EOF'
---
phase: 01
plan: 01
status: "complete"
---

Done.
EOF

if is_summary_complete "$TMPDIR_BASE/quoted.md"; then
  pass "is_summary_complete: status: \"complete\" (quoted) -> 0"
else
  fail "is_summary_complete: status: \"complete\" (quoted) -> expected 0, got 1"
fi

# Leading blank lines before frontmatter -> true
cat > "$TMPDIR_BASE/leadingblank.md" <<'EOF'

---
phase: 01
plan: 01
status: complete
---

Done.
EOF

if is_summary_complete "$TMPDIR_BASE/leadingblank.md"; then
  pass "is_summary_complete: leading blank line before frontmatter -> 0"
else
  fail "is_summary_complete: leading blank line before frontmatter -> expected 0, got 1"
fi

# UTF-8 BOM before frontmatter -> true
printf '\357\273\277---\nphase: 01\nplan: 01\nstatus: complete\n---\n\nDone.\n' > "$TMPDIR_BASE/bom.md"

if is_summary_complete "$TMPDIR_BASE/bom.md"; then
  pass "is_summary_complete: UTF-8 BOM before frontmatter -> 0"
else
  fail "is_summary_complete: UTF-8 BOM before frontmatter -> expected 0, got 1"
fi

# Whitespace-padded status value -> true
cat > "$TMPDIR_BASE/padded.md" <<'EOF'
---
phase: 01
plan: 01
status:    complete   
---

Done.
EOF

if is_summary_complete "$TMPDIR_BASE/padded.md"; then
  pass "is_summary_complete: whitespace-padded status -> 0"
else
  fail "is_summary_complete: whitespace-padded status -> expected 0, got 1"
fi

# Quoted whitespace-padded status value -> true
cat > "$TMPDIR_BASE/quoted-padded.md" <<'EOF'
---
phase: 01
plan: 01
status: "  complete  "
---

Done.
EOF

if is_summary_complete "$TMPDIR_BASE/quoted-padded.md"; then
  pass "is_summary_complete: quoted whitespace-padded status -> 0"
else
  fail "is_summary_complete: quoted whitespace-padded status -> expected 0, got 1"
fi

# CRLF line endings -> true
printf -- '---\r\nphase: 01\r\nstatus: complete\r\n---\r\n\r\nDone.\r\n' > "$TMPDIR_BASE/crlf.md"

if is_summary_complete "$TMPDIR_BASE/crlf.md"; then
  pass "is_summary_complete: CRLF line endings -> 0"
else
  fail "is_summary_complete: CRLF line endings -> expected 0, got 1"
fi

# ===== is_summary_terminal =====

echo ""
echo "--- is_summary_terminal ---"

if is_summary_terminal "$TMPDIR_BASE/complete.md"; then
  pass "is_summary_terminal: status: complete -> 0"
else
  fail "is_summary_terminal: status: complete -> expected 0, got 1"
fi

if is_summary_terminal "$TMPDIR_BASE/completed.md"; then
  pass "is_summary_terminal: status: completed -> 0"
else
  fail "is_summary_terminal: status: completed -> expected 0, got 1"
fi

if is_summary_terminal "$TMPDIR_BASE/partial.md"; then
  pass "is_summary_terminal: status: partial -> 0 (terminal)"
else
  fail "is_summary_terminal: status: partial -> expected 0, got 1"
fi

if is_summary_terminal "$TMPDIR_BASE/failed.md"; then
  pass "is_summary_terminal: status: failed -> 0 (terminal)"
else
  fail "is_summary_terminal: status: failed -> expected 0, got 1"
fi

if is_summary_terminal "$TMPDIR_BASE/pending.md"; then
  fail "is_summary_terminal: status: pending -> expected 1, got 0"
else
  pass "is_summary_terminal: status: pending -> 1 (not terminal)"
fi

if is_summary_terminal "$TMPDIR_BASE/does-not-exist.md"; then
  fail "is_summary_terminal: non-existent file -> expected 1, got 0"
else
  pass "is_summary_terminal: non-existent file -> 1"
fi

if is_summary_terminal "$TMPDIR_BASE/nostatus.md"; then
  fail "is_summary_terminal: no status field -> expected 1, got 0"
else
  pass "is_summary_terminal: no status field -> 1"
fi

if is_summary_terminal "$TMPDIR_BASE/nofm.md"; then
  fail "is_summary_terminal: no frontmatter -> expected 1, got 0"
else
  pass "is_summary_terminal: no frontmatter -> 1"
fi

if is_summary_terminal "$TMPDIR_BASE/crlf.md"; then
  pass "is_summary_terminal: CRLF line endings -> 0"
else
  fail "is_summary_terminal: CRLF line endings -> expected 0, got 1"
fi

if is_summary_terminal "$TMPDIR_BASE/leadingblank.md"; then
  pass "is_summary_terminal: leading blank line before frontmatter -> 0"
else
  fail "is_summary_terminal: leading blank line before frontmatter -> expected 0, got 1"
fi

if is_summary_terminal "$TMPDIR_BASE/bom.md"; then
  pass "is_summary_terminal: UTF-8 BOM before frontmatter -> 0"
else
  fail "is_summary_terminal: UTF-8 BOM before frontmatter -> expected 0, got 1"
fi

if is_summary_terminal "$TMPDIR_BASE/padded.md"; then
  pass "is_summary_terminal: whitespace-padded status -> 0"
else
  fail "is_summary_terminal: whitespace-padded status -> expected 0, got 1"
fi

if is_summary_terminal "$TMPDIR_BASE/quoted-padded.md"; then
  pass "is_summary_terminal: quoted whitespace-padded status -> 0"
else
  fail "is_summary_terminal: quoted whitespace-padded status -> expected 0, got 1"
fi

# ===== is_valid_summary_status =====

echo ""
echo "--- is_valid_summary_status ---"

for valid_status in complete partial failed; do
  if is_valid_summary_status "$valid_status"; then
    pass "is_valid_summary_status: $valid_status -> 0"
  else
    fail "is_valid_summary_status: $valid_status -> expected 0, got 1"
  fi
done

for invalid_status in completed pending in_progress ""; do
  if is_valid_summary_status "$invalid_status"; then
    fail "is_valid_summary_status: '${invalid_status}' -> expected 1, got 0"
  else
    pass "is_valid_summary_status: '${invalid_status}' -> 1"
  fi
done

# ===== count_complete_summaries =====

echo ""
echo "--- count_complete_summaries ---"

PHASE_DIR="$TMPDIR_BASE/phase-mixed"
mkdir -p "$PHASE_DIR"

# Create a mix: complete, completed, partial, pending, failed
cat > "$PHASE_DIR/01-01-SUMMARY.md" <<'EOF'
---
status: complete
---
Done.
EOF

cat > "$PHASE_DIR/01-02-SUMMARY.md" <<'EOF'
---
status: completed
---
Done (legacy).
EOF

cat > "$PHASE_DIR/01-03-SUMMARY.md" <<'EOF'
---
status: partial
---
Partial.
EOF

cat > "$PHASE_DIR/01-04-SUMMARY.md" <<'EOF'
---
status: pending
---
Stub.
EOF

cat > "$PHASE_DIR/01-05-SUMMARY.md" <<'EOF'
---
status: failed
---
Failed.
EOF

count=$(count_complete_summaries "$PHASE_DIR")
if [ "$count" -eq 2 ]; then
  pass "count_complete_summaries: 5 files (complete, completed, partial, pending, failed) -> 2"
else
  fail "count_complete_summaries: expected 2, got $count"
fi

# Empty directory
EMPTY_DIR="$TMPDIR_BASE/phase-empty"
mkdir -p "$EMPTY_DIR"

count=$(count_complete_summaries "$EMPTY_DIR")
if [ "$count" -eq 0 ]; then
  pass "count_complete_summaries: empty directory -> 0"
else
  fail "count_complete_summaries: empty directory -> expected 0, got $count"
fi

# All complete
ALL_DIR="$TMPDIR_BASE/phase-all"
mkdir -p "$ALL_DIR"

cat > "$ALL_DIR/02-01-SUMMARY.md" <<'EOF'
---
status: complete
---
Done 1.
EOF

cat > "$ALL_DIR/02-02-SUMMARY.md" <<'EOF'
---
status: complete
---
Done 2.
EOF

count=$(count_complete_summaries "$ALL_DIR")
if [ "$count" -eq 2 ]; then
  pass "count_complete_summaries: 2 complete files -> 2"
else
  fail "count_complete_summaries: 2 complete files -> expected 2, got $count"
fi

# ===== count_terminal_summaries =====

echo ""
echo "--- count_terminal_summaries ---"

count=$(count_terminal_summaries "$PHASE_DIR")
if [ "$count" -eq 4 ]; then
  pass "count_terminal_summaries: 5 files (complete, completed, partial, pending, failed) -> 4"
else
  fail "count_terminal_summaries: expected 4, got $count"
fi

count=$(count_terminal_summaries "$EMPTY_DIR")
if [ "$count" -eq 0 ]; then
  pass "count_terminal_summaries: empty directory -> 0"
else
  fail "count_terminal_summaries: empty directory -> expected 0, got $count"
fi

count=$(count_terminal_summaries "$ALL_DIR")
if [ "$count" -eq 2 ]; then
  pass "count_terminal_summaries: 2 complete files -> 2"
else
  fail "count_terminal_summaries: 2 complete files -> expected 2, got $count"
fi

# ===== Integration: runtime scripts source summary-utils.sh =====

echo ""
echo "--- Integration: runtime scripts source summary-utils.sh ---"

# Verify all runtime scripts that should source summary-utils.sh actually reference it
for script in phase-detect.sh state-updater.sh recover-state.sh qa-gate.sh file-guard.sh session-start.sh verify-state-consistency.sh; do
  if grep -q 'summary-utils\.sh' "$ROOT/scripts/$script" 2>/dev/null; then
    pass "integration: $script references summary-utils.sh"
  else
    fail "integration: $script does NOT reference summary-utils.sh"
  fi
done

# Verify no runtime script still sources the deprecated lib/summary-status.sh
for script in phase-detect.sh state-updater.sh recover-state.sh qa-gate.sh file-guard.sh session-start.sh verify-state-consistency.sh; do
  if grep -q 'lib/summary-status\.sh' "$ROOT/scripts/$script" 2>/dev/null; then
    fail "integration: $script still references deprecated lib/summary-status.sh"
  else
    pass "integration: $script does not reference deprecated lib/summary-status.sh"
  fi
done

# Verify no consumer script overrides extract_summary_status() after sourcing summary-utils.sh.
# Fallback stubs in else-blocks (for when summary-utils.sh is missing) are allowed — only
# definitions that coexist with the sourced helper create split-brain parsing.
for script in phase-detect.sh state-updater.sh recover-state.sh qa-gate.sh file-guard.sh session-start.sh verify-state-consistency.sh; do
  # Count function definitions of extract_summary_status()
  def_count=$(grep -cE '^[[:space:]]*extract_summary_status[[:space:]]*\(\)' "$ROOT/scripts/$script" 2>/dev/null) || def_count=0
  # Count source lines for summary-utils.sh (matches both `. file` and `source file`)
  source_count=$(grep -cE '^[[:space:]]*(\.|source)[[:space:]]+.*summary-utils\.sh' "$ROOT/scripts/$script" 2>/dev/null) || source_count=0
  # If the script sources summary-utils.sh AND defines extract_summary_status() more than once
  # (the fallback else-stub), that means there's an override in the sourced branch.
  # If it doesn't source summary-utils.sh, any definition is a standalone (not an override).
  if [ "$source_count" -gt 0 ] && [ "$def_count" -gt 1 ]; then
    fail "integration: $script overrides extract_summary_status() after sourcing summary-utils.sh"
  else
    pass "integration: $script does not override extract_summary_status()"
  fi
done

# ===== Summary =====

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All summary-utils contract checks passed."
exit 0

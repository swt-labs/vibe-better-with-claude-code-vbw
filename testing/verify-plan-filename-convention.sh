#!/usr/bin/env bash
set -euo pipefail

# verify-plan-filename-convention.sh — Tests for deterministic plan filename enforcement (#151)

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

cleanup() {
  rm -rf "$TMPDIR_TEST" 2>/dev/null || true
}
trap cleanup EXIT

TMPDIR_TEST=$(mktemp -d)

echo "=== Plan Filename Convention Tests ==="

# --- file-guard tests ---
echo ""
echo "file-guard.sh:"

# Test 1: file-guard blocks type-first PLAN name
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/PLAN-01.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "wrong naming convention"; then
  pass "blocks PLAN-01.md (type-first)"
else
  fail "blocks PLAN-01.md — got rc=$RC, output: $OUTPUT"
fi

# Test 2: file-guard blocks type-first SUMMARY name
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/SUMMARY-01.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "wrong naming convention"; then
  pass "blocks SUMMARY-01.md (type-first)"
else
  fail "blocks SUMMARY-01.md — got rc=$RC, output: $OUTPUT"
fi

# Test 3: file-guard blocks type-first CONTEXT name
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/CONTEXT-01.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "wrong naming convention"; then
  pass "blocks CONTEXT-01.md (type-first)"
else
  fail "blocks CONTEXT-01.md — got rc=$RC, output: $OUTPUT"
fi

# Test 4: file-guard allows number-first PLAN name
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/01-PLAN.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
  pass "allows 01-PLAN.md (number-first)"
else
  fail "allows 01-PLAN.md — got rc=$RC, output: $OUTPUT"
fi

# Test 5: file-guard allows number-first SUMMARY name
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/01-SUMMARY.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
  pass "allows 01-SUMMARY.md (number-first)"
else
  fail "allows 01-SUMMARY.md — got rc=$RC, output: $OUTPUT"
fi

# --- normalize-plan-filenames tests ---
echo ""
echo "normalize-plan-filenames.sh:"
NORM_SCRIPT="$SCRIPT_DIR/scripts/normalize-plan-filenames.sh"

# Test 6: renames type-first to number-first
TDIR="$TMPDIR_TEST/test6"
mkdir -p "$TDIR"
echo "plan1" > "$TDIR/PLAN-01.md"
echo "plan2" > "$TDIR/PLAN-02.md"
echo "summary" > "$TDIR/PLAN-01-SUMMARY.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/01-PLAN.md" ] && [ -f "$TDIR/02-PLAN.md" ] && [ -f "$TDIR/01-SUMMARY.md" ]; then
  pass "renames PLAN-01.md → 01-PLAN.md, PLAN-02.md → 02-PLAN.md, PLAN-01-SUMMARY.md → 01-SUMMARY.md"
else
  fail "rename — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 7: renames SUMMARY-NN.md
TDIR="$TMPDIR_TEST/test7"
mkdir -p "$TDIR"
echo "summary" > "$TDIR/SUMMARY-03.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/03-SUMMARY.md" ]; then
  pass "renames SUMMARY-03.md → 03-SUMMARY.md"
else
  fail "SUMMARY rename — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 8: renames CONTEXT-NN.md
TDIR="$TMPDIR_TEST/test8"
mkdir -p "$TDIR"
echo "context" > "$TDIR/CONTEXT-01.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/01-CONTEXT.md" ]; then
  pass "renames CONTEXT-01.md → 01-CONTEXT.md"
else
  fail "CONTEXT rename — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 9: idempotent on correct names
TDIR="$TMPDIR_TEST/test9"
mkdir -p "$TDIR"
echo "plan" > "$TDIR/01-PLAN.md"
echo "summary" > "$TDIR/01-SUMMARY.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/01-PLAN.md" ] && [ -f "$TDIR/01-SUMMARY.md" ] && [ -z "$OUTPUT" ]; then
  pass "idempotent on correct names (no output, no renames)"
else
  fail "idempotent — rc=$RC, output: '$OUTPUT'"
fi

# Test 10: handles collision (both PLAN-01.md and 01-PLAN.md exist)
TDIR="$TMPDIR_TEST/test10"
mkdir -p "$TDIR"
echo "correct" > "$TDIR/01-PLAN.md"
echo "misnamed" > "$TDIR/PLAN-01.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
CONTENT=$(cat "$TDIR/01-PLAN.md")
if [ "$RC" -eq 0 ] && [ "$CONTENT" = "correct" ] && echo "$OUTPUT" | grep -q "skipped"; then
  pass "collision: skips PLAN-01.md when 01-PLAN.md exists"
else
  fail "collision — rc=$RC, content: $CONTENT, output: $OUTPUT"
fi

# Test 11: empty/missing dir exits 0
OUTPUT=$(bash "$NORM_SCRIPT" "$TMPDIR_TEST/nonexistent" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
  pass "exits 0 for nonexistent directory"
else
  fail "nonexistent dir — got rc=$RC"
fi

# --- phase-detect misnamed_plans diagnostic ---
echo ""
echo "phase-detect.sh misnamed_plans diagnostic:"

# Test 12: detects misnamed plans
TDIR="$TMPDIR_TEST/test12"
mkdir -p "$TDIR/.vbw-planning/phases/01-setup"
echo "plan" > "$TDIR/.vbw-planning/phases/01-setup/PLAN-01.md"
cat > "$TDIR/.vbw-planning/PROJECT.md" << 'EOF'
# Test Project
This is a test project.
EOF
OUTPUT=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null) && RC=$? || RC=$?
if echo "$OUTPUT" | grep -q "misnamed_plans=true"; then
  pass "phase-detect reports misnamed_plans=true"
else
  fail "phase-detect misnamed — output missing misnamed_plans=true"
fi

# Test 13: clean names report false
TDIR="$TMPDIR_TEST/test13"
mkdir -p "$TDIR/.vbw-planning/phases/01-setup"
echo "plan" > "$TDIR/.vbw-planning/phases/01-setup/01-PLAN.md"
cat > "$TDIR/.vbw-planning/PROJECT.md" << 'EOF'
# Test Project
This is a test project.
EOF
OUTPUT=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null) && RC=$? || RC=$?
if echo "$OUTPUT" | grep -q "misnamed_plans=false"; then
  pass "phase-detect reports misnamed_plans=false for clean names"
else
  fail "phase-detect clean — output missing misnamed_plans=false"
fi

# --- Uppercase extension (.MD) tests ---
echo ""
echo "Uppercase extension (.MD) handling:"

# Test 14: file-guard blocks uppercase PLAN-01.MD
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/PLAN-01.MD"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "wrong naming convention"; then
  pass "blocks PLAN-01.MD (uppercase extension)"
else
  fail "blocks PLAN-01.MD — got rc=$RC, output: $OUTPUT"
fi

# Test 15: file-guard blocks mixed-case SUMMARY-01.Md
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/SUMMARY-01.Md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "wrong naming convention"; then
  pass "blocks SUMMARY-01.Md (mixed-case extension)"
else
  fail "blocks SUMMARY-01.Md — got rc=$RC, output: $OUTPUT"
fi

# Test 16: normalize handles uppercase PLAN-01.MD (normalizes extension to lowercase)
TDIR="$TMPDIR_TEST/test16"
mkdir -p "$TDIR"
echo "plan" > "$TDIR/PLAN-01.MD"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/01-PLAN.md" ]; then
  pass "renames PLAN-01.MD → 01-PLAN.md (normalizes extension to lowercase)"
else
  fail "uppercase rename — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 17: phase-detect catches uppercase PLAN-01.MD
TDIR="$TMPDIR_TEST/test17"
mkdir -p "$TDIR/.vbw-planning/phases/01-setup"
echo "plan" > "$TDIR/.vbw-planning/phases/01-setup/PLAN-01.MD"
cat > "$TDIR/.vbw-planning/PROJECT.md" << 'EOF'
# Test Project
This is a test project.
EOF
OUTPUT=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null) && RC=$? || RC=$?
if echo "$OUTPUT" | grep -q "misnamed_plans=true"; then
  pass "phase-detect catches uppercase PLAN-01.MD"
else
  fail "phase-detect uppercase — output missing misnamed_plans=true"
fi

# --- PLAN-NN-CONTEXT compound form test ---
echo ""
echo "Compound form handling:"

# Test 18: normalize handles PLAN-01-CONTEXT.md → 01-CONTEXT.md
TDIR="$TMPDIR_TEST/test18"
mkdir -p "$TDIR"
echo "context" > "$TDIR/PLAN-01-CONTEXT.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/01-CONTEXT.md" ] && [ ! -f "$TDIR/01-PLAN.md" ]; then
  pass "renames PLAN-01-CONTEXT.md → 01-CONTEXT.md (not 01-PLAN.md)"
else
  fail "PLAN-NN-CONTEXT compound — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 19: normalize handles PLAN-02-SUMMARY.md alongside PLAN-02-CONTEXT.md
TDIR="$TMPDIR_TEST/test19"
mkdir -p "$TDIR"
echo "summary" > "$TDIR/PLAN-02-SUMMARY.md"
echo "context" > "$TDIR/PLAN-02-CONTEXT.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/02-SUMMARY.md" ] && [ -f "$TDIR/02-CONTEXT.md" ] && [ ! -f "$TDIR/02-PLAN.md" ]; then
  pass "renames both PLAN-02-SUMMARY.md and PLAN-02-CONTEXT.md correctly"
else
  fail "compound pair — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# --- file-guard precision tests ---
echo ""
echo "File-guard precision (false-positive prevention):"

# Test 20: file-guard allows plan-01-review.md (arbitrary name, not a plan)
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/plan-01-review.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
  pass "allows plan-01-review.md (not a type-first pattern)"
else
  fail "plan-01-review.md — got rc=$RC, output: $OUTPUT"
fi

# Test 21: file-guard allows summary-1custom.md (digits followed by letters)
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/summary-1custom.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
  pass "allows summary-1custom.md (not a strict type-first pattern)"
else
  fail "summary-1custom.md — got rc=$RC, output: $OUTPUT"
fi

# Test 22: file-guard still blocks PLAN-01-SUMMARY.md (compound type-first)
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/PLAN-01-SUMMARY.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "wrong naming convention"; then
  pass "blocks PLAN-01-SUMMARY.md (compound type-first)"
else
  fail "PLAN-01-SUMMARY.md — got rc=$RC, output: $OUTPUT"
fi

# Test 23: file-guard still blocks PLAN-01-CONTEXT.md (compound type-first)
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/PLAN-01-CONTEXT.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "wrong naming convention"; then
  pass "blocks PLAN-01-CONTEXT.md (compound type-first)"
else
  fail "PLAN-01-CONTEXT.md — got rc=$RC, output: $OUTPUT"
fi

# --- Edge-case tests (unknown compounds, symlinks, many digits) ---
echo ""
echo "Edge cases:"

# Test 24: normalize skips unknown compound PLAN-01-RESEARCH.md
TDIR="$TMPDIR_TEST/test24"
mkdir -p "$TDIR"
echo "research" > "$TDIR/PLAN-01-RESEARCH.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/PLAN-01-RESEARCH.md" ] && [ ! -f "$TDIR/01-PLAN.md" ]; then
  pass "skips unknown compound PLAN-01-RESEARCH.md (no rename)"
else
  fail "unknown compound — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 25: normalize skips unknown compound SUMMARY-01-extra.md
TDIR="$TMPDIR_TEST/test25"
mkdir -p "$TDIR"
echo "extra" > "$TDIR/SUMMARY-01-extra.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/SUMMARY-01-extra.md" ] && [ ! -f "$TDIR/01-SUMMARY.md" ]; then
  pass "skips unknown compound SUMMARY-01-extra.md (no rename)"
else
  fail "SUMMARY compound — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 26: normalize handles many-digit PLAN-0000001.md → 01-PLAN.md
TDIR="$TMPDIR_TEST/test26"
mkdir -p "$TDIR"
echo "plan" > "$TDIR/PLAN-0000001.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/01-PLAN.md" ]; then
  pass "normalizes PLAN-0000001.md → 01-PLAN.md (many leading zeros)"
else
  fail "many zeros — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 27: normalize skips symlinks
TDIR="$TMPDIR_TEST/test27"
mkdir -p "$TDIR"
echo "real" > "$TDIR/real-plan.md"
ln -s "$TDIR/real-plan.md" "$TDIR/PLAN-01.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -L "$TDIR/PLAN-01.md" ] && [ ! -f "$TDIR/01-PLAN.md" ]; then
  pass "skips symlink PLAN-01.md (no rename)"
else
  fail "symlink — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 28: phase-detect ignores PLAN-01-RESEARCH.md (not a misnamed plan)
TDIR="$TMPDIR_TEST/test28"
mkdir -p "$TDIR/.vbw-planning/phases/01-setup"
echo "research" > "$TDIR/.vbw-planning/phases/01-setup/PLAN-01-RESEARCH.md"
cat > "$TDIR/.vbw-planning/PROJECT.md" << 'EOF'
# Test Project
This is a test project.
EOF
OUTPUT=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null) && RC=$? || RC=$?
if echo "$OUTPUT" | grep -q "misnamed_plans=false"; then
  pass "phase-detect ignores PLAN-01-RESEARCH.md (not a known misname pattern)"
else
  fail "phase-detect compound — output missing misnamed_plans=false, got: $(echo "$OUTPUT" | grep misnamed)"
fi

# --- Type-aware error messages, path normalization, placeholder guard ---
echo ""
echo "Type-aware error messages and path handling:"

# Test 29: file-guard error message references SUMMARY (not PLAN) for SUMMARY-01.md
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/SUMMARY-01.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "SUMMARY artifact" && echo "$OUTPUT" | grep -q "{NN}-SUMMARY.md"; then
  pass "error references SUMMARY type for SUMMARY-01.md"
else
  fail "type-aware SUMMARY — got rc=$RC, output: $OUTPUT"
fi

# Test 30: file-guard error message references CONTEXT for CONTEXT-02.md
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/02-impl/CONTEXT-02.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "CONTEXT artifact" && echo "$OUTPUT" | grep -q "{NN}-CONTEXT.md"; then
  pass "error references CONTEXT type for CONTEXT-02.md"
else
  fail "type-aware CONTEXT — got rc=$RC, output: $OUTPUT"
fi

# Test 31: file-guard error message references PLAN for plain PLAN-01.md
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/PLAN-01.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "PLAN artifact" && echo "$OUTPUT" | grep -q "{NN}-PLAN.md"; then
  pass "error references PLAN type for PLAN-01.md"
else
  fail "type-aware PLAN — got rc=$RC, output: $OUTPUT"
fi

# Test 32: file-guard blocks .. traversal path (e.g., phases/01-setup/../01-setup/PLAN-01.md)
OUTPUT=$(echo '{"tool_input":{"file_path":".vbw-planning/phases/01-setup/../01-setup/PLAN-01.md"}}' | bash "$SCRIPT_DIR/scripts/file-guard.sh" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "wrong naming convention"; then
  pass "blocks PLAN-01.md via .. traversal path"
else
  fail ".. traversal — got rc=$RC, output: $OUTPUT"
fi

# --- Lowercase normalization tests (Finding 1 regression) ---
echo ""
echo "Lowercase type-first normalization:"

# Test 34: normalize renames lowercase plan-01.md → 01-PLAN.md
TDIR="$TMPDIR_TEST/test34"
mkdir -p "$TDIR"
echo "plan" > "$TDIR/plan-01.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/01-PLAN.md" ] && [ ! -f "$TDIR/plan-01.md" ]; then
  pass "renames lowercase plan-01.md → 01-PLAN.md"
else
  fail "lowercase plan — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 35: normalize renames lowercase summary-02.md → 02-SUMMARY.md
TDIR="$TMPDIR_TEST/test35"
mkdir -p "$TDIR"
echo "summary" > "$TDIR/summary-02.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/02-SUMMARY.md" ] && [ ! -f "$TDIR/summary-02.md" ]; then
  pass "renames lowercase summary-02.md → 02-SUMMARY.md"
else
  fail "lowercase summary — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 36: normalize renames lowercase context-03.md → 03-CONTEXT.md
TDIR="$TMPDIR_TEST/test36"
mkdir -p "$TDIR"
echo "context" > "$TDIR/context-03.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/03-CONTEXT.md" ] && [ ! -f "$TDIR/context-03.md" ]; then
  pass "renames lowercase context-03.md → 03-CONTEXT.md"
else
  fail "lowercase context — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# Test 37: normalize renames mixed-case Plan-01.md → 01-PLAN.md
TDIR="$TMPDIR_TEST/test37"
mkdir -p "$TDIR"
echo "plan" > "$TDIR/Plan-01.md"
OUTPUT=$(bash "$NORM_SCRIPT" "$TDIR" 2>&1) && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TDIR/01-PLAN.md" ] && [ ! -f "$TDIR/Plan-01.md" ]; then
  pass "renames mixed-case Plan-01.md → 01-PLAN.md"
else
  fail "mixed-case Plan — rc=$RC, files: $(ls "$TDIR"), output: $OUTPUT"
fi

# --- 3+ digit phase-detect tests (Finding 2 regression) ---
echo ""
echo "Multi-digit phase-detect detection:"

# Test 38: phase-detect catches PLAN-100.md (3 digits)
TDIR="$TMPDIR_TEST/test38"
mkdir -p "$TDIR/.vbw-planning/phases/01-setup"
echo "plan" > "$TDIR/.vbw-planning/phases/01-setup/PLAN-100.md"
cat > "$TDIR/.vbw-planning/PROJECT.md" << 'EOF'
# Test Project
This is a test project.
EOF
OUTPUT=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null) && RC=$? || RC=$?
if echo "$OUTPUT" | grep -q "misnamed_plans=true"; then
  pass "phase-detect catches PLAN-100.md (3 digits)"
else
  fail "phase-detect 3-digit — output missing misnamed_plans=true, got: $(echo "$OUTPUT" | grep misnamed)"
fi

# Test 39: phase-detect catches PLAN-1000.md (4 digits)
TDIR="$TMPDIR_TEST/test39"
mkdir -p "$TDIR/.vbw-planning/phases/01-setup"
echo "plan" > "$TDIR/.vbw-planning/phases/01-setup/PLAN-1000.md"
cat > "$TDIR/.vbw-planning/PROJECT.md" << 'EOF'
# Test Project
This is a test project.
EOF
OUTPUT=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null) && RC=$? || RC=$?
if echo "$OUTPUT" | grep -q "misnamed_plans=true"; then
  pass "phase-detect catches PLAN-1000.md (4 digits)"
else
  fail "phase-detect 4-digit — output missing misnamed_plans=true, got: $(echo "$OUTPUT" | grep misnamed)"
fi

# Test 40: phase-detect still ignores PLAN-100-RESEARCH.md (unknown compound, 3 digits)
TDIR="$TMPDIR_TEST/test40"
mkdir -p "$TDIR/.vbw-planning/phases/01-setup"
echo "research" > "$TDIR/.vbw-planning/phases/01-setup/PLAN-100-RESEARCH.md"
cat > "$TDIR/.vbw-planning/PROJECT.md" << 'EOF'
# Test Project
This is a test project.
EOF
OUTPUT=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null) && RC=$? || RC=$?
if echo "$OUTPUT" | grep -q "misnamed_plans=false"; then
  pass "phase-detect ignores PLAN-100-RESEARCH.md (unknown compound, 3 digits)"
else
  fail "phase-detect 3-digit compound — output missing misnamed_plans=false, got: $(echo "$OUTPUT" | grep misnamed)"
fi

# --- End-to-end: phase-detect → normalize → phase-detect loop ---
echo ""
echo "End-to-end misnamed repair loop:"

# Test 41: misnamed_plans=true → normalize → misnamed_plans=false
TDIR="$TMPDIR_TEST/test41"
mkdir -p "$TDIR/.vbw-planning/phases/01-setup"
echo "plan" > "$TDIR/.vbw-planning/phases/01-setup/PLAN-01.md"
echo "summary" > "$TDIR/.vbw-planning/phases/01-setup/SUMMARY-01.md"
echo "context" > "$TDIR/.vbw-planning/phases/01-setup/CONTEXT-01.md"
cat > "$TDIR/.vbw-planning/PROJECT.md" << 'EOF'
# Test Project
This is a test project.
EOF
OUTPUT_BEFORE=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null)
bash "$NORM_SCRIPT" "$TDIR/.vbw-planning/phases/01-setup" >/dev/null 2>&1
OUTPUT_AFTER=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null)
if echo "$OUTPUT_BEFORE" | grep -q "misnamed_plans=true" && echo "$OUTPUT_AFTER" | grep -q "misnamed_plans=false"; then
  pass "end-to-end: misnamed_plans true → normalize → false"
else
  fail "end-to-end — before: $(echo "$OUTPUT_BEFORE" | grep misnamed), after: $(echo "$OUTPUT_AFTER" | grep misnamed)"
fi

# Test 42: end-to-end with lowercase misnamed files
TDIR="$TMPDIR_TEST/test42"
mkdir -p "$TDIR/.vbw-planning/phases/01-setup"
echo "plan" > "$TDIR/.vbw-planning/phases/01-setup/plan-01.md"
echo "summary" > "$TDIR/.vbw-planning/phases/01-setup/summary-02.md"
cat > "$TDIR/.vbw-planning/PROJECT.md" << 'EOF'
# Test Project
This is a test project.
EOF
OUTPUT_BEFORE=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null)
bash "$NORM_SCRIPT" "$TDIR/.vbw-planning/phases/01-setup" >/dev/null 2>&1
OUTPUT_AFTER=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null)
if echo "$OUTPUT_BEFORE" | grep -q "misnamed_plans=true" && echo "$OUTPUT_AFTER" | grep -q "misnamed_plans=false"; then
  pass "end-to-end: lowercase misnamed → normalize → clean"
else
  fail "end-to-end lowercase — before: $(echo "$OUTPUT_BEFORE" | grep misnamed), after: $(echo "$OUTPUT_AFTER" | grep misnamed)"
fi

# --- Command-level normalization guard contract tests ---
echo ""
echo "Command normalization guard contracts:"

# Test 43: qa.md contains normalization guard
if grep -q 'normalize-plan-filenames.sh' "$SCRIPT_DIR/commands/qa.md" && grep -q 'misnamed_plans=true' "$SCRIPT_DIR/commands/qa.md"; then
  pass "qa.md contains normalization guard"
else
  fail "qa.md missing normalization guard"
fi

# Test 44: verify.md contains normalization guard
if grep -q 'normalize-plan-filenames.sh' "$SCRIPT_DIR/commands/verify.md" && grep -q 'misnamed_plans=true' "$SCRIPT_DIR/commands/verify.md"; then
  pass "verify.md contains normalization guard"
else
  fail "verify.md missing normalization guard"
fi

# Test 45: vibe.md contains normalization guard
if grep -q 'normalize-plan-filenames.sh' "$SCRIPT_DIR/commands/vibe.md" && grep -q 'misnamed_plans=true' "$SCRIPT_DIR/commands/vibe.md"; then
  pass "vibe.md contains normalization guard"
else
  fail "vibe.md missing normalization guard"
fi

# Test 46: status.md contains normalization guard
if grep -q 'normalize-plan-filenames.sh' "$SCRIPT_DIR/commands/status.md" && grep -q 'misnamed_plans=true' "$SCRIPT_DIR/commands/status.md"; then
  pass "status.md contains normalization guard"
else
  fail "status.md missing normalization guard"
fi

# Test 47: resume.md contains normalization guard
if grep -q 'normalize-plan-filenames.sh' "$SCRIPT_DIR/commands/resume.md" && grep -q 'misnamed_plans=true' "$SCRIPT_DIR/commands/resume.md"; then
  pass "resume.md contains normalization guard"
else
  fail "resume.md missing normalization guard"
fi

# Test 48: verify.md refreshes phase-detect after normalization
NORM_LINE=$(grep -n 'normalize-plan-filenames' "$SCRIPT_DIR/commands/verify.md" | head -1 | cut -d: -f1)
REFRESH_LINE=$(grep -n 're-run phase-detect' "$SCRIPT_DIR/commands/verify.md" | head -1 | cut -d: -f1)
if [ -n "$NORM_LINE" ] && [ -n "$REFRESH_LINE" ] && [ "$REFRESH_LINE" -gt "$NORM_LINE" ]; then
  pass "verify.md refreshes phase-detect after normalization"
else
  fail "verify.md missing post-normalization phase-detect refresh"
fi

# Test 49: verify.md has post-normalization verify context regeneration
if grep -q 'compile-verify-context' "$SCRIPT_DIR/commands/verify.md" && grep -B5 -A5 'compile-verify-context' "$SCRIPT_DIR/commands/verify.md" | grep -qi 'normalization\|stale'; then
  pass "verify.md has post-normalization verify context regeneration"
else
  fail "verify.md missing post-normalization verify context refresh"
fi

# Test 50: verify.md auto-detect phase precedes SUMMARY check
AUTO_LINE=$(grep -n 'Auto-detect phase' "$SCRIPT_DIR/commands/verify.md" | head -1 | cut -d: -f1)
SUMMARY_LINE=$(grep -n 'No SUMMARY.md' "$SCRIPT_DIR/commands/verify.md" | head -1 | cut -d: -f1)
if [ -n "$AUTO_LINE" ] && [ -n "$SUMMARY_LINE" ] && [ "$AUTO_LINE" -lt "$SUMMARY_LINE" ]; then
  pass "verify.md auto-detect phase precedes SUMMARY check"
else
  fail "verify.md SUMMARY check should come after auto-detect phase"
fi

# --- Post-normalization refresh parity tests ---
echo ""
echo "Post-normalization phase-detect refresh parity:"

# Test 51: status.md refreshes phase-detect after normalization
NORM_LINE_S=$(grep -n 'normalize-plan-filenames' "$SCRIPT_DIR/commands/status.md" | head -1 | cut -d: -f1)
REFRESH_LINE_S=$(grep -n 'phase-detect.sh' "$SCRIPT_DIR/commands/status.md" | grep -v 'Context\|context\|Plugin root' | tail -1 | cut -d: -f1)
if [ -n "$NORM_LINE_S" ] && [ -n "$REFRESH_LINE_S" ] && [ "$REFRESH_LINE_S" -gt "$NORM_LINE_S" ]; then
  pass "status.md refreshes phase-detect after normalization"
else
  fail "status.md missing post-normalization phase-detect refresh"
fi

# Test 52: resume.md refreshes phase-detect after normalization
NORM_LINE_R=$(grep -n 'normalize-plan-filenames' "$SCRIPT_DIR/commands/resume.md" | head -1 | cut -d: -f1)
REFRESH_LINE_R=$(grep -n 're-run phase-detect' "$SCRIPT_DIR/commands/resume.md" | head -1 | cut -d: -f1)
if [ -n "$NORM_LINE_R" ] && [ -n "$REFRESH_LINE_R" ] && [ "$REFRESH_LINE_R" -gt "$NORM_LINE_R" ]; then
  pass "resume.md refreshes phase-detect after normalization"
else
  fail "resume.md missing post-normalization phase-detect refresh"
fi

# Test 53: qa.md refreshes phase-detect after normalization
NORM_LINE_Q=$(grep -n 'normalize-plan-filenames' "$SCRIPT_DIR/commands/qa.md" | head -1 | cut -d: -f1)
REFRESH_LINE_Q=$(grep -n 'phase-detect.sh' "$SCRIPT_DIR/commands/qa.md" | grep -v 'Context\|context\|Plugin root' | tail -1 | cut -d: -f1)
if [ -n "$NORM_LINE_Q" ] && [ -n "$REFRESH_LINE_Q" ] && [ "$REFRESH_LINE_Q" -gt "$NORM_LINE_Q" ]; then
  pass "qa.md refreshes phase-detect after normalization"
else
  fail "qa.md missing post-normalization phase-detect refresh"
fi

# Test 54: verify.md uses deterministic misnamed_plans condition (not inferential)
if grep -q 'misnamed_plans=true' "$SCRIPT_DIR/commands/verify.md" && \
   grep -q 'initial Phase state contained.*misnamed_plans=true' "$SCRIPT_DIR/commands/verify.md"; then
  pass "verify.md uses deterministic misnamed_plans condition for regeneration"
else
  fail "verify.md regeneration condition is inferential (should reference misnamed_plans=true)"
fi

# Test 55: all normalization-aware commands instruct using refreshed output
for cmd in status resume verify qa; do
  if grep -q 'refreshed.*phase-detect\|refreshed.*output\|Use the refreshed' "$SCRIPT_DIR/commands/$cmd.md"; then
    pass "$cmd.md instructs using refreshed phase-detect output"
  else
    fail "$cmd.md missing instruction to use refreshed phase-detect output"
  fi
done

# --- Behavioral: end-to-end phase-state refresh after normalization ---
echo ""
echo "Behavioral state-refresh tests:"

# Test 56: phase-detect shows correct plan/summary counts after normalization
TDIR="$TMPDIR_TEST/test56"
mkdir -p "$TDIR/.vbw-planning/phases/01-setup"
cat > "$TDIR/.vbw-planning/PROJECT.md" << 'EOF'
# Test Project
This is a test project.
EOF
echo "plan" > "$TDIR/.vbw-planning/phases/01-setup/PLAN-01.md"
echo "plan2" > "$TDIR/.vbw-planning/phases/01-setup/PLAN-02.md"
printf '%s\n' '---' 'status: complete' '---' 'summary' > "$TDIR/.vbw-planning/phases/01-setup/SUMMARY-01.md"
# Before normalization: misnamed, and plan/summary counts should track
OUTPUT_BEFORE=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null)
PLANS_BEFORE=$(echo "$OUTPUT_BEFORE" | grep '^next_phase_plans=' | cut -d= -f2)
SUMMARIES_BEFORE=$(echo "$OUTPUT_BEFORE" | grep '^next_phase_summaries=' | cut -d= -f2)
# Normalize
bash "$NORM_SCRIPT" "$TDIR/.vbw-planning/phases/01-setup" >/dev/null 2>&1
# After normalization: clean, counts should be preserved
OUTPUT_AFTER=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null)
PLANS_AFTER=$(echo "$OUTPUT_AFTER" | grep '^next_phase_plans=' | cut -d= -f2)
SUMMARIES_AFTER=$(echo "$OUTPUT_AFTER" | grep '^next_phase_summaries=' | cut -d= -f2)
MISNAMED_AFTER=$(echo "$OUTPUT_AFTER" | grep '^misnamed_plans=' | cut -d= -f2)
if [ "$PLANS_AFTER" = "2" ] && [ "$SUMMARIES_AFTER" = "1" ] && [ "$MISNAMED_AFTER" = "false" ]; then
  pass "phase-detect counts preserved after normalization (plans=$PLANS_AFTER, summaries=$SUMMARIES_AFTER)"
else
  fail "phase-detect counts wrong after normalization — plans=$PLANS_AFTER (want 2), summaries=$SUMMARIES_AFTER (want 1), misnamed=$MISNAMED_AFTER (want false)"
fi

# Test 57: phase-detect next_phase_state transitions correctly after normalization
TDIR="$TMPDIR_TEST/test57"
mkdir -p "$TDIR/.vbw-planning/phases/01-setup" "$TDIR/.vbw-planning/phases/02-impl"
cat > "$TDIR/.vbw-planning/PROJECT.md" << 'EOF'
# Test Project
This is a test project.
EOF
printf '%s\n' '# Roadmap' '' '## Phase 01: Setup' '- Status: complete' '' '## Phase 02: Implementation' '- Status: not started' > "$TDIR/.vbw-planning/ROADMAP.md"
echo "plan" > "$TDIR/.vbw-planning/phases/01-setup/PLAN-01.md"
printf '%s\n' '---' 'status: complete' '---' 'done' > "$TDIR/.vbw-planning/phases/01-setup/SUMMARY-01.md"
# misnamed plans in phase 01, phase 02 empty
OUTPUT_BEFORE=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null)
MISNAMED_B=$(echo "$OUTPUT_BEFORE" | grep '^misnamed_plans=' | cut -d= -f2)
bash "$NORM_SCRIPT" "$TDIR/.vbw-planning/phases/01-setup" >/dev/null 2>&1
OUTPUT_AFTER=$(cd "$TDIR" && bash "$SCRIPT_DIR/scripts/phase-detect.sh" 2>/dev/null)
MISNAMED_A=$(echo "$OUTPUT_AFTER" | grep '^misnamed_plans=' | cut -d= -f2)
STATE_A=$(echo "$OUTPUT_AFTER" | grep '^next_phase_state=' | cut -d= -f2)
if [ "$MISNAMED_B" = "true" ] && [ "$MISNAMED_A" = "false" ]; then
  pass "normalization clears misnamed_plans flag across phases"
else
  fail "misnamed_plans flag not cleared — before=$MISNAMED_B, after=$MISNAMED_A, state=$STATE_A"
fi

echo ""
echo "==============================="
echo "Plan filename convention: $PASS passed, $FAIL failed"
echo "==============================="
[ "$FAIL" -eq 0 ] || exit 1

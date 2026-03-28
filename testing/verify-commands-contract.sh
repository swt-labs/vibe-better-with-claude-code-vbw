#!/usr/bin/env bash
set -euo pipefail

# verify-commands-contract.sh — Structural + reference checks for all command files
#
# Checks each commands/*.md file for:
# - YAML frontmatter
# - name matches file basename (plugin auto-prefixes vbw:)
# - single-line non-empty description
# - allowed-tools field present
# - `${CLAUDE_PLUGIN_ROOT}/...` references resolve to real files/dirs

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMANDS_DIR="$ROOT/commands"

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

extract_frontmatter() {
  local file="$1"
  awk '
    BEGIN { delim=0 }
    /^---$/ {
      delim++
      if (delim == 2) exit
      next
    }
    delim == 1 { print }
  ' "$file"
}

echo "=== Command Contract Verification ==="

# Scan both commands/ (consumer-facing) and internal/ (maintainer-only)
for file in "$COMMANDS_DIR"/*.md "$ROOT/internal"/*.md; do
  [ -f "$file" ] || continue
  base="$(basename "$file" .md)"

  if [ "$(head -1 "$file" 2>/dev/null || true)" != "---" ]; then
    fail "$base: missing YAML frontmatter opener"
    continue
  fi

  FRONTMATTER="$(extract_frontmatter "$file")"
  if [ -z "$FRONTMATTER" ]; then
    fail "$base: empty or malformed frontmatter"
    continue
  fi

  NAME_VALUE="$(printf '%s\n' "$FRONTMATTER" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
  # Strip vbw: prefix if present — plugin auto-prefixes the namespace
  NAME_STEM="${NAME_VALUE#vbw:}"

  if [ -z "$NAME_VALUE" ]; then
    fail "$base: missing name field"
  elif [ "$NAME_STEM" != "$base" ]; then
    fail "$base: name mismatch (expected '$base', got '$NAME_VALUE')"
  else
    pass "$base: name matches filename"
  fi

  if ! printf '%s\n' "$FRONTMATTER" | grep -q '^allowed-tools:'; then
    fail "$base: missing allowed-tools field"
  else
    pass "$base: allowed-tools present"
  fi

  DESC_COUNT="$(printf '%s\n' "$FRONTMATTER" | grep -c '^description:')"
  if [ "$DESC_COUNT" -ne 1 ]; then
    fail "$base: description field missing or duplicated"
    continue
  fi

  DESC_VALUE="$(printf '%s\n' "$FRONTMATTER" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
  if [ -z "$DESC_VALUE" ]; then
    fail "$base: description is empty"
  elif [[ "$DESC_VALUE" == \|* || "$DESC_VALUE" == \>* ]]; then
    fail "$base: description must be single-line (block scalar found)"
  else
    AFTER_DESC="$(printf '%s\n' "$FRONTMATTER" | awk '/^description:/{found=1; next} found && /^[[:space:]]/{print; next} found{exit}')"
    if [ -n "$AFTER_DESC" ]; then
      fail "$base: description has continuation lines"
    else
      pass "$base: description is single-line"
    fi
  fi
done

echo ""
echo "=== Milestone Context Verification ==="

# Commands that reference milestone-scoped paths in their Steps section must have
# either:
# 1. The ACTIVE milestone shell interpolation in their Context section, OR
# 2. Bash in allowed-tools (so the agent can read ACTIVE at runtime)
# Without either, the agent has no way to discover the active milestone slug.
for file in "$COMMANDS_DIR"/*.md "$ROOT/internal"/*.md; do
  [ -f "$file" ] || continue
  base="$(basename "$file" .md)"

  # Extract body after frontmatter, excluding Context section (which contains the fix itself)
  body="$(awk '/^---$/{d++; next} d>=2' "$file")"
  body_no_context="$(printf '%s\n' "$body" | awk '/^## Context$/{skip=1; next} /^## /{skip=0} !skip')"

  # ACTIVE-file milestone indirection was removed (architecture simplification).
  # Commands should NOT reference .vbw-planning/ACTIVE anymore.
  if printf '%s\n' "$body_no_context" | grep -qi '\.vbw-planning/ACTIVE'; then
    fail "$base: references .vbw-planning/ACTIVE — milestone indirection was removed"
  else
    pass "$base: no stale ACTIVE file references"
  fi
done

echo ""
echo "=== Stale ACTIVE Reference Verification (scripts + references) ==="

# Scan scripts and references for any runtime usage of .vbw-planning/ACTIVE
# (session-start.sh is allowed — it only deletes the stale file)
for scan_dir in "$ROOT/scripts" "$ROOT/references" "$ROOT/agents" "$ROOT/templates"; do
  [ -d "$scan_dir" ] || continue
  dir_label="$(basename "$scan_dir")"
  while IFS= read -r -d '' scan_file; do
    scan_base="$(basename "$scan_file")"

    # session-start.sh is allowed to reference ACTIVE (rm -f cleanup migration)
    if [[ "$scan_base" == "session-start.sh" ]]; then
      pass "$dir_label/$scan_base: ACTIVE reference allowed (cleanup migration)"
      continue
    fi

    if grep -qi '\.vbw-planning/ACTIVE' "$scan_file" 2>/dev/null; then
      fail "$dir_label/$scan_base: references .vbw-planning/ACTIVE — milestone indirection was removed"
    else
      pass "$dir_label/$scan_base: no stale ACTIVE file references"
    fi
  done < <(find "$scan_dir" -maxdepth 2 -type f \( -name '*.sh' -o -name '*.md' \) -print0 2>/dev/null)
done

echo ""
echo "=== Phase-Detect Usage Verification ==="

# Commands that present phase progress MUST use phase-detect.sh output for state
# detection rather than having the LLM glob and compute state independently.
# Without this, the LLM may read from archived milestone directories and present
# stale data. Commands that read STATE.md/ROADMAP.md should also scope reads to
# top-level .vbw-planning/ only (not milestones/).
PHASE_DETECT_REQUIRED_COMMANDS="resume vibe discuss qa verify"
for pd_cmd in $PHASE_DETECT_REQUIRED_COMMANDS; do
  pd_file="$COMMANDS_DIR/${pd_cmd}.md"
  if [ ! -f "$pd_file" ]; then
    fail "$pd_cmd: command file not found"
    continue
  fi
  if grep -q 'phase-detect\.sh' "$pd_file"; then
    pass "$pd_cmd: uses phase-detect.sh for state detection"
  else
    fail "$pd_cmd: missing phase-detect.sh — LLM may read archived milestone data"
  fi
done

echo ""
echo "=== Phase-Detect Refresh Safety Verification ==="

for pd_safe_cmd in vibe verify resume status discuss qa; do
  pd_safe_file="$COMMANDS_DIR/${pd_safe_cmd}.md"
  if [ ! -f "$pd_safe_file" ]; then
    fail "$pd_safe_cmd: command file not found"
    continue
  fi

  if grep -Fq '_PD_CACHE="$PD"' "$pd_safe_file"; then
    fail "$pd_safe_cmd: stale phase-detect cache fallback still present"
  else
    pass "$pd_safe_cmd: no stale phase-detect cache fallback"
  fi

  if grep -Fq 'if [ -L "$L" ] && [ -f "$L/scripts/hook-wrapper.sh" ]; then R="$L"; fi' "$pd_safe_file"; then
    fail "$pd_safe_cmd: reuses session symlink as plugin-root candidate"
  else
    pass "$pd_safe_cmd: does not trust session symlink as plugin root"
  fi
done

echo ""
echo "=== Verify Guardrail Verification ==="

VIBE_FILE="$COMMANDS_DIR/vibe.md"
VERIFY_FILE="$COMMANDS_DIR/verify.md"

if grep -q 'Verify-context error guard (NON-NEGOTIABLE)' "$VERIFY_FILE"; then
  pass "verify: has fail-closed verify-context error guard"
else
  fail "verify: missing fail-closed verify-context error guard"
fi

if grep -q 'If the user specified an explicit phase number that differs from the auto-detected target, ignore the pre-computed `qa_status`' "$VERIFY_FILE"; then
  pass "verify: explicit target phases ignore auto-detected qa_status"
else
  fail "verify: missing explicit-phase qa_status override guidance"
fi

if grep -q 'Only proceed to UAT when the PASS is fresh for the target phase' "$VERIFY_FILE"; then
  pass "verify: explicit QA gate requires fresh PASS for target phase"
else
  fail "verify: missing fresh-PASS requirement in explicit QA gate"
fi

if grep -q 'echo "verify_context=unavailable"' "$VIBE_FILE"; then
  pass "vibe: routed verify precompute emits fail-closed verify_context sentinel"
else
  fail "vibe: routed verify precompute missing fail-closed verify_context sentinel"
fi

echo ""
echo "=== Milestone Context Refresh Verification ==="
mode_block() {
  local heading="$1"
  awk -v h="$heading" '
    $0 == h { found=1; print; next }
    found && /^### Mode: / { exit }
    found { print }
  ' "$VIBE_FILE"
}

for mode in "### Mode: Add Phase" "### Mode: Insert Phase" "### Mode: Remove Phase"; do
  block=$(mode_block "$mode")
  label=${mode#"### Mode: "}

  if printf '%s\n' "$block" | grep -q 'If `\.vbw-planning/CONTEXT\.md` exists, rewrite it to reflect the updated milestone decomposition'; then
    pass "vibe: $label refreshes milestone CONTEXT.md"
  else
    fail "vibe: $label missing milestone CONTEXT refresh instruction"
  fi

  if printf '%s\n' "$block" | grep -q 'Preserve project-level key decisions and deferred ideas where still valid\.'; then
    pass "vibe: $label preserves milestone decisions and deferred ideas"
  else
    fail "vibe: $label missing preservation instruction for milestone CONTEXT refresh"
  fi
done

echo ""
echo "=== QA Result Gate Contract ==="

# vibe.md must reference qa-result-gate.sh in the QA gate section
if grep -q 'qa-result-gate\.sh' "$COMMANDS_DIR/vibe.md" 2>/dev/null; then
  pass "vibe: references qa-result-gate.sh"
else
  fail "vibe: missing qa-result-gate.sh reference in QA gate section"
fi

# execute-protocol.md must reference qa-result-gate.sh in Step 4.1
if grep -q 'qa-result-gate\.sh' "$ROOT/references/execute-protocol.md" 2>/dev/null; then
  pass "execute-protocol: references qa-result-gate.sh"
else
  fail "execute-protocol: missing qa-result-gate.sh reference in Step 4.1"
fi

# Both must include the anti-rationalization instruction
for f in "$COMMANDS_DIR/vibe.md" "$ROOT/references/execute-protocol.md"; do
  base=$(basename "$f")
  if grep -q 'no exceptions, no judgment' "$f" 2>/dev/null; then
    pass "$base: has anti-rationalization instruction"
  else
    fail "$base: missing anti-rationalization instruction for qa_gate_routing"
  fi
done

echo ""
echo "=== Command Reference Verification ==="

while IFS= read -r ref; do
  rel="${ref#\$\{CLAUDE_PLUGIN_ROOT\}/}"

  # Template placeholders like {profile} are dynamic by design.
  if [[ "$rel" == *"{"* || "$rel" == *"}"* ]]; then
    pass "reference uses template placeholder (skipped): $ref"
    continue
  fi

  # Wildcard references must match at least one file.
  if [[ "$rel" == *"*"* ]]; then
    if compgen -G "$ROOT/$rel" >/dev/null; then
      pass "wildcard reference resolves: $ref"
    else
      fail "wildcard reference has no matches: $ref"
    fi
    continue
  fi

  if [ -e "$ROOT/$rel" ]; then
    pass "reference resolves: $ref"
  else
    fail "reference missing target: $ref -> $rel"
  fi
done < <(grep -RhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9._/*{}-]+' "$COMMANDS_DIR"/*.md "$ROOT/internal"/*.md 2>/dev/null | sort -u)

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All command contract checks passed."
exit 0

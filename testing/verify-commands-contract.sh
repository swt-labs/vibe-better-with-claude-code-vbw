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

for file in "$COMMANDS_DIR"/*.md; do
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
for file in "$COMMANDS_DIR"/*.md; do
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
done < <(grep -RhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9._/*{}-]+' "$COMMANDS_DIR"/*.md | sort -u)

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All command contract checks passed."
exit 0

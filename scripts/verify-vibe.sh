#!/usr/bin/env bash
set -euo pipefail

# verify-vibe.sh — Automated verification of vibe command consolidation (Plan 03-01)
#
# Checks all 25 requirements (REQ-01 through REQ-25) across 6 groups.
# Read-only: never modifies any files.
#
# Usage: bash scripts/verify-vibe.sh
# Exit: 0 if all pass, 1 if any fail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

VIBE="$ROOT/commands/vibe.md"
PROTOCOL="$ROOT/references/execute-protocol.md"
README="$ROOT/README.md"
CLAUDE_MD="$ROOT/CLAUDE.md"
HELP="$ROOT/commands/help.md"
SUGGEST="$ROOT/scripts/suggest-next.sh"
MKT_ROOT="$ROOT/marketplace.json"
MKT_PLUGIN="$ROOT/.claude-plugin/marketplace.json"

tracked_repo_file_exists() {
  git -C "$ROOT" ls-files --error-unmatch "$1" >/dev/null 2>&1
}

tracked_markdown_count() {
  git -C "$ROOT" ls-files -- "$@" | wc -l | tr -d ' '
}

# Counters
TOTAL_PASS=0
TOTAL_FAIL=0
GROUP_PASS=0
GROUP_FAIL=0

# --- Helpers ---

group_start() {
  GROUP_PASS=0
  GROUP_FAIL=0
  echo ""
  echo "=== $1 ==="
}

group_end() {
  local label="$1"
  TOTAL_PASS=$((TOTAL_PASS + GROUP_PASS))
  TOTAL_FAIL=$((TOTAL_FAIL + GROUP_FAIL))
  if [ "$GROUP_FAIL" -eq 0 ]; then
    echo "  >> $label: ALL PASS ($GROUP_PASS checks)"
  else
    echo "  >> $label: $GROUP_FAIL FAIL, $GROUP_PASS pass"
  fi
}

check() {
  local req="$1"
  local desc="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then
    echo "  PASS  $req: $desc"
    GROUP_PASS=$((GROUP_PASS + 1))
  else
    echo "  FAIL  $req: $desc"
    GROUP_FAIL=$((GROUP_FAIL + 1))
  fi
}

check_absent() {
  local req="$1"
  local desc="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then
    echo "  FAIL  $req: $desc"
    GROUP_FAIL=$((GROUP_FAIL + 1))
  else
    echo "  PASS  $req: $desc"
    GROUP_PASS=$((GROUP_PASS + 1))
  fi
}

# --- GROUP 1: Core Router (REQ-01 to REQ-05) ---

group_start "GROUP 1: Core Router (REQ-01 to REQ-05)"

# REQ-01: State detection table
check "REQ-01" "vibe.md contains planning_dir_exists" grep -q "planning_dir_exists" "$VIBE"
check "REQ-01" "vibe.md contains phase_count=0" grep -q "phase_count=0" "$VIBE"
check "REQ-01" "vibe.md contains next_phase_state" grep -q "next_phase_state" "$VIBE"

# REQ-02: NL intent parsing section
check "REQ-02" "vibe.md has Natural language intent section" grep -q "Natural language intent" "$VIBE"
check "REQ-02" "vibe.md has interpret user intent" grep -q "interpret user intent" "$VIBE"

# REQ-03: Flags map to modes
check "REQ-03" "vibe.md maps --plan to Plan mode" grep -q "\-\-plan.*Plan mode" "$VIBE"
check "REQ-03" "vibe.md maps --execute to Execute mode" grep -q "\-\-execute.*Execute mode" "$VIBE"
check "REQ-03" "vibe.md maps --discuss to Discuss mode" grep -q "\-\-discuss.*Discuss mode" "$VIBE"

# REQ-04: Confirmation gate via AskUserQuestion
check "REQ-04" "vibe.md references AskUserQuestion" grep -q "AskUserQuestion" "$VIBE"

# REQ-05: --yolo skip behavior
check "REQ-05" "vibe.md describes --yolo flag" grep -q "\-\-yolo" "$VIBE"
check "REQ-05" "vibe.md describes --yolo skipping confirmations" grep -q "skip.*confirmation" "$VIBE"

group_end "Core Router"

# --- GROUP 2: Mode Implementation (REQ-06 to REQ-15) ---

group_start "GROUP 2: Mode Implementation (REQ-06 to REQ-15)"

# All 11 mode headers
check "REQ-06" "Mode: Init Redirect header" grep -q "### Mode: Init Redirect" "$VIBE"
check "REQ-06" "Mode: Bootstrap header" grep -q "### Mode: Bootstrap" "$VIBE"
check "REQ-07" "Mode: Scope header" grep -q "### Mode: Scope" "$VIBE"
check "REQ-10" "Mode: Discuss header" grep -q "### Mode: Discuss" "$VIBE"
check "REQ-11" "Mode: Assumptions header" grep -q "### Mode: Assumptions" "$VIBE"
check "REQ-08" "Mode: Plan header" grep -q "### Mode: Plan" "$VIBE"
check "REQ-09" "Mode: Execute header" grep -q "### Mode: Execute" "$VIBE"
check "REQ-12" "Mode: Add Phase header" grep -q "### Mode: Add Phase" "$VIBE"
check "REQ-13" "Mode: Insert Phase header" grep -q "### Mode: Insert Phase" "$VIBE"
check "REQ-14" "Mode: Remove Phase header" grep -q "### Mode: Remove Phase" "$VIBE"
check "REQ-15" "Mode: Archive header" grep -q "### Mode: Archive" "$VIBE"

# REQ-06: Bootstrap mentions PROJECT.md
check "REQ-06" "Bootstrap references PROJECT.md" grep -q "PROJECT.md" "$VIBE"

# REQ-09: Execute mode references execute-protocol.md
check "REQ-09" "Execute mode references execute-protocol.md" grep -q "execute-protocol.md" "$VIBE"

# REQ-15: Archive mode contains audit checks
check "REQ-15" "Archive mode has audit matrix" grep -q "audit" "$VIBE"

group_end "Mode Implementation"

# --- GROUP 3: Execution Protocol (REQ-16, REQ-17) ---

group_start "GROUP 3: Execution Protocol (REQ-16, REQ-17)"

# REQ-16: execute-protocol.md in references/ (not commands/)
check "REQ-16" "execute-protocol.md exists in references/" test -f "$PROTOCOL"
check_absent "REQ-16" "execute-protocol.md NOT in commands/" tracked_repo_file_exists "commands/execute-protocol.md"

# REQ-16: No command frontmatter (no name: line)
check_absent "REQ-16" "execute-protocol.md has no name: frontmatter" grep -q "^name:" "$PROTOCOL"

# REQ-16: Contains Steps 2-5
check "REQ-16" "execute-protocol.md contains Step 2" grep -q "Step 2" "$PROTOCOL"
check "REQ-16" "execute-protocol.md contains Step 3" grep -q "Step 3" "$PROTOCOL"
check "REQ-16" "execute-protocol.md contains Step 4" grep -q "Step 4" "$PROTOCOL"
check "REQ-16" "execute-protocol.md contains Step 5" grep -q "Step 5" "$PROTOCOL"

# REQ-17: Execute mode uses conditional Read for protocol
check "REQ-17" "vibe.md Execute mode reads execute-protocol.md" grep -q "Read.*execute-protocol" "$VIBE"

group_end "Execution Protocol"

# --- GROUP 4: Command Surface (REQ-18 to REQ-20) ---

group_start "GROUP 4: Command Surface (REQ-18 to REQ-20)"

# REQ-18: 9 absorbed commands do NOT exist
ABSORBED=(implement plan execute assumptions add-phase insert-phase remove-phase archive audit)
for cmd in "${ABSORBED[@]}"; do
  check_absent "REQ-18" "commands/${cmd}.md does not exist" tracked_repo_file_exists "commands/${cmd}.md"
done

# REQ-18: Exact tracked file count (ignore ignored/untracked local command artifacts)
CMD_COUNT=$(tracked_markdown_count 'commands/*.md')
check "REQ-18" "commands/ has exactly 25 .md files (found $CMD_COUNT)" test "$CMD_COUNT" -eq 25

# REQ-20: No stale "29 commands" in key files
check_absent "REQ-20" "README.md has no '29 commands'" grep -q "29 commands" "$README"
check_absent "REQ-20" "marketplace.json has no '29 commands'" grep -q "29 commands" "$MKT_ROOT"
check_absent "REQ-20" ".claude-plugin/marketplace.json has no '29 commands'" grep -q "29 commands" "$MKT_PLUGIN"

# REQ-20: No /vbw:implement in key files
check_absent "REQ-20" "suggest-next.sh has no /vbw:implement" grep -q "/vbw:implement" "$SUGGEST"
check_absent "REQ-20" "help.md has no /vbw:implement" grep -q "/vbw:implement" "$HELP"
check_absent "REQ-20" "README.md has no /vbw:implement" grep -q "/vbw:implement" "$README"
check_absent "REQ-20" "CLAUDE.md has no /vbw:implement" grep -q "/vbw:implement" "$CLAUDE_MD"

# REQ-20: Positive checks — key files reference /vbw:vibe
check "REQ-20" "suggest-next.sh references /vbw:vibe" grep -q "/vbw:vibe" "$SUGGEST"

group_end "Command Surface"

# --- GROUP 5: NL Parsing (REQ-21, REQ-22) ---

group_start "GROUP 5: NL Parsing (REQ-21, REQ-22)"

# REQ-21: NL parsing is prompt-only (no regex, no import)
check_absent "REQ-21" "vibe.md has no regex patterns" grep -q "regex" "$VIBE"
check_absent "REQ-21" "vibe.md has no import statements" grep -q "^import " "$VIBE"
check "REQ-21" "vibe.md has keyword-based intent matching" grep -q "keywords" "$VIBE"

# REQ-22: Ambiguous intents handled
check "REQ-22" "vibe.md handles ambiguous intents" grep -q "Ambiguous" "$VIBE"
check "REQ-22" "vibe.md routes ambiguity to contextual AskUserQuestion flow" grep -q "Ambiguous -> AskUserQuestion with contextual options" "$VIBE"

group_end "NL Parsing"

# --- GROUP 6: Flags (REQ-23 to REQ-25) ---

group_start "GROUP 6: Flags (REQ-23 to REQ-25)"

# REQ-23: Count unique mode flags (should be >= 9)
FLAG_COUNT=$(grep -c "^\- \`--" "$VIBE" || true)
check "REQ-23" "vibe.md has >= 9 mode flags (found $FLAG_COUNT)" test "$FLAG_COUNT" -ge 9

# REQ-24: Behavior modifiers present
check "REQ-24" "vibe.md has --effort modifier" grep -q "\-\-effort" "$VIBE"
check "REQ-24" "vibe.md has --skip-qa modifier" grep -q "\-\-skip-qa" "$VIBE"
check "REQ-24" "vibe.md has --skip-audit modifier" grep -q "\-\-skip-audit" "$VIBE"
check "REQ-24" "vibe.md has --plan=NN modifier" grep -q "\-\-plan=NN" "$VIBE"

# REQ-25: Bare integer support
check "REQ-25" "vibe.md documents bare integer support" grep -qi "bare integer" "$VIBE"
check "REQ-25" "vibe.md bare integer targets phase N" grep -q "phase N" "$VIBE"

group_end "Flags"

# --- Summary ---

echo ""
echo "==============================="
echo "  TOTAL: $TOTAL_PASS PASS, $TOTAL_FAIL FAIL"
echo "==============================="

if [ "$TOTAL_FAIL" -eq 0 ]; then
  echo "  All checks passed."
  exit 0
else
  echo "  Some checks failed."
  exit 1
fi

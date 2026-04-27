#!/usr/bin/env bash
set -euo pipefail

# verify-askuserquestion-contract.sh — Contract checks for AskUserQuestion usage
#
# The Claude Code AskUserQuestion tool has a maxItems:4 constraint on its
# `options` array. Commands that need more than 4 choices must use a
# numbered-list-in-question-text workaround with explicit guard language.
#
# This verifier also protects the shared VBW interactive prompt pattern:
# centralized AskUserQuestion guidance, local-vs-shared `/vbw:vibe`
# boundaries, intentional freeform/plain-text handoffs, and stable
# structured-vs-freeform command boundaries.
#
# Checks:
# 1. No option lists with >4 items in AskUserQuestion context (pipe-delimited
#    or JSON array format)
# 2. Numbered-list AskUserQuestion workarounds include guard language
# 3. Shared interactive prompt reference has stable semantic anchors
# 4. Command consumers preserve their structured/freeform boundaries

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMANDS_DIR="$ROOT/commands"
REFERENCES_DIR="$ROOT/references"

ASK_USER_QUESTION_REF="$REFERENCES_DIR/ask-user-question.md"
VIBE_COMMAND_FILE="$COMMANDS_DIR/vibe.md"
LIST_TODOS_COMMAND_FILE="$COMMANDS_DIR/list-todos.md"
CONFIG_COMMAND_FILE="$COMMANDS_DIR/config.md"
SKILLS_COMMAND_FILE="$COMMANDS_DIR/skills.md"

tracked_command_markdown_files() {
  local rel
  git -C "$ROOT" ls-files -- 'commands/*.md' 'internal/*.md' | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    printf '%s\n' "$ROOT/$rel"
  done
}

TRACKED_COMMAND_MARKDOWN_FILES=()
while IFS= read -r file; do
  [ -n "$file" ] || continue
  TRACKED_COMMAND_MARKDOWN_FILES+=("$file")
done < <(tracked_command_markdown_files)

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

# Extract body after YAML frontmatter (everything after second ---)
extract_body() {
  local file="$1"
  awk '
    BEGIN { delim=0 }
    /^---$/ && delim < 2 { delim++; next }
    delim >= 2 { print }
  ' "$file"
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

extract_heading_block() {
  local file="$1"
  local heading="$2"
  local end_regex="$3"

  awk -v h="$heading" -v end_re="$end_regex" '
    function trim_line(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }

    {
      line=$0
      gsub(/\r/, "", line)
      trimmed=trim_line(line)

      if (trimmed == h) {
        found=1
        print line
        next
      }

      if (found && trimmed ~ end_re) {
        exit
      }

      if (found) {
        print line
      }
    }
  ' "$file"
}

extract_regex_block() {
  local file="$1"
  local start_regex="$2"
  local end_regex="$3"

  awk -v start_re="$start_regex" -v end_re="$end_regex" '
    $0 ~ start_re {
      found=1
      print
      next
    }

    found && $0 ~ end_re {
      exit
    }

    found {
      print
    }
  ' "$file"
}

count_text_occurrences() {
  local text="$1"
  local needle="$2"

  awk -v needle="$needle" '
    BEGIN { count=0 }

    {
      line=$0
      while (needle != "" && (idx = index(line, needle)) > 0) {
        count++
        line = substr(line, idx + length(needle))
      }
    }

    END { print count + 0 }
  ' <<< "$text"
}

require_file_exists() {
  local desc="$1"
  local file="$2"

  if [ -f "$file" ]; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

require_file_literal() {
  local desc="$1"
  local needle="$2"
  local file="$3"

  if [ -f "$file" ] && grep -Fq -- "$needle" "$file"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

require_file_regex() {
  local desc="$1"
  local pattern="$2"
  local file="$3"

  if [ -f "$file" ] && grep -Eq -- "$pattern" "$file"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

forbid_file_regex() {
  local desc="$1"
  local pattern="$2"
  local file="$3"

  if [ -f "$file" ] && grep -Eiq -- "$pattern" "$file"; then
    fail "$desc"
  else
    pass "$desc"
  fi
}

require_text_literal() {
  local desc="$1"
  local needle="$2"
  local text="$3"

  if grep -Fq -- "$needle" <<< "$text"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

require_text_regex() {
  local desc="$1"
  local pattern="$2"
  local text="$3"

  if grep -Eq -- "$pattern" <<< "$text"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

forbid_text_regex() {
  local desc="$1"
  local pattern="$2"
  local text="$3"

  if grep -Eiq -- "$pattern" <<< "$text"; then
    fail "$desc"
  else
    pass "$desc"
  fi
}

require_text_occurrence_count() {
  local desc="$1"
  local text="$2"
  local needle="$3"
  local expected_count="$4"
  local actual_count=""

  actual_count="$(count_text_occurrences "$text" "$needle")"
  if [ "$actual_count" -eq "$expected_count" ]; then
    pass "$desc"
  else
    fail "$desc (expected $expected_count, found $actual_count)"
  fi
}

echo "=== AskUserQuestion Contract Verification ==="

# --------------------------------------------------------------------------
# Check 1: No pipe-delimited option lists exceeding 4 items
#
# Scans for lines matching: "something" | "something" | ... (quoted strings
# separated by pipes). If a single line has >4 pipe-separated quoted items,
# it violates the maxItems:4 constraint.
#
# Exclusions: fenced code blocks, markdown table rows (lines starting with |)
# --------------------------------------------------------------------------

echo ""
echo "--- Check 1: No >4 option lists ---"

for file in "${TRACKED_COMMAND_MARKDOWN_FILES[@]}"; do
  base="$(basename "$file" .md)"

  # Count lines with >4 options in either format (outside code fences):
  # - Pipe-delimited: "a" | "b" | "c" | "d" | "e"
  # - JSON array:     Options: ["a", "b", "c", "d", "e"]
  violations=$(extract_body "$file" | awk '
    /^```/ { in_fence = !in_fence; next }
    in_fence { next }
    /^\|/ { next }  # skip markdown table rows

    {
      # Check 1a: pipe-separated quoted segments: "..." | "..."
      n = split($0, parts, /\|/)
      quoted_count = 0
      for (i = 1; i <= n; i++) {
        if (parts[i] ~ /"[^"]*"/) {
          quoted_count++
        }
      }
      if (quoted_count > 4) {
        print NR ": " $0
        next
      }

      # Check 1b: JSON array options: Options: ["...", "...", ...]
      if ($0 ~ /Options:[[:space:]]*\[/) {
        # Extract content between [ and ]
        arr = $0
        sub(/.*Options:[[:space:]]*\[/, "", arr)
        sub(/\].*/, "", arr)
        # Count comma-separated quoted items
        m = split(arr, items, /,/)
        arr_count = 0
        for (j = 1; j <= m; j++) {
          if (items[j] ~ /"[^"]*"/) {
            arr_count++
          }
        }
        if (arr_count > 4) {
          print NR ": " $0
        }
      }
    }
  ')

  if [ -n "$violations" ]; then
    while IFS= read -r violation; do
      fail "$base: >4 options (line $violation)"
    done <<<"$violations"
  else
    pass "$base: no >4 option lists"
  fi
done

# --------------------------------------------------------------------------
# Check 2: Numbered-list AskUserQuestion workarounds include guard language
#
# When a command instructs the LLM to "present ... as a numbered list in the
# AskUserQuestion text", it should also include guard language like:
# "do NOT use `options` array" or "no `options` array"
#
# This prevents future editors from removing the guard while keeping the
# numbered-list pattern, which could lead to the LLM using an options array
# with >4 items.
# --------------------------------------------------------------------------

echo ""
echo "--- Check 2: Numbered-list workarounds include guard language ---"

for file in "${TRACKED_COMMAND_MARKDOWN_FILES[@]}"; do
  base="$(basename "$file" .md)"

  body=$(extract_body "$file")

  # Check if the command uses the numbered-list AskUserQuestion workaround pattern
  has_numbered_list_pattern=false
  if grep -Eqi 'numbered list.*AskUserQuestion|AskUserQuestion.*numbered list' <<< "$body"; then
    # Only trigger on lines that say to present choices as a numbered list
    # in the AskUserQuestion text (the workaround pattern)
    if grep -Eqi 'present.*(as a |as )numbered list.*(in|for).*AskUserQuestion|numbered list in the (AskUserQuestion|question) text' <<< "$body"; then
      has_numbered_list_pattern=true
    fi
  fi

  if [ "$has_numbered_list_pattern" = true ]; then
    # Verify guard language exists somewhere in the body
    if grep -Eqi 'do NOT use.*options.*array|no.*options.*array' <<< "$body"; then
      pass "$base: numbered-list workaround has guard language"
    else
      fail "$base: uses numbered-list AskUserQuestion workaround but missing guard language (e.g., 'do NOT use \`options\` array')"
    fi
  fi
done

# --------------------------------------------------------------------------
# Check 3: Shared reference semantic anchors
# --------------------------------------------------------------------------

echo ""
echo "--- Check 3: Shared AskUserQuestion reference anchors ---"

require_file_exists "ask-user-question: shared reference exists" "$ASK_USER_QUESTION_REF"
require_file_literal "ask-user-question: source note metadata present" "Source note:" "$ASK_USER_QUESTION_REF"
require_file_literal "ask-user-question: last reviewed metadata present" "Last reviewed:" "$ASK_USER_QUESTION_REF"
require_file_literal "ask-user-question: documents short-header guidance" "Keep headers short" "$ASK_USER_QUESTION_REF"
require_file_regex "ask-user-question: documents 2-4 option sweet spot" '2[-–]4 options' "$ASK_USER_QUESTION_REF"
require_file_regex "ask-user-question: documents 1-4 question guidance" '1[-–]4 questions' "$ASK_USER_QUESTION_REF"
require_file_literal "ask-user-question: documents built-in Other path" '`Other` path' "$ASK_USER_QUESTION_REF"
require_file_literal "ask-user-question: documents intentional freeform boundary" "high-cardinality or unbounded" "$ASK_USER_QUESTION_REF"
require_file_literal "ask-user-question: documents freeform handoff heading" "### Freeform handoff" "$ASK_USER_QUESTION_REF"
require_file_literal "ask-user-question: documents freeform handoff behavior" "stop using AskUserQuestion" "$ASK_USER_QUESTION_REF"
require_file_literal "ask-user-question: documents fake bounded menu anti-pattern" "Fake bounded menus" "$ASK_USER_QUESTION_REF"
require_file_literal "ask-user-question: includes structured example" "### Example — structured single-select" "$ASK_USER_QUESTION_REF"
require_file_literal "ask-user-question: includes intentional-freeform example" "### Example — intentional freeform" "$ASK_USER_QUESTION_REF"
require_file_literal "ask-user-question: includes decision-gate example" "### Example — decision gate" "$ASK_USER_QUESTION_REF"
forbid_file_regex "ask-user-question: no volatile upstream issue links" 'github\.com/.*issues|fixes #[0-9]+|see #[0-9]+|issue #[0-9]+|parent.*#[0-9]+' "$ASK_USER_QUESTION_REF"

# --------------------------------------------------------------------------
# Check 4: /vbw:vibe local-vs-shared confirmation boundary
# --------------------------------------------------------------------------

echo ""
echo "--- Check 4: /vbw:vibe confirmation boundary ---"

VIBE_CONFIRMATION_BLOCK="$(extract_heading_block "$VIBE_COMMAND_FILE" "### Confirmation Gate" '^## ' || true)"

require_file_literal "vibe: loads shared AskUserQuestion reference" '@${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md' "$VIBE_COMMAND_FILE"

if [ -n "$VIBE_CONFIRMATION_BLOCK" ]; then
  pass "vibe: confirmation gate block extracted"
else
  fail "vibe: confirmation gate block extracted"
fi

require_text_literal "vibe: confirmation gate points to shared reference" "references/ask-user-question.md" "$VIBE_CONFIRMATION_BLOCK"

if grep -Fq '**Exception:** `--yolo` skips all confirmation gates.' <<< "$VIBE_CONFIRMATION_BLOCK" \
  && grep -Fq '**Exception:** Flags skip confirmation (explicit intent).' <<< "$VIBE_CONFIRMATION_BLOCK" \
  && grep -Fq '| Routing state | Recommended | Alternatives |' <<< "$VIBE_CONFIRMATION_BLOCK" \
  && grep -Fq '**Discussion-aware alternatives:**' <<< "$VIBE_CONFIRMATION_BLOCK"; then
  pass "vibe: confirmation gate preserves vibe-local routing constructs"
else
  fail "vibe: confirmation gate preserves vibe-local routing constructs"
fi

if grep -Eq '2[-–]4 options|1[-–]4 questions|high-cardinality' <<< "$VIBE_CONFIRMATION_BLOCK" \
  || grep -Fq '`Other` path' <<< "$VIBE_CONFIRMATION_BLOCK" \
  || grep -Fq 'Keep headers short' <<< "$VIBE_CONFIRMATION_BLOCK" \
  || grep -Fq 'dialog obscures' <<< "$VIBE_CONFIRMATION_BLOCK" \
  || grep -Fq 'For simple yes/no confirmations without a table entry' <<< "$VIBE_CONFIRMATION_BLOCK" \
  || grep -Fq '**AskUserQuestion parameters:**' <<< "$VIBE_CONFIRMATION_BLOCK"; then
  fail "vibe: confirmation gate does not duplicate generic AskUserQuestion guidance"
else
  pass "vibe: confirmation gate does not duplicate generic AskUserQuestion guidance"
fi

# --------------------------------------------------------------------------
# Check 5: /vbw:list-todos intentional plain-text/freeform handoff
# --------------------------------------------------------------------------

echo ""
echo "--- Check 5: /vbw:list-todos freeform boundary ---"

LIST_TODOS_FRONTMATTER="$(extract_frontmatter "$LIST_TODOS_COMMAND_FILE" || true)"
LIST_TODOS_STEP_5="$(extract_regex_block "$LIST_TODOS_COMMAND_FILE" 'Display action hints and STOP' '^## ' || true)"

if grep -Fq 'AskUserQuestion' <<< "$LIST_TODOS_FRONTMATTER"; then
  fail "list-todos: frontmatter allowed-tools excludes AskUserQuestion"
else
  pass "list-todos: frontmatter allowed-tools excludes AskUserQuestion"
fi

if grep -Fq 'AskUserQuestion' <<< "$(extract_body "$LIST_TODOS_COMMAND_FILE")"; then
  fail "list-todos: body does not use AskUserQuestion"
else
  pass "list-todos: body does not use AskUserQuestion"
fi

require_text_regex "list-todos: displays action hints and stops without prompting" 'Display action hints and STOP.*Do NOT prompt the user for input' "$LIST_TODOS_STEP_5"
require_text_literal "list-todos: unfiltered hints preserve /vbw:vibe N" "/vbw:vibe N" "$LIST_TODOS_STEP_5"
require_text_literal "list-todos: unfiltered hints preserve /vbw:fix N" "/vbw:fix N" "$LIST_TODOS_STEP_5"
require_text_literal "list-todos: unfiltered hints preserve /vbw:debug N" "/vbw:debug N" "$LIST_TODOS_STEP_5"
require_text_literal "list-todos: unfiltered hints preserve remove N" "remove N         — delete from todo list" "$LIST_TODOS_STEP_5"
require_text_literal "list-todos: filtered hints preserve remove N" "remove N         — delete from this displayed list" "$LIST_TODOS_STEP_5"
require_text_literal "list-todos: filtered hints preserve delete N" "delete N         — same as remove N" "$LIST_TODOS_STEP_5"
require_text_literal "list-todos: filtered hints preserve rerun-unfiltered guard" "rerun unfiltered /vbw:list-todos before using /vbw:vibe N, /vbw:fix N, or /vbw:debug N" "$LIST_TODOS_STEP_5"

# --------------------------------------------------------------------------
# Check 6: /vbw:config bounded structured flow
# --------------------------------------------------------------------------

echo ""
echo "--- Check 6: /vbw:config structured boundary ---"

CONFIG_NO_ARGS_BLOCK="$(extract_heading_block "$CONFIG_COMMAND_FILE" "### No arguments: Interactive configuration" '^### ' || true)"
CONFIG_STEP_2="$(extract_regex_block "$CONFIG_COMMAND_FILE" 'Step 2:.*AskUserQuestion with 1 question' 'Step 2\.5:' || true)"

if [ -n "$CONFIG_NO_ARGS_BLOCK" ]; then
  pass "config: no-args interactive configuration block extracted"
else
  fail "config: no-args interactive configuration block extracted"
fi

require_text_occurrence_count "config: Step 2 uses exactly one AskUserQuestion prompt definition" "$CONFIG_STEP_2" "AskUserQuestion with 1 question:" 1
require_text_literal "config: bounded branches acknowledge built-in Other path" 'the built-in `Other` path is still part of that question' "$CONFIG_NO_ARGS_BLOCK"
require_text_literal "config: bounded branches do not add visible Other option" 'do NOT add an extra visible `Other` option' "$CONFIG_NO_ARGS_BLOCK"

if grep -Fq 'Which core setting do you want to change?' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`Effort` — current:' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`Autonomy` — current:' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`Planning tracking` — current:' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`Auto push` — current:' <<< "$CONFIG_NO_ARGS_BLOCK"; then
  pass "config: core setting selection remains bounded"
else
  fail "config: core setting selection remains bounded"
fi

if grep -Fq '`thorough` — Maximum planning and verification depth' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`balanced` — Default depth for most work' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`fast` — Lighter planning, quicker verification' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`turbo` — Minimal ceremony, fastest path' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`cautious` — Confirm more often' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`standard` — Default phase-by-phase flow' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`confident` — Fewer confirmations' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`pure-vibe` — Full auto loop through phases' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`manual` — Leave planning files for manual git handling' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`ignore` — Keep `.vbw-planning/` out of git' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`commit` — Auto-commit planning artifacts' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`never` — Never push automatically' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`after_phase` — Push once after each phase' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`always` — Push after every commit' <<< "$CONFIG_NO_ARGS_BLOCK"; then
  pass "config: core values remain 3-4 option bounded choices"
else
  fail "config: core values remain 3-4 option bounded choices"
fi

if grep -Fq 'How do you want to configure model behavior?' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`Use preset profile` — quality, balanced, or budget' <<< "$CONFIG_NO_ARGS_BLOCK" \
  && grep -Fq '`Configure each agent individually` — 6 per-agent model questions' <<< "$CONFIG_NO_ARGS_BLOCK"; then
  pass "config: model profile method remains a 2-option branch"
else
  fail "config: model profile method remains a 2-option branch"
fi

require_text_literal "config: preset profile branch remains 3 options" 'AskUserQuestion with 1 question and 3 options (`quality`, `balanced`, `budget`)' "$CONFIG_NO_ARGS_BLOCK"
require_text_literal "config: per-agent overrides keep 4-question first round" "AskUserQuestion with 4 questions:" "$CONFIG_NO_ARGS_BLOCK"
require_text_literal "config: per-agent overrides keep 2-question second round" "AskUserQuestion with 2 questions:" "$CONFIG_NO_ARGS_BLOCK"
forbid_text_regex "config: no-args flow avoids numeric pseudo-menu language" 'enter numbers|comma-separated|numbered list' "$CONFIG_NO_ARGS_BLOCK"

# --------------------------------------------------------------------------
# Check 7: /vbw:skills structured-vs-freeform boundary
# --------------------------------------------------------------------------

echo ""
echo "--- Check 7: /vbw:skills structured/freeform boundary ---"

SKILLS_STEP_5="$(extract_regex_block "$SKILLS_COMMAND_FILE" '^### Step 5: Offer installation$' '^### ' || true)"

if [ -n "$SKILLS_STEP_5" ]; then
  pass "skills: Step 5 block extracted"
else
  fail "skills: Step 5 block extracted"
fi

require_text_literal "skills: empty candidate list stops without AskUserQuestion" "If the combined list is empty: STOP here. Do NOT AskUserQuestion." "$SKILLS_STEP_5"
require_text_literal "skills: one candidate uses structured single bounded question" "If the combined list has exactly 1 candidate: keep it structured." "$SKILLS_STEP_5"
require_text_literal "skills: one candidate asks a single bounded question" "AskUserQuestion with a single bounded question." "$SKILLS_STEP_5"
require_text_regex "skills: 2-4 candidates stay structured" 'If the combined list has 2[-–]4 candidates: keep it structured' "$SKILLS_STEP_5"
require_text_regex "skills: 2-4 candidates use per-skill AskUserQuestion prompts" 'Use AskUserQuestion with 1 question per skill \(2[-–]4 questions total\)' "$SKILLS_STEP_5"
require_text_literal "skills: bounded branches acknowledge built-in Other path" 'the built-in `Other` path is still part of that question' "$SKILLS_STEP_5"
require_text_literal "skills: bounded branches accept hybrid number replies" 'accept hybrid replies anchored to one of those visible option numbers' "$SKILLS_STEP_5"
require_text_literal "skills: no-selection stops before installation scope" 'Do not ask Step 5b and do not enter Step 6.' "$SKILLS_STEP_5"
require_text_literal "skills: 5+ candidates use intentional high-cardinality freeform" "If the combined list has more than 4 candidates: use intentional high-cardinality freeform input." "$SKILLS_STEP_5"
require_text_literal "skills: 5+ candidate branch forbids options array" 'do NOT use `options` array' "$SKILLS_STEP_5"
require_text_literal "skills: 5+ candidate branch explains numeric/freeform boundary" "This list is larger than the 2–4 structured-choice sweet spot, so use numeric/freeform selection here." "$SKILLS_STEP_5"

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All AskUserQuestion contract checks passed."
exit 0

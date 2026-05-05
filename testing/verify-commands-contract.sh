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

tracked_command_markdown_files() {
  local rel
  git -C "$ROOT" ls-files -- 'commands/*.md' 'internal/*.md' | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    printf '%s\n' "$ROOT/$rel"
  done
}

tracked_active_scan_files() {
  local rel
  git -C "$ROOT" ls-files -- scripts references agents templates \
    | awk -F/ '($1 == "scripts" || $1 == "references" || $1 == "agents" || $1 == "templates") && NF <= 3 && ($NF ~ /\.sh$/ || $NF ~ /\.md$/) { print }' \
    | while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      printf '%s\n' "$ROOT/$rel"
    done
}

TRACKED_COMMAND_MARKDOWN_FILES=()
while IFS= read -r file; do
  [ -n "$file" ] || continue
  TRACKED_COMMAND_MARKDOWN_FILES+=("$file")
done < <(tracked_command_markdown_files)

TRACKED_ACTIVE_SCAN_FILES=()
while IFS= read -r file; do
  [ -n "$file" ] || continue
  TRACKED_ACTIVE_SCAN_FILES+=("$file")
done < <(tracked_active_scan_files)

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

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

normalize_block_whitespace() {
  tr '\r\n\t' '   ' | awk '
    {
      gsub(/[[:space:]]+/, " ")
      sub(/^ /, "")
      sub(/ $/, "")
      print
    }
  '
}

contains_literal() {
  local haystack="$1"
  local needle="$2"

  grep -Fq -- "$needle" <<< "$haystack"
}

frontmatter_first_scalar() {
  local frontmatter="$1"
  local field="$2"

  awk -v field="$field" '
    BEGIN {
      pattern = "^" field ":[[:space:]]*"
    }

    $0 ~ pattern && first == "" {
      line = $0
      sub(pattern, "", line)
      first = line
    }

    END {
      if (first != "") print first
    }
  ' <<< "$frontmatter"
}

frontmatter_first_scalar_from_file() {
  local file="$1"
  local field="$2"
  local frontmatter=""

  frontmatter="$(extract_frontmatter "$file")"
  frontmatter_first_scalar "$frontmatter" "$field"
}

frontmatter_continuation_lines() {
  local frontmatter="$1"
  local field="$2"

  awk -v field="$field" '
    BEGIN {
      pattern = "^" field ":"
    }

    $0 ~ pattern {
      collecting = 1
      next
    }

    collecting && /^[[:space:]]/ {
      print
      next
    }

    collecting {
      collecting = 0
    }
  ' <<< "$frontmatter"
}

first_matching_line_number() {
  local text="$1"
  local needle="$2"

  awk -v needle="$needle" '
    index($0, needle) && first == 0 {
      first = NR
    }

    END {
      if (first > 0) print first
    }
  ' <<< "$text"
}

first_matching_regex_line_number() {
  local text="$1"
  local regex="$2"

  awk -v regex="$regex" '
    $0 ~ regex && first == 0 {
      first = NR
    }

    END {
      if (first > 0) print first
    }
  ' <<< "$text"
}

check_literal_before_literal() {
  local label="$1"
  local text="$2"
  local before="$3"
  local after="$4"
  local before_line after_line

  before_line=$(first_matching_line_number "$text" "$before")
  after_line=$(first_matching_line_number "$text" "$after")

  if [ -n "$before_line" ] && [ -n "$after_line" ] && [ "$before_line" -lt "$after_line" ]; then
    pass "$label"
  else
    fail "$label"
  fi
}

check_literal_before_regex() {
  local label="$1"
  local text="$2"
  local before="$3"
  local after_regex="$4"
  local before_line after_line

  before_line=$(first_matching_line_number "$text" "$before")
  after_line=$(first_matching_regex_line_number "$text" "$after_regex")

  if [ -n "$before_line" ] && [ -n "$after_line" ] && [ "$before_line" -lt "$after_line" ]; then
    pass "$label"
  else
    fail "$label"
  fi
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

block_contains_normalized() {
  local block="$1"
  local expected="$2"
  local normalized_block=""
  local normalized_expected=""

  normalized_block=$(printf '%s' "$block" | normalize_block_whitespace)
  normalized_expected=$(printf '%s' "$expected" | normalize_block_whitespace)
  [ -n "$normalized_expected" ] || return 1

  contains_literal "$normalized_block" "$normalized_expected"
}

has_allowed_tool() {
  local allowed="$1"
  local target="$2"

  printf '%s' "$allowed" | awk -v RS=',' -v target="$target" '
    {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      if ($0 == target) found=1
    }
    END { exit(found ? 0 : 1) }
  '
}

first_trigger_line() {
  local file="$1"
  local positive_regex="$2"
  local negative_regex="${3:-}"

  awk -v pos="$positive_regex" -v neg="$negative_regex" '
    BEGIN { IGNORECASE=1; delim=0 }
    /^---$/ { delim++; next }
    delim < 2 { next }
    $0 ~ pos && (neg == "" || $0 !~ neg) { print; exit }
  ' "$file"
}

check_allowed_tool_match() {
  local base="$1"
  local allowed="$2"
  local file="$3"
  local tool="$4"
  local positive_regex="$5"
  local negative_regex="${6:-}"
  local trigger=""
  local snippet=""

  trigger=$(first_trigger_line "$file" "$positive_regex" "$negative_regex" || true)
  [ -n "$trigger" ] || return 0

  if has_allowed_tool "$allowed" "$tool"; then
    pass "$base: $tool in body matches allowed-tools"
    return 0
  fi

  snippet=$(trim "$trigger")
  snippet="${snippet//$'\t'/ }"
  snippet="${snippet//$'\r'/ }"
  if [ ${#snippet} -gt 140 ]; then
    snippet="${snippet:0:137}..."
  fi

  fail "$base: body references $tool but allowed-tools does not include it (trigger: $snippet)"
}

echo "=== Command Contract Verification ==="

# Scan both commands/ (consumer-facing) and internal/ (maintainer-only)
for file in "${TRACKED_COMMAND_MARKDOWN_FILES[@]}"; do
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

  NAME_VALUE="$(frontmatter_first_scalar "$FRONTMATTER" "name")"
  # Strip vbw: prefix if present — plugin auto-prefixes the namespace
  NAME_STEM="${NAME_VALUE#vbw:}"

  if [ -z "$NAME_VALUE" ]; then
    fail "$base: missing name field"
  elif [ "$NAME_STEM" != "$base" ]; then
    fail "$base: name mismatch (expected '$base', got '$NAME_VALUE')"
  else
    pass "$base: name matches filename"
  fi

  if ! grep -q '^allowed-tools:' <<< "$FRONTMATTER"; then
    fail "$base: missing allowed-tools field"
  else
    pass "$base: allowed-tools present"
  fi

  DESC_COUNT="$(printf '%s\n' "$FRONTMATTER" | grep -c '^description:')"
  if [ "$DESC_COUNT" -ne 1 ]; then
    fail "$base: description field missing or duplicated"
    continue
  fi

  DESC_VALUE="$(frontmatter_first_scalar "$FRONTMATTER" "description")"
  if [ -z "$DESC_VALUE" ]; then
    fail "$base: description is empty"
  elif [[ "$DESC_VALUE" == \|* || "$DESC_VALUE" == \>* ]]; then
    fail "$base: description must be single-line (block scalar found)"
  else
    AFTER_DESC="$(frontmatter_continuation_lines "$FRONTMATTER" "description")"
    if [ -n "$AFTER_DESC" ]; then
      fail "$base: description has continuation lines"
    else
      pass "$base: description is single-line"
    fi
  fi
done

echo ""
echo "=== AskUserQuestion Contract Verification ==="

ASK_USER_QUESTION_REF="$ROOT/references/ask-user-question.md"
VIBE_COMMAND_FILE="$COMMANDS_DIR/vibe.md"
VIBE_CONFIRMATION_BLOCK="$(extract_heading_block "$VIBE_COMMAND_FILE" "### Confirmation Gate" '^## ' || true)"

if [ -f "$ASK_USER_QUESTION_REF" ]; then
  pass "ask-user-question: shared reference exists"
else
  fail "ask-user-question: shared reference missing"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Fq 'Source note:' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: source note present"
else
  fail "ask-user-question: missing source note"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Fq 'Last reviewed:' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: last reviewed metadata present"
else
  fail "ask-user-question: missing last reviewed metadata"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Fq 'Keep headers short' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: documents short-header rule"
else
  fail "ask-user-question: missing short-header rule"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Eq '2[-–]4 options' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: documents 2-4 option sweet spot"
else
  fail "ask-user-question: missing 2-4 option guidance"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Eq '1[-–]4 questions' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: documents 1-4 question guidance"
else
  fail "ask-user-question: missing 1-4 question guidance"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Fq '`Other` path' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: documents built-in Other path"
else
  fail "ask-user-question: missing built-in Other path guidance"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Fq 'high-cardinality or unbounded' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: documents intentional freeform boundary"
else
  fail "ask-user-question: missing intentional freeform boundary"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Fq '### Example — structured single-select' "$ASK_USER_QUESTION_REF" \
  && grep -Fq '### Example — intentional freeform' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: includes structured and freeform examples"
else
  fail "ask-user-question: missing structured/freeform example coverage"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Fq '### Freeform handoff' "$ASK_USER_QUESTION_REF" \
  && grep -Fq 'stop using AskUserQuestion' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: documents freeform handoff rule"
else
  fail "ask-user-question: missing freeform handoff rule"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Fq '## Anti-patterns' "$ASK_USER_QUESTION_REF" \
  && grep -Fq 'Fake bounded menus' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: includes anti-patterns section"
else
  fail "ask-user-question: missing anti-patterns section"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Fq '### Example — decision gate' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: includes decision gate example"
else
  fail "ask-user-question: missing decision gate example"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && ! grep -Eiq 'github\.com/.*issues|fixes #[0-9]+|see #[0-9]+|issue #[0-9]+|parent.*#[0-9]+' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: no volatile upstream issue links"
else
  fail "ask-user-question: contains volatile upstream issue links"
fi

if grep -Fq '@${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md' "$VIBE_COMMAND_FILE"; then
  pass "vibe: loads shared AskUserQuestion reference"
else
  fail "vibe: missing shared AskUserQuestion reference include"
fi

if [ -n "$VIBE_CONFIRMATION_BLOCK" ]; then
  pass "vibe: confirmation gate block extracted for boundary checks"
else
  fail "vibe: could not extract confirmation gate block"
fi

if grep -Fq 'references/ask-user-question.md' <<< "$VIBE_CONFIRMATION_BLOCK"; then
  pass "vibe: confirmation gate points to shared AskUserQuestion reference"
else
  fail "vibe: confirmation gate missing shared AskUserQuestion reference"
fi

if grep -Fq '**Exception:** `--yolo` skips all confirmation gates.' <<< "$VIBE_CONFIRMATION_BLOCK" \
  && grep -Fq '**Exception:** Flags skip confirmation (explicit intent).' <<< "$VIBE_CONFIRMATION_BLOCK" \
  && grep -Fq '| Routing state | Recommended | Alternatives |' <<< "$VIBE_CONFIRMATION_BLOCK" \
  && grep -Fq '**Discussion-aware alternatives:**' <<< "$VIBE_CONFIRMATION_BLOCK"; then
  pass "vibe: confirmation gate keeps vibe-local routing behavior"
else
  fail "vibe: confirmation gate lost vibe-local routing constructs"
fi

if grep -Eq '2[-–]4 options|1[-–]4 questions|freeform|high-cardinality' <<< "$VIBE_CONFIRMATION_BLOCK" \
  || grep -Fq '`Other` path' <<< "$VIBE_CONFIRMATION_BLOCK" \
  || grep -Fq 'Keep headers short' <<< "$VIBE_CONFIRMATION_BLOCK" \
  || grep -Fq 'dialog obscures' <<< "$VIBE_CONFIRMATION_BLOCK" \
  || grep -Fq 'For simple yes/no confirmations without a table entry' <<< "$VIBE_CONFIRMATION_BLOCK" \
  || grep -Fq '**AskUserQuestion parameters:**' <<< "$VIBE_CONFIRMATION_BLOCK"; then
  fail "vibe: confirmation gate still carries generic AskUserQuestion contract guidance"
else
  pass "vibe: confirmation gate keeps generic AskUserQuestion contract guidance out of vibe-local prose"
fi

echo ""
echo "=== skills.md Step 5 Verification ==="

SKILLS_FILE="$COMMANDS_DIR/skills.md"
if [ ! -f "$SKILLS_FILE" ]; then
  fail "skills: command file not found"
else
  skills_step_5="$({
    awk '
      /^### Step 5: Offer installation$/ { in_block=1; next }
      in_block && /^### / { exit }
      in_block { print }
    ' "$SKILLS_FILE"
  } || true)"

  if [ -z "$skills_step_5" ]; then
    fail "skills: missing Step 5 block"
  else
    if grep -Fq 'Combine curated + registry, deduplicate, rank (curated first).' <<< "$skills_step_5"; then
      pass "skills: Step 5 preserves curated-first ranking"
    else
      fail "skills: Step 5 missing curated-first ranking guidance"
    fi

    if grep -Fq 'If the combined list is empty: STOP here. Do NOT AskUserQuestion.' <<< "$skills_step_5"; then
      pass "skills: Step 5 stops immediately when no candidates exist"
    else
      fail "skills: Step 5 missing empty-list stop without AskUserQuestion"
    fi

    if grep -Fq 'If the combined list has exactly 1 candidate: keep it structured.' <<< "$skills_step_5" \
      && grep -Fq 'AskUserQuestion with a single bounded question.' <<< "$skills_step_5"; then
      pass "skills: Step 5 keeps single-candidate installs structured"
    else
      fail "skills: Step 5 missing structured single-candidate branch"
    fi

    if grep -Eq 'If the combined list has 2[-–]4 candidates: keep it structured' <<< "$skills_step_5" \
      && grep -Eq 'Use AskUserQuestion with 1 question per skill \(2[-–]4 questions total\)' <<< "$skills_step_5"; then
      pass "skills: Step 5 keeps bounded multi-candidate installs structured"
    else
      fail "skills: Step 5 missing structured 2-4 candidate branch"
    fi

    if grep -Fq 'For any bounded AskUserQuestion branch below that uses visible options, the built-in `Other` path is still part of that question:' <<< "$skills_step_5" \
      && grep -Fq 'accept unambiguous visible option-by-number replies (for example `#1` / `#2`)' <<< "$skills_step_5" \
      && grep -Fq 'accept hybrid replies anchored to one of those visible option numbers (for example `#2 for now`)' <<< "$skills_step_5" \
      && grep -Fq 're-ask only when the follow-up is ambiguous or invalid for that same question.' <<< "$skills_step_5"; then
      pass "skills: Step 5 bounded Other path accepts numbered and hybrid replies"
    else
      fail "skills: Step 5 missing bounded Other-path numbered/hybrid reply guidance"
    fi

    if grep -Fq 'If none were selected, display `○ No skills selected for installation.` and STOP here. Do not ask Step 5b and do not enter Step 6.' <<< "$skills_step_5"; then
      pass "skills: Step 5 skips scope selection when bounded structured branch declines everything"
    else
      fail "skills: Step 5 missing no-selection stop before Step 5b"
    fi

    if grep -Fq 'If the combined list has more than 4 candidates: use intentional high-cardinality freeform input.' <<< "$skills_step_5" \
      && grep -Fq 'do NOT use `options` array' <<< "$skills_step_5" \
      && grep -Eq 'larger than the 2[-–]4 structured-choice sweet spot' <<< "$skills_step_5"; then
      pass "skills: Step 5 keeps 5+ candidates on an intentional freeform path"
    else
      fail "skills: Step 5 missing explicit intentional freeform 5+ candidate branch"
    fi
  fi
fi

echo ""
echo "=== skills.md Step 5b Verification ==="

if [ ! -f "$SKILLS_FILE" ]; then
  fail "skills: command file not found"
else
  skills_step_5b="$({
    awk '
      /^### Step 5b: Choose installation scope$/ { in_block=1; next }
      in_block && /^### / { exit }
      in_block { print }
    ' "$SKILLS_FILE"
  } || true)"

  if [ -z "$skills_step_5b" ]; then
    fail "skills: missing Step 5b block"
  else
    if grep -Fq -- '- **Global** — "Installed to `<global_skills_dir>/`, available in all projects."' <<< "$skills_step_5b"; then
      pass "skills: Step 5b Global option uses <global_skills_dir>/ placeholder"
    else
      fail "skills: Step 5b Global option missing <global_skills_dir>/ placeholder"
    fi

    if grep -Fq 'Use the `global_skills_dir` value from the Stack detection Context JSON as the display path.' <<< "$skills_step_5b"; then
      pass "skills: Step 5b explains global_skills_dir display source"
    else
      fail "skills: Step 5b missing global_skills_dir Stack detection Context JSON guidance"
    fi

    if grep -Fq '~/.agents/skills/' <<< "$skills_step_5b"; then
      fail "skills: Step 5b still exposes ~/.agents/skills/ display path"
    else
      pass "skills: Step 5b does not expose ~/.agents/skills/ display path"
    fi
  fi
fi

echo ""
echo "=== Milestone Context Verification ==="

# Commands that reference milestone-scoped paths in their Steps section must have
# either:
# 1. The ACTIVE milestone shell interpolation in their Context section, OR
# 2. Bash in allowed-tools (so the agent can read ACTIVE at runtime)
# Without either, the agent has no way to discover the active milestone slug.
for file in "${TRACKED_COMMAND_MARKDOWN_FILES[@]}"; do
  base="$(basename "$file" .md)"

  # Extract body after frontmatter, excluding Context section (which contains the fix itself)
  body="$(awk '/^---$/{d++; next} d>=2' "$file")"
  body_no_context="$(printf '%s\n' "$body" | awk '/^## Context$/{skip=1; next} /^## /{skip=0} !skip')"

  # ACTIVE-file milestone indirection was removed (architecture simplification).
  # Commands should NOT reference .vbw-planning/ACTIVE anymore.
  if grep -qi '\.vbw-planning/ACTIVE' <<< "$body_no_context"; then
    fail "$base: references .vbw-planning/ACTIVE — milestone indirection was removed"
  else
    pass "$base: no stale ACTIVE file references"
  fi
done

echo ""
echo "=== Stale ACTIVE Reference Verification (scripts + references) ==="

# Scan scripts and references for any runtime usage of .vbw-planning/ACTIVE
# (session-start.sh is allowed — it only deletes the stale file)
for scan_file in "${TRACKED_ACTIVE_SCAN_FILES[@]}"; do
  rel_scan_file="${scan_file#$ROOT/}"
  dir_label="${rel_scan_file%%/*}"
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
QA_FILE="$COMMANDS_DIR/qa.md"
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

if grep -q 'Only proceed to UAT when the PASS is both gate-authoritative and fresh for the target phase' "$VERIFY_FILE"; then
  pass "verify: explicit QA gate requires gate-authoritative fresh PASS for target phase"
else
  fail "verify: missing gate-authoritative fresh-PASS requirement in explicit QA gate"
fi

if grep -q 'qa-result-gate\.sh' "$VERIFY_FILE" \
  && grep -q 'QA_GATE_ROUTING=' "$VERIFY_FILE" \
  && grep -q 'PROCEED_TO_UAT' "$VERIFY_FILE" \
  && grep -q 'QA_RERUN_REQUIRED' "$VERIFY_FILE" \
  && grep -q 'REMEDIATION_REQUIRED' "$VERIFY_FILE"; then
  pass "verify: standalone UAT honors deterministic QA gate before UAT"
else
  fail "verify: missing deterministic qa-result-gate enforcement before UAT"
fi

if grep -q 'KNOWN_ISSUES_STATUS=' "$VERIFY_FILE" \
  && grep -q 'KNOWN_ISSUES_STATUS=malformed' "$VERIFY_FILE" \
  && grep -q 'unreadable tracked known issues' "$VERIFY_FILE" \
  && grep -q 'unresolved tracked known issues' "$VERIFY_FILE"; then
  pass "verify: skip-qa guard blocks malformed known-issues registries"
else
  fail "verify: missing malformed known-issues fail-closed guard in skip-qa path"
fi

if grep -q 'sync-verification "\$PDIR" "\$VERIF_FILE"' "$VERIFY_FILE"; then
  pass "verify: restores known-issues registry from existing verification artifacts before gating"
else
  fail "verify: missing known-issues restore from existing verification artifact"
fi

if grep -q 'sync-verification "\$PDIR" "\$VERIF_FILE"' "$VERIFY_FILE" \
  && grep -q 'promote-todos "\$PDIR"' "$VERIFY_FILE"; then
  pass "verify: restore path re-promotes known issues into STATE.md todos after sync-verification"
else
  fail "verify: missing promote-todos after known-issues restore in verify recovery path"
fi

if grep -Eq 'qa-remediation-state\.sh"? advance' "$QA_FILE"; then
  pass "qa: round-scoped PROCEED_TO_UAT persists remediation advance"
else
  fail "qa: missing round-scoped qa-remediation-state advance before standalone QA success presentation"
fi

if grep -Eq 'qa-remediation-state\.sh"? needs-round' "$QA_FILE"; then
  pass "qa: round-scoped REMEDIATION_REQUIRED persists next-round state"
else
  fail "qa: missing round-scoped qa-remediation-state needs-round before standalone remediation handoff"
fi

if grep -q 'echo "verify_context=unavailable"' "$VIBE_FILE"; then
  pass "vibe: routed verify precompute emits fail-closed verify_context sentinel"
else
  fail "vibe: routed verify precompute missing fail-closed verify_context sentinel"
fi

if grep -q 'qa-remediation-state\.sh get-or-init {phase-dir}' "$VIBE_FILE" \
  && grep -q 'deterministic stage-less resume path' "$VIBE_FILE"; then
  pass "vibe: QA remediation resume self-initializes absent state"
else
  fail "vibe: missing qa-remediation-state get-or-init for stage-less QA remediation resume"
fi

if grep -q 'qa_reason' "$VIBE_FILE" \
  && grep -q 'qa_attention_reason' "$VIBE_FILE" \
  && grep -q 'missing_verification_artifact' "$VIBE_FILE" \
  && grep -q 'verified_at_commit_mismatch' "$VIBE_FILE" \
  && grep -q 'qa_gate_rerun_required' "$VIBE_FILE"; then
  pass "vibe: QA pending gate surfaces machine-readable phase-detect reasons"
else
  fail "vibe: QA pending gate missing machine-readable reason guidance"
fi

if grep -Fq 'QA is pending ({qa_reason})' "$VIBE_FILE"; then
  fail "vibe: QA pending table still displays raw qa_reason token"
else
  pass "vibe: QA pending table avoids raw qa_reason display token"
fi

if grep -Fq 'QA is pending ({reason label})' "$VIBE_FILE" \
  && grep -Fq 'Resolve `{reason label}` from `qa_reason`' "$VIBE_FILE"; then
  pass "vibe: QA pending table points to resolved reason-label mapping"
else
  fail "vibe: QA pending table missing resolved reason-label guidance"
fi

if grep -Fq -- 'qa_reason=none|<reason>' "$ROOT/references/phase-detection.md" \
  && grep -Fq -- 'qa_attention_reason=none|<reason>' "$ROOT/references/phase-detection.md" \
  && grep -Fq -- 'result:` is authoritative when present' "$ROOT/references/phase-detection.md" \
  && grep -Fq -- 'Legacy `status:` is accepted only when `result:` is absent' "$ROOT/references/phase-detection.md"; then
  pass "phase-detection: documents QA reason fields and legacy result precedence"
else
  fail "phase-detection: missing QA reason or legacy result documentation"
fi

if grep -q 'Read the active UAT artifact exactly once' "$VIBE_FILE" \
  && grep -q 'Do NOT shell out to `extract-uat-issues.sh` for active-phase routing' "$VIBE_FILE" \
  && grep -q 'Use `uat_file` from the pre-computed state when available' "$VIBE_FILE"; then
  pass "vibe: active UAT remediation reads the active UAT artifact directly from routing metadata"
else
  fail "vibe: active UAT remediation missing direct-read routing guidance"
fi

if grep -q 'UAT issues (remediation only):' "$VIBE_FILE" || grep -q '^---UAT_EXTRACT_START---$' "$VIBE_FILE"; then
  fail "vibe: active UAT remediation still includes the precomputed extraction block"
else
  pass "vibe: active UAT remediation no longer embeds an active extraction marker block"
fi

if grep -q 'compile-verify-context-for-uat\.sh' "$VERIFY_FILE"; then
  pass "verify: precomputed UAT context uses shared scope resolver"
else
  fail "verify: precomputed UAT context missing shared scope resolver"
fi

if grep -q 'compile-verify-context-for-uat\.sh' "$VIBE_FILE"; then
  pass "vibe: precomputed UAT context uses shared scope resolver"
else
  fail "vibe: precomputed UAT context missing shared scope resolver"
fi

if grep -q 'extract-uat-resume\.sh "{phase-dir}"' "$VIBE_FILE" \
  && grep -q 'remediation/uat/round-{RR}/R{RR}-UAT.md' "$VIBE_FILE" \
  && grep -q 'remediation/round-{RR}/R{RR}-UAT.md' "$VIBE_FILE"; then
  pass "vibe: needs_reverification refreshes and validates round-scoped uat_path for round-dir and legacy layouts"
else
  fail "vibe: needs_reverification missing refreshed round-scoped uat_path validation"
fi

if grep -q 'compile-verify-context.sh --remediation-only {phase-dir}' "$ROOT/references/execute-protocol.md"; then
  pass "execute-protocol: QA remediation verify uses remediation-only verify context"
else
  fail "execute-protocol: QA remediation verify missing remediation-only verify context"
fi

if grep -q 'verify the exception is documented with non-fixable justification and that the justification is credible for this FAIL' "$ROOT/references/execute-protocol.md" \
  && grep -q 'documentation alone is insufficient when the original FAIL still appears fixable via code or plan amendment' "$ROOT/references/execute-protocol.md"; then
  pass "execute-protocol: remediation QA rejects unjustified process-exception labels"
else
  fail "execute-protocol: remediation QA guidance still allows documentation-only process-exception loophole"
fi

if grep -q 'After QA persists VERIFICATION.md (and only after that), run the verification threshold gate' "$ROOT/references/execute-protocol.md"; then
  pass "execute-protocol: verification_threshold runs after QA persists VERIFICATION"
else
  fail "execute-protocol: verification_threshold ordering still appears before QA"
fi

if grep -q 'compile-verify-context.sh --remediation-only {phase-dir}' "$VIBE_FILE"; then
  pass "vibe: QA remediation verify uses remediation-only verify context"
else
  fail "vibe: QA remediation verify missing remediation-only verify context"
fi

if grep -q 'verify the exception is documented with non-fixable justification and that the justification is credible for this FAIL' "$VIBE_FILE" \
  && grep -q 'documentation alone is insufficient when the original FAIL still appears fixable via code or plan amendment' "$VIBE_FILE"; then
  pass "vibe: remediation QA rejects unjustified process-exception labels"
else
  fail "vibe: remediation QA guidance still allows documentation-only process-exception loophole"
fi

if grep -q 'compile-verify-context-for-uat\.sh' "$VERIFY_FILE"; then
  pass "verify: misnamed-plan refresh recomputes UAT scope through shared resolver"
else
  fail "verify: misnamed-plan refresh missing shared UAT scope resolver"
fi

if grep -Eq 'uat-remediation-state\.sh"? get-or-init "{phase-dir}" major' "$VERIFY_FILE" \
  && grep -q 'remediation/uat/round-{RR}/R{RR}-UAT.md' "$VERIFY_FILE" \
  && grep -q 'remediation/round-{RR}/R{RR}-UAT.md' "$VERIFY_FILE" \
  && grep -Eq 'extract-uat-resume\.sh"? "{phase-dir}"' "$VERIFY_FILE"; then
  pass "verify: remediation re-verification refreshes and validates round-scoped uat_path for round-dir and legacy layouts"
else
  fail "verify: remediation re-verification missing refreshed round-scoped uat_path validation"
fi

if grep -q 'ignore the pre-computed verify context, `next_phase_state`, `qa_status`, and UAT resume metadata' "$VERIFY_FILE" \
  && grep -q 'Do NOT force full scope' "$VERIFY_FILE" \
  && grep -q 'Use UAT resume metadata for the active target phase' "$VERIFY_FILE" \
  && grep -q 'uat-remediation-state\.sh" get "{phase-dir}"' "$VERIFY_FILE"; then
  pass "verify: explicit target phase uses target-specific verify state and blocks mid-remediation UAT"
else
  fail "verify: explicit target phase still depends on auto-detected state or allows mid-remediation UAT"
fi

if grep -q '_uat_state_file=.*remediation/uat/\.uat-remediation-stage' "$VERIFY_FILE" \
  && grep -q '_uat_legacy_remed_file=.*remediation/\.uat-remediation-stage' "$VERIFY_FILE" \
  && grep -q '_uat_legacy_file=.*\.uat-remediation-stage' "$VERIFY_FILE" \
  && grep -q '_uat_state_exists' "$VERIFY_FILE"; then
  pass "verify: remediation lifecycle advance has state-existence guard for new-format and both legacy locations"
else
  fail "verify: remediation lifecycle advance missing state-existence guard before needs-round"
fi

echo ""
echo "=== Milestone Context Refresh Verification ==="
mode_block() {
  extract_heading_block "$VIBE_FILE" "$1" '^### Mode: '
}

echo ""
echo "=== Mode Block Helper Regression Verification ==="

_mode_helper_tmp_dir="$(mktemp -d)"
_mode_helper_fixture="$_mode_helper_tmp_dir/mode-block-fixture.md"
printf '%s' $'### Mode: Archive   \r\n9b. Post-archive hook (non-blocking): after successful archive completion, run:\r\n  MILESTONE_SLUG=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/derive-milestone-slug.sh\r\n    .vbw-planning)\r\n### Mode: Next\r\nignored\r\n' > "$_mode_helper_fixture"
_mode_helper_block="$(extract_heading_block "$_mode_helper_fixture" "### Mode: Archive" '^### Mode: ' || true)"

if [ -n "$_mode_helper_block" ]; then
  pass "mode-block helper extracts mode blocks with trailing-space/CRLF headings"
else
  fail "mode-block helper failed to extract mode block with trailing-space/CRLF heading"
fi

if block_contains_normalized "$_mode_helper_block" 'MILESTONE_SLUG=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/derive-milestone-slug.sh .vbw-planning)'; then
  pass "mode-block helper matches wrapped milestone slug command after whitespace normalization"
else
  fail "mode-block helper missed wrapped milestone slug command after whitespace normalization"
fi

if contains_literal "$_mode_helper_block" 'ignored'; then
  fail "mode-block helper did not stop at the next mode heading"
else
  pass "mode-block helper stops at the next mode heading"
fi

if block_contains_normalized "$_mode_helper_block" 'MILESTONE_SLUG=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/not-the-helper.sh .vbw-planning)'; then
  fail "mode-block helper normalization produced a false positive for the wrong helper path"
else
  pass "mode-block helper normalization rejects wrong helper paths"
fi

rm -rf "$_mode_helper_tmp_dir"

for mode in "### Mode: Add Phase" "### Mode: Insert Phase" "### Mode: Remove Phase"; do
  block=$(mode_block "$mode")
  label=${mode#"### Mode: "}

  if grep -q 'If `\.vbw-planning/CONTEXT\.md` exists, rewrite it to reflect the updated milestone decomposition' <<< "$block"; then
    pass "vibe: $label refreshes milestone CONTEXT.md"
  else
    fail "vibe: $label missing milestone CONTEXT refresh instruction"
  fi

  if grep -q 'Preserve project-level key decisions and deferred ideas where still valid\.' <<< "$block"; then
    pass "vibe: $label preserves milestone decisions and deferred ideas"
  else
    fail "vibe: $label missing preservation instruction for milestone CONTEXT refresh"
  fi
done

echo ""
echo "=== Add Phase Numbering Verification ==="

add_phase_block=$(mode_block "### Mode: Add Phase")
if contains_literal "$add_phase_block" '6. Update ROADMAP.md:' \
  && contains_literal "$add_phase_block" '7. If `.vbw-planning/CONTEXT.md` exists, rewrite it to reflect the updated milestone decomposition' \
  && contains_literal "$add_phase_block" '8. Update STATE.md phase total:' \
  && contains_literal "$add_phase_block" '9. **Phase mutation commit boundary (conditional):**' \
  && contains_literal "$add_phase_block" '10. Present:' \
  && ! contains_literal "$add_phase_block" '1. Update ROADMAP.md:'; then
  pass "vibe: Add Phase keeps one ordered parent step list"
else
  fail "vibe: Add Phase restarts ordered steps instead of continuing 6-10"
fi

echo ""
echo "=== Archive Hook Wiring Verification ==="

archive_block=$(mode_block "### Mode: Archive")

if contains_literal "$archive_block" '9b. Post-archive hook (non-blocking): after successful archive completion, run:'; then
  pass "vibe: Archive mode includes explicit post-archive hook step"
else
  fail "vibe: Archive mode missing explicit post-archive hook step"
fi

if block_contains_normalized "$archive_block" 'MILESTONE_SLUG=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/derive-milestone-slug.sh .vbw-planning)'; then
  pass "vibe: Archive mode derives milestone slug via derive-milestone-slug.sh"
else
  fail "vibe: Archive mode missing deterministic milestone slug derivation"
fi

if contains_literal "$archive_block" 'Parse args: --tag=vN.N.N (custom tag), --no-tag (skip), --force (skip non-UAT audit).'; then
  pass "vibe: Archive mode still defines --tag as a custom git tag"
else
  fail "vibe: Archive mode no longer defines --tag as a custom git tag"
fi

if contains_literal "$archive_block" 'Override with `--tag` if provided.'; then
  fail "vibe: Archive mode still lets --tag override milestone slug"
else
  pass "vibe: Archive mode keeps milestone slug separate from custom --tag"
fi

if block_contains_normalized "$archive_block" 'bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/post-archive-hook.sh "{SLUG}" ".vbw-planning/milestones/{SLUG}" "{tag}" .vbw-planning/config.json'; then
  pass "vibe: Archive mode wires post-archive hook with slug/archive/tag/config arguments"
else
  fail "vibe: Archive mode missing post-archive hook argument contract"
fi

archive_regen_line=$(first_matching_line_number "$archive_block" '9. Regenerate CLAUDE.md:')
archive_hook_line=$(first_matching_line_number "$archive_block" '9b. Post-archive hook (non-blocking):')
archive_present_line=$(first_matching_line_number "$archive_block" '10. Present:')

if [ -n "$archive_regen_line" ] && [ -n "$archive_hook_line" ] && [ -n "$archive_present_line" ] \
  && [ "$archive_regen_line" -lt "$archive_hook_line" ] \
  && [ "$archive_hook_line" -lt "$archive_present_line" ]; then
  pass "vibe: Archive post-archive hook remains between CLAUDE regeneration and final presentation"
else
  fail "vibe: Archive post-archive hook ordering drifted outside the successful archive sequence"
fi

echo ""
echo "=== QA Result Gate Contract ==="

QA_FILE="$COMMANDS_DIR/qa.md"

if grep -Eq 'qa-remediation-state\.sh"? get' "$QA_FILE"; then
  pass "qa: resolves remediation state before choosing verification output path"
else
  fail "qa: missing qa-remediation-state.sh get — standalone QA may overwrite phase-level verification"
fi

if grep -q 'first_qa_attention_phase' "$QA_FILE" && grep -q 'qa_attention_status' "$QA_FILE"; then
  pass "qa: auto-detect can target stale or failed QA even with terminal UAT"
else
  fail "qa: missing first_qa_attention-based auto-detect guidance"
fi

if grep -q 'pending`, `failed`, or `verify`' "$QA_FILE"; then
  pass "qa: auto-detect includes verify-stage remediation escape hatch"
else
  fail "qa: auto-detect missing verify-stage remediation escape hatch"
fi

if grep -q 'case "\$QA_STAGE" in' "$QA_FILE" && grep -q 'verify)' "$QA_FILE" && grep -q 'done)' "$QA_FILE" && grep -q 'plan|execute' "$QA_FILE"; then
  pass "qa: uses persisted verification_path only for verify/done and blocks plan/execute"
else
  fail "qa: missing verify/done output guard and plan/execute stop for persisted verification_path"
fi

if grep -Eq 'resolve-verification-path\.sh"? current' "$QA_FILE"; then
  pass "qa: resolves authoritative verification path for done-stage remediation"
else
  fail "qa: missing authoritative done-stage verification path resolution"
fi

if grep -q 'source_verification_path' "$ROOT/references/execute-protocol.md" && grep -q 'verification_path' "$ROOT/references/execute-protocol.md"; then
  pass "execute-protocol: parses full QA remediation metadata contract"
else
  fail "execute-protocol: missing source_verification_path/verification_path in QA remediation metadata parsing"
fi

if grep -Eq 'source_plan`? must reference an original plan in the current phase only' "$ROOT/references/execute-protocol.md" \
  && grep -Eq 'source_plan`? must reference an original plan in the current phase only' "$VIBE_FILE"; then
  pass "execute-protocol/vibe: plan-amendment source_plan is constrained to current-phase original plans"
else
  fail "execute-protocol/vibe: missing current-phase-only constraint for plan-amendment source_plan"
fi

if grep -q 'carry forward the nearest earlier verification artifact in the remediation chain that still contains the unresolved FAILs' "$ROOT/references/execute-protocol.md" \
  && grep -q 'carry forward the nearest earlier verification artifact in the remediation chain that still contains the unresolved FAILs' "$VIBE_FILE"; then
  pass "execute-protocol/vibe: round 02+ planning carries unresolved FAIL source forward across gate-rejected PASS rounds"
else
  fail "execute-protocol/vibe: missing unresolved FAIL carry-forward guidance for round 02+ remediation planning"
fi

if grep -q 'verification_path=' "$QA_FILE" && grep -q 'Output path: {VERIF_PATH}' "$QA_FILE"; then
  pass "qa: uses persisted verification_path contract for standalone QA output"
else
  fail "qa: missing persisted verification_path contract for standalone QA output"
fi

if grep -q 'qa-result-gate\.sh' "$QA_FILE" \
  && grep -Eq 'qa-remediation-state\.sh"? advance' "$QA_FILE" \
  && grep -Eq 'qa-remediation-state\.sh"? needs-round' "$QA_FILE"; then
  pass "qa: standalone remediation QA reruns deterministic gate before trusting round-scoped PASS artifacts"
else
  fail "qa: missing deterministic gate reconciliation for standalone remediation QA"
fi

qa_remediation_block="$({
  awk '
    /^\*\*QA Remediation mode \(needs_qa_remediation\)/ { in_block=1 }
    /^\*\*QA Remediation \+ UAT blocking:/ { in_block=0 }
    in_block { print }
  ' "$VIBE_FILE"
} || true)"

qa_remediation_plan_block="$({
  awk '
    /^- \*\*stage=plan:/ { in_block=1 }
    /^- \*\*stage=execute:/ { in_block=0 }
    in_block { print }
  ' <<< "$qa_remediation_block"
} || true)"

qa_remediation_execute_block="$({
  awk '
    /^- \*\*stage=execute:/ { in_block=1 }
    /^- \*\*stage=verify:/ { in_block=0 }
    in_block { print }
  ' <<< "$qa_remediation_block"
} || true)"

execute_protocol_qa_remediation_block="$({
  awk '
    /^\*\*QA Remediation Loop \(inline, same session\):/ { in_block=1 }
    /^### Step 4\.5: Human acceptance testing \(UAT\)/ { in_block=0 }
    in_block { print }
  ' "$ROOT/references/execute-protocol.md"
} || true)"

qa_remediation_verify_block="$({
  awk '
    /^- \*\*stage=verify:/ { in_block=1 }
    in_block { print }
  ' <<< "$qa_remediation_block"
} || true)"

if grep -Fq '<qa_remediation_artifact_contract>' <<< "$qa_remediation_block" \
  && grep -Fq '`round_dir`, `source_verification_path`, `known_issues_path`, and `verification_path` are authoritative host-repository paths from `qa-remediation-state.sh` metadata' <<< "$qa_remediation_block" \
  && grep -Fq 'pass these exact paths to Lead, Dev, and QA prompts' <<< "$qa_remediation_block" \
  && grep -Fq '.claude/worktrees/agent-*' <<< "$qa_remediation_block" \
  && grep -Fq 'never rewrite them relative to the current CWD' <<< "$qa_remediation_block"; then
  pass "vibe: QA remediation has host artifact path contract"
else
  fail "vibe: QA remediation missing host artifact path contract"
fi

if grep -Fq '<qa_remediation_artifact_contract>' <<< "$execute_protocol_qa_remediation_block" \
  && grep -Fq '`round_dir`, `source_verification_path`, `known_issues_path`, and `verification_path` from `qa-remediation-state.sh` metadata are authoritative host-repository paths' <<< "$execute_protocol_qa_remediation_block" \
  && grep -Fq 'pass these exact paths to Lead, Dev, and QA prompts' <<< "$execute_protocol_qa_remediation_block" \
  && grep -Fq 'never rewrite them relative to the current CWD' <<< "$execute_protocol_qa_remediation_block"; then
  pass "execute-protocol: QA remediation host paths cover Lead, Dev, and QA"
else
  fail "execute-protocol: QA remediation host path contract missing Lead/Dev/QA coverage"
fi

if grep -Fq '<qa_remediation_spawn_contract>' <<< "$qa_remediation_block" \
  && grep -Fq 'QA remediation spawns are plain sequential subagent calls' <<< "$qa_remediation_block" \
  && grep -Fq 'Do not pass team metadata (`team_name`), per-agent names (`name`), `run_in_background`, `isolation`, or worktree cwd fields (`cwd`, `working_dir`, `workingDirectory`, `workdir`)' <<< "$qa_remediation_block"; then
  pass "vibe: QA remediation has non-team spawn-shape contract"
else
  fail "vibe: QA remediation missing non-team spawn-shape contract"
fi

if grep -Fq 'future section explicitly prepares VBW worktree targeting' <<< "$qa_remediation_block" \
  || grep -Fq 'unless a future section' <<< "$qa_remediation_block" \
  || grep -Fq 'prepared VBW worktree target' <<< "$qa_remediation_block"; then
  fail "vibe: QA remediation must not preserve worktree-targeting spawn exceptions"
else
  pass "vibe: QA remediation rejects worktree-targeting spawn exceptions"
fi

if grep -Fq '<qa_remediation_no_tool_circuit_breaker>' <<< "$qa_remediation_block" \
  && grep -Fq 'After any QA remediation Lead, Dev, or QA subagent returns' <<< "$qa_remediation_block" \
  && grep -Fq 'tools, shell/Bash, filesystem, edits, or API-session access are unavailable' <<< "$qa_remediation_block" \
  && grep -Fq 'STOP without advancing `.qa-remediation-stage`' <<< "$qa_remediation_block" \
  && grep -Fq 'do not retry the same prompt' <<< "$qa_remediation_block"; then
  pass "vibe: QA remediation has no-tool circuit breaker"
else
  fail "vibe: QA remediation missing no-tool circuit breaker"
fi

if grep -Fq 'tools, Bash, filesystem, edits, or API-session access are unavailable' <<< "$qa_remediation_block"; then
  fail "vibe: QA remediation no-tool breaker still uses Bash-only wording"
else
  pass "vibe: QA remediation no-tool breaker includes generic shell signal"
fi

if grep -Fq 'unavailable tools, Bash, filesystem, edits, or API-session access' <<< "$qa_remediation_block"; then
  fail "vibe: QA remediation return sites still use Bash-only wording"
else
  pass "vibe: QA remediation return sites include generic shell signal"
fi

if grep -Fq 'After any QA remediation Dev or QA subagent returns' <<< "$qa_remediation_block"; then
  fail "vibe: QA remediation shared no-tool breaker still excludes Lead"
else
  pass "vibe: QA remediation shared no-tool breaker includes Lead"
fi

if grep -Fq 'After any QA remediation Lead, Dev, or QA subagent returns' <<< "$execute_protocol_qa_remediation_block" \
  && grep -Fq 'tools, shell/Bash, filesystem, edits, or API-session access are unavailable' <<< "$execute_protocol_qa_remediation_block" \
  && grep -Fq 'STOP without advancing `.qa-remediation-stage`' <<< "$execute_protocol_qa_remediation_block" \
  && grep -Fq 'do not retry the same prompt' <<< "$execute_protocol_qa_remediation_block"; then
  pass "execute-protocol: QA remediation shared no-tool breaker includes Lead"
else
  fail "execute-protocol: QA remediation shared no-tool breaker missing Lead or stop/no-retry wording"
fi

check_literal_before_regex "vibe: QA no-tool breaker appears before remediation state advance" "$qa_remediation_block" '<qa_remediation_no_tool_circuit_breaker>' 'qa-remediation-state\.sh.*advance'
check_literal_before_literal "vibe: QA no-tool breaker appears before deterministic gate" "$qa_remediation_block" '<qa_remediation_no_tool_circuit_breaker>' 'qa-result-gate.sh'

if grep -Fq 'The orchestrator/Lead writes the plan' <<< "$qa_remediation_plan_block" \
  || grep -Fq 'The orchestrator writes the plan' <<< "$qa_remediation_plan_block"; then
  fail "vibe: QA remediation plan stage still has ambiguous orchestrator-authored planning wording"
else
  pass "vibe: QA remediation plan stage removes ambiguous orchestrator-authored wording"
fi

if grep -Fq 'spawns exactly one Lead subagent to write `{round_dir}/R{RR}-PLAN.md`' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'subagent_type: "vbw:vbw-lead"' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'resolve-agent-settings.sh lead' <<< "$qa_remediation_plan_block" \
  && grep -Fq '.vbw-planning/config.json' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'config/model-profiles.json' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'LEAD_MODEL="$RESOLVED_MODEL"' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'LEAD_MAX_TURNS="$RESOLVED_MAX_TURNS"' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'model: "${LEAD_MODEL}"' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'maxTurns: ${LEAD_MAX_TURNS}' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'omit `maxTurns` because the resolved profile is unlimited' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'Do not pass `team_name`, per-agent `name`, `run_in_background`, `isolation`, `cwd`, `working_dir`, `workingDirectory`, or `workdir`' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'Read the remediation plan template at /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/templates/REMEDIATION-PLAN.md' <<< "$qa_remediation_plan_block"; then
  pass "vibe: QA remediation plan stage resolves Lead settings and spawns with safe shape"
else
  fail "vibe: QA remediation plan stage missing Lead settings resolution or safe spawn contract"
fi

check_literal_before_literal "vibe: QA plan resolves Lead settings before using Lead model" "$qa_remediation_plan_block" 'resolve-agent-settings.sh lead' 'model: "${LEAD_MODEL}"'
if grep -Fq 'Existing-plan recovery before spawning Lead' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'If the canonical `{round_dir}/R{RR}-PLAN.md` exists after normalization' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'If validation passes, do not spawn Lead again; reuse the persisted plan' <<< "$qa_remediation_plan_block"; then
  pass "vibe: QA remediation reuses existing validated plan on resume"
else
  fail "vibe: QA remediation missing existing-plan recovery before Lead respawn"
fi
check_literal_before_literal "vibe: QA existing-plan recovery normalizes before canonical probe" "$qa_remediation_plan_block" 'normalize-plan-filenames.sh' 'If the canonical `{round_dir}/R{RR}-PLAN.md` exists after normalization'
check_literal_before_literal "vibe: QA existing-plan recovery appears before Lead spawn" "$qa_remediation_plan_block" 'Existing-plan recovery before spawning Lead' 'spawns exactly one Lead subagent to write `{round_dir}/R{RR}-PLAN.md`'
check_literal_before_literal "vibe: QA plan Lead spawn appears before Lead return breaker" "$qa_remediation_plan_block" 'spawns exactly one Lead subagent to write `{round_dir}/R{RR}-PLAN.md`' 'After Lead returns, apply the QA remediation no-tool circuit breaker'

if grep -Fq 'Normalize plan filenames before validation' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'normalize-plan-filenames.sh' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'validate-uat-remediation-artifact.sh plan "{round_dir}/R{RR}-PLAN.md"' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'If validation fails, display the validator error and STOP without advancing `.qa-remediation-stage`' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'Do not search for an alternate PLAN.md' <<< "$qa_remediation_plan_block"; then
  pass "vibe: QA remediation plan stage validates canonical plan before advance"
else
  fail "vibe: QA remediation plan stage missing normalization/validation gate before advance"
fi

if grep -Fq 'After Lead returns, apply the QA remediation no-tool circuit breaker' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'If Lead reports unavailable tools, shell/Bash, filesystem, edits, or API-session access' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'After Dev returns, apply the QA remediation no-tool circuit breaker' <<< "$qa_remediation_block" \
  && grep -Fq 'If Dev reports unavailable tools, shell/Bash, filesystem, edits, or API-session access' <<< "$qa_remediation_execute_block" \
  && grep -Fq 'After QA returns, apply the QA remediation no-tool circuit breaker' <<< "$qa_remediation_block" \
  && grep -Fq 'If QA reports unavailable tools, shell/Bash, filesystem, edits, or API-session access' <<< "$qa_remediation_verify_block"; then
  pass "vibe: QA remediation applies no-tool breaker at Lead, Dev, and QA return sites"
else
  fail "vibe: QA remediation missing no-tool breaker at Lead, Dev, or QA return site"
fi

check_literal_before_regex "vibe: QA plan Lead breaker appears before plan-stage state advance" "$qa_remediation_plan_block" 'After Lead returns, apply the QA remediation no-tool circuit breaker' 'qa-remediation-state\.sh.*advance'
check_literal_before_literal "vibe: QA plan Lead breaker appears before plan normalization" "$qa_remediation_plan_block" 'After Lead returns, apply the QA remediation no-tool circuit breaker' 'Normalize plan filenames before validation'
check_literal_before_literal "vibe: QA plan normalization appears before plan validation" "$qa_remediation_plan_block" 'Normalize plan filenames before validation' 'Validate the exact QA remediation plan artifact before advancing'
check_literal_before_regex "vibe: QA plan validation appears before plan-stage state advance" "$qa_remediation_plan_block" 'validate-uat-remediation-artifact.sh plan "{round_dir}/R{RR}-PLAN.md"' 'qa-remediation-state\.sh.*advance'
check_literal_before_literal "vibe: QA plan validation passes before state advance wording" "$qa_remediation_plan_block" 'Validate the exact QA remediation plan artifact before advancing' 'After plan validation passes, advance state'
check_literal_before_regex "vibe: QA execute Dev breaker appears before execute-stage state advance" "$qa_remediation_execute_block" 'After Dev returns, apply the QA remediation no-tool circuit breaker' 'qa-remediation-state\.sh.*advance'
check_literal_before_literal "vibe: QA verify breaker appears before known-issue sync" "$qa_remediation_verify_block" 'After QA returns, apply the QA remediation no-tool circuit breaker' 'track-known-issues.sh" sync-verification'
check_literal_before_literal "vibe: QA verify breaker appears before known-issue promotion" "$qa_remediation_verify_block" 'After QA returns, apply the QA remediation no-tool circuit breaker' 'track-known-issues.sh" promote-todos'
check_literal_before_literal "vibe: QA verify breaker appears before deterministic gate" "$qa_remediation_verify_block" 'After QA returns, apply the QA remediation no-tool circuit breaker' 'qa-result-gate.sh'

if grep -q 'Determine verification scope from `VERIF_PATH`' "$QA_FILE"; then
  pass "qa: standalone QA scope is tied to resolved VERIF_PATH"
else
  fail "qa: standalone QA scope still appears disconnected from resolved VERIF_PATH"
fi

if grep -q 'Determine verification scope from `VERIF_PATH`' "$QA_FILE"; then
  pass "qa: standalone QA scope is tied to resolved VERIF_PATH"
else
  fail "qa: standalone QA scope still appears disconnected from resolved VERIF_PATH"
fi

if grep -q 'first_qa_attention_phase' "$QA_FILE" && grep -q 'qa_attention_status' "$QA_FILE"; then
  pass "qa: auto-detect retargets stale or failed authoritative QA artifacts"
else
  fail "qa: auto-detect missing stale/failed authoritative QA retargeting guidance"
fi

if grep -q 'compile-verify-context.sh --remediation-only' "$VIBE_FILE"; then
  pass "vibe: refreshes verify context before QA remediation handoff to Verify"
else
  fail "vibe: missing verify-context refresh for QA remediation handoff"
fi

echo ""
echo "=== Execute Team Routing Verification ==="

if grep -q 'True team mode' "$ROOT/references/execute-protocol.md" \
  && grep -q 'Explicit non-team mode' "$ROOT/references/execute-protocol.md" \
  && grep -q 'Team-tooling-unavailable fallback' "$ROOT/references/execute-protocol.md"; then
  pass "execute-protocol: defines true team, explicit non-team, and fallback branches"
else
  fail "execute-protocol: missing one or more execute team-routing branches"
fi

if grep -q 'Plain background `Agent` spawns without team semantics are NOT an agent team' "$ROOT/references/execute-protocol.md"; then
  pass "execute-protocol: forbids faux-team background Agent substitution"
else
  fail "execute-protocol: missing faux-team Agent prohibition"
fi

if grep -q '⚠ Agent Teams not enabled — using non-team mode' "$ROOT/references/execute-protocol.md"; then
  pass "execute-protocol: pins explicit non-team fallback warning text"
else
  fail "execute-protocol: missing explicit non-team fallback warning text"
fi

if grep -Fq 'resolve-execute-delegation-mode.sh' "$ROOT/references/execute-protocol.md" \
  && grep -Fq "prefer_teams='auto'" "$ROOT/references/execute-protocol.md" \
  && grep -Fq 'max_parallel_width > 1' "$ROOT/references/execute-protocol.md" \
  && ! grep -Fq "prefer_teams='auto': request team mode only when 2+ uncompleted plans remain" "$ROOT/references/execute-protocol.md" \
  && grep -Fq 'When true team mode is active, pass `team_name: "vbw-phase-{NN}"` and `name: "dev-{MM}"`' "$ROOT/references/execute-protocol.md" \
  && grep -Fq 'When true team mode is active, pass `team_name: "vbw-phase-{NN}"` and `name: "qa"' "$ROOT/references/execute-protocol.md"; then
  pass "execute-protocol: dependency-aware routing uses consistent true-team metadata wording"
else
  fail "execute-protocol: dependency-aware routing wording is inconsistent or still references stale 2+ plan team creation"
fi

if grep -q 'scripts/delegated-workflow.sh" set execute' "$ROOT/references/execute-protocol.md" \
  && grep -q 'delegation_mode' "$ROOT/scripts/delegated-workflow.sh"; then
  pass "execute-protocol + delegated-workflow: runtime execute delegation mode is persisted"
else
  fail "execute-protocol + delegated-workflow: missing persisted execute delegation mode contract"
fi

if grep -q 'background `Agent` spawns that lack `team_name`' "$VIBE_FILE" \
  && grep -q 'fall back to explicit non-team execution' "$VIBE_FILE"; then
  pass "vibe: execute invariant forbids faux-team background Agent execution"
else
  fail "vibe: missing execute invariant for real-team vs explicit fallback"
fi

# vibe.md must reference qa-result-gate.sh at both gate call sites (primary + remediation verify)
_vibe_gate_count=$(grep -c 'qa-result-gate\.sh' "$COMMANDS_DIR/vibe.md" 2>/dev/null || echo 0)
if [ "$_vibe_gate_count" -ge 2 ]; then
  pass "vibe: references qa-result-gate.sh at $_vibe_gate_count call sites"
else
  fail "vibe: expected >=2 qa-result-gate.sh references, found $_vibe_gate_count"
fi

# execute-protocol.md must reference qa-result-gate.sh at both call sites
_ep_gate_count=$(grep -c 'qa-result-gate\.sh' "$ROOT/references/execute-protocol.md" 2>/dev/null || echo 0)
if [ "$_ep_gate_count" -ge 2 ]; then
  pass "execute-protocol: references qa-result-gate.sh at $_ep_gate_count call sites"
else
  fail "execute-protocol: expected >=2 qa-result-gate.sh references, found $_ep_gate_count"
fi

# Both must include the anti-rationalization instruction at all gate call sites
for f in "$COMMANDS_DIR/vibe.md" "$ROOT/references/execute-protocol.md"; do
  base=$(basename "$f")
  _ar_count=$(grep -c 'no exceptions, no judgment, no rationalization' "$f" 2>/dev/null || echo 0)
  if [ "$_ar_count" -ge 2 ]; then
    pass "$base: has anti-rationalization instruction at $_ar_count call sites"
  else
    fail "$base: expected >=2 anti-rationalization instructions, found $_ar_count"
  fi
done

echo ""
echo "=== Allowed-Tools Consistency Verification ==="

# Commands that reference specific tool names in their body must include those
# tools in their allowed-tools frontmatter. Keep these checks exact-pattern and
# low-noise: match real tool-call syntax or explicit tool names, not generic
# prose about "skills" or "search".
for file in "${TRACKED_COMMAND_MARKDOWN_FILES[@]}"; do
  base="$(basename "$file" .md)"

  FRONTMATTER="$(extract_frontmatter "$file")"
  if [ -z "$FRONTMATTER" ]; then
    continue
  fi

  ALLOWED="$(frontmatter_first_scalar "$FRONTMATTER" "allowed-tools")"
  if [ -z "$ALLOWED" ]; then
    continue
  fi

  check_allowed_tool_match "$base" "$ALLOWED" "$file" "AskUserQuestion" '(^|[^[:alnum:]_])AskUserQuestion([^[:alnum:]_]|$)'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "Skill" 'Call[[:space:]]+Skill[(]|(^|[^[:alnum:]_])Skill[(]'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "WebSearch" '(^|[^[:alnum:]_])WebSearch([^[:alnum:]_]|$)' 'do[[:space:]]+not.*WebSearch'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "Agent" '(via[[:space:]]+Task[[:space:]]+tool|Task[[:space:]]+tool[[:space:]]+invocation|subagent_type:)'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "TeamCreate" '(^|[^[:alnum:]_])TeamCreate([^[:alnum:]_]|$)' 'do[[:space:]]+not.*TeamCreate'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "TaskCreate" '(^|[^[:alnum:]_])TaskCreate([^[:alnum:]_]|$)' 'do[[:space:]]+not.*TaskCreate'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "TodoWrite" '(^|[^[:alnum:]_])TodoWrite([^[:alnum:]_]|$)' 'do[[:space:]]+not.*TodoWrite|disallow.*TodoWrite|forbid.*TodoWrite'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "SendMessage" '(^|[^[:alnum:]_])SendMessage([^[:alnum:]_]|$)' 'do[[:space:]]+not.*SendMessage'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "TeamDelete" '(^|[^[:alnum:]_])TeamDelete([^[:alnum:]_]|$)' 'do[[:space:]]+not.*TeamDelete'
done

# Regression guards for prompt-text tool references that previously slipped
# through the generic matcher. Keep these explicit until the generic helper is
# proven to catch them in all command bodies.
for skill_cmd in debug fix map qa research vibe; do
  skill_file="$COMMANDS_DIR/${skill_cmd}.md"
  [ -f "$skill_file" ] || continue

  if grep -Fq 'Call Skill(' "$skill_file"; then
    skill_allowed="$(frontmatter_first_scalar_from_file "$skill_file" "allowed-tools")"
    if has_allowed_tool "$skill_allowed" "Skill"; then
      pass "$skill_cmd: regression guard confirms Skill allowlist"
    else
      fail "$skill_cmd: regression guard found Call Skill(...) but allowed-tools is missing Skill"
    fi
  fi
done

INIT_FILE="$COMMANDS_DIR/init.md"
if [ -f "$INIT_FILE" ] && grep -Fq 'WebSearch' "$INIT_FILE"; then
  init_allowed="$(frontmatter_first_scalar_from_file "$INIT_FILE" "allowed-tools")"
  if has_allowed_tool "$init_allowed" "WebSearch"; then
    pass "init: regression guard confirms WebSearch allowlist"
  else
    fail "init: regression guard found WebSearch in body but allowed-tools is missing WebSearch"
  fi
fi

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
done < <(grep -RhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9._/*{}-]+' "${TRACKED_COMMAND_MARKDOWN_FILES[@]}" 2>/dev/null | sort -u)

# ── UAT Remediation step 4 must use TodoWrite (not generic "task list") ──
echo ""
echo "--- UAT Remediation TodoWrite disambiguation ---"
# Extract the UAT Remediation section body (between its header and the next ### Mode:)
# Match step 4's heading specifically — not just any "TodoWrite progress list" in the section
uat_section="$(
  awk '
    /^### Mode: UAT Remediation$/ { in_section=1; next }
    in_section && /^### Mode:/ { exit }
    in_section { print }
  ' "$COMMANDS_DIR/vibe.md"
)"
if grep -q '\*\*TodoWrite progress list (NON-NEGOTIABLE' <<< "$uat_section"; then
  pass "UAT Remediation step 4 explicitly references TodoWrite"
else
  fail "UAT Remediation step 4 missing 'TodoWrite progress list' heading — risk of TaskCreate conflation (see issue #367)"
fi

if contains_literal "$uat_section" 'TodoWrite is the only progress tracker for these stages'; then
  pass "UAT Remediation declares TodoWrite as the sole stage progress tracker"
else
  fail "UAT Remediation missing explicit TodoWrite-only stage progress tracker contract"
fi

if contains_literal "$uat_section" 'Do not represent Research, Plan, Execute, or Fix as TaskCreate/TaskUpdate items'; then
  pass "UAT Remediation forbids TaskCreate/TaskUpdate stage trackers"
else
  fail "UAT Remediation missing TaskCreate/TaskUpdate stage-tracker prohibition"
fi

if contains_literal "$uat_section" 'TaskCreate/Agent is allowed only for real Scout/Lead/Dev work-unit delegation inside the current stage'; then
  pass "UAT Remediation distinguishes progress tracking from Scout/Lead/Dev delegation"
else
  fail "UAT Remediation missing delegation/progress-tracking distinction"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All command contract checks passed."
exit 0

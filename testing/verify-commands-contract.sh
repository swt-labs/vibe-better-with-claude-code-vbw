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
echo "=== skills.md Step 5b Verification ==="

SKILLS_FILE="$COMMANDS_DIR/skills.md"
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
if printf '%s\n' "$add_phase_block" | grep -Fq '6. Update ROADMAP.md:' \
  && printf '%s\n' "$add_phase_block" | grep -Fq '7. If `.vbw-planning/CONTEXT.md` exists, rewrite it to reflect the updated milestone decomposition' \
  && printf '%s\n' "$add_phase_block" | grep -Fq '8. Update STATE.md phase total:' \
  && printf '%s\n' "$add_phase_block" | grep -Fq '9. **Phase mutation commit boundary (conditional):**' \
  && printf '%s\n' "$add_phase_block" | grep -Fq '10. Present:' \
  && ! printf '%s\n' "$add_phase_block" | grep -Fq '1. Update ROADMAP.md:'; then
  pass "vibe: Add Phase keeps one ordered parent step list"
else
  fail "vibe: Add Phase restarts ordered steps instead of continuing 6-10"
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

if ! grep -Fq 'When team was created (2+ plans)' "$ROOT/references/execute-protocol.md" \
  && grep -Fq 'request team mode for ALL remaining-plan counts (even 1 plan)' "$ROOT/references/execute-protocol.md" \
  && grep -Fq 'ALL remaining-plan counts (even 1 plan)' "$ROOT/references/execute-protocol.md" \
  && grep -Fq 'When true team mode is active, pass `team_name: "vbw-phase-{NN}"` and `name: "dev-{MM}"`' "$ROOT/references/execute-protocol.md" \
  && grep -Fq 'When true team mode is active, pass `team_name: "vbw-phase-{NN}"` and `name: "qa"' "$ROOT/references/execute-protocol.md"; then
  pass "execute-protocol: single-plan team mode uses consistent true-team metadata wording"
else
  fail "execute-protocol: single-plan team mode wording is inconsistent or still references 2+ plan team creation"
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

  ALLOWED="$(printf '%s\n' "$FRONTMATTER" | sed -n 's/^allowed-tools:[[:space:]]*//p' | head -1)"
  if [ -z "$ALLOWED" ]; then
    continue
  fi

  check_allowed_tool_match "$base" "$ALLOWED" "$file" "AskUserQuestion" '(^|[^[:alnum:]_])AskUserQuestion([^[:alnum:]_]|$)'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "Skill" 'Call[[:space:]]+Skill[(]|(^|[^[:alnum:]_])Skill[(]'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "WebSearch" '(^|[^[:alnum:]_])WebSearch([^[:alnum:]_]|$)' 'do[[:space:]]+not.*WebSearch'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "Agent" '(via[[:space:]]+Task[[:space:]]+tool|Task[[:space:]]+tool[[:space:]]+invocation|subagent_type:)'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "TeamCreate" '(^|[^[:alnum:]_])TeamCreate([^[:alnum:]_]|$)' 'do[[:space:]]+not.*TeamCreate'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "TaskCreate" '(^|[^[:alnum:]_])TaskCreate([^[:alnum:]_]|$)' 'do[[:space:]]+not.*TaskCreate'
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
    if grep -F 'allowed-tools:' "$skill_file" | grep -Fq 'Skill'; then
      pass "$skill_cmd: regression guard confirms Skill allowlist"
    else
      fail "$skill_cmd: regression guard found Call Skill(...) but allowed-tools is missing Skill"
    fi
  fi
done

INIT_FILE="$COMMANDS_DIR/init.md"
if [ -f "$INIT_FILE" ] && grep -Fq 'WebSearch' "$INIT_FILE"; then
  if grep -F 'allowed-tools:' "$INIT_FILE" | grep -Fq 'WebSearch'; then
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

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All command contract checks passed."
exit 0

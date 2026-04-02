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

if grep -q 'echo "verify_context=unavailable"' "$VIBE_FILE"; then
  pass "vibe: routed verify precompute emits fail-closed verify_context sentinel"
else
  fail "vibe: routed verify precompute missing fail-closed verify_context sentinel"
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

if grep -q 'uat-remediation-state\.sh get-or-init "{phase-dir}" major' "$VERIFY_FILE" \
  && grep -q 'remediation/uat/round-{RR}/R{RR}-UAT.md' "$VERIFY_FILE" \
  && grep -q 'remediation/round-{RR}/R{RR}-UAT.md' "$VERIFY_FILE" \
  && grep -q 'extract-uat-resume\.sh "{phase-dir}"' "$VERIFY_FILE"; then
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

QA_FILE="$COMMANDS_DIR/qa.md"

if grep -q 'qa-remediation-state\.sh get' "$QA_FILE"; then
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

if grep -q 'resolve-verification-path\.sh current' "$QA_FILE"; then
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

if grep -q 'qa-result-gate\.sh' "$QA_FILE" && grep -q 'not authoritative' "$QA_FILE"; then
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
# tools in their allowed-tools frontmatter. Claude Code enforces allowed-tools as
# a strict allowlist — unlisted tools are silently unavailable.
for file in "$COMMANDS_DIR"/*.md "$ROOT/internal"/*.md; do
  [ -f "$file" ] || continue
  base="$(basename "$file" .md)"

  FRONTMATTER="$(extract_frontmatter "$file")"
  if [ -z "$FRONTMATTER" ]; then
    continue
  fi

  ALLOWED="$(printf '%s\n' "$FRONTMATTER" | sed -n 's/^allowed-tools:[[:space:]]*//p' | head -1)"
  if [ -z "$ALLOWED" ]; then
    continue
  fi

  # Extract body (everything after second ---)
  body="$(awk '/^---$/{d++; next} d>=2' "$file")"

  # Check AskUserQuestion: if body references it, allowed-tools must include it
  if printf '%s\n' "$body" | grep -q 'AskUserQuestion'; then
    if printf '%s\n' "$ALLOWED" | grep -q 'AskUserQuestion'; then
      pass "$base: AskUserQuestion in body matches allowed-tools"
    else
      fail "$base: body references AskUserQuestion but allowed-tools does not include it"
    fi
  fi

  # Check Agent: if body references subagent spawning via "Task tool" or
  # subagent_type, allowed-tools must include Agent
  if printf '%s\n' "$body" | grep -qE '(via Task tool|subagent_type:)'; then
    if printf '%s\n' "$ALLOWED" | grep -q 'Agent'; then
      pass "$base: subagent spawning in body matches Agent in allowed-tools"
    else
      fail "$base: body spawns subagents but allowed-tools does not include Agent"
    fi
  fi

  # Check TeamCreate: if body uses TeamCreate (not in a "do not [use] TeamCreate"
  # instruction), allowed-tools must include it
  if printf '%s\n' "$body" | grep -q 'TeamCreate' && printf '%s\n' "$body" | grep 'TeamCreate' | grep -qvi 'do not.*TeamCreate'; then
    if printf '%s\n' "$ALLOWED" | grep -q 'TeamCreate'; then
      pass "$base: TeamCreate in body matches allowed-tools"
    else
      fail "$base: body references TeamCreate but allowed-tools does not include it"
    fi
  fi

  # Check TaskCreate: if body uses TaskCreate (not in a "do not [use] TaskCreate"
  # instruction), allowed-tools must include it
  if printf '%s\n' "$body" | grep -q 'TaskCreate' && printf '%s\n' "$body" | grep 'TaskCreate' | grep -qvi 'do not.*TaskCreate'; then
    if printf '%s\n' "$ALLOWED" | grep -q 'TaskCreate'; then
      pass "$base: TaskCreate in body matches allowed-tools"
    else
      fail "$base: body references TaskCreate but allowed-tools does not include it"
    fi
  fi

  # Check SendMessage: if body uses SendMessage (not in a "do not [use] SendMessage"
  # instruction), allowed-tools must include it
  if printf '%s\n' "$body" | grep -q 'SendMessage' && printf '%s\n' "$body" | grep 'SendMessage' | grep -qvi 'do not.*SendMessage'; then
    if printf '%s\n' "$ALLOWED" | grep -q 'SendMessage'; then
      pass "$base: SendMessage in body matches allowed-tools"
    else
      fail "$base: body references SendMessage but allowed-tools does not include it"
    fi
  fi

  # Check TeamDelete: if body uses TeamDelete (not in a "do not [use] TeamDelete"
  # instruction), allowed-tools must include it
  if printf '%s\n' "$body" | grep -q 'TeamDelete' && printf '%s\n' "$body" | grep 'TeamDelete' | grep -qvi 'do not.*TeamDelete'; then
    if printf '%s\n' "$ALLOWED" | grep -q 'TeamDelete'; then
      pass "$base: TeamDelete in body matches allowed-tools"
    else
      fail "$base: body references TeamDelete but allowed-tools does not include it"
    fi
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

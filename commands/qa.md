---
name: vbw:qa
category: monitoring
hidden: true
disable-model-invocation: true
description: Run deep verification on completed phase work using the QA agent.
argument-hint: [phase-number] [--tier=quick|standard|deep] [--effort=thorough|balanced|fast|turbo]
allowed-tools: Read, Write, Bash, Glob, Grep, Agent, Skill, LSP
---

# VBW QA: $ARGUMENTS

## Context
Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; SESSION_LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ] && [ -f "${SESSION_LINK}/scripts/hook-wrapper.sh" ]; then R="${SESSION_LINK}"; fi; if [ -z "$R" ]; then ANY_LINK=$(command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r link; do if [ -f "$link/scripts/hook-wrapper.sh" ]; then printf '%s\n' "$link"; break; fi; done || true); [ -n "$ANY_LINK" ] && R="$ANY_LINK"; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; LINK="${SESSION_LINK}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || { echo "VBW: plugin root canonicalization failed" >&2; exit 1; }; bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$LINK" "$REAL_R" >/dev/null 2>&1 || { echo "VBW: plugin root link failed" >&2; exit 1; }; bash "$LINK/scripts/phase-detect.sh" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt" 2>/dev/null || echo "phase_detect_error=true" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; echo "$LINK"`
```

Current state:
```text
!`head -40 .vbw-planning/STATE.md 2>/dev/null || echo "No state found"`
```

Config: Pre-injected by SessionStart hook. Override with --effort flag.

Phase directories:
```text
!`ls .vbw-planning/phases/ 2>/dev/null || echo "No phases directory"`
```

Phase state:
```text
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"
P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"
PD=""
_refresh_phase_detect() {
  local VBW_CACHE_ROOT R V D REAL_R
  VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"
  R=""
  if [ -z "$R" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi
  if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi
  if [ -z "$R" ]; then
    V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
    [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"
  fi
  if [ -z "$R" ]; then
    V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1)
    [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"
  fi
  SESSION_LINK="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"
  if [ -z "$R" ] && [ -f "$SESSION_LINK/scripts/hook-wrapper.sh" ]; then
    R="$SESSION_LINK"
  fi
  if [ -z "$R" ]; then
    ANY_LINK=$(command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r link; do
      if [ -f "$link/scripts/hook-wrapper.sh" ]; then
        printf '%s\n' "$link"
        break
      fi
    done || true)
    [ -n "$ANY_LINK" ] && R="$ANY_LINK"
  fi
  if [ -z "$R" ]; then
    D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1)
    D="${D#--plugin-dir }"
    [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"
  fi
  if [ -z "$R" ] || [ ! -d "$R" ] || [ ! -f "$R/scripts/phase-detect.sh" ]; then
    return 1
  fi
  REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || return 1
  bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$L" "$REAL_R" >/dev/null 2>&1 || true
  PD=$(bash "$REAL_R/scripts/phase-detect.sh" 2>/dev/null) || PD=""
  if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then
    return 1
  fi
  printf '%s' "$PD" > "$P"
  return 0
}
if ! _refresh_phase_detect; then
  PD="phase_detect_error=true"
  printf '%s\n' "$PD" > "$P"
fi
[ -f "$P" ] && PD=$(cat "$P")
if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then
  printf '%s' "$PD"
else
  echo "phase_detect_error=true"
fi`
```

```text
!`L="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; bash "$L/scripts/suggest-compact.sh" qa 2>/dev/null || true`
```

## Guard
- Not initialized (no .vbw-planning/ dir): STOP "Run /vbw:init first."
- **Debug session override:** If `$ARGUMENTS` does NOT contain an explicit phase number OR `$ARGUMENTS` contains `--session`, check for an active debug session before any phase-related guards:
  ```bash
  eval "$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/debug-session-state.sh get-or-latest .vbw-planning 2>/dev/null)" 2>/dev/null || true
  ```
  If `active_session != none` AND session `status` is `qa_pending` or `qa_failed` AND (`phase_count=0` OR `$ARGUMENTS` contains `--session`) → skip ALL remaining guards and jump directly to `<debug_session_qa>` below.
  If phases exist (`phase_count > 0`) AND `$ARGUMENTS` does NOT contain `--session`, skip this override — standard phase QA takes priority.
- **Brownfield normalization:** If Phase state (from Context above) contains `misnamed_plans=true`, normalize all phase directories before proceeding:
  ```bash
  NORM_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
  if [ -f "$NORM_SCRIPT" ]; then
    for pdir in .vbw-planning/phases/*/; do
      [ -d "$pdir" ] && bash "$NORM_SCRIPT" "$pdir"
    done
  fi
  ```
  Display: "⚠ Renamed misnamed plan files to `{NN}-PLAN.md` convention."
  Then re-run phase-detect.sh to refresh state (filenames changed):
  ```bash
  bash "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/phase-detect.sh" > "/tmp/.vbw-phase-detect-${CLAUDE_SESSION_ID:-default}.txt"
  ```
  Use the refreshed phase-detect output for all subsequent guard checks and steps.
- **Auto-detect phase** (no explicit number): Phase detection is pre-computed in Context above. Use `next_phase` and `next_phase_slug` for the target phase.
  - If `next_phase_state=needs_qa_remediation`, target that phase directly.
    - If the remediation stage is `plan` or `execute`, STOP and tell the user to run `/vbw:vibe` to continue QA remediation first — standalone QA must not mint a round VERIFICATION before re-verification is actually ready.
    - If the remediation stage is `verify` or `done`, standalone QA re-verifies the authoritative round artifact rather than overwriting the frozen phase-level VERIFICATION.
  - If `first_qa_attention_phase` is set and `qa_attention_status` is `pending`, `failed`, or `verify`, target that phase directly — existing QA artifacts may be stale or failed even when a file already exists, and verify-stage remediation rounds remain directly re-runnable even if an earlier phase is unfinished.
  - Otherwise, to find the first phase needing QA: scan phase dirs for first with completed `*-SUMMARY.md` files but no authoritative QA verification artifact (no numbered final VERIFICATION, no brownfield plain `VERIFICATION.md`, no wave fallback). Found: announce "Auto-detected Phase {NN} ({slug})". All verified: STOP "All phases verified. Specify: `/vbw:qa {NN}`"
- Phase not built (no SUMMARYs): STOP "Phase {NN} has no completed plans. Run /vbw:vibe first."

## Debug Session Routing

<debug_session_qa>
**Before resolving phase target**, check for an active debug session. This handles the case where phase_count=0 but a debug session with `status=qa_pending` or `status=qa_failed` exists.

```bash
eval "$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/debug-session-state.sh get-or-latest .vbw-planning)"
```

**Routing decision:**
- If `$ARGUMENTS` contains an explicit phase number AND no `--session` flag → skip debug-session routing, use standard phase QA flow below.
- If `active_session != none` AND session `status` is `qa_pending` or `qa_failed` AND (`phase_count=0` OR `$ARGUMENTS` contains `--session`) → enter debug-session QA mode (below). If `phase_count > 0` and no `--session` flag, skip debug-session routing — standard phase QA takes priority.
- If `active_session != none` but session `status` is NOT `qa_pending`/`qa_failed` → skip debug-session routing. Session is in a different lifecycle stage.
- If `active_session = none` → skip debug-session routing, continue to standard phase QA.

**Debug-session QA mode:**
When routed here, skip the standard phase-resolution Steps entirely. Instead:

1. Read the debug session's QA context:
   ```bash
   QA_CONTEXT=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/compile-debug-session-context.sh "$session_file" qa)
   ```

2. Increment the QA round:
   ```bash
   eval "$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/debug-session-state.sh increment-qa .vbw-planning)"
   ```

3. Resolve tier: same logic as Step 1 below (--tier flag > --effort flag > config default > Standard).

4. Resolve QA model:
   ```bash
   QA_MODEL=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh qa .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
   if [ $? -ne 0 ]; then echo "$QA_MODEL" >&2; exit 1; fi
   QA_MAX_TURNS=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-max-turns.sh qa .vbw-planning/config.json "$QA_EFFORT_PROFILE")
   if [ $? -ne 0 ]; then echo "$QA_MAX_TURNS" >&2; exit 1; fi
   ```

5. Spawn vbw-qa as subagent via Task tool for debug-session verification. **Set `subagent_type: "vbw:vbw-qa"` and `model: "${QA_MODEL}"` in the Task tool invocation. If `QA_MAX_TURNS` is non-empty, also pass `maxTurns: ${QA_MAX_TURNS}`.**

   Task description for debug-session QA:
   ```text
   Debug session verification. Tier: {ACTIVE_TIER}. Round: {qa_round}.

   This is a debug-session QA round, NOT a phase-scoped verification. You are verifying
   a standalone debug fix — there are no phase PLAN.md or SUMMARY.md files.

   Session context (issue, investigation, plan, implementation, prior QA rounds):
   {QA_CONTEXT}

   Verification targets:
   - The root cause identified in the investigation is correct
   - The fix addresses the root cause (not just the symptom)
   - Changed files are correct and complete
   - No regressions introduced in modified files
   - Related tests pass

   Output your verdict as PASS, FAIL, or PARTIAL with a checks table.
   Do NOT use write-verification.sh — return your verdict inline as structured text.
   Format each check as: ID | Description | Status (PASS/FAIL) | Evidence
   ```

6. Process the QA result:
   - Parse the verdict (PASS/FAIL/PARTIAL) from the QA agent's response.
   - Write the QA round to the session file:
     ```bash
     QA_RESULT_JSON=$(cat <<'ENDJSON'
     {
       "mode": "qa",
       "round": {qa_round},
       "result": "{PASS|FAIL|PARTIAL}",
       "checks": [
         {"id": "{check-id}", "description": "{check description}", "status": "{PASS|FAIL}", "evidence": "{evidence}"}
       ]
     }
     ENDJSON
     )
     echo "$QA_RESULT_JSON" | bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/write-debug-session.sh "$session_file"
     ```
   - Update session status based on result:
     - PASS → `bash .../debug-session-state.sh set-status .vbw-planning uat_pending`
     - FAIL or PARTIAL → `bash .../debug-session-state.sh set-status .vbw-planning qa_failed`

7. Present debug-session QA result:
   ```text
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Debug QA: Round {qa_round}
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

     Session:  {session_id}
     Tier:     {quick|standard|deep}
     Result:   {✓ PASS | ✗ FAIL | ◆ PARTIAL}
     Checks:   {passed}/{total}
     Failed:   {list or "None"}

   ```
   - If PASS: `➜ Next: /vbw:verify --session -- Run UAT on the debug fix`
   - If FAIL/PARTIAL: `➜ Next: /vbw:debug --resume -- Address QA failures and re-investigate`

   STOP after presenting. Do not continue to the standard phase QA steps.
</debug_session_qa>

Note: Continuous verification handled by hooks. This command is for deep, on-demand verification only.

## Steps
1. **Resolve tier:** Priority order: `--tier` flag > `--effort` flag > config
  default > Standard.
  Keep effort profile as `QA_EFFORT_PROFILE` (thorough|balanced|fast|turbo).
  Effort mapping: turbo=skip (exit "QA skipped in turbo mode"), fast=quick,
  balanced=standard, thorough=deep.
  Read ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/effort-profile-{profile}.md`.
  Context overrides: >15 requirements or last phase before ship → Deep.

2. **Resolve phase:** Use `.vbw-planning/phases/` for phase directories.

3. **Spawn QA:**
    - Resolve QA model:

        ```bash
        QA_MODEL=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh qa .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
        if [ $? -ne 0 ]; then echo "$QA_MODEL" >&2; exit 1; fi
        QA_MAX_TURNS=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-max-turns.sh qa .vbw-planning/config.json "$QA_EFFORT_PROFILE")
        if [ $? -ne 0 ]; then echo "$QA_MAX_TURNS" >&2; exit 1; fi
        ```

    - Display: `◆ Spawning QA agent (${QA_MODEL})...`
    - Resolve the VERIFICATION output path before spawning QA:

        ```bash
        QA_STATE=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/qa-remediation-state.sh get "{phase-dir}" 2>/dev/null || true)
        QA_STAGE=$(printf '%s\n' "$QA_STATE" | head -1)
        VERIF_PATH=$(printf '%s\n' "$QA_STATE" | awk -F= '/^verification_path=/{print $2; exit}')
        case "$QA_STAGE" in
          verify) ;;
          done)
            VERIF_PATH=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-verification-path.sh current "{phase-dir}" 2>/dev/null || true)
            [ -n "$VERIF_PATH" ] && [ ! -f "$VERIF_PATH" ] && VERIF_PATH=""
            if [ -z "$VERIF_PATH" ] || [ ! -f "$VERIF_PATH" ]; then
              echo "Phase {NN} QA remediation is done, but the round-scoped VERIFICATION artifact is missing. Re-run /vbw:vibe to restore the remediation artifact before standalone QA." >&2
              exit 1
            fi
            ;;
          plan|execute)
            echo "Phase {NN} has active QA remediation at stage ${QA_STAGE}. Run /vbw:vibe to continue remediation before standalone QA." >&2
            exit 1
            ;;
          *) VERIF_PATH="" ;;
        esac
        if [ -z "$VERIF_PATH" ]; then
          VERIF_NAME=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-artifact-path.sh verification "{phase-dir}")
          VERIF_PATH="{phase-dir}/${VERIF_NAME}"
        fi
        if [ ! -f "$VERIF_PATH" ]; then
          bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/track-known-issues.sh sync-summaries "{phase-dir}" 2>/dev/null || true
        fi
        ```

      The guarded `sync-summaries` backfill above is for resumed phase-level QA only. It closes the interruption window where execution completed and `SUMMARY.md` files exist, but the earlier session ended before the post-build QA handoff created `{phase-dir}/known-issues.json`.

    - Before composing the QA task description, evaluate installed skills visible in your system context — read each skill's description and determine if it is relevant to verifying this phase's work. The QA prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each relevant skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills apply, or `<skill_no_activation>Evaluated installed skills for this task. No installed skills apply. Reason: {brief task-specific reason}.</skill_no_activation>` when none apply. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none apply — {reason}") so the user has visibility before the agent is spawned. Only include skills whose description matches the verification task.

    - Also evaluate available MCP tools in your system context. If any MCP servers provide build, test, documentation, or domain-specific capabilities relevant to verification, note them in the QA task context.

    - Spawn vbw-qa as subagent via Task tool. **Set `subagent_type: "vbw:vbw-qa"` and `model: "${QA_MODEL}"` in
      the Task tool invocation. If `QA_MAX_TURNS` is non-empty, also pass
      `maxTurns: ${QA_MAX_TURNS}`. If `QA_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).**

        ```text
        Verify phase {NN}. Tier: {ACTIVE_TIER}.
        Determine verification scope from `VERIF_PATH`.
        - If `VERIF_PATH` is under `remediation/qa/round-*/R*-VERIFICATION.md`, re-verify the remediation round using compounded remediation context.
          - Run `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/compile-verify-context.sh --remediation-only "{phase-dir}"` and use its `VERIFICATION HISTORY` section to re-verify each original FAIL from the source VERIFICATION.
          - Plans for `plans_verified` / `plan_ref`: {current round R{RR}-PLAN.md path(s) only}
          - Summaries for current-round execution evidence: {current round R{RR}-SUMMARY.md path(s) only}
          - Do NOT include phase-root PLAN.md/SUMMARY.md files in plans_verified or plan_ref for round-scoped output.
          - Any original FAIL not resolved by code-fix, plan-amendment, or documented process-exception is still a FAIL, even if the remediation round's own must_haves pass.
        - Otherwise, verify full phase scope.
          - Plans: {paths to phase PLAN.md files}
          - Summaries: {paths to phase SUMMARY.md files}
          - If `{phase-dir}/known-issues.json` exists, read it as the authoritative tracked phase backlog. Re-check those known issues during this QA run and return only the ones that still remain unresolved in `pre_existing_issues`.
        Phase success criteria: {section from ROADMAP.md}
        If `.vbw-planning/codebase/META.md` exists, read CONVENTIONS.md, TESTING.md, CONCERNS.md, and ARCHITECTURE.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before verifying.
        Verification protocol: `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/verification-protocol.md
        Return findings using the qa_verdict schema (see `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/handoff-schemas.md).
        If tests reveal pre-existing failures unrelated to this phase, list them in your response under a "Pre-existing Issues" heading and include them in the qa_verdict payload's pre_existing_issues array.
        Persist your VERIFICATION.md by piping qa_verdict JSON through write-verification.sh. Output path: {VERIF_PATH}. Plugin root: `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`.
        ```

    - QA agent reads all files and persists VERIFICATION.md itself. If QA reports a `write-verification.sh` failure, surface the error to the user — do NOT fall back to manual VERIFICATION.md writes.

4. **Reconcile with the deterministic QA gate before trusting the result:**
    - Immediately after QA persists `VERIFICATION.md`, sync tracked known issues from the written artifact:

      ```bash
      bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/track-known-issues.sh sync-verification "{phase-dir}" "{VERIF_PATH}" 2>/dev/null || true
      ```

      After sync-verification, auto-promote surviving known issues to `STATE.md ## Todos`:

      ```bash
      bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/track-known-issues.sh promote-todos "{phase-dir}" 2>/dev/null || true
      ```

      Phase-level `VERIFICATION.md` merges newly found pre-existing issues into `{phase-dir}/known-issues.json` without clearing the execution-time backlog. Round-scoped `R{RR}-VERIFICATION.md` is authoritative for unresolved known issues and prunes/clears the registry when issues are fixed.

    - Then run:

      ```bash
      QA_GATE=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/qa-result-gate.sh "{phase-dir}" 2>/dev/null || true)
      QA_GATE_ROUTING=$(printf '%s\n' "$QA_GATE" | awk -F= '/^qa_gate_routing=/{print $2; exit}')
      ```

    - Follow `QA_GATE_ROUTING` literally:
      - `PROCEED_TO_UAT` → if `VERIF_PATH` is round-scoped (`remediation/qa/round-*/R*-VERIFICATION.md`), persist the remediation transition first:

        ```bash
        bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/qa-remediation-state.sh advance "{phase-dir}"
        ```

        Then continue to presentation.
      - `REMEDIATION_REQUIRED` → if `VERIF_PATH` is round-scoped (`remediation/qa/round-*/R*-VERIFICATION.md`), persist the next remediation round first:

        ```bash
        bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/qa-remediation-state.sh needs-round "{phase-dir}"
        ```

        Then display that standalone QA found a result, but the deterministic gate still requires remediation; tell the user to continue via `/vbw:vibe`. Do **not** present the round as a shippable PASS. If `qa_gate_known_issues_override=true`, note that the contract checks passed but `{qa_gate_known_issue_count}` tracked known issues remain unresolved in `{phase-dir}/known-issues.json`.
      - `REMEDIATION_REQUIRED` → if `VERIF_PATH` is phase-level, initialize QA remediation state first so plain `/vbw:vibe` has a deterministic resume target:

        ```bash
        bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/qa-remediation-state.sh init "{phase-dir}" 2>/dev/null || true
        ```

        Then display that the phase-level QA result was written, but the deterministic gate still requires remediation; tell the user to continue via `/vbw:vibe`. Do **not** continue to the generic verified presentation. If `qa_gate_known_issues_override=true`, note that the contract checks passed but `{qa_gate_known_issue_count}` tracked known issues remain unresolved in `{phase-dir}/known-issues.json`.
      - `QA_RERUN_REQUIRED` → display that the persisted verification artifact is invalid or incomplete and must be re-run before it can be trusted. Do **not** present it as authoritative.

5. **Present:** Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
    ```text
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Phase {NN}: {name} -- Verified
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      Tier:     {quick|standard|deep}
      Result:   {✓ PASS | ✗ FAIL | ◆ PARTIAL}
      Checks:   {passed}/{total}
      Failed:   {list or "None"}

      Report:   {path to VERIFICATION.md}

    ```

**Discovered Issues:** If the QA agent reported pre-existing failures, out-of-scope bugs, or issues unrelated to this phase's work, de-duplicate by test name and file (keep first error message when the same test+file pair has different messages) and append after the result box. Cap the list at 20 entries; if more exist, show the first 20 and append `... and {N} more`:
```text
  Discovered Issues:
    ⚠ testName (path/to/file): error message
    ⚠ testName (path/to/file): error message
  Registry: {phase-dir}/known-issues.json
```
This display is supplemental to the phase registry. After `VERIFICATION.md` is written, the orchestrator must sync these issues into `{phase-dir}/known-issues.json` before reading the deterministic gate. Do NOT create todos automatically or enter an interactive loop here. If no discovered issues: omit the section entirely. After displaying discovered issues, STOP. Do not take further action.

Run:
```text
bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/suggest-next.sh qa {result}
```
Then display the output.

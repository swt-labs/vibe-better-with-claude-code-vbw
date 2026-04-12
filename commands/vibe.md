---
name: vbw:vibe
category: lifecycle
description: "The one command. Detects state, parses intent, routes to any lifecycle mode -- bootstrap, scope, plan, execute, verify, discuss, archive, and more."
argument-hint: "[intent or flags] [--plan] [--execute] [--verify] [--discuss] [--assumptions] [--scope] [--add] [--insert] [--remove] [--archive] [--yolo] [--effort=level] [--skip-qa] [--skip-audit] [--plan=NN] [N]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch, WebSearch, AskUserQuestion, Agent, TeamCreate, TaskCreate, SendMessage, TeamDelete, Skill, LSP
disable-model-invocation: true
---

# VBW Vibe: $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; SESSION_LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ] && [ -f "${SESSION_LINK}/scripts/hook-wrapper.sh" ]; then R="${SESSION_LINK}"; fi; if [ -z "$R" ]; then ANY_LINK=$(command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r link; do if [ -f "$link/scripts/hook-wrapper.sh" ]; then printf '%s\n' "$link"; break; fi; done || true); [ -n "$ANY_LINK" ] && R="$ANY_LINK"; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; LINK="${SESSION_LINK}"; P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; PTMP="${P}.tmp.$$"; LOCK="/tmp/.vbw-phase-detect-live-${SESSION_KEY}.lock"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || { echo "VBW: plugin root canonicalization failed" >&2; exit 1; }; bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$LINK" "$REAL_R" >/dev/null 2>&1 || { echo "VBW: plugin root link failed" >&2; exit 1; }; LOCKED=false; i=0; while [ $i -lt 100 ]; do if mkdir "$LOCK" 2>/dev/null; then LOCKED=true; break; fi; sleep 0.1; i=$((i+1)); done; if [ "$LOCKED" = true ]; then bash "$LINK/scripts/phase-detect.sh" > "$PTMP" 2>/dev/null || printf '%s\n' 'phase_detect_error=true' > "$PTMP"; mv "$PTMP" "$P"; rmdir "$LOCK" 2>/dev/null || true; else j=0; while [ $j -lt 100 ]; do [ -f "$P" ] && break; sleep 0.1; j=$((j+1)); done; [ -f "$P" ] || { printf '%s\n' 'phase_detect_error=true' > "$PTMP"; mv "$PTMP" "$P"; }; fi; echo "$LINK"`
```

Pre-computed state (via phase-detect.sh):
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"
P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"
PD=""
_PD_START_TS=$(date +%s 2>/dev/null || echo 0)
_phase_detect_cache_fresh() {
  local m=""
  [ -f "$P" ] || return 1
  m=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo "")
  [ -n "$m" ] || return 1
  [ "$m" -ge "$_PD_START_TS" ] 2>/dev/null
}
i=0
while [ $i -lt 100 ]; do
  if _phase_detect_cache_fresh; then
    PD=$(cat "$P")
    break
  fi
  sleep 0.1
  i=$((i+1))
done
if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ]; then
  LOCK="/tmp/.vbw-phase-detect-live-${SESSION_KEY}.lock"
  i=0
  while [ $i -lt 100 ]; do
    if _phase_detect_cache_fresh; then
      PD=$(cat "$P")
      break
    fi
    if mkdir "$LOCK" 2>/dev/null; then
      PTMP="${P}.reader.$$.$RANDOM"
      PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""
      if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ]; then
        printf '%s\n' "$PD" > "$PTMP" 2>/dev/null && mv "$PTMP" "$P" 2>/dev/null || true
      fi
      rmdir "$LOCK" 2>/dev/null || true
      break
    fi
    sleep 0.1
    i=$((i+1))
  done
fi
[ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && _phase_detect_cache_fresh && PD=$(cat "$P")
if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then
  printf '%s' "$PD"
else
  echo "phase_detect_error=true"
fi`
```

Config:
```
!`cat .vbw-planning/config.json 2>/dev/null || echo "No config found"`
```

Milestone UAT issues (milestone recovery only):
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"
P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"
PD=""
_PD_START_TS=$(date +%s 2>/dev/null || echo 0)
_phase_detect_cache_fresh() {
  local m=""
  [ -f "$P" ] || return 1
  m=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo "")
  [ -n "$m" ] || return 1
  [ "$m" -ge "$_PD_START_TS" ] 2>/dev/null
}
i=0
while [ $i -lt 100 ]; do
  if _phase_detect_cache_fresh; then
    PD=$(cat "$P")
    break
  fi
  sleep 0.1
  i=$((i+1))
done
if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ]; then
  LOCK="/tmp/.vbw-phase-detect-live-${SESSION_KEY}.lock"
  i=0
  while [ $i -lt 100 ]; do
    if _phase_detect_cache_fresh; then
      PD=$(cat "$P")
      break
    fi
    if mkdir "$LOCK" 2>/dev/null; then
      PTMP="${P}.reader.$$.$RANDOM"
      PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""
      if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ]; then
        printf '%s\n' "$PD" > "$PTMP" 2>/dev/null && mv "$PTMP" "$P" 2>/dev/null || true
      fi
      rmdir "$LOCK" 2>/dev/null || true
      break
    fi
    sleep 0.1
    i=$((i+1))
  done
fi
[ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && _phase_detect_cache_fresh && PD=$(cat "$P")
if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then
  echo "milestone_extract_unavailable=true"
  exit 0
fi
if printf '%s' "$PD" | grep -q '^---MILESTONE_UAT_EXTRACT_START---$'; then
  printf '%s\n' "$PD" | awk '/^---MILESTONE_UAT_EXTRACT_START---$/{f=1; next} /^---MILESTONE_UAT_EXTRACT_END---$/{exit} f{print}'
else
  MS_UAT=$(printf '%s' "$PD" | grep '^milestone_uat_issues=' | head -1 | cut -d= -f2)
  if [ "$MS_UAT" = "true" ]; then
    echo "milestone_extract_unavailable=true"
  else
    echo "not_milestone_recovery"
  fi
fi`
```

Verify context (verify routing only — needs_reverification OR needs_verification):
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"
P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"
PD=""
_PD_START_TS=$(date +%s 2>/dev/null || echo 0)
_phase_detect_cache_fresh() {
  local m=""
  [ -f "$P" ] || return 1
  m=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo "")
  [ -n "$m" ] || return 1
  [ "$m" -ge "$_PD_START_TS" ] 2>/dev/null
}
i=0
while [ $i -lt 100 ]; do
  if _phase_detect_cache_fresh; then
    PD=$(cat "$P")
    break
  fi
  sleep 0.1
  i=$((i+1))
done
if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ]; then
  LOCK="/tmp/.vbw-phase-detect-live-${SESSION_KEY}.lock"
  i=0
  while [ $i -lt 100 ]; do
    if _phase_detect_cache_fresh; then
      PD=$(cat "$P")
      break
    fi
    if mkdir "$LOCK" 2>/dev/null; then
      PTMP="${P}.reader.$$.$RANDOM"
      PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""
      if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ]; then
        printf '%s\n' "$PD" > "$PTMP" 2>/dev/null && mv "$PTMP" "$P" 2>/dev/null || true
      fi
      rmdir "$LOCK" 2>/dev/null || true
      break
    fi
    sleep 0.1
    i=$((i+1))
  done
fi
[ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && _phase_detect_cache_fresh && PD=$(cat "$P")
if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then
  echo "verify_context=unavailable"
else
  STATE=$(printf '%s' "$PD" | grep '^next_phase_state=' | head -1 | cut -d= -f2)
  AUTO_UAT=$(printf '%s' "$PD" | grep '^config_auto_uat=' | head -1 | cut -d= -f2)
  HAS_UV=$(printf '%s' "$PD" | grep '^has_unverified_phases=' | head -1 | cut -d= -f2)
  TARGET=""
  if [ "$STATE" = "needs_reverification" ] || [ "$STATE" = "needs_verification" ]; then
    TARGET=$(printf '%s' "$PD" | grep '^next_phase_slug=' | head -1 | cut -d= -f2)
  elif [ "$AUTO_UAT" = "true" ] && [ "$HAS_UV" = "true" ]; then
    TARGET=$(printf '%s' "$PD" | grep '^first_unverified_slug=' | head -1 | cut -d= -f2)
  fi
  if [ -n "$TARGET" ]; then
    PDIR=".vbw-planning/phases/$TARGET"
    echo "verify_target_slug=$TARGET"
    if [ -d "$PDIR" ] && [ -L "$L" ] && [ -f "$L/scripts/compile-verify-context-for-uat.sh" ]; then
      bash "$L/scripts/compile-verify-context-for-uat.sh" "$PDIR" 2>/dev/null || echo "verify_context_error=true"
    else
      echo "verify_context_error=true"
    fi
    echo "---"
    if [ "$STATE" = "needs_reverification" ]; then
      echo "uat_resume=pending_archive"
    elif [ "$STATE" = "needs_verification" ]; then
      if [ -d "$PDIR" ] && [ -L "$L" ] && [ -f "$L/scripts/extract-uat-resume.sh" ]; then
        bash "$L/scripts/extract-uat-resume.sh" "$PDIR" 2>/dev/null || echo "uat_resume=none"
      else
        echo "uat_resume=none"
      fi
    elif [ -d "$PDIR" ] && [ -L "$L" ] && [ -f "$L/scripts/extract-uat-resume.sh" ]; then
      bash "$L/scripts/extract-uat-resume.sh" "$PDIR" 2>/dev/null || echo "uat_resume=error"
    else
      echo "uat_resume=error"
    fi
  else
    echo "verify_context=unavailable"
  fi
fi`
```

!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; bash "$L/scripts/suggest-compact.sh" execute 2>/dev/null || true`

## Input Parsing

Three input paths, evaluated in order:

### Path 1: Flag detection

Check $ARGUMENTS for flags. If any mode flag is present, go directly to that mode:
- `--plan [N]` -> Plan mode
- `--execute [N]` -> Execute mode
- `--discuss [N]` -> Discuss mode
- `--assumptions [N]` -> Assumptions mode
- `--scope` -> Scope mode
- `--add "desc"` -> Add Phase mode
- `--insert N "desc"` -> Insert Phase mode
- `--remove N` -> Remove Phase mode
- `--verify [N]` -> Verify mode
- `--archive` -> Archive mode

Behavior modifiers (combinable with mode flags):
- `--effort <level>`: thorough|balanced|fast|turbo (overrides config)
- `--skip-qa`: skip post-build QA
- `--skip-audit`: skip non-UAT pre-archive audit checks (hard UAT gate still enforced)
- `--yolo`: skip all confirmation gates, auto-loop remaining phases
- `--plan=NN`: execute single plan (bypasses wave grouping)
- Bare integer `N`: targets phase N (works with any mode flag)

If flags present: skip confirmation gate (flags express explicit intent).

### Path 2: Natural language intent

If $ARGUMENTS present but no flags detected, interpret user intent:
- Discussion keywords (talk, discuss, explore, think about, what about) -> Discuss mode
- Assumption keywords (assume, assuming, what if, what are you assuming) -> Assumptions mode
- Planning keywords (plan, scope, break down, decompose, structure) -> Plan mode
- Execution keywords (build, execute, run, do it, go, make it, ship it) -> Execute mode
- Verification keywords (verify, test, uat, check my work, acceptance test, walk through) -> Verify mode
- Phase mutation keywords (add, insert, remove, skip, drop, new phase) -> relevant Phase Mutation mode
- Completion keywords (done, ship, archive, wrap up, finish, complete) -> Archive mode
- Ambiguous -> AskUserQuestion with 2-3 contextual options

ALWAYS call AskUserQuestion to confirm interpreted intent before executing.

### Path 3: State detection (no args)

If no $ARGUMENTS, evaluate phase-detect.sh output. First match determines mode:

**Phase-detect error guard (NON-NEGOTIABLE):** If the output contains `phase_detect_error=true`, display:
"⚠ Phase detection failed. Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/phase-detect.sh` manually to debug."
STOP. Do NOT manually scan for project state or improvise routing — incorrect routing can corrupt archived milestones.

**Misnamed plan auto-repair:** If the output contains `misnamed_plans=true`, normalize all phase directories before routing:
```bash
NORM_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
if [ -f "$NORM_SCRIPT" ]; then
  for pdir in .vbw-planning/phases/*/; do
    [ -d "$pdir" ] && bash "$NORM_SCRIPT" "$pdir"
  done
fi
```
Display: "⚠ Renamed misnamed plan files to `{NN}-PLAN.md` convention."
Then re-run phase-detect.sh and use updated output for routing below.

**State-driven routing prohibition (NON-NEGOTIABLE):** When state detection routes to a mode, call its confirmation gate (AskUserQuestion — see Confirmation Gate section below) in the same turn, then execute the mode inline after the user responds. Do NOT use TaskCreate, TaskUpdate, or any task management tool for state-driven routing — these add overhead and delay execution. State routing is deterministic: the pre-computed data in the Context section above provides all routing information. Do not spawn tasks or read protocol files for routing decisions. After confirmation (when required by the routing table), execute the mode inline. Modes that spawn agents (Scout, Lead, Dev) do so within their step-by-step flow — this is delegation of work units within a stage, not delegation of the stage pipeline itself.

<examples>
<example type="anti-pattern" label="WRONG — delegating the stage pipeline via TaskCreate">
State detects needs_uat_remediation → TaskCreate("Research"), TaskCreate("Plan"), TaskCreate("Execute") with blocking dependencies → stages run as separate delegated tasks, breaking state management and losing orchestrator control between stages
</example>
<example type="correct" label="RIGHT — inline orchestration with agent spawning per stage">
State detects needs_uat_remediation → enters mode inline → step 4 creates TodoWrite progress list (Research, Plan, Execute) → step 6 spawns Scout for research stage via Task tool → advances state → spawns Lead for plan stage → advances → spawns Dev for execute stage → chains into re-verification
</example>
</examples>

| Priority | Condition | Mode | Confirmation |
| --- | --- | --- | --- |
| 1 | `planning_dir_exists=false` | Init redirect | (redirect, no confirmation) |
| 2 | `project_exists=false` | Bootstrap | → AskUserQuestion: "No project defined. Set one up?" |
| 3 | `next_phase_state=needs_uat_remediation` | UAT Remediation | auto_uat=true: no confirmation. auto_uat=false: → AskUserQuestion: "Phase {NN} has unresolved UAT issues. Continue with remediation now?" |
| 3.5 | `next_phase_state=needs_qa_remediation` | QA Remediation | auto_uat=true: no confirmation. auto_uat=false: → AskUserQuestion: "Phase {NN} has QA failures. Continue with QA remediation?" |
| 4 | `next_phase_state=needs_reverification` | Re-verify | auto_uat=true: no confirmation. auto_uat=false: → AskUserQuestion: "Phase {NN} remediation complete. Run re-verification?" |
| 5 | `milestone_uat_issues=true` | Milestone UAT Recovery | (mode handles confirmation — see Milestone UAT Recovery steps) |
| 6 | `phase_count=0` | Scope | → AskUserQuestion: "Project defined but no phases. Scope the work?" |
| 7 | `next_phase_state=needs_verification` | Verify | (no confirmation — auto_uat intent). **QA gate:** If `qa_status=pending`, display "Phase {NN} QA is pending — running QA now." and spawn QA inline first (see QA Gate section below). This state also covers `all_done` milestones that were retargeted because authoritative QA on a completed phase is stale/missing, plus fully built no-UAT phases retargeted back into verification when QA is still pending even with `auto_uat=false`. If `qa_status=failed`, enter QA remediation inline. Only proceed to Verify mode when `qa_status` is `passed` or `remediated`. |
| 8 | `next_phase_state=needs_discussion` | Discuss | → AskUserQuestion: "Phase {NN} needs discussion before planning. Start discussion?" |
| 9 | `next_phase_state=needs_plan_and_execute` | Plan + Execute | → AskUserQuestion: "Phase {NN} needs planning and execution. Start?" |
| 10 | `next_phase_state=needs_execute` | Execute | → AskUserQuestion: "Phase {NN} is planned. Execute it?" |
| 11 | `next_phase_state=all_done` | Archive | → AskUserQuestion: "All phases complete. Run audit and archive?" (only when no `first_qa_attention_phase` remains) |

**all_done QA-attention fallback (pending):** When `next_phase_state=all_done`, `first_qa_attention_phase` is set, and `qa_attention_status=pending`, do **not** archive yet. Target `first_qa_attention_phase` / `first_qa_attention_slug` and continue into Verify mode instead. This is the stage-less resume path for a completed phase whose QA verification is still missing or stale, even when `auto_uat=false`.

**Earlier-work QA-attention fallback (failed):** When `next_phase_state` is still an earlier-work state (`needs_discussion`, `needs_plan_and_execute`, or `needs_execute`), but `first_qa_attention_phase` is set and `qa_attention_status=failed`, do **not** continue into that unrelated earlier work. Target `first_qa_attention_phase` / `first_qa_attention_slug` and continue into the existing QA Remediation mode instead. This is the stage-less resume path for a completed phase that already has phase-level QA findings and a persisted known-issues backlog, but has not written `.qa-remediation-stage` yet.

**QA remediation resume priority (needs_qa_remediation) — IMMEDIATE RESUME (NON-NEGOTIABLE):**
Persisted QA remediation / known-issues backlog is the authoritative plain `/vbw:vibe` resume target. When `next_phase_state=needs_qa_remediation`, do **not** skip ahead to unrelated earlier discussion, planning, or execution work — close the QA backlog first, unless an active UAT remediation path is already higher priority.

**Re-verify after remediation (needs_reverification) — IMMEDIATE EXECUTION (NON-NEGOTIABLE):**
When `next_phase_state=needs_reverification`, execute these steps inline in the same turn — do NOT create tasks, read protocol files, or perform any intermediate planning:
1. Run: `bash {plugin-root}/scripts/prepare-reverification.sh {phase-dir}`
2. **Error guard:** If the script fails (non-zero exit), display the error message and **STOP** — do not attempt to enter Verify mode with stale/missing context.
3. Parse output: `archived=kept|in-round-dir|already_archived|ready_for_verify`, `round_file=...`, `phase=NN`, `layout=...`
4. If `archived=kept`: display "Phase UAT preserved. Starting fresh re-verification in round dir."
   If `archived=in-round-dir`: display "Archived previous UAT → {round_file}. Starting fresh re-verification."
   If `skipped=already_archived`: display "UAT already archived. Starting fresh re-verification."
   If `skipped=ready_for_verify`: display "Round {NN} remediation complete. Starting fresh re-verification."
5. Refresh verify context and UAT resume metadata for that phase:
  ```bash
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-verify-context-for-uat.sh "{phase-dir}"
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/extract-uat-resume.sh "{phase-dir}"
  ```
  Use this refreshed output in place of the pre-computed verify blocks from Context.
  **uat_path validation (defense-in-depth):** If the refreshed `uat_path` does not already point at the current remediation round's round-scoped UAT path (`remediation/uat/round-{RR}/R{RR}-UAT.md` for round-dir layout, `remediation/round-{RR}/R{RR}-UAT.md` for legacy layout), run:
  ```bash
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh get-or-init "{phase-dir}" major
  ```
  Parse `round=RR` and `layout=...`, then override `uat_path` with the matching round-scoped path for that layout before entering Verify mode.
6. **Continue directly into Verify mode below** for that phase — do NOT stop, do NOT tell the user to run a separate command.

The `needs_reverification` state fires regardless of `auto_uat` — remediation always requires re-verification. The `auto_uat` flag only controls whether the user is prompted for confirmation.

**auto_uat verification (needs_verification):** When `next_phase_state=needs_verification`, **continue directly into Verify mode below** targeting phase `{next_phase}` (from phase-detect output) — do NOT stop and tell the user to run a separate command. Verify mode runs the CHECKPOINT loop **inline in this conversation** via AskUserQuestion — do NOT spawn a QA agent or any subagent for UAT (see Verify mode's inline execution rule). This state fires when `auto_uat=true` and a completed phase has no UAT verification yet, regardless of whether later phases still need work. After verification completes, the next `/vbw:vibe` call re-runs phase-detect and routes to the next pending phase.

**QA gate before UAT (needs_verification) — NON-NEGOTIABLE:**
Before entering Verify mode (UAT), check `qa_status` from phase-detect output:
- `qa_status=passed` or `qa_status=remediated`: proceed to Verify mode (UAT). These values mean VERIFICATION.md exists with PASS and the product code has not changed since QA verified it (staleness check via `verified_at_commit`).
- `qa_status=pending` (no VERIFICATION.md, or VERIFICATION.md exists but code changed since QA verified — stale): display "Phase {NN} QA is pending — running QA now." and spawn QA inline first. Resolve QA model, compile QA context, and spawn the QA agent as a subagent (same as execute-protocol Step 4). After QA returns, run the deterministic gate:
  - If the phase-level verification artifact does not yet exist, backfill tracked known issues from completed summaries before QA starts:
    ```bash
    bash "${VBW_PLUGIN_ROOT}/scripts/track-known-issues.sh" sync-summaries "{phase-dir}" 2>/dev/null || true
    ```
    This backfill is only for the first phase-level QA run after execution. Do not reuse it for round-scoped remediation verification or generic stale-verification reruns.
  ```bash
  bash "${VBW_PLUGIN_ROOT}/scripts/track-known-issues.sh" sync-verification "{phase-dir}" "{QA-output-path}" 2>/dev/null || true
  ```
  After sync-verification, auto-promote surviving known issues to `STATE.md ## Todos`:
  ```bash
  bash "${VBW_PLUGIN_ROOT}/scripts/track-known-issues.sh" promote-todos "{phase-dir}" 2>/dev/null || true
  ```
  Then run the deterministic gate:
  ```bash
  bash "${VBW_PLUGIN_ROOT}/scripts/qa-result-gate.sh" "{phase-dir}"
  ```
  **Follow `qa_gate_routing` output literally — no exceptions, no judgment, no rationalization. Do NOT evaluate whether failures are justified, acceptable, or minor. The gate script has already made the decision:**
  - `qa_gate_routing=PROCEED_TO_UAT` → proceed to Verify mode (UAT)
  - `qa_gate_routing=REMEDIATION_REQUIRED` → init QA remediation: `bash {plugin-root}/scripts/qa-remediation-state.sh init {phase-dir}`, then enter QA Remediation mode below. If `qa_gate_known_issues_override=true`, the contract verification passed but `{qa_gate_known_issue_count}` unresolved tracked known issues remain in `{phase-dir}/known-issues.json`.
  - `qa_gate_routing=QA_RERUN_REQUIRED` → re-spawn QA agent immediately (max 2 retries). If `qa_gate_deviation_override=true`, tell QA: "Previous QA run found PASS but SUMMARY.md files contain {qa_gate_deviation_count} deviations that were not reflected as FAIL checks. Each deviation MUST become a FAIL check — do not rationalize deviations as acceptable." If `qa_gate_plan_coverage` is present, tell QA: "Previous QA run only verified {qa_gate_plans_verified_count}/{qa_gate_plan_count} plans. Every plan in the phase must be verified — include all plan IDs in plans_verified." If QA fails to produce a valid result after 2 re-runs, STOP and escalate to user: "QA failed to produce a valid VERIFICATION.md after {N} attempts. Manual intervention needed."
- `qa_status=failed` (VERIFICATION.md exists with FAIL/PARTIAL): init QA remediation and enter QA Remediation mode
- `qa_status=remediating`: should not reach here (phase-detect routes to `needs_qa_remediation` first)
- `--skip-qa` flag: bypass contract-QA execution, but **do not** bypass unresolved phase known issues. UAT still cannot proceed while `{phase-dir}/known-issues.json` contains tracked issues.

**QA Remediation mode (needs_qa_remediation) — cross-session recovery:**
When `next_phase_state=needs_qa_remediation`, resume QA remediation at the persisted stage. This is the cross-session recovery path — the inline execution path is in execute-protocol.md Step 4. This state also covers completed phases with no UAT yet when phase-level QA already wrote a PASS artifact but unresolved tracked known issues still force remediation before UAT can begin.

**Execution model:** This mode runs inline — the orchestrator manages stage transitions and spawns agents for the actual work within each stage. Do not decompose the stages into TaskCreate items — they are sequential steps of this conversation, not delegated tasks.

1. Read current state: `bash {plugin-root}/scripts/qa-remediation-state.sh get-or-init {phase-dir}`
  Parse output: `stage`, `round`, `round_dir`, `source_verification_path`, `source_fail_count`, `known_issues_path`, `known_issues_count`, `input_mode`, `verification_path`
   If remediation state was absent, `get-or-init` initializes round 01 before stage-specific routing. This is the deterministic stage-less resume path for a persisted known-issues backlog.
2. Read remediation inputs.
- Round 01: phase-level VERIFICATION (`{NN}-VERIFICATION.md` or brownfield `VERIFICATION.md`)
- Round 02+: previous round's `R{RR}-VERIFICATION.md`
- If `known_issues_count>0`, read `known_issues_path` as the authoritative unresolved known-issues backlog for this phase.
- `input_mode=verification` → remediate FAIL rows only
- `input_mode=known-issues` → remediate tracked known issues only
- `input_mode=both` → remediate both FAIL rows and tracked known issues in the same round

**Stage-specific actions:**

- **stage=plan:** Create `R{RR}-PLAN.md` in `{round_dir}`:
  - Read `source_verification_path` failed checks when `source_fail_count>0` — these are the current contract issues to fix
  - Read `known_issues_path` when `known_issues_count>0` — these tracked phase issues must clear before UAT can proceed
    - Round 01 uses the phase-level VERIFICATION (`{NN}-VERIFICATION.md` or brownfield `VERIFICATION.md`).
    - Round 02+ first checks the previous round's `R{RR}-VERIFICATION.md`. If that artifact still contains FAIL checks, use it. If it passed QA but the deterministic gate still required another remediation round, carry forward the nearest earlier verification artifact in the remediation chain that still contains the unresolved FAILs.
    - If `source_verification_path` is empty and `known_issues_count=0`, STOP and restore the earlier verification artifact that should have carried the unresolved FAILs before planning. Do NOT silently continue when the carried-forward phase-level source artifact is missing and there is no known-issues backlog to remediate.
  - **Deviation Classification (NON-NEGOTIABLE):** For each FAIL check in the source VERIFICATION.md, classify as exactly one of:
    - **`code-fix`**: The code/config must change to match the plan. The remediation plan MUST include tasks that modify the executable/config/test artifacts that actually implement the fix — not just planning or documentation files.
    - **`plan-amendment`**: The deviation was a valid improvement over the original plan. The remediation plan MUST include a task to update the original PLAN.md with the actual approach and rationale, marking the deviation as resolved-by-amendment.
    - **`process-exception`**: Genuinely non-fixable retroactive issue (e.g., cannot un-batch a historical commit without risky rebase). The remediation plan must include the exception classification with explicit reasoning why it is non-fixable.
  - **The plan MUST include at least one `code-fix` or `plan-amendment` task if ANY FAIL check is classifiable as such.** A plan that classifies all FAIL checks as `process-exception` when code-fix or plan-amendment alternatives exist is itself a defect. Documentation-only changes to SUMMARY.md deviations arrays are NOT a valid resolution for code/architecture deviations.
  - Include `fail_classifications:` YAML array in R{RR}-PLAN.md frontmatter.
    - `code-fix` / `process-exception` entries: `{id: "FAIL-ID", type: "code-fix|process-exception", rationale: "..."}`
    - `plan-amendment` entries MUST also identify the original plan being amended: `{id: "FAIL-ID", type: "plan-amendment", rationale: "...", source_plan: "01-01-PLAN.md"}`. `source_plan` must reference an original plan in the current phase only — never a sibling phase, archived milestone, or remediation plan.
  - When `input_mode=known-issues` or `input_mode=both`, include every carried known issue from `known_issues_path` in `known_issues_input:` using the canonical `{test,file,error}` JSON object-string shape already used for tracked issues.
  - When `input_mode=known-issues` or `input_mode=both`, include a matching `known_issue_resolutions:` entry for every carried known issue using `{test,file,error,disposition,rationale}` JSON object strings. Valid `disposition` values are `resolved`, `accepted-process-exception`, and `unresolved`.
    - `resolved` = this round fixes the issue and QA should no longer return it in `pre_existing_issues`
    - `accepted-process-exception` = QA must verify the issue is real but non-blocking for this phase, omit it from `pre_existing_issues`, and leave it visible via the summary/STATE backlog instead of reopening the round forever
    - `unresolved` = the issue remains blocking and the next round must continue to carry it
  - Do NOT omit a carried known issue from `known_issues_input` or `known_issue_resolutions`. The deterministic gate treats missing coverage as a failed remediation round even if QA writes `PASS`.
  - Scope the plan to those failures: what to fix, which files, acceptance criteria
  - The orchestrator/Lead writes the plan (QA says what's wrong, planning says how to fix)
  - After writing the plan, advance state: `bash {plugin-root}/scripts/qa-remediation-state.sh advance {phase-dir}`

- **stage=execute:** Spawn a Dev subagent per `R{RR}-PLAN.md`:
  - Always subagent — NO team creation for QA remediation (NON-NEGOTIABLE)
  - Dev fixes code, commits, writes `R{RR}-SUMMARY.md` in `{round_dir}` using `templates/REMEDIATION-SUMMARY.md` (NOT `templates/SUMMARY.md`)
    - The remediation summary frontmatter MUST include aggregated `commit_hashes`, `files_modified`, and `deviations`
    - `files_modified` is required even for documentation-only rounds so `qa-result-gate.sh` can deterministically distinguish metadata-only remediation from real code changes
    - When `input_mode=known-issues` or `input_mode=both`, the remediation summary frontmatter MUST also include `known_issue_outcomes` with one `{test,file,error,disposition,rationale}` JSON object string per carried known issue. Keys and `disposition` values must match `R{RR}-PLAN.md` `known_issue_resolutions`; do not silently drop accepted non-blocking issues.
  - After Dev completes, advance state: `bash {plugin-root}/scripts/qa-remediation-state.sh advance {phase-dir}`

- **stage=verify:** Re-run QA:
  - Run `compile-verify-context.sh --remediation-only {phase-dir}` to get compounded verification history plus the current round's plan/summary context only
  - Spawn QA agent as subagent — writes to `{verification_path}` (from `qa-remediation-state.sh get` metadata)
    - The output path is `{round_dir}/R{RR}-VERIFICATION.md` — NOT the phase-level file
    - Phase-level VERIFICATION.md stays frozen as the original QA FAIL result
    - Include the compiled verify context output in QA's task description
    - After QA persists `{verification_path}`, immediately sync tracked known issues:
      ```bash
      bash "${VBW_PLUGIN_ROOT}/scripts/track-known-issues.sh" sync-verification "{phase-dir}" "{verification_path}" 2>/dev/null || true
      ```
    - After sync-verification, auto-promote surviving known issues to `STATE.md ## Todos` so they are visible via `/vbw:list-todos` and `/vbw:resume`:
      ```bash
      bash "${VBW_PLUGIN_ROOT}/scripts/track-known-issues.sh" promote-todos "{phase-dir}" 2>/dev/null || true
      ```
    - **Include in QA task description:** "In addition to verifying the remediation plan's own must_haves, you MUST re-verify each original FAIL from the VERIFICATION HISTORY section. For each FAIL_ID: if classified as code-fix, verify the code now matches the plan; if classified as plan-amendment, verify the original PLAN.md has been updated with the actual approach and rationale; if classified as process-exception, verify the exception is documented with non-fixable justification and that the justification is credible for this FAIL; if code-fix or plan-amendment still appears viable, keep the FAIL open. Any original FAIL that has not been addressed by one of these three paths is still a FAIL."
    - **Include in QA task description when a KNOWN ISSUES block is present:** "Tracked phase known issues are not informational in remediation rounds. Re-check every carried known issue from `known_issues_input` / `known_issue_resolutions`. Return only still-blocking issues in `pre_existing_issues`. If a carried issue is verified as an `accepted-process-exception`, omit it from `pre_existing_issues`, confirm that the accepted non-blocking disposition is credible for this phase, and rely on the matching `known_issue_outcomes` entry to preserve visibility after the blocking registry clears. A clean remediation QA run must return an empty `pre_existing_issues` array for all resolved or accepted non-blocking carried issues so `{phase-dir}/known-issues.json` can clear."
      - The deterministic gate validates structural evidence only. QA must decide whether a `process-exception` is *actually* justified during this re-verification step — documentation alone is insufficient when the original FAIL still appears fixable via code or plan amendment.
  - After QA returns, run the deterministic gate:
    ```bash
    bash "${VBW_PLUGIN_ROOT}/scripts/qa-result-gate.sh" "{phase-dir}"
    ```
    **Follow `qa_gate_routing` output literally — no exceptions, no judgment, no rationalization. Do NOT evaluate whether failures are justified, acceptable, or minor. The gate script has already made the decision:**
    - `qa_gate_routing=PROCEED_TO_UAT` → advance to done: `bash {plugin-root}/scripts/qa-remediation-state.sh advance {phase-dir}`, then **refresh verify context before entering Verify mode**:
      ```bash
      bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-verify-context-for-uat.sh "{phase-dir}"
      ```
      Use this fresh verify context and **continue directly into Verify mode** for the phase
    - `qa_gate_routing=REMEDIATION_REQUIRED` → start new round: `bash {plugin-root}/scripts/qa-remediation-state.sh needs-round {phase-dir}`, loop back to stage=plan. If `qa_gate_known_issues_override=true`, unresolved tracked known issues remain in `{phase-dir}/known-issues.json`.
    - `qa_gate_routing=QA_RERUN_REQUIRED` → re-spawn QA immediately (max 2 retries per round). If `qa_gate_deviation_override=true`, tell QA: "Previous QA run found PASS but SUMMARY.md files contain {qa_gate_deviation_count} deviations that were not reflected as FAIL checks. Each deviation MUST become a FAIL check — do not rationalize deviations as acceptable." If `qa_gate_plan_coverage` is present, tell QA: "Previous QA run only verified {qa_gate_plans_verified_count}/{qa_gate_plan_count} plans. Every plan in the phase must be verified — include all plan IDs in plans_verified." If QA still fails to produce valid output, treat as REMEDIATION_REQUIRED.
    - **When `qa_gate_metadata_only_override=true`** (routing will be `REMEDIATION_REQUIRED`): Display `⚠ QA remediation round made no implementation changes — only planning/documentation updates. The round still depends on a code-fix path (or omitted fail_classifications), so the original failures cannot be considered resolved without code changes. ${qa_gate_phase_deviation_count} phase deviations remain recorded.` This override is the deterministic safety net for rounds that still depend on code changes. Pure plan-amendment rounds can pass when the original plan was actually updated, and pure process-exception rounds still need planning/remediation-artifact evidence — delivered docs/README changes alone do not count. The next round's `stage=plan` MUST classify each FAIL as code-fix, plan-amendment, or process-exception per the Deviation Classification rules above.
    - **When `qa_gate_round_change_evidence_empty=true`** (routing will be `REMEDIATION_REQUIRED`): Display `⚠ QA remediation round recorded no change evidence — both files_modified and commit_hashes were empty. A PASS without any recorded changed files or commits cannot resolve prior FAILs.` The next round must produce real code/plan changes or capture justified remediation evidence instead of an empty summary.
    - **When `qa_gate_round_change_evidence_unavailable=true`** (routing will be `REMEDIATION_REQUIRED`): Display `⚠ QA remediation round recorded change evidence that could not be verified as current-round work. Either the recorded files did not match any committed or current round-local remediation-artifact changes after the source verification commit, or the referenced commit_hashes could not be proven to belong to this round, so the actual changed files could not be trusted.` Restore explicit files_modified entries and/or round-local commit evidence anchored to the remediation round before treating the failures as resolved.

- **stage=done:** Re-compute verify context, then proceed to Verify mode (UAT) for the phase:
  ```bash
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-verify-context-for-uat.sh "{phase-dir}"
  ```
  Use this fresh verify context for the Verify mode CHECKPOINT loop.

**QA Remediation + UAT blocking:** UAT cannot start while QA remediation is active. The `needs_qa_remediation` state takes priority over `needs_verification` in the routing table.

**all_done + natural language:** If $ARGUMENTS describe new work (bug, feature, task) and state is `all_done`, route to Add Phase mode instead of Archive. Add Phase handles codebase context loading and research internally — do NOT spawn an Explore agent or do ad-hoc research before entering the mode.

**UAT remediation default:** When `next_phase_state=needs_uat_remediation`, plain `/vbw:vibe` must read that phase's UAT report and continue remediation directly. Do NOT require the user to manually specify `--discuss` or `--plan`.

**Milestone UAT recovery:** When `milestone_uat_issues=true` and active phases are empty, the latest shipped milestone has unresolved UAT issues. Present the user with options: (a) create remediation phases to fix the UAT issues, (b) start fresh with new work (ignoring the stale UAT), or (c) skip for now (issues re-trigger next session). Use `milestone_uat_count` to determine how many phases are affected. When `milestone_uat_count` > 1, parse `milestone_uat_phase_dirs` (pipe-separated) to read all UAT reports and display a consolidated issue summary. Use `milestone_uat_major_or_higher` to determine severity context.

**Remediation + require_phase_discussion:** Both in-phase UAT remediation and milestone-level remediation phases skip the discussion step via pre-seeded phase context files. When `uat-remediation-state.sh get-or-init` runs for in-phase remediation, it appends the UAT report to the existing `{NN}-CONTEXT.md` and adds `pre_seeded: true` to its frontmatter — preserving the original discussion context while satisfying the `require_phase_discussion` gate. Milestone remediation phases created by `create-remediation-phase.sh` generate a fresh `{NN}-CONTEXT.md` with `pre_seeded: true` (populated from the source UAT report). Both paths use the same `pre_seeded` mechanism so `suggest-next.sh` handles them uniformly.

### Confirmation Gate

Every mode triggers confirmation before executing. **Use the AskUserQuestion tool** to present the question from the routing table's Confirmation column (marked with `→ AskUserQuestion:`), providing the recommended option and alternatives from the table below where listed. Do not render the confirmation as prose text or run a no-op command — the AskUserQuestion tool must be invoked so the user can respond via the interactive UI. For simple yes/no confirmations without a table entry, offer the affirmative action as recommended and a "Skip" or "Not now" alternative.
- **Exception:** `--yolo` skips all confirmation gates. Error guards (missing roadmap, uninitialized project) still halt.
- **Exception:** Flags skip confirmation (explicit intent).

**Discussion-aware alternatives (NON-NEGOTIABLE):** Alternatives must reflect whether discussion has already happened for the target phase. Never offer "discuss this phase" as if discussion never happened — when `{NN}-CONTEXT.md` exists, use continuation-aware wording like "Start a discussion" (which enters the Discussion Engine's continuation mode, building on existing context rather than repeating it).

| Routing state | Recommended | Alternatives |
| --- | --- | --- |
| `needs_discussion` | "Discuss phase {NN}" | "Skip discussion and plan directly", "View phase goal first" |
| `needs_plan_and_execute` | "Plan and execute phase {NN}" | "Plan only (review before executing)", "Start a discussion (explore gray areas before planning)" |
| `needs_execute` | "Execute phase {NN}" | "Review plans first", "Start a discussion (revisit scope before executing)" |
| `milestone_uat_issues` | "Create remediation phases" | "Start fresh with new work", "Not now" |

**AskUserQuestion parameters:** Set the recommended option's `isRecommended` flag. Output 3–4 blank lines before the AskUserQuestion call (the dialog obscures trailing text).

## Modes

### Mode: Init Redirect

If `planning_dir_exists=false`: display "Run /vbw:init first to set up your project." STOP.

### Mode: Bootstrap

**Guard:** `.vbw-planning/` exists but no PROJECT.md.

**Critical Rules (non-negotiable):**
- NEVER fabricate content. Only use what the user explicitly states.
- If answer doesn't match question: STOP, handle their request, let them re-run.
- No silent assumptions -- ask follow-ups for gaps.
- Phases come from the user, not you.

**Constraints:** Do NOT explore/scan codebase (that's /vbw:map). Use existing `.vbw-planning/codebase/` if `.vbw-planning/codebase/META.md` exists.

**Brownfield detection:** `git ls-files` or Glob check for existing code.

**Steps:**
- **B1: PROJECT.md** -- If $ARGUMENTS provided (excluding flags), use as description. Otherwise ask name + core purpose. Then call:
  ```
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-project.sh .vbw-planning/PROJECT.md "$NAME" "$DESCRIPTION"
  ```
- **B1.5: Discovery Depth** -- Read `discovery_questions` and `active_profile` from config. Map profile to depth:

  | Profile | Depth | Questions |
  | --------- | ------- | ----------- |
  | yolo | skip | 0 |
  | prototype | quick | 1-2 |
  | default | standard | 3-5 |
  | production | thorough | 5-8 |

  If `discovery_questions=false`: force depth=skip. Store DISCOVERY_DEPTH for B2.

- **B2: REQUIREMENTS.md (Discovery)** -- Behavior depends on DISCOVERY_DEPTH:
  - **B2.1: Domain Research (if not skip):** If DISCOVERY_DEPTH != skip:
    1. Extract domain from user's project description (the $NAME or $DESCRIPTION from B1)
    2. Resolve Scout model via `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-model.sh scout .vbw-planning/config.json /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/config/model-profiles.json` and Scout max turns via `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-max-turns.sh scout .vbw-planning/config.json "$(jq -r '.effort // \"balanced\"' .vbw-planning/config.json 2>/dev/null)"`
    3. Before composing the Scout task description, evaluate installed skills visible in your system context — read each skill's description and determine if it is relevant to this specific task. The Scout prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each relevant skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills apply, or `<skill_no_activation>Evaluated installed skills for this task. No installed skills apply. Reason: {brief task-specific reason}.</skill_no_activation>` when none apply. Silent omission of both blocks is invalid. Only include skills whose description matches the task at hand.
    4. Also evaluate available MCP tools in your system context. If any MCP servers provide documentation, search, or data retrieval capabilities relevant to this research topic, note them in the Scout's task context so it prioritizes those tools over generic WebSearch/WebFetch where applicable.
    5. Spawn Scout agent via Task tool with prompt: "Research the {domain} domain. Write your findings directly to the output path. <output_path>.vbw-planning/domain-research.md</output_path> Structure as four sections: ## Table Stakes (features every {domain} app has), ## Common Pitfalls (what projects get wrong), ## Architecture Patterns (how similar apps are structured), ## Competitor Landscape (existing products). Use WebSearch (or relevant MCP tools if available). Be concise (2-3 bullets per section)."
    6. Set `subagent_type: "vbw:vbw-scout"`, `model: "${SCOUT_MODEL}"` and `timeout: 120000` in Task tool invocation. If `SCOUT_MAX_TURNS` is non-empty, also pass `maxTurns: ${SCOUT_MAX_TURNS}`. If `SCOUT_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).
    7. On success: Read `.vbw-planning/domain-research.md` (Scout wrote it directly). Extract brief summary (3-5 lines max). Display to user: "◆ Domain Research: {brief summary}\n\n✓ Research complete. Now let's explore your specific needs..."
    8. On failure: Log warning "⚠ Domain research timed out, proceeding with general questions". Set RESEARCH_AVAILABLE=false, continue.
  - **B2.2: Discussion Engine** -- Read `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/discussion-engine.md` and follow its protocol.
    - Context for the engine: "This is a new project. No phases yet." Use project description + domain research (if available) as input.
    - If `.vbw-planning/codebase/META.md` exists and `discussion_mode` in config is `"assumptions"` or `"auto"`, pass "Discussion mode: assumptions" to the engine. The engine's Step 1.7 will form evidence-backed assumptions from codebase context instead of asking questions from scratch.
    - The engine handles calibration, gray area generation, exploration, and capture. The Recommendation Principle applies during bootstrap: lead with enterprise-standard recommendations for technical decisions, present product decisions equally.
    - Output: `discovery.json` with answered/inferred/deferred arrays.
  - **If skip (yolo profile or discovery_questions=false):** Ask 2 minimal static questions via AskUserQuestion:
    1. "What are the must-have features for this project?" Options: ["Core functionality only", "A few essential features", "Comprehensive feature set", "Let me explain..."]
    2. "Who will use this?" Options: ["Just me", "Small team (2-10 people)", "Many users (100+)", "Let me explain..."]
    Record answers to `.vbw-planning/discovery.json` with `{"answered":[],"inferred":[],"deferred":[]}`.
  - **After discovery (all depths):** Call:
    ```
    bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-requirements.sh .vbw-planning/REQUIREMENTS.md .vbw-planning/discovery.json .vbw-planning/domain-research.md
    ```

- **B3: ROADMAP.md** -- Suggest 3-5 phases from requirements. If `.vbw-planning/codebase/META.md` exists, read PATTERNS.md, ARCHITECTURE.md, and CONCERNS.md (whichever exist) from `.vbw-planning/codebase/`. Each phase: name, goal, mapped reqs, success criteria. Write phases JSON to temp file, then call:
  ```
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-roadmap.sh .vbw-planning/ROADMAP.md "$PROJECT_NAME" /tmp/vbw-phases.json
  ```
  Script handles ROADMAP.md generation and phase directory creation.
- **B4: STATE.md** -- Extract project name, milestone name, and phase count from earlier steps. Call:
  ```
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-state.sh .vbw-planning/STATE.md "$PROJECT_NAME" "$MILESTONE_NAME" "$PHASE_COUNT"
  ```
  Script handles today's date, Phase 1 status, empty decisions, and 0% progress.
- **B5: Brownfield summary** -- If BROWNFIELD=true AND no codebase/: count files by ext, check tests/CI/Docker/monorepo, add Codebase Profile to STATE.md.
- **B6: CLAUDE.md** -- Extract project name and core value from PROJECT.md. If root CLAUDE.md exists, pass it as EXISTING_PATH for section preservation. Call:
  ```
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-claude.sh CLAUDE.md "$PROJECT_NAME" "$CORE_VALUE" [CLAUDE.md]
  ```
  Script handles: new file generation (heading + core value + VBW sections), existing file preservation (refreshes only exact canonical VBW-owned sections already emitted by VBW, preserves the user's title/intro/arbitrary headings verbatim, and adds `## Code Intelligence` only if no Code Intelligence heading/guidance already exists anywhere in the file). Omit the fourth argument if no existing CLAUDE.md. Max 200 lines.
- **B7: Planning commit boundary (conditional)** -- Run:
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "bootstrap project files" .vbw-planning/config.json
   else
     echo "VBW: planning-git.sh unavailable; skipping planning git boundary commit" >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits `.vbw-planning/` + `CLAUDE.md` if changed. Other modes no-op.
- **B8: Transition** -- Display "Bootstrap complete. Transitioning to scoping..." Re-evaluate state, route to next match.

### Mode: Scope

**Guard:** PROJECT.md exists but `phase_count=0`.

**Steps:**
1. Load context: PROJECT.md, REQUIREMENTS.md. If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md and CONCERNS.md (whichever exist) from `.vbw-planning/codebase/`.
2. If $ARGUMENTS (excl. flags) provided, use as scope. Else ask: "What do you want to build?" Show uncovered requirements as suggestions.
3. Decompose into 3-5 phases (name, goal, success criteria). Each independently plannable. Map REQ-IDs.
4. Write ROADMAP.md. Create `.vbw-planning/phases/{NN}-{slug}/` dirs.
5. Update STATE.md by calling bootstrap-state.sh. Extract `PROJECT_NAME` from PROJECT.md, derive `MILESTONE_NAME` from the scope description (step 2), and use the phase count from step 3. The script preserves existing project-level sections (Todos, Decisions, Blockers, Codebase Profile) while restoring the `## Current Phase` section:
   ```
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-state.sh .vbw-planning/STATE.md "$PROJECT_NAME" "$MILESTONE_NAME" "$PHASE_COUNT"
   ```
   Do NOT write next-action suggestions (e.g. "Run /vbw:vibe --plan 1") into the Todos section — those are ephemeral display output from suggest-next.sh, not persistent state.
6. Write milestone context to `.vbw-planning/CONTEXT.md` using the template from `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/templates/MILESTONE-CONTEXT.md`. Capture:
   - **Gathered date** and **Calibration** (builder or architect, inferred from conversation signals — same as Discussion Engine calibration)
   - **Scope Boundary:** the user's scope description from step 2
   - **Decomposition Decisions:** rationale for phase count, grouping, and ordering from step 3. Includes **Scope Coverage** (what the milestone covers vs what is explicitly excluded or deferred) as a subsection under Decomposition Decisions per the template structure.
   - **Requirement Mapping:** which REQ-IDs map to which phases (from step 3)
   - **Key Decisions:** project-level decisions surfaced during scoping (tech choices, architecture patterns that transcend the milestone). Also insert these as rows in STATE.md's `## Key Decisions` table (append after the header row, replacing the `_(No decisions yet)_` placeholder if present). Milestone-scoped decisions (phase ordering rationale, scope boundaries) stay only in CONTEXT.md.
   - **Deferred Ideas:** out-of-scope ideas mentioned during steps 2-3
7. **Scope commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "scope milestone" .vbw-planning/config.json
   else
     echo "VBW: planning-git.sh unavailable; skipping planning git boundary commit" >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits `.vbw-planning/` if changed (ROADMAP.md, STATE.md, CONTEXT.md, phase dirs). Other modes no-op.
8. Display "Scoping complete. {N} phases created." STOP -- do not auto-continue to planning.

### Mode: Discuss

**Guard:** Initialized, phase exists in roadmap.
**Phase auto-detection:** First phase without `*-CONTEXT.md`. All discussed: STOP "All phases discussed. Specify: `/vbw:vibe --discuss N`"

**Continuation mode:** When the target phase already has a `{NN}-CONTEXT.md`, this is a **continuation discussion** — not a fresh one. If the CONTEXT.md has `pre_seeded: true` in its YAML frontmatter (remediation phase), WARN the user that this phase has pre-seeded UAT context and ask whether they want to re-discuss (which overwrites the pre-seeded content) or skip discussion and proceed to planning. Otherwise display: "Phase {NN} already has discussion context. Continuing to explore additional topics." The Discussion Engine will load existing decisions as baseline and focus on uncovered gray areas.

**Steps:**
1. Determine target phase from $ARGUMENTS or auto-detection.
2. Read `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/discussion-engine.md` and follow its protocol for the target phase.
3. **Discussion commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "discuss phase {NN}" .vbw-planning/config.json
   else
     echo "VBW: planning-git.sh unavailable; skipping planning git boundary commit" >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits `{NN}-CONTEXT.md` and `discovery.json` if changed. Other modes no-op.
4. Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh vibe`.

### Mode: Assumptions

**Guard:** Initialized, phase exists in roadmap.
**Phase auto-detection:** Same as Discuss mode.

**Continuation mode:** Same as Discuss mode — if a `{NN}-CONTEXT.md` exists, this is a continuation. Pre-seeded remediation phases get the same warning.

**Steps:**
1. Determine target phase from $ARGUMENTS or auto-detection.
2. Read `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/discussion-engine.md` and follow its protocol for the target phase. Pass "Discussion mode: assumptions" to the engine — Step 1.7 handles the assumptions workflow (codebase analysis, assumption formation, user correction, capture).
3. **Discussion commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "assumptions phase {NN}" .vbw-planning/config.json
   else
     echo "VBW: planning-git.sh unavailable; skipping planning git boundary commit" >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits `{NN}-CONTEXT.md` and `discovery.json` if changed. Other modes no-op.
4. Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh vibe`.

### Mode: UAT Remediation

**Guard:** Initialized, target phase has `*-UAT.md` with `status: issues_found`.

**Execution model:** This mode runs inline — the orchestrator manages stage transitions (steps 1-5) and spawns agents for the actual work within each stage (step 6). The three stages (research, plan, execute) are sequential steps of this conversation, not delegated tasks — do not decompose them into TaskCreate items.

**Chain state tracking:** This mode uses `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh` to persist the current stage of the remediation chain on disk. This ensures correct resumption after compaction or session restart — the chain does NOT rely on prompt memory alone.

**Steps:**
1. Resolve target phase from pre-computed state (`next_phase`, `next_phase_slug`) when `next_phase_state=needs_uat_remediation`. Set `PHASE_DIR` to the resolved phase directory path.
   **Milestone path guard (NON-NEGOTIABLE):** If `PHASE_DIR` contains `.vbw-planning/milestones/` (e.g., `.vbw-planning/milestones/*/phases/`), STOP — this is an archived milestone. UAT Remediation operates only on active phases in `.vbw-planning/phases/`. Display: "⚠ UAT issues found in archived milestone, not active phases. Routing to Milestone UAT Recovery." Then route to Milestone UAT Recovery mode instead.
2. Read the active UAT artifact exactly once. Use `uat_file` from the pre-computed state when available; it is phase-relative to `PHASE_DIR` (for example `03-UAT.md` or `remediation/uat/round-01/R01-UAT.md`). If `uat_file=none` or the computed path does not exist, resolve the active UAT artifact from `PHASE_DIR` with one deterministic fallback (current round-dir UAT first, phase-root fallback). If no active UAT artifact exists, STOP and display: "⚠ Phase {NN} routes to UAT remediation but no active UAT artifact could be found."
   **Single-read rule (NON-NEGOTIABLE):** Use that single UAT read as the source of truth for issue descriptions, severities, and current remediation scope. Do NOT shell out to `extract-uat-issues.sh` for active-phase routing.
   **Round-dir nuance:** At the start of a new remediation round, the active artifact may still be the latest previous-round UAT (for example step 4 returns `round=02` while the active file is `remediation/uat/round-01/R01-UAT.md`). That is expected — treat the artifact you read here as the current source report until a newer UAT exists.
3. Normalize the current issue list from the UAT read. For each failing test or discovered issue, capture `ID`, `SEVERITY`, and `DESCRIPTION`. Treat this normalized issue list as source-of-truth scope. Do NOT ask the user to restate issues already recorded in UAT.
4. **Resolve remediation stage (single call):**
   ```bash
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh get-or-init "$PHASE_DIR" "major"
   ```
   Use `major` when `uat_issues_major_or_higher=true`; otherwise use `minor` for the initial entry call.
   **Run directly (do NOT capture with `$()`).**
   - Both resume and init paths emit **plan metadata** after the stage line:
     ```text
     round=RR              — zero-padded current round number (e.g., 01)
     round_dir=<path>      — full path to the round directory (e.g., .vbw-planning/phases/03-slug/remediation/uat/round-01)
     research_path=<path>  — path to existing RESEARCH.md (empty if none)
     plan_path=<path>      — path to existing PLAN.md (empty if none)
     ```
     **Use these values directly** — do NOT glob `*-PLAN.md` or search for RESEARCH.md files. The script pre-computes all paths from the phase directory (with legacy phase-root fallback for brownfield projects).
   - If a stage was already persisted (resume after compaction/restart), the script returns the stage word + plan metadata with no side effects.
   - If no stage existed (first entry into remediation), the script initializes the stage file, creates `remediation/uat/round-01/` directory, pre-seeds the phase `{NN}-CONTEXT.md`, and returns the stage word + plan metadata + `---CONTEXT---` separator with the full pre-seeded context content — **use this directly as your remediation context. Do NOT separately read UAT.md or `{NN}-CONTEXT.md` files.**
   - If the returned stage is `done`: UAT remediation already completed for this phase. Display "Remediation already completed. Run `/vbw:vibe` to re-verify." STOP.
  **TodoWrite progress list (NON-NEGOTIABLE ordering and state):** Immediately after resolving the stage, create a TodoWrite progress list with items in **exactly this order** for the major path: (1) Research, (2) Plan, (3) Execute. For the minor path: (1) Fix. **Item numbering must match stage order** — Research is always #1, Plan #2, Execute #3. Never reorder items. This is a progress display for the user — agent spawning for each stage is handled in the execution stage below.
   - **Initial creation:** If the resolved stage is `research`, mark Research as in-progress, Plan and Execute as not-started. If the resolved stage is `plan` (resume case), mark Research as completed, Plan as in-progress, Execute as not-started. If `execute`, mark Research and Plan as completed, Execute as in-progress.
   - **Same-session progression:** When a stage completes and you advance to the next stage within the same session (e.g., research completes → advance → start plan), immediately update the TodoWrite progress list: mark the completed stage as completed and the new stage as in-progress. Do NOT defer updates or recreate the list from scratch.
   - **Final stage:** When the last stage completes, mark ALL TodoWrite items as completed before presenting the summary.
5. **Recurrence analysis and priority ranking:**
   Use `round=RR` from step 4 as the **current remediation round** for stage management.

   Derive `active_uat_round` from the single step-2 UAT artifact:
   - `remediation/uat/round-{NN}/R{NN}-UAT.md` → `active_uat_round={NN}`
   - phase-root `*-UAT.md` → the active report round at the phase root (round 1 when no archived round files exist; otherwise the root report comes after the archived round files already on disk)

   **Important:** `active_uat_round` can be **less than `RR`** at the start of a new remediation round because the new round has no UAT yet. Do NOT assume the active UAT artifact belongs to the current remediation round.

   **Post-route enrichment:** When inspecting earlier archived UAT artifacts for recurrence, read only the archived artifacts for this phase (flat `*-UAT-round-*.md` or round-dir `remediation/uat/round-*/R*-UAT.md`) and **exclude the active step-2 UAT artifact itself from the scan**. Build `FAILED_IN_ROUNDS` from the matching archived rounds plus `active_uat_round`. If no earlier matches exist, default each current issue to `FAILED_IN_ROUNDS={active_uat_round}` — **never** default to `RR` when the active artifact is a previous-round UAT.

   **Phase-level escalation:** When `RR >= 3`, force ALL issues through `research → plan → execute` regardless of severity. If the persisted stage from step 4 is `fix`, replace the quick-fix TodoWrite progress list with the major-path TodoWrite progress list (`Research`, `Plan`, `Execute`) before continuing.

   **Per-test priority ranking:** Rank issues by `failure_count` descending — tests that failed the most recorded UAT rounds get investigated and fixed FIRST. When presenting issues to Scout (research stage) and Lead (plan stage), reorder by `failure_count` descending and annotate:
   - `⚠ RECURRING (failed in N recorded rounds): ID|SEVERITY|DESCRIPTION` for tests with `failure_count >= 2`
   - `ID|SEVERITY|DESCRIPTION` (no annotation) for first-time failures

   **Scout research prompt for recurring issues** MUST include: *"{ID} has failed in {N} recorded UAT rounds (rounds: {FAILED_IN_ROUNDS}). Current source artifact round: {active_uat_round}; current remediation round: {RR}. Prior fixes have not resolved this. Investigate WHY previous fixes failed before proposing a new approach — examine the actual data flow, not just symptoms."*

   **Lead planning prompt for recurring issues** MUST include: *"Prioritize recurring failures. {ID} has failed in {N} recorded UAT rounds — allocate more plans/effort to this issue than to first-time failures."*
### Execute the current stage

Execute the current stage based on `STAGE`:
**File read rule:** Do NOT re-read the active `{phase}-UAT.md` artifact unless step 5 requires earlier archived rounds for recurrence enrichment. Use the single step-2 UAT read as the active-round source of truth, and if step 5 scans archived rounds, exclude that active artifact from the scan. Do NOT read `{phase}-CONTEXT.md` — step 4 already emitted the remediation context when needed.
**Round metadata prohibition:** Do NOT glob `*-PLAN.md` or search for `*-RESEARCH.md` — use the pre-computed `round`, `round_dir`, `research_path`, and `plan_path` values from step 4.

#### research

If `research_path` from step 4 is non-empty, research already exists — skip to advancing the stage. Otherwise, spawn Scout (with `subagent_type: "vbw:vbw-scout"`) with the normalized issue list from steps 3-5, **ordered by failure_count descending**, so Scout investigates the relevant code areas for each issue. Use `round` from step 4 as `{RR}`. Pass `<output_path>{round_dir}/R{RR}-RESEARCH.md</output_path>` in the Scout prompt so Scout writes the file directly. Before composing the Scout task description, evaluate installed skills visible in your system context — read each skill's description and determine if it is relevant to this specific task. The Scout prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each relevant skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills apply, or `<skill_no_activation>Evaluated installed skills for this task. No installed skills apply. Reason: {brief task-specific reason}.</skill_no_activation>` when none apply. Silent omission of both blocks is invalid. Only include skills whose description matches the task at hand. Also evaluate available MCP tools in your system context — if any MCP servers provide documentation, search, or data retrieval capabilities relevant to investigating these issues, note them in the Scout's task context so it prioritizes those tools over generic WebSearch/WebFetch where applicable.

- **Live data validation:** When any issue involves external data sources (APIs, databases, services), include in the Scout prompt: *"For issues involving external data sources, use WebFetch to query accessible HTTP endpoints and compare actual responses against what the code expects. For non-HTTP data sources, document what live data needs to be checked and flag it as ⚠ REQUIRES LIVE VALIDATION for the execute stage."*
- After Scout completes, confirm RESEARCH.md exists (read first line), then advance:
  ```bash
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh advance "$PHASE_DIR"
  ```
- Then continue to the next stage (`plan`).

#### plan

If `plan_path` from step 4 is non-empty, the plan was already written in a previous session — do NOT re-plan. Read the existing plan and advance directly to `execute`. Otherwise, spawn Lead as a **single subagent** to write the remediation plan.

**NO team creation (NON-NEGOTIABLE).** Do NOT use TeamCreate — remediation planning spawns Lead directly via Task tool with **no `team_name` or `name` parameters**. This is NOT "Plan mode steps 1-12" — remediation has its own sequential flow that does not use the standard planning pipeline.

- Resolve Lead model:
  ```bash
  LEAD_MODEL=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-model.sh lead .vbw-planning/config.json /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/config/model-profiles.json)
  LEAD_MAX_TURNS=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-max-turns.sh lead .vbw-planning/config.json "{effort}")
  ```
- Before composing the Lead task description, evaluate installed skills visible in your system context — read each skill's description and determine if it is relevant to this specific task. The Lead prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each relevant skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills apply, or `<skill_no_activation>Evaluated installed skills for this task. No installed skills apply. Reason: {brief task-specific reason}.</skill_no_activation>` when none apply. Silent omission of both blocks is invalid. Only include skills whose description matches the task at hand.
- Also evaluate available MCP tools in your system context. If any MCP servers provide capabilities relevant to this planning task, note them in the Lead's task context so Lead can include them when spawning Dev agents.
- Spawn vbw-lead via Task tool: Set `subagent_type: "vbw:vbw-lead"` and `model: "${LEAD_MODEL}"`. If `LEAD_MAX_TURNS` is non-empty, also pass `maxTurns: ${LEAD_MAX_TURNS}`. If empty, omit maxTurns.
- Lead prompt MUST include:
  - If `research_path` from step 4 is non-empty: `Read {research_path} for full research findings before planning.` (Lead must read the file, do NOT inline a summary.)
  - The priority-ranked issue list from step 5 with recurring-issue annotations.
  - `"Read the remediation plan template at /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/templates/REMEDIATION-PLAN.md and follow its structure exactly. This template is different from the regular PLAN.md — it has no wave or depends_on fields because remediation tasks are always sequential. Produce a flat ordered task list where each task can see the results of previous tasks."` (Lead must read the template file.)
  - Output path: `{round_dir}/R{RR}-PLAN.md` (using `round` from step 4 as `{RR}`).
- Display `◆ Spawning Lead agent...` → `✓ Lead agent complete`.
- Normalize plan filenames:
  ```bash
  NORM_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
  if [ -f "$NORM_SCRIPT" ]; then
    bash "$NORM_SCRIPT" "{round_dir}"
  fi
  ```
- Validate: Verify plan has valid frontmatter (phase, round, title, must_haves) and tasks.
- After planning completes, advance:
  ```bash
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh advance "$PHASE_DIR"
  ```

Then continue to the next stage (`execute`), respecting autonomy confirmation rules.

#### execute

Execute the remediation plan by spawning Dev agents sequentially — one per task in the plan. Do NOT use "normal Execute flow" or `execute-protocol.md` — remediation execution is self-contained with no wave parallelism.

**NO team creation (NON-NEGOTIABLE).** Do NOT use TeamCreate — remediation execution spawns Dev agents directly via Task tool with **no `team_name` or `name` parameters**.

- Read `{round_dir}/R{RR}-PLAN.md` (using `round` and `round_dir` from step 4) and extract the task list from the plan frontmatter/body. Each task has an ID (e.g., `P07`, `P08`, `UAT-3`).
- Resolve Dev model:
  ```bash
  DEV_MODEL=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-model.sh dev .vbw-planning/config.json /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/config/model-profiles.json)
  DEV_MAX_TURNS=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-max-turns.sh dev .vbw-planning/config.json "{effort}")
  ```
- Before composing Dev task descriptions, evaluate installed skills visible in your system context — read each skill's description and determine if it is relevant to this specific task. The Dev prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each relevant skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills apply, or `<skill_no_activation>Evaluated installed skills for this task. No installed skills apply. Reason: {brief task-specific reason}.</skill_no_activation>` when none apply. Silent omission of both blocks is invalid. Only include skills whose description matches the task at hand.
- Also evaluate available MCP tools in your system context. If any MCP servers provide build, test, documentation, or domain-specific capabilities relevant to the Dev tasks, note them in the Dev's task context.
- For each task in the plan (**sequentially**, one at a time — wait for each Dev to complete before spawning the next):
  - Spawn vbw-dev via Task tool: Set `subagent_type: "vbw:vbw-dev"` and `model: "${DEV_MODEL}"`. If `DEV_MAX_TURNS` is non-empty, also pass `maxTurns: ${DEV_MAX_TURNS}`. If empty, omit maxTurns.
  - Dev prompt MUST include:
    - The task details from the plan (description, files to modify, acceptance criteria).
    - `"Read the remediation summary template at /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/templates/REMEDIATION-SUMMARY.md and follow its structure for your task section."` For the **first task only**, also include: `"Create {round_dir}/R{RR}-SUMMARY.md with the YAML frontmatter from the template (populate phase, round, title from the plan; set status to in-progress, tasks_completed to 0, tasks_total to {total}) followed by your ## Task {N}: {name} section."` For **subsequent tasks**, include: `"Append your ## Task {N}: {name} section to {round_dir}/R{RR}-SUMMARY.md. Do NOT rewrite the frontmatter or earlier task sections. Do NOT leave trailing blank lines after your section."`
    - `"Do NOT create git worktrees. Work in the project root directory."`
    - If `.vbw-planning/codebase/META.md` exists: `"Read CONVENTIONS.md, PATTERNS.md, STRUCTURE.md, and DEPENDENCIES.md (whichever exist) from .vbw-planning/codebase/ to bootstrap codebase understanding before executing."`
  - Display: `◆ Spawning Dev agent for task {task-id} (${DEV_MODEL})...` → `✓ Dev agent complete for task {task-id}`.
- **Frontmatter finalization:** After ALL Dev agents have completed, update the YAML frontmatter in `{round_dir}/R{RR}-SUMMARY.md`: set `status` to `complete` (or `partial`/`failed`), `completed` to today's date, `tasks_completed` to the actual count, and populate `commit_hashes`, `files_modified`, and `deviations` with aggregate data from all task sections. Strip any trailing blank lines from the file.
- **Worktree cleanup check:** After execution, check for orphan CC worktrees:
  ```bash
  if [ -d ".claude/worktrees" ] && [ -n "$(ls -A .claude/worktrees 2>/dev/null)" ]; then
    echo "⚠ Found CC worktrees at .claude/worktrees/ — run 'git worktree list' and 'git worktree remove <path>' to clean up"
  fi
  ```
  Display this warning to the user if worktrees are found. Do NOT auto-delete them.
- Advance:
  ```bash
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh advance "$PHASE_DIR"
  ```
- **Chain into re-verification (NON-NEGOTIABLE):** After the execute stage advances to `done`, the remediation round is complete but NOT verified. Immediately prepare for re-verification and chain into Verify mode in the same turn:
  - Run: `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/prepare-reverification.sh "$PHASE_DIR"`
  - **Error guard:** If the script fails (non-zero exit), display the error message and **STOP** — do not attempt to enter Verify mode with stale/missing context.
  - Parse output: `archived=kept|in-round-dir`, `skipped=already_archived|ready_for_verify`, `round_file=...`, `phase=NN`, `layout=...`
  - If `archived=kept`: display "Phase UAT preserved. Starting re-verification in round dir."
    If `skipped=ready_for_verify`: display "Round {NN} remediation complete. Starting re-verification."
    If `skipped=already_archived`: display "UAT already archived. Starting re-verification."
    Otherwise: display "Archived previous UAT → {round_file}. Starting re-verification."
  - Planning artifact boundary commit (conditional):
    ```bash
    PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
    if [ -f "$PG_SCRIPT" ]; then
      bash "$PG_SCRIPT" commit-boundary "execute phase {NN} remediation round {RR}" .vbw-planning/config.json
    fi
    ```
  - **Continue directly into Verify mode** for this phase — do NOT stop, do NOT tell the user to run `/vbw:vibe`. Enter Verify mode (below) inline in the same turn. The pre-computed verify context may be stale (it was computed at session start, before remediation). Re-compute it:
    ```bash
    bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-verify-context-for-uat.sh "$PHASE_DIR"
    ```
    **uat_path validation (defense-in-depth):** After parsing the fresh verify context, validate that `uat_path` already points at the current remediation round's round-scoped UAT path (`remediation/uat/round-{RR}/R{RR}-UAT.md` for round-dir layout, `remediation/round-{RR}/R{RR}-UAT.md` for legacy layout). If it does not (e.g., it points to the phase-root UAT like `03-UAT.md`), override it with the round-scoped path for the current round from `uat-remediation-state.sh`. This prevents the original phase-root UAT from being overwritten during re-verification.
    Use this fresh verify context for the Verify mode CHECKPOINT loop.
  Do NOT present the remediation summary and stop — the summary is only useful if the session cannot continue (e.g., compaction).

#### fix

Route to a quick-fix implementation path for the same phase using the normalized issue list from step 3 (with step-5 recurrence annotations when available) as task input (equivalent to `/vbw:fix`, but without requiring the user to invoke it manually). After changes, advance:

```bash
bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh advance "$PHASE_DIR"
```

Then chain into re-verification using the same steps as the execute stage above (prepare-reverification → commit boundary → Verify mode inline). Do NOT suggest `/vbw:vibe` — enter Verify mode in the same turn.

### Fallback remediation summary

Only when re-verification chaining could not complete in this turn — e.g., context window limits, compaction, or session interruption — present a remediation summary with: phase, issue count, severity mix, current stage, chosen path (`research -> plan -> execute` or quick-fix), and per-test recurrence. For any issue with `failure_count >= 2`, include: `"⚠ RECURRING ({failure_count}/{round} rounds): {ID} — {DESCRIPTION}"`. First-time failures display without the annotation. End with: "Run `/vbw:vibe` to start re-verification."

### Mode: Milestone UAT Recovery

**Guard:** `milestone_uat_issues=true` from phase-detect.sh. Active phases dir is empty/all_done but the latest shipped milestone has unresolved UAT issues.

This mode handles the case where a milestone was archived before UAT issues were resolved (e.g., due to a missing audit gate in older versions).

**Steps:**
1. Use pre-computed milestone UAT issues from the "Milestone UAT issues" context block above. Each block starts with `milestone_phase_dir=<path>` followed by `extract-uat-issues.sh` output (header line + issue lines). Do NOT read UAT files from the milestone — all issue data is already extracted.
   If `milestone_uat_count` > 1, multiple blocks are present (one per affected phase, separated by `---`). If `milestone_uat_count` = 1, a single block is present.
2. Display the unresolved issues to the user with milestone context (milestone slug, affected phase count, severity mix). Then call AskUserQuestion with three options:
   - **"Create remediation phases"** (set `isRecommended` when `milestone_uat_major_or_higher=true`): Create one remediation phase per affected milestone phase. Auto-populate each phase goal from the UAT issue descriptions. Route to Plan mode for the first created phase.
   - **"Start fresh with new work"**: Acknowledge the stale UAT issues, mark them as acknowledged (`.remediated`) so they don't re-trigger archive blocking, then proceed as if all_done. The user can define new work via `/vbw:vibe` with arguments.
   - **"Not now"**: Skip milestone UAT recovery without marking anything. The unresolved UAT issues will re-trigger on the next `/vbw:vibe` invocation.
   Output 3–4 blank lines before the AskUserQuestion call (the dialog obscures trailing text).
   **`--yolo` exception:** If `--yolo` was passed, skip the AskUserQuestion and auto-select "Create remediation phases" (the recommended action).
3. If the user chooses remediation: create remediation phases via script — one per affected milestone phase:
   ```bash
   IFS='|' read -ra UAT_DIRS <<< "$milestone_uat_phase_dirs"
   for dir in "${UAT_DIRS[@]}"; do
     bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/create-remediation-phase.sh .vbw-planning "$dir"
   done
   ```
   The script also writes a `.remediated` marker in each source milestone phase dir to prevent re-triggering on future sessions. After creating all phases, write a ROADMAP.md and update STATE.md reflecting the remediation phases.
   **Remediation commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "create milestone remediation phases" .vbw-planning/config.json
   else
     echo "VBW: planning-git.sh unavailable; skipping planning git boundary commit" >&2
   fi
   ```
   Then route to Plan mode for the first phase.
4. If the user chooses start-fresh: persist acknowledgement markers for all affected archived phases before continuing:
   ```bash
   TARGET_PHASE_DIRS="$milestone_uat_phase_dirs"
   if [ -z "$TARGET_PHASE_DIRS" ] && [ "$milestone_uat_phase_dir" != "none" ]; then
     TARGET_PHASE_DIRS="$milestone_uat_phase_dir"
   fi
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/mark-milestone-remediated.sh .vbw-planning "$TARGET_PHASE_DIRS"
   ```
   **Re-route after marking (NON-NEGOTIABLE):** The pre-computed routing state is now stale — `.remediated` markers changed on-disk state. Re-run phase-detect to discover existing phases or new-work eligibility:
   ```bash
   FRESH_PD=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/phase-detect.sh 2>/dev/null)
   ```
   **Error guard:** If `FRESH_PD` is empty or contains `phase_detect_error=true`, display "⚠ Phase detection failed after marking milestones. Run `/vbw:vibe` again." and STOP.
   **Re-trigger guard:** If `FRESH_PD` still shows `milestone_uat_issues=true`, check whether `milestone_uat_slug` from `FRESH_PD` matches the slug that was just processed (the original `milestone_uat_slug` from the pre-computed state). If it matches — the marking failed for this milestone. Display "⚠ Some milestone UAT markers could not be written. Manually create `.remediated` files in the affected phase dirs, then run `/vbw:vibe`." and STOP (prevents infinite loop). If it does NOT match — a different older milestone has unresolved UAT; let routing continue (the priority table will handle it, which may route to Milestone UAT Recovery for that other milestone).
   Otherwise, parse all routing variables from `FRESH_PD` (`next_phase_state`, `phase_count`, `config_auto_uat`, `has_unverified_phases`, etc.) and apply the **full priority table above** (priorities 1–11) to determine the correct mode. Route inline in the same turn. Key outcomes:
   - `needs_uat_remediation` → UAT Remediation mode
   - `needs_reverification` → Re-verify mode
   - `milestone_uat_issues=true` (different milestone) → Milestone UAT Recovery mode
   - `needs_verification` → Verify mode (auto_uat)
   - `needs_discussion` → Discuss mode
   - `needs_plan_and_execute` → Plan + Execute mode
   - `needs_execute` → Execute mode
   - `phase_count=0` → Scope mode
   - `all_done` → Archive mode
   This list is illustrative — always defer to the full priority table. Do NOT stop and ask "What would you like to build?" when phases already exist.
5. If the user chooses "Not now": display "Skipping milestone UAT recovery. Run `/vbw:vibe` again when ready to address these issues." and STOP. No `.remediated` markers are written — the unresolved UAT issues will re-trigger on the next `/vbw:vibe` invocation.

### Mode: Plan

**Guard:** Initialized, roadmap exists, phase exists.
**Phase auto-detection:** First phase without PLAN.md. All planned: STOP "All phases planned. Specify phase: `/vbw:vibe --plan N`"
**Milestone path guard:** If `{phases_dir}` contains `.vbw-planning/milestones/`, STOP "Cannot plan inside archived milestones." Archived milestones are read-only.

**Steps:**
1. **Parse args:** Phase number (optional, auto-detected), --effort (optional, falls back to config).
2. **Phase context:** Resolve CONTEXT path:
   ```bash
   CONTEXT_NAME=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-artifact-path.sh context "{phase-dir}")
   ```
   If `{phase-dir}/${CONTEXT_NAME}` exists, include it in Lead agent context. If not, proceed without — users who want context run `/vbw:discuss {NN}` first.
3. **Research persistence (REQ-08, graduated):** If effort != turbo:
   - Determine the next plan number `{MM}` and resolve artifact paths:
     ```bash
     RESOLVE_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-artifact-path.sh"
     NEXT_PLAN_NAME=$(bash "$RESOLVE_SCRIPT" plan "{phase-dir}")
     MM=$(echo "$NEXT_PLAN_NAME" | sed 's/^[0-9]*-\([0-9]*\)-.*/\1/')
     RESEARCH_NAME=$(bash "$RESOLVE_SCRIPT" phase-research "{phase-dir}")
     ```
    - Check for phase-wide research `{phase-dir}/${RESEARCH_NAME}` (preferred). If phase-wide does not exist, only treat historical `{phase-dir}/{NN}-01-RESEARCH.md` as brownfield phase research when no higher-numbered per-plan research exists. Compute it with: `OTHER_PLAN_RESEARCH=$(find "{phase-dir}" -maxdepth 1 -name "{NN}-[0-9][0-9]*-RESEARCH.md" ! -name "{NN}-01-RESEARCH.md" -print -quit 2>/dev/null); if [ -f "{phase-dir}/{NN}-01-RESEARCH.md" ] && [ -z "$OTHER_PLAN_RESEARCH" ]; then BROWNFIELD_RESEARCH="{phase-dir}/{NN}-01-RESEARCH.md"; fi`. If `$OTHER_PLAN_RESEARCH` is non-empty, leave `$BROWNFIELD_RESEARCH` empty — multiple per-plan research files remain distinct and do not count as phase-wide research.
   - **If neither exists:** If `config_context_compiler=true`, compile Scout context first: `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-context.sh {phase} scout {phases_dir}`. Include `.context-scout.md` in the Scout prompt if produced, described as: "compiled context — includes milestone scope decisions (decomposition rationale, scope boundaries, cross-phase key decisions) and phase operational context (goal, success criteria, matched requirements, conventions, changed files)."
     Spawn Scout agent to research the phase goal, requirements, and relevant codebase patterns. Scout writes its findings directly to the output path. Pass `<output_path>{phase-dir}/${RESEARCH_NAME}</output_path>` in the Scout prompt so Scout writes the file using its Write tool. After Scout completes, confirm the file exists (read first line). Resolve Scout model:
     ```bash
     SCOUT_MODEL=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-model.sh scout .vbw-planning/config.json /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/config/model-profiles.json)
     SCOUT_MAX_TURNS=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-max-turns.sh scout .vbw-planning/config.json "{effort}")
     ```
  Pass `subagent_type: "vbw:vbw-scout"` and `model: "${SCOUT_MODEL}"` to the Task tool. If `SCOUT_MAX_TURNS` is non-empty, also pass `maxTurns: ${SCOUT_MAX_TURNS}`. If `SCOUT_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited). Before composing the Scout task description, evaluate installed skills visible in your system context — read each skill's description and determine if it is relevant to this specific task. The Scout prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each relevant skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills apply, or `<skill_no_activation>Evaluated installed skills for this task. No installed skills apply. Reason: {brief task-specific reason}.</skill_no_activation>` when none apply. Silent omission of both blocks is invalid. Only include skills whose description matches the task at hand. Also evaluate available MCP tools in your system context — if any MCP servers provide documentation, search, or data retrieval capabilities relevant to this research, note them in the Scout's task context so it prioritizes those tools over generic WebSearch/WebFetch where applicable.
    - **If exists (phase-wide or legacy single-file brownfield):** Record the RESEARCH.md path (phase-wide `${RESEARCH_NAME}` or brownfield `${BROWNFIELD_RESEARCH}`) for inclusion in the Lead prompt. The Lead prompt MUST include the directive: `Read {research-path} for full research findings before planning.` Do NOT inline a summary of the research as a substitute — the Lead must read the file itself to get the complete, unabridged findings. Multiple per-plan research files are not phase-wide research; if no real phase-wide file exists, Scout should create `${RESEARCH_NAME}`. Lead may update the phase-wide RESEARCH.md if new information emerges.
   - **On failure:** Log warning, continue planning without research. Do not block.
   - **Authenticated live validation policy:** Scout cannot safely validate authenticated/private APIs (no Bash access). If research identifies a need for authenticated live validation (signed requests, API tokens, env-based secrets), Scout must flag it with `⚠ REQUIRES AUTHENTICATED LIVE VALIDATION` in findings. The execute stage (Dev/Debugger) performs that validation via Bash before code changes. Do not route authenticated API validation through WebFetch.
   - If effort=turbo: skip entirely.
4. **Research commit boundary (conditional):** If Scout was spawned in step 3 (new RESEARCH.md written):
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "research phase {NN}" .vbw-planning/config.json
   else
     echo "VBW: planning-git.sh unavailable; skipping research git boundary commit" >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits RESEARCH.md if changed. Skipped when research was pre-existing or effort=turbo.
5. **Context compilation:** If `config_context_compiler=true`, run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-context.sh {phase} lead {phases_dir}`. Include `.context-lead.md` in Lead agent context if produced. When including it in the Lead prompt, describe its contents: "Read `.context-lead.md` for compiled context — includes milestone scope decisions (decomposition rationale, scope boundaries, cross-phase key decisions) and operational context (phase goal, success criteria, matched requirements, active decisions, research findings)."
6. **Turbo shortcut:** If effort=turbo, skip Lead. Resolve the plan filename:
   ```bash
   TURBO_PLAN=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-artifact-path.sh plan "{phase-dir}")
   ```
   Read phase reqs from ROADMAP.md, create single lightweight plan as `${TURBO_PLAN}` in the phase directory.
7. **Other efforts:**
   - Resolve Lead model:
     ```bash
     LEAD_MODEL=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-model.sh lead .vbw-planning/config.json /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/config/model-profiles.json)
       LEAD_MAX_TURNS=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-max-turns.sh lead .vbw-planning/config.json "{effort}")
     if [ $? -ne 0 ]; then
       echo "$LEAD_MODEL" >&2
       exit 1
     fi
     ```
   **No team creation in Plan mode.** Scout (step 3) and Lead are sequential — Scout must complete before Lead starts (Lead reads the RESEARCH.md). Teams are only for parallel Dev agents in Execute mode (`prefer_teams` is evaluated there, not here). Always spawn Lead as a plain subagent.
  - Before composing the Lead task description, evaluate installed skills visible in your system context — read each skill's description and determine if it is relevant to this specific task. The Lead prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each relevant skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills apply, or `<skill_no_activation>Evaluated installed skills for this task. No installed skills apply. Reason: {brief task-specific reason}.</skill_no_activation>` when none apply. Silent omission of both blocks is invalid. Only include skills whose description matches the task at hand.
   - Also evaluate available MCP tools in your system context. If any MCP servers provide capabilities relevant to this planning task, note them in the Lead's task context so Lead can include them when spawning Dev agents.
   - Spawn vbw-lead as subagent via Task tool with compiled context (or full file list as fallback).
   - **CRITICAL:** Set `subagent_type: "vbw:vbw-lead"` and `model: "${LEAD_MODEL}"` in the Task tool invocation. If `LEAD_MAX_TURNS` is non-empty, also pass `maxTurns: ${LEAD_MAX_TURNS}`. If `LEAD_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).
   - **CRITICAL:** If a RESEARCH.md was found or created in step 3, include in the Lead prompt: `Read {research-path} for full research findings before planning.` where `{research-path}` is the per-plan or legacy path from step 3. The Lead must read the file itself — do NOT substitute an inlined summary.
   - **CRITICAL:** Include in the Lead prompt: "Plans will be executed by a team of parallel Dev agents — one agent per plan. Maximize wave 1 plans (no deps) so agents start simultaneously. Ensure same-wave plans modify disjoint file sets to avoid merge conflicts."
   - **CRITICAL:** Include in the Lead prompt: `Use resolve-artifact-path.sh to compute plan filenames: bash ${RESOLVE_SCRIPT} plan "{phase-dir}" --plan-number {MM}` where `RESOLVE_SCRIPT` is the path from step 3. The script returns the canonical filename (e.g., `03-01-PLAN.md`). Call it once per plan with the plan number.
   - Display `◆ Spawning Lead agent...` -> `✓ Lead agent complete`.
8. **Normalize plan filenames:**
    ```bash
    NORM_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
    if [ -f "$NORM_SCRIPT" ]; then
      bash "$NORM_SCRIPT" "{phase_dir}"
    fi
    ```
    This catches any misnamed files written by Lead (e.g., turbo mode or models that bypass the PreToolUse block).
9. **Validate output:** Verify PLAN.md has valid frontmatter (phase, plan, title, wave, depends_on, must_haves) and tasks. Check wave deps acyclic.
10. **Present:** Update STATE.md (phase position, plan count, status=Planned). Resolve model profile:
   ```bash
   MODEL_PROFILE=$(jq -r '.model_profile // "quality"' .vbw-planning/config.json)
   ```
   Display Phase Banner with plan list, effort level, and model profile:
    ```text
   Phase {NN}: {name}
   Plans: {N}
     {plan}: {title} (wave {W}, {N} tasks)
   Effort: {effort}
   Model Profile: {profile}
   ```
11. **Planning commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "plan phase {NN}" .vbw-planning/config.json
   else
     echo "VBW: planning-git.sh unavailable; skipping planning git boundary commit" >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits planning artifacts if changed. `auto_push=always` pushes when upstream exists.
12. **Cautious gate (autonomy=cautious only):** STOP after planning. Ask "Plans ready. Execute Phase {NN}?" Other levels: auto-chain.

### Mode: Execute

**Execute-mode invariant:** Parallel execution is only valid when the live tool set can create real team-scoped teammates. If real team semantics cannot be established, execute mode must warn and fall back to explicit non-team execution. Never simulate a team with background `Agent` spawns that lack `team_name`.

Read `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/execute-protocol.md` and follow its instructions.

This mode delegates entirely to the protocol file. **Orchestrator read-scope:** Do NOT read product source files. Your job is orchestration — read plans, check summaries, spawn Dev for remaining work. If you need product-code understanding to route or sequence, delegate that to Dev.

Before reading:
0. **Pre-normalize filenames:**
    ```bash
    NORM_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
    if [ -f "$NORM_SCRIPT" ]; then
      bash "$NORM_SCRIPT" "{phase_dir}"
    fi
    ```
1. **Parse arguments:** Phase number (auto-detect if omitted), --effort, --skip-qa, --plan=NN.
2. **Run execute guards:**
   - Not initialized: STOP "Run /vbw:init first."
   - No PLAN.md in phase dir: STOP "Phase {NN} has no plans. Run `/vbw:vibe --plan {NN}` first."
   - All plans have SUMMARY.md: cautious/standard -> WARN + confirm; confident/pure-vibe -> warn + auto-continue.
   - **Milestone path guard:** If `{phases_dir}` contains `.vbw-planning/milestones/`, STOP "Cannot execute inside archived milestones." This prevents writing artifacts into shipped milestone directories.
3. **Compile context:** If `config_context_compiler=true`, run:
   - `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-context.sh {phase} dev {phases_dir} {plan_path}`
   - `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-context.sh {phase} qa {phases_dir}`
   Include compiled context paths in Dev and QA task descriptions. When referencing `.context-dev.md`, describe it as: "compiled context — includes milestone scope decisions (decomposition rationale, scope boundaries, cross-phase key decisions) and phase operational context (goal, conventions, active plan, research findings, changed files, code slices)." When referencing `.context-qa.md`, describe it as: "compiled context — includes milestone scope decisions and phase verification context (success criteria, requirements, conventions to check)."

Then Read the protocol file and execute Steps 2-5 as written.

### Mode: Verify

**Guard:** Initialized, phase has `*-SUMMARY.md` files.
No SUMMARY.md: STOP "Phase {NN} has no completed plans. Run /vbw:vibe first."
**Phase auto-detection:** First phase with `*-SUMMARY.md` but no canonical `*-UAT.md` (exclude `*-SOURCE-UAT.md` copies). All verified: STOP "All phases have UAT results. Specify: `/vbw:verify {NN}`"

**Inline execution (NON-NEGOTIABLE):** UAT is an interactive conversation with the human user via AskUserQuestion CHECKPOINT prompts. Do NOT spawn a QA agent, Dev agent, or any subagent for UAT verification. Do NOT use TaskCreate to delegate UAT. The AskUserQuestion tool is only available to the orchestrator — subagents cannot interact with the user, so delegating UAT to a subagent bypasses user input entirely and produces auto-written UAT files without human judgment. Run the verify.md CHECKPOINT loop directly in this conversation, the same way UAT Remediation coordinates its stages inline.

**Steps:**
1. Read `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/commands/verify.md` protocol. When entering from `needs_reverification` or `auto_uat` routing, the pre-computed verify context (verify_scope, uat_path, uat_resume) is already available from the Context section above — use it unless the `needs_reverification` flow above just refreshed verify context and resume metadata after `prepare-reverification.sh`, in which case use that refreshed output instead. **Error guard:** If the active verify block contains `verify_context_error=true` or `verify_context=unavailable`, display: "⚠ Verify context compilation failed. Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-verify-context.sh .vbw-planning/phases/{NN}-{slug}` manually to debug." STOP. Do NOT improvise by scanning PLAN/SUMMARY files manually in this routed path.
2. Execute the verify.md steps inline in this conversation. Specifically: generate test scenarios (verify.md Step 4), then run the CHECKPOINT loop (verify.md Step 5) presenting one test at a time via AskUserQuestion and waiting for the user's response before proceeding to the next test. Use the pre-computed "Verify context" block from this command's Context section — it contains the PLAN/SUMMARY aggregation and UAT resume metadata for the target phase. Pass this data through to the verify protocol steps so they do NOT read individual PLAN/SUMMARY files or scan-parse UAT.md for resume state.
3. Display results per verify.md output format.
4. **UAT Remediation Auto-Continuation:** This step only applies when verify.md emitted `remediation_continue=true` (which happens when `verify_scope=remediation` AND `status=issues_found` AND running in orchestrated mode from vibe.md). If `remediation_continue` was not set (first-time UAT, complete result, or standalone verify), skip this step entirely — the command ends after step 3.

   **Check the UAT remediation round cap, then advance state:** Read the current round number (read-only, no state mutation) and compare against the configured maximum before advancing:

   ```bash
   _current_round=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh current-round "{phase-dir}")
   _max_rounds=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-uat-remediation-round-limit.sh .vbw-planning/config.json 2>/dev/null || true)
   _next_round=$(( 10#${_current_round} + 1 ))
   ```

   **If `_max_rounds` is empty:** The UAT remediation round cap is unlimited (`max_uat_remediation_rounds=false`, `0`, absent, or malformed). Skip the cap-stop branch and continue directly to `needs-round`.

   **If `_max_rounds` is non-empty and `_next_round > _max_rounds`:** Display the cap-reached banner and STOP. Do NOT call `needs-round` — no state mutation occurs:
   ```text
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     Reached maximum UAT remediation rounds ({_max_rounds}).
     Review issues manually or adjust max_uat_remediation_rounds
     in config.json.
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```
   Do NOT re-enter remediation. STOP.

   **If `_max_rounds` is empty or `_next_round <= _max_rounds`:** Advance state by calling `needs-round`:
   ```bash
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh needs-round "{phase-dir}"
   ```
   Parse `round={next-round}` from the script output (the script outputs `research`, `round={next-round}`, `round_dir={path}` on separate lines — match by key name, not line position).

   Display the transition banner and re-enter UAT Remediation mode inline:
   ```text
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     Re-verification found {N} issue(s). Continuing to Round {next-round}.
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```
   Where `{N}` is the issue count from the `remediation_continue` signal (`issues={N}`).
   Re-enter UAT Remediation mode (above) for the same `PHASE_DIR`. The `needs-round` call above set the remediation state to `research` for the new round. The UAT Remediation mode's step 4 (`get-or-init`) will resume correctly from the `research` stage.

  **Continuation loop behavior:** The re-entered UAT Remediation mode chains into Verify mode after its execute stage completes (existing behavior). If that verification again finds issues, verify.md emits `remediation_continue=true` again, and this step 4 re-checks the UAT remediation round cap. This creates the auto-continuation loop, bounded only when `max_uat_remediation_rounds` resolves to a positive integer. The Step 7 fallback summary remains the escape hatch when context window limits prevent continuation mid-loop.

### Mode: Add Phase

**Guard:** Initialized. Requires phase name in $ARGUMENTS.
Missing name: STOP "Usage: `/vbw:vibe --add <phase-name>`"

**Steps:**
1. **Codebase context:** If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md and CONCERNS.md (whichever exist) from `.vbw-planning/codebase/`. Use this to inform phase goal scoping and identify relevant modules/services.
2. Parse args: phase name (first non-flag arg), --goal (optional), slug (lowercase hyphenated).
3. Next number: highest in ROADMAP.md + 1, zero-padded.
4. Create dir: `mkdir -p .vbw-planning/phases/{NN}-{slug}/`
5. **Problem research (conditional):** If $ARGUMENTS contain a problem description (bug report, feature request, multi-sentence intent) rather than just a bare phase name:
   - Resolve Scout model: `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-model.sh scout .vbw-planning/config.json /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/config/model-profiles.json`
   - Resolve Scout max turns: `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-max-turns.sh scout .vbw-planning/config.json "$(jq -r '.effort // "balanced"' .vbw-planning/config.json 2>/dev/null)"`
  - Spawn Scout agent (with `subagent_type: "vbw:vbw-scout"`) to research the problem in the codebase. Pass `<output_path>{phase-dir}/{NN}-RESEARCH.md</output_path>` in the Scout prompt so Scout writes its findings directly using its Write tool. Before composing the Scout task description, evaluate installed skills visible in your system context — read each skill's description and determine if it is relevant to this specific task. The Scout prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each relevant skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills apply, or `<skill_no_activation>Evaluated installed skills for this task. No installed skills apply. Reason: {brief task-specific reason}.</skill_no_activation>` when none apply. Silent omission of both blocks is invalid. Only include skills whose description matches the task at hand. Also evaluate available MCP tools — if any MCP servers provide documentation, search, or data retrieval capabilities relevant to this research, note them in the Scout's task context. After Scout completes, confirm the file exists (read first line).
   - Use Scout findings to write an informed phase goal and success criteria in ROADMAP.md.
   - On failure: log warning, write phase goal from $ARGUMENTS alone. Do not block.
   - **This eliminates duplicate research** — Plan mode step 3 checks for existing RESEARCH.md and skips Scout if found.
1. Update ROADMAP.md: append phase list entry, append Phase Details section (using Scout findings if available), add progress row.
2. If `.vbw-planning/CONTEXT.md` exists, rewrite it to reflect the updated milestone decomposition (phase count/grouping, ordering, scope coverage, and requirement mapping). Preserve project-level key decisions and deferred ideas where still valid.
3. Update STATE.md phase total: `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/update-phase-total.sh .vbw-planning`
4. **Phase mutation commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "add phase {NN}-{slug}" .vbw-planning/config.json
   else
     echo "VBW: planning-git.sh unavailable; skipping planning git boundary commit" >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits `.vbw-planning/` if changed. Other modes no-op.
5. Present: Phase Banner with position, goal. Checklist for roadmap update + dir creation. Next Up: `/vbw:vibe --discuss` or `/vbw:vibe --plan`.

### Mode: Insert Phase

**Guard:** Initialized. Requires position + name.
Missing args: STOP "Usage: `/vbw:vibe --insert <position> <phase-name>`"
Invalid position (out of range 1 to max+1): STOP with valid range.
Inserting before completed phase: WARN + confirm.

**Steps:**
1. **Codebase context:** If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md and CONCERNS.md (whichever exist) from `.vbw-planning/codebase/`. Use this to inform phase goal scoping and identify relevant modules/services.
2. Parse args: position (int), phase name, --goal (optional), slug (lowercase hyphenated).
3. Identify renumbering: all phases >= position shift up by 1.
4. Renumber dirs in REVERSE order: rename dir {NN}-{slug} -> {NN+1}-{slug}, rename internal PLAN/SUMMARY files, update `phase:` frontmatter, update `depends_on` references.
5. Create dir: `mkdir -p .vbw-planning/phases/{NN}-{slug}/`
6. **Problem research (conditional):** If $ARGUMENTS contain a problem description, spawn Scout (with `subagent_type: "vbw:vbw-scout"`) to research the codebase. Pass `<output_path>{phase-dir}/{NN}-RESEARCH.md</output_path>` in the Scout prompt so Scout writes the file directly. Before composing the Scout task description, evaluate installed skills visible in your system context — read each skill's description and determine if it is relevant to this specific task. The Scout prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each relevant skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills apply, or `<skill_no_activation>Evaluated installed skills for this task. No installed skills apply. Reason: {brief task-specific reason}.</skill_no_activation>` when none apply. Silent omission of both blocks is invalid. Only include skills whose description matches the task at hand. Also evaluate available MCP tools — if any MCP servers provide documentation, search, or data retrieval capabilities relevant to this research, note them in the Scout's task context. After Scout completes, confirm the file exists (read first line). This prevents Plan mode from duplicating the research.
7. Update ROADMAP.md: insert new phase entry + details at position (using Scout findings if available), renumber subsequent entries/headers/cross-refs, update progress table.
8. If `.vbw-planning/CONTEXT.md` exists, rewrite it to reflect the updated milestone decomposition (phase count/grouping, ordering, scope coverage, and requirement mapping). Preserve project-level key decisions and deferred ideas where still valid.
9. Update STATE.md phase total: `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/update-phase-total.sh .vbw-planning --inserted {position}` (where {position} is the insert position from step 2).
10. **Phase mutation commit boundary (conditional):**
    ```bash
   PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
    if [ -f "$PG_SCRIPT" ]; then
      bash "$PG_SCRIPT" commit-boundary "insert phase {NN}-{slug} at position {position}" .vbw-planning/config.json
    else
      echo "VBW: planning-git.sh unavailable; skipping planning git boundary commit" >&2
    fi
    ```
    Behavior: `planning_tracking=commit` commits `.vbw-planning/` if changed. Other modes no-op.
11. Present: Phase Banner with renumber count, phase changes, file checklist, Next Up.

### Mode: Remove Phase

**Guard:** Initialized. Requires phase number.
Missing number: STOP "Usage: `/vbw:vibe --remove <phase-number>`"
Not found: STOP "Phase {NN} not found."
Has work (PLAN.md or SUMMARY.md): STOP "Phase {NN} has artifacts. Remove plans first."
Completed ([x] in roadmap): STOP "Cannot remove completed Phase {NN}."

**Steps:**
1. Parse args: extract phase number, validate, look up name/slug.
2. Confirm: display phase details, ask confirmation. Not confirmed -> STOP.
3. Remove dir: `rm -rf .vbw-planning/phases/{NN}-{slug}/`
4. Renumber FORWARD: for each phase > removed: rename dir {NN} -> {NN-1}, rename internal files, update frontmatter, update depends_on.
5. Update ROADMAP.md: remove phase entry + details, renumber subsequent, update deps, update progress table.
6. If `.vbw-planning/CONTEXT.md` exists, rewrite it to reflect the updated milestone decomposition (phase count/grouping, ordering, scope coverage, and requirement mapping). Preserve project-level key decisions and deferred ideas where still valid.
7. Update STATE.md phase total: `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/update-phase-total.sh .vbw-planning --removed {NN}` (where {NN} is the removed phase number from step 1).
8. **Phase mutation commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "remove phase {NN}" .vbw-planning/config.json
   else
     echo "VBW: planning-git.sh unavailable; skipping planning git boundary commit" >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits `.vbw-planning/` if changed. Other modes no-op.
9. Present: Phase Banner with renumber count, phase changes, file checklist, Next Up.

### Mode: Archive

**Guard:** Initialized, roadmap exists.
No roadmap: STOP "No milestones configured. Run `/vbw:vibe` to bootstrap."
No work (no SUMMARY.md files): STOP "Nothing to ship."

**Hard UAT gate (always, non-bypassable):**
Before any audit/bypass handling, run:
```bash
bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/archive-uat-guard.sh
```
If exit code is 2: STOP. Unresolved UAT (active or milestone) blocks archive regardless of `--skip-audit` or `--force`.

**Pre-gate audit (unless --skip-audit or --force):**
Run 7-point audit matrix:
1. Roadmap completeness: every phase has real goal (not TBD/empty)
2. Phase planning: every phase has >= 1 PLAN.md
3. Plan execution: every PLAN.md has SUMMARY.md
4. Execution status: every SUMMARY.md has `status: complete`
5. Verification: authoritative QA verification exists and is fresh PASS. Missing=WARN, failed=FAIL. After QA remediation reaches `done`, the authoritative artifact is the round-scoped `R{RR}-VERIFICATION.md`; the frozen phase-level VERIFICATION.md must not be reused.
6. UAT status: any `*-UAT.md` with `status: issues_found` = FAIL. Unresolved UAT issues must be remediated before archiving.
7. Requirements coverage: req IDs in roadmap exist in REQUIREMENTS.md
FAIL -> STOP with remediation suggestions. WARN -> proceed with warnings.

**Steps:**
1. **Derive milestone slug (deterministic — do NOT invent a slug):**
   ```bash
   MILESTONE_SLUG=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/derive-milestone-slug.sh .vbw-planning)
   ```
   This reads ROADMAP.md phase names and outputs a numbered kebab-case slug (e.g., `01-setup-api-layer`). Override with `--tag` if provided. **Never use a hardcoded slug like "default" — always use the script output.**
2. Parse args: --tag=vN.N.N (custom tag), --no-tag (skip), --force (skip non-UAT audit).
3. Compute summary: from ROADMAP (phases), SUMMARY.md files (tasks/commits/deviations), REQUIREMENTS.md (satisfied count).
4. **Rolling summary (conditional):** If `rolling_summary=true` in config:
   ```bash
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-rolling-summary.sh \
     .vbw-planning/phases .vbw-planning/ROLLING-CONTEXT.md 2>/dev/null || true
   ```
   Compiles final rolling context before artifacts move to milestones/. Fail-open.
   When `rolling_summary=false`: skip.
5. Archive: `mkdir -p .vbw-planning/milestones/{SLUG}`. Move ROADMAP.md, STATE.md, and phases/ to milestones/{SLUG}/. If `.vbw-planning/CONTEXT.md` exists, move it to milestones/{SLUG}/CONTEXT.md. Use the **Write** tool (not Bash) to create `.vbw-planning/milestones/{SLUG}/SHIPPED.md` — this ensures PostToolUse hooks fire for artifact tracking. Delete stale RESUME.md.
5b. **Persist project-level state:** After archiving, run:
   ```bash
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/persist-state-after-ship.sh \
     .vbw-planning/milestones/{SLUG}/STATE.md .vbw-planning/STATE.md "{PROJECT_NAME}"
   ```
   This extracts project-level sections (Todos, Decisions, Blockers, Codebase Profile) from the archived STATE.md and writes a fresh root STATE.md. Milestone-specific sections (Current Phase, Activity Log, Phase Status) stay in the archive only. Fail-open: if the script fails, warn but continue.
6. Planning commit boundary (conditional):
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "archive milestone {SLUG}" .vbw-planning/config.json
   else
     echo "VBW: planning-git.sh unavailable; skipping planning git boundary commit" >&2
   fi
   ```
   Run this BEFORE branch merge/tag so shipped planning state is committed.
7. Git branch merge: if `milestone/{SLUG}` branch exists, merge --no-ff. Conflict -> abort, warn. No branch -> skip.
8. Git tag: unless --no-tag, `git tag -a {tag} -m "Shipped milestone: {name}"`. Default: `milestone/{SLUG}`.
9. Regenerate CLAUDE.md: update Active Context, remove shipped refs. Preserve non-VBW content — only replace VBW-managed sections, keep user's own sections intact.
10. Present: Phase Banner with metrics (phases, tasks, commits, requirements, deviations), archive path, tag, branch status, memory status. Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh vibe`.

### Pure-Vibe Phase Loop

After Execute mode completes (autonomy=pure-vibe only): if more unbuilt phases exist, auto-continue to next phase (Plan + Execute). Loop until `next_phase_state=all_done` or error. Other autonomy levels: STOP after phase.

**CRITICAL — Between iterations:** Before starting the next phase's Plan mode, verify ALL agents from the previous phase (Dev, QA) have been shut down via the Execute mode Step 5 HARD GATE. Do NOT enter Plan mode while prior Execute agents are still active. If unsure (e.g., after compaction), send `shutdown_request` to any teammates that may still exist from the prior Execute team and call TeamDelete before continuing.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md for all output except Verify mode (UAT files use plain markdown — do NOT read brand-essentials during verification).

Per-mode output:
- **Bootstrap:** project-defined banner + transition to scoping
- **Scope:** phases-created summary + STOP
- **Discuss:** ✓ for captured answers, Next Up Block
- **Assumptions:** numbered list with confidence indicators: ✓ confirmed (high), ⚡ validated (medium), ? resolved (low), ✗ corrected, ○ expanded (user added nuance), Next Up
- **Plan:** Phase Banner (double-line box), plan list with waves/tasks, Effort, Next Up
- **Execute:** Phase Banner, plan results (✓/✗), Metrics (plans, effort, deviations), QA result, "What happened" (NRW-02), Next Up
- **Add/Insert/Remove Phase:** Phase Banner, ✓ checklist, Next Up
- **Archive:** Phase Banner, Metrics (phases, tasks, commits, reqs, deviations), archive path, tag, branch, memory status, Next Up

Rules: Phase Banner (double-line box), ◆ running, ✓ complete, ✗ failed, ○ skipped, Metrics Block, Next Up Block, no ANSI color codes.

Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh vibe {result}` for Next Up suggestions.

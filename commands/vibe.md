---
name: vbw:vibe
category: lifecycle
description: "The one command. Detects state, parses intent, routes to any lifecycle mode -- bootstrap, scope, plan, execute, verify, discuss, archive, and more."
argument-hint: "[intent or flags] [--plan] [--execute] [--verify] [--discuss] [--assumptions] [--scope] [--add] [--insert] [--remove] [--archive] [--yolo] [--effort=level] [--skip-qa] [--skip-audit] [--plan=NN] [N]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
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
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}" && break; done; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; rm -f "$LINK"; ln -s "$REAL_R" "$LINK" 2>/dev/null || { echo "VBW: plugin root link failed" >&2; exit 1; }; STAMP="/tmp/.vbw-phase-detect-stamp-${SESSION_KEY}.txt"; : > "$STAMP"; bash "$LINK/scripts/phase-detect.sh" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt" 2>/dev/null || echo "phase_detect_error=true" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; echo "$LINK"`
```

Pre-computed state (via phase-detect.sh):
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; S="/tmp/.vbw-phase-detect-stamp-${SESSION_KEY}.txt"; PD=""; [ -f "$P" ] && PD=$(cat "$P"); if [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ -L "$L" ]; then i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; S_M=0; P_M=0; [ -f "$S" ] && S_M=$(stat -c %Y "$S" 2>/dev/null || stat -f %m "$S" 2>/dev/null || echo 0); [ -f "$P" ] && P_M=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo 0); if [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ] && { [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ "$P_M" -lt "$S_M" ]; }; then PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""; fi; fi; if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then printf '%s' "$PD"; else echo "phase_detect_error=true"; fi`
```

Config:
```
!`cat .vbw-planning/config.json 2>/dev/null || echo "No config found"`
```

UAT issues (remediation only):
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; S="/tmp/.vbw-phase-detect-stamp-${SESSION_KEY}.txt"; PD=""; [ -f "$P" ] && PD=$(cat "$P"); if [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ -L "$L" ]; then i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; S_M=0; P_M=0; [ -f "$S" ] && S_M=$(stat -c %Y "$S" 2>/dev/null || stat -f %m "$S" 2>/dev/null || echo 0); [ -f "$P" ] && P_M=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo 0); if [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ] && { [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ "$P_M" -lt "$S_M" ]; }; then PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""; fi; fi; if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then echo "not_in_remediation"; else STATE=$(printf '%s' "$PD" | grep '^next_phase_state=' | head -1 | cut -d= -f2); if [ "$STATE" = "needs_uat_remediation" ]; then SLUG=$(printf '%s' "$PD" | grep '^next_phase_slug=' | head -1 | cut -d= -f2); PDIR=".vbw-planning/phases/$SLUG"; if [ -d "$PDIR" ]; then bash "$L/scripts/extract-uat-issues.sh" "$PDIR" 2>/dev/null || echo "uat_extract_error=true"; else echo "uat_extract_error=true"; fi; else echo "not_in_remediation"; fi; fi`
```

Milestone UAT issues (milestone recovery only):
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; S="/tmp/.vbw-phase-detect-stamp-${SESSION_KEY}.txt"; PD=""; [ -f "$P" ] && PD=$(cat "$P"); if [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ -L "$L" ]; then i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; S_M=0; P_M=0; [ -f "$S" ] && S_M=$(stat -c %Y "$S" 2>/dev/null || stat -f %m "$S" 2>/dev/null || echo 0); [ -f "$P" ] && P_M=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo 0); if [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ] && { [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ "$P_M" -lt "$S_M" ]; }; then PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""; fi; fi; if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then echo "not_milestone_recovery"; else MS_UAT=$(printf '%s' "$PD" | grep '^milestone_uat_issues=' | head -1 | cut -d= -f2); if [ "$MS_UAT" = "true" ]; then MS_DIRS=$(printf '%s' "$PD" | grep '^milestone_uat_phase_dirs=' | head -1 | cut -d= -f2); IFS='|' read -ra DIRS <<< "$MS_DIRS"; for d in "${DIRS[@]}"; do [ -d "$d" ] || continue; echo "milestone_phase_dir=$d"; bash "$L/scripts/extract-uat-issues.sh" "$d" 2>/dev/null || echo "uat_extract_error=true dir=$d"; echo "---"; done; else echo "not_milestone_recovery"; fi; fi`
```

Verify context (verify routing only — needs_reverification OR auto_uat+unverified):
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; S="/tmp/.vbw-phase-detect-stamp-${SESSION_KEY}.txt"; PD=""; [ -f "$P" ] && PD=$(cat "$P"); if [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ -L "$L" ]; then i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; S_M=0; P_M=0; [ -f "$S" ] && S_M=$(stat -c %Y "$S" 2>/dev/null || stat -f %m "$S" 2>/dev/null || echo 0); [ -f "$P" ] && P_M=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo 0); if [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ] && { [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ "$P_M" -lt "$S_M" ]; }; then PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""; fi; fi; if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then echo "not_verify_routing"; else STATE=$(printf '%s' "$PD" | grep '^next_phase_state=' | head -1 | cut -d= -f2); AUTO_UAT=$(printf '%s' "$PD" | grep '^config_auto_uat=' | head -1 | cut -d= -f2); HAS_UV=$(printf '%s' "$PD" | grep '^has_unverified_phases=' | head -1 | cut -d= -f2); TARGET=""; if [ "$STATE" = "needs_reverification" ]; then TARGET=$(printf '%s' "$PD" | grep '^next_phase_slug=' | head -1 | cut -d= -f2); elif [ "$AUTO_UAT" = "true" ] && [ "$HAS_UV" = "true" ]; then TARGET=$(printf '%s' "$PD" | grep '^first_unverified_slug=' | head -1 | cut -d= -f2); fi; if [ -n "$TARGET" ]; then PDIR=".vbw-planning/phases/$TARGET"; echo "verify_target_slug=$TARGET"; if [ -d "$PDIR" ] && [ -f "$L/scripts/compile-verify-context.sh" ]; then bash "$L/scripts/compile-verify-context.sh" "$PDIR" 2>/dev/null || echo "verify_context_error=true"; else echo "verify_context_error=true"; fi; echo "---"; if [ "$STATE" = "needs_reverification" ]; then echo "uat_resume=pending_archive"; elif [ -d "$PDIR" ] && [ -f "$L/scripts/extract-uat-resume.sh" ]; then bash "$L/scripts/extract-uat-resume.sh" "$PDIR" 2>/dev/null || echo "uat_resume=error"; else echo "uat_resume=error"; fi; else echo "not_verify_routing"; fi; fi`
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

ALWAYS confirm interpreted intent via AskUserQuestion before executing.

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

| Priority | Condition | Mode | Confirmation |
|---|---|---|---|
| 1 | `planning_dir_exists=false` | Init redirect | (redirect, no confirmation) |
| 2 | `project_exists=false` | Bootstrap | "No project defined. Set one up?" |
| 3 | `next_phase_state=needs_uat_remediation` | UAT Remediation | auto_uat=true: no confirmation. auto_uat=false: "Phase {NN} has unresolved UAT issues. Continue with remediation now?" |
| 4 | `next_phase_state=needs_reverification` | Re-verify | auto_uat=true: no confirmation. auto_uat=false: "Phase {NN} remediation complete. Run re-verification?" |
| 5 | `milestone_uat_issues=true` | Milestone UAT Recovery | "Milestone {slug} has unresolved UAT issues in {count} phase(s). Unarchive and remediate?" |
| 6 | `phase_count=0` | Scope | "Project defined but no phases. Scope the work?" |
| 7 | `config_auto_uat=true` AND `has_unverified_phases=true` AND `next_phase_state` != `all_done` | Verify | (no confirmation — auto_uat intent, mid-milestone) |
| 8 | `next_phase_state=needs_discussion` | Discuss | "Phase {NN} needs discussion before planning. Start discussion?" |
| 9 | `next_phase_state=needs_plan_and_execute` | Plan + Execute | "Phase {NN} needs planning and execution. Start?" |
| 10 | `next_phase_state=needs_execute` | Execute | "Phase {NN} is planned. Execute it?" |
| 11 | `next_phase_state=all_done` AND `config_auto_uat=true` AND `has_unverified_phases=true` | Verify | (no confirmation — auto_uat intent) |
| 12 | `next_phase_state=all_done` | Archive | "All phases complete. Run audit and archive?" |

**Re-verify after remediation:** When `next_phase_state=needs_reverification`, remediation is complete but the phase hasn't been re-verified. Run `bash {plugin-root}/scripts/prepare-reverification.sh {phase-dir}` to archive the old UAT and reset the remediation stage, then route to `/vbw:verify {phase-number}`. The `needs_reverification` state fires regardless of `auto_uat` — remediation always requires re-verification. The `auto_uat` flag only controls whether the user is prompted for confirmation.

**auto_uat mid-milestone:** When `config_auto_uat=true` and `has_unverified_phases=true` but `next_phase_state` is NOT `all_done`, route to Verify mode before continuing to the next phase. Use `first_unverified_phase` and `first_unverified_slug` from phase-detect output to target the specific phase: `/vbw:verify {first_unverified_phase}`. This ensures each completed phase gets UAT verification immediately after execution, even when later phases still need work. After verification completes, the next `/vbw:vibe` call re-runs phase-detect and routes to the next pending phase.

**auto_uat + all_done:** When `config_auto_uat=true` and `has_unverified_phases=true`, skip the Archive confirmation and route directly to Verify mode. Use `first_unverified_phase` from phase-detect output to target the specific phase: `/vbw:verify {first_unverified_phase}`. After verification completes, the next `/vbw:vibe` call re-runs phase-detect — if more unverified phases remain, it routes to Verify again; otherwise it falls through to Archive (priority 12).

**all_done + natural language:** If $ARGUMENTS describe new work (bug, feature, task) and state is `all_done`, route to Add Phase mode instead of Archive. Add Phase handles codebase context loading and research internally — do NOT spawn an Explore agent or do ad-hoc research before entering the mode.

**UAT remediation default:** When `next_phase_state=needs_uat_remediation`, plain `/vbw:vibe` must read that phase's UAT report and continue remediation directly. Do NOT require the user to manually specify `--discuss` or `--plan`.

**Milestone UAT recovery:** When `milestone_uat_issues=true` and active phases are empty, the latest shipped milestone has unresolved UAT issues. Present the user with options: (a) create remediation phases to fix the UAT issues, or (b) start fresh with new work (ignoring the stale UAT). Use `milestone_uat_count` to determine how many phases are affected. When `milestone_uat_count` > 1, parse `milestone_uat_phase_dirs` (pipe-separated) to read all UAT reports and display a consolidated issue summary. Use `milestone_uat_major_or_higher` to determine severity context.

**Remediation + require_phase_discussion:** Both in-phase UAT remediation and milestone-level remediation phases skip the discussion step via pre-seeded CONTEXT.md. When `uat-remediation-state.sh init` runs for in-phase remediation, it appends the UAT report to the existing CONTEXT.md and adds `pre_seeded: true` to its frontmatter — preserving the original discussion context while satisfying the `require_phase_discussion` gate. Milestone remediation phases created by `create-remediation-phase.sh` generate a fresh CONTEXT.md with `pre_seeded: true` (populated from the source UAT report). Both paths use the same `pre_seeded` mechanism so `suggest-next.sh` handles them uniformly.

### Confirmation Gate

Every mode triggers confirmation via AskUserQuestion before executing, with contextual options (recommended action + alternatives).
- **Exception:** `--yolo` skips all confirmation gates. Error guards (missing roadmap, uninitialized project) still halt.
- **Exception:** Flags skip confirmation (explicit intent).

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
  |---------|-------|-----------|
  | yolo | skip | 0 |
  | prototype | quick | 1-2 |
  | default | standard | 3-5 |
  | production | thorough | 5-8 |

  If `discovery_questions=false`: force depth=skip. Store DISCOVERY_DEPTH for B2.

- **B2: REQUIREMENTS.md (Discovery)** -- Behavior depends on DISCOVERY_DEPTH:
  - **B2.1: Domain Research (if not skip):** If DISCOVERY_DEPTH != skip:
    1. Extract domain from user's project description (the $NAME or $DESCRIPTION from B1)
    2. Resolve Scout model via `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-model.sh scout .vbw-planning/config.json /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/config/model-profiles.json` and Scout max turns via `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-max-turns.sh scout .vbw-planning/config.json "$(jq -r '.effort // \"balanced\"' .vbw-planning/config.json 2>/dev/null)"`
    3. Before composing the Scout task description, select skills from installed skills visible in your system context (use both skill names and descriptions). The Scout prompt MUST start with `<skill_activation>{For each selected skill: "Call Skill({skill-name})"} Do not skip any listed skill.</skill_activation>`. Use direct imperative language only.
    4. Spawn Scout agent via Task tool with prompt: "Research the {domain} domain. Write your findings directly to the output path. <output_path>.vbw-planning/domain-research.md</output_path> Structure as four sections: ## Table Stakes (features every {domain} app has), ## Common Pitfalls (what projects get wrong), ## Architecture Patterns (how similar apps are structured), ## Competitor Landscape (existing products). Use WebSearch. Be concise (2-3 bullets per section)."
    5. Set `subagent_type: "vbw:vbw-scout"`, `model: "${SCOUT_MODEL}"` and `timeout: 120000` in Task tool invocation. If `SCOUT_MAX_TURNS` is non-empty, also pass `maxTurns: ${SCOUT_MAX_TURNS}`. If `SCOUT_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).
    6. On success: Read `.vbw-planning/domain-research.md` (Scout wrote it directly). Extract brief summary (3-5 lines max). Display to user: "◆ Domain Research: {brief summary}\n\n✓ Research complete. Now let's explore your specific needs..."
    7. On failure: Log warning "⚠ Domain research timed out, proceeding with general questions". Set RESEARCH_AVAILABLE=false, continue.
  - **B2.2: Discussion Engine** -- Read `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/discussion-engine.md` and follow its protocol.
    - Context for the engine: "This is a new project. No phases yet." Use project description + domain research (if available) as input.
    - The engine handles calibration, gray area generation, exploration, and capture.
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
  Script handles: new file generation (heading + core value + VBW sections), existing file preservation (replaces only VBW-managed sections: Active Context, VBW Rules, Project Conventions, Commands, Plugin Isolation; preserves all other content). Omit the fourth argument if no existing CLAUDE.md. Max 200 lines.
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
5. Update STATE.md: Phase 1, status "Pending planning". Do NOT write next-action suggestions (e.g. "Run /vbw:vibe --plan 1") into the Todos section — those are ephemeral display output from suggest-next.sh, not persistent state.
6. Display "Scoping complete. {N} phases created." STOP -- do not auto-continue to planning.

### Mode: Discuss

**Guard:** Initialized, phase exists in roadmap.
**Phase auto-detection:** First phase without `*-CONTEXT.md`. All discussed: STOP "All phases discussed. Specify: `/vbw:vibe --discuss N`"

**Steps:**
1. Determine target phase from $ARGUMENTS or auto-detection.
2. Read `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/discussion-engine.md` and follow its protocol for the target phase.
3. Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh vibe`.

### Mode: Assumptions

**Guard:** Initialized, phase exists in roadmap.
**Phase auto-detection:** Same as Discuss mode.

**Steps:**
1. Load context: ROADMAP.md, REQUIREMENTS.md, PROJECT.md, STATE.md, CONTEXT.md (if exists), codebase signals.
2. Generate 5-10 assumptions by impact: scope (included/excluded), technical (implied approaches), ordering (sequencing), dependency (prior phases), user preference (defaults without stated preference).
3. Gather feedback per assumption: "Confirm, correct, or expand?" Confirm=proceed, Correct=user provides answer, Expand=user adds nuance.
4. Present grouped by status (confirmed/corrected/expanded). This mode does NOT write files. For persistence: "Run `/vbw:vibe --discuss {NN}` to capture as CONTEXT.md." Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh vibe`.

### Mode: UAT Remediation

**Guard:** Initialized, target phase has `*-UAT.md` with `status: issues_found`.

**Chain state tracking:** This mode uses `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh` to persist the current stage of the remediation chain on disk. This ensures correct resumption after compaction or session restart — the chain does NOT rely on prompt memory alone.

**Steps:**
1. Resolve target phase from pre-computed state (`next_phase`, `next_phase_slug`) when `next_phase_state=needs_uat_remediation`. Set `PHASE_DIR` to the resolved phase directory path.
   **Milestone path guard (NON-NEGOTIABLE):** If `PHASE_DIR` contains `.vbw-planning/milestones/` (e.g., `.vbw-planning/milestones/*/phases/`), STOP — this is an archived milestone. UAT Remediation operates only on active phases in `.vbw-planning/phases/`. Display: "⚠ UAT issues found in archived milestone, not active phases. Routing to Milestone UAT Recovery." Then route to Milestone UAT Recovery mode instead.
2. **Use pre-computed UAT issues** from the "UAT issues (remediation only)" section above. The `extract-uat-issues.sh` output provides compact `ID|SEVERITY|DESCRIPTION` lines — no need to read the full UAT file. If the pre-computed section shows `uat_extract_error=true`, fall back to reading `{phase}-UAT.md` directly.
3. Treat the UAT issues as source-of-truth scope. Do NOT ask the user to restate issues already recorded in UAT.
4. **Read or initialize remediation stage:**
   ```bash
   STAGE=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh get "$PHASE_DIR")
   ```
   - If `STAGE=none`: initialize based on severity. **Run directly (do NOT capture with `$()`)** — the init output contains both the stage and the pre-seeded CONTEXT.md content:
     ```bash
     bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh init "$PHASE_DIR" "major"
     # or "minor" when uat_issues_major_or_higher=false
     ```
     The first line of output is the stage (`research` or `fix`). After the `---CONTEXT---` separator, the full pre-seeded CONTEXT.md content follows — **use this directly as your remediation context. Do NOT separately read UAT.md or CONTEXT.md files.**
   - If `STAGE=done`: UAT remediation already completed for this phase. Display "Remediation already completed. Run `/vbw:verify --resume` to re-test." STOP.
   - Otherwise: resume at the persisted stage (handles compaction recovery).
5. **Execute the current stage** based on `STAGE`:
   **File read prohibition:** Do NOT read `{phase}-UAT.md` or `{phase}-CONTEXT.md` — all UAT data is already available from step 2 (pre-computed issue lines) and step 4 (CONTEXT.md content emitted by `init`). Reading these files wastes tool calls.
   - `research`: Execute **Plan mode step 3 only** (research persistence) for this phase. Spawn Scout (with `subagent_type: "vbw:vbw-scout"`) with the pre-computed UAT issue lines (`ID|SEVERITY|DESCRIPTION` from step 2) so Scout investigates the relevant code areas for each issue. Pass `<output_path>{phase-dir}/{phase}-{MM}-RESEARCH.md</output_path>` in the Scout prompt so Scout writes the file directly. Before composing the Scout task description, select skills from installed skills visible in your system context (use both skill names and descriptions). The Scout prompt MUST start with `<skill_activation>{For each selected skill: "Call Skill({skill-name})"} Do not skip any listed skill.</skill_activation>`. Use direct imperative language only. After Scout completes, confirm RESEARCH.md exists (read first line), then advance:
     ```bash
     bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh advance "$PHASE_DIR"
     ```
     Then continue to the next stage (`plan`).
   - `plan`: Execute **Plan mode steps 1-11 above** for the same phase. "No separate discussion" means skip Discuss assumption-gathering (step 2) — the UAT report serves as scope. Step 3 will find the existing RESEARCH.md from the `research` stage and include it in Lead's context (no re-run of Scout needed). After planning completes, advance:
     ```bash
     bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh advance "$PHASE_DIR"
     ```
     Then continue to the next stage (`execute`), respecting autonomy confirmation rules.
   - `execute`: Continue through normal Execute flow for that phase. After execution completes, advance:
     ```bash
     bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh advance "$PHASE_DIR"
     ```
   - `fix` (minor-only path): Route to a quick-fix implementation path for the same phase using the extracted UAT issue list as task input (equivalent to `/vbw:fix`, but without requiring the user to invoke it manually). After changes, advance:
     ```bash
     bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh advance "$PHASE_DIR"
     ```
     Suggest `/vbw:verify --resume`.
6. Present a remediation summary with: phase, issue count, severity mix, current stage, and chosen path (`research -> plan -> execute` or quick-fix).

### Mode: Milestone UAT Recovery

**Guard:** `milestone_uat_issues=true` from phase-detect.sh. Active phases dir is empty/all_done but the latest shipped milestone has unresolved UAT issues.

This mode handles the case where a milestone was archived before UAT issues were resolved (e.g., due to a missing audit gate in older versions).

**Steps:**
1. Use pre-computed milestone UAT issues from the "Milestone UAT issues" context block above. Each block starts with `milestone_phase_dir=<path>` followed by `extract-uat-issues.sh` output (header line + issue lines). Do NOT read UAT files from the milestone — all issue data is already extracted.
   If `milestone_uat_count` > 1, multiple blocks are present (one per affected phase, separated by `---`). If `milestone_uat_count` = 1, a single block is present.
2. Display the unresolved issues to the user with milestone context (milestone slug, affected phase count, severity mix).
3. Present options via AskUserQuestion:
   - **"Create a remediation milestone"** (recommended for major/critical): Create one remediation phase per affected milestone phase. Auto-populate each phase goal from the UAT issue descriptions. Route to Plan mode for the first created phase.
   - **"Start fresh with new work"**: Acknowledge the stale UAT issues, mark them as acknowledged (`.remediated`) so they don't re-trigger archive blocking, then proceed as if all_done. The user can define new work via `/vbw:vibe` with arguments.
4. If the user chooses remediation: create remediation phases via script — one per affected milestone phase:
   ```bash
   IFS='|' read -ra UAT_DIRS <<< "$milestone_uat_phase_dirs"
   for dir in "${UAT_DIRS[@]}"; do
     bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/create-remediation-phase.sh .vbw-planning "$dir"
   done
   ```
   The script also writes a `.remediated` marker in each source milestone phase dir to prevent re-triggering on future sessions. After creating all phases, write a ROADMAP.md and update STATE.md reflecting the remediation phases, then route to Plan mode for the first phase.
5. If the user chooses start-fresh: persist acknowledgement markers for all affected archived phases before continuing:
   ```bash
   TARGET_PHASE_DIRS="$milestone_uat_phase_dirs"
   if [ -z "$TARGET_PHASE_DIRS" ] && [ "$milestone_uat_phase_dir" != "none" ]; then
     TARGET_PHASE_DIRS="$milestone_uat_phase_dir"
   fi
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/mark-milestone-remediated.sh .vbw-planning "$TARGET_PHASE_DIRS"
   ```
   Then continue to normal all_done/new-work routing.

### Mode: Plan

**Guard:** Initialized, roadmap exists, phase exists.
**Phase auto-detection:** First phase without PLAN.md. All planned: STOP "All phases planned. Specify phase: `/vbw:vibe --plan N`"
**Milestone path guard:** If `{phases_dir}` contains `.vbw-planning/milestones/`, STOP "Cannot plan inside archived milestones." Archived milestones are read-only.

**Steps:**
1. **Parse args:** Phase number (optional, auto-detected), --effort (optional, falls back to config).
2. **Phase context:** If `{phase-dir}/{phase}-CONTEXT.md` exists, include it in Lead agent context. If not, proceed without — users who want context run `/vbw:discuss {NN}` first.
3. **Research persistence (REQ-08, graduated):** If effort != turbo:
   - Determine the next plan number `{MM}`: glob `*-PLAN.md` in the phase dir, extract the highest `{MM}` value, add 1 (zero-padded to 2 digits). If no plans exist, `{MM}=01`.
   - Check for per-plan research `{phase-dir}/{phase}-{MM}-RESEARCH.md` (preferred) or legacy `{phase-dir}/{phase}-RESEARCH.md` (fallback).
   - **If neither exists:** Spawn Scout agent to research the phase goal, requirements, and relevant codebase patterns. Scout writes its findings directly to the output path. Pass `<output_path>{phase-dir}/{phase}-{MM}-RESEARCH.md</output_path>` in the Scout prompt so Scout writes the file using its Write tool. If a legacy `{phase-dir}/{phase}-RESEARCH.md` exists, delete it after Scout writes the per-plan file to avoid stale context. After Scout completes, confirm the file exists (read first line). Resolve Scout model:
     ```bash
     SCOUT_MODEL=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-model.sh scout .vbw-planning/config.json /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/config/model-profiles.json)
     SCOUT_MAX_TURNS=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-max-turns.sh scout .vbw-planning/config.json "{effort}")
     ```
   Pass `subagent_type: "vbw:vbw-scout"` and `model: "${SCOUT_MODEL}"` to the Task tool. If `SCOUT_MAX_TURNS` is non-empty, also pass `maxTurns: ${SCOUT_MAX_TURNS}`. If `SCOUT_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited). Before composing the Scout task description, select skills from installed skills visible in your system context (use both skill names and descriptions). The Scout prompt MUST start with `<skill_activation>{For each selected skill: "Call Skill({skill-name})"} Do not skip any listed skill.</skill_activation>`. Use direct imperative language only.
   - **If exists (per-plan or legacy):** Include it in Lead's context for incremental refresh. Lead may update the per-plan RESEARCH.md if new information emerges.
   - **On failure:** Log warning, continue planning without research. Do not block.
   - If effort=turbo: skip entirely.
4. **Context compilation:** If `config_context_compiler=true`, run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-context.sh {phase} lead {phases_dir}`. Include `.context-lead.md` in Lead agent context if produced.
5. **Turbo shortcut:** If effort=turbo, skip Lead. Read phase reqs from ROADMAP.md, create single lightweight plan as `{NN}-PLAN.md` in the phase directory.
6. **Other efforts:**
   - Resolve Lead model:
     ```bash
     LEAD_MODEL=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-model.sh lead .vbw-planning/config.json /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/config/model-profiles.json)
       LEAD_MAX_TURNS=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-max-turns.sh lead .vbw-planning/config.json "{effort}")
     if [ $? -ne 0 ]; then
       echo "$LEAD_MODEL" >&2
       exit 1
     fi
     ```
   - **Team creation:** Read prefer_teams config:
     ```bash
     PREFER_TEAMS=$(jq -r '.prefer_teams // "always"' .vbw-planning/config.json 2>/dev/null)
     ```
     Decision tree:
     - `prefer_teams='always'`: Create team even for Lead-only (no Scout)
     - `prefer_teams='when_parallel'`: Create team only if Scout was spawned (research needed), else no team
     - `prefer_teams='auto'`: Same as when_parallel (Lead-only is low-risk)

     When team should be created (based on prefer_teams):
     - Create team via TeamCreate: `team_name="vbw-plan-{NN}"`, `description="Planning Phase {NN}: {phase-name}"`
     - Spawn Scout (if spawned in step 3) with `subagent_type: "vbw:vbw-scout"`, `team_name: "vbw-plan-{NN}"`, `name: "scout"` parameters on the Task tool invocation.
     - Spawn Lead with `subagent_type: "vbw:vbw-lead"`, `team_name: "vbw-plan-{NN}"`, `name: "lead"` parameters on the Task tool invocation.
     - **HARD GATE — Shutdown before proceeding (NON-NEGOTIABLE):** After all team agents complete their work, you MUST shut down the team BEFORE validating output, presenting results, auto-chaining to Execute, or asking the user anything. This gate CANNOT be skipped, deferred, or optimized away — even after compaction. Lingering agents burn API credits silently.
       1. Send `shutdown_request` to EVERY active teammate via SendMessage (Lead, Scout — excluding yourself, the orchestrator)
       2. Wait for each `shutdown_response` (approved=true). If rejected, re-request (max 3 attempts per teammate — then proceed).
       3. Call TeamDelete for team "vbw-plan-{NN}"
       4. Verify: after TeamDelete, there must be ZERO active teammates. If tmux panes still show agent labels, something went wrong — do NOT proceed.
       5. Only THEN proceed to step 7
       **WHY THIS EXISTS:** Without this gate, each Plan invocation spawns a new Lead that lingers in tmux. After 2-3 phases, multiple @lea panes accumulate, each burning API credits doing nothing. This is the #1 user-reported cost issue.

     When team should NOT be created (Lead-only with when_parallel/auto):
     - Spawn vbw-lead as subagent via Task tool without team (single agent, no team overhead).
   - Before composing the Lead task description, select skills from installed skills visible in your system context (use both skill names and descriptions). The Lead prompt MUST start with `<skill_activation>{For each selected skill: "Call Skill({skill-name})"} Do not skip any listed skill.</skill_activation>`. Use direct imperative language only.
   - Spawn vbw-lead as subagent via Task tool with compiled context (or full file list as fallback).
   - **CRITICAL:** Set `subagent_type: "vbw:vbw-lead"` and `model: "${LEAD_MODEL}"` in the Task tool invocation. If `LEAD_MAX_TURNS` is non-empty, also pass `maxTurns: ${LEAD_MAX_TURNS}`. If `LEAD_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).
   - **CRITICAL:** Include in the Lead prompt: "Plans will be executed by a team of parallel Dev agents — one agent per plan. Maximize wave 1 plans (no deps) so agents start simultaneously. Ensure same-wave plans modify disjoint file sets to avoid merge conflicts."
   - Display `◆ Spawning Lead agent...` -> `✓ Lead agent complete`.
7. **Normalize plan filenames:**
    ```bash
    NORM_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
    if [ -f "$NORM_SCRIPT" ]; then
      bash "$NORM_SCRIPT" "{phase_dir}"
    fi
    ```
    This catches any misnamed files written by Lead (e.g., turbo mode or models that bypass the PreToolUse block).
8. **Validate output:** Verify PLAN.md has valid frontmatter (phase, plan, title, wave, depends_on, must_haves) and tasks. Check wave deps acyclic.
9. **Present:** Update STATE.md (phase position, plan count, status=Planned). Resolve model profile:
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
10. **Planning commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "plan phase {NN}" .vbw-planning/config.json
   else
     echo "VBW: planning-git.sh unavailable; skipping planning git boundary commit" >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits planning artifacts if changed. `auto_push=always` pushes when upstream exists.
11. **Pre-chain verification:** Before auto-chaining or presenting results, confirm the planning team was fully shut down (step 6 HARD GATE completed). If you skipped the gate or are unsure after compaction, send `shutdown_request` to any teammates that may still be active and call TeamDelete before continuing. NEVER enter Execute mode with a prior planning team still alive.
12. **Cautious gate (autonomy=cautious only):** STOP after planning. Ask "Plans ready. Execute Phase {NN}?" Other levels: auto-chain.

### Mode: Execute

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
   Include compiled context paths in Dev and QA task descriptions.

Then Read the protocol file and execute Steps 2-5 as written.

### Mode: Verify

**Guard:** Initialized, phase has `*-SUMMARY.md` files.
No SUMMARY.md: STOP "Phase {NN} has no completed plans. Run /vbw:vibe first."
**Phase auto-detection:** First phase with `*-SUMMARY.md` but no canonical `*-UAT.md` (exclude `*-SOURCE-UAT.md` copies). All verified: STOP "All phases have UAT results. Specify: `/vbw:verify {NN}`"

**Steps:**
1. Read `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/commands/verify.md` protocol.
2. Execute the verify protocol for the target phase. Use the pre-computed "Verify context" block from this command's Context section — it contains the PLAN/SUMMARY aggregation and UAT resume metadata for the target phase. Pass this data through to the verify protocol steps so they do NOT read individual PLAN/SUMMARY files or scan-parse UAT.md for resume state.
3. Display results per verify.md output format.

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
   - Spawn Scout agent (with `subagent_type: "vbw:vbw-scout"`) to research the problem in the codebase. Pass `<output_path>{phase-dir}/{NN}-RESEARCH.md</output_path>` in the Scout prompt so Scout writes its findings directly using its Write tool. Before composing the Scout task description, select skills from installed skills visible in your system context (use both skill names and descriptions). The Scout prompt MUST start with `<skill_activation>{For each selected skill: "Call Skill({skill-name})"} Do not skip any listed skill.</skill_activation>`. Use direct imperative language only. After Scout completes, confirm the file exists (read first line).
   - Use Scout findings to write an informed phase goal and success criteria in ROADMAP.md.
   - On failure: log warning, write phase goal from $ARGUMENTS alone. Do not block.
   - **This eliminates duplicate research** — Plan mode step 3 checks for existing RESEARCH.md and skips Scout if found.
6. Update ROADMAP.md: append phase list entry, append Phase Details section (using Scout findings if available), add progress row.
7. Present: Phase Banner with position, goal. Checklist for roadmap update + dir creation. Next Up: `/vbw:vibe --discuss` or `/vbw:vibe --plan`.

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
6. **Problem research (conditional):** Same as Add Phase step 5 — if $ARGUMENTS contain a problem description, spawn Scout (with `subagent_type: "vbw:vbw-scout"`) to research the codebase. Pass `<output_path>{phase-dir}/{NN}-RESEARCH.md</output_path>` in the Scout prompt so Scout writes the file directly. This prevents Plan mode from duplicating the research.
7. Update ROADMAP.md: insert new phase entry + details at position (using Scout findings if available), renumber subsequent entries/headers/cross-refs, update progress table.
8. Present: Phase Banner with renumber count, phase changes, file checklist, Next Up.

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
6. Present: Phase Banner with renumber count, phase changes, file checklist, Next Up.

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
5. Verification: VERIFICATION.md files exist + PASS. Missing=WARN, failed=FAIL
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
5. Archive: `mkdir -p .vbw-planning/milestones/`. Move roadmap, state, phases to milestones/{SLUG}/. Write SHIPPED.md. Delete stale RESUME.md.
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

**CRITICAL — Between iterations:** Before starting the next phase's Plan mode, verify ALL agents from the previous phase (Dev, QA, Lead, Scout) have been shut down via the Execute mode Step 5 HARD GATE and the Plan mode HARD GATE. Do NOT spawn a new Lead while a prior Lead is still active. If unsure (e.g., after compaction), send `shutdown_request` to any teammates that may still exist from prior teams and call TeamDelete before creating a new team.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md for all output.

Per-mode output:
- **Bootstrap:** project-defined banner + transition to scoping
- **Scope:** phases-created summary + STOP
- **Discuss:** ✓ for captured answers, Next Up Block
- **Assumptions:** numbered list, ✓ confirmed, ✗ corrected, ○ expanded, Next Up
- **Plan:** Phase Banner (double-line box), plan list with waves/tasks, Effort, Next Up
- **Execute:** Phase Banner, plan results (✓/✗), Metrics (plans, effort, deviations), QA result, "What happened" (NRW-02), Next Up
- **Add/Insert/Remove Phase:** Phase Banner, ✓ checklist, Next Up
- **Archive:** Phase Banner, Metrics (phases, tasks, commits, reqs, deviations), archive path, tag, branch, memory status, Next Up

Rules: Phase Banner (double-line box), ◆ running, ✓ complete, ✗ failed, ○ skipped, Metrics Block, Next Up Block, no ANSI color codes.

Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh vibe {result}` for Next Up suggestions.

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

Working directory: `!`pwd``
Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}``

Pre-computed state (via phase-detect.sh):
```
!`bash ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}/scripts/phase-detect.sh 2>/dev/null || echo "phase_detect_error=true"`
```

Config:
```
!`cat .vbw-planning/config.json 2>/dev/null || echo "No config found"`
```

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
- `--skip-audit`: skip pre-archive audit
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

| Priority | Condition | Mode | Confirmation |
|---|---|---|---|
| 1 | `planning_dir_exists=false` | Init redirect | (redirect, no confirmation) |
| 2 | `project_exists=false` | Bootstrap | "No project defined. Set one up?" |
| 3 | `phase_count=0` | Scope | "Project defined but no phases. Scope the work?" |
| 4 | `next_phase_state=needs_uat_remediation` | UAT Remediation | "Phase {N} has unresolved UAT issues. Continue with remediation now?" |
| 5 | `next_phase_state=needs_plan_and_execute` | Plan + Execute | "Phase {N} needs planning and execution. Start?" |
| 6 | `next_phase_state=needs_execute` | Execute | "Phase {N} is planned. Execute it?" |
| 7 | `next_phase_state=all_done` | Archive | "All phases complete. Run audit and archive?" |

**all_done + natural language:** If $ARGUMENTS describe new work (bug, feature, task) and state is `all_done`, route to Add Phase mode instead of Archive. Add Phase handles codebase context loading and research internally — do NOT spawn an Explore agent or do ad-hoc research before entering the mode.

**UAT remediation default:** When `next_phase_state=needs_uat_remediation`, plain `/vbw:vibe` must read that phase's UAT report and continue remediation directly. Do NOT require the user to manually specify `--discuss` or `--plan`.

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
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-project.sh .vbw-planning/PROJECT.md "$NAME" "$DESCRIPTION"
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
   2. Resolve Scout model via `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh scout .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json` and Scout max turns via `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh scout .vbw-planning/config.json "$(jq -r '.effort // \"balanced\"' .vbw-planning/config.json 2>/dev/null)"`
    3. Spawn Scout agent via Task tool with prompt: "Research the {domain} domain. Return your findings as structured markdown with four sections: ## Table Stakes (features every {domain} app has), ## Common Pitfalls (what projects get wrong), ## Architecture Patterns (how similar apps are structured), ## Competitor Landscape (existing products). Use WebSearch. Be concise (2-3 bullets per section). Do NOT attempt to write files — return findings in your response."
   4. Set `model: "${SCOUT_MODEL}"`, `maxTurns: ${SCOUT_MAX_TURNS}`, and `timeout: 120000` in Task tool invocation
    5. On success: Write Scout's returned findings to `.vbw-planning/domain-research.md`. Extract brief summary (3-5 lines max). Display to user: "◆ Domain Research: {brief summary}\n\n✓ Research complete. Now let's explore your specific needs..."
    6. On failure: Log warning "⚠ Domain research timed out, proceeding with general questions". Set RESEARCH_AVAILABLE=false, continue.
  - **B2.2: Discussion Engine** -- Read `${CLAUDE_PLUGIN_ROOT}/references/discussion-engine.md` and follow its protocol.
    - Context for the engine: "This is a new project. No phases yet." Use project description + domain research (if available) as input.
    - The engine handles calibration, gray area generation, exploration, and capture.
    - Output: `discovery.json` with answered/inferred/deferred arrays.
  - **If skip (yolo profile or discovery_questions=false):** Ask 2 minimal static questions via AskUserQuestion:
    1. "What are the must-have features for this project?" Options: ["Core functionality only", "A few essential features", "Comprehensive feature set", "Let me explain..."]
    2. "Who will use this?" Options: ["Just me", "Small team (2-10 people)", "Many users (100+)", "Let me explain..."]
    Record answers to `.vbw-planning/discovery.json` with `{"answered":[],"inferred":[],"deferred":[]}`.
  - **After discovery (all depths):** Call:
    ```
    bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-requirements.sh .vbw-planning/REQUIREMENTS.md .vbw-planning/discovery.json .vbw-planning/domain-research.md
    ```

- **B3: ROADMAP.md** -- Suggest 3-5 phases from requirements. If `.vbw-planning/codebase/META.md` exists, read PATTERNS.md, ARCHITECTURE.md, and CONCERNS.md (whichever exist) from `.vbw-planning/codebase/`. Each phase: name, goal, mapped reqs, success criteria. Write phases JSON to temp file, then call:
  ```
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-roadmap.sh .vbw-planning/ROADMAP.md "$PROJECT_NAME" /tmp/vbw-phases.json
  ```
  Script handles ROADMAP.md generation and phase directory creation.
- **B4: STATE.md** -- Extract project name, milestone name, and phase count from earlier steps. Call:
  ```
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-state.sh .vbw-planning/STATE.md "$PROJECT_NAME" "$MILESTONE_NAME" "$PHASE_COUNT"
  ```
  Script handles today's date, Phase 1 status, empty decisions, and 0% progress.
- **B5: Brownfield summary** -- If BROWNFIELD=true AND no codebase/: count files by ext, check tests/CI/Docker/monorepo, add Codebase Profile to STATE.md.
- **B6: CLAUDE.md** -- Extract project name and core value from PROJECT.md. If root CLAUDE.md exists, pass it as EXISTING_PATH for section preservation. Call:
  ```
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-claude.sh CLAUDE.md "$PROJECT_NAME" "$CORE_VALUE" [CLAUDE.md]
  ```
  Script handles: new file generation (heading + core value + VBW sections), existing file preservation (replaces only VBW-managed sections: Active Context, VBW Rules, Installed Skills, Project Conventions, Commands, Plugin Isolation; preserves all other content). Omit the fourth argument if no existing CLAUDE.md. Max 200 lines.
- **B7: Planning commit boundary (conditional)** -- Run:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/planning-git.sh commit-boundary "bootstrap project files" .vbw-planning/config.json
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
2. Read `${CLAUDE_PLUGIN_ROOT}/references/discussion-engine.md` and follow its protocol for the target phase.
3. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh vibe`.

### Mode: Assumptions

**Guard:** Initialized, phase exists in roadmap.
**Phase auto-detection:** Same as Discuss mode.

**Steps:**
1. Load context: ROADMAP.md, REQUIREMENTS.md, PROJECT.md, STATE.md, CONTEXT.md (if exists), codebase signals.
2. Generate 5-10 assumptions by impact: scope (included/excluded), technical (implied approaches), ordering (sequencing), dependency (prior phases), user preference (defaults without stated preference).
3. Gather feedback per assumption: "Confirm, correct, or expand?" Confirm=proceed, Correct=user provides answer, Expand=user adds nuance.
4. Present grouped by status (confirmed/corrected/expanded). This mode does NOT write files. For persistence: "Run `/vbw:vibe --discuss {N}` to capture as CONTEXT.md." Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh vibe`.

### Mode: UAT Remediation

**Guard:** Initialized, target phase has `*-UAT.md` with `status: issues_found`.

**Chain state tracking:** This mode uses `${CLAUDE_PLUGIN_ROOT}/scripts/uat-remediation-state.sh` to persist the current stage of the remediation chain on disk. This ensures correct resumption after compaction or session restart — the chain does NOT rely on prompt memory alone.

**Steps:**
1. Resolve target phase from pre-computed state (`next_phase`, `next_phase_slug`) when `next_phase_state=needs_uat_remediation`. Set `PHASE_DIR` to the resolved phase directory path.
2. Read latest `{phase}-UAT.md` in the target phase directory. Extract all issues (`Pxx-Ty` entries) with description and severity.
3. Treat the UAT report as source-of-truth scope. Do NOT ask the user to restate issues already recorded in UAT.
4. **Read or initialize remediation stage:**
   ```bash
   STAGE=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/uat-remediation-state.sh get "$PHASE_DIR")
   ```
   - If `STAGE=none`: initialize based on severity:
     ```bash
     STAGE=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/uat-remediation-state.sh init "$PHASE_DIR" "major")
     # or "minor" when uat_issues_major_or_higher=false
     ```
   - If `STAGE=done`: UAT remediation already completed for this phase. Display "Remediation already completed. Run `/vbw:verify --resume` to re-test." STOP.
   - Otherwise: resume at the persisted stage (handles compaction recovery).
5. **Execute the current stage** based on `STAGE`:
   - `discuss`: Route into Discuss mode for the same phase, using UAT issues as the discussion agenda. Capture/merge decisions into `{phase}-CONTEXT.md` (create if missing), with explicit references to each UAT issue (`Pxx-Ty`). After discuss completes, advance:
     ```bash
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/uat-remediation-state.sh advance "$PHASE_DIR"
     ```
     Then continue to the next stage (`plan`).
   - `plan`: Route into Plan mode for the same phase, with UAT issues + discuss decisions as required planning inputs. After planning completes, advance:
     ```bash
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/uat-remediation-state.sh advance "$PHASE_DIR"
     ```
     Then continue to the next stage (`execute`), respecting autonomy confirmation rules.
   - `execute`: Continue through normal Execute flow for that phase. After execution completes, advance:
     ```bash
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/uat-remediation-state.sh advance "$PHASE_DIR"
     ```
   - `fix` (minor-only path): Route to a quick-fix implementation path for the same phase using the extracted UAT issue list as task input (equivalent to `/vbw:fix`, but without requiring the user to invoke it manually). After changes, advance:
     ```bash
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/uat-remediation-state.sh advance "$PHASE_DIR"
     ```
     Suggest `/vbw:verify --resume`.
6. Present a remediation summary with: phase, issue count, severity mix, current stage, and chosen path (`discuss -> plan -> execute` or quick-fix).

### Mode: Plan

**Guard:** Initialized, roadmap exists, phase exists.
**Phase auto-detection:** First phase without PLAN.md. All planned: STOP "All phases planned. Specify phase: `/vbw:vibe --plan N`"

**Steps:**
1. **Parse args:** Phase number (optional, auto-detected), --effort (optional, falls back to config).
2. **Phase context:** If `{phase-dir}/{phase}-CONTEXT.md` exists, include it in Lead agent context. If not, proceed without — users who want context run `/vbw:discuss N` first.
3. **Research persistence (REQ-08):** If `v3_plan_research_persist=true` in config AND effort != turbo:
   - Check for `{phase-dir}/{phase}-RESEARCH.md`.
   - **If missing:** Spawn Scout agent to research the phase goal, requirements, and relevant codebase patterns. Scout returns structured findings with sections: `## Findings`, `## Relevant Patterns`, `## Risks`, `## Recommendations`. The **orchestrator** (not Scout) writes the returned findings to `{phase-dir}/{phase}-RESEARCH.md`. Scout has `disallowedTools: Write` (platform-enforced) and cannot write files. Resolve Scout model:
     ```bash
     SCOUT_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh scout .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
   SCOUT_MAX_TURNS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh scout .vbw-planning/config.json "{effort}")
     ```
   Pass `model: "${SCOUT_MODEL}"` and `maxTurns: ${SCOUT_MAX_TURNS}` to the Task tool.
   - **If exists:** Include it in Lead's context for incremental refresh. Lead may update RESEARCH.md if new information emerges.
   - **On failure:** Log warning, continue planning without research. Do not block.
   - If `v3_plan_research_persist=false` or effort=turbo: skip entirely.
4. **Context compilation:** If `config_context_compiler=true`, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} lead {phases_dir}`. Include `.context-lead.md` in Lead agent context if produced.
5. **Turbo shortcut:** If effort=turbo, skip Lead. Read phase reqs from ROADMAP.md, create single lightweight PLAN.md inline.
6. **Other efforts:**
   - Resolve Lead model:
     ```bash
     LEAD_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh lead .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
       LEAD_MAX_TURNS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh lead .vbw-planning/config.json "{effort}")
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
     - Create team via TeamCreate: `team_name="vbw-plan-{NN}"`, `description="Planning Phase {N}: {phase-name}"`
     - Spawn Scout (if spawned in step 3) with `team_name: "vbw-plan-{NN}"`, `name: "scout"` parameters on the Task tool invocation.
     - Spawn Lead with `team_name: "vbw-plan-{NN}"`, `name: "lead"` parameters on the Task tool invocation.
     - **HARD GATE — Shutdown before proceeding (NON-NEGOTIABLE):** After all team agents complete their work, you MUST shut down the team BEFORE validating output, presenting results, auto-chaining to Execute, or asking the user anything. This gate CANNOT be skipped, deferred, or optimized away — even after compaction. Lingering agents burn API credits silently.
       1. Send `shutdown_request` to EVERY active teammate via SendMessage (Lead, Scout — excluding yourself, the orchestrator)
       2. Wait for each `shutdown_response` (approved=true). If rejected, re-request (max 3 attempts per teammate — then proceed).
       3. Call TeamDelete for team "vbw-plan-{NN}"
       4. Verify: after TeamDelete, there must be ZERO active teammates. If tmux panes still show agent labels, something went wrong — do NOT proceed.
       5. Only THEN proceed to step 7
       **WHY THIS EXISTS:** Without this gate, each Plan invocation spawns a new Lead that lingers in tmux. After 2-3 phases, multiple @lea panes accumulate, each burning API credits doing nothing. This is the #1 user-reported cost issue.

     When team should NOT be created (Lead-only with when_parallel/auto):
     - Spawn vbw-lead as subagent via Task tool without team (single agent, no team overhead).
   - Spawn vbw-lead as subagent via Task tool with compiled context (or full file list as fallback).
   - **CRITICAL:** Add `model: "${LEAD_MODEL}"` and `maxTurns: ${LEAD_MAX_TURNS}` parameters to the Task tool invocation.
   - **CRITICAL:** Include in the Lead prompt: "Plans will be executed by a team of parallel Dev agents — one agent per plan. Maximize wave 1 plans (no deps) so agents start simultaneously. Ensure same-wave plans modify disjoint file sets to avoid merge conflicts."
   - Display `◆ Spawning Lead agent...` -> `✓ Lead agent complete`.
7. **Validate output:** Verify PLAN.md has valid frontmatter (phase, plan, title, wave, depends_on, must_haves) and tasks. Check wave deps acyclic.
8. **Present:** Update STATE.md (phase position, plan count, status=Planned). Resolve model profile:
   ```bash
   MODEL_PROFILE=$(jq -r '.model_profile // "quality"' .vbw-planning/config.json)
   ```
   Display Phase Banner with plan list, effort level, and model profile:
   ```
   Phase {N}: {name}
   Plans: {N}
     {plan}: {title} (wave {W}, {N} tasks)
   Effort: {effort}
   Model Profile: {profile}
   ```
9. **Planning commit boundary (conditional):**
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/planning-git.sh commit-boundary "plan phase {N}" .vbw-planning/config.json
   ```
   Behavior: `planning_tracking=commit` commits planning artifacts if changed. `auto_push=always` pushes when upstream exists.
10. **Pre-chain verification:** Before auto-chaining or presenting results, confirm the planning team was fully shut down (step 6 HARD GATE completed). If you skipped the gate or are unsure after compaction, send `shutdown_request` to any teammates that may still be active and call TeamDelete before continuing. NEVER enter Execute mode with a prior planning team still alive.
11. **Cautious gate (autonomy=cautious only):** STOP after planning. Ask "Plans ready. Execute Phase {N}?" Other levels: auto-chain.

### Mode: Execute

Read `${CLAUDE_PLUGIN_ROOT}/references/execute-protocol.md` and follow its instructions.

This mode delegates entirely to the protocol file. Before reading:
1. **Parse arguments:** Phase number (auto-detect if omitted), --effort, --skip-qa, --plan=NN.
2. **Run execute guards:**
   - Not initialized: STOP "Run /vbw:init first."
   - No PLAN.md in phase dir: STOP "Phase {N} has no plans. Run `/vbw:vibe --plan {N}` first."
   - All plans have SUMMARY.md: cautious/standard -> WARN + confirm; confident/pure-vibe -> warn + auto-continue.
3. **Compile context:** If `config_context_compiler=true`, run:
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} dev {phases_dir} {plan_path}`
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} qa {phases_dir}`
   Include compiled context paths in Dev and QA task descriptions.

Then Read the protocol file and execute Steps 2-5 as written.

### Mode: Verify

**Guard:** Initialized, phase has `*-SUMMARY.md` files.
No SUMMARY.md: STOP "Phase {N} has no completed plans. Run /vbw:vibe first."
**Phase auto-detection:** First phase with `*-SUMMARY.md` but no `*-UAT.md`. All verified: STOP "All phases have UAT results. Specify: `/vbw:verify N`"

**Steps:**
1. Read `${CLAUDE_PLUGIN_ROOT}/commands/verify.md` protocol.
2. Execute the verify protocol for the target phase.
3. Display results per verify.md output format.

### Mode: Add Phase

**Guard:** Initialized. Requires phase name in $ARGUMENTS.
Missing name: STOP "Usage: `/vbw:vibe --add <phase-name>`"

**Steps:**
1. Resolve context: ACTIVE -> milestone-scoped paths, otherwise defaults.
2. **Codebase context:** If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md and CONCERNS.md (whichever exist) from `.vbw-planning/codebase/`. Use this to inform phase goal scoping and identify relevant modules/services.
3. Parse args: phase name (first non-flag arg), --goal (optional), slug (lowercase hyphenated).
4. Next number: highest in ROADMAP.md + 1, zero-padded.
5. Create dir: `mkdir -p {PHASES_DIR}/{NN}-{slug}/`
6. **Problem research (conditional):** If $ARGUMENTS contain a problem description (bug report, feature request, multi-sentence intent) rather than just a bare phase name:
   - Resolve Scout model: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh scout .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json`
   - Resolve Scout max turns: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh scout .vbw-planning/config.json "$(jq -r '.effort // "balanced"' .vbw-planning/config.json 2>/dev/null)"`
   - Spawn Scout agent to research the problem in the codebase. Scout returns structured findings with sections: `## Findings`, `## Relevant Patterns`, `## Risks`, `## Recommendations`. Scout has `disallowedTools: Write` and cannot write files — the **orchestrator** writes the returned findings to `{phase-dir}/{NN}-RESEARCH.md`.
   - Use Scout findings to write an informed phase goal and success criteria in ROADMAP.md.
   - On failure: log warning, write phase goal from $ARGUMENTS alone. Do not block.
   - **This eliminates duplicate research** — Plan mode step 3 checks for existing RESEARCH.md and skips Scout if found.
7. Update ROADMAP.md: append phase list entry, append Phase Details section (using Scout findings if available), add progress row.
8. Present: Phase Banner with milestone, position, goal. Checklist for roadmap update + dir creation. Next Up: `/vbw:vibe --discuss` or `/vbw:vibe --plan`.

### Mode: Insert Phase

**Guard:** Initialized. Requires position + name.
Missing args: STOP "Usage: `/vbw:vibe --insert <position> <phase-name>`"
Invalid position (out of range 1 to max+1): STOP with valid range.
Inserting before completed phase: WARN + confirm.

**Steps:**
1. Resolve context: ACTIVE -> milestone-scoped paths, otherwise defaults.
2. **Codebase context:** If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md and CONCERNS.md (whichever exist) from `.vbw-planning/codebase/`. Use this to inform phase goal scoping and identify relevant modules/services.
3. Parse args: position (int), phase name, --goal (optional), slug (lowercase hyphenated).
4. Identify renumbering: all phases >= position shift up by 1.
5. Renumber dirs in REVERSE order: rename dir {NN}-{slug} -> {NN+1}-{slug}, rename internal PLAN/SUMMARY files, update `phase:` frontmatter, update `depends_on` references.
6. Create dir: `mkdir -p {PHASES_DIR}/{NN}-{slug}/`
7. **Problem research (conditional):** Same as Add Phase step 6 — if $ARGUMENTS contain a problem description, spawn Scout to research the codebase. Scout returns findings; the **orchestrator** writes `{phase-dir}/{NN}-RESEARCH.md`. This prevents Plan mode from duplicating the research.
8. Update ROADMAP.md: insert new phase entry + details at position (using Scout findings if available), renumber subsequent entries/headers/cross-refs, update progress table.
9. Present: Phase Banner with renumber count, phase changes, file checklist, Next Up.

### Mode: Remove Phase

**Guard:** Initialized. Requires phase number.
Missing number: STOP "Usage: `/vbw:vibe --remove <phase-number>`"
Not found: STOP "Phase {N} not found."
Has work (PLAN.md or SUMMARY.md): STOP "Phase {N} has artifacts. Remove plans first."
Completed ([x] in roadmap): STOP "Cannot remove completed Phase {N}."

**Steps:**
1. Resolve context: ACTIVE -> milestone-scoped paths, otherwise defaults.
2. Parse args: extract phase number, validate, look up name/slug.
3. Confirm: display phase details, ask confirmation. Not confirmed -> STOP.
4. Remove dir: `rm -rf {PHASES_DIR}/{NN}-{slug}/`
5. Renumber FORWARD: for each phase > removed: rename dir {NN} -> {NN-1}, rename internal files, update frontmatter, update depends_on.
6. Update ROADMAP.md: remove phase entry + details, renumber subsequent, update deps, update progress table.
7. Present: Phase Banner with renumber count, phase changes, file checklist, Next Up.

### Mode: Archive

**Guard:** Initialized, roadmap exists.
No roadmap: STOP "No milestones configured. Run `/vbw:vibe` to bootstrap."
No work (no SUMMARY.md files): STOP "Nothing to ship."

**Pre-gate audit (unless --skip-audit or --force):**
Run 6-point audit matrix:
1. Roadmap completeness: every phase has real goal (not TBD/empty)
2. Phase planning: every phase has >= 1 PLAN.md
3. Plan execution: every PLAN.md has SUMMARY.md
4. Execution status: every SUMMARY.md has `status: complete`
5. Verification: VERIFICATION.md files exist + PASS. Missing=WARN, failed=FAIL
6. Requirements coverage: req IDs in roadmap exist in REQUIREMENTS.md
FAIL -> STOP with remediation suggestions. WARN -> proceed with warnings.

**Steps:**
1. Resolve context: ACTIVE -> milestone-scoped paths. No ACTIVE -> SLUG="default", root paths.
2. Parse args: --tag=vN.N.N (custom tag), --no-tag (skip), --force (skip audit).
3. Compute summary: from ROADMAP (phases), SUMMARY.md files (tasks/commits/deviations), REQUIREMENTS.md (satisfied count).
4. **Rolling summary (conditional):** If `v3_rolling_summary=true` in config:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-rolling-summary.sh \
     .vbw-planning/phases .vbw-planning/ROLLING-CONTEXT.md 2>/dev/null || true
   ```
   Compiles final rolling context before artifacts move to milestones/. Fail-open.
   When `v3_rolling_summary=false`: skip.
5. Archive: `mkdir -p .vbw-planning/milestones/`. Move roadmap, state, phases to milestones/{SLUG}/. Write SHIPPED.md. Delete stale RESUME.md.
5b. **Persist project-level state:** After archiving, run:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/persist-state-after-ship.sh \
     .vbw-planning/milestones/{SLUG}/STATE.md .vbw-planning/STATE.md "{PROJECT_NAME}"
   ```
   This extracts project-level sections (Todos, Decisions, Skills, Blockers, Codebase Profile) from the archived STATE.md and writes a fresh root STATE.md. Milestone-specific sections (Current Phase, Activity Log, Phase Status) stay in the archive only. Fail-open: if the script fails, warn but continue.
6. Planning commit boundary (conditional):
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/planning-git.sh commit-boundary "archive milestone {SLUG}" .vbw-planning/config.json
   ```
   Run this BEFORE branch merge/tag so shipped planning state is committed.
7. Git branch merge: if `milestone/{SLUG}` branch exists, merge --no-ff. Conflict -> abort, warn. No branch -> skip.
8. Git tag: unless --no-tag, `git tag -a {tag} -m "Shipped milestone: {name}"`. Default: `milestone/{SLUG}`.
9. Update ACTIVE: remaining milestones -> set ACTIVE to first. None -> remove ACTIVE.
10. Regenerate CLAUDE.md: update Active Context, remove shipped refs. Preserve non-VBW content — only replace VBW-managed sections, keep user's own sections intact.
11. Present: Phase Banner with metrics (phases, tasks, commits, requirements, deviations), archive path, tag, branch status, memory status. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh vibe`.

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

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh vibe {result}` for Next Up suggestions.

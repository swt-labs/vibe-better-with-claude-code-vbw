# VBW Execution Protocol

Loaded on demand by /vbw:vibe Execute mode. Not a user-facing command.

### Step 2: Load plans and detect resume state

1. Glob `*-PLAN.md` in phase dir. Read each plan's YAML frontmatter.
2. Check existing SUMMARY.md files (complete plans).
3. `git log --oneline -20` for committed tasks (crash recovery).
4. Build remaining plans list. If `--plan=NN`, filter to that plan.
4b. **Worktree isolation (REQ-WORKTREE):** If `worktree_isolation` is not `"off"` in config:
   ```bash
   WORKTREE_ISOLATION=$(jq -r '.worktree_isolation // "off"' .vbw-planning/config.json 2>/dev/null || echo "off")
   ```
   For each uncompleted plan in the remaining plans list:
   - Create worktree: `WPATH=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-create.sh {phase} {plan} 2>/dev/null || echo "")`. If `WPATH` is empty, log warning and continue without worktree for this plan.
   - If `WPATH` is non-empty:
     - Store `worktree_path` in the plan's entry in execution-state.json (added alongside `"status"` in the `plans` array).
     - Fetch targeting JSON: `WTARGET=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-target.sh "$WPATH" 2>/dev/null || echo "{}")`.
     - Register agent mapping: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-agent-map.sh set "dev-{plan}" "$WPATH" {phase} {plan} 2>/dev/null || true`.
   When `worktree_isolation="off"`: skip this step silently.
5. Partially-complete plans: note resume-from task number.
6. **Crash recovery:** If `.vbw-planning/.execution-state.json` exists with `"status": "running"`, update plan statuses to match current SUMMARY.md state.
   - **Event Recovery (REQ-17):** If `event_recovery=true` in config, attempt event-sourced recovery first:
     `RECOVERED=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/recover-state.sh {phase} 2>/dev/null || echo "{}")`
     If non-empty and has `plans` array, use recovered state as the baseline instead of the stale execution-state.json. This provides more accurate status when execution-state.json was not written (crash before flush).
6b. **Generate correlation_id:** Generate a UUID for this phase execution:
   - If `.vbw-planning/.execution-state.json` already exists and has `correlation_id` (crash-resume):
     preserve it: `CORRELATION_ID=$(jq -r '.correlation_id // ""' .vbw-planning/.execution-state.json 2>/dev/null || echo "")`
   - Otherwise generate fresh:
     `CORRELATION_ID=$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "$(date -u +%s)-${RANDOM}${RANDOM}")`

7. **Write execution state** to `.vbw-planning/.execution-state.json`:
```json
{
  "phase": N, "phase_name": "{slug}", "status": "running",
  "started_at": "{ISO 8601}", "wave": 1, "total_waves": N,
  "correlation_id": "{UUID}",
  "plans": [{"id": "NN-MM", "title": "...", "wave": W, "status": "pending|complete"}]
}
```
Set completed plans (with SUMMARY.md) to `"complete"`, others to `"pending"`.

7b. **Export correlation_id:** Set `VBW_CORRELATION_ID={CORRELATION_ID}` in the execution environment
    so log-event.sh can fall back to it if .execution-state.json is temporarily unavailable.
    Log a confirmation: `◆ Correlation ID: {CORRELATION_ID}`

8. **Event Log (REQ-16, graduated, always-on):**
   - Log phase start: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/log-event.sh phase_start {phase} 2>/dev/null || true`

9. **Snapshot Resume (REQ-18):** If `snapshot_resume=true` in config:
   - On crash recovery (execution-state.json exists with `"status": "running"`): attempt restore:
     `SNAPSHOT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/snapshot-resume.sh restore {phase} {preferred-role} 2>/dev/null || echo "")`
   - If snapshot found, log: `✓ Snapshot found: ${SNAPSHOT}` — use snapshot's `recent_commits` to cross-reference git log for more reliable resume-from detection.

10. **Schema Validation (REQ-17, graduated, always-on):**
   - Validate each PLAN.md frontmatter before execution:
     `VALID=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-schema.sh plan {plan_path} 2>/dev/null || echo "valid")`
   - If `invalid`: log warning `⚠ Plan {NN-MM} schema: ${VALID}` — continue execution (advisory only).
   - Log to metrics: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-metrics.sh schema_check {phase} {plan} result=$VALID 2>/dev/null || true`

11. **Cross-phase deps (PWR-04):** For each plan with `cross_phase_deps`:
   - Verify referenced plan's SUMMARY.md exists with `status: complete`
   - If artifact path specified, verify file exists
   - Unsatisfied → STOP: "Cross-phase dependency not met. Plan {id} depends on Phase {P}, Plan {plan} ({reason}). Status: {failed|missing|not built}. Fix: Run /vbw:vibe {P}"
   - All satisfied: `✓ Cross-phase dependencies verified`
   - No cross_phase_deps: skip silently

### Step 3: Create Agent Team and execute

**Team creation (multi-agent only):**
Read prefer_teams config to determine team creation:
```bash
PREFER_TEAMS=$(jq -r '.prefer_teams // "always"' .vbw-planning/config.json 2>/dev/null)
```

Decision tree:
- `prefer_teams='always'`: Create team for ALL plan counts (even 1 plan), unless turbo or smart-routed to turbo
- `prefer_teams='when_parallel'`: Create team only when 2+ uncompleted plans, unless turbo or smart-routed to turbo
- `prefer_teams='auto'`: Same as when_parallel (use current behavior, smart routing can downgrade)

When team should be created based on prefer_teams:
- Create team via TeamCreate: `team_name="vbw-phase-{NN}"`, `description="Phase {N}: {phase-name}"`
- All Dev and QA agents below MUST be spawned with `team_name: "vbw-phase-{NN}"` and `name: "dev-{MM}"` (from plan number) or `name: "qa"` parameters on the Task tool invocation.

When team should NOT be created (1 plan with when_parallel/auto, or turbo, or smart-routed turbo):
- Skip TeamCreate — single agent, no team overhead.

**Smart Routing (REQ-15):** If `smart_routing=true` in config:
- Before creating agent teams, assess each plan:
  ```bash
  RISK=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/assess-plan-risk.sh {plan_path} 2>/dev/null || echo "medium")
  TASK_COUNT=$(grep -c '^### Task [0-9]' {plan_path} 2>/dev/null || echo "0")
  ```
- If `RISK=low` AND `TASK_COUNT<=3` AND effort is not `thorough`: force turbo execution for this plan (no team, direct implementation). Log routing decision:
  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-metrics.sh smart_route {phase} {plan} risk=$RISK tasks=$TASK_COUNT routed=turbo 2>/dev/null || true`
- Otherwise: proceed with normal team delegation. Log:
  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-metrics.sh smart_route {phase} {plan} risk=$RISK tasks=$TASK_COUNT routed=team 2>/dev/null || true`
- On script error: fall back to configured effort level.

**Delegation directive (all except Turbo):**
You are the team LEAD. NEVER implement tasks yourself.
- Delegate ALL implementation to Dev teammates via TaskCreate
- NEVER Write/Edit files in a plan's `files_modified` — only state files: STATE.md, ROADMAP.md, .execution-state.json, SUMMARY.md
- If Dev fails: guidance via SendMessage, not takeover. If all Devs unavailable: create new Dev.
- At Turbo (or smart-routed to turbo): no team — Dev executes directly.

**Monorepo Routing (REQ-17):** If `monorepo_routing=true` in config:
- Before context compilation, detect relevant package paths:
  `PACKAGES=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/route-monorepo.sh {phase_dir} 2>/dev/null || echo "[]")`
- If non-empty array (not `[]`): pass package paths to context compilation for scoped file inclusion.
  Log: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-metrics.sh monorepo_route {phase} packages=$PACKAGES 2>/dev/null || true`
- If empty or error: proceed with default (full repo) context compilation.

**Control Plane Coordination (REQ-05):** If `${CLAUDE_PLUGIN_ROOT}/scripts/control-plane.sh` exists:
- **Once per plan (before first task):** Run the `full` action to generate contract and compile context:
  ```bash
  CP_RESULT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/control-plane.sh full {phase} {plan} 1 \
    --plan-path={plan_path} --role=dev --phase-dir={phase-dir} 2>/dev/null || echo '{"action":"full","steps":[]}')
  ```
  Extract `contract_path` and `context_path` from result for subsequent per-task calls.
- **Before each task:** Run the `pre-task` action:
  ```bash
  CP_RESULT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/control-plane.sh pre-task {phase} {plan} {task} \
    --plan-path={plan_path} --task-id={phase}-{plan}-T{task} \
    --claimed-files={files_from_task} 2>/dev/null || echo '{"action":"pre-task","steps":[]}')
  ```
  If the result contains a gate failure (step with `status=fail`), treat as gate failure and follow existing auto-repair + escalation flow.
- **After each task:** Run the `post-task` action:
  ```bash
  CP_RESULT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/control-plane.sh post-task {phase} {plan} {task} \
    --task-id={phase}-{plan}-T{task} 2>/dev/null || echo '{"action":"post-task","steps":[]}')
  ```
- If `control-plane.sh` does NOT exist: fall through to the individual script calls below (backward compatibility).
- On any `control-plane.sh` error: fall through to individual script calls (fail-open).

The existing individual script call sections (V3 Contract-Lite, V2 Hard Gates, Context compilation, Token Budgets) remain unchanged below as the fallback path.

**Context compilation (REQ-11):** If control-plane.sh `full` action was used above and returned a `context_path`, use that path directly. Otherwise, if `config_context_compiler=true` from Context block above, before creating Dev tasks run:
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} dev {phases_dir} {plan_path}`
This produces `{phase-dir}/.context-dev.md` with phase goal and conventions.
The plan_path argument enables skill bundling: compile-context.sh reads skills_used from the plan's frontmatter and bundles referenced SKILL.md content into .context-dev.md. If the plan has no skills_used, this is a no-op.
If compilation fails, proceed without it — Dev reads files directly.

**V2 Token Budgets (REQ-12):** If control-plane.sh `compile` or `full` action was used and included token budget enforcement, skip this step. Otherwise:
- After context compilation, enforce per-role token budgets. Pass the contract path and task number for per-task budget computation:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/token-budget.sh dev {phase-dir}/.context-dev.md {contract_path} {task_number} > {phase-dir}/.context-dev.md.tmp && mv {phase-dir}/.context-dev.md.tmp {phase-dir}/.context-dev.md
  ```
  Where `{contract_path}` is `.vbw-planning/.contracts/{phase}-{plan}.json` (generated by generate-contract.sh in Step 3) and `{task_number}` is the current task being executed (1-based). When no contract is available, omit the contract_path and task_number arguments (per-role fallback).
- Same for QA context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/token-budget.sh qa {phase-dir}/.context-qa.md {contract_path} {task_number} > ...`
- Role caps defined in `config/token-budgets.json`: Scout (200 lines), Lead/Architect (500), QA (600), Dev/Debugger (800).
- Per-task budgets use contract metadata (must_haves, allowed_paths, depends_on) to compute a complexity score, which maps to a tier multiplier applied to the role's base budget.
- Overage logged to metrics as `token_overage` event with role, lines truncated, and budget_source (task or role).
- **Escalation:** When overage occurs, token-budget.sh emits a `token_cap_escalated` event and reduces the remaining budget for subsequent tasks in the plan. The budget reduction state is stored in `.vbw-planning/.token-state/{phase}-{plan}.json`. Escalation is advisory only -- execution continues regardless.
- **Cleanup:** At phase end, clean up token state: `rm -f .vbw-planning/.token-state/*.json 2>/dev/null || true`
- Truncation uses tail strategy (keep most recent context).


**Model resolution:** Resolve models for Dev and QA agents:
```bash
DEV_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh dev .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
if [ $? -ne 0 ]; then echo "$DEV_MODEL" >&2; exit 1; fi
DEV_MAX_TURNS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh dev .vbw-planning/config.json "{effort}")
if [ $? -ne 0 ]; then echo "$DEV_MAX_TURNS" >&2; exit 1; fi

QA_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh qa .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
if [ $? -ne 0 ]; then echo "$QA_MODEL" >&2; exit 1; fi
QA_MAX_TURNS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh qa .vbw-planning/config.json "{effort}")
if [ $? -ne 0 ]; then echo "$QA_MAX_TURNS" >&2; exit 1; fi
```

For each uncompleted plan, TaskCreate:
```
subject: "Execute {NN-MM}: {plan-title}"
description: |
  Execute all tasks in {PLAN_PATH}.
  Effort: {DEV_EFFORT}. Working directory: {worktree_path (from execution-state.json for this plan) if worktree_isolation is enabled and worktree_path is set, else {pwd}}.
  {If worktree_isolation enabled and WTARGET non-empty: "Worktree targeting: {WTARGET}"}
  Model: ${DEV_MODEL}
  Phase context: {phase-dir}/.context-dev.md (if compiled)
  If `.vbw-planning/codebase/META.md` exists, read CONVENTIONS.md, PATTERNS.md, STRUCTURE.md, and DEPENDENCIES.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before executing.
  {If resuming: "Resume from Task {N}. Tasks 1-{N-1} already committed."}
  {If autonomous: false: "This plan has checkpoints -- pause for user input."}
activeForm: "Executing {NN-MM}"
```

Display: `◆ Spawning Dev teammate (${DEV_MODEL})...`

**CRITICAL:** Pass `model: "${DEV_MODEL}"` and `maxTurns: ${DEV_MAX_TURNS}` parameters to the Task tool invocation when spawning Dev teammates.
**CRITICAL:** When team was created (2+ plans), pass `team_name: "vbw-phase-{NN}"` and `name: "dev-{MM}"` parameters to each Task tool invocation. This enables colored agent labels and status bar entries.

Wire dependencies via TaskUpdate: read `depends_on` from each plan's frontmatter, add `addBlockedBy: [task IDs of dependency plans]`. Plans with empty depends_on start immediately.

Spawn Dev teammates and assign tasks. Platform enforces execution ordering via task deps. If `--plan=NN`: single task, no dependencies.

**Blocked agent notification (mandatory):** When a Dev teammate completes a plan (task marked completed + SUMMARY.md verified), check if any other tasks have `blockedBy` containing that completed task's ID. For each newly-unblocked task, send its assigned Dev a message: "Blocking task {id} complete. Your task is now unblocked — proceed with execution." This ensures blocked agents resume without manual intervention.

**Validation Gates (REQ-13, REQ-14):** If `validation_gates=true` in config:
- **Per plan:** Assess risk and resolve gate policy:
  ```bash
  RISK=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/assess-plan-risk.sh {plan_path} 2>/dev/null || echo "medium")
  GATE_POLICY=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-gate-policy.sh {effort} $RISK {autonomy} 2>/dev/null || echo '{}')
  ```
- Extract policy fields: `qa_tier`, `approval_required`, `communication_level`, `two_phase`
- Use these to override the static tables below for this plan
- Log to metrics: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-metrics.sh gate_policy {phase} {plan} risk=$RISK qa_tier=$QA_TIER approval=$APPROVAL 2>/dev/null || true`
- On script error: fall back to static tables below

**Plan approval gate (effort-gated, autonomy-gated):**
When `validation_gates=true`: use `approval_required` from gate policy above.
When `validation_gates=false` (default): use static table:

| Autonomy | Approval active at |
|----------|-------------------|
| cautious | Thorough + Balanced |
| standard | Thorough only |
| confident/pure-vibe | OFF |

When active: spawn Devs with `plan_mode_required`. Dev reads PLAN.md, proposes approach, waits for lead approval. Lead approves/rejects via plan_approval_response.
When off: Devs begin immediately.

**Teammate communication (effort-gated):**
When `validation_gates=true`: use `communication_level` from gate policy (none/blockers/blockers_findings/full).
When `validation_gates=false` (default): use static table:

Schema ref: `${CLAUDE_PLUGIN_ROOT}/references/handoff-schemas.md`

| Effort | Messages sent |
|--------|--------------|
| Thorough | blockers (blocker_report), findings (scout_findings), progress (execution_update), contracts (plan_contract) |
| Balanced | blockers (blocker_report), progress (execution_update) |
| Fast | blockers only (blocker_report) |
| Turbo | N/A (no team) |

Use targeted `message` not `broadcast`. Reserve broadcast for critical blocking issues only.

**Typed Protocol (REQ-04, REQ-05, graduated, always-on):**
- **On message receive** (from any teammate): validate before processing:
  `VALID=$(echo "$MESSAGE_JSON" | bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-message.sh 2>/dev/null || echo '{"valid":true}')`
  If `valid=false`: log rejection, send error back to sender with `errors` array. Do not process the message.
- **On message send** (before sending): agents should construct messages using full V2 envelope (id, type, phase, task, author_role, timestamp, schema_version, payload, confidence). Reference `${CLAUDE_PLUGIN_ROOT}/references/handoff-schemas.md` for schema details.

**Execution state updates:**
- Task completion: update plan status in .execution-state.json (`"complete"` or `"failed"`)
- Wave transition: update `"wave"` when first wave N+1 task starts
- Use `jq` for atomic updates

Hooks handle continuous verification: PostToolUse validates SUMMARY.md, TaskCompleted verifies commits, TeammateIdle runs quality gate.

**Event Log — plan lifecycle (REQ-16, graduated, always-on):**
- At plan start: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/log-event.sh plan_start {phase} {plan} 2>/dev/null || true`
- At agent spawn: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/log-event.sh agent_spawn {phase} {plan} role=dev model=$DEV_MODEL 2>/dev/null || true`
- At agent shutdown: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/log-event.sh agent_shutdown {phase} {plan} role=dev 2>/dev/null || true`
- At plan complete: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/log-event.sh plan_end {phase} {plan} status=complete 2>/dev/null || true`
- At plan failure: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/log-event.sh plan_end {phase} {plan} status=failed 2>/dev/null || true`
- On error: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/log-event.sh error {phase} {plan} message={error_summary} 2>/dev/null || true`

**Full Event Types (REQ-09, REQ-10, graduated, always-on):** Emit all 13 event types at correct lifecycle points.

> **Naming convention:** Event types (`shutdown_sent`/`shutdown_received`) log _what happened_ — the orchestrator sent or received a message. Message types (`shutdown_request`/`shutdown_response`) define _what was communicated_ — the typed payload in SendMessage. Events are emitted by `log-event.sh`; messages are validated by `validate-message.sh`.
- `phase_planned`: at plan completion (after Lead writes PLAN.md): `log-event.sh phase_planned {phase}`
- `task_created`: when task is defined in plan: `log-event.sh task_created {phase} {plan} task_id={id}`
- `task_claimed`: when Dev starts a task: `log-event.sh task_claimed {phase} {plan} task_id={id} role=dev`
- `task_started`: when task execution begins: `log-event.sh task_started {phase} {plan} task_id={id}`
- `artifact_written`: after writing/modifying a file: `log-event.sh artifact_written {phase} {plan} path={file} task_id={id}`
  - Also register in artifact registry: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/artifact-registry.sh register {file} {event_id} {phase} {plan}`
- `gate_passed` / `gate_failed`: already emitted by hard-gate.sh
- `task_completed_candidate`: emitted by two-phase-complete.sh
- `task_completed_confirmed`: emitted by two-phase-complete.sh after validation
- `task_blocked`: already emitted by auto-repair.sh
- `task_reassigned`: when task is re-assigned to different agent: `log-event.sh task_reassigned {phase} {plan} task_id={id} from={old} to={new}`
- `shutdown_sent`: when orchestrator sends shutdown_request to teammates: `log-event.sh shutdown_sent {phase} team={team_name} targets={count}`
- `shutdown_received`: when orchestrator has collected all shutdown_response messages: `log-event.sh shutdown_received {phase} team={team_name} approved={count} rejected={count}`

**Snapshot — per-plan checkpoint (REQ-18):** If `snapshot_resume=true` in config:
- After each plan completes (SUMMARY.md verified):
  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/snapshot-resume.sh save {phase} .vbw-planning/.execution-state.json {agent-role} {trigger} 2>/dev/null || true`
- This captures execution state + recent git context for crash recovery. The optional `{agent-role}` and `{trigger}` arguments add metadata to the snapshot for role-filtered restore.

**Metrics instrumentation (REQ-09):** If `metrics=true` in config:
- At phase start: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-metrics.sh execute_phase_start {phase} plan_count={N} effort={effort}`
- At each plan completion: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-metrics.sh execute_plan_complete {phase} {plan} task_count={N} commit_count={N}`
- At phase end: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-metrics.sh execute_phase_complete {phase} plans_completed={N} total_tasks={N} total_commits={N} deviations={N}`
All metrics calls should be `2>/dev/null || true` — never block execution.

**V3 Contract-Lite (REQ-10, graduated):**
- **Once per plan (before first task):** Generate contract sidecar:
  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/generate-contract.sh {plan_path} 2>/dev/null || true`
  This produces `.vbw-planning/.contracts/{phase}-{plan}.json` with allowed_paths and must_haves.
- **Before each task:** Validate task start:
  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-contract.sh start {contract_path} {task_number} 2>/dev/null || true`
- **After each task:** Validate modified files against contract:
  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-contract.sh end {contract_path} {task_number} {modified_files...} 2>/dev/null || true`
  Where `{modified_files}` comes from `git diff --name-only HEAD~1` after the task's commit.
- Violations are advisory only (logged to metrics, not blocking).

**V2 Hard Gates (REQ-02, REQ-03, graduated):**
- **Pre-task gate sequence (before each task starts):**
  1. `contract_compliance` gate: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/hard-gate.sh contract_compliance {phase} {plan} {task} {contract_path}`
  2. **Lease acquisition** (V2 control plane): acquire exclusive file lease before protected_file check:
     `bash ${CLAUDE_PLUGIN_ROOT}/scripts/lease-lock.sh acquire {task_id} --ttl=300 {claimed_files...}`
     - Lease conflict → auto-repair attempt (wait + re-acquire), then escalate blocker if unresolved.
  3. `protected_file` gate: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/hard-gate.sh protected_file {phase} {plan} {task} {contract_path}`
  - If any gate fails (exit 2): attempt auto-repair:
    `REPAIR=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/auto-repair.sh {gate_type} {phase} {plan} {task} {contract_path})`
  - If `repaired=true`: re-run the failed gate to confirm, then proceed.
  - If `repaired=false`: emit blocker, halt task execution. Send Lead a message with the failure evidence and next action from the blocker event.
- **Post-task gate sequence (after each task commit):**
  1. `required_checks` gate: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/hard-gate.sh required_checks {phase} {plan} {task} {contract_path}`
  2. `commit_hygiene` gate: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/hard-gate.sh commit_hygiene {phase} {plan} {task} {contract_path}`
  3. **Lease release**: release file lease after task completes:
     `bash ${CLAUDE_PLUGIN_ROOT}/scripts/lease-lock.sh release {task_id}`
  - Gate failures trigger auto-repair with same flow as pre-task.
- **Post-plan gate (after all tasks complete, before marking plan done):**
  1. `artifact_persistence` gate: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/hard-gate.sh artifact_persistence {phase} {plan} {task} {contract_path}`
  2. `verification_threshold` gate: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/hard-gate.sh verification_threshold {phase} {plan} {task} {contract_path}`
  - These gates fire AFTER SUMMARY.md verification but BEFORE updating execution-state.json to "complete".
- **YOLO mode:** Hard gates ALWAYS fire regardless of autonomy level. YOLO only skips confirmation prompts.
- **Fallback:** If hard-gate.sh or auto-repair.sh errors (not a gate fail, but a script error), log to metrics and continue (fail-open on script errors, hard-stop only on gate verdicts).

**Lease Locks (REQ-17):** If `lease_locks=true` in config:
- Use `lease-lock.sh` for all lock operations:
  - Acquire: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/lease-lock.sh acquire {task_id} --ttl=300 {claimed_files...} 2>/dev/null || true`
  - Release: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/lease-lock.sh release {task_id} 2>/dev/null || true`
- **During long-running tasks** (>2 minutes estimated): renew lease periodically:
  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/lease-lock.sh renew {task_id} 2>/dev/null || true`
- Check for expired leases before acquiring: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/lease-lock.sh check {task_id} {claimed_files...} 2>/dev/null || true`

### Step 3b: Two-Phase Completion (REQ-09)

**If `two_phase_completion=true` in config:**

After each task commit (and after post-task gates pass), run two-phase completion:
```bash
RESULT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/two-phase-complete.sh {task_id} {phase} {plan} {contract_path} {evidence...})
```
- If `result=confirmed`: proceed to next task.
- If `result=rejected`: treat as gate failure — attempt auto-repair (re-run checks), then escalate blocker if still failing.
- Artifact registration: after each file write during task execution, register the artifact:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/artifact-registry.sh register {file_path} {event_id} {phase} {plan}
  ```
- When `two_phase_completion=false`: skip (direct task completion as before).

### Step 3c: SUMMARY.md verification gate (mandatory)

**This is a hard gate. Do NOT proceed to QA or mark a plan as complete in .execution-state.json without verifying its SUMMARY.md.**

When a Dev teammate reports plan completion (task marked completed):
1. **Check:** Verify `{phase_dir}/{plan_id}-SUMMARY.md` exists and contains commit hashes, task statuses, and files modified.
2. **If missing or incomplete:** Send the Dev a message: "Write {plan_id}-SUMMARY.md using the template at templates/SUMMARY.md. Include commit hashes, tasks completed, files modified, and any deviations." Wait for confirmation before proceeding.
3. **If Dev is unavailable:** Write it yourself from `git log --oneline` and the PLAN.md.
4. **Schema Validation — SUMMARY.md (REQ-17, graduated, always-on):**
   - Validate SUMMARY.md frontmatter: `VALID=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-schema.sh summary {summary_path} 2>/dev/null || echo "valid")`
   - If `invalid`: log warning `⚠ Summary {plan_id} schema: ${VALID}` — advisory only.
5. **Only after SUMMARY.md is verified:** Update plan status to `"complete"` in .execution-state.json and proceed.

### Step 4: Post-build QA (optional)

If `--skip-qa` or turbo: "○ QA verification skipped ({reason})"

**Auto-skip for certain agents:** Check if the current agent type is in `qa_skip_agents` config array (default: `["docs"]`):
```bash
AGENT_TYPE=$(jq -r '.current_agent_type // "dev"' .vbw-planning/config.json 2>/dev/null)
QA_SKIP_AGENTS=$(jq -r '.qa_skip_agents // []' .vbw-planning/config.json 2>/dev/null)
if echo "$QA_SKIP_AGENTS" | jq -e --arg agent "$AGENT_TYPE" 'contains([$agent])' >/dev/null 2>&1; then
  echo "○ QA verification skipped (agent: $AGENT_TYPE)"
  # Skip to Step 4.5 (UAT)
fi
```
When the agent type is in the skip list, QA is skipped automatically without needing `--skip-qa` flag. Docs-only changes don't need formal QA.

**Tier resolution:** When `validation_gates=true`: use `qa_tier` from gate policy resolved in Step 3.
When `validation_gates=false` (default): map effort to tier: turbo=skip (already handled), fast=quick, balanced=standard, thorough=deep. Override: if >15 requirements or last phase before ship, force Deep.

**Control Plane QA context:** If `${CLAUDE_PLUGIN_ROOT}/scripts/control-plane.sh` exists:
  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/control-plane.sh compile {phase} 0 0 --role=qa --phase-dir={phase-dir} 2>/dev/null || true`
Otherwise, fall through to direct compile-context.sh call below.

**Context compilation:** If `config_context_compiler=true`, before spawning QA run:
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} qa {phases_dir}`
This produces `{phase-dir}/.context-qa.md` with phase goal, success criteria, requirements to verify, and conventions.
If compilation fails, proceed without it.

Display: `◆ Spawning QA agent (${QA_MODEL})...`

**Per-wave QA (Thorough/Balanced, QA_TIMING=per-wave):** After each wave completes, spawn QA concurrently with next wave's Dev work. QA receives only completed wave's PLAN.md + SUMMARY.md + "Phase context: {phase-dir}/.context-qa.md (if compiled). Model: ${QA_MODEL}. Your verification tier is {tier}. If `.vbw-planning/codebase/META.md` exists, read TESTING.md, CONCERNS.md, and ARCHITECTURE.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before verifying. Run {5-10|15-25|30+} checks per the tier definitions in your agent protocol." After final wave, spawn integration QA covering all plans + cross-plan integration. Persist to `{phase-dir}/{phase}-VERIFICATION-wave{W}.md` and `{phase}-VERIFICATION.md`.

**Post-build QA (Fast, QA_TIMING=post-build):** Spawn QA after ALL plans complete. Include in task description: "Phase context: {phase-dir}/.context-qa.md (if compiled). Model: ${QA_MODEL}. Your verification tier is {tier}. If `.vbw-planning/codebase/META.md` exists, read TESTING.md, CONCERNS.md, and ARCHITECTURE.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before verifying. Run {5-10|15-25|30+} checks per the tier definitions in your agent protocol." Persist to `{phase-dir}/{phase}-VERIFICATION.md`.

**CRITICAL:** Pass `model: "${QA_MODEL}"` and `maxTurns: ${QA_MAX_TURNS}` parameters to the Task tool invocation when spawning QA agents.
**CRITICAL:** When team was created (2+ plans), pass `team_name: "vbw-phase-{NN}"` and `name: "qa"` (or `name: "qa-wave{W}"` for per-wave QA) parameters to each QA Task tool invocation.

### Step 4.5: Human acceptance testing (UAT)

**Autonomy gate:**

| Autonomy | UAT active |
|----------|-----------|
| cautious | YES |
| standard | YES |
| confident | OFF |
| pure-vibe | OFF |

Read autonomy from config: `jq -r '.autonomy // "standard"' .vbw-planning/config.json`

If autonomy is confident or pure-vibe: display "○ UAT verification skipped (autonomy: {level})" and proceed to Step 5.

**UAT execution (cautious + standard):**

1. Check if `{phase-dir}/{phase}-UAT.md` already exists with `status: complete`. If so: "○ UAT already complete" and proceed to Step 5.
2. Generate test scenarios from completed SUMMARY.md files (same logic as `commands/verify.md`).
3. Run CHECKPOINT loop inline (same protocol as `commands/verify.md` Steps 4-8).
4. After all tests complete:
   - If no issues: proceed to Step 5
   - If issues found: display issue summary, suggest `/vbw:fix`, STOP (do not proceed to Step 5)

Note: "Run inline" means the execute-protocol agent runs the verify protocol directly, not by invoking /vbw:verify as a command. The protocol is the same; the entry point differs.

### Step 5: Update state and present summary

**HARD GATE — Shutdown before ANY output or state updates:** If team was created (based on prefer_teams decision), you MUST shut down the team BEFORE updating state, presenting results, or asking the user anything. This is blocking and non-negotiable:
1. Send `shutdown_request` via SendMessage to EVERY active teammate (excluding yourself — the orchestrator controls the sequence, not the lead agent) — do not skip any
2. Log event: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/log-event.sh shutdown_sent {phase} team={team_name} targets={count} 2>/dev/null || true`
3. Wait for each `shutdown_response` with `approved: true`. If a teammate rejects, re-request immediately (max 3 attempts per teammate — if still rejected after 3 attempts, log a warning and proceed with TeamDelete).
4. Log event: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/log-event.sh shutdown_received {phase} team={team_name} approved={count} rejected={count} 2>/dev/null || true`
5. Call TeamDelete for team "vbw-phase-{NN}"
6. Only THEN proceed to state updates and user-facing output below
Failure to shut down leaves agents running in the background, consuming API credits (visible as hanging panes in tmux, invisible but still costly without tmux). If no team was created: skip shutdown sequence.

**Worktree merge and cleanup (post-TeamDelete):** If `worktree_isolation` is not `"off"` in config:
For each plan that has a `worktree_path` entry in execution-state.json (completed or failed):
1. **Copy SUMMARY.md** from worktree to phase dir (ensure it is present in the main working tree before merge changes branch context):
   `cp "{worktree_path}/.vbw-planning/phases/{phase-dir}/{plan_id}-SUMMARY.md" ".vbw-planning/phases/{phase-dir}/{plan_id}-SUMMARY.md" 2>/dev/null || true`
2. **Merge worktree branch:**
   `MERGE_RESULT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-merge.sh {phase} {plan} 2>/dev/null || echo "conflict")`
3. **If `MERGE_RESULT=clean`:**
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-cleanup.sh {phase} {plan} 2>/dev/null || true`
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-agent-map.sh clear "dev-{plan}" 2>/dev/null || true`
4. **If `MERGE_RESULT=conflict`:**
   - Log deviation in `{plan_id}-SUMMARY.md`: append "DEVIATION: worktree merge conflict — manual resolution required before cleanup."
   - Display: `⚠ Worktree merge conflict for plan {plan_id}. Resolve conflicts in {worktree_path}, then run: git worktree remove {worktree_path} --force`
   - Skip worktree-cleanup.sh — leave worktree in place for manual resolution.
All worktree operations are fail-open: script errors are suppressed (2>/dev/null || true). Merge failures are surfaced as warnings, not blockers.
When `worktree_isolation="off"`: skip this block silently.

**Post-shutdown verification:** After TeamDelete, there must be ZERO active teammates. If the Pure-Vibe loop or auto-chain will re-enter Plan mode next, confirm no prior agents linger before spawning new ones. This gate survives compaction — if you lost context about whether shutdown happened, assume it did NOT and send `shutdown_request` to any teammates that may still exist before proceeding.

**Control Plane cleanup:** Lock and token state cleanup already handled by existing Lease Lock and Token Budget cleanup blocks.

**Rolling Summary (REQ-03):** If `rolling_summary=true` in config:
- After TeamDelete (team fully shut down), before phase_end event log:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-rolling-summary.sh \
    .vbw-planning/phases .vbw-planning/ROLLING-CONTEXT.md 2>/dev/null || true
  ```
  This compiles all completed SUMMARY.md files into a condensed digest for the next phase's agents.
  Fail-open: if script errors, log warning and continue — never block phase completion.
- When `rolling_summary=false` (default): skip this step silently.

**Event Log — phase end (REQ-16, graduated, always-on):**
- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/log-event.sh phase_end {phase} plans_completed={N} total_tasks={N} 2>/dev/null || true`

**Observability Report (REQ-14):** After phase completion, if `metrics=true`:
- Generate observability report: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/metrics-report.sh {phase}`
- The report aggregates 7 V2 metrics: task latency, tokens/task, gate failure rate, lease conflicts, resume success, regression escape, fallback %.
- Display summary table in phase completion output.
- Dashboards show by profile (thorough|balanced|fast|turbo) and autonomy (cautious|standard|confident|pure-vibe).

**Mark complete:** Set .execution-state.json `"status"` to `"complete"` (statusline auto-deletes on next refresh).
**Update STATE.md:** phase position, plan completion counts, effort used.
**Update ROADMAP.md:** mark completed plans.

**Planning artifact boundary commit (conditional):**
```bash
PG_SCRIPT="$(ls -1 "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/*/scripts/planning-git.sh 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)"
[ ! -f "$PG_SCRIPT" ] && PG_SCRIPT="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/planning-git.sh}"
if [ -f "$PG_SCRIPT" ]; then
  bash "$PG_SCRIPT" commit-boundary "complete phase {N}" .vbw-planning/config.json
else
  echo "VBW: planning-git.sh unavailable; skipping planning git boundary commit" >&2
fi
```
- `planning_tracking=commit`: commits `.vbw-planning/` + `CLAUDE.md` when changed
- `planning_tracking=manual|ignore`: no-op
- `auto_push=always`: push happens inside the boundary commit command when upstream exists

**After-phase push (conditional):**
```bash
PG_SCRIPT="$(ls -1 "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/*/scripts/planning-git.sh 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)"
[ ! -f "$PG_SCRIPT" ] && PG_SCRIPT="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/planning-git.sh}"
if [ -f "$PG_SCRIPT" ]; then
  bash "$PG_SCRIPT" push-after-phase .vbw-planning/config.json
else
  echo "VBW: planning-git.sh unavailable; skipping planning git push-after-phase" >&2
fi
```
- `auto_push=after_phase`: pushes once after phase completion (if upstream exists)
- other modes: no-op

Display per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
```text
╔═══════════════════════════════════════════════╗
║  Phase {N}: {name} -- Built                   ║
╚═══════════════════════════════════════════════╝

  Plan Results:
    ✓ Plan 01: {title}  /  ✗ Plan 03: {title} (failed)

  Metrics:
    Plans: {completed}/{total}  Effort: {profile}  Model Profile: {profile}  Deviations: {count}

  QA: {PASS|PARTIAL|FAIL|skipped}
```

**"What happened" (NRW-02):** If config `plain_summary` is true (default), append 2-4 plain-English sentences between QA and Next Up. No jargon. Source from SUMMARY.md files + QA result. If false, skip.

**Discovered Issues:** If any Dev or QA agent reported pre-existing failures, out-of-scope bugs, or issues unrelated to this phase's work, collect and de-duplicate them by test name and file (when the same test+file pair appears with different error messages, keep the first error message encountered), then list them in the summary output between "What happened" and Next Up. To keep context size manageable, cap the displayed list at 20 entries; if more exist, show the first 20 and append `... and {N} more`. Format each bullet as `⚠ testName (path/to/file): error message`:
```text
  Discovered Issues:
    ⚠ {issue-1}
    ⚠ {issue-2}
  Suggest: /vbw:todo <description> to track
```
This is **display-only**. Do NOT edit STATE.md, do NOT add todos, do NOT invoke /vbw:todo, and do NOT enter an interactive loop. The user decides whether to track these. If no discovered issues: omit the section entirely. After displaying discovered issues, STOP. Do not take further action.

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh execute {qa-result}` and display output.

**STOP.** Execute mode is complete. Return control to the user. Do NOT take further actions — no file edits, no additional commits, no interactive prompts, no improvised follow-up work. The user will decide what to do next based on the summary and suggest-next output.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — Phase Banner (double-line box), ◆ running, ✓ complete, ✗ failed, ○ skipped, Metrics Block, Next Up Block, no ANSI color codes.

# VBW Execution Protocol

Loaded on demand by /vbw:vibe Execute mode. Not a user-facing command.

## Runtime Plugin Root Resolution (required once per Execute run)

Resolve and validate `VBW_PLUGIN_ROOT` once before running script commands below:

```bash
VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"
VBW_PLUGIN_ROOT=""

if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then
  VBW_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
fi
if [ -z "$VBW_PLUGIN_ROOT" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then
  VBW_PLUGIN_ROOT="${VBW_CACHE_ROOT}/local"
fi
if [ -z "$VBW_PLUGIN_ROOT" ]; then
  VERSION_DIR=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
  if [ -n "$VERSION_DIR" ] && [ -f "${VBW_CACHE_ROOT}/${VERSION_DIR}/scripts/hook-wrapper.sh" ]; then
    VBW_PLUGIN_ROOT="${VBW_CACHE_ROOT}/${VERSION_DIR}"
  else
    FALLBACK_DIR=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1)
    [ -n "$FALLBACK_DIR" ] && [ -f "${VBW_CACHE_ROOT}/${FALLBACK_DIR}/scripts/hook-wrapper.sh" ] && VBW_PLUGIN_ROOT="${VBW_CACHE_ROOT}/${FALLBACK_DIR}"
  fi
fi
SESSION_LINK="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"
if [ -z "$VBW_PLUGIN_ROOT" ] && [ -f "${SESSION_LINK}/scripts/hook-wrapper.sh" ]; then
  VBW_PLUGIN_ROOT="${SESSION_LINK}"
fi
if [ -z "$VBW_PLUGIN_ROOT" ]; then
  ANY_LINK=$(command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r link; do
    if [ -f "$link/scripts/hook-wrapper.sh" ]; then
      printf '%s\n' "$link"
      break
    fi
  done || true)
  if [ -n "$ANY_LINK" ]; then
    VBW_PLUGIN_ROOT="$ANY_LINK"
  fi
fi
if [ -z "$VBW_PLUGIN_ROOT" ]; then
  PLUGIN_DIR_PATH=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1)
  PLUGIN_DIR_PATH="${PLUGIN_DIR_PATH#--plugin-dir }"
  [ -n "$PLUGIN_DIR_PATH" ] && [ -f "$PLUGIN_DIR_PATH/scripts/hook-wrapper.sh" ] && VBW_PLUGIN_ROOT="$PLUGIN_DIR_PATH"
fi

if [ -z "$VBW_PLUGIN_ROOT" ] || [ ! -d "$VBW_PLUGIN_ROOT" ]; then
  echo "VBW: plugin root resolution failed (checked CLAUDE_PLUGIN_ROOT, cache local/, versioned dirs, symlink fallback, process tree)." >&2
  exit 1
fi

# Canonicalize to real path — survives cache symlink deletion mid-session
VBW_PLUGIN_ROOT=$(cd "$VBW_PLUGIN_ROOT" 2>/dev/null && pwd -P || echo "$VBW_PLUGIN_ROOT")
```

All runtime script invocations below assume `VBW_PLUGIN_ROOT` is set.

### Step 2: Load plans and detect resume state

**Orchestrator read-scope boundary:** You may ONLY read planning/state artifacts: `*-PLAN.md`, `*-SUMMARY.md`, `*-RESEARCH.md`, `STATE.md`, `ROADMAP.md`, `REQUIREMENTS.md`, `.execution-state.json`, `.context-*.md`, `config.json`, and `.vbw-planning/` metadata. Do NOT read product source files (application code, tests, configs outside `.vbw-planning/`). If you need to understand product code to make a routing or sequencing decision, that understanding must come from Dev — delegate it via a task.

1. Glob `*-PLAN.md` in phase dir. Read each plan's YAML frontmatter.
2. Check existing SUMMARY.md files — a plan is progression-complete for Execute dependency routing only when its SUMMARY has `status: complete|partial`. Strict phase/build completion still requires `complete|completed`. A SUMMARY with `status: pending` or no status field is NOT progression-complete.
3. `git log --oneline -20` for committed tasks (crash recovery).
4. Build remaining plans list. If `--plan=NN`, filter to that plan.
4b. **Worktree isolation (REQ-WORKTREE):** If `worktree_isolation` is not `"off"` in config, worktrees remain per-plan but are created/refreshed just in time when a plan becomes runnable. Do **not** create every remaining plan worktree up front; a dependent serialized plan must start from a branch that includes prerequisite output.
   ```bash
   WORKTREE_ISOLATION=$(jq -r '.worktree_isolation // "off"' .vbw-planning/config.json 2>/dev/null || echo "off")
   ```
  For each plan when it becomes runnable in Step 3:
  - Merge or otherwise make completed prerequisite worktree output visible before creating the dependent plan's worktree.
  - Create/refresh worktree: `WPATH=$(bash "${VBW_PLUGIN_ROOT}/scripts/worktree-create.sh" {phase} {plan} 2>/dev/null || echo "")`. If `WPATH` is empty, log warning and continue without worktree for this plan.
  - If `WPATH` is non-empty: update that plan's `worktree_path` in `.execution-state.json`, regenerate `WTARGET=$(bash "${VBW_PLUGIN_ROOT}/scripts/worktree-target.sh" "$WPATH" 2>/dev/null || echo "{}")`, and register `bash "${VBW_PLUGIN_ROOT}/scripts/worktree-agent-map.sh" set "dev-{plan}" "$WPATH" {phase} {plan} 2>/dev/null || true` before spawning Dev.
  - After merge/cleanup for that plan, clear `bash "${VBW_PLUGIN_ROOT}/scripts/worktree-agent-map.sh" clear "dev-{plan}" 2>/dev/null || true`.
   When `worktree_isolation="off"`: skip this step silently.
5. Partially-complete plans: note resume-from task number.
6. **Crash recovery:** If `.vbw-planning/.execution-state.json` exists with `"status": "running"`, update plan statuses to match current SUMMARY.md state.
   - **Event Recovery (REQ-17):** If `event_recovery=true` in config, attempt event-sourced recovery first:
  `RECOVERED=$(bash "${VBW_PLUGIN_ROOT}/scripts/recover-state.sh" {phase} 2>/dev/null || echo "{}")`
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
  "effort": "{effective effort}", "phase_effort": "{configured phase effort}",
  "plans": [{"id": "NN-MM", "title": "...", "wave": W, "status": "pending|complete|partial|failed"}]
}
```
Set plan status from verified SUMMARY.md frontmatter: `complete|completed` → `"complete"`, `partial` → `"partial"`, `failed` → `"failed"`, others → `"pending"`. `phase_effort` preserves the configured phase effort; `effort` may be temporarily changed to `turbo` or internal `direct` for segment-local guard visibility and restored before the next non-direct segment.

**Task list hygiene (crash-resume):** When resuming execution (`.execution-state.json` already existed), plans that are already `"complete"` were finished in a prior session. Immediately mark those plans as completed in your task list — do NOT leave them as not-started or in-progress. Only pending plans should be active in your task list.

7b. **Export correlation_id:** Set `VBW_CORRELATION_ID={CORRELATION_ID}` in the execution environment
    so log-event.sh can fall back to it if .execution-state.json is temporarily unavailable.
    Log a confirmation: `◆ Correlation ID: {CORRELATION_ID}`

8. **Event Log (REQ-16, graduated, always-on):**
  - Log phase start: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" phase_start {phase} 2>/dev/null || true`

9. **Snapshot Resume (REQ-18):** If `snapshot_resume=true` in config:
   - On crash recovery (execution-state.json exists with `"status": "running"`): attempt restore:
  `SNAPSHOT=$(bash "${VBW_PLUGIN_ROOT}/scripts/snapshot-resume.sh" restore {phase} {preferred-role} 2>/dev/null || echo "")`
   - If snapshot found, log: `✓ Snapshot found: ${SNAPSHOT}` — use snapshot's `recent_commits` to cross-reference git log for more reliable resume-from detection.

10. **Schema Validation (REQ-17, graduated, always-on):**
   - Validate each PLAN.md frontmatter before execution:
     `VALID=$(bash "${VBW_PLUGIN_ROOT}/scripts/validate-schema.sh" plan {plan_path} 2>/dev/null || echo "valid")`
   - If `invalid`: log warning `⚠ Plan {NN-MM} schema: ${VALID}` — continue execution (advisory only).
   - Log to metrics: `bash "${VBW_PLUGIN_ROOT}/scripts/collect-metrics.sh" schema_check {phase} {plan} result=$VALID 2>/dev/null || true`

11. **Cross-phase deps (PWR-04):** For each plan with `cross_phase_deps`:
   - Verify referenced plan's SUMMARY.md exists with `status: complete`
   - If artifact path specified, verify file exists
   - Unsatisfied → STOP: "Cross-phase dependency not met. Plan {id} depends on Phase {P}, Plan {plan} ({reason}). Status: {failed|missing|not built}. Fix: Run /vbw:vibe {P}"
   - All satisfied: `✓ Cross-phase dependencies verified`
   - No cross_phase_deps: skip silently

### Step 3: Resolve Execute routing and run segments

**Smart Routing (REQ-15):** If `smart_routing=true` in config, build a transient route map before selecting team/subagent mode:
```bash
ROUTE_MAP=.vbw-planning/.cache/execute-route-map.json
mkdir -p .vbw-planning/.cache
printf '{"plans":{}}\n' > "$ROUTE_MAP"
```
- For each remaining plan, assess risk before team selection:
  ```bash
  RISK=$(bash "${VBW_PLUGIN_ROOT}/scripts/assess-plan-risk.sh" {plan_path} 2>/dev/null || echo "medium")
  TASK_COUNT=$(grep -c '^### Task [0-9]' {plan_path} 2>/dev/null || echo "0")
  ```
- If `RISK=low` AND `TASK_COUNT<=3` AND effort is not `thorough`: write route `turbo` for that plan in `$ROUTE_MAP` and log numeric metrics:
  `bash "${VBW_PLUGIN_ROOT}/scripts/collect-metrics.sh" smart_route {phase} {plan} risk=$RISK tasks=$TASK_COUNT routed=turbo 2>/dev/null || true`
- Otherwise: omit the route-map entry or write route `delegate`; log non-turbo delegated metrics as:
  `bash "${VBW_PLUGIN_ROOT}/scripts/collect-metrics.sh" smart_route {phase} {plan} risk=$RISK tasks=$TASK_COUNT routed=team 2>/dev/null || true`
- Internal route `direct` is only for explicit route-map entries supplied by existing guard/delegation machinery. Do not add a user-facing `direct` phase effort.
- On script error: leave the plan unlisted in the route map; missing entries default to delegate.

**Dependency-aware routing helper:** After `.execution-state.json` and the optional route map exist, resolve routing before writing `.delegated-workflow.json`:
```bash
ROUTE_ARGS=()
[ -f .vbw-planning/.cache/execute-route-map.json ] && ROUTE_ARGS=(--route-map .vbw-planning/.cache/execute-route-map.json)
ROUTING=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-execute-delegation-mode.sh" \
  --phase-dir "{phase_dir}" \
  --config .vbw-planning/config.json \
  --execution-state .vbw-planning/.execution-state.json \
  "${ROUTE_ARGS[@]}" \
  --segments)
```
The helper canonicalizes `prefer_teams` with `normalize-prefer-teams.sh`, computes remaining dependency waves from the execution state and plan frontmatter, and emits compact JSON (`delegation_mode`, `requested_mode`, `reason`, `max_parallel_width`, `delegate_count`, route-specific plan IDs, and ordered `segments`).
If the helper exits non-zero or returns `reason=invalid_dependency_graph`, stop before spawning agents and surface the diagnostic. Valid serial graphs are not errors: `prefer_teams=auto` with `max_parallel_width <= 1` uses serialized Dev subagents.

Team request policy from helper output:
- `prefer_teams='always'`: request team mode for delegate-eligible work regardless of dependency width; it does not override phase-level turbo, smart-routed turbo, or explicit internal-direct segments.
- `prefer_teams='auto'`: request team mode only when dependency analysis finds real parallel delegate work (`max_parallel_width > 1`).
- `prefer_teams='never'`: request explicit non-team mode.
- Unknown normalized values preserve the raw value, use `delegation_mode=subagent`, and report `unknown_prefer_teams:<value>`.

Determine whether **real team semantics** are available in the live tool set before spawning anything:
- Real team semantics are available when either:
  1. `TeamCreate` + teammate task spawning are available, **or**
  2. the live teammate spawn tool accepts both `team_name` and per-teammate `name` parameters (for example `Agent(...)` with `team_name:` and `name:`)
- If the live tool set only supports plain background spawns (for example `Agent` with `run_in_background: true` but no `team_name`), then real team semantics are **NOT** available.
- **Plain background `Agent` spawns without team semantics are NOT an agent team. Do NOT use them as a substitute for team mode.**

Process `ROUTING.segments[]` in order. For each segment, extract `route`, `plan_ids`, `effort`, `delegation_mode`, and optional `team_name` from the helper output. Before any direct, turbo, fallback, or serialized subagent segment starts, check the current delegation marker; if a live execute marker has `delegation_mode=team`, complete shutdown (`shutdown_request`, responses, `TeamDelete`, stale cleanup) and clear the marker first. Do not start a non-team segment while `.delegated-workflow.json` still reports a live team marker.

Branch each segment into exactly one runtime path and persist that segment's actual mode **before the first spawn or orchestrator product-file write**:

1. **True team mode**
   - Use this path only when the helper segment has `delegation_mode=team` **and** real team semantics are available.
   - **Pre-TeamCreate cleanup** (remove orphaned VBW team directories from prior sessions before creating a new team):
     ```bash
     bash "${VBW_PLUGIN_ROOT}/scripts/clean-stale-teams.sh" 2>/dev/null || true
     ```
   - Set `TEAM_NAME` from the segment (`team_name`) or default to `"vbw-phase-{NN}"`.
   - If literal `TeamCreate` is available, call it with `team_name="$TEAM_NAME"`, `description="Phase {NN}: {phase-name}"`.
   - If literal `TeamCreate` is unavailable but the live teammate spawn tool accepts `team_name`, create the team implicitly by using the shared `TEAM_NAME` on every teammate spawn.
   - Persist the actual runtime mode:
     ```bash
     bash "${VBW_PLUGIN_ROOT}/scripts/delegated-workflow.sh" set execute {segment_effort} team "$TEAM_NAME"
     ```
   - All Dev and QA teammates below MUST carry `team_name: "$TEAM_NAME"` plus `name: "dev-{MM}"` (from plan number) or `name: "qa"` / `name: "qa-wave{W}"` on the live spawn call. No plain task-management `TaskCreate` may happen after the team marker is set unless it carries the selected `TEAM_NAME` and teammate `name`.

2. **Explicit non-team mode**
   - Use this path when `prefer_teams='never'`, `prefer_teams='auto'` with `max_parallel_width <= 1`, unknown `prefer_teams`, no delegate-eligible plans, segment route `turbo`/internal `direct`, or team-tooling-unavailable fallback.
   - For serialized delegate segments (`route=delegate`, `delegation_mode=subagent`), persist the actual runtime mode as subagent, skip TeamCreate, spawn one Dev subagent, and wait for completion before the next spawn:
     ```bash
     bash "${VBW_PLUGIN_ROOT}/scripts/delegated-workflow.sh" set execute {segment_effort} subagent
     ```
   - For `turbo` or internal `direct` segments (`delegation_mode=direct`), update `.execution-state.json.effort` to `turbo` or `direct` before orchestrator product-file writes; keep `phase_effort` unchanged, persist the actual runtime mode as direct, and restore `.execution-state.json.effort` to `phase_effort` before the next non-direct segment:
     ```bash
     bash "${VBW_PLUGIN_ROOT}/scripts/delegated-workflow.sh" set execute {segment_effort} direct
     ```
   - **Do NOT use `run_in_background: true` to simulate parallelism in non-team mode.**

3. **Team-tooling-unavailable fallback**
   - Use this path when the helper requests `delegation_mode=team` but the live tool set cannot express real team semantics.
   - Display: `⚠ Agent Teams not enabled — using non-team mode`
   - Persist the fallback runtime mode:
     ```bash
     bash "${VBW_PLUGIN_ROOT}/scripts/delegated-workflow.sh" set execute {segment_effort} subagent
     ```
   - Skip TeamCreate and continue in explicit non-team mode.
   - **Do NOT preserve “parallelism” by launching multiple background `Agent` spawns without `team_name`.**

After each segment completes, verify each plan's SUMMARY.md through Step 3c and write the verified status (`complete`, `partial`, or `failed`) into `.execution-state.json`. Only `complete|partial` unlock dependents. Re-run the helper against the updated execution state until no pending plans remain.

**Delegation directive (all except Turbo):**
You are the team LEAD. NEVER implement tasks yourself.
- Delegate ALL implementation to Dev teammates via TaskCreate
- NEVER Write/Edit files in a plan's `files_modified` — only state files: STATE.md, ROADMAP.md, .execution-state.json, SUMMARY.md
- If Dev fails: guidance via SendMessage, not takeover. If all Devs unavailable: create new Dev.
- **Subagent return handling (non-team model):** When a Dev subagent Task returns, inspect the result immediately:
  1. **platform/tool provisioning failure:** If the returned text explicitly says tools, Bash, filesystem, edits, or API-session access are unavailable, optionally paired with visible zero tool-use metadata when you can see it, stop immediately and surface a platform/tool provisioning blocker. Do not consume the normal retry budget and do not re-spawn the same prompt shape; the child cannot fix missing tools by receiving the same instructions again.
  2. **blocker_report received:** Read the blocker details. If the blocker is a tool precondition error (e.g., "File has not been read yet"), amend the task description with explicit "Read {file} first, then edit" and re-spawn once. If the blocker is a validation contradiction or empty-result failure, do NOT blindly re-spawn — the same subagent prompt will hit the same wall. Instead: (a) verify the validation target yourself (run the bash/curl command Lead can execute), (b) if the data truly contradicts expectations, update the plan task to reflect reality, (c) re-spawn with the corrected task.
  3. **Task returned without SUMMARY.md or with incomplete work:** Check what the Dev actually accomplished (git log, file changes). If partial progress was made, spawn a new Dev with "Continue from where the previous Dev stopped — files X, Y already modified, remaining work is Z." If zero progress, check whether the task description was ambiguous or missing context and re-spawn with clarification.
  4. **Max retry: 2 re-spawns per plan.** After 2 failed Dev spawns for the same plan, stop and surface the blocker to the user: "Dev agent failed {N} times on plan {plan_id}. Last blocker: {details}. Manual intervention needed."
- At Turbo (or smart-routed to turbo): no team — Dev executes directly.
- **Runtime enforcement:** This directive is structurally enforced by the `file-guard.sh` PreToolUse hook. When `.execution-state.json` has `status: running` and effort is not turbo/direct, the hook blocks product-file Write/Edit from the orchestrator. Two bypass mechanisms exist:
  - **Subagent model:** `.active-agent-count` (written by `agent-start.sh`): when count > 0, at least one VBW subagent is running and the write is allowed.
  - **Execute team mode:** `scripts/delegated-workflow.sh set execute {effort} team {team_name}` records true team mode before teammate spawns. `file-guard.sh` bypasses only when that execute marker is active. This avoids assuming that `prefer_teams` or background `Agent` spawns automatically imply a real team.
  - When neither bypass applies, the write is treated as an orchestrator action and blocked. Planning/state artifacts (`.vbw-planning/*`, `STATE.md`, `SUMMARY.md`, etc.) remain exempt.

**Monorepo Routing (REQ-17):** If `monorepo_routing=true` in config:
- Before context compilation, detect relevant package paths:
  `PACKAGES=$(bash "${VBW_PLUGIN_ROOT}/scripts/route-monorepo.sh" {phase_dir} 2>/dev/null || echo "[]")`
- If non-empty array (not `[]`): pass package paths to context compilation for scoped file inclusion.
  Log: `bash "${VBW_PLUGIN_ROOT}/scripts/collect-metrics.sh" monorepo_route {phase} packages=$PACKAGES 2>/dev/null || true`
- If empty or error: proceed with default (full repo) context compilation.

**Control Plane Coordination (REQ-05):** If `${VBW_PLUGIN_ROOT}/scripts/control-plane.sh` exists:
- **Once per plan (before first task):** Run the `full` action to generate contract and compile context:
  ```bash
  CP_RESULT=$(bash "${VBW_PLUGIN_ROOT}/scripts/control-plane.sh" full {phase} {plan} 1 \
    --plan-path={plan_path} --role=dev --phase-dir={phase-dir} 2>/dev/null || echo '{"action":"full","steps":[]}')
  ```
  Extract `contract_path` and `context_path` from result for subsequent per-task calls.
- **Before each task:** Run the `pre-task` action:
  ```bash
  CP_RESULT=$(bash "${VBW_PLUGIN_ROOT}/scripts/control-plane.sh" pre-task {phase} {plan} {task} \
    --plan-path={plan_path} --task-id={phase}-{plan}-T{task} \
    --claimed-files={files_from_task} 2>/dev/null || echo '{"action":"pre-task","steps":[]}')
  ```
  If the result contains a gate failure (step with `status=fail`), treat as gate failure and follow existing auto-repair + escalation flow.
- **After each task:** Run the `post-task` action:
  ```bash
  CP_RESULT=$(bash "${VBW_PLUGIN_ROOT}/scripts/control-plane.sh" post-task {phase} {plan} {task} \
    --task-id={phase}-{plan}-T{task} 2>/dev/null || echo '{"action":"post-task","steps":[]}')
  ```
- If `control-plane.sh` does NOT exist: fall through to the individual script calls below (backward compatibility).
- On any `control-plane.sh` error: fall through to individual script calls (fail-open).

The existing individual script call sections (V3 Contract-Lite, V2 Hard Gates, Context compilation, Token Budgets) remain unchanged below as the fallback path.

**Context compilation (REQ-11):** If control-plane.sh `full` action was used above and returned a `context_path`, use that path directly. Otherwise, if `config_context_compiler=true` from Context block above, before creating Dev tasks run:
`bash "${VBW_PLUGIN_ROOT}/scripts/compile-context.sh" {phase} dev {phases_dir} {plan_path}`
This produces `{phase-dir}/.context-dev.md` with phase goal and conventions.
The plan_path argument is passed for context. **Research resolution:** For a specific plan `{NN}-{MM}-PLAN.md`, resolve research in this order:
1. Per-plan research: `{phase-dir}/{NN}-{MM}-RESEARCH.md` (if the plan has its own research)
2. Phase-wide research: resolve via `bash "${VBW_PLUGIN_ROOT}/scripts/resolve-artifact-path.sh" phase-research "{phase-dir}"` → `{phase-dir}/{NN}-RESEARCH.md`
3. Wildcard fallback: first `*-RESEARCH.md` in the phase directory

Include the first match in the Dev task prompt alongside the compiled context. Phase-wide research (`{NN}-RESEARCH.md`) is the default — Plan mode creates it before Lead plans. Per-plan research (`{NN}-{MM}-RESEARCH.md`) is used only for plan-specific research added after initial planning. Skill activation uses a plan-driven architecture:
- **Orchestrator skill selection:** When composing subagent task descriptions, the orchestrator uses a two-pass rubric. **Pass 1:** derive technical domains from the task text plus structured metadata already available — logs, error text, related files, prior detail context, and any bounded sparse-input enrichment. When the input is sparse but names a concrete symbol, service, type, or file, reuse existing detail metadata first; if that is absent, resolve at most 1-3 likely files or framework markers before final preselection. SwiftData markers such as `import SwiftData`, `@Model`, `ModelContext`, `ModelContainer`, `FetchDescriptor`, `VersionedSchema`, `SchemaMigrationPlan`, or `PersistentModel` are sufficient evidence to select `swiftdata`. Do NOT add `core-data` as a generic persistence fallback unless the actual evidence instead shows Core Data APIs such as `import CoreData`, `NSManagedObject`, `NSPersistentContainer`, `NSFetchRequest`, or `NSManagedObjectContext`. **Pass 2:** select all materially helpful direct matches plus only the narrowly adjacent support skills surfaced by those domains — not just the single most direct skill. Every spawned prompt that performs this evaluation must begin with exactly one explicit outcome block: `<skill_activation>` when one or more skills are preselected at orchestration time, or `<skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. The orchestrator also states the skill evaluation outcome in its visible response before spawning the agent, giving the user visibility into which skills were preselected or why none were. If bounded enrichment influenced the decision, the orchestrator cites that explicitly in the visible outcome and reason text.
- **Lead (planning time):** Wires the final skill set into plans via `skills_used` frontmatter and `@`-references to SKILL.md files, including materially helpful adjacent/supporting domain skills surfaced during research or error analysis.
- **Spawned agents (Lead/Dev/QA/Scout/Docs/Debugger/Architect):** Treat `<skill_activation>` and `<skill_no_activation>` as explicit orchestrator starting state, not as a ceiling. Call preselected skills first, honor any plan `skills_used`, then run one bounded completeness pass over `<available_skills>` to add any missing adjacent/domain skills surfaced by the prompt or context. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting — do not scan entire skill folders or read unrelated references. When a `<skill_follow_up_files>` block is present, treat it as the authoritative resolved path list for the preselected skills and read those exact paths before any other skill-related exploration.
- **Ad-hoc paths (`/vbw:fix`, `/vbw:debug`, `/vbw:research`):** Debugger/Dev/Scout still evaluate installed skills directly because no plan exists, but they follow the same additive model: start with any orchestrator preselection, apply the same bounded sparse-input enrichment rule when the task names a concrete symbol/service/type/file but lacks richer metadata, then add materially helpful adjacent/domain skills discovered from the active task context.
- **Architect (scoping time):** Evaluates installed skills in system context. Activates relevant skills before producing requirements and roadmap artifacts.
- **Runtime skill hooks preserved:** `skill-hook-dispatch.sh` dispatches skill-defined PostToolUse/PreToolUse hooks at runtime. This is separate from skill *activation* and is unaffected by the plan-driven model.
If compilation fails, proceed without it — Dev reads files directly.

**V2 Token Budgets (REQ-12):** If control-plane.sh `compile` or `full` action was used and included token budget enforcement, skip this step. Otherwise:
- After context compilation, enforce per-role token budgets. Pass the contract path and task number for per-task budget computation:
  ```bash
  bash "${VBW_PLUGIN_ROOT}/scripts/token-budget.sh" dev {phase-dir}/.context-dev.md {contract_path} {task_number} > {phase-dir}/.context-dev.md.tmp && mv {phase-dir}/.context-dev.md.tmp {phase-dir}/.context-dev.md
  ```
  Where `{contract_path}` is `.vbw-planning/.contracts/{phase}-{plan}.json` (generated by generate-contract.sh in Step 3) and `{task_number}` is the current task being executed (1-based). When no contract is available, omit the contract_path and task_number arguments (per-role fallback).
- Same for QA context: `bash "${VBW_PLUGIN_ROOT}/scripts/token-budget.sh" qa {phase-dir}/.context-qa.md {contract_path} {task_number} > ...`
- Role caps defined in `config/token-budgets.json`: Scout (200 lines), Lead/Architect (500), QA (600), Dev/Debugger (800).
- Per-task budgets use contract metadata (must_haves, allowed_paths, depends_on) to compute a complexity score, which maps to a tier multiplier applied to the role's base budget.
- Overage logged to metrics as `token_overage` event with role, lines truncated, and budget_source (task or role).
- **Escalation:** When overage occurs, token-budget.sh emits a `token_cap_escalated` event and reduces the remaining budget for subsequent tasks in the plan. The budget reduction state is stored in `.vbw-planning/.token-state/{phase}-{plan}.json`. Escalation is advisory only -- execution continues regardless.
- **Cleanup:** At phase end, clean up token state: `rm -f .vbw-planning/.token-state/*.json 2>/dev/null || true`
- Truncation uses tail strategy (keep most recent context).

**Pre-code validation gate (mandatory when plan requires it):**
If a plan task contains validation requirements such as "MUST be done before any code changes", "Expected: ...", or "If absent, stop and re-analyze", the validation result is a hard gate:

1. **Execute the validation** using the tool appropriate to the data source:
   - **Public/anonymous endpoints** (docs pages, open APIs, status endpoints): WebFetch is acceptable.
   - **Authenticated/private APIs** (signed requests, tokens, env-based secrets, custom headers): use Bash helper scripts, curl wrappers, or repo helper commands. Do not route authenticated API validation through WebFetch.
2. **Evaluate the result:**
   - If the result matches the task's expected shape: gate passes, proceed with code changes.
   - If the result contradicts expectations (wrong values, missing fields, empty when non-empty expected): gate fails.
3. **On gate failure:**
   - Run ONE broadened sanity-check query (remove filters, broaden search, confirm environment/account context).
   - If the contradiction remains: send `blocker_report` immediately. Do NOT proceed to the next task or begin code changes.
   - Empty filtered results (`[]`, no matches) are contradictory when the task expected specific data — do not treat empty as success unless the task explicitly defines empty as the expected outcome.
4. **Operator fallback:** If automated respawn after a blocker is not possible, surface a message to the user: "Validation gate failed for task {N}. Restart `/vbw:vibe` from current plan state to retry."


**Model resolution:** Resolve models for Dev and QA agents:
```bash
DEV_MODEL=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-agent-model.sh" dev .vbw-planning/config.json "${VBW_PLUGIN_ROOT}/config/model-profiles.json")
if [ $? -ne 0 ]; then echo "$DEV_MODEL" >&2; exit 1; fi
DEV_MAX_TURNS=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh" dev .vbw-planning/config.json "{effort}")
if [ $? -ne 0 ]; then echo "$DEV_MAX_TURNS" >&2; exit 1; fi

QA_MODEL=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-agent-model.sh" qa .vbw-planning/config.json "${VBW_PLUGIN_ROOT}/config/model-profiles.json")
if [ $? -ne 0 ]; then echo "$QA_MODEL" >&2; exit 1; fi
QA_MAX_TURNS=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh" qa .vbw-planning/config.json "{effort}")
if [ $? -ne 0 ]; then echo "$QA_MAX_TURNS" >&2; exit 1; fi
```

**Skill activation for Dev/QA tasks:** Before composing task descriptions, evaluate installed skills visible in your system context — read each skill's description and select all materially helpful installed skills for the tasks being executed, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context — not just the single most direct skill. Every spawned prompt that performs this evaluation MUST begin with exactly one explicit outcome block: use `<skill_activation>` as the FIRST line when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>` as the FIRST line when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected — {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting — do not scan entire skill folders or read unrelated references. When preselected skills expose named local follow-up docs, resolve them with `extract-skill-follow-up-files.sh` and paste the emitted `<skill_follow_up_files>` block immediately after the follow-up-read sentence in the spawned payload.

**MCP-derived context for Dev tasks:** You may use MCP tools available in the parent session to pre-extract concise task-relevant facts, docs, command results, or paths for Dev. Pass that MCP-derived context into the Dev task description, but do not instruct `vbw-dev` to call MCP servers directly; Dev uses an explicit tool allowlist and validates with built-in tools or Bash-accessible CLIs.

For each runnable plan in the current segment, create the teammate task using the live teammate spawn tool (for example `TaskCreate` or `Agent`). In non-team mode, spawn exactly one Dev and wait for its result before spawning the next runnable plan. In true team mode, every spawn/TaskCreate after the marker is set must include the selected `TEAM_NAME` and teammate `name`.

**Non-team spawn-shape rule:** On non-team live teammate spawn calls, whether the live tool is `Agent` or `TaskCreate`, omit `team_name`, per-agent `name`, `run_in_background`, and `isolation`. Prepared VBW worktree targeting means the `Working directory:` and `Worktree targeting:` lines in the task description, derived from `.execution-state.json` `worktree_path` and `scripts/worktree-target.sh`; it is not an `isolation` or `cwd` field on the spawn call. Claude-side `isolation:"worktree"` can create unmanaged `.claude/worktrees/agent-*` sidechains with different tool/artifact assumptions; VBW's current isolation uses its own `.vbw-worktrees` git worktrees.
```yaml
subject: "Execute {NN-MM}: {plan-title}"
description: |
  <!-- When skills apply: -->
  <skill_activation>Call Skill('{relevant-skill-1}'). Call Skill('{relevant-skill-2}').</skill_activation>
  After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting — do not scan entire skill folders or read unrelated references.
  <skill_follow_up_files>{If one or more skills were preselected, run `bash "${VBW_PLUGIN_ROOT}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning and replace this block with the emitted absolute follow-up file paths. Omit this block when the helper prints nothing.}</skill_follow_up_files>
  <!-- OR when no skills apply: -->
  <skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>
  After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting — do not scan entire skill folders or read unrelated references.
  Execute all tasks in {PLAN_PATH}.
  Effort: {DEV_EFFORT}. Working directory: {worktree_path (from execution-state.json for this plan) if worktree_isolation is enabled and worktree_path is set, else {pwd}}.
  {If worktree_isolation enabled and WTARGET non-empty: "Worktree targeting: {WTARGET}"}
  Model: ${DEV_MODEL}
  Phase context: {phase-dir}/.context-dev.md (if compiled)
  If `.vbw-planning/codebase/META.md` exists, read CONVENTIONS.md, PATTERNS.md, STRUCTURE.md, and DEPENDENCIES.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before executing.
  {If resuming: "Resume from Task {NN}. Tasks 1-{NN-1} already committed."}
  {If autonomous: false: "This plan has checkpoints -- pause for user input."}
activeForm: "Executing {NN-MM}"
```

**TaskCompleted advisory scope:** Commit verification is advisory and only applies to canonical execute-task subjects (`Execute {NN-MM}: {plan-title}`). Manual, research, setup, and other non-execute tasks are allowed to complete without commit matching.

Display: `◆ Spawning Dev teammate (${DEV_MODEL})...`

**CRITICAL:** Set `subagent_type: "vbw:vbw-dev"` and `model: "${DEV_MODEL}"` on the live spawn call when spawning Dev teammates. If `DEV_MAX_TURNS` is non-empty, also pass `maxTurns: ${DEV_MAX_TURNS}`. If `DEV_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).
**CRITICAL:** When true team mode is active, pass `team_name: "vbw-phase-{NN}"` and `name: "dev-{MM}"` on the live spawn call. If the live spawn tool is `Agent`, those parameters belong on `Agent(...)`. If the live spawn tool is `TaskCreate`, put the same parameters there. Team mode without `team_name` is invalid.
**CRITICAL:** In explicit non-team mode or team-tooling-unavailable fallback, do NOT use `run_in_background: true` to imitate parallel team execution.

Dependency ordering is enforced by the routing helper's segment plan, not by speculative background spawns. Use TaskUpdate dependency metadata only as a task-list mirror of `depends_on`; do not spawn a dependent plan until the helper recomputes it as runnable from updated execution state. If `--plan=NN`: single task, no dependencies.

Just before spawning a runnable plan with `worktree_isolation` enabled, create or refresh that plan's worktree, update its `worktree_path` in execution state, regenerate `WTARGET`, and register `dev-{plan}` with `worktree-agent-map.sh`. After the plan's worktree is merged or cleaned up, clear the mapping.

**Blocked agent notification (mandatory):** When a Dev teammate completes a plan (task marked completed + SUMMARY.md verified), check if any other tasks have `blockedBy` containing that completed task's ID. For each newly-unblocked task, send its assigned Dev a message: "Blocking task {id} complete. Your task is now unblocked — proceed with execution." This ensures blocked agents resume without manual intervention.

**Validation Gates (REQ-13, REQ-14):** If `validation_gates=true` in config:
- **Per plan:** Assess risk and resolve gate policy:
  ```bash
  RISK=$(bash "${VBW_PLUGIN_ROOT}/scripts/assess-plan-risk.sh" {plan_path} 2>/dev/null || echo "medium")
  GATE_POLICY=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-gate-policy.sh" {effort} $RISK {autonomy} 2>/dev/null || echo '{}')
  ```
- Extract policy fields: `qa_tier`, `approval_required`, `communication_level`, `two_phase`
- Use these to override the static tables below for this plan
- Log to metrics: `bash "${VBW_PLUGIN_ROOT}/scripts/collect-metrics.sh" gate_policy {phase} {plan} risk=$RISK qa_tier=$QA_TIER approval=$APPROVAL 2>/dev/null || true`
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

Schema ref: `${VBW_PLUGIN_ROOT}/references/handoff-schemas.md`

| Effort | Messages sent |
|--------|--------------|
| Thorough | blockers (blocker_report), findings (scout_findings), progress (execution_update), contracts (plan_contract) |
| Balanced | blockers (blocker_report), progress (execution_update) |
| Fast | blockers only (blocker_report) |
| Turbo | N/A (no team) |

Use targeted `message` not `broadcast`. Reserve broadcast for critical blocking issues only.

**Typed Protocol (REQ-04, REQ-05, graduated, always-on):**
- **On message receive** (from any teammate): validate before processing:
  `VALID=$(echo "$MESSAGE_JSON" | bash "${VBW_PLUGIN_ROOT}/scripts/validate-message.sh" 2>/dev/null || echo '{"valid":true}')`
  If `valid=false`: log rejection, send error back to sender with `errors` array. Do not process the message.
- **On message send** (before sending): agents should construct messages using full V2 envelope (id, type, phase, task, author_role, timestamp, schema_version, payload, confidence). Reference `${VBW_PLUGIN_ROOT}/references/handoff-schemas.md` for schema details.

**Execution state updates:**
- Task completion: update plan status in .execution-state.json (`"complete"`, `"partial"`, or `"failed"` from verified SUMMARY.md status)
- Wave transition: update `"wave"` when first wave N+1 task starts
- Use `jq` for atomic updates

Hooks handle continuous verification: PostToolUse validates SUMMARY.md, TaskCompleted emits advisory execute-task commit checks, TeammateIdle runs quality gate.

**Event Log — plan lifecycle (REQ-16, graduated, always-on):**
- At plan start: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" plan_start {phase} {plan} 2>/dev/null || true`
- At agent spawn: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" agent_spawn {phase} {plan} role=dev model=$DEV_MODEL 2>/dev/null || true`
- At agent shutdown: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" agent_shutdown {phase} {plan} role=dev 2>/dev/null || true`
- At plan complete: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" plan_end {phase} {plan} status=complete 2>/dev/null || true`
- At plan failure: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" plan_end {phase} {plan} status=failed 2>/dev/null || true`
- On error: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" error {phase} {plan} message={error_summary} 2>/dev/null || true`

**Full Event Types (REQ-09, REQ-10, graduated, always-on):** Emit all 13 event types at correct lifecycle points.

> **Naming convention:** Event types (`shutdown_sent`/`shutdown_received`) log _what happened_ — the orchestrator sent or received a message. Message types (`shutdown_request`/`shutdown_response`) define _what was communicated_ — the typed payload in SendMessage. Events are emitted by `log-event.sh`; messages are validated by `validate-message.sh`.
- `phase_planned`: at plan completion (after Lead writes PLAN.md): `log-event.sh phase_planned {phase}`
- `task_created`: when task is defined in plan: `log-event.sh task_created {phase} {plan} task_id={id}`
- `task_claimed`: when Dev starts a task: `log-event.sh task_claimed {phase} {plan} task_id={id} role=dev`
- `task_started`: when task execution begins: `log-event.sh task_started {phase} {plan} task_id={id}`
- `artifact_written`: after writing/modifying a file: `log-event.sh artifact_written {phase} {plan} path={file} task_id={id}`
  - Also register in artifact registry: `bash "${VBW_PLUGIN_ROOT}/scripts/artifact-registry.sh" register {file} {event_id} {phase} {plan}`
- `gate_passed` / `gate_failed`: already emitted by hard-gate.sh
- `task_completed_candidate`: emitted by two-phase-complete.sh
- `task_completed_confirmed`: emitted by two-phase-complete.sh after validation
- `task_blocked`: already emitted by auto-repair.sh
- `task_reassigned`: when task is re-assigned to different agent: `log-event.sh task_reassigned {phase} {plan} task_id={id} from={old} to={new}`
- `shutdown_sent`: when orchestrator sends shutdown_request to teammates: `log-event.sh shutdown_sent {phase} team={team_name} targets={count}`
- `shutdown_received`: when orchestrator has collected all shutdown_response messages: `log-event.sh shutdown_received {phase} team={team_name} approved={count} rejected={count}`

**Snapshot — per-plan checkpoint (REQ-18):** If `snapshot_resume=true` in config:
- After each plan completes (SUMMARY.md verified):
  `bash "${VBW_PLUGIN_ROOT}/scripts/snapshot-resume.sh" save {phase} .vbw-planning/.execution-state.json {agent-role} {trigger} 2>/dev/null || true`
- This captures execution state + recent git context for crash recovery. The optional `{agent-role}` and `{trigger}` arguments add metadata to the snapshot for role-filtered restore.

**Metrics instrumentation (REQ-09):** If `metrics=true` in config:
- At phase start: `bash "${VBW_PLUGIN_ROOT}/scripts/collect-metrics.sh" execute_phase_start {phase} plan_count={N} effort={effort}`
- At each plan completion: `bash "${VBW_PLUGIN_ROOT}/scripts/collect-metrics.sh" execute_plan_complete {phase} {plan} task_count={N} commit_count={N}`
- At phase end: `bash "${VBW_PLUGIN_ROOT}/scripts/collect-metrics.sh" execute_phase_complete {phase} plans_completed={N} total_tasks={N} total_commits={N} deviations={N}`
All metrics calls should be `2>/dev/null || true` — never block execution.

**V3 Contract-Lite (REQ-10, graduated):**
- **Once per plan (before first task):** Generate contract sidecar:
  `bash "${VBW_PLUGIN_ROOT}/scripts/generate-contract.sh" {plan_path} 2>/dev/null || true`
  This produces `.vbw-planning/.contracts/{phase}-{plan}.json` with allowed_paths and must_haves.
- **Before each task:** Validate task start:
  `bash "${VBW_PLUGIN_ROOT}/scripts/validate-contract.sh" start {contract_path} {task_number} 2>/dev/null || true`
- **After each task:** Validate modified files against contract:
  `bash "${VBW_PLUGIN_ROOT}/scripts/validate-contract.sh" end {contract_path} {task_number} {modified_files...} 2>/dev/null || true`
  Where `{modified_files}` comes from `git diff --name-only HEAD~1` after the task's commit.
- Violations are advisory only (logged to metrics, not blocking).

**V2 Hard Gates (REQ-02, REQ-03, graduated):**
- **Pre-task gate sequence (before each task starts):**
  1. `contract_compliance` gate: `bash "${VBW_PLUGIN_ROOT}/scripts/hard-gate.sh" contract_compliance {phase} {plan} {task} {contract_path}`
  2. **Lease acquisition** (V2 control plane): acquire exclusive file lease before protected_file check:
    `bash "${VBW_PLUGIN_ROOT}/scripts/lease-lock.sh" acquire {task_id} --ttl=300 {claimed_files...}`
     - Lease conflict → auto-repair attempt (wait + re-acquire), then escalate blocker if unresolved.
  3. `protected_file` gate: `bash "${VBW_PLUGIN_ROOT}/scripts/hard-gate.sh" protected_file {phase} {plan} {task} {contract_path}`
  - If any gate fails (exit 2): attempt auto-repair:
    `REPAIR=$(bash "${VBW_PLUGIN_ROOT}/scripts/auto-repair.sh" {gate_type} {phase} {plan} {task} {contract_path})`
  - If `repaired=true`: re-run the failed gate to confirm, then proceed.
  - If `repaired=false`: emit blocker, halt task execution. Send Lead a message with the failure evidence and next action from the blocker event.
- **Post-task gate sequence (after each task commit):**
  1. `required_checks` gate: `bash "${VBW_PLUGIN_ROOT}/scripts/hard-gate.sh" required_checks {phase} {plan} {task} {contract_path}`
  2. `commit_hygiene` gate: `bash "${VBW_PLUGIN_ROOT}/scripts/hard-gate.sh" commit_hygiene {phase} {plan} {task} {contract_path}`
  3. **Lease release**: release file lease after task completes:
    `bash "${VBW_PLUGIN_ROOT}/scripts/lease-lock.sh" release {task_id}`
  - Gate failures trigger auto-repair with same flow as pre-task.
- **Post-plan gate (after all tasks complete, before marking plan done):**
  1. `artifact_persistence` gate: `bash "${VBW_PLUGIN_ROOT}/scripts/hard-gate.sh" artifact_persistence {phase} {plan} {task} {contract_path}`
  - This gate fires AFTER SUMMARY.md verification but BEFORE updating execution-state.json to the verified terminal status.
- **YOLO mode:** Hard gates ALWAYS fire regardless of autonomy level. YOLO only skips confirmation prompts.
- **Fallback:** If hard-gate.sh or auto-repair.sh errors (not a gate fail, but a script error), log to metrics and continue (fail-open on script errors, hard-stop only on gate verdicts).

**Lease Locks (REQ-17):** If `lease_locks=true` in config:
- Use `lease-lock.sh` for all lock operations:
  - Acquire: `bash "${VBW_PLUGIN_ROOT}/scripts/lease-lock.sh" acquire {task_id} --ttl=300 {claimed_files...} 2>/dev/null || true`
  - Release: `bash "${VBW_PLUGIN_ROOT}/scripts/lease-lock.sh" release {task_id} 2>/dev/null || true`
- **During long-running tasks** (>2 minutes estimated): renew lease periodically:
  `bash "${VBW_PLUGIN_ROOT}/scripts/lease-lock.sh" renew {task_id} 2>/dev/null || true`
- Check for expired leases before acquiring: `bash "${VBW_PLUGIN_ROOT}/scripts/lease-lock.sh" check {task_id} {claimed_files...} 2>/dev/null || true`

### Step 3b: Two-Phase Completion (REQ-09)

**If `two_phase_completion=true` in config:**

After each task commit (and after post-task gates pass), run two-phase completion:
```bash
RESULT=$(bash "${VBW_PLUGIN_ROOT}/scripts/two-phase-complete.sh" {task_id} {phase} {plan} {contract_path} {evidence...})
```
- If `result=confirmed`: proceed to next task.
- If `result=rejected`: treat as gate failure — attempt auto-repair (re-run checks), then escalate blocker if still failing.
- Artifact registration: after each file write during task execution, register the artifact:
  ```bash
  bash "${VBW_PLUGIN_ROOT}/scripts/artifact-registry.sh" register {file_path} {event_id} {phase} {plan}
  ```
- When `two_phase_completion=false`: skip (direct task completion as before).

### Step 3c: SUMMARY.md verification gate (mandatory)

**This is a hard gate. Do NOT proceed to QA or mark a plan terminal in .execution-state.json without verifying its SUMMARY.md.**

When a Dev teammate reports plan completion (task marked completed):
1. **Check:** Verify `{phase_dir}/{plan_id}-SUMMARY.md` exists and contains commit hashes, task statuses, and files modified.
2. **Status validation:** Verify SUMMARY.md frontmatter `status` is one of `complete|partial|failed`. Never accept `pending`, `draft`, or other non-terminal values. The `file-guard.sh` PreToolUse hook blocks SUMMARY writes with non-terminal status values. **Exception:** Remediation round summaries (`R{RR}-SUMMARY.md`) are exempt from this guard — they use an incremental lifecycle where the first Dev creates the file with `status: in-progress`, subsequent Devs append task sections, and the Lead finalizes the frontmatter to a terminal status after all tasks complete.
3. **If missing or incomplete:** Send the Dev a message: "Write {plan_id}-SUMMARY.md using the template at templates/SUMMARY.md. Include commit hashes, tasks completed, files modified, and any deviations." Wait for confirmation before proceeding.
4. **If Dev is unavailable:** Write it yourself from `git log --oneline` and the PLAN.md.
5. **Schema Validation — SUMMARY.md (REQ-17, graduated, always-on):**
  - Validate SUMMARY.md frontmatter: `VALID=$(bash "${VBW_PLUGIN_ROOT}/scripts/validate-schema.sh" summary {summary_path} 2>/dev/null || echo "valid")`
   - If `invalid`: log warning `⚠ Summary {plan_id} schema: ${VALID}` — advisory only.
6. **Only after SUMMARY.md is verified with terminal status:** Canonicalize and write the verified status to `.execution-state.json`: `complete|completed` → `"complete"`, `partial` → `"partial"`, `failed` → `"failed"`. Only `complete|partial` satisfy Execute dependencies; `failed` is terminal but does not unlock dependents.

**SUMMARY.md timing rule:** A SUMMARY.md represents completed execution. Never create a SUMMARY.md as a placeholder or stub before execution begins. Do not write SUMMARY.md with `status: pending` or any non-terminal status. **Exception:** Remediation round summaries (`R{RR}-SUMMARY.md`) are built incrementally across multiple Dev agents — the first Dev creates the file with `status: in-progress` and subsequent Devs append task sections. The Lead finalizes the frontmatter after all tasks complete.

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

**After QA persists VERIFICATION.md (and only after that), run the verification threshold gate:**
```bash
bash "${VBW_PLUGIN_ROOT}/scripts/hard-gate.sh" verification_threshold {phase} {plan} {task} {contract_path}
```
If this gate fails, treat it as a QA/verification failure and stop before UAT.

**Dev-surfaced issues collection (before spawning QA):**
After all plans are complete (Step 3c verified), collect deviations and pre-existing issues from all SUMMARY.md files. This data is passed to QA in the task description so QA can treat deviations as FAIL checks and persist pre-existing issues in VERIFICATION.md.

```bash
# Collect deviations and pre-existing issues from all SUMMARY.md files
DEV_ISSUES=""
for summary_file in {phase-dir}/*-SUMMARY.md; do
  [ -f "$summary_file" ] || continue
  plan_id=$(basename "$summary_file" | sed 's/-SUMMARY\.md$//')

  # Extract deviations from YAML frontmatter
  devs=$(awk '
    BEGIN { in_fm=0; in_dev=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^deviations:/ { in_dev=1; next }
    in_fm && in_dev && /^[[:space:]]+- / {
      line=$0; sub(/^[[:space:]]+- /, "", line)
      gsub(/^"/, "", line); gsub(/"$/, "", line)
      items = items (items ? "; " : "") line; next
    }
    in_fm && in_dev && /^[^[:space:]]/ { exit }
    END { print items }
  ' "$summary_file" 2>/dev/null)

  # Fallback: extract deviations from body ## Deviations section
  # Dev agents frequently write deviations only in the body, omitting
  # the YAML frontmatter array. This fallback ensures QA always receives them.
  if [ -z "$devs" ]; then
    devs=$(awk '
      /^## Deviations/ { found=1; next }
      found && /^## / { exit }
      found && /^[[:space:]]*$/ { next }
      found && /^- / {
        line=$0; sub(/^- /, "", line)
        if (tolower(line) ~ /^\*\*n(one|\/a|a)\*\*/ || tolower(line) ~ /^\*\*no deviations\*\*/) next
        sub(/^\*\*[^*]+\*\*:?[[:space:]]*/, "", line)
        lc = tolower(line)
        if (lc ~ /^none[. ]/ || lc == "none" || lc ~ /^n\/a[. ]/ || lc == "n/a" || lc == "na" || lc ~ /^no deviations/) next
        items = items (items ? "; " : "") line
      }
      END { print items }
    ' "$summary_file" 2>/dev/null)
  fi

  # Extract pre-existing issues from canonical SUMMARY.md frontmatter first.
  preex_key_present=false
  awk '
    BEGIN { in_fm=0; found=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit(found ? 0 : 1) }
    in_fm && /^pre_existing_issues:[[:space:]]*/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$summary_file" >/dev/null 2>&1 && preex_key_present=true

  preex=$(awk '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    function strip_quotes(v, first, last) {
      first = substr(v, 1, 1)
      last = substr(v, length(v), 1)
      if ((first == "\"" && last == "\"") || (first == squote && last == squote)) {
        return substr(v, 2, length(v) - 2)
      }
      return v
    }
    function emit_value(v) {
      v = trim(v)
      if (v == "") return
      v = strip_quotes(v)
      if (v != "") print v
    }
    BEGIN { in_fm=0; in_arr=0; squote=sprintf("%c", 39) }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^pre_existing_issues:[[:space:]]*/ {
      rest=$0
      sub(/^pre_existing_issues:[[:space:]]*/, "", rest)
      if (rest ~ /^\[/) exit
      in_arr=1
      next
    }
    in_fm && in_arr && /^[[:space:]]+- / {
      line=$0
      sub(/^[[:space:]]+- /, "", line)
      emit_value(line)
      next
    }
    in_fm && in_arr && /^[^[:space:]]/ { exit }
  ' "$summary_file" 2>/dev/null | while IFS= read -r issue_json; do
    [ -n "$issue_json" ] || continue
    printf '%s' "$issue_json" | jq -er '
      select(type == "object")
      | if .file == .test then
          (.test + ": " + .error)
        else
          (.test + " (" + .file + "): " + .error)
        end
    ' 2>/dev/null || true
  done | awk '
    {
      items = items (items ? "; " : "") $0
    }
    END { print items }
  ' 2>/dev/null)

  # Brownfield fallback: extract pre-existing issues from the legacy body section.
  # Only use this when the canonical frontmatter key is absent. If the key is
  # present as `pre_existing_issues: []`, that explicit empty array is the
  # authoritative "no known issues" signal and must suppress stale body text.
  if [ -z "$preex" ] && [ "$preex_key_present" != true ]; then
    preex=$(awk '
      /^## Pre-existing Issues/ { found=1; next }
      found && /^## / { exit }
      found && /^[[:space:]]*$/ { next }
      found && /^- / { line=$0; sub(/^- /, "", line); items = items (items ? "; " : "") line }
      END { print items }
    ' "$summary_file" 2>/dev/null)
  fi

  if [ -n "$devs" ]; then
    DEV_ISSUES="${DEV_ISSUES}DEVIATIONS (Plan ${plan_id}): ${devs}\n"
  fi
  if [ -n "$preex" ]; then
    DEV_ISSUES="${DEV_ISSUES}PREEXISTING (Plan ${plan_id}): ${preex}\n"
  fi
done
```

If `DEV_ISSUES` is non-empty, include it in the QA task description:
```
Dev-surfaced issues (include in VERIFICATION.md):
${DEV_ISSUES}
DEVIATIONS are plan violations — treat each as a FAIL check.
PREEXISTING items go in the "Pre-existing Issues" section of VERIFICATION.md.
```

**Phase known-issues persistence (before QA):**
After collecting Dev-surfaced pre-existing issues from SUMMARY.md files, persist them to phase state so a later QA session does not forget them:

```bash
bash "${VBW_PLUGIN_ROOT}/scripts/track-known-issues.sh" sync-summaries "{phase-dir}" 2>/dev/null || true
```

This writes `{phase-dir}/known-issues.json`. The human-readable `Discovered Issues` block later in the execute summary is supplemental — the JSON registry is the authoritative phase backlog. Unresolved issues that survive QA and remediation are auto-promoted to `STATE.md ## Todos` via `promote-todos`, making them visible in `/vbw:list-todos` and `/vbw:resume`.

If execution completed but the session ended before QA actually started, standalone/resumed phase-level QA entrypoints must rerun this `sync-summaries` backfill before the first `VERIFICATION.md` is written.

**Tier resolution:** When `validation_gates=true`: use `qa_tier` from gate policy resolved in Step 3.
When `validation_gates=false` (default): map effort to tier: turbo=skip (already handled), fast=quick, balanced=standard, thorough=deep. Override: if >15 requirements or last phase before ship, force Deep.

**Control Plane QA context:** If `${VBW_PLUGIN_ROOT}/scripts/control-plane.sh` exists:
  `bash "${VBW_PLUGIN_ROOT}/scripts/control-plane.sh" compile {phase} 0 0 --role=qa --phase-dir={phase-dir} 2>/dev/null || true`
Otherwise, fall through to direct compile-context.sh call below.

**Context compilation:** If `config_context_compiler=true`, before spawning QA run:
`bash "${VBW_PLUGIN_ROOT}/scripts/compile-context.sh" {phase} qa {phases_dir}`
This produces `{phase-dir}/.context-qa.md` with phase goal, success criteria, requirements to verify, and conventions.
If compilation fails, proceed without it.

Display: `◆ Spawning QA agent (${QA_MODEL})...`

Resolve the VERIFICATION filename before spawning QA:
```bash
VERIF_NAME=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-artifact-path.sh" verification "{phase-dir}")
VERIF_BASE="${VERIF_NAME%.md}"
```

**Per-wave QA (Thorough/Balanced, QA_TIMING=per-wave):** After each wave completes, spawn QA concurrently with next wave's Dev work. QA receives only completed wave's PLAN.md + SUMMARY.md + "Phase context: {phase-dir}/.context-qa.md (if compiled). Model: ${QA_MODEL}. Your verification tier is {tier}. If `.vbw-planning/codebase/META.md` exists, read TESTING.md, CONCERNS.md, and ARCHITECTURE.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before verifying. Run {5-10|15-25|30+} checks per the tier definitions in your agent protocol." Include the output path in the task description so QA persists directly: "Persist your VERIFICATION.md by piping qa_verdict JSON through write-verification.sh. Output path: {phase-dir}/${VERIF_BASE}-wave{W}.md. Plugin root: ${VBW_PLUGIN_ROOT}." After final wave, spawn integration QA covering all plans + cross-plan integration with output path `{phase-dir}/${VERIF_NAME}`. QA calls `write-verification.sh` directly — the orchestrator does NOT persist. If QA reports a `write-verification.sh` failure, surface the error to the user — do NOT fall back to manual VERIFICATION.md writes.

**Post-build QA (Fast, QA_TIMING=post-build):** Spawn QA after ALL plans complete. Include in task description: "Phase context: {phase-dir}/.context-qa.md (if compiled). Model: ${QA_MODEL}. Your verification tier is {tier}. If `.vbw-planning/codebase/META.md` exists, read TESTING.md, CONCERNS.md, and ARCHITECTURE.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before verifying. Run {5-10|15-25|30+} checks per the tier definitions in your agent protocol. Persist your VERIFICATION.md by piping qa_verdict JSON through write-verification.sh. Output path: {phase-dir}/${VERIF_NAME}. Plugin root: ${VBW_PLUGIN_ROOT}." QA calls `write-verification.sh` directly — the orchestrator does NOT persist. If QA reports a `write-verification.sh` failure, surface the error to the user — do NOT fall back to manual VERIFICATION.md writes.

**CRITICAL:** Set `subagent_type: "vbw:vbw-qa"` and `model: "${QA_MODEL}"` in the Task tool invocation when spawning QA agents. If `QA_MAX_TURNS` is non-empty, also pass `maxTurns: ${QA_MAX_TURNS}`. If `QA_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).
**CRITICAL:** When true team mode is active, pass `team_name: "vbw-phase-{NN}"` and `name: "qa"` (or `name: "qa-wave{W}"` for per-wave QA) parameters to each QA Task tool invocation.

### Step 4.1: QA Result Gating (NON-NEGOTIABLE)

After QA writes its VERIFICATION artifact, sync tracked known issues from that artifact before reading the gate:
```bash
bash "${VBW_PLUGIN_ROOT}/scripts/track-known-issues.sh" sync-verification "{phase-dir}" "{verification-output-path}" 2>/dev/null || true
```
After sync, auto-promote surviving known issues to `STATE.md ## Todos`:
```bash
bash "${VBW_PLUGIN_ROOT}/scripts/track-known-issues.sh" promote-todos "{phase-dir}" 2>/dev/null || true
```
- Phase-level VERIFICATION writes merge new pre-existing issues into the existing registry without clearing the execution-time backlog.
- Round-scoped `R{RR}-VERIFICATION.md` writes are authoritative for unresolved known issues and may prune or clear `{phase-dir}/known-issues.json`.

After QA completes (subagent returns or teammate sends `qa_verdict`), run the deterministic gate:
```bash
bash "${VBW_PLUGIN_ROOT}/scripts/qa-result-gate.sh" "{phase-dir}"
```

**Follow `qa_gate_routing` output literally — no exceptions, no judgment, no rationalization. Do NOT evaluate whether failures are justified, acceptable, or minor. The gate script has already made the decision:**
- **`qa_gate_routing=PROCEED_TO_UAT`:** Display `◆ QA: PASS` — proceed to Step 4.5 (UAT)
- **`qa_gate_routing=REMEDIATION_REQUIRED`:** Display `◆ QA: ${qa_gate_result} (${qa_gate_fail_count} FAIL)` — enter QA remediation loop below. If `qa_gate_known_issues_override=true`, the contract verification passed but `{qa_gate_known_issue_count}` unresolved tracked known issues remain in `{phase-dir}/known-issues.json`.
- **`qa_gate_routing=QA_RERUN_REQUIRED`:** Display `⚠ QA result invalid (writer=${qa_gate_writer}, result=${qa_gate_result}). Re-running QA.` — re-spawn QA agent immediately (no plan→execute cycle). Max 2 retries. If `qa_gate_deviation_override=true`, tell QA: "Previous QA run found PASS but SUMMARY.md files contain ${qa_gate_deviation_count} deviations that were not reflected as FAIL checks. Each deviation MUST become a FAIL check — do not rationalize deviations as acceptable." If `qa_gate_plan_coverage` is present, tell QA: "Previous QA run only verified ${qa_gate_plans_verified_count}/${qa_gate_plan_count} plans. Every plan in the phase must be verified — include all plan IDs in plans_verified." If QA still fails to produce a valid result, STOP and escalate: "QA failed to produce a valid VERIFICATION.md after {N} attempts. Manual intervention needed."

**QA Remediation Loop (inline, same session):**

This loop runs inline during execution — no second `/vbw:vibe` call needed. If the session ends mid-loop, phase-detect will detect the `.qa-remediation-stage` state file and route to `needs_qa_remediation` on the next `/vbw:vibe` call.

1. **Init state:**
   ```bash
   bash "${VBW_PLUGIN_ROOT}/scripts/qa-remediation-state.sh" init "{phase-dir}"
   ```
  Parse output: `stage`, `round`, `round_dir`, `source_verification_path`, `source_fail_count`, `known_issues_path`, `known_issues_count`, `input_mode`, `verification_path`
  <qa_remediation_artifact_contract>
  `round_dir`, `source_verification_path`, `known_issues_path`, and `verification_path` from `qa-remediation-state.sh` metadata are authoritative host-repository paths. Claude Code may run subagents from `.claude/worktrees/agent-*` sidechain CWDs; pass these exact paths to Dev and QA prompts and never rewrite them relative to the current CWD. Rewriting those paths relative to sidechain CWDs can write or read remediation artifacts from the wrong location and break resume or verification.
  </qa_remediation_artifact_contract>
  <qa_remediation_spawn_contract>
  QA remediation uses plain sequential subagent calls. Do not use TeamCreate. Do not pass team metadata (`team_name`), per-agent names (`name`), `run_in_background`, or `isolation` unless a future section explicitly prepares VBW worktree targeting for this path.
  </qa_remediation_spawn_contract>
  <qa_remediation_no_tool_circuit_breaker>
  After any QA remediation Dev or QA subagent returns, inspect returned text before artifact validation, deterministic gates, or state advancement. If it says tools, Bash, filesystem, edits, or API-session access are unavailable, treat that as a platform/tool provisioning failure: STOP without advancing `.qa-remediation-stage`, report the failed role and task, and do not retry the same prompt.
  </qa_remediation_no_tool_circuit_breaker>

2. **Loop (until PROCEED_TO_UAT or user intervention):**

   **stage=plan:** Create `R{RR}-PLAN.md` in `{round_dir}`:
  - Read `source_verification_path` from `qa-remediation-state.sh get` metadata for failed checks when `source_fail_count>0`
  - Read `known_issues_path` when `known_issues_count>0` — this is the phase-scoped unresolved known-issues backlog that must clear before UAT
     - Round 01 uses the phase-level VERIFICATION (`{NN}-VERIFICATION.md` or brownfield `VERIFICATION.md`)
     - Round 02+ first checks the previous round's `R{RR}-VERIFICATION.md`. If that artifact still contains FAIL checks, use it. If it passed QA but the deterministic gate still required another remediation round, carry forward the nearest earlier verification artifact in the remediation chain that still contains the unresolved FAILs.
    - If `source_verification_path` is empty and `known_issues_count=0`, STOP and restore the earlier verification artifact that should have carried the unresolved FAILs before planning. Do NOT silently continue when the previous round verification is missing or when the carried-forward phase-level source artifact no longer exists.
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
   - The orchestrator writes the plan (QA identified problems, orchestrator determines fixes)
   - Advance state: `bash "${VBW_PLUGIN_ROOT}/scripts/qa-remediation-state.sh" advance "{phase-dir}"`

   **stage=execute:** Spawn a Dev subagent per `R{RR}-PLAN.md`:
   - **Always subagent — NO team creation for QA remediation (NON-NEGOTIABLE)**
   - Set `subagent_type: "vbw:vbw-dev"` and `model: "${DEV_MODEL}"`
   - Dev fixes code, commits, writes `R{RR}-SUMMARY.md` in `{round_dir}` using `templates/REMEDIATION-SUMMARY.md` (NOT `templates/SUMMARY.md`)
     - The remediation summary frontmatter MUST include aggregated `commit_hashes`, `files_modified`, and `deviations`
     - `files_modified` is required even for documentation-only rounds so `qa-result-gate.sh` can deterministically distinguish metadata-only remediation from real code changes
     - When `input_mode=known-issues` or `input_mode=both`, the remediation summary frontmatter MUST also include `known_issue_outcomes` with one `{test,file,error,disposition,rationale}` JSON object string per carried known issue. Keys and `disposition` values must match `R{RR}-PLAN.md` `known_issue_resolutions`; do not silently drop accepted non-blocking issues.
    - After Dev returns, apply the QA remediation no-tool circuit breaker before checking the summary or advancing state. If Dev reports unavailable tools, Bash, filesystem, edits, or API-session access, STOP without advancing `.qa-remediation-stage` and do not retry that same Dev prompt.
    - After Dev completes without a no-tool provisioning failure, advance state: `bash "${VBW_PLUGIN_ROOT}/scripts/qa-remediation-state.sh" advance "{phase-dir}"`

   **stage=verify:** Re-run QA:
   - Run `compile-verify-context.sh --remediation-only {phase-dir}` to get compounded verification history plus the current round's plan/summary context only
   - Spawn QA agent as subagent — writes to `{verification_path}` (from `qa-remediation-state.sh` metadata)
     - Output path: `{round_dir}/R{RR}-VERIFICATION.md` — phase-level VERIFICATION.md stays frozen
     - After QA returns, apply the QA remediation no-tool circuit breaker before syncing known issues or running the deterministic gate. If QA reports unavailable tools, Bash, filesystem, edits, or API-session access, STOP without advancing `.qa-remediation-stage` and do not retry that same QA prompt.
     - After QA persists `{verification_path}`, immediately sync tracked known issues from that round artifact:
       ```bash
       bash "${VBW_PLUGIN_ROOT}/scripts/track-known-issues.sh" sync-verification "{phase-dir}" "{verification_path}" 2>/dev/null || true
       ```
     - After sync-verification, auto-promote surviving known issues to `STATE.md ## Todos`:
       ```bash
       bash "${VBW_PLUGIN_ROOT}/scripts/track-known-issues.sh" promote-todos "{phase-dir}" 2>/dev/null || true
       ```
    - If `compile-verify-context.sh` emits a `KNOWN ISSUES` block, include in QA's task description: "Tracked phase known issues are not informational in remediation rounds. Re-check every carried known issue from `known_issues_input` / `known_issue_resolutions`. Return only still-blocking issues in `pre_existing_issues`. If a carried issue is verified as an `accepted-process-exception`, omit it from `pre_existing_issues`, confirm that the accepted non-blocking disposition is credible for this phase, and rely on the matching `known_issue_outcomes` entry to preserve visibility after the blocking registry clears. A clean remediation QA run must return an empty `pre_existing_issues` array for all resolved or accepted non-blocking carried issues so `{phase-dir}/known-issues.json` can clear."
     - Include the compiled verify context output in QA's task description
      - **Include in QA task description:** "In addition to verifying the remediation plan's own must_haves, you MUST re-verify each original FAIL from the VERIFICATION HISTORY section. For each FAIL_ID: if classified as code-fix, verify the code now matches the plan; if classified as plan-amendment, verify the original PLAN.md has been updated with the actual approach and rationale; if classified as process-exception, verify the exception is documented with non-fixable justification and that the justification is credible for this FAIL; if code-fix or plan-amendment still appears viable, keep the FAIL open. Any original FAIL that has not been addressed by one of these three paths is still a FAIL."
      - The deterministic gate validates structural evidence only. QA must decide whether a `process-exception` is *actually* justified during this re-verification step — documentation alone is insufficient when the original FAIL still appears fixable via code or plan amendment.
   - After QA returns, run the deterministic gate:
     ```bash
     bash "${VBW_PLUGIN_ROOT}/scripts/qa-result-gate.sh" "{phase-dir}"
     ```
     **Follow `qa_gate_routing` output literally — no exceptions, no judgment, no rationalization. Do NOT evaluate whether failures are justified, acceptable, or minor. The gate script has already made the decision:**
     - **`qa_gate_routing=PROCEED_TO_UAT`:** Advance to done: `bash "${VBW_PLUGIN_ROOT}/scripts/qa-remediation-state.sh" advance "{phase-dir}"`, display `◆ QA remediation: PASS (round {RR})`, break loop, proceed to Step 4.5
    - **`qa_gate_routing=REMEDIATION_REQUIRED`:** Start new round: `bash "${VBW_PLUGIN_ROOT}/scripts/qa-remediation-state.sh" needs-round "{phase-dir}"`, display `◆ QA remediation round {RR}: ${qa_gate_result}`, continue loop. If `qa_gate_known_issues_override=true`, unresolved tracked known issues remain in `{phase-dir}/known-issues.json`.
     - **`qa_gate_routing=QA_RERUN_REQUIRED`:** Re-spawn QA immediately (max 2 retries per round). If `qa_gate_deviation_override=true`, tell QA: "Previous QA run found PASS but SUMMARY.md files contain ${qa_gate_deviation_count} deviations that were not reflected as FAIL checks. Each deviation MUST become a FAIL check — do not rationalize deviations as acceptable." If `qa_gate_plan_coverage` is present, tell QA: "Previous QA run only verified ${qa_gate_plans_verified_count}/${qa_gate_plan_count} plans. Every plan in the phase must be verified — include all plan IDs in plans_verified." If still invalid, treat as REMEDIATION_REQUIRED.
      - **When `qa_gate_metadata_only_override=true`** (routing will be `REMEDIATION_REQUIRED`): Display `⚠ QA remediation round made no implementation changes — only planning/documentation updates. The round still depends on a code-fix path (or omitted fail_classifications), so the original failures cannot be considered resolved without code changes. ${qa_gate_phase_deviation_count} phase deviations remain recorded.` This override is the deterministic safety net for rounds that still depend on code changes. Pure plan-amendment rounds can pass when the original plan was actually updated, and pure process-exception rounds still need planning/remediation-artifact evidence — delivered docs/README changes alone do not count. The next round's `stage=plan` MUST classify each FAIL as code-fix, plan-amendment, or process-exception per the Deviation Classification rules above.
      - **When `qa_gate_process_exception_evidence_missing=true`** (routing will be `REMEDIATION_REQUIRED`): Display `⚠ QA remediation round has a clean verification result, but the gate cannot find recorded remediation-artifact evidence. Record an existing remediation RNN-PLAN.md/RNN-SUMMARY.md or a valid original phase PLAN.md before treating the process-exception as resolved.` Continue with a new remediation round.
      - **When `qa_gate_round_change_evidence_empty=true`** (routing will be `REMEDIATION_REQUIRED`): This flag only fires when the round includes `code-fix` classifications. Display `⚠ QA remediation round recorded no change evidence — both files_modified and commit_hashes were empty. A PASS without any recorded changed files or commits cannot resolve prior FAILs.` The next round must produce real code/plan changes or capture justified remediation evidence instead of an empty summary.
      - **When `qa_gate_round_change_evidence_unavailable=true`** (routing will be `REMEDIATION_REQUIRED`): This flag only fires when the round includes `code-fix` classifications. Pure `plan-amendment` and `process-exception` rounds are validated by their own evidence paths (source-plan coverage and process-exception artifact evidence respectively) rather than by code change evidence. Display `⚠ QA remediation round recorded change evidence that could not be verified as current-round work. Either the recorded files did not match any committed or current round-local remediation-artifact changes after the source verification commit, or the referenced commit_hashes could not be proven to belong to this round, so the actual changed files could not be trusted.` Restore explicit files_modified entries and/or round-local commit evidence anchored to the remediation round before treating the failures as resolved.

### Step 4.5: Human acceptance testing (UAT)

**Autonomy gate:**

| Autonomy | UAT active |
| -------- | ---------- |
| cautious | YES |
| standard | YES |
| confident | OFF |
| pure-vibe | OFF |

**Override:** If `auto_uat` is `true` in config, UAT is always active regardless of autonomy level.

Read autonomy and auto_uat from config:
```bash
AUTONOMY=$(jq -r '.autonomy // "standard"' .vbw-planning/config.json)
AUTO_UAT=$(jq -r '.auto_uat // false' .vbw-planning/config.json)
```

If `AUTO_UAT` is not `true` and autonomy is confident or pure-vibe: display "○ UAT verification skipped (autonomy: {level})" and proceed to Step 5.

**UAT execution:**

Resolve the UAT filename before proceeding:
```bash
UAT_NAME=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-artifact-path.sh" uat "{phase-dir}")
```

1. Check if `{phase-dir}/${UAT_NAME}` already exists with `status: complete`. If so: "○ UAT already complete" and proceed to Step 5.
2. Generate test scenarios from completed SUMMARY.md files:
   - Read each SUMMARY.md: extract what was built, files modified, must_haves
   - Generate 1-3 test scenarios per plan requiring HUMAN judgment — things only a person can verify
   - Minimum 1 test per plan. Test IDs: `P{plan}-T{NN}`

   **UAT tests must require human judgment.** Good examples:
   - Open the app and navigate to screen X — does it display Y correctly?
   - Perform user workflow A → B → C — does the result look right?
   - Check that the UI reflects the change — is the label/value/layout correct?

   **NEVER generate tests that can be performed programmatically.** These belong in QA (Step 4), not UAT:
   - ✗ Grep/search files for expected content or missing imports
   - ✗ Verify file existence, deletion, or structure
   - ✗ Run a test suite or individual test (xcodebuild test, pytest, bats, jest, etc.)
   - ✗ Run a CLI command and check its exit code or output
   - ✗ Execute a script and verify it passes
   - ✗ Run a linter, type-checker, or build command

   **What belongs in UAT (ask the user):**
   - Visual/UI correctness
   - Domain-specific data validation
   - UX flows and usability
   - Behavior that requires the running app or hardware
   - Subjective quality

   **What does NOT belong in UAT (the agent or QA already handles these):**
   - Running test suites — QA runs these during execution. Do NOT ask the user to run tests.
   - Checking command output, exit codes, or build success
   - Grepping files for expected content
   - Verifying file existence or structure
   - Any check that can be performed programmatically via Bash, Grep, or Glob

   **Skill-aware exclusion:** If any active skill, tool, or MCP server gives the model UI automation capabilities (e.g., describe-UI, tap/click simulation, accessibility inspection, screenshot capture, DOM querying), then UI interactions that can be verified programmatically via those capabilities also belong in QA, not UAT. Only include scenarios that require true human judgment — subjective quality, visual design assessment, domain-specific data correctness, or hardware-dependent behavior that available tooling cannot automate.

   If a plan's work is purely internal (refactor, test infrastructure, script changes) with no user-facing behavior, generate a single lightweight checkpoint asking the user to confirm the app still works as expected from their perspective, rather than asking them to run automated checks.

   - Write initial `${UAT_NAME}` in phase dir with all tests (Result fields empty)
3. **CHECKPOINT loop — present ONE test at a time, wait for user response:**

   **This is a conversational loop. Do NOT present all tests at once. Do NOT end the session after presenting a test. Do NOT proceed to Step 5 until all tests are complete.**

   For the FIRST test without a result, display a CHECKPOINT followed by AskUserQuestion:

   ```text
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   CHECKPOINT {NN}/{total} — {plan-id}: {plan-title}
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   {scenario description}
   ```

   Then use AskUserQuestion:

   ```yaml
   question: "Expected: {expected result}"
   header: "UAT"
   multiSelect: false
   options:
     - label: "Pass"
       description: "Behavior matches expected result"
     - label: "Skip"
       description: "Cannot test right now — skip this checkpoint"
   ```

   The tool automatically provides a freeform "Other" option for the user to describe issues.

   **STOP HERE.** Wait for the AskUserQuestion response. Do NOT continue to the next test or to Step 5.

   **After the user responds:**

   Map the AskUserQuestion response:

   - **"Pass" selected:** record pass
   - **"Skip" selected:** record skip
   - **Freeform text (via "Other"):** Apply case-insensitive, trimmed string matching:
     - **Skip words** (skip, skipped, next, n/a, na, later, defer): record skip
     - **Anything else**: treat the entire response text as an issue description, infer severity from keywords (crash/broken/error=critical, wrong/missing/bug=major, minor/cosmetic/nitpick=minor, default=major)
   - Update `${UAT_NAME}` immediately (persist to disk)
   - Display progress: `✓ {completed}/{total} tests`
   - If more tests remain: present the NEXT test using the same CHECKPOINT format with AskUserQuestion, then **STOP and wait again**
   - If all tests done: go to step 4

4. After all tests complete:
   - Update UAT.md frontmatter (status, completed date, final counts)
   - If no issues: proceed to Step 5
   - If issues found: display issue summary, suggest `/vbw:fix`, STOP (do not proceed to Step 5)

**Inline execution (NON-NEGOTIABLE):** The orchestrator runs the CHECKPOINT loop directly in the main conversation — this is NOT a subagent operation. Do NOT spawn a QA agent, Dev agent, or any subagent for UAT. Do NOT use TaskCreate to delegate UAT. The AskUserQuestion tool is only available to the orchestrator — subagents cannot interact with the user, so delegating UAT to a subagent bypasses user input entirely. The orchestrator must wait for user input at each checkpoint.

### Step 5: Update state and present summary

**HARD GATE — Shutdown before ANY output or state updates:** Run team shutdown only when the persisted/helper-resolved runtime state says `delegation_mode=team` and a real `TEAM_NAME` exists. If the helper selected `subagent`, turbo, internal `direct`, no delegate-eligible plans, or team-tooling-unavailable fallback, skip SendMessage/TeamDelete and clear the marker. For actual team mode, shut down the team BEFORE updating state, presenting results, or asking the user anything. This is blocking and non-negotiable:
1. Send `shutdown_request` via SendMessage to EVERY active teammate in `TEAM_NAME` (excluding yourself — the orchestrator controls the sequence, not the lead agent) — do not skip any. The SendMessage JSON body must include at minimum: `{"type": "shutdown_request", "id": "<unique-id>", "reason": "phase_complete", "team_name": "<TEAM_NAME>"}` (this is a simplified form — the full V2 envelope nests these under `payload` with `id` at envelope level, but agents are instructed to match on `"type":"shutdown_request"` regardless of structure). Agents echo the `id` back as `request_id` in their `shutdown_response`. Teammates respond by calling SendMessage with `type: "shutdown_response"`.
2. Log event: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" shutdown_sent {phase} team={team_name} targets={count} 2>/dev/null || true`
3. Wait for each `shutdown_response` with `approved: true` (delivered as a SendMessage tool call from the teammate, NOT as plain text). If a teammate responds in plain text instead of calling SendMessage, re-send the `shutdown_request`. If a teammate rejects, re-request immediately (max 3 attempts per teammate — if still rejected after 3 attempts, log a warning and proceed with TeamDelete).
4. Log event: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" shutdown_received {phase} team={team_name} approved={count} rejected={count} 2>/dev/null || true`
5. Call TeamDelete for `TEAM_NAME`
6. **Post-TeamDelete residual cleanup** (belt-and-suspenders — catches race-condition residuals where agents recreate inbox files after TeamDelete):
   ```bash
   bash "${VBW_PLUGIN_ROOT}/scripts/clean-stale-teams.sh" 2>/dev/null || true
   ```
7. Only THEN proceed to state updates and user-facing output below
Failure to shut down an actual team leaves agents running in the background, consuming API credits (visible as hanging panes in tmux, invisible but still costly without tmux). If no actual team was created: skip shutdown sequence. **Recovery:** If shutdown stalls or agents linger after TeamDelete, do NOT manually `rm -rf ~/.claude/teams` — use `/vbw:doctor --cleanup` which runs `doctor-cleanup.sh` and `clean-stale-teams.sh` with safe atomic cleanup. These scripts detect stale teams, orphan processes, and dangling PIDs. `clean-stale-teams.sh` immediately removes VBW team directories missing `config.json` (orphaned residuals) without waiting for the 2-hour stale threshold.

Regardless of whether a real team was created, clear the execute delegation marker before state updates:
```bash
bash "${VBW_PLUGIN_ROOT}/scripts/delegated-workflow.sh" clear 2>/dev/null || true
```

> **Runtime enforcement limitation:** Claude Code does not expose agent-team message tool calls (e.g., `SendMessage`) to `PreToolUse`/`PostToolUse` hooks with stable `tool_name` values. Therefore VBW cannot hook-validate malformed shutdown responses at runtime. Enforcement relies on: (1) mechanical SendMessage instructions in all 6 agent prompts, (2) compaction-instructions.sh reminders that survive context compaction, (3) orchestrator retry (re-send if teammate responds in plain text), and (4) `/vbw:doctor --cleanup` as a recovery path for stuck teams.

**Worktree merge and cleanup (post-TeamDelete):** If `worktree_isolation` is not `"off"` in config:
For each plan that has a `worktree_path` entry in execution-state.json (completed or failed):
1. **Copy SUMMARY.md** from worktree to phase dir (ensure it is present in the main working tree before merge changes branch context):
   `cp "{worktree_path}/.vbw-planning/phases/{phase-dir}/{plan_id}-SUMMARY.md" ".vbw-planning/phases/{phase-dir}/{plan_id}-SUMMARY.md" 2>/dev/null || true`
2. **Merge worktree branch:**
  `MERGE_RESULT=$(bash "${VBW_PLUGIN_ROOT}/scripts/worktree-merge.sh" {phase} {plan} 2>/dev/null || echo "conflict")`
3. **If `MERGE_RESULT=clean`:**
  - `bash "${VBW_PLUGIN_ROOT}/scripts/worktree-cleanup.sh" {phase} {plan} 2>/dev/null || true`
  - `bash "${VBW_PLUGIN_ROOT}/scripts/worktree-agent-map.sh" clear "dev-{plan}" 2>/dev/null || true`
4. **If `MERGE_RESULT=conflict`:**
   - Log deviation in `{plan_id}-SUMMARY.md`: append "DEVIATION: worktree merge conflict — manual resolution required before cleanup."
   - Display: `⚠ Worktree merge conflict for plan {plan_id}. Resolve conflicts in {worktree_path}, then run: git worktree remove {worktree_path} --force`
   - Skip worktree-cleanup.sh — leave worktree in place for manual resolution.
All worktree operations are fail-open: script errors are suppressed (2>/dev/null || true). Merge failures are surfaced as warnings, not blockers.
When `worktree_isolation="off"`: skip this block silently.

**Post-shutdown verification:** After TeamDelete for an actual `delegation_mode=team` run, there must be ZERO active teammates. If the Pure-Vibe loop or auto-chain will re-enter Plan mode next, confirm no prior agents linger before spawning new ones. For serialized subagent, turbo, direct, or fallback runs, rely on completed subagent/direct execution plus the cleared delegation marker; do not send team shutdown messages without a real `TEAM_NAME`.

**Control Plane cleanup:** Lock and token state cleanup already handled by existing Lease Lock and Token Budget cleanup blocks.

**Rolling Summary (REQ-03):** If `rolling_summary=true` in config:
- After TeamDelete when an actual team was fully shut down, before phase_end event log:
  ```bash
  bash "${VBW_PLUGIN_ROOT}/scripts/compile-rolling-summary.sh" \
    .vbw-planning/phases .vbw-planning/ROLLING-CONTEXT.md 2>/dev/null || true
  ```
  This compiles all completed SUMMARY.md files into a condensed digest for the next phase's agents.
  Fail-open: if script errors, log warning and continue — never block phase completion.
- When `rolling_summary=false` (default): skip this step silently.

**Event Log — phase end (REQ-16, graduated, always-on):**
- `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" phase_end {phase} plans_completed={N} total_tasks={N} 2>/dev/null || true`

**Observability Report (REQ-14):** After phase completion, if `metrics=true`:
- Generate observability report: `bash "${VBW_PLUGIN_ROOT}/scripts/metrics-report.sh" {phase}`
- The report aggregates 7 V2 metrics: task latency, tokens/task, gate failure rate, lease conflicts, resume success, regression escape, fallback %.
- Display summary table in phase completion output.
- Dashboards show by profile (thorough|balanced|fast|turbo) and autonomy (cautious|standard|confident|pure-vibe).

**Mark complete:** Set .execution-state.json `"status"` to `"complete"` (statusline auto-deletes on next refresh).
**Update STATE.md:** phase position, plan completion counts, effort used.
**Update ROADMAP.md:** mark completed plans.

**Advisory state-consistency verification:** After state updates, run:
```bash
VERIFY_SCRIPT="${VBW_PLUGIN_ROOT}/scripts/verify-state-consistency.sh"
if [ -f "$VERIFY_SCRIPT" ]; then
  _vsc_out="$(bash "$VERIFY_SCRIPT" .vbw-planning --mode advisory 2>/dev/null || true)"
  if [ -n "$_vsc_out" ] && echo "$_vsc_out" | jq -e '.verdict == "fail"' >/dev/null 2>&1; then
    echo "VBW state-consistency warning: $(echo "$_vsc_out" | jq -c '.failed_checks')" >&2
  fi
fi
```
If the captured output's `verdict` is `"fail"`, the warning above surfaces the `failed_checks` in the phase completion output. This is non-blocking — the reactive state updater handles most drift, but crashes, compaction, or manual edits can cause silent misalignment that propagates to the next phase. This catch-net surfaces those issues early. If the script is unavailable or errors, continue normally.

**Caveman commit messages (conditional):** If `caveman_commit` is `true` in config, write commit messages using the rules in `references/caveman-commit.md`. The conventional commit format (`type(scope): description`) still applies — caveman language applies to the description text only.

**Planning artifact boundary commit (conditional):**
```bash
PG_SCRIPT="${VBW_PLUGIN_ROOT}/scripts/planning-git.sh"
if [ -f "$PG_SCRIPT" ]; then
  bash "$PG_SCRIPT" commit-boundary "complete phase {NN}" .vbw-planning/config.json
else
  echo "VBW: planning-git.sh unavailable; skipping planning git boundary commit" >&2
fi
```
- `planning_tracking=commit`: commits `.vbw-planning/` + `CLAUDE.md` when changed
- `planning_tracking=manual|ignore`: no-op
- `auto_push=always`: push happens inside the boundary commit command when upstream exists

**After-phase push (conditional):**
```bash
PG_SCRIPT="${VBW_PLUGIN_ROOT}/scripts/planning-git.sh"
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
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Phase {NN}: {name} -- Built
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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
  Registry: {phase-dir}/known-issues.json
```
This display is supplemental to the phase registry. The orchestrator should already have synced these issues into `{phase-dir}/known-issues.json` and auto-promoted surviving entries to `STATE.md ## Todos` via `promote-todos` before rendering this summary. The display block is informational only — do not enter an interactive loop here. If no discovered issues: omit the section entirely. After displaying discovered issues, STOP. Do not take further action.

Run `bash "${VBW_PLUGIN_ROOT}/scripts/suggest-next.sh" execute {qa-result}` and display output.

**STOP.** Execute mode is complete. Return control to the user. Do NOT take further actions — no file edits, no additional commits, no interactive prompts, no improvised follow-up work. The user will decide what to do next based on the summary and suggest-next output.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — Phase Banner (double-line box), ◆ running, ✓ complete, ✗ failed, ○ skipped, Metrics Block, Next Up Block, no ANSI color codes.

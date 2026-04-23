---
name: vbw:debug
category: supporting
disable-model-invocation: true
description: Investigate a bug using the Debugger agent's scientific method protocol.
argument-hint: "bug description | todo number | --resume | --session ID"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch, Agent, TeamCreate, TaskCreate, SendMessage, TeamDelete, Skill, LSP, AskUserQuestion
---

# VBW Debug: $ARGUMENTS

## Context
Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; SESSION_LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ] && [ -f "${SESSION_LINK}/scripts/hook-wrapper.sh" ]; then R="${SESSION_LINK}"; fi; if [ -z "$R" ]; then ANY_LINK=$(command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r link; do if [ -f "$link/scripts/hook-wrapper.sh" ]; then printf '%s\n' "$link"; break; fi; done || true); [ -n "$ANY_LINK" ] && R="$ANY_LINK"; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; LINK="${SESSION_LINK}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$LINK" "$REAL_R" >/dev/null 2>&1 || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```

Recent commits:
```text
!`git log --oneline -10 2>/dev/null || echo "No git history"`
```

Store the plugin root path output above as `{plugin-root}` for use in script invocations below. Replace `{plugin-root}` with the literal `Plugin root` value from Context whenever a step below references a script or reference file.

## Guard
- Not initialized (no .vbw-planning/ dir): STOP "Run /vbw:init first."
- No $ARGUMENTS and no `--resume` flag and no `--session` flag: STOP "Usage: `/vbw:debug \"description of the bug or error message\" [--competing|--parallel|--serial]` | `/vbw:debug <todo-number> [--competing|--parallel|--serial]` | `/vbw:debug --resume` | `/vbw:debug --session <id>`"

## Resolve todo number

If $ARGUMENTS is a bare integer (matches `^[0-9]+$` with no other text or flags), preserve the original numeric-selection marker before rewriting anything. Resolve the todo item against the persisted unfiltered `/vbw:list-todos` snapshot and validate that the live backlog still matches the snapshotted identity:
```bash
bash "{plugin-root}/scripts/resolve-todo-item.sh" <N> --session-snapshot --require-unfiltered --validate-live
```
Parse the JSON output. If `status` is `"ok"`, store the full payload as `TODO_SELECTED_JSON`, preserve `TODO_SELECTED=true`, and replace $ARGUMENTS with the item's `command_text` value. If the resolved `state_path` points under `.vbw-planning/milestones/`, STOP with: `This todo came from archived milestone state. Restore the writable root STATE.md first by restarting so session-start.sh can run migration, or run 'bash scripts/migrate-orphaned-state.sh .vbw-planning'.` Do not continue using the archived description as live work input.

If the selected item has a non-null `ref`, load detail immediately — before session creation:
```bash
bash "{plugin-root}/scripts/todo-details.sh" get {hash}
```
If `status` is `"ok"`, store `DETAIL_STATUS=ok`, store the exact helper stdout as `TODO_DETAIL_RESULT_JSON`, and store `detail.context` plus `detail.files` for later use. If `status` is `"not_found"` or `"error"`, clear `TODO_DETAIL_RESULT_JSON`, record the matching `DETAIL_STATUS` value, and run:
```bash
bash "{plugin-root}/scripts/todo-lifecycle.sh" detail-warning {hash}
```
Continue without detail. If the selected item has no ref, use `DETAIL_STATUS=none` and `TODO_DETAIL_RESULT_JSON=""`.

If `status` is `"error"`, STOP with the resolver's `message` value.

## Debug Session Resolution

<debug_session_routing>
Resolve or create the debug session before any investigation. Order of precedence:

1. **Explicit `--session <id>`:** Extract `SESSION_ID` — the token immediately following `--session` in $ARGUMENTS. If `--session` is present but no id follows it, STOP: `"--session requires a session id."` Resume the named session:
   ```bash
  eval "$(bash "{plugin-root}/scripts/debug-session-state.sh" resume .vbw-planning "$SESSION_ID")"
   ```
   If the session file is missing, STOP with error.

2. **`--resume` flag (no explicit session):** Resume the active session or latest unresolved.
   ```bash
  eval "$(bash "{plugin-root}/scripts/debug-session-state.sh" get-or-latest .vbw-planning)"
   ```
  If `active_session=none`, STOP "No active debug session to resume. Use `/vbw:debug --session <id>` to open a specific session, or start one with `/vbw:debug \"description of the bug or error message\"` or `/vbw:debug <todo-number>`."
  If `active_session=fallback`, inform user which session was auto-selected (no `.active-session` pointer was set, so the latest unresolved session was chosen automatically).
  For metadata-read helper calls (`resume`, `get-or-latest`), use `active_session`, `session_id`, `session_file`, and `session_status` after `eval`. Use `session_status` for lifecycle checks after `eval`; do not rely on a bare `status` variable.

3. **New session (no --resume, no --session):** Create a fresh session from $ARGUMENTS. Strip known flags (`--competing`, `--parallel`, `--serial`) and any `(ref:HASH)` suffix from $ARGUMENTS before computing the slug — these are routing/ref metadata, not part of the bug description.
   ```bash
   BUG_DESC=$(printf '%s' "$ARGUMENTS" | sed -E 's/[[:space:]]*\(ref:[^)]+\)//g' | sed -E 's/(^|[[:space:]])--(competing|parallel|serial)([[:space:]]|$)/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -s '[:space:]' ' ')
   SLUG=$(printf '%s' "$BUG_DESC" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 50)
   if [ "${TODO_SELECTED:-false}" = "true" ]; then
     eval "$(printf '%s' "$TODO_SELECTED_JSON" | TODO_DETAIL_RESULT_JSON="${TODO_DETAIL_RESULT_JSON:-}" bash "{plugin-root}/scripts/debug-session-state.sh" start-with-selected-todo .vbw-planning "$SLUG" "${DETAIL_STATUS:-none}")"
   else
     MANUAL_REF="${REF_HASH:-none}"
     MANUAL_DETAIL_CONTEXT=""
     MANUAL_DETAIL_FILES='[]'
     if [ "${DETAIL_STATUS:-none}" = "ok" ] && [ -n "${TODO_DETAIL_RESULT_JSON:-}" ]; then
       MANUAL_DETAIL_CONTEXT=$(printf '%s' "$TODO_DETAIL_RESULT_JSON" | jq -r '.detail.context // empty' 2>/dev/null || echo "")
       MANUAL_DETAIL_FILES=$(printf '%s' "$TODO_DETAIL_RESULT_JSON" | jq -c '(.detail.files // []) | if type == "array" then . else [] end' 2>/dev/null || printf '[]')
     fi
     eval "$(jq -cn \
       --arg mode "source-todo" \
       --arg text "$BUG_DESC" \
       --arg raw_line "none" \
       --arg ref "$MANUAL_REF" \
       --arg detail_status "${DETAIL_STATUS:-none}" \
       --argjson related_files "$MANUAL_DETAIL_FILES" \
       --arg detail_context "$MANUAL_DETAIL_CONTEXT" \
       '{mode:$mode, text:$text, raw_line:$raw_line, ref:$ref, detail_status:$detail_status, related_files:$related_files, detail_context:$detail_context}' \
       | bash "{plugin-root}/scripts/debug-session-state.sh" start-with-source-todo .vbw-planning "$SLUG")"
   fi
   ```
   The selected-todo helper owns the numbered `/vbw:list-todos` source-todo payload normalization, `## Source Todo` persistence, and rollback on write failure. Keep manual/freeform debug starts on the existing `start-with-source-todo` path.

  Only after the source-todo write succeeds, and only when `TODO_SELECTED=true`, pipe `TODO_SELECTED_JSON` into:
  ```bash
  bash "{plugin-root}/scripts/todo-lifecycle.sh" pickup /vbw:debug {DETAIL_STATUS} {cleanup_policy}
  ```
  Set `{cleanup_policy}` to `safe` when `DETAIL_STATUS=ok`; otherwise set it to `keep`. If the helper returns `status="error"`, STOP with its `message` value. If it returns `status="partial"`, continue but surface its `warning` value with the final result so cleanup state stays explicit. Capture the helper result immediately into explicit presentation variables so post-pickup messaging stays deterministic: `TODO_PICKUP_RESULT_JSON` for the exact helper stdout, `TODO_PICKUP_STATUS=ok|partial`, `TODO_PICKUP_WARNING` from `.warning // empty`, and `TODO_PICKUP_AUTO_NOTE="Selected todo was already picked up automatically."`.

Store the resolved `session_id` and `session_file` for use in Steps below.

If resuming a session with `session_status=qa_pending` or `session_status=fix_applied`: skip investigation, jump directly to `<debug_inline_qa>` below to run QA inline.
If resuming a session with `session_status=qa_failed`: load failure context:
  ```bash
  FAILURE_CONTEXT=$(bash "{plugin-root}/scripts/compile-debug-session-context.sh" "$session_file" qa 2>/dev/null || echo "")
  ```
  Update status to `investigating` via `write-debug-session.sh` (mode=status), then continue investigation from Step 3. When composing the debugger task prompt in Step 4, prepend the compiled `FAILURE_CONTEXT` to the bug report so the debugger has the specific failed QA checks and findings. Use this format in the task prompt: `Previous QA failed. Failure context:\n{FAILURE_CONTEXT}\n\nOriginal bug report: {description}`.
If resuming a session with `session_status=uat_pending`: skip investigation, jump directly to `<debug_inline_uat>` below to run UAT inline.
If resuming a session with `session_status=uat_failed`: load failure context:
  ```bash
  FAILURE_CONTEXT=$(bash "{plugin-root}/scripts/compile-debug-session-context.sh" "$session_file" uat 2>/dev/null || echo "")
  ```
  Update status to `investigating` via `write-debug-session.sh` (mode=status), then continue investigation from Step 3. When composing the debugger task prompt in Step 4, prepend the compiled `FAILURE_CONTEXT` to the bug report so the debugger has the specific failed UAT issues and findings. Use this format in the task prompt: `Previous UAT failed. Failure context:\n{FAILURE_CONTEXT}\n\nOriginal bug report: {description}`.
If resuming a session with `session_status=complete`: STOP "This debug session is already complete. Use `/vbw:debug --session <id>` to inspect another session, or start a new one with `/vbw:debug \"description of the bug or error message\"` or `/vbw:debug <todo-number>`."
</debug_session_routing>

## Steps
1. **Parse + effort:** Strip any known flags (`--competing`, `--parallel`, `--serial`) from $ARGUMENTS and store them separately for Step 2 routing. If `TODO_SELECTED_JSON` already exists from the numeric-selection path above, reuse its `command_text` as the bug description, reuse its `ref`, and reuse the already-loaded `DETAIL_STATUS`, `TODO_DETAIL_RESULT_JSON`, `detail.context`, and `detail.files` values — do not call `todo-details.sh` a second time. Otherwise, if the remaining $ARGUMENTS contains a `(ref:HASH)` suffix (8 hex characters), extract the hash as `REF_HASH` and strip the ref tag. Store remaining text (minus flags and ref) as the bug description. If a ref was found, load extended detail:
   ```bash
   bash "{plugin-root}/scripts/todo-details.sh" get {hash}
   ```
   Parse the JSON output. If `status` is `"ok"`, store `DETAIL_STATUS=ok`, store the exact helper stdout as `TODO_DETAIL_RESULT_JSON`, and store `detail.context` plus `detail.files` for use in Step 4. If `status` is `"not_found"` or `"error"`, clear `TODO_DETAIL_RESULT_JSON`, record the matching `DETAIL_STATUS` value, and run:
   ```bash
   bash "{plugin-root}/scripts/todo-lifecycle.sh" detail-warning {hash}
   ```
   In all cases, continue without detail.
   If no ref suffix, $ARGUMENTS minus flags = bug description, `DETAIL_STATUS=none`, and `TODO_DETAIL_RESULT_JSON=""`.
  **Post-parse validation:** If the bug description is empty or whitespace-only after stripping flags and ref, check whether a ref was found AND its detail loaded successfully (status `"ok"`). If yes, proceed — the detail provides the investigation context. If no ref was found, or the ref detail failed to load, STOP: "Usage: `/vbw:debug \"description of the bug or error message\" [--competing|--parallel|--serial]` | `/vbw:debug <todo-number> [--competing|--parallel|--serial]` | `/vbw:debug --resume` | `/vbw:debug --session <id>`".
   Map effort: thorough=high, balanced/fast=medium, turbo=low.
   Keep effort profile as `EFFORT_PROFILE` (thorough|balanced|fast|turbo).
   Read `{plugin-root}/references/effort-profile-{profile}.md`.

2. **Classify ambiguity:** 2+ signals = ambiguous.
  Keywords: "intermittent/sometimes/random/unclear/inconsistent/flaky/sporadic/nondeterministic",
  multiple root cause areas, generic/missing error, previous reverted fixes in
  git log. Overrides: `--competing`/`--parallel` = always ambiguous;
  `--serial` = never.

3. **Routing decision + delegation marker:** Read prefer_teams config:
   ```bash
   PREFER_TEAMS=$(bash "{plugin-root}/scripts/normalize-prefer-teams.sh" .vbw-planning/config.json 2>/dev/null || echo "auto")
   ```

   Before spawning any agent, activate the delegation guard:
   ```bash
   bash "{plugin-root}/scripts/delegated-workflow.sh" set debug "$EFFORT_PROFILE"
   ```

   Decision tree:

   - `prefer_teams='always'`: Use Path A (team) for ALL bugs, regardless of effort or ambiguity
   - `prefer_teams='auto'`: Use Path A (team) only if effort=high AND ambiguous, else Path B
   - `prefer_teams='never'`: Always use Path B (single debugger, no team). Overrides effort and ambiguity.

4. **Spawn investigation:**
  Before any debugger or team is spawned, capture the current HEAD exactly once:
  ```bash
  HEAD_BEFORE=$(git rev-parse HEAD 2>/dev/null || echo "")
  ```
  Treat `HEAD_BEFORE` as the pre-investigation baseline for Step 5. Do not use commit presence alone to infer whether this investigation created a new fix.

  **Path A: Competing Hypotheses** (prefer_teams='always' OR (prefer_teams!='never' AND effort=high AND ambiguous)):
    - Generate 3 hypotheses (cause, codebase area, confirming evidence)
    - Resolve Debugger model:
        ```bash
        if ! AGENT_SETTINGS=$(bash "{plugin-root}/scripts/resolve-agent-settings.sh" debugger .vbw-planning/config.json "{plugin-root}/config/model-profiles.json" "$EFFORT_PROFILE"); then
          echo "$AGENT_SETTINGS" >&2
          exit 1
        fi
        eval "$AGENT_SETTINGS"
        DEBUGGER_MODEL="$RESOLVED_MODEL"
        DEBUGGER_MAX_TURNS="$RESOLVED_MAX_TURNS"
        ```
    - Display: `◆ Spawning Debugger (${DEBUGGER_MODEL})...`
    - **Pre-TeamCreate cleanup:** `bash "{plugin-root}/scripts/clean-stale-teams.sh" 2>/dev/null || true`
    - Create team via TeamCreate: `team_name="vbw-debug-{timestamp}"`, `description="Debug: {one-line-bug-summary}"`
    - Before composing task descriptions, evaluate installed skills visible in your system context — read each skill's description and select all materially helpful installed skills for this bug investigation, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context — not just the single most direct skill. Each Debugger task prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected — {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills.
    - Also evaluate available MCP tools in your system context. If any MCP servers provide debugging, build, test, documentation, or domain-specific capabilities relevant to this investigation, note them in each Debugger's task context so it can use those tools during investigation.
    - **Discover research context** (optional, from prior `/vbw:research`):
        ```bash
        RESEARCH_CONTEXT=$(bash "{plugin-root}/scripts/compile-research-context.sh" .vbw-planning "{bug description from Step 1}" 2>/dev/null || echo "")
        ```
        Replace `{bug description from Step 1}` with the actual parsed bug description. If `RESEARCH_CONTEXT` is non-empty, include it in each Debugger task prompt below. If empty, omit the `<standalone_research_context>` block entirely.
    - Create 3 tasks via TaskCreate, each with: bug report, standalone research context (include ONLY if RESEARCH_CONTEXT was non-empty: `<standalone_research_context>Prior research findings from /vbw:research. Advisory — verify all claims against the current codebase before relying on them.\n{RESEARCH_CONTEXT}</standalone_research_context>`), extended context from todo detail if loaded in Step 1 (include `detail.context` and `detail.files` — omit this section entirely if no detail was loaded), ONE hypothesis only (no cross-contamination), working dir, codebase bootstrap instruction ("If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md, CONCERNS.md, PATTERNS.md, and DEPENDENCIES.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before investigating"), instruction to report via `debugger_report` schema (see `{plugin-root}/references/handoff-schemas.md`) including explicit `resolution_observation=already_fixed|needs_change|inconclusive`, instruction that `resolution_observation` is analysis-scoped only (teammates do not own the final command outcome or session status), instruction: "If investigation reveals pre-existing failures unrelated to this bug, list them in your response under a 'Pre-existing Issues' heading with test name, file, and failure message." **Include `[analysis-only]` in each task subject** (e.g., "Hypothesis 1: race condition in sync handler [analysis-only]") so the TaskCompleted hook skips the commit-verification gate for report-only tasks.
    - Spawn 3 vbw-debugger teammates, one task each. **Set `subagent_type: "vbw:vbw-debugger"` and `model: "${DEBUGGER_MODEL}"` on each Task spawn. If `DEBUGGER_MAX_TURNS` is non-empty, also pass `maxTurns: ${DEBUGGER_MAX_TURNS}`. If `DEBUGGER_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).**
    - Wait for completion. Synthesize: strongest evidence + highest confidence wins. Multiple confirmed = contributing factors. After synthesis, choose one authoritative `RESOLUTION_OBSERVATION` value for the command from the teammate reports: `already_fixed` when the current branch already contains the fix and no new change is needed, `needs_change` when code changes were required or would still be required, `inconclusive` when the evidence is not yet strong enough.
    - Collect pre-existing issues from all debugger responses. De-duplicate by test name and file (keep first error message when the same test+file pair has different messages) — if multiple debuggers report the same pre-existing failure, include it only once.
    - Winning hypothesis with fix: apply + commit `fix({scope}): {description}`
    - **HARD GATE — Shutdown before presenting results:** Send `shutdown_request` to each teammate, wait for `shutdown_response` (approved=true) delivered via SendMessage tool call (NOT plain text). If a teammate responds in plain text instead of calling SendMessage, re-send the `shutdown_request`. If rejected, re-request (max 3 attempts per teammate — then proceed). Call TeamDelete. **Post-TeamDelete residual cleanup:** `bash "{plugin-root}/scripts/clean-stale-teams.sh" 2>/dev/null || true`. Verify: after TeamDelete, there must be ZERO active teammates. If teardown stalls, advise the user to run `/vbw:doctor --cleanup`. Only THEN present results to user. Failure to shut down leaves agents running and consuming API credits.

    **Path B: Standard** (all other cases):
    - Resolve Debugger model:
        ```bash
        if ! AGENT_SETTINGS=$(bash "{plugin-root}/scripts/resolve-agent-settings.sh" debugger .vbw-planning/config.json "{plugin-root}/config/model-profiles.json" "$EFFORT_PROFILE"); then
          echo "$AGENT_SETTINGS" >&2
          exit 1
        fi
        eval "$AGENT_SETTINGS"
        DEBUGGER_MODEL="$RESOLVED_MODEL"
        DEBUGGER_MAX_TURNS="$RESOLVED_MAX_TURNS"
        ```
    - Display: `◆ Spawning Debugger (${DEBUGGER_MODEL})...`
    - Before composing the Debugger task description, evaluate installed skills visible in your system context — read each skill's description and select all materially helpful installed skills for this bug investigation, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context — not just the single most direct skill. The Debugger prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected — {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills.
    - Also evaluate available MCP tools in your system context. If any MCP servers provide debugging, build, test, documentation, or domain-specific capabilities relevant to this investigation, note them in the Debugger's task context so it can use those tools during investigation.
    - **Discover research context** (optional, from prior `/vbw:research`):
        ```bash
        RESEARCH_CONTEXT=$(bash "{plugin-root}/scripts/compile-research-context.sh" .vbw-planning "{bug description from Step 1}" 2>/dev/null || echo "")
        ```
        Replace `{bug description from Step 1}` with the actual parsed bug description. If `RESEARCH_CONTEXT` is non-empty, include it in the Debugger task prompt below. If empty, omit the `<standalone_research_context>` block entirely — the debug workflow proceeds as today.
    - Spawn vbw-debugger as subagent via Task tool. **Set `subagent_type: "vbw:vbw-debugger"` and `model: "${DEBUGGER_MODEL}"` in the Task tool invocation. If `DEBUGGER_MAX_TURNS` is non-empty, also pass `maxTurns: ${DEBUGGER_MAX_TURNS}`. If `DEBUGGER_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).**
        ```text
        Bug investigation. Effort: {DEBUGGER_EFFORT}.
        Standalone research context (include ONLY if RESEARCH_CONTEXT was non-empty — omit this entire block otherwise):
        <standalone_research_context>
        Prior research findings from /vbw:research. Advisory — verify all claims against the current codebase before relying on them.
        {RESEARCH_CONTEXT}
        </standalone_research_context>
        Bug report: {description}.
        Extended context from todo detail (include only if detail was loaded in Step 1): {detail.context}. Related files: {detail.files, comma-separated}.
        Working directory: {pwd}.
        If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md, CONCERNS.md, PATTERNS.md, and DEPENDENCIES.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before investigating.
        Follow protocol: bootstrap (if codebase mapping exists), reproduce, hypothesize, gather evidence, diagnose, fix, verify, document.
        Return a final report that includes an explicit `resolution_observation` field with exactly one of `already_fixed`, `needs_change`, or `inconclusive`. This field is analysis-scoped: use `already_fixed` only when the current branch already contains the fix and no new code change is needed; use `needs_change` when additional code changes were required or would still be required; use `inconclusive` when diagnosis is incomplete.
        If you apply a fix, commit with: fix({scope}): {description}.
        If investigation reveals pre-existing failures unrelated to this bug, list them in your response under a "Pre-existing Issues" heading with test name, file, and failure message.
        ```

5. **Persist to debug session + Clear delegation marker + Present:**

   <debug_session_persistence>
   After investigation completes (Path A or Path B), capture the post-investigation HEAD before classifying the outcome:

   ```bash
   HEAD_AFTER=$(git rev-parse HEAD 2>/dev/null || echo "")
   ```

   Resolve one authoritative analysis-scoped `RESOLUTION_OBSERVATION` before persisting anything. For Path A, use the synthesized `debugger_report.payload.resolution_observation` chosen from teammate evidence. For Path B, read the single debugger's explicit `resolution_observation` field from its final report. Normalize it to exactly one of `already_fixed`, `needs_change`, or `inconclusive`. Do **not** infer `already_fixed` from free-text phrasing or from commit presence alone.

   Then compute the command-local three-way outcome: new commit created now (`HEAD_BEFORE` != `HEAD_AFTER`) → `INVESTIGATION_OUTCOME=fixed_now`; no new commit now + `RESOLUTION_OBSERVATION=already_fixed` → `INVESTIGATION_OUTCOME=already_fixed`; no new commit now + `RESOLUTION_OBSERVATION=needs_change|inconclusive` → `INVESTIGATION_OUTCOME=no_fix_yet`.

   Persist branch-specific investigation wording — do not collapse `already_fixed` and `no_fix_yet` into the same `"No fix applied"` text.

   Build the investigation JSON payload:
   ```bash
   INVESTIGATION_JSON=$(cat <<'ENDJSON'
   {
     "mode": "investigation",
     "title": "{one-line bug summary}",
     "issue": "{bug description from user}",
     "hypotheses": [
       {
         "description": "{hypothesis description}",
         "status": "confirmed|rejected",
         "evidence_for": "{supporting evidence}",
         "evidence_against": "{contradicting evidence}",
         "conclusion": "{why chosen or rejected}"
       }
     ],
     "root_cause": "{confirmed root cause with file references}",
     "plan": "{chosen fix approach}",
     "implementation": "{summary of changes, or branch-specific text: fixed_now = changes applied now; already_fixed = no new changes were required because the current branch already contained the fix; no_fix_yet = investigation completed without applying a new fix in this run}",
     "changed_files": ["{file1}", "{file2}"],
     "commit": "{fixed_now = commit hash and message; already_fixed = 'Already fixed before this investigation — no new commit created.'; no_fix_yet = 'No new commit created during this investigation.'}"
   }
   ENDJSON
   )
   echo "$INVESTIGATION_JSON" | bash "{plugin-root}/scripts/write-debug-session.sh" "$session_file"
   ```

   Then update session state from `INVESTIGATION_OUTCOME`. For `fixed_now`, set status to `qa_pending`:
   ```bash
   bash "{plugin-root}/scripts/debug-session-state.sh" set-status .vbw-planning qa_pending
   ```
   For `already_fixed`, mark the investigation complete using the existing completed-session workflow:
   ```bash
   bash "{plugin-root}/scripts/debug-session-state.sh" set-status .vbw-planning complete
   ```
   For `no_fix_yet`, do **not** set `fix_applied`; keep the session status as `investigating`.
   </debug_session_persistence>

   Always clear the marker, regardless of outcome:
   ```bash
   bash "{plugin-root}/scripts/delegated-workflow.sh" clear
   ```
   Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
   ```text
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Bug Investigation Complete
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

     Mode:       {Path A: "Competing Hypotheses (3 parallel)" + hypothesis outcomes | Path B: "Standard (single debugger)"}
     Issue:      {one-line summary}
     Root Cause: {from report}
     Outcome:    {fixed_now | already_fixed | no_fix_yet}
     Resolution: {fixed_now = "Applied now in {commit hash + message}" | already_fixed = "Already fixed on the current branch — no new commit created" | no_fix_yet = "No new commit created — further implementation still required"}

     Files Modified: {list}
   ```

  If `TODO_SELECTED=true` and pickup ran, any numbered list captured before pickup is stale because `STATE.md` has already changed. Use the stored `TODO_PICKUP_STATUS`, `TODO_PICKUP_WARNING`, and `TODO_PICKUP_AUTO_NOTE` values instead of inventing fresh numbered cleanup advice. Never tell the user to `remove N` for the selected todo; `/vbw:debug` already picked it up automatically. Never cite a remaining todo number unless you first refresh through the existing snapshot/resolver flow. Default low-token UX: unnumbered prose only — emit `TODO_PICKUP_AUTO_NOTE` verbatim and, when related backlog items may still exist, say `Rerun /vbw:list-todos for fresh numbering.` If `TODO_PICKUP_STATUS=partial` and `TODO_PICKUP_WARNING` is non-empty, surface that warning explicitly.

**Discovered Issues:** If the Debugger reported pre-existing failures, out-of-scope bugs, or issues unrelated to the investigated bug, append after the result box. Cap the list at 20 entries; if more exist, show the first 20 and append `... and {N} more`:
```text
  Discovered Issues:
    ⚠ testName (path/to/file): error message
    ⚠ testName (path/to/file): error message
  Suggest: /vbw:todo <description> to track
```
This is **display-only**. Do NOT edit STATE.md, do NOT add todos, do NOT invoke /vbw:todo, and do NOT enter an interactive loop. The user decides whether to track these. If no discovered issues: omit the section entirely.

If `INVESTIGATION_OUTCOME=no_fix_yet` (session status is still `investigating`): STOP with `➜ Next: /vbw:debug --resume -- Continue investigation and apply fix`. Do not enter inline QA.

If `INVESTIGATION_OUTCOME=already_fixed`: STOP with `➜ Debug session complete. Investigation confirmed the fix was already present.` Do not enter inline QA.

If `INVESTIGATION_OUTCOME=fixed_now` and session status is `qa_pending`: proceed to `<debug_inline_qa>` below (even if discovered issues were displayed above — they are informational only and do not gate the QA lifecycle).

<debug_inline_qa>
**Inline QA — runs automatically after a fix is committed.**

Read the `auto_uat` config:
```bash
AUTO_UAT=$(jq -r '.auto_uat // "false"' .vbw-planning/config.json 2>/dev/null || echo "false")
```

Resolve effort profile if not already set (needed for tier resolution and max-turns):
```bash
if [ -z "${EFFORT_PROFILE:-}" ]; then
  EFFORT_PROFILE=$(jq -r '.effort // "balanced"' .vbw-planning/config.json 2>/dev/null || echo "balanced")
fi
```

**QA orchestration (absorbed from /vbw:qa debug-session mode):**

1. Compile QA context:
  ```bash
  QA_CONTEXT=$(bash "{plugin-root}/scripts/compile-debug-session-context.sh" "$session_file" qa)
  ```

1. Resolve tier from effort profile: fast=quick, balanced=standard, thorough=deep. Store as `ACTIVE_TIER`. If turbo:
  ```bash
  bash "{plugin-root}/scripts/debug-session-state.sh" set-status .vbw-planning uat_pending
  ```
   Then jump directly to `<debug_inline_uat>` below — skip all remaining QA steps (do not increment QA round).

1. Increment QA round:
  ```bash
  eval "$(bash "{plugin-root}/scripts/debug-session-state.sh" increment-qa .vbw-planning)"
  ```

1. Resolve QA model and max turns:
  ```bash
  if ! AGENT_SETTINGS=$(bash "{plugin-root}/scripts/resolve-agent-settings.sh" qa .vbw-planning/config.json "{plugin-root}/config/model-profiles.json" "$EFFORT_PROFILE"); then
    echo "$AGENT_SETTINGS" >&2
    exit 1
  fi
  eval "$AGENT_SETTINGS"
  QA_MODEL="$RESOLVED_MODEL"
  QA_MAX_TURNS="$RESOLVED_MAX_TURNS"
  ```

1. Spawn vbw-qa as subagent via Task tool for debug-session verification. **Set `subagent_type: "vbw:vbw-qa"` and `model: "${QA_MODEL}"` in the Task tool invocation. If `QA_MAX_TURNS` is non-empty, also pass `maxTurns: ${QA_MAX_TURNS}`.**

    Before composing the QA task description, evaluate installed skills visible in your system context — read each skill's description and select all materially helpful installed skills for this verification pass, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context — not just the single most direct skill. The QA prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected — {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills.

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

2. Process the QA result:
   Parse the verdict (PASS/FAIL/PARTIAL) from the QA agent's response.

   Write the QA round to the session file:
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
   echo "$QA_RESULT_JSON" | bash "{plugin-root}/scripts/write-debug-session.sh" "$session_file"
   ```

   Update session status based on result:
   - PASS → `bash .../debug-session-state.sh set-status .vbw-planning uat_pending`
   - FAIL or PARTIAL → `bash .../debug-session-state.sh set-status .vbw-planning qa_failed`

3. Present debug-session QA result:
   Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
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

**QA failure handling:** If FAIL or PARTIAL:
- Display: `QA found issues. Re-investigating...`
- Load failure context: `FAILURE_CONTEXT=$(bash .../compile-debug-session-context.sh "$session_file" qa 2>/dev/null || echo "")`
- Update status to `investigating` via `write-debug-session.sh` (mode=status)
- Re-enter investigation from Step 3 with the failure context prepended to the bug report (same pattern as `--resume` from `qa_failed`). After the next fix commit, inline QA fires again automatically.

**QA pass:** If PASS, proceed to `<debug_inline_uat>` below.
</debug_inline_qa>

<debug_inline_uat>
**Inline UAT — prompt-gated by default (`auto_uat`); runs automatically when `auto_uat=true`.**

Resolve `AUTO_UAT` if not already set (needed when entering via `--resume` from `uat_pending`):
```bash
if [ -z "${AUTO_UAT:-}" ]; then
  AUTO_UAT=$(jq -r '.auto_uat // "false"' .vbw-planning/config.json 2>/dev/null || echo "false")
fi
```

**Prompt gate:** If `AUTO_UAT` is not `"true"`, call AskUserQuestion:
```yaml
question: "QA passed. Run UAT verification now?"
header: "Debug Session"
multiSelect: false
options:
  - label: "Yes"
    description: "Run UAT checkpoints inline"
  - label: "No"
    description: "Skip — I'll resume later with /vbw:debug --resume"
```
**AskUserQuestion is a tool call (NON-NEGOTIABLE):** You MUST invoke AskUserQuestion via the tool_use mechanism — never emit the question parameters as text, YAML, or any other inline format in your response body. If AskUserQuestion appears in your text output instead of as a tool call, the prompt will not be presented to the user and the session will end prematurely. **STOP HERE.** Wait for the AskUserQuestion response before processing the answer.

If the user selects "No": STOP with `➜ Next: /vbw:debug --resume -- Continue to UAT verification`.
If the user selects "Yes": proceed.
If the user provides freeform input: proceed only when the response is clearly affirmative (e.g., "yes", "y", "sure", "go ahead"). If the response is negative or deferring (e.g., "no", "not now", "later", "skip"): treat as "No" and STOP. If ambiguous: ask a brief follow-up to confirm before proceeding.

If `AUTO_UAT` is `"true"`: skip the prompt and proceed directly.

**UAT orchestration (absorbed from /vbw:verify debug-session mode):**

1. Compile UAT context:
  ```bash
  UAT_CONTEXT=$(bash "{plugin-root}/scripts/compile-debug-session-context.sh" "$session_file" uat)
  ```

1. Increment UAT round:
  ```bash
  eval "$(bash "{plugin-root}/scripts/debug-session-state.sh" increment-uat .vbw-planning)"
  ```

1. Generate 1-3 UAT checkpoints from the session context. These must require HUMAN judgment:
   - Reproduce the original bug — is it fixed?
   - Check related workflows — any regressions visible?
   - Verify the fix from the user's perspective

   **Guardrails:** Never ask the user to run automated checks (tests, lint, build commands) — those belong in QA. If the fix is purely internal (test-infra, script-only, non-user-facing), fall back to a single lightweight checkpoint: "Does the app still work as expected from your perspective?" rather than generating inapplicable user-facing scenarios.

2. Present checkpoints one at a time using CHECKPOINT + AskUserQuestion:

   Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
   ```text
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     CHECKPOINT {NN}/{total} — Debug Fix Verification
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   {scenario description}
   ```

   Then call AskUserQuestion:
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

   **AskUserQuestion is a tool call (NON-NEGOTIABLE):** You MUST invoke AskUserQuestion via the tool_use mechanism — never emit the question parameters as text, YAML, or any other inline format in your response body. If AskUserQuestion appears in your text output instead of as a tool call, the checkpoint will not be presented to the user and the session will end prematurely. **STOP HERE and wait for the user to respond.** Process one checkpoint at a time.

3. Response mapping (same rules as /vbw:verify; AskUserQuestion automatically provides a freeform "Other" option):
   - "Pass" → record as passed
   - "Skip" → record as skipped
   - Freeform text via "Other" → treat as issue description, infer severity from keywords (crash/broken/error=critical, wrong/missing/bug=major, minor/cosmetic=minor, default=major)

4. After all checkpoints, persist the UAT round:
   ```bash
   UAT_RESULT_JSON=$(cat <<'ENDJSON'
   {
     "mode": "uat",
     "round": {uat_round},
     "result": "{pass|issues_found}",
     "checkpoints": [
       {"id": "{id}", "description": "{desc}", "result": "pass|skip|issue", "user_response": "{verbatim}"}
     ],
     "issues": [
       {"id": "{id}", "description": "{desc}", "severity": "{level}"}
     ]
   }
   ENDJSON
   )
   echo "$UAT_RESULT_JSON" | bash "{plugin-root}/scripts/write-debug-session.sh" "$session_file"
   ```

5. Update session status:
   - All checkpoints pass (no issues) → `bash .../debug-session-state.sh set-status .vbw-planning complete`
   - Any issues found → `bash .../debug-session-state.sh set-status .vbw-planning uat_failed`

6. Present debug-session UAT result:
   Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
   ```text
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Debug UAT: Round {uat_round}
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

     Session:  {session_id}
     Result:   {✓ COMPLETE | ✗ ISSUES FOUND}
     Passed:   {N}
     Issues:   {N}

   ```

**UAT failure handling:** If issues found:
- Display: `UAT found issues. Re-investigating...`
- Load failure context: `FAILURE_CONTEXT=$(bash .../compile-debug-session-context.sh "$session_file" uat 2>/dev/null || echo "")`
- Update status to `investigating` via `write-debug-session.sh` (mode=status)
- Re-enter investigation from Step 3 with the failure context prepended (same pattern as `--resume` from `uat_failed`). After the next fix commit, the inline QA → UAT chain fires again automatically.

**UAT pass:** If all checkpoints pass:
- Move session to completed: the `complete` status set above handles this.
- Display: `➜ Debug session complete. The fix is verified.`
- STOP.
</debug_inline_uat>

<debug_session_next_step>
Session-aware next step (only shown when the inline flow did not run):

- If investigation completed but no fix was applied (session status is `investigating`):
  `➜ Next: /vbw:debug --resume -- Continue investigation and apply fix`
- If session was not created (error or guard stopped execution):
  `➜ Next: /vbw:status -- View project status`
</debug_session_next_step>
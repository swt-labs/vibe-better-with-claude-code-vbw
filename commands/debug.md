---
name: vbw:debug
category: supporting
disable-model-invocation: true
description: Investigate a bug using the Debugger agent's scientific method protocol.
argument-hint: "<bug description or error message>"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch, Agent, TeamCreate, TaskCreate, SendMessage, TeamDelete, Skill, LSP
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

Store the plugin root path output above as `VBW_PLUGIN_ROOT` for use in script invocations below.

## Guard
- Not initialized (no .vbw-planning/ dir): STOP "Run /vbw:init first."
- No $ARGUMENTS and no `--resume` flag and no `--session` flag: STOP "Usage: /vbw:debug \"description of the bug or error message\""

## Debug Session Resolution

<debug_session_routing>
Resolve or create the debug session before any investigation. Order of precedence:

1. **Explicit `--session <id>`:** Resume the named session.
   ```bash
   eval "$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/debug-session-state.sh resume .vbw-planning "$SESSION_ID")"
   ```
   If the session file is missing, STOP with error.

2. **`--resume` flag (no explicit session):** Resume the active session or latest unresolved.
   ```bash
   eval "$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/debug-session-state.sh get-or-latest .vbw-planning)"
   ```
   - If `active_session=none`: STOP "No active debug session to resume. Start one with: /vbw:debug \"bug description\""
   - If `active_session=fallback`: inform user which session was auto-selected (no `.active-session` pointer was set, so the latest unresolved session was chosen automatically).

3. **New session (no --resume, no --session):** Create a fresh session from $ARGUMENTS.
   ```bash
   SLUG=$(printf '%s' "$ARGUMENTS" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 50)
   eval "$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/debug-session-state.sh start .vbw-planning "$SLUG")"
   ```

Store the resolved `session_id` and `session_file` for use in Steps below.

If resuming a session with `status=qa_pending`: skip investigation, display current session state, and suggest `/vbw:qa --session` instead.
If resuming a session with `status=qa_failed`: load failure context:
  ```bash
  FAILURE_CONTEXT=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/compile-debug-session-context.sh "$session_file" qa 2>/dev/null || echo "")
  ```
  Update status to `investigating` via `write-debug-session.sh` (mode=status), then continue investigation from Step 3. When composing the debugger task prompt in Step 4, prepend the compiled `FAILURE_CONTEXT` to the bug report so the debugger has the specific failed QA checks and findings. Use this format in the task prompt: `Previous QA failed. Failure context:\n{FAILURE_CONTEXT}\n\nOriginal bug report: {description}`.
If resuming a session with `status=uat_pending`: skip investigation, display current session state, and suggest `/vbw:verify --session` instead.
If resuming a session with `status=uat_failed`: load failure context:
  ```bash
  FAILURE_CONTEXT=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/compile-debug-session-context.sh "$session_file" uat 2>/dev/null || echo "")
  ```
  Update status to `investigating` via `write-debug-session.sh` (mode=status), then continue investigation from Step 3. When composing the debugger task prompt in Step 4, prepend the compiled `FAILURE_CONTEXT` to the bug report so the debugger has the specific failed UAT issues and findings. Use this format in the task prompt: `Previous UAT failed. Failure context:\n{FAILURE_CONTEXT}\n\nOriginal bug report: {description}`.
If resuming a session with `status=complete`: STOP "This debug session is already complete. Start a new one with: /vbw:debug \"bug description\""
</debug_session_routing>

## Steps
1. **Parse + effort:** Strip any known flags (`--competing`, `--parallel`, `--serial`) from $ARGUMENTS and store them separately for Step 2 routing. If the remaining $ARGUMENTS contains a `(ref:HASH)` suffix (8 hex characters), extract the hash and strip the ref tag. Store remaining text (minus flags and ref) as the bug description. If a ref was found, load extended detail:
    ```bash
    bash "`!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/todo-details.sh" get <hash>
    ```
    Parse the JSON output. If `status` is `"ok"`, store `detail.context` and `detail.files` for use in Step 4. If `status` is `"not_found"` or `"error"`, and `.vbw-planning/STATE.md` exists, append `- {YYYY-MM-DD}: Detail for ref HASH could not be loaded` under the `## Activity Log` section (or the first heading beginning with `## Activity`) in `.vbw-planning/STATE.md`; if that file does not exist, skip logging. In all cases, continue without detail.
    If no ref suffix, $ARGUMENTS minus flags = bug description.
    **Post-parse validation:** If the bug description is empty or whitespace-only after stripping flags and ref, check whether a ref was found AND its detail loaded successfully (status `"ok"`). If yes, proceed — the detail provides the investigation context. If no ref was found, or the ref detail failed to load, STOP: `"Usage: /vbw:debug \"description of the bug or error message\" [--competing|--parallel|--serial]"`.
    Map effort: thorough=high, balanced/fast=medium, turbo=low.
    Keep effort profile as `EFFORT_PROFILE` (thorough|balanced|fast|turbo).
    Read ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/effort-profile-{profile}.md`.

2. **Classify ambiguity:** 2+ signals = ambiguous.
  Keywords: "intermittent/sometimes/random/unclear/inconsistent/flaky/sporadic/nondeterministic",
  multiple root cause areas, generic/missing error, previous reverted fixes in
  git log. Overrides: `--competing`/`--parallel` = always ambiguous;
  `--serial` = never.

3. **Routing decision + delegation marker:** Read prefer_teams config:
    ```bash
  PREFER_TEAMS=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/normalize-prefer-teams.sh .vbw-planning/config.json 2>/dev/null || echo "auto")
    ```

    Before spawning any agent, activate the delegation guard:
    ```bash
    bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/delegated-workflow.sh set debug "$EFFORT_PROFILE"
    ```

    Decision tree:

    - `prefer_teams='always'`: Use Path A (team) for ALL bugs, regardless of effort or ambiguity
    - `prefer_teams='auto'`: Use Path A (team) only if effort=high AND ambiguous, else Path B
    - `prefer_teams='never'`: Always use Path B (single debugger, no team). Overrides effort and ambiguity.

4. **Spawn investigation:**
    **Path A: Competing Hypotheses** (prefer_teams='always' OR (prefer_teams!='never' AND effort=high AND ambiguous)):
    - Generate 3 hypotheses (cause, codebase area, confirming evidence)
    - Resolve Debugger model:
        ```bash
        DEBUGGER_MODEL=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh debugger .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
        if [ $? -ne 0 ]; then echo "$DEBUGGER_MODEL" >&2; exit 1; fi
        DEBUGGER_MAX_TURNS=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-max-turns.sh debugger .vbw-planning/config.json "$EFFORT_PROFILE")
        if [ $? -ne 0 ]; then echo "$DEBUGGER_MAX_TURNS" >&2; exit 1; fi
        ```
    - Display: `◆ Spawning Debugger (${DEBUGGER_MODEL})...`
    - **Pre-TeamCreate cleanup:** `bash "${VBW_PLUGIN_ROOT}/scripts/clean-stale-teams.sh" 2>/dev/null || true`
    - Create team via TeamCreate: `team_name="vbw-debug-{timestamp}"`, `description="Debug: {one-line-bug-summary}"`
    - Before composing task descriptions, evaluate installed skills visible in your system context — read each skill's description and determine if it is relevant to this bug investigation. Each Debugger task prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each relevant skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills apply, or `<skill_no_activation>Evaluated installed skills for this task. No installed skills apply. Reason: {brief task-specific reason}.</skill_no_activation>` when none apply. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none apply — {reason}") so the user has visibility before the agent is spawned. Only include skills whose description matches the investigation at hand (e.g., debugging skills, platform-specific skills for the affected stack).
    - Also evaluate available MCP tools in your system context. If any MCP servers provide debugging, build, test, documentation, or domain-specific capabilities relevant to this investigation, note them in each Debugger's task context so it can use those tools during investigation.
    - Create 3 tasks via TaskCreate, each with: bug report, extended context from todo detail if loaded in Step 1 (include `detail.context` and `detail.files` — omit this section entirely if no detail was loaded), ONE hypothesis only (no cross-contamination), working dir, codebase bootstrap instruction ("If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md, CONCERNS.md, PATTERNS.md, and DEPENDENCIES.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before investigating"), instruction to report via `debugger_report` schema (see ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/handoff-schemas.md`), instruction: "If investigation reveals pre-existing failures unrelated to this bug, list them in your response under a 'Pre-existing Issues' heading with test name, file, and failure message." **Include `[analysis-only]` in each task subject** (e.g., "Hypothesis 1: race condition in sync handler [analysis-only]") so the TaskCompleted hook skips the commit-verification gate for report-only tasks.
    - Spawn 3 vbw-debugger teammates, one task each. **Set `subagent_type: "vbw:vbw-debugger"` and `model: "${DEBUGGER_MODEL}"` on each Task spawn. If `DEBUGGER_MAX_TURNS` is non-empty, also pass `maxTurns: ${DEBUGGER_MAX_TURNS}`. If `DEBUGGER_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).**
    - Wait for completion. Synthesize: strongest evidence + highest confidence wins. Multiple confirmed = contributing factors.
    - Collect pre-existing issues from all debugger responses. De-duplicate by test name and file (keep first error message when the same test+file pair has different messages) — if multiple debuggers report the same pre-existing failure, include it only once.
    - Winning hypothesis with fix: apply + commit `fix({scope}): {description}`
    - **HARD GATE — Shutdown before presenting results:** Send `shutdown_request` to each teammate, wait for `shutdown_response` (approved=true) delivered via SendMessage tool call (NOT plain text). If a teammate responds in plain text instead of calling SendMessage, re-send the `shutdown_request`. If rejected, re-request (max 3 attempts per teammate — then proceed). Call TeamDelete. **Post-TeamDelete residual cleanup:** `bash "${VBW_PLUGIN_ROOT}/scripts/clean-stale-teams.sh" 2>/dev/null || true`. Verify: after TeamDelete, there must be ZERO active teammates. If teardown stalls, advise the user to run `/vbw:doctor --cleanup`. Only THEN present results to user. Failure to shut down leaves agents running and consuming API credits.

    **Path B: Standard** (all other cases):
    - Resolve Debugger model:
        ```bash
        DEBUGGER_MODEL=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh debugger .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
        if [ $? -ne 0 ]; then echo "$DEBUGGER_MODEL" >&2; exit 1; fi
        DEBUGGER_MAX_TURNS=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-max-turns.sh debugger .vbw-planning/config.json "$EFFORT_PROFILE")
        if [ $? -ne 0 ]; then echo "$DEBUGGER_MAX_TURNS" >&2; exit 1; fi
        ```
    - Display: `◆ Spawning Debugger (${DEBUGGER_MODEL})...`
    - Before composing the Debugger task description, evaluate installed skills visible in your system context — read each skill's description and determine if it is relevant to this bug investigation. The Debugger prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each relevant skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills apply, or `<skill_no_activation>Evaluated installed skills for this task. No installed skills apply. Reason: {brief task-specific reason}.</skill_no_activation>` when none apply. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none apply — {reason}") so the user has visibility before the agent is spawned. Only include skills whose description matches the investigation at hand (e.g., debugging skills, platform-specific skills for the affected stack).
    - Also evaluate available MCP tools in your system context. If any MCP servers provide debugging, build, test, documentation, or domain-specific capabilities relevant to this investigation, note them in the Debugger's task context so it can use those tools during investigation.
    - Spawn vbw-debugger as subagent via Task tool. **Set `subagent_type: "vbw:vbw-debugger"` and `model: "${DEBUGGER_MODEL}"` in the Task tool invocation. If `DEBUGGER_MAX_TURNS` is non-empty, also pass `maxTurns: ${DEBUGGER_MAX_TURNS}`. If `DEBUGGER_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).**
        ```text
        Bug investigation. Effort: {DEBUGGER_EFFORT}.
        Bug report: {description}.
        Extended context from todo detail (include only if detail was loaded in Step 1): {detail.context}. Related files: {detail.files, comma-separated}.
        Working directory: {pwd}.
        If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md, CONCERNS.md, PATTERNS.md, and DEPENDENCIES.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before investigating.
        Follow protocol: bootstrap (if codebase mapping exists), reproduce, hypothesize, gather evidence, diagnose, fix, verify, document.
        If you apply a fix, commit with: fix({scope}): {description}.
        If investigation reveals pre-existing failures unrelated to this bug, list them in your response under a "Pre-existing Issues" heading with test name, file, and failure message.
        ```

5. **Persist to debug session + Clear delegation marker + Present:**

    <debug_session_persistence>
    After investigation completes (Path A or Path B), persist results to the debug session file using `write-debug-session.sh`:

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
      "implementation": "{summary of changes}",
      "changed_files": ["{file1}", "{file2}"],
      "commit": "{commit hash and message, or 'No commit yet.'}"
    }
    ENDJSON
    )
    echo "$INVESTIGATION_JSON" | bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/write-debug-session.sh "$session_file"
    ```

    If a fix was applied and committed, set status to `qa_pending`:
    ```bash
    bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/debug-session-state.sh set-status .vbw-planning qa_pending
    ```

    If investigation completed but no fix was applied (analysis only), set status to `fix_applied` is wrong — keep as `investigating` and advise user to apply the fix.
    </debug_session_persistence>

    Clear the marker:
    ```bash
    bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/delegated-workflow.sh clear
    ```
    Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
    ```text
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Bug Investigation Complete
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      Mode:       {Path A: "Competing Hypotheses (3 parallel)" + hypothesis outcomes | Path B: "Standard (single debugger)"}
      Issue:      {one-line summary}
      Root Cause: {from report}
      Fix:        {commit hash + message, or "No fix applied"}

      Files Modified: {list}
    ```

**Discovered Issues:** If the Debugger reported pre-existing failures, out-of-scope bugs, or issues unrelated to the investigated bug, append after the result box. Cap the list at 20 entries; if more exist, show the first 20 and append `... and {N} more`:
```text
  Discovered Issues:
    ⚠ testName (path/to/file): error message
    ⚠ testName (path/to/file): error message
  Suggest: /vbw:todo <description> to track
```
This is **display-only**. Do NOT edit STATE.md, do NOT add todos, do NOT invoke /vbw:todo, and do NOT enter an interactive loop. The user decides whether to track these. If no discovered issues: omit the section entirely. After displaying discovered issues, STOP. Do not take further action.

<debug_session_next_step>
Session-aware next step (based on what happened during investigation):

- If a fix was committed and session status is `qa_pending`:
  `➜ Next: /vbw:qa --session -- Verify the debug fix`
- If investigation completed but no fix was applied (session status is `investigating`):
  `➜ Next: /vbw:debug --resume -- Continue investigation and apply fix`
- If session was not created (error or guard stopped execution):
  `➜ Next: /vbw:status -- View project status`
</debug_session_next_step>
---
name: vbw:fix
category: supporting
disable-model-invocation: true
description: Apply a quick fix or small change with commit discipline. Turbo mode -- no planning ceremony.
argument-hint: "<description of what to fix or change>"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch, Agent, Skill, LSP
---

# VBW Fix: $ARGUMENTS

## Context
Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; SESSION_LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ] && [ -f "${SESSION_LINK}/scripts/hook-wrapper.sh" ]; then R="${SESSION_LINK}"; fi; if [ -z "$R" ]; then ANY_LINK=$(command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r link; do if [ -f "$link/scripts/hook-wrapper.sh" ]; then printf '%s\n' "$link"; break; fi; done || true); [ -n "$ANY_LINK" ] && R="$ANY_LINK"; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; LINK="${SESSION_LINK}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$LINK" "$REAL_R" >/dev/null 2>&1 || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```

Store the plugin root path output above as `{plugin-root}` for use in script invocations below. Replace `{plugin-root}` with the literal `Plugin root` value from Context whenever a step below references a script or reference file.
Config: Pre-injected by SessionStart hook.

## Guard
- Not initialized (no .vbw-planning/ dir): STOP "Run /vbw:init first."
- No $ARGUMENTS: STOP "Usage: /vbw:fix \"description of what to fix\""

## Steps
1. **Resolve todo number:** If $ARGUMENTS is a bare integer (matches `^[0-9]+$` with no other text or flags), preserve the original numeric-selection marker before rewriting anything. Resolve the todo item against the persisted session snapshot of the last `/vbw:list-todos` view:
    ```bash
  bash "{plugin-root}/scripts/resolve-todo-item.sh" <N> --session-snapshot --require-unfiltered --validate-live
    ```
    Parse the JSON output. If `status` is `"ok"`, store the full payload as `TODO_SELECTED_JSON`, preserve `TODO_SELECTED=true`, and replace $ARGUMENTS with the item's `command_text` value (not the old duplicated `description` form). If the resolved `state_path` points under `.vbw-planning/milestones/`, STOP with: `This todo came from archived milestone state. Restore the writable root STATE.md first by restarting so session-start.sh can run migration, or run 'bash scripts/migrate-orphaned-state.sh .vbw-planning'.` Do not continue using the archived description as live work input. If `status` is `"error"`, STOP with the `message` value.

2. **Parse:** Entire $ARGUMENTS (minus flags) = fix description. If `TODO_SELECTED_JSON` exists, treat its `command_text` as the fix description and its `ref` as the already-resolved ref before any additional parsing. Otherwise, if the description contains a `(ref:HASH)` suffix (8 hex characters), extract the hash and strip the ref tag from the description before further processing. If a ref was found, load extended detail:
    ```bash
  bash "{plugin-root}/scripts/todo-details.sh" get <hash>
    ```
  Command shape: `bash "{plugin-root}/scripts/todo-details.sh" get <hash>`.
  Parse the JSON output. If `status` is `"ok"`, store the `detail.context` and `detail.files` values for use in step 5 and record `DETAIL_STATUS=ok`. If `status` is `"not_found"` or `"error"`, record `DETAIL_STATUS` to match and run:
    ```bash
    bash "{plugin-root}/scripts/todo-lifecycle.sh" detail-warning {hash}
    ```
    In all cases, continue without detail.
    **Post-parse validation:** If the fix description is empty or whitespace-only after stripping flags and ref, check whether a ref was found AND its detail loaded successfully (status `"ok"`). If yes, proceed — the detail provides the fix context. If no ref was found, or the ref detail failed to load, STOP: `"Usage: /vbw:fix \"description of what to fix\""`.

3. **State:** Use `.vbw-planning/STATE.md`.

4. **Set delegation marker:** Before spawning Dev, activate the delegation guard so the orchestrator cannot accidentally write product files directly:
    ```bash
  bash "{plugin-root}/scripts/delegated-workflow.sh" set fix turbo
    ```

   - **Immediate todo pickup (numeric selections only):** If `TODO_SELECTED=true`, claim the todo now — after fix has passed its own parse/guard steps, and before Dev is spawned. Pipe `TODO_SELECTED_JSON` into:
     ```bash
    bash "{plugin-root}/scripts/todo-lifecycle.sh" pickup /vbw:fix {DETAIL_STATUS} {cleanup_policy}
     ```
    Use `safe` for `{cleanup_policy}` when `DETAIL_STATUS=ok`; otherwise use `keep`. If the helper returns `status="error"`, STOP with its `message` value. If it returns `status="partial"`, continue but surface its `warning` value in the final result so cleanup state is explicit. This pickup path only applies to true numeric todo selections — never to manual text or manual `(ref:HASH)` inputs.

5. **Spawn Dev:** Resolve model first:
    ```bash
  if ! AGENT_SETTINGS=$(bash "{plugin-root}/scripts/resolve-agent-settings.sh" dev .vbw-planning/config.json "{plugin-root}/config/model-profiles.json" turbo); then
    echo "$AGENT_SETTINGS" >&2
    exit 1
  fi
  eval "$AGENT_SETTINGS"
  DEV_MODEL="$RESOLVED_MODEL"
  DEV_MAX_TURNS="$RESOLVED_MAX_TURNS"
    ```

    Before composing the Dev task description, evaluate installed skills visible in your system context — read each skill's description and select all materially helpful installed skills for this fix, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context — not just the single most direct skill. The spawned prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected — {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting — do not scan entire skill folders or read unrelated references.

    If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning the Dev. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.

    Also evaluate available MCP tools in your system context. If any MCP servers provide capabilities relevant to this fix (build tools, documentation servers, domain-specific APIs), note them in the Dev task description.

    **Discover research context** (optional, from prior `/vbw:research`):
    ```bash
    RESEARCH_CONTEXT=$(bash "{plugin-root}/scripts/compile-research-context.sh" .vbw-planning "{fix description from Step 1}" 2>/dev/null || echo "")
    ```
    Replace `{fix description from Step 1}` with the actual parsed fix description. If `RESEARCH_CONTEXT` is non-empty, include it in the Dev task prompt below. If empty, omit the `<standalone_research_context>` block entirely — the fix workflow proceeds as today.

    Spawn vbw-dev as subagent via Task tool with `subagent_type: "vbw:vbw-dev"` and `model: "${DEV_MODEL}"`.
    If `DEV_MAX_TURNS` is non-empty, also pass `maxTurns: ${DEV_MAX_TURNS}`.
    If `DEV_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited):

    Use this payload prefix as the FIRST lines of the Dev prompt:
    ```text
    <skill_activation>
    Call Skill('{relevant-skill-1}').
    Call Skill('{relevant-skill-2}').
    </skill_activation>
    After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting — do not scan entire skill folders or read unrelated references.
    <skill_follow_up_files>
    {If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning and replace this block with the emitted absolute follow-up file paths. Omit this block when the helper prints nothing.}
    </skill_follow_up_files>
    ```

    When no installed skills apply, use this prefix instead:
    ```text
    <skill_no_activation>
    Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.
    </skill_no_activation>
    After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting — do not scan entire skill folders or read unrelated references.
    ```

    ```text
    Quick fix (Turbo mode). Effort: low.
    Standalone research context (include ONLY if RESEARCH_CONTEXT was non-empty — omit this entire block otherwise):
    <standalone_research_context>
    Prior research findings from /vbw:research. Advisory — verify all claims against the current codebase before relying on them.
    {RESEARCH_CONTEXT}
    </standalone_research_context>
    Task: {fix description}.
    {If detail was loaded in step 1, include on next lines:
    "Extended context (from todo detail):
    {detail.context value}
    Related files: {detail.files, comma-separated, or omit if empty}"}
    If `.vbw-planning/codebase/META.md` exists, read CONVENTIONS.md, PATTERNS.md, STRUCTURE.md, and DEPENDENCIES.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before implementing.
    Implement directly. One atomic commit: fix(quick): {brief description}.
    No SUMMARY.md or PLAN.md needed.
    If tests reveal pre-existing failures unrelated to this fix, list them in your response under a "Pre-existing Issues" heading with test name, file, and failure message.
    If ambiguous or requires architectural decisions, STOP and report back.
    ```

6. **Clear delegation marker + Verify + present:** Clear the marker first, then check results:
    ```bash
  bash "{plugin-root}/scripts/delegated-workflow.sh" clear
    ```
    Check `git log --oneline -1`. Check Dev response for pre-existing issues.
    Committed, no discovered issues:

    ```text
    ✓ Fix applied
      {commit hash} {commit message}
      Files: {changed files}
    ```

    Run `bash "{plugin-root}/scripts/write-fix-marker.sh" .vbw-planning 2>/dev/null || true` silently — this persists fix context for inline QA/UAT.
    Run `bash "{plugin-root}/scripts/suggest-next.sh" fix` and display.

    Committed, with discovered issues (Dev reported pre-existing failures):

    De-duplicate by test name and file (keep first error message when the same
    test+file pair has different messages). Cap the list at 20 entries; if more
    exist, show the first 20 and append `... and {N} more`.

    ```text
    ✓ Fix applied
      {commit hash} {commit message}
      Files: {changed files}

      Discovered Issues:
        ⚠ testName (path/to/file): error message
        ⚠ testName (path/to/file): error message
      Suggest: /vbw:todo <description> to track
    ```

    This is **display-only**. Do NOT edit STATE.md, do NOT add todos, do NOT
    invoke /vbw:todo, and do NOT enter an interactive loop. The user decides
    whether to track these. If no discovered issues: omit the section entirely.
    After displaying discovered issues, **STOP. Do not take further action** on discovered issues (no auto-fix, no auto-track, no investigation)—just display them.
    Run `bash "{plugin-root}/scripts/write-fix-marker.sh" .vbw-planning 2>/dev/null || true` silently — this persists fix context for inline QA/UAT.
    Run `bash "{plugin-root}/scripts/suggest-next.sh" fix` and display.

    Dev stopped:

    ```text
    ⚠ Fix could not be applied automatically
      {reason from Dev agent}
    ```

    Run `bash "{plugin-root}/scripts/suggest-next.sh" debug` and display.
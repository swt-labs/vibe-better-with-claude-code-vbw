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
Config: Pre-injected by SessionStart hook.

## Guard
- Not initialized (no .vbw-planning/ dir): STOP "Run /vbw:init first."
- No $ARGUMENTS: STOP "Usage: /vbw:fix \"description of what to fix\""

## Steps
1. **Parse:** Entire $ARGUMENTS (minus flags) = fix description. If the description contains a `(ref:HASH)` suffix (8 hex characters), extract the hash and strip the ref tag from the description before further processing. If a ref was found, load extended detail:
    ```bash
    bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/todo-details.sh get <hash>
    ```
  Parse the JSON output. If `status` is `"ok"`, store the `detail.context` and `detail.files` values for use in step 4. If `status` is `"not_found"` or `"error"`, and `.vbw-planning/STATE.md` exists, append `- {YYYY-MM-DD}: Detail for ref HASH could not be loaded` under the `## Activity Log` section (or the first heading beginning with `## Activity`) in `.vbw-planning/STATE.md`; if that file does not exist, skip logging. In all cases, continue without detail.
    **Post-parse validation:** If the fix description is empty or whitespace-only after stripping flags and ref, check whether a ref was found AND its detail loaded successfully (status `"ok"`). If yes, proceed — the detail provides the fix context. If no ref was found, or the ref detail failed to load, STOP: `"Usage: /vbw:fix \"description of what to fix\""`.

2. **State:** Use `.vbw-planning/STATE.md`.

3. **Set delegation marker:** Before spawning Dev, activate the delegation guard so the orchestrator cannot accidentally write product files directly:
    ```bash
    bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/delegated-workflow.sh set fix turbo
    ```

4. **Spawn Dev:** Resolve model first:
    ```bash
    DEV_MODEL=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh dev .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
    DEV_MAX_TURNS=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-max-turns.sh dev .vbw-planning/config.json turbo)
    ```

    Before composing the Dev task description, evaluate installed skills visible in your system context — read each skill's description and determine if it is relevant to this specific fix. The spawned prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each relevant skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills apply, or `<skill_no_activation>Evaluated installed skills for this task. No installed skills apply. Reason: {brief task-specific reason}.</skill_no_activation>` when none apply. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none apply — {reason}") so the user has visibility before the agent is spawned. Only include skills whose description matches the task at hand.

    Also evaluate available MCP tools in your system context. If any MCP servers provide capabilities relevant to this fix (build tools, documentation servers, domain-specific APIs), note them in the Dev task description.

    **Discover research context** (optional, from prior `/vbw:research`):
    ```bash
    RESEARCH_CONTEXT=$(bash "`!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/compile-research-context.sh" .vbw-planning "{fix description from Step 1}" 2>/dev/null || echo "")
    ```
    Replace `{fix description from Step 1}` with the actual parsed fix description. If `RESEARCH_CONTEXT` is non-empty, include it in the Dev task prompt below. If empty, omit the `<standalone_research_context>` block entirely — the fix workflow proceeds as today.

    Spawn vbw-dev as subagent via Task tool with `subagent_type: "vbw:vbw-dev"` and `model: "${DEV_MODEL}"`.
    If `DEV_MAX_TURNS` is non-empty, also pass `maxTurns: ${DEV_MAX_TURNS}`.
    If `DEV_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited):

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

5. **Clear delegation marker + Verify + present:** Clear the marker first, then check results:
    ```bash
    bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/delegated-workflow.sh clear
    ```
    Check `git log --oneline -1`. Check Dev response for pre-existing issues.
    Committed, no discovered issues:

    ```text
    ✓ Fix applied
      {commit hash} {commit message}
      Files: {changed files}
    ```

    Run `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/suggest-next.sh fix` and display.

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
    After displaying discovered issues, STOP. Do not take further action.
    Run `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/suggest-next.sh fix` and display.

    Dev stopped:

    ```text
    ⚠ Fix could not be applied automatically
      {reason from Dev agent}
    ```

    Run `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/suggest-next.sh debug` and display.
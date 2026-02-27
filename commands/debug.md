---
name: vbw:debug
category: supporting
description: Investigate a bug using the Debugger agent's scientific method protocol.
argument-hint: "<bug description or error message>"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
---

# VBW Debug: $ARGUMENTS

## Context
Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}" && break; done; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; rm -f "$LINK"; ln -s "$REAL_R" "$LINK" 2>/dev/null || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```

Recent commits:
```text
!`git log --oneline -10 2>/dev/null || echo "No git history"`
```

## Guard
- Not initialized (no .vbw-planning/ dir): STOP "Run /vbw:init first."
- No $ARGUMENTS: STOP "Usage: /vbw:debug \"description of the bug or error message\""

## Steps
1. **Parse + effort:** Entire $ARGUMENTS = bug description.
  Map effort: thorough=high, balanced/fast=medium, turbo=low.
  Keep effort profile as `EFFORT_PROFILE` (thorough|balanced|fast|turbo).
  Read ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/effort-profile-{profile}.md`.

2. **Classify ambiguity:** 2+ signals = ambiguous.
  Keywords: "intermittent/sometimes/random/unclear/inconsistent/flaky/sporadic/nondeterministic",
  multiple root cause areas, generic/missing error, previous reverted fixes in
  git log. Overrides: `--competing`/`--parallel` = always ambiguous;
  `--serial` = never.

3. **Routing decision:** Read prefer_teams config:
    ```bash
    PREFER_TEAMS=$(jq -r '.prefer_teams // "always"' .vbw-planning/config.json 2>/dev/null)
    ```

    Decision tree:

    - `prefer_teams='always'`: Use Path A (team) for ALL bugs, regardless of effort or ambiguity
    - `prefer_teams='when_parallel'`: Use Path A (team) only if effort=high AND ambiguous, else Path B
    - `prefer_teams='auto'`: Same as when_parallel (single debugger is low-risk for non-ambiguous bugs)

4. **Spawn investigation:**
    **Path A: Competing Hypotheses** (prefer_teams='always' OR (effort=high AND ambiguous)):
    - Generate 3 hypotheses (cause, codebase area, confirming evidence)
    - Resolve Debugger model:
        ```bash
        DEBUGGER_MODEL=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh debugger .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
        if [ $? -ne 0 ]; then echo "$DEBUGGER_MODEL" >&2; exit 1; fi
        DEBUGGER_MAX_TURNS=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-max-turns.sh debugger .vbw-planning/config.json "$EFFORT_PROFILE")
        if [ $? -ne 0 ]; then echo "$DEBUGGER_MAX_TURNS" >&2; exit 1; fi
        ```
    - Display: `◆ Spawning Debugger (${DEBUGGER_MODEL})...`
    - Create Agent Team "debug-{timestamp}" via TeamCreate
    - Create 3 tasks via TaskCreate, each with: bug report, ONE hypothesis only (no cross-contamination), working dir, codebase bootstrap instruction ("If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md, CONCERNS.md, PATTERNS.md, and DEPENDENCIES.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before investigating"), instruction to report via `debugger_report` schema (see ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/handoff-schemas.md`), instruction: "If investigation reveals pre-existing failures unrelated to this bug, list them in your response under a 'Pre-existing Issues' heading with test name, file, and failure message." **Include `[analysis-only]` in each task subject** (e.g., "Hypothesis 1: race condition in sync handler [analysis-only]") so the TaskCompleted hook skips the commit-verification gate for report-only tasks.
    - Spawn 3 vbw-debugger teammates, one task each. **Add `model: "${DEBUGGER_MODEL}"` and `maxTurns: ${DEBUGGER_MAX_TURNS}` parameters to each Task spawn.**
    - Wait for completion. Synthesize: strongest evidence + highest confidence wins. Multiple confirmed = contributing factors.
    - Collect pre-existing issues from all debugger responses. De-duplicate by test name and file (keep first error message when the same test+file pair has different messages) — if multiple debuggers report the same pre-existing failure, include it only once.
    - Winning hypothesis with fix: apply + commit `fix({scope}): {description}`
    - **HARD GATE — Shutdown before presenting results:** Send `shutdown_request` to each teammate, wait for `shutdown_response` (approved=true), re-request if rejected, then TeamDelete. Only THEN present results to user. Failure to shut down leaves agents running and consuming API credits.

    **Path B: Standard** (all other cases):
    - Resolve Debugger model:
        ```bash
        DEBUGGER_MODEL=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh debugger .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
        if [ $? -ne 0 ]; then echo "$DEBUGGER_MODEL" >&2; exit 1; fi
        DEBUGGER_MAX_TURNS=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-max-turns.sh debugger .vbw-planning/config.json "$EFFORT_PROFILE")
        if [ $? -ne 0 ]; then echo "$DEBUGGER_MAX_TURNS" >&2; exit 1; fi
        ```
    - Display: `◆ Spawning Debugger (${DEBUGGER_MODEL})...`
    - Spawn vbw-debugger as subagent via Task tool. **Add `model: "${DEBUGGER_MODEL}"` and `maxTurns: ${DEBUGGER_MAX_TURNS}` parameters.**
        ```text
        Bug investigation. Effort: {DEBUGGER_EFFORT}.
        Bug report: {description}.
        Working directory: {pwd}.
        If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md, CONCERNS.md, PATTERNS.md, and DEPENDENCIES.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before investigating.
        Follow protocol: bootstrap (if codebase mapping exists), reproduce, hypothesize, gather evidence, diagnose, fix, verify, document.
        If you apply a fix, commit with: fix({scope}): {description}.
        If investigation reveals pre-existing failures unrelated to this bug, list them in your response under a "Pre-existing Issues" heading with test name, file, and failure message.
        ```

5. **Present:** Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
    ```text
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      Bug Investigation Complete
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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

➜ Next: /vbw:status -- View project status
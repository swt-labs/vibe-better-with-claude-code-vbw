---
name: vbw:qa
category: monitoring
disable-model-invocation: true
description: Run deep verification on completed phase work using the QA agent.
argument-hint: [phase-number] [--tier=quick|standard|deep] [--effort=thorough|balanced|fast|turbo]
allowed-tools: Read, Write, Bash, Glob, Grep, LSP
---

# VBW QA: $ARGUMENTS

## Context
Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}" && break; done; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; rm -f "$LINK"; ln -s "$REAL_R" "$LINK" 2>/dev/null || { echo "VBW: plugin root link failed" >&2; exit 1; }; STAMP="/tmp/.vbw-phase-detect-stamp-${SESSION_KEY}.txt"; : > "$STAMP"; bash "$LINK/scripts/phase-detect.sh" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt" 2>/dev/null || echo "phase_detect_error=true" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; echo "$LINK"`
```

Current state:
```text
!`head -40 .vbw-planning/STATE.md 2>/dev/null || echo "No state found"`
```

Config: Pre-injected by SessionStart hook. Override with --effort flag.

Phase directories:
```text
!`ls .vbw-planning/phases/ 2>/dev/null || echo "No phases directory"`
```

Phase state:
```text
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; S="/tmp/.vbw-phase-detect-stamp-${SESSION_KEY}.txt"; PD=""; [ -f "$P" ] && PD=$(cat "$P"); if [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ -L "$L" ]; then i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; S_M=0; P_M=0; [ -f "$S" ] && S_M=$(stat -c %Y "$S" 2>/dev/null || stat -f %m "$S" 2>/dev/null || echo 0); [ -f "$P" ] && P_M=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo 0); if [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ] && { [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ "$P_M" -lt "$S_M" ]; }; then PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""; fi; fi; if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then printf '%s' "$PD"; else echo "phase_detect_error=true"; fi`
```

```text
!`L="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; bash "$L/scripts/suggest-compact.sh" qa 2>/dev/null || true`
```

## Guard
- Not initialized (no .vbw-planning/ dir): STOP "Run /vbw:init first."
- **Brownfield normalization:** If Phase state (from Context above) contains `misnamed_plans=true`, normalize all phase directories before proceeding:
  ```bash
  NORM_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
  if [ -f "$NORM_SCRIPT" ]; then
    for pdir in .vbw-planning/phases/*/; do
      [ -d "$pdir" ] && bash "$NORM_SCRIPT" "$pdir"
    done
  fi
  ```
  Display: "⚠ Renamed misnamed plan files to `{NN}-PLAN.md` convention."
  Then re-run phase-detect.sh to refresh state (filenames changed):
  ```bash
  bash "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/phase-detect.sh" > "/tmp/.vbw-phase-detect-${CLAUDE_SESSION_ID:-default}.txt"
  ```
  Use the refreshed phase-detect output for all subsequent guard checks and steps.
- **Auto-detect phase** (no explicit number): Phase detection is pre-computed in Context above. Use `next_phase` and `next_phase_slug` for the target phase. To find the first phase needing QA: scan phase dirs for first with `*-SUMMARY.md` but no `*-VERIFICATION.md` (phase-detect.sh provides the base phase state; QA-specific detection requires this additional check). Found: announce "Auto-detected Phase {NN} ({slug})". All verified: STOP "All phases verified. Specify: `/vbw:qa {NN}`"
- Phase not built (no SUMMARYs): STOP "Phase {NN} has no completed plans. Run /vbw:vibe first."

Note: Continuous verification handled by hooks. This command is for deep, on-demand verification only.

## Steps
1. **Resolve tier:** Priority order: `--tier` flag > `--effort` flag > config
  default > Standard.
  Keep effort profile as `QA_EFFORT_PROFILE` (thorough|balanced|fast|turbo).
  Effort mapping: turbo=skip (exit "QA skipped in turbo mode"), fast=quick,
  balanced=standard, thorough=deep.
  Read ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/effort-profile-{profile}.md`.
  Context overrides: >15 requirements or last phase before ship → Deep.

2. **Resolve phase:** Use `.vbw-planning/phases/` for phase directories.

3. **Spawn QA:**
    - Resolve QA model:

        ```bash
        QA_MODEL=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh qa .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
        if [ $? -ne 0 ]; then echo "$QA_MODEL" >&2; exit 1; fi
        QA_MAX_TURNS=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-max-turns.sh qa .vbw-planning/config.json "$QA_EFFORT_PROFILE")
        if [ $? -ne 0 ]; then echo "$QA_MAX_TURNS" >&2; exit 1; fi
        ```

    - Display: `◆ Spawning QA agent (${QA_MODEL})...`
    - Spawn vbw-qa as subagent via Task tool. **Set `subagent_type: "vbw:vbw-qa"` and `model: "${QA_MODEL}"` in
      the Task tool invocation. If `QA_MAX_TURNS` is non-empty, also pass
      `maxTurns: ${QA_MAX_TURNS}`. If `QA_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).**

        ```text
        Verify phase {NN}. Tier: {ACTIVE_TIER}.
        Plans: {paths to PLAN.md files}
        Summaries: {paths to SUMMARY.md files}
        Phase success criteria: {section from ROADMAP.md}
        If `.vbw-planning/codebase/META.md` exists, read CONVENTIONS.md, TESTING.md, CONCERNS.md, and ARCHITECTURE.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before verifying.
        Verification protocol: `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/verification-protocol.md
        Return findings using the qa_verdict schema (see `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/handoff-schemas.md).
        If tests reveal pre-existing failures unrelated to this phase, list them in your response under a "Pre-existing Issues" heading and include them in the qa_verdict payload's pre_existing_issues array.
        Persist your VERIFICATION.md by piping qa_verdict JSON through write-verification.sh. Output path: {phase-dir}/{phase}-VERIFICATION.md. Plugin root: `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`.
        ```

    - QA agent reads all files and persists VERIFICATION.md itself. If QA reports a `write-verification.sh` failure, surface the error to the user — do NOT fall back to manual VERIFICATION.md writes.

4. **Present:** Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
    ```text
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Phase {NN}: {name} -- Verified
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      Tier:     {quick|standard|deep}
      Result:   {✓ PASS | ✗ FAIL | ◆ PARTIAL}
      Checks:   {passed}/{total}
      Failed:   {list or "None"}

      Report:   {path to VERIFICATION.md}

    ```

**Discovered Issues:** If the QA agent reported pre-existing failures, out-of-scope bugs, or issues unrelated to this phase's work, de-duplicate by test name and file (keep first error message when the same test+file pair has different messages) and append after the result box. Cap the list at 20 entries; if more exist, show the first 20 and append `... and {N} more`:
```text
  Discovered Issues:
    ⚠ testName (path/to/file): error message
    ⚠ testName (path/to/file): error message
  Suggest: /vbw:todo <description> to track
```
This is **display-only**. Do NOT edit STATE.md, do NOT add todos, do NOT invoke /vbw:todo, and do NOT enter an interactive loop. The user decides whether to track these. If no discovered issues: omit the section entirely. After displaying discovered issues, STOP. Do not take further action.

Run:
```text
bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/suggest-next.sh qa {result}
```
Then display the output.
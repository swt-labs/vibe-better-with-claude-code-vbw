---
name: vbw:qa
category: monitoring
description: Run deep verification on completed phase work using the QA agent.
argument-hint: [phase-number] [--tier=quick|standard|deep] [--effort=thorough|balanced|fast|turbo]
allowed-tools: Read, Write, Bash, Glob, Grep
---

# VBW QA: $ARGUMENTS

## Context
Working directory: `!`pwd``
Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(bash -c 'ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1')}``

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
!`bash ${CLAUDE_PLUGIN_ROOT:-$(bash -c 'ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1')}/scripts/phase-detect.sh 2>/dev/null || echo "phase_detect_error=true"`
```

!`bash ${CLAUDE_PLUGIN_ROOT:-$(bash -c 'ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1')}/scripts/suggest-compact.sh qa 2>/dev/null || true`

## Guard
- Not initialized (no .vbw-planning/ dir): STOP "Run /vbw:init first."
- **Auto-detect phase** (no explicit number): Phase detection is pre-computed in Context above. Use `next_phase` and `next_phase_slug` for the target phase. To find the first phase needing QA: scan phase dirs for first with `*-SUMMARY.md` but no `*-VERIFICATION.md` (phase-detect.sh provides the base phase state; QA-specific detection requires this additional check). Found: announce "Auto-detected Phase {N} ({slug})". All verified: STOP "All phases verified. Specify: `/vbw:qa N`"
- Phase not built (no SUMMARYs): STOP "Phase {N} has no completed plans. Run /vbw:vibe first."

Note: Continuous verification handled by hooks. This command is for deep, on-demand verification only.

## Steps
1. **Resolve tier:** Priority order: `--tier` flag > `--effort` flag > config
  default > Standard.
  Keep effort profile as `QA_EFFORT_PROFILE` (thorough|balanced|fast|turbo).
  Effort mapping: turbo=skip (exit "QA skipped in turbo mode"), fast=quick,
  balanced=standard, thorough=deep.
  Read `${CLAUDE_PLUGIN_ROOT}/references/effort-profile-{profile}.md`.
  Context overrides: >15 requirements or last phase before ship → Deep.

2. **Resolve phase:** Use `.vbw-planning/phases/` for phase directories.

3. **Spawn QA:**
    - Resolve QA model:

        ```bash
        QA_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh qa .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
        if [ $? -ne 0 ]; then echo "$QA_MODEL" >&2; exit 1; fi
        QA_MAX_TURNS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh qa .vbw-planning/config.json "$QA_EFFORT_PROFILE")
        if [ $? -ne 0 ]; then echo "$QA_MAX_TURNS" >&2; exit 1; fi
        ```

    - Display: `◆ Spawning QA agent (${QA_MODEL})...`
    - Spawn vbw-qa as subagent via Task tool. **Add `model: "${QA_MODEL}"` and
      `maxTurns: ${QA_MAX_TURNS}` parameters.**

        ```text
        Verify phase {N}. Tier: {ACTIVE_TIER}.
        Plans: {paths to PLAN.md files}
        Summaries: {paths to SUMMARY.md files}
        Phase success criteria: {section from ROADMAP.md}
        If `.vbw-planning/codebase/META.md` exists, read CONVENTIONS.md, TESTING.md, CONCERNS.md, and ARCHITECTURE.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before verifying.
        Verification protocol: ${CLAUDE_PLUGIN_ROOT}/references/verification-protocol.md
        Return findings using the qa_verdict schema (see ${CLAUDE_PLUGIN_ROOT}/references/handoff-schemas.md).
        If tests reveal pre-existing failures unrelated to this phase, list them in your response under a "Pre-existing Issues" heading and include them in the qa_verdict payload's pre_existing_issues array.
        ```

    - QA agent reads all files itself.

4. **Persist:**
  Parse QA output as JSON (`qa_verdict` schema).
  Fallback: extract from markdown.
  Pipe the `qa_verdict` JSON through the deterministic writer:
  ```bash
  echo "$QA_VERDICT_JSON" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-verification.sh" "{phase-dir}/{phase}-VERIFICATION.md"
  ```
  If the script fails (exit 1) or `write-verification.sh` is missing, fall back to manual file writing:
  write `{phase-dir}/{phase}-VERIFICATION.md` with frontmatter (phase, tier,
  result, passed, failed, total, date) and QA body as content.

5. **Present:** Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
    ```text
    ┌──────────────────────────────────────────┐
    │  Phase {N}: {name} -- Verified           │
    └──────────────────────────────────────────┘

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

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh qa {result}` and display.
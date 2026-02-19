---
name: vbw:verify
category: monitoring
description: Run human acceptance testing on completed phase work. Presents CHECKPOINT prompts one at a time.
argument-hint: "[phase-number] [--resume]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# VBW Verify: $ARGUMENTS

## Context

Working directory: `!`pwd``
Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}``

Current state:
```
!`head -40 .vbw-planning/STATE.md 2>/dev/null || echo "No state found"`
```

Config: Pre-injected by SessionStart hook.

Phase directories:
```
!`ls .vbw-planning/phases/ 2>/dev/null || echo "No phases directory"`
```

Phase state:
```
!`bash ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}/scripts/phase-detect.sh 2>/dev/null || echo "phase_detect_error=true"`
```

## Guard

- Not initialized (no .vbw-planning/ dir): STOP "Run /vbw:init first."
- No SUMMARY.md in phase dir: STOP "Phase {N} has no completed plans. Run /vbw:vibe first."
- **Auto-detect phase** (no explicit number): Phase detection is pre-computed in Context above. Use `next_phase` and `next_phase_slug` for the target phase. To find the first phase needing UAT: scan phase dirs for first with `*-SUMMARY.md` but no `*-UAT.md`. Found: announce "Auto-detected Phase {N} ({slug})". All verified: STOP "All phases have UAT results. Specify: `/vbw:verify N`"

## Steps

### 1. Resolve phase and load summaries

- Parse explicit phase number from $ARGUMENTS, or use auto-detected phase
- Resolve milestone: if .vbw-planning/ACTIVE exists, use milestone-scoped paths
- Read all `*-SUMMARY.md` files in the phase directory
- Read corresponding `*-PLAN.md` files for `must_haves` and success criteria

### 2. Check for existing UAT session (resume support)

- If `{phase}-UAT.md` exists in the phase directory:
  - Read it, find the first test without a result (Result line is empty or missing)
  - Display: `Resuming UAT session -- {completed}/{total} tests done`
  - Jump to the CHECKPOINT loop at the resume point
- If all tests already have results: display the summary, STOP

### 3. Generate test scenarios from SUMMARY.md files

For each completed plan's SUMMARY.md:
- Read what was built, files modified, and the plan's `must_haves`
- Generate 1-3 test scenarios that require HUMAN verification (not automated checks)
- Minimum 1 test per plan, even for pure refactors (use "verify nothing broke" regression test)
- Tests should walk through real changes: run commands, check output, open files, verify behavior
- Test IDs follow the format: `P{plan}-T{N}` (e.g., P01-T1, P01-T2, P02-T1)

Write the initial `{phase}-UAT.md` in the phase directory using the `templates/UAT.md` format:
- Populate YAML frontmatter: phase, plan_count, status=in_progress, started=today, total_tests
- Write all test entries with Result fields empty

### 4. CHECKPOINT loop (one test at a time)

For each test without a result, display a CHECKPOINT block:

```
┌─ CHECKPOINT {N}/{total} ──────────────────────┐
│  Plan: {plan-id} -- {plan-title}               │
│                                                │
│  {scenario description}                        │
│                                                │
│  Expected: {expected result}                   │
└────────────────────────────────────────────────┘
```

Wait for the user's response via natural conversation (do NOT use AskUserQuestion).

### 5. Response mapping (string matching, not LLM)

Map the user's response using case-insensitive, trimmed string matching:

**Pass words:** pass, passed, yes, y, good, ok, okay, works, correct, confirmed, lgtm, looks good

**Skip words:** skip, skipped, next, n/a, na, later, defer

**Anything else:** treat the entire response text as an issue description.

### 6. Issue handling (when response = issue)

The user's response text IS the issue description. Infer severity from keywords (never ask the user):

| Keywords | Severity |
|----------|----------|
| crash, broken, error, doesn't work, fails, exception | critical |
| wrong, incorrect, missing, not working, bug | major |
| minor, cosmetic, nitpick, small, typo, polish | minor |
| (no keyword match) | major |

Record: description, inferred severity.

Display:
```
Issue recorded (severity: {level}). Final next-step routing shown at UAT summary.
```

### 7. After each response: persist immediately

- Update `{phase}-UAT.md` with the result for this test
- Write the file to disk (survives /clear)
- Display progress: `✓ {completed}/{total} tests`

### 8. Session complete

- Update `{phase}-UAT.md` frontmatter: status (complete or issues_found), completed date, final counts
- Display summary:

```
┌──────────────────────────────────────────┐
│  Phase {N}: {name} -- UAT Complete       │
└──────────────────────────────────────────┘

  Result:   {✓ PASS | ✗ ISSUES FOUND}
  Passed:   {N}
  Skipped:  {N}
  Issues:   {N}

  Report:   {path to UAT.md}

```

**Discovered Issues:** If the user reported failures or bugs during CHECKPOINT responses that are clearly unrelated to this phase's work (e.g., "this other test was already broken"), extract structured fields on a best-effort basis: use the test name if mentioned (or infer from context), the file path if identifiable, and the error text as reported. If the user's description is too vague to extract a test name or file, use the description verbatim as the error field and mark test/file as "unknown". De-duplicate by test name and file. Cap the list at 20 entries; if more exist, show the first 20 and append `... and {N} more`. Append after the result box:
```text
  Discovered Issues:
    ⚠ testName (path/to/file): error message
    ⚠ testName (path/to/file): error message
  Suggest: /vbw:todo <description> to track
```
This is **display-only**. Do NOT edit STATE.md, do NOT add todos, do NOT invoke /vbw:todo, and do NOT enter an interactive loop. The user decides whether to track these. If no discovered issues: omit the section entirely. After displaying discovered issues, STOP. Do not take further action.

- If issues found:
  - Any issue severity is `critical` or `major`:
    - `Suggest /vbw:vibe to continue UAT remediation directly from {phase}-UAT.md`
  - All issues are `minor`:
    - `Suggest /vbw:fix to address recorded issues.`

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh verify {result} {phase}` and display.

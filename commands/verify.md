---
name: vbw:verify
category: monitoring
description: Run human acceptance testing on completed phase work. Presents CHECKPOINT prompts one at a time.
argument-hint: "[phase-number] [--resume]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
---

# VBW Verify: $ARGUMENTS

## Context

Working directory:
```bash
!`pwd`
```
Plugin root:
```bash
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(ls -1d "${VBW_CACHE_ROOT}"/* 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(ls -1d "${VBW_CACHE_ROOT}"/* 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | sed -n 's/.*--plugin-dir  *\([^ ]*\).*/\1/p' | head -1); [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; rm -f "$LINK"; ln -s "$R" "$LINK" 2>/dev/null || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```

Current state:
```bash
!`head -40 .vbw-planning/STATE.md 2>/dev/null || echo "No state found"`
```

Config: Pre-injected by SessionStart hook.

Phase directories:
```bash
!`ls .vbw-planning/phases/ 2>/dev/null || echo "No phases directory"`
```

Phase state:
```bash
!`L="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; bash "$L/scripts/phase-detect.sh" 2>/dev/null || echo "phase_detect_error=true"`
```

!`L="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; bash "$L/scripts/suggest-compact.sh" verify 2>/dev/null || true`

## Guard

- Not initialized (no .vbw-planning/ dir): STOP "Run /vbw:init first."
- No SUMMARY.md in phase dir: STOP "Phase {N} has no completed plans. Run /vbw:vibe first."
- **Auto-detect phase** (no explicit number): Phase detection is pre-computed in Context above. Use `next_phase` and `next_phase_slug` for the target phase. To find the first phase needing UAT: scan phase dirs for first with `*-SUMMARY.md` but no `*-UAT.md`. Found: announce "Auto-detected Phase {N} ({slug})". All verified: STOP "All phases have UAT results. Specify: `/vbw:verify N`"

## Steps

### 1. Resolve phase and load summaries

- Parse explicit phase number from $ARGUMENTS, or use auto-detected phase
- Use `.vbw-planning/phases/` for phase directories
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
- Generate 1-3 test scenarios that require HUMAN judgment — things only a person can verify
- Minimum 1 test per plan, even for pure refactors (use "verify nothing broke" regression test)
- Test IDs follow the format: `P{plan}-T{N}` (e.g., P01-T1, P01-T2, P02-T1)

**UAT tests must be things only a human can judge.** Good examples:
- Open the app and navigate to screen X — does it display Y correctly?
- Perform user workflow A → B → C — does the result look right?
- Check that the UI reflects the change — is the label/value/layout correct?

**NEVER generate tests that ask the user to run automated checks.** These belong in the QA phase, not UAT:
- ✗ Run a test suite or individual test (xcodebuild test, pytest, bats, jest, etc.)
- ✗ Run a CLI command and check its exit code or output
- ✗ Execute a script and verify it passes
- ✗ Run a linter, type-checker, or build command

If a plan only contains backend/test/script changes with no user-facing behavior, generate a scenario that asks the human to verify the *effect* is visible (e.g., "confirm the migration preview no longer shows phantom entries") rather than asking them to run the tests themselves.

Write the initial `{phase}-UAT.md` in the phase directory using the `templates/UAT.md` format:
- Populate YAML frontmatter: phase, plan_count, status=in_progress, started=today, total_tests
- Write all test entries with Result fields empty

### 4. CHECKPOINT loop (one test at a time — conversational, blocking)

**This is a conversational loop. Present ONE test, then STOP and wait for the user to respond. Do NOT present multiple tests at once. Do NOT skip ahead. Do NOT end the session after presenting a test.**

For the FIRST test without a result, display a CHECKPOINT followed by AskUserQuestion:

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  CHECKPOINT {N}/{total} — {plan-id}: {plan-title}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{scenario description}
```

Then immediately use AskUserQuestion:

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

After response: process (Step 5), persist (Step 7), then present the NEXT test. Repeat until all tests are done, then go to Step 8.

### 5. Response mapping

Map the AskUserQuestion response:

**"Pass" selected:** Record as passed.

**"Skip" selected:** Record as skipped.

**Freeform text (via "Other"):** Apply case-insensitive, trimmed string matching:
- **Skip words:** skip, skipped, next, n/a, na, later, defer → record as skipped
- **Anything else:** treat the entire response text as an issue description.

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
```text
Issue recorded (severity: {level}). Final next-step routing shown at UAT summary.
```

### 7. After each response: persist immediately

- Update `{phase}-UAT.md` with the result for this test
- Write the file to disk (survives /clear)
- Display progress: `✓ {completed}/{total} tests`

### 8. Session complete

- Update `{phase}-UAT.md` frontmatter: status (complete or issues_found), completed date, final counts
- Display summary:

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Phase {N}: {name} — UAT Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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

Run `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/suggest-next.sh verify {result} {phase}` and display.

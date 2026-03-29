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
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}" && break; done; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || { echo "VBW: plugin root canonicalization failed" >&2; exit 1; }; bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$LINK" "$REAL_R" >/dev/null 2>&1 || { echo "VBW: plugin root link failed" >&2; exit 1; }; bash "$LINK/scripts/phase-detect.sh" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt" 2>/dev/null || echo "phase_detect_error=true" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; echo "$LINK"`
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
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"
P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"
PD=""
_refresh_phase_detect() {
  local VBW_CACHE_ROOT R V D REAL_R
  VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"
  R=""
  if [ -z "$R" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi
  if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi
  if [ -z "$R" ]; then
    V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
    [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"
  fi
  if [ -z "$R" ]; then
    V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1)
    [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"
  fi
  if [ -z "$R" ]; then
    for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do
      [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}" && break
    done
  fi
  if [ -z "$R" ]; then
    D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1)
    D="${D#--plugin-dir }"
    [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"
  fi
  if [ -z "$R" ] || [ ! -d "$R" ] || [ ! -f "$R/scripts/phase-detect.sh" ]; then
    return 1
  fi
  REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || return 1
  bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$L" "$REAL_R" >/dev/null 2>&1 || true
  PD=$(bash "$REAL_R/scripts/phase-detect.sh" 2>/dev/null) || PD=""
  if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then
    return 1
  fi
  printf '%s' "$PD" > "$P"
  return 0
}
if ! _refresh_phase_detect; then
  PD="phase_detect_error=true"
  printf '%s\n' "$PD" > "$P"
fi
[ -f "$P" ] && PD=$(cat "$P")
if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then
  printf '%s' "$PD"
else
  echo "phase_detect_error=true"
fi`
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
- **Auto-detect phase** (no explicit number): Phase detection is pre-computed in Context above. Use `next_phase` and `next_phase_slug` for the target phase.
  - If `next_phase_state=needs_qa_remediation`, target that phase directly.
    - If the remediation stage is `plan` or `execute`, STOP and tell the user to run `/vbw:vibe` to continue QA remediation first — standalone QA must not mint a round VERIFICATION before re-verification is actually ready.
    - If the remediation stage is `verify` or `done`, standalone QA re-verifies the authoritative round artifact rather than overwriting the frozen phase-level VERIFICATION.
  - If `first_qa_attention_phase` is set and `qa_attention_status` is `pending` or `failed`, target that phase directly — existing QA artifacts may be stale or failed even when a file already exists and even when terminal UAT already exists.
  - Otherwise, to find the first phase needing QA: scan phase dirs for first with completed `*-SUMMARY.md` files but no authoritative QA verification artifact (no numbered final VERIFICATION, no brownfield plain `VERIFICATION.md`, no wave fallback). Found: announce "Auto-detected Phase {NN} ({slug})". All verified: STOP "All phases verified. Specify: `/vbw:qa {NN}`"
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
    - Resolve the VERIFICATION output path before spawning QA:

        ```bash
        QA_STATE=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/qa-remediation-state.sh get "{phase-dir}" 2>/dev/null || true)
        QA_STAGE=$(printf '%s\n' "$QA_STATE" | head -1)
        VERIF_PATH=$(printf '%s\n' "$QA_STATE" | awk -F= '/^verification_path=/{print $2; exit}')
        case "$QA_STAGE" in
          verify) ;;
          done)
            VERIF_PATH=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-verification-path.sh current "{phase-dir}" 2>/dev/null || true)
            [ -n "$VERIF_PATH" ] && [ ! -f "$VERIF_PATH" ] && VERIF_PATH=""
            ;;
          plan|execute)
            echo "Phase {NN} has active QA remediation at stage ${QA_STAGE}. Run /vbw:vibe to continue remediation before standalone QA." >&2
            exit 1
            ;;
          *) VERIF_PATH="" ;;
        esac
        if [ -z "$VERIF_PATH" ]; then
          VERIF_NAME=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-artifact-path.sh verification "{phase-dir}")
          VERIF_PATH="{phase-dir}/${VERIF_NAME}"
        fi
        ```

    - Before composing the QA task description, evaluate installed skills visible in your system context — read each skill's description and determine if it is relevant to verifying this phase's work. If any skills are relevant, the QA prompt MUST start with `<skill_activation>{For each relevant skill: "Call Skill({skill-name})"}</skill_activation>`. Only include skills whose description matches the verification task. If no skills are relevant, omit the skill_activation block entirely.

    - Also evaluate available MCP tools in your system context. If any MCP servers provide build, test, documentation, or domain-specific capabilities relevant to verification, note them in the QA task context.

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
        Persist your VERIFICATION.md by piping qa_verdict JSON through write-verification.sh. Output path: {VERIF_PATH}. Plugin root: `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`.
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

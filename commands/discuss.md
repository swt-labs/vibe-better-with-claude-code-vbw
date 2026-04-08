---
name: vbw:discuss
category: lifecycle
description: "Start or continue phase discussion to build context before planning."
argument-hint: "[N] [--assumptions]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, LSP
disable-model-invocation: true
---

# VBW Discuss: $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then f=$( (unsetopt nomatch 2>/dev/null || true; ls -d /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh 2>/dev/null) | head -1); [ -n "$f" ] && [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}"; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || { echo "VBW: plugin root canonicalization failed" >&2; exit 1; }; bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$LINK" "$REAL_R" >/dev/null 2>&1 || { echo "VBW: plugin root link failed" >&2; exit 1; }; bash "$LINK/scripts/phase-detect.sh" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt" 2>/dev/null || echo "phase_detect_error=true" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; echo "$LINK"`
```

Phase state:
```
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
    f=$( (unsetopt nomatch 2>/dev/null || true; ls -d /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh 2>/dev/null) | head -1)
    [ -n "$f" ] && [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}"
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

!`L="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; bash "$L/scripts/suggest-compact.sh" discuss 2>/dev/null || true`

## Guards

- No `.vbw-planning/` directory: STOP "Run /vbw:init first."
- No phases in ROADMAP.md: STOP "No phases defined. Run /vbw:vibe first."

## Phase Resolution

1. If `$ARGUMENTS` contains a number N, target phase N.
2. If the target phase has a `*-CONTEXT.md` file with `pre_seeded: true` in its YAML frontmatter (remediation phase): WARN the user that this phase has pre-seeded UAT context and ask whether they want to re-discuss (which overwrites the pre-seeded content) or skip discussion and proceed to planning.
3. If the target phase has a `*-CONTEXT.md` file WITHOUT `pre_seeded: true` (organic discussion already happened): This is a **continuation discussion**. Display: "Phase {NN} already has discussion context. Continuing to explore additional topics." The Discussion Engine's Step 1.5 will handle loading existing decisions as baseline.
4. If no target was set by step 1 (no explicit phase number): auto-detect by finding the first phase directory without a `*-CONTEXT.md` file. If all phases already have context: STOP "All phases discussed. Specify a phase number to deepen an existing discussion."

## Discussion Mode Resolution

Determine the discussion mode before invoking the engine:

1. If `$ARGUMENTS` contains `--assumptions` → mode is `assumptions`
2. Else read `discussion_mode` from `.vbw-planning/config.json` (via `jq -r '.discussion_mode // "questions"'`)
3. If config value is `"assumptions"` → mode is `assumptions`
4. If config value is `"auto"` and `.vbw-planning/codebase/META.md` exists → mode is `assumptions`
5. Otherwise → mode is `questions`

Pass the resolved mode to the engine: "Discussion mode: {resolved_mode}"

## Execute

Read ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/discussion-engine.md` and follow its protocol for the target phase. The engine's Step 1.7 uses the resolved discussion mode to branch between assumptions and questions paths.

## After Discussion

**Discussion commit boundary (conditional):**
```bash
PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
if [ -f "$PG_SCRIPT" ]; then
  bash "$PG_SCRIPT" commit-boundary "discuss phase {NN}" .vbw-planning/config.json
else
  echo "VBW: planning-git.sh unavailable; skipping planning git boundary commit" >&2
fi
```
Behavior: `planning_tracking=commit` commits `{NN}-CONTEXT.md` and `discovery.json` if changed. Other modes no-op.

Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh discuss`.

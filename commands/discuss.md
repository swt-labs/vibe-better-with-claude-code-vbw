---
name: vbw:discuss
category: lifecycle
description: "Start or continue phase discussion to build context before planning."
argument-hint: "[N]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
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
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}" ]; then R="${CLAUDE_PLUGIN_ROOT}"; elif [ -d "${VBW_CACHE_ROOT}/local" ]; then R="${VBW_CACHE_ROOT}/local"; else V=$(ls -1d "${VBW_CACHE_ROOT}"/* 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && R="${VBW_CACHE_ROOT}/${V}"; if [ -z "$R" ]; then L=$(ls -1d "${VBW_CACHE_ROOT}"/* 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; rm -f "$LINK"; ln -s "$R" "$LINK" 2>/dev/null || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```

Phase state:
```
!`bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/phase-detect.sh 2>/dev/null || echo "phase_detect_error=true"`
```

!`bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/suggest-compact.sh discuss 2>/dev/null || true`

## Guards

- No `.vbw-planning/` directory: STOP "Run /vbw:init first."
- No phases in ROADMAP.md: STOP "No phases defined. Run /vbw:vibe first."

## Phase Resolution

1. If `$ARGUMENTS` contains a number N, target phase N.
2. If the target phase has a `*-CONTEXT.md` file with `pre_seeded: true` in its YAML frontmatter (remediation phase): WARN the user that this phase has pre-seeded UAT context and ask whether they want to re-discuss (which overwrites the pre-seeded content) or skip discussion and proceed to planning.
3. Otherwise auto-detect: find the first phase directory without a `*-CONTEXT.md` file. If all phases already have context: STOP "All phases discussed."

## Execute

Read ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/discussion-engine.md` and follow its protocol for the target phase.

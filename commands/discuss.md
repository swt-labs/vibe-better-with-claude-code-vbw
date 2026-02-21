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

Working directory: `!`pwd``
Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(bash -c 'ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1')}``

Phase state:
```
!`bash ${CLAUDE_PLUGIN_ROOT:-$(bash -c 'ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1')}/scripts/phase-detect.sh 2>/dev/null || echo "phase_detect_error=true"`
```

!`bash ${CLAUDE_PLUGIN_ROOT:-$(bash -c 'ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1')}/scripts/suggest-compact.sh discuss 2>/dev/null || true`

## Guards

- No `.vbw-planning/` directory: STOP "Run /vbw:init first."
- No phases in ROADMAP.md: STOP "No phases defined. Run /vbw:vibe first."

## Phase Resolution

1. If `$ARGUMENTS` contains a number N, target phase N.
2. If the target phase has a `*-CONTEXT.md` file with `pre_seeded: true` in its YAML frontmatter (remediation phase): WARN the user that this phase has pre-seeded UAT context and ask whether they want to re-discuss (which overwrites the pre-seeded content) or skip discussion and proceed to planning.
3. Otherwise auto-detect: find the first phase directory without a `*-CONTEXT.md` file. If all phases already have context: STOP "All phases discussed."

## Execute

Read `${CLAUDE_PLUGIN_ROOT}/references/discussion-engine.md` and follow its protocol for the target phase.

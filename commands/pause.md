---
name: vbw:pause
category: supporting
disable-model-invocation: true
description: Save session notes for next time (state auto-persists).
argument-hint: [notes]
allowed-tools: Read, Write
---

# VBW Pause: $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```

## Guard

Bind `PLANNING_ROOT=$(bash "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-planning-root.sh" 2>/dev/null || echo .vbw-planning)` and use `"$PLANNING_ROOT/..."` for every subsequent path reference in this command.

1. **Guard:**
   - `"$PLANNING_ROOT/config.json"` missing AND `"$(dirname "$PLANNING_ROOT")"` equals cwd (truly uninitialized): STOP "Run /vbw:init first."
   - `"$PLANNING_ROOT/config.json"` exists AND `"$(dirname "$PLANNING_ROOT")"` is an ancestor of cwd: NOTE "◆ VBW: planning found at $PLANNING_ROOT — paths resolved from there." CONTINUE.
   - `"$PLANNING_ROOT/config.json"` exists AND `"$(dirname "$PLANNING_ROOT")"` equals cwd: proceed normally.

## Steps

1. **Write notes:** If $ARGUMENTS has notes: write `"$PLANNING_ROOT/RESUME.md"` with timestamp + notes + resume hint. If no notes: skip write.
2. **Present:** Phase Banner "Session Paused". Show notes path if saved. "State is always saved in $PLANNING_ROOT. Nothing to lose, nothing to remember." Next Up: /vbw:resume.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — double-line box, ➜ Next Up, no ANSI.

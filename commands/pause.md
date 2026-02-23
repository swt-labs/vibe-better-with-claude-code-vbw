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

1. **Not initialized** (no .vbw-planning/ dir): STOP "Run /vbw:init first."

## Steps

1. **Write notes:** If $ARGUMENTS has notes: write `.vbw-planning/RESUME.md` with timestamp + notes + resume hint. If no notes: skip write.
2. **Present:** Phase Banner "Session Paused". Show notes path if saved. "State is always saved in .vbw-planning/. Nothing to lose, nothing to remember." Next Up: /vbw:resume.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — double-line box, ➜ Next Up, no ANSI.

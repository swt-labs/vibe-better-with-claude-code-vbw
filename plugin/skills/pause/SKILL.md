---
name: pause
description: Stop for now safely - VBW checks nothing is left half-done and notes where you are, so /vbw:resume picks up exactly there.
argument-hint: "[anything to remember]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" status 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" next 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

VBW keeps its state in `.vbw/`; nothing needs saving. Make the stop clean:

1. A VBW workflow still running: it finishes in the background if the session
   stays open; if they close Claude Code, its unfinished plans return to the
   next wave on resume.
2. Uncommitted changes outside VBW's files (`git status`): tell them.
3. Anything they asked to remember ($ARGUMENTS): park it with
   `vbw todo add "<it>"`, or record a decision with `vbw decide`.
4. Say where things stand and what comes next; `/vbw:resume` picks up from here.

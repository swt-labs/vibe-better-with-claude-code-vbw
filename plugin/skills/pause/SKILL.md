---
name: pause
description: Stop for now safely - VBW checks nothing is left half-done and notes where you are, so /vbw:resume picks up exactly there.
argument-hint: "[anything to remember]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" status 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" next 2>&1 || true
```

VBW keeps its state in `.vbw/` as it goes, so nothing needs saving. Make sure
the stop is clean:

1. A VBW workflow still running in this session: say it will finish in the
   background if the session stays open; if they close Claude Code now, its
   unfinished plans simply go back to the next wave on resume.
2. Uncommitted changes outside VBW's own files (`git status`): tell them, so
   nothing is lost by surprise.
3. Anything they asked to remember ($ARGUMENTS): park it with
   `vbw todo add "<it>"`, or record a decision with `vbw decide`.
4. Say where things stand and what comes next (above), and that `/vbw:resume`
   picks up from here.

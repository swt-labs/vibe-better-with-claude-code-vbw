---
name: resume
description: Pick up where you left off - where the project stands, what was decided, and the next step.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" status 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" next 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" show decisions 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" todo list 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

In a few plain lines: where the project stands, the latest decisions that
matter, ideas parked for later, and the next step. If a run was interrupted
(next says `run`), say its unfinished work goes back to the next wave. Then ask whether to continue; on yes, continue with the `vbw:vibe`
skill.

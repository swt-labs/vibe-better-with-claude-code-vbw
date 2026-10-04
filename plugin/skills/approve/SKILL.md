---
name: approve
description: Approve the VBW contract (requirements, checks, plans) and the project commands it may run. Only the user can run this.
disable-model-invocation: true
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

The user approved the VBW contract. Result:

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" approve 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

Tell the user in one or two sentences what this means (from the output above;
if it refused, say exactly why and what to do). If it succeeded, continue with
the VBW loop: use the `vbw:vibe` skill.

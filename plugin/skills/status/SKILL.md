---
name: status
description: Where this VBW project stands - progress, the roadmap and the next step. Reads only.
effort: low
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" status 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" show roadmap 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" next 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

Summarize the above for the user in at most six lines: progress, what is done,
what is next and whether it needs them. Change nothing.

---
name: list-todos
description: List the ideas parked for later, with what you can do with each.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" todo list 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

Show the list above in plain words. Then say what they can do with any item:
bring it into the current work (`/vbw:discuss` or `/vbw:vibe` with the idea),
mark it done (`vbw todo done <id>`), or drop it (`vbw todo drop <id>`). New
ideas: `/vbw:todo <idea>`.

---
name: whats-new
description: What changed in VBW, newest first.
effort: low
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

Read `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` and tell the user what is new in the
latest version, in plain words: what they can do now that they could not
before, and anything they need to do. Mention earlier versions only if asked.

---
name: panel
description: Check whether the VBW panel and its sound work on this Claude Code.
effort: low
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Bash(claude --version)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

Run `claude --version`. The panel and its sound need Claude Code 2.1.287 or newer.

- Older: say they are not available, give the version, tell the user to run `claude update` and restart. The rest of VBW works unchanged.
- Newer: say the panel is available. `/vbw-panel` opens it; `/vbw-sound` turns the "needs you" sound on or off (or one click in the panel). The choice is kept in the user's own settings, never in the project.

If they do not respond on a new enough version, suggest `/vbw:doctor`.

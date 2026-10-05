---
name: panel
description: Check whether the VBW panel and its "needs you" sound work on this Claude Code, and how to use them.
effort: low
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Bash(claude --version)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

Run `claude --version`. The panel and its sound need Claude Code 2.1.287 or
newer.

- Older version: say plainly that the panel and the sound are not available
  yet, give the version found, and tell the user to update Claude Code
  (`claude update`, or reinstall the way they installed it), then restart.
  Everything else in VBW works unchanged.
- 2.1.287 or newer: say the panel is available. `/vbw-panel` opens or closes
  it. `/vbw-sound` turns the "needs you" sound on or off (also one click in the
  panel); the choice is remembered, kept in the user's own settings, never in
  the project or its record.

If the panel or `/vbw-panel` does not respond on a new enough version, say so
and suggest `/vbw:doctor`.

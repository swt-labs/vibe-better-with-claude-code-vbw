---
name: update
description: Update VBW to the latest version.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Bash(claude plugin *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

Update with Claude Code's own plugin commands, one at a time:

1. `claude plugin marketplace update vbw-marketplace`
2. `claude plugin update vbw@vbw-marketplace`

Then tell the user to run `/reload-plugins` (or restart Claude Code) so the new
version loads, and to run `/vbw:whats-new` to see what changed. If a command
fails, show its output and suggest `/plugin` to update from the menu.

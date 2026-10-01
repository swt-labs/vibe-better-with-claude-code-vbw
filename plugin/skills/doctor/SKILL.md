---
name: doctor
description: Check that everything VBW needs is in place (tools, Claude Code version, workflows, status line, the project) and fix what is wrong.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" doctor 2>&1 || true
```

Summarize the result for the user in plain words: say it is all fine, or list
what is wrong with its fix. Offer to run any fix that is a `vbw` command. A fix
in Claude Code's own settings (`/config`) is theirs to make; say where.

---
name: uninstall
description: Remove VBW from Claude Code - the status line setting first, then the plugin; project files stay.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Bash(claude plugin *)
disable-model-invocation: true
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" statusline status 2>&1 || true
```

Confirm with the user first (AskUserQuestion: "Remove VBW" or "Cancel"). Then:

1. `vbw statusline off` (restores the status line they had before VBW, if any).
2. `claude plugin uninstall vbw@vbw-marketplace`.

Tell them that each project's `.vbw/` folder (their spec, plan and history)
is left untouched and is theirs to keep or delete, and to restart Claude Code.

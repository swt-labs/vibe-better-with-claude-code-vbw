---
name: rtk
description: Set up, check or remove RTK, a third-party tool that compresses command output to save tokens; uses RTK's own official installer.
argument-hint: "[status | install | uninstall]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" rtk 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

The user said: $ARGUMENTS

RTK (https://github.com/rtk-ai/rtk) shrinks command output before it reaches
the context, through its own Claude Code hook. VBW's guard judges the command inside `rtk ...`.

- **status** (or nothing asked): explain the state and each action; ask what they want.
- **install**: only with the user's yes, run the "install with" command shown
  above if RTK is not installed, then `rtk init -g` (RTK adds its own hook to
  the user's Claude settings), then `rtk --version` and `rtk gain` to confirm.
  Tell them to restart Claude Code. Never use `sudo` or pipe a downloaded script
  into a shell.
- **uninstall**: with the user's yes, `rtk init -g --uninstall` removes the hook;
  removing the program itself is `brew uninstall rtk` or `cargo uninstall rtk`,
  only if they ask.

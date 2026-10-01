---
name: todo
description: Keep an idea for later in the VBW backlog, or list the backlog.
argument-hint: "[the idea]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
effort: low
---

The user said: $ARGUMENTS

If they gave an idea, add it with `vbw todo add "<the idea, in their words>"`.
Then show the backlog (`vbw todo list`). To finish or drop an item: `vbw todo
done <id>` or `vbw todo drop <id>`. Backlog items never enter the current work
by themselves.

---
name: init
description: Set up VBW in this git repository (.vbw/ with the spec and the plan of record) and the VBW status line, then start agreeing on what to build.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" init 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" statusline on 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" workflows on 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

Tell the user in a few lines what was set up (from the output above),
including the VBW status line (if it replaced theirs, say `vbw statusline off`
brings theirs back). If project commands were detected, say they run only after
the user approves them. If VBW needs a git repository, offer `git init`.

Headless use (`claude -p`, CI) needs one allow rule per workflow; mention only
if asked: `Workflow(vbw:mapping)`, `Workflow(vbw:planning)`, `Workflow(vbw:verifying)`, `Workflow(vbw:researching)`,
`Workflow(vbw:building)`, `Workflow(vbw:fixing)`, `Workflow(vbw:investigating)`.

Then continue with the `vbw:vibe` skill, which starts the spec conversation.

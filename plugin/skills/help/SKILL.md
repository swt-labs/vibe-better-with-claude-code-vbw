---
name: help
description: What VBW does and every VBW command, with when to use each.
effort: low
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

Show the user this, as is:

**VBW turns what you want into proven, committed work.** You agree on
requirements and decide; VBW plans them with tests, you approve, VBW builds in
parallel and proves each requirement, you check what only a person can judge,
and you ship.

| Command | What it does |
|---|---|
| **Everyday** | |
| `/vbw:vibe [what you want]` | The one command: takes the project to its next step, stops when it needs you |
| `/vbw:approve` | Approve the plan, its tests and the commands it may run (only you can) |
| `/vbw:status` | Where the project stands |
| **Think and decide** | |
| `/vbw:discuss [topic]` | Think something through; the outcome is recorded |
| `/vbw:research [question]` | A sourced answer with a recommendation |
| `/vbw:todo [idea]`, `/vbw:list-todos` | Park an idea for later; see the list |
| **Check the work** | |
| `/vbw:qa` | Run every proof now and explain the result |
| `/vbw:verify` | Check, one at a time, what only you can judge |
| `/vbw:debug [the problem]` | Find a bug's root cause |
| `/vbw:fix [what]` | A quick fix without planning; proofs re-run after |
| **Your project** | |
| `/vbw:init` | Set up VBW and its status line |
| `/vbw:convert` | Bring a VBW 1 project into VBW 2 |
| `/vbw:map` | Map an existing codebase |
| `/vbw:teach [convention]` | Teach VBW your project's conventions |
| `/vbw:pause`, `/vbw:resume` | Stop safely; pick up where you left off |
| **Settings and tools** | |
| `/vbw:profile [careful/standard/fast]` | Models, autonomy and how VBW talks to you, in one switch |
| `/vbw:config` | Each setting on its own |
| `/vbw:skills`, `/vbw:rtk`, `/vbw:compress` | Community skills; token-saving compression |
| `/vbw:doctor` | Check VBW's setup |
| `/vbw:panel` | Whether the panel and its "needs you" sound work here; `/vbw-panel` and `/vbw-sound` use them |
| `/vbw:report` | Prepare a bug report (you see it first) |
| `/vbw:update`, `/vbw:whats-new`, `/vbw:uninstall` | Update VBW, see what changed, remove it |

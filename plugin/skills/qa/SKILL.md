---
name: qa
description: Check the finished work now - run every proof and explain in plain words what passes, what fails and what only you can judge.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" show requirements 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

1. If the contract is approved, run `vbw prove`; otherwise say the plan and its
   tests need `/vbw:approve` first, and stop.
2. Explain the result in plain words, requirement by requirement: proven,
   failing (with the reason from `vbw show evidence`), or still being built.
   Name any failed project command and any commit that changed files outside
   its plan (`vbw show evidence`).
3. The `[human]` requirements no check can prove: list the ones whose work is
   built (`built` above) and offer `/vbw:verify` to check them now.
4. If something fails, say what happens next: `/vbw:vibe` fixes failures
   (each becomes a fix item, worked and proved again).

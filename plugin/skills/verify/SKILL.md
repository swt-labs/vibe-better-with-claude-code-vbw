---
name: verify
description: Check, one at a time, the things only you can judge (look, feel, wording) for the work that is built, and record your verdict.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" show requirements 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

The requirements to check are the `[human, open]` or `[human, rejected]` ones
marked `built` above. None: say what is still being built and stop.

For each one, one at a time: show the user the thing to judge. Run it yourself
when you can (the program's actual output, the page's text) and put that, or
one concrete thing to try, in the question and the `preview` of "Works".
Something visual: if you can, save a screenshot in `.vbw/runtime/` and open it
for the user (`open`, `xdg-open`); otherwise give the exact way to see it. Ask with
AskUserQuestion: "Works", "Something's wrong", "Skip for now".

- Works: `vbw req accept <id>`.
- Something's wrong: ask what, in their words, then
  `vbw req reject <id> "<their words>"` (VBW fixes it and asks again).
- Skip: leave it.

Close with what was accepted and what goes back for fixing; `/vbw:vibe` continues.

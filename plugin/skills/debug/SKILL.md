---
name: debug
description: Investigate a bug from three angles at once (reproduce, trace the code, recent changes) and get its root cause with evidence and a proposed fix.
argument-hint: "[what is wrong]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Workflow(vbw:investigating)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config models 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" workflows on 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words), and pass them to the workflow as `"profile": {"level", "depth", "involvement"}` (none for "-").

The problem, in the user's words: $ARGUMENTS

If that is empty, ask what is wrong (what they did, what happened, what they
expected). VBW needs the Workflow tool: the `workflows` line above turns it on
(say so in one line when it did); without it, say why and stop. (Outside a VBW
project omit `models`.)

Start the Workflow `vbw:investigating` with args `{"problem": "<the problem>",
"models": <the JSON above>, "profile": ...}`. When it returns, tell the user the root cause,
its evidence, rejected hypotheses, confidence and the proposed fix, then ask whether to fix it now. If yes, start the Workflow again
with args `{"problem": "<the problem>", "fix": <the diagnosis it returned>,
"models": ..., "profile": ...}`: one Debugger fixes the root cause, adds a regression test,
commits and verifies (`vbw prove` in a VBW project). Report what changed.

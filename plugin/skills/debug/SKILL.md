---
name: debug
description: Investigate a bug from three angles at once (reproduce, trace the code, recent changes) and get its root cause with evidence and a proposed fix.
argument-hint: "[what is wrong]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Workflow(vbw:investigating)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config models 2>&1 || true
```

The problem, in the user's words: $ARGUMENTS

If that is empty, ask what is wrong (what they did, what happened, what they
expected) before anything else. VBW needs the Workflow tool; without it, tell
the user to turn on Dynamic workflows in /config and stop. (Outside a VBW
project the models line above shows an error; omit `models` then.)

Start the Workflow `vbw:investigating` with args `{"problem": "<the problem>",
"models": <the JSON above>}`. When it returns, tell the user the root cause,
the evidence for it, how confident it is, and the proposed fix, then ask
whether to make the fix now. If yes, make it as a normal change; in a VBW
project, run `vbw prove` afterwards so the evidence stays current.

---
name: whats-next
description: Have the Architect recommend what to do next (a top pick and up to two runners-up, each with a size) and store it. Used by the vibe router after a ship and when the user asks what's next.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Workflow(vbw:recommending)
effort: low
---

# What's next

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" triage --json 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config models 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config effort 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" suggest list 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Above: the open requirements and backlog (`summary`), the models, the effort table, the declined suggestions and the user's level, depth and involvement.

## Steps

1. The summary shows a run is open (`run` is not null): say so in one line and do not start. Stop here.
2. Otherwise run Workflow `vbw:recommending` with args `{"summary": <the triage JSON>, "declined": <declined suggestion texts>, "models": ..., "effort": ..., "profile": <the interview answers>}`. It starts no run.
3. Pipe its `recommendation` (JSON) to `vbw recommend`.
4. Show the what's-next part of `vbw status`.

## When it does not work

The workflow returns an error, or `vbw recommend` refuses: say so in one line, with the reason. The earlier recommendation stays. A ship that came first stays shipped (never undone). Do not retry and do not ask the user.

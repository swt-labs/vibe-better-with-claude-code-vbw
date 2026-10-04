---
name: map
description: Map an existing codebase (stack and commands, structure, conventions, tests, risks) so VBW plans fit the code; saves .vbw/map.md.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Workflow(vbw:mapping)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config models 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" workflows on 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words), and pass them to the workflow as `"profile": {"level", "depth", "involvement"}` (none for "-").

If this is not a VBW project yet ("not a VBW project" above), set it up first:
`vbw init` and `vbw statusline on`. VBW needs the Workflow tool: the
`workflows` line above turns it on (say so in one line when it did); without
it, say why and stop.

Run `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start map`, then start the Workflow `vbw:mapping` with args
`{"models": <the JSON above>, "profile": ...}`. When it returns, `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run end`, then write its `map` to `.vbw/map.md` (replacing any older map), then tell
the user in a few lines what the codebase is and how to build and test it, and
name any angle listed in `missing`. The Architect and Lead read this map when they plan.

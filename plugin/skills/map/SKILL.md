---
name: map
description: Map an existing codebase (stack and commands, structure, conventions, tests, risks) so VBW plans fit the code; saves .vbw/map.md.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Workflow(vbw:mapping)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config models 2>&1 || true
```

If this is not a VBW project yet ("not a VBW project" above), run `vbw init`
first. VBW needs the Workflow tool; without it, tell the user to turn on
Dynamic workflows in /config and stop.

Start the Workflow `vbw:mapping` with args `{"models": <the JSON above>}`. When it
returns, write its `map` to `.vbw/map.md` (replacing any older map), then tell
the user in a few lines what the codebase is and how to build and test it, and
name any angle listed in `missing`. The planner reads this map when it plans.

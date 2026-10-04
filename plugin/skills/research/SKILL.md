---
name: research
description: Research a question on the web, in documentation and in this project, and get a sourced answer with a recommendation (up to four Scouts in parallel).
argument-hint: "[the question]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Workflow(vbw:researching)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config models 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" workflows on 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

The question: $ARGUMENTS

If it is empty, ask what they want to find out. VBW needs the Workflow tool:
the `workflows` line above turns Dynamic workflows on (say so in one line when
it did); without the tool, say why and stop. (Outside a VBW project the models
line shows an error; omit `models` then.)

1. Say in one line what will be looked into, and why it matters here.
2. Start the Workflow `vbw:researching` with args `{"question": "<the
   question>", "models": <the JSON above>}`: four Scouts research it in parallel
   (official sources, practice, what is current, project fit); one weighs them.
3. Give the user its answer in plain words: what is true, options with trade-offs,
   the recommendation, sources with links, and what could not be confirmed
   (angles in `missing`).
4. If it settles a decision, offer to record it: `vbw decide "<decision>"
   "<why>"`. If it changes what to build, offer `/vbw:discuss` or `/vbw:vibe`.

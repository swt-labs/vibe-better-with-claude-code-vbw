---
name: report
description: Prepare a bug report or idea about VBW as a GitHub issue; you see the full text and decide before anything is sent.
argument-hint: "[what happened]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
disable-model-invocation: true
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" report 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

The user said: $ARGUMENTS

1. If it is unclear, ask what happened: what they did (which `/vbw:` command),
   what happened, what they expected. One question at a time.
2. Draft the issue for https://github.com/swt-labs/vibe-better-with-claude-code-vbw:
   a short title, then **What happened**, **Expected**, **Steps**, and the
   diagnostics above. Remove anything private (project names, home paths, tokens) and say what.
3. Ask (AskUserQuestion) with the complete title and body in the `preview` of
   "File it on GitHub": "File it on GitHub", "I'll file it myself", "Cancel".
4. File only on "File it on GitHub": `gh issue create -R swt-labs/vibe-better-with-claude-code-vbw --title ... --body-file <file>`
   and show the issue link. No `gh` or not logged in: give them the text and https://github.com/swt-labs/vibe-better-with-claude-code-vbw/issues/new
   instead. Never send anything without that confirmation.

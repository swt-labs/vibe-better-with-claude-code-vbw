---
name: skills
description: Look for the best tools for this project (safety scanners, code-quality tools, test frameworks, community skills), show a short sourced list and install only what the user approves.
argument-hint: "[what to search for]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Bash(npx skills *) Workflow(vbw:tooling)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config models 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config effort 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to user's level, explanation depth and involvement (above; "-": plain words). Explain every technical term and tool name at first use.

The user said: $ARGUMENTS

Runs any time, from any project state, whatever an earlier answer was ("no", "not yet" included): asking here is the yes.

1. Work out the stack: from `.vbw/map.md` if present, else the manifest files (package.json, pyproject.toml, Cargo.toml, go.mod, ...), plus what user asked. Name main language, frameworks, test tools. Stack cannot be determined: say so plainly, ask what is being built, do not search without it.
2. Record the yes: `vbw tools answer yes`. Start the `vbw:tooling` workflow with `args` `{"stack": "<the stack, one plain sentence>", "profile": <the profile above>, "models": <vbw config models>, "effort": <vbw config effort>}`. Four angles: code safety (security scanners), code quality (linters, formatters), tests (frameworks), community skills.
3. Show the short list (at most 6), plain words at user's level. Each: what it is, why it fits, where from, a link. Explain terms a beginner would not know.
4. A pick with a `warning` is from a source not a respected open-source project: show the warning in plain words beside it; user chooses keep, drop, or look further (rerun workflow for that angle).
5. AskUserQuestion: approve the list: approve all, choose which, or not yet. Nothing installed or downloaded before approval; "not yet" or decline installs nothing; partial approval installs only what was approved.
6. For each approved tool, AskUserQuestion: this project only or all projects. Install only approved: skill with `npx skills add <skill> -y` (`-g` for all projects); other tools as their docs say, to the chosen scope.
7. Workflow returns a `note` or `missing` angles (a Scout failed or found nothing): say so plainly, show what was found, install nothing for missing ones. Never show an error or stack trace; flow goes on. Nothing found at all: install nothing, say it.

End every stop with one plain line: "I need your ..." saying what VBW needs now (or nothing).

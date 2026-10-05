---
name: skills
description: Look for the best tools for this project (safety scanners, code-quality tools, test frameworks, community skills), show a short sourced list and install only what the user approves.
argument-hint: "[what to search for]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Bash(npx skills *) Workflow(vbw:tooling)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words). Explain every technical term and tool name the first time you use it.

The user said: $ARGUMENTS

This runs at any time, from any state of the project, whatever an earlier
answer was ("no" or "not yet" included): asking for it here is the yes.

1. Work out the stack: from `.vbw/map.md` if it exists, otherwise from the
   project's manifest files (package.json, pyproject.toml, Cargo.toml, go.mod
   and so on), plus what the user asked for. Name the main language,
   frameworks and test tools. If it cannot be determined, say so plainly, ask
   what is being built, and do not start the search without it.
2. Record the yes: `vbw tools answer yes`. Then start the `vbw:tooling`
   workflow with `args` `{"stack": "<the stack, one plain sentence>", "profile": <the profile above>, "models": <vbw config models>}`.
   It looks at four angles: code safety (security scanners), code quality
   (linters, formatters), tests (frameworks), and community skills.
3. Show the short list (a handful, at most 6), in plain words at the user's
   level. For each: what it is, why it fits this project, where it came from,
   and a link. Explain terms and names a beginner would not know.
4. A pick with a `warning` is from a source that is not a respected open-source
   project: show the warning in plain words beside it and let the user choose:
   keep it, drop it, or look further (run the workflow again for that angle).
5. Ask with AskUserQuestion whether to approve the list: approve all, choose
   which, or not yet. Nothing is installed or downloaded until the user
   approves; "not yet" or a decline installs nothing, and a partial approval
   installs only what was approved.
6. For each approved tool, ask with AskUserQuestion whether it goes into this
   project only or into all projects. Install only the approved ones: a skill
   with `npx skills add <skill> -y` (add `-g` for all projects); other tools
   as their own docs say, to the chosen scope.
7. If the workflow returns a `note` or `missing` angles (a Scout failed or
   found nothing), say so plainly, show what was found, and install nothing
   for the missing ones. Never show an error or stack trace; the flow goes on.
   When nothing at all was found, install nothing and say it.

End every stop with one plain line: "I need your ..." saying what VBW needs
now (or that it needs nothing).

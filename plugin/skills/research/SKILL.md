---
name: research
description: Research a question on the web and in documentation, and get a sourced answer with a recommendation for this project.
argument-hint: "[the question]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) WebSearch WebFetch
---

The question: $ARGUMENTS

If it is empty, ask what they want to find out. Then:

1. Say in one line what you will look for, and why it matters for this project
   (read `.vbw/spec.md` and `vbw show decisions` when they exist).
2. Search the web and official documentation. Prefer primary sources (official
   docs, changelogs, the project's own repository) and recent ones; note dates
   where things change fast (versions, prices, limits).
3. Answer in plain words: what you found, the options with their trade-offs,
   and your recommendation for this project. List the sources with links. Say
   clearly what you could not confirm.
4. If it settles a decision, offer to record it: `vbw decide "<decision>"
   "<why>"`. If it changes what to build, offer `/vbw:discuss` or `/vbw:vibe`.

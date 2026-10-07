---
name: fix
description: Make a quick fix or small change without planning ceremony; VBW's guards stay on and every proof is re-run afterwards so nothing proven breaks.
argument-hint: "[what to fix or change]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" status 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

The user wants a quick change: $ARGUMENTS

If that is empty, ask what to fix. New user-visible behavior: recommend
`/vbw:vibe` instead, so it becomes a requirement with a check; do it as a
quick fix only if they still want that.

1. Find the cause before changing anything; say it in one or two sentences.
2. Make the smallest change that fixes it, in the code's existing style. Do not
   edit check test files (`vbw show contract` lists them): changing one changes
   the approved contract.
3. Run the project's own tests if they are quick. Commit the change yourself
   with a conventional message (`fix(scope): ...`), only the files you changed.
4. In a VBW project with an approved contract, run `vbw prove` and report: all
   proofs still pass, or which one this change broke (then fix it or revert).
5. Tell the user what changed, in plain words.

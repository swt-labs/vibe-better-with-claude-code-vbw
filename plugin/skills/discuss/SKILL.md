---
name: discuss
description: Think something through with VBW before building (a decision, an idea, a concern): plain questions, trade-offs, a recommendation, and the outcome recorded.
argument-hint: "[what to think through]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" status 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" show decisions 2>&1 || true
```

The user wants to think this through: $ARGUMENTS

If that is empty, ask what is on their mind, offering a few starting points
that fit the project's state: the next milestone, a technical choice, an idea,
a worry.

Your job is to help them decide well, not to decide for them. They may not know
what they don't know, so bring up what they haven't considered when it matters:
cost, where data lives and who sees it, security, effort to maintain, what is
hard to change later.

1. **Understand** first: read what you need (`.vbw/spec.md`, `.vbw/map.md`, the
   code) and say back in a sentence what you understood.
2. **Ask one question at a time** (AskUserQuestion), each with your
   recommendation first, marked "(Recommended)", and a plain trade-off for
   every option. Ask only what changes the outcome; stop when it is decided.
3. **Record the outcome**, and say what you recorded:
   - each decision: `vbw decide "<what was decided>" "<why>"`;
   - a new or changed requirement: `vbw spec add auto|human "<statement>"`, or
     edit `.vbw/spec.md` and run `vbw spec sync`; say that the plan's contract
     will need approval again;
   - an idea for later: `vbw todo add "<idea>"`.
4. **Close** with what was decided and what happens next; `/vbw:vibe`
   continues the work with it.

Outside a VBW project (the status above says so), discuss all the same, and
offer `/vbw:init` at the end so the decisions can be kept.

---
name: profile
description: Switch how VBW works in one go - which AI models it uses, how much it does on its own (Careful, Standard, Fast, or your own mix), and how it talks to you (your level, how much it explains, how much you decide).
argument-hint: "[careful | standard | fast]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

Write to the user's level, explanation depth and involvement.

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

The user said: $ARGUMENTS

Output above says not a VBW project: set up first (`vbw init` and `vbw statusline on`, one line saying so), then run `vbw config` again.

Presets (each sets two things with `vbw config set`):

| Preset | `profile` (models) | `autonomy` | Good for |
|---|---|---|---|
| Careful | `quality` (Opus for the Architect, Lead, Dev and Debugger) | `guided`: explains each step and waits for "go" | learning, a first project, risky changes |
| Standard | `balanced` (Opus for the Architect, Sonnet for the rest) | `balanced`: keeps going, stops for your decisions, approval, checking and shipping | most work (the default) |
| Fast | `budget` (Haiku for Scout, Sonnet for the rest, QA included) | `hands-off`: takes its own recommendations on decisions and lists them for you | small changes, once you trust it |

Preset named: apply it, show the result. Else show current settings and ask (AskUserQuestion) which preset, best fit first, or "My own mix" (then ask the two settings separately). Approval, checking and shipping always stop for the user.

Interview answers above (`vbw interview`) set how VBW talks to the user. Show them in plain words. To change one answer: ask which and its new value (AskUserQuestion; a wrong value's error lists allowed ones), change only that one answer:

- `vbw interview set level VALUE`
- `vbw interview set depth VALUE`
- `vbw interview set involvement VALUE`

Interview not done: say so, point to `/vbw:vibe`, which asks it.

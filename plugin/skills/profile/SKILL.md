---
name: profile
description: Switch how VBW works in one go - which AI models it uses, how much it does on its own (Careful, Standard, Fast, or your own mix), and how it talks to you (your level, how much it explains, how much you decide).
argument-hint: "[careful | standard | fast]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

The user said: $ARGUMENTS

If the output above says this is not a VBW project, set it up first (`vbw init`
and `vbw statusline on`, one line to say so), then run `vbw config` again.

Presets (each sets two things with `vbw config set`):

| Preset | `profile` (models) | `autonomy` | Good for |
|---|---|---|---|
| Careful | `quality` (Opus for the Architect, Lead, Dev and Debugger) | `guided`: explains each step and waits for "go" | learning, a first project, risky changes |
| Standard | `balanced` (Sonnet for every agent) | `balanced`: keeps going, stops for your decisions, approval, checking and shipping | most work (the default) |
| Fast | `budget` (Haiku for Scout, Sonnet for the rest, QA included) | `hands-off`: takes its own recommendations on decisions and lists them for you | small changes, once you trust it |

If they named a preset, apply it and show the result. Otherwise show the
current settings above in plain words and ask (AskUserQuestion) which preset,
with the one that fits what you know of them first, or "My own mix" (then ask
the two settings separately). Approval, checking results and shipping always
stop for the user, whatever the preset.

The interview answers shown above (`vbw interview`) set how VBW talks to the
user. Show them in plain words. To change one answer, ask which one and its new
value (AskUserQuestion; the allowed values come from the error of a wrong one),
then change only that one answer, the other two stay as they are:

- `vbw interview set level VALUE`
- `vbw interview set depth VALUE`
- `vbw interview set involvement VALUE`

If the interview has not been done, say so and point to `/vbw:vibe`, which asks it.

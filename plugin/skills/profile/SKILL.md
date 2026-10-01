---
name: profile
description: Switch how VBW works in one go - which AI models it uses and how much it does on its own (Careful, Standard, Fast, or your own mix).
argument-hint: "[careful | standard | fast]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config 2>&1 || true
```

The user said: $ARGUMENTS

If the output above says this is not a VBW project, set it up first (`vbw init`
and `vbw statusline on`, one line to say so), then run `vbw config` again.

Presets (each sets two things with `vbw config set`):

| Preset | `profile` (models) | `autonomy` | Good for |
|---|---|---|---|
| Careful | `quality` (Opus for the Architect, Lead, Dev and Debugger) | `guided`: explains each step and waits for "go" | learning, a first project, risky changes |
| Standard | `balanced` (Sonnet for every agent) | `balanced`: keeps going, stops for your decisions, approval, checking and shipping | most work (the default) |
| Fast | `budget` (Haiku for QA and Scout, Sonnet for the rest) | `hands-off`: takes its own recommendations on decisions and lists them for you | small changes, once you trust it |

If they named a preset, apply it and show the result. Otherwise show the
current settings above in plain words and ask (AskUserQuestion) which preset,
with the one that fits what you know of them first, or "My own mix" (then ask
the two settings separately). Approval, checking results and shipping always
stop for the user, whatever the preset.

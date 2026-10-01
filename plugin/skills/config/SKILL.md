---
name: config
description: Show or change VBW settings - the model profile (quality, balanced, budget), per-role models, the autonomy step cap and the status line.
argument-hint: "[what to change]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" statusline status 2>&1 || true
```

The user said: $ARGUMENTS

If they asked for a change, make it with `vbw config set KEY VALUE` and show
the result. Otherwise show the settings above in plain words. Keys:

- `profile`: which models VBW's agents run on. `quality` (Opus for planning,
  reviewing and building), `balanced` (the default: Opus plans, Sonnet reviews
  and builds), `budget` (Sonnet plans and builds, Haiku reviews).
- `model.planner`, `model.critic`, `model.builder`: override one role (`opus`,
  `sonnet`, `haiku` or a model id; `default` removes the override).
- `autonomy_cap`: how many steps `/vbw:vibe --auto` takes before stopping.
- The status line: `vbw statusline on` or `off`.

Your own session keeps the model you chose with `/model`; it must be Sonnet,
Opus or Fable for auto mode.

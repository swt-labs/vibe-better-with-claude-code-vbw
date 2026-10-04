---
name: config
description: Show or change VBW settings - the model profile (quality, balanced, budget), per-role models, how much VBW does on its own, and the status line.
argument-hint: "[what to change]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" statusline status 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

The user said: $ARGUMENTS

If the output above says this is not a VBW project, set it up first (`vbw init`
and `vbw statusline on`, one line to say so), then run `vbw config` again.

If they asked for a change, make it with `vbw config set KEY VALUE` and show
the result. Otherwise show the settings above in plain words. Keys:

- `profile`: which models VBW's agents (VBW 1's team: Architect, Lead, Dev, QA,
  Scout, Debugger, Docs) run on. `quality` (Opus for the Architect, Lead, Dev
  and Debugger; Sonnet for QA, Scout and Docs), `balanced` (the default: Sonnet
  for all), `budget` (Haiku for Scout, Sonnet for the rest, QA included).
- `model.<role>` (architect, lead, dev, qa, scout, debugger, docs): override
  one agent (`opus`, `sonnet`, `haiku`, a model id; `default` removes it).
  QA never runs on Haiku (it judges whether the work meets the spec):
  `model.qa` refuses any Haiku id and changes nothing; it accepts `sonnet`,
  `opus`, `default` and non-Haiku ids such as `claude-opus-5-5`. A stored Haiku
  value is raised to Sonnet.
- `autonomy`: how much `/vbw:vibe` does alone: `guided` (explains each step and
  waits), `balanced` (the default: stops for decisions, approval, checking and
  shipping), `hands-off` (takes its own recommendations and lists them).
- `autonomy_cap`: how many steps one autonomous run takes before stopping.
- `rigor`: how thorough each phase's checking is. `auto` (the default) picks a
  tier per phase from its risk; `express`, `standard` or `deep` forces it. Set
  with `vbw config rigor MODE`; phases not yet started are re-tiered.
- The status line: `vbw statusline on` or `off`.

Your own session keeps the model you chose with `/model`; it must be Sonnet,
Opus or Fable for auto mode.

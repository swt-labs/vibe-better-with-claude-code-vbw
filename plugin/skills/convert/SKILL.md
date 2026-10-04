---
name: convert
description: Bring a VBW 1 project (.vbw-planning/) into VBW 2 through a short Q&A; the old folder stays unless you choose to delete it.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" legacy 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" status 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

The facts above describe the VBW 1 plan. `"legacy": false`: there is nothing
to convert; say so and stop. `"converted": true`: it was converted already;
say so, and offer only the removal question (step 6).

You carry over what the user still wants, through their answers. Never change
`.vbw-planning/`; only `vbw legacy remove` may, and only on their word.

1. **Set up.** If the status above says it is not a VBW project, run `vbw init`.
2. **Read** only the files in `files` (project, requirements, roadmap, state,
   shipped notes). Tell the user in a few lines what the project is, what was
   finished (`phases` marked done, shipped milestones) and what was open.
3. **Ask one question at a time** (AskUserQuestion), recommendation first,
   what you found in the question or `preview`:
   - **Goals:** is this still what the project is for? Write the agreed goals
     under `## Goals` in `.vbw/spec.md`.
   - **What to do next:** of the open requirements and unfinished phases, which
     belong in the first VBW 2 milestone? Recommend the must-haves and work
     already started; the rest waits in the backlog. For each one kept: restate it as something a user can observe, and say whether a test
     can prove it (`auto`) or only they can judge it (`human`). Add each with
     `vbw spec add auto|human "statement"`; park the rest with `vbw todo add`.
   - **Ideas and decisions:** after checking they still hold, carry over the
     open todos (`vbw todo add`) and decisions (`vbw decide "decision" "why"`).
4. **History.** Under a `## History (VBW 1)` heading in `.vbw/spec.md` (not in
   the Requirements section), one line per finished milestone or phase. Name
   the milestone: `vbw milestone rename "<title>"`.
5. **Record it:** `vbw legacy done`.
6. **Ask:** "Delete the old `.vbw-planning/` folder, or keep it?" Recommend
   keeping it. `git.tracked` above 0: its files stay in git history either
   way; 0: deleting is permanent. Delete only on their answer: `vbw legacy remove`.
7. **Continue** with the `vbw:vibe` skill: VBW maps the code if needed, then
   plans the new milestone and asks for approval.

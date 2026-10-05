---
name: convert
description: Bring a VBW 1 project (.vbw-planning/) into VBW 2 through a short Q&A; the old folder stays unless you choose to delete it.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" legacy 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" legacy review 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" status 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to user's level, explanation depth and involvement (above; "-": plain words).

Facts above describe the VBW 1 plan. `"legacy": false`: nothing to convert; say so, stop. `"converted": true`: already converted; say so, offer only the removal question (step 6).

The review above (`vbw legacy review`: finished, last used, match with the code, half done, recommendation) can be shown on demand when the user asks; same plain words as the interview step.

Carry over what the user still wants, through their answers. Never change `.vbw-planning/`; only `vbw legacy remove` may, only on their word.

1. **Set up.** Status above says not a VBW project: run `vbw init`.
2. **Read** only files in `files` (project, requirements, roadmap, state, shipped notes). Tell user in a few lines what the project is, what finished (`phases` marked done, shipped milestones), what was open.
3. **Ask one question at a time** (AskUserQuestion), recommendation first, what you found in the question or `preview`:
   - **Goals:** still what the project is for? Write agreed goals under `## Goals` in `.vbw/spec.md`.
   - **What to do next:** which open requirements and unfinished phases belong in the first VBW 2 milestone? Recommend must-haves and work already started; rest waits in backlog. Each kept: restate as something a user can observe; say whether a test can prove it (`auto`) or only they can judge (`human`). Add with `vbw spec add auto|human "statement"`; park the rest with `vbw todo add`.
   - **Ideas and decisions:** after checking they still hold, carry over open todos (`vbw todo add`) and decisions (`vbw decide "decision" "why"`).
4. **History.** Under `## History (VBW 1)` in `.vbw/spec.md` (not in Requirements), one line per finished milestone or phase. Name the milestone: `vbw milestone rename "<title>"`.
5. **Record it:** `vbw legacy done`.
6. **Ask:** "Delete the old `.vbw-planning/` folder, or keep it?" Recommend keeping. `git.tracked` above 0: its files stay in git history either way; 0: deleting is permanent. Delete only on their answer: `vbw legacy remove`.
7. **Continue** with the `vbw:vibe` skill: VBW maps the code if needed, plans the new milestone, asks for approval.

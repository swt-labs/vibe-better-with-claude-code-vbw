---
name: interview
description: Ask the user, once at the start of a project, how much software they have built, how VBW should explain things, how involved they want to be, and what they are building and for whom. Used by the vibe router when the kernel says the interview is due.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

# Interview

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

The answers so far are above. Once they are kept, write every later message at the user's level, explanation depth and involvement.

The router calls this when `profile.ask` is true: after mapping (for existing
code), before any spec work. Ask with AskUserQuestion, one question at a time,
in plain words. Skip the answers `profile` already holds: resume at the first
unanswered question, named by `profile.pending` (`level`, `depth`,
`involvement`, then `keep`). `vbw interview` shows the same state.

## The three fixed questions

Each answer is recorded as soon as it is given, so an interrupted interview
loses nothing. Offer exactly these options, in this order, and no others: never reorder them or mark one Recommended, whatever the earlier answers suggest (they are the user's own facts, not a choice VBW advises).

1. "Hello, Human! Welcome to VBW. Let me interview you real quick to better adapt to you. What is your level of proficiency?"
   Options: never; small scripts or no-code; professionally; senior engineer.
   Record: `vbw interview set level "<option>"`.
2. "How should I explain things?"
   Options: plain words; plain with technical terms explained; technical and brief.
   Record: `vbw interview set depth "<option>"`.
3. "How involved do you want to be in technical decisions?"
   Options: decide and tell me; options with a recommendation; I make the calls.
   Record: `vbw interview set involvement "<option>"`.

The kernel refuses any other value and says which are allowed. On a refusal or
an answer that fits no option (free text, "Other"), never record it: ask again,
the same question, with the same options. Never guess the nearest option.

## What and for whom

Then ask briefly what you are building and for whom. Existing code: start
from `.vbw/map.md`, say what the project seems to do and let the user correct
it, instead of asking what it is. Write the answer into `.vbw/spec.md` under
`## Goals` (one or two plain sentences), then `vbw spec sync`.

## Follow-ups

Then at most three written follow-up questions, which you write for this user
and this project: pitched at their level and depth answers, aimed at what the
spec still lacks (what it does, users, constraints, what success looks like).
Zero is allowed only when the answers already say what it does and for whom;
otherwise ask them now, as a shop asks its client: inside the interview,
before the keep question, never left to the spec step. For
"decide and tell me", a follow-up may be your proposal for them to confirm or
correct. Never fill the gap unasked. Never ask a fourth.
Fold each answer into `.vbw/spec.md` (Goals, or the user's own constraints),
then `vbw spec sync`. These follow-ups are not recorded as interview answers.

## Keep

The last question: where to keep the personal answers (level, depth,
involvement). Options: "private on this machine (Recommended)", or "saved in
the project" (shared with whoever clones it).

- private: `vbw interview keep private`
- saved in the project: `vbw interview keep project`

The interview is complete only after this command. If the user stops before
it, record nothing as complete; the router asks again next time and resumes at
the first unanswered question.

Afterwards say in one line how the answers shape what follows, and that
`/vbw:profile` changes any of them.

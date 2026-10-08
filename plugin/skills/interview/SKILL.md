---
name: interview
description: Ask the user, once at the start of a project, how much software they have built, how VBW should explain things, how involved they want to be, and what they are building and for whom. Used by the vibe router when the kernel says the interview is due.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Bash(npx skills *) Workflow(vbw:tooling)
---

# Interview

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" legacy review 2>&1 || true
```

Answers so far above. Once kept, write every later message at the user's level, explanation depth and involvement.

Router calls this when `profile.ask` is true: after mapping (existing code), before any spec or convert work. Ask with AskUserQuestion, one question at a time, plain words. Skip the answers `profile` already holds: resume at first unanswered, named by `profile.pending` (`level`, `depth`, `involvement`, then `keep`). `vbw interview` shows same state.

## The three fixed questions

Record each answer at once; an interrupted interview loses nothing. Offer exactly these options, this order, no others: never reorder or mark one Recommended, whatever earlier answers suggest (user's own facts, not a choice VBW advises).

1. "Hello, Human! Welcome to VBW. Let me interview you real quick to better adapt to you. What is your level of proficiency?"
   Options: never; small scripts or no-code; professionally; senior engineer.
   Record: `vbw interview set level "<option>"`.
2. "How should I explain things?"
   Options: plain words; plain with technical terms explained; technical and brief.
   Record: `vbw interview set depth "<option>"`.
3. "How involved do you want to be in technical decisions?"
   Options: decide and tell me; options with a recommendation; I make the calls.
   Record: `vbw interview set involvement "<option>"`.

Kernel refuses other values and names allowed ones. On refusal or an answer fitting no option (free text, "Other"): never record it; ask again, same question, same options. Never guess nearest option.

## The old VBW 1 folder

One extra step, right after the level answer, before any other question. Review above. `"legacy": false` (no folder) or `asked` true (a choice is recorded): skip it and say nothing; it is asked once.

Else show it at the user's level and depth: how much was finished, when last used, whether plans still match the code, any work half done. Never guess or change the kernel's numbers, `recommendation` or `reasons`. Say any `notes` (what could not be read); never recommend converting what could not be read.

Ask with AskUserQuestion: the recommended option first, marked "(Recommended)", the other second, each with a short trade-off: "Convert it" (keeps your old plans, a few questions), "Start fresh" (clean slate). Either may be picked whatever was recommended; own words allowed.

- convert: `vbw legacy choose convert`, run /vbw:convert, report the result; the old folder stays.
- fresh: `vbw legacy choose fresh`. Nothing is converted, the folder is left untouched; carry on with the interview.

Read-only: it only reads files, runs no command found there. `/vbw:convert` shows it again on demand.

## What and for whom

Ask briefly what you are building and for whom. Existing code: start from `.vbw/map.md`, say what the project seems to do, let user correct, instead of asking what it is. Write answer into `.vbw/spec.md` under `## Goals` (one or two plain sentences), then `vbw spec sync`.

## Follow-ups

Then at most three written follow-up questions, written for this user and project: pitched at their level and depth, aimed at what spec still lacks (what it does, users, constraints, what success looks like). Zero is allowed only when the answers already say what it does and for whom; otherwise ask now, as a shop asks its client: inside the interview, before the keep question, never left to the spec step. For "decide and tell me", a follow-up may be your proposal for them to confirm or correct. Never fill a gap unasked. Never a fourth. Fold each answer into `.vbw/spec.md` (Goals, or user's constraints), then `vbw spec sync`. Not recorded as interview answers.

## Keep

Last question: where to keep personal answers (level, depth, involvement). Options: "private on this machine (Recommended)", or "saved in the project" (shared with whoever clones it).

- private: `vbw interview keep private`
- saved in the project: `vbw interview keep project`

The interview is complete only after this command. If user stops before it, record nothing as complete; router asks again next time, resuming at first unanswered question.

Afterwards say in one line how answers shape what follows, and that `/vbw:profile` changes any.

## Tools

After keep, ask once whether VBW may look for tools. First `vbw tools`. If it holds an answer, yes or no: skip, never ask again; asked once per project.

Else one plain yes/no question with AskUserQuestion. Explain each kind in a few words at user's level: skills (add-ons teaching Claude a craft), code-safety scanners (programs looking for security holes), linters (flag likely mistakes), formatters (tidy code layout), test frameworks (run automatic tests).

Record at once:

- yes: `vbw tools answer yes`, then carry on exactly as `/vbw:skills` does (work out stack, run `vbw:tooling` workflow, show short list, install only what user approves).
- no: `vbw tools answer no`. No Scout started, nothing searched, install nothing; flow goes on unchanged. `/vbw:skills` runs it later.

End the step with: "I need your yes or no to look for tools".

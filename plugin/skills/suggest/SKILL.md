---
name: suggest
description: Offer the user at most three yes-or-no suggestions when requirements are proposed or a plan is presented for approval. Used by the vibe router at those two moments only.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
effort: low
---

# Suggest

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" suggest list 2>&1 || true
```

Above: the user's answers (level, explanation depth, involvement) and the
suggestions already declined in this project.

## When

Only at spec proposal (with the proposed requirements) and at plan approval
(with the plan). Never offer or ask mid-run, mid-build, during a run, or while a
step is working; the user is not interrupted for ideas.

## What

At most three suggestions, each one yes or no. None is required: zero is valid,
and when nothing worth raising exists, say nothing about suggestions. Never pad
to reach three.

Match them to the user's level and explanation depth: for a first-time builder,
plain outcomes ("Should visitors be able to find the page by searching?"); for a
senior engineer, terse technical ones (rate limiting, migrations, observability).
With no interview answers, stay neutral: plain and brief.

Before offering, read `vbw show requirements` and `vbw show decisions`. Never
offer a duplicate of a requirement or a decision, and never offer one whose text
matches the declined list above.

## Answers

Ask with AskUserQuestion, one question per suggestion: "Yes", "No". The user may
decline any.

- Yes, a testable outcome: `vbw spec add auto|human "statement"` (as the router
  does for any requirement).
- Yes, a choice or constraint: `vbw decide "<what>" "<why: accepted on suggestion>"`.
- No: `vbw suggest decline "<the suggestion's exact text>"`. A declined
  suggestion is never offered again in this project; never offer it again,
  reworded or not.

# AskUserQuestion Contract

Source note: Stable VBW-facing contract distilled from Claude Code interactive prompt behavior plus the repo's current `references/execute-protocol.md` and `references/discussion-engine.md` anchor examples.
Last reviewed: 2026-04-18

## Structured choices

- Keep headers short. Prefer compact labels over sentence-length titles.
- Use structured choices when the real decision is bounded.
- Treat 2–4 options as the sweet spot for a single question.
- Ask 1–4 questions per tool call.
- When options exist, Claude Code still exposes an `Other` path. Treat it as the built-in escape hatch instead of pretending freeform input does not exist.
- Mark the preferred option with `isRecommended` when one option is genuinely better.
- Leave 3–4 blank lines before the tool call so the dialog does not cover the last line of prose.

### Batch vs. sequence

- Batch independent questions in a single AskUserQuestion call when answers do not depend on each other.
- Sequence dependent questions across separate calls when answer N determines what to ask for N+1.

## Intentional freeform

- Do not fake a bounded menu when the real choice space is high-cardinality or unbounded.
- Use intentional freeform input when the user may need to name, number, search, or describe something outside a short fixed list.
- If the user takes the `Other` path to explain their answer, treat that as real follow-up input rather than forcing them back into another pseudo-menu.

### Freeform handoff

- When a user selects "Other" and signals freeform intent ("let me describe it", "I'll explain", "something else"), stop using AskUserQuestion. Ask follow-up as plain text at the normal prompt.
- Wait for the freeform response. Resume AskUserQuestion only after processing it.
- Same rule applies when you include a freeform-indicating option ("Let me explain") and the user selects it.
- Users can also reference options by number from the Other path: `#2 but with pagination disabled`. Accept these hybrid responses without forcing a re-selection.

## Anti-patterns

- **Checklist walking** — marching through a predetermined question list regardless of what the user already said.
- **Canned questions** — asking questions whose answers are already in context.
- **Shallow acceptance** — taking vague answers ("something like X") without probing for specifics.
- **Premature constraints** — narrowing options before the problem space is understood.
- **Fake bounded menus** — presenting a fixed option list when the real choice space is unbounded or high-cardinality.

## Examples

### Example — structured single-select

Header: Confirm
Question: Continue with phase 03 now?
Options:
- Execute phase 03 (Recommended — the plan is already complete)
- Review plans first
- Not now

### Example — intentional freeform

Prompt: Tell me which todo to act on. Use the todo number or describe the item in your own words.

Why this stays freeform:
- the list length is not bounded to 2–4 options
- the correct answer may be a number, a phrase, or a new clarification
- pretending this is a fixed menu creates fake structure and worse UX

### Example — decision gate

Header: Next step
Question: Ready to proceed with implementation?
Options:
- Proceed (Recommended)
- Keep exploring

Why two options: Decision gates are binary commit/defer choices. Extra options add noise without value.
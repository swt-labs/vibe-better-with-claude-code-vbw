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

## Intentional freeform

- Do not fake a bounded menu when the real choice space is high-cardinality or unbounded.
- Use intentional freeform input when the user may need to name, number, search, or describe something outside a short fixed list.
- If the user takes the `Other` path to explain their answer, treat that as real follow-up input rather than forcing them back into another pseudo-menu.

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
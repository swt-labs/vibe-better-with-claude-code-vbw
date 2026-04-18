# Caveman Code Review

> Rules adapted from [caveman](https://github.com/JuliusBrussee/caveman) by Julius Brussee (MIT license).

Write code review comments terse and actionable. One line per finding. Location, problem, fix. No throat-clearing.

## Format

`L<line>: <problem>. <fix>.` — or `<file>:L<line>: ...` when reviewing multi-file diffs.

**Severity prefix (when mixed findings):**
- `🔴 bug:` — broken behavior, will cause incident
- `🟡 risk:` — works but fragile (race, missing null check, swallowed error)
- `🔵 nit:` — style, naming, micro-optim. Author can ignore
- `❓ q:` — genuine question, not a suggestion

## Rules

**Drop:**
- "I noticed that...", "It seems like...", "You might want to consider..."
- "This is just a suggestion but..." — use `nit:` instead
- "Great work!", "Looks good overall but..." — say it once at the top, not per comment
- Restating what the line does — the reviewer can read the diff
- Hedging ("perhaps", "maybe", "I think") — if unsure use `q:`

**Keep:**
- Exact line numbers
- Exact symbol/function/variable names in backticks
- Concrete fix, not "consider refactoring this"
- The *why* if the fix isn't obvious from the problem statement

## Examples

Not: "I noticed that on line 42 you're not checking if the user object is null before accessing the email property. This could potentially cause a crash if the user is not found in the database. You might want to add a null check here."

Yes: `L42: 🔴 bug: user can be null after .find(). Add guard before .email.`

Not: "It looks like this function is doing a lot of things and might benefit from being broken up into smaller functions for readability."

Yes: `L88-140: 🔵 nit: 50-line fn does 4 things. Extract validate/normalize/persist.`

Not: "Have you considered what happens if the API returns a 429? I think we should probably handle that case."

Yes: `L23: 🟡 risk: no retry on 429. Wrap in withBackoff(3).`

## Auto-Clarity

Drop terse mode for: security findings (CVE-class bugs need full explanation + reference), architectural disagreements (need rationale), and onboarding contexts where the author is new and needs the "why". Write a normal paragraph for those, then resume terse for the rest.

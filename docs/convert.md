# From VBW 1 to VBW 2

## The update

VBW 2 is version 2.0.0 of the same plugin (`vbw@vbw-marketplace`), so a VBW 1
user updates as usual: VBW 1's `/vbw:update`, or Claude Code's plugin update.

- VBW 1's `/vbw:update` checks `VERSION` on `main`, clears VBW 1's cache, runs
  `claude plugin marketplace update` and `claude plugin update`, then confirms by
  reading `VERSION` inside the installed plugin. VBW 2 ships `plugin/VERSION`
  for that check (kept in sync by `tools/bump-version.sh`).
- On the first start after the update, VBW 2's SessionStart hook removes VBW 1's
  command copies from the Claude config directory (they would shadow the
  `/vbw:` commands) and asks for `/reload-skills`.
- The status line setting is the same for both versions and always runs the
  newest installed version's script, so it switches by itself.

## The project: `.vbw-planning/` → `.vbw/`

VBW 1 kept its plan in `.vbw-planning/`; VBW 2 keeps it in `.vbw/`. They never
mix, and VBW 2 never changes `.vbw-planning/` on its own.

| Step | Who | What |
|---|---|---|
| Notice | SessionStart; `vbw next` | a project with `.vbw-planning/` and no conversion yet: the user is told once; `vbw next` says `convert` (a human gate) while the current milestone has no requirements |
| Facts | `vbw legacy` | JSON: the files that describe the project, its milestones (shipped or not), its phases with plan counts (a plan with a SUMMARY is done), and how many of its files git tracks. Reads nothing else, changes nothing |
| Q&A | `/vbw:convert` (also run by `/vbw:vibe` at `convert`) | the model reads those files, tells the user what it found, and asks one question at a time, with a recommendation: goals, which open requirements go in the first milestone (each restated as user-observable, `auto` or `human`), which wait in the backlog, which todos and decisions still hold. History goes in `spec.md` under `## History (VBW 1)` |
| Record | `vbw legacy done` | `record.converted = {from: ".vbw-planning", at}`; VBW stops offering the conversion |
| Remove (optional) | `vbw legacy remove` | only after `done`, only on the user's answer (keeping is the default). Tracked files: `git rm` plus a commit of that deletion only, so the history keeps them; then anything left (caches) |

Finished VBW 1 work is not re-proved: VBW 1 had no runnable proofs. It is
history, and the user can turn any of it into a requirement with a check.

Starting fresh is `vbw legacy done` without carrying anything over.

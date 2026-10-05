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

## The review and the choice

```text
$ vbw legacy review
{"legacy":true,"recommendation":"convert","finished":{"done":6,"total":8},"last_used":"2026-09-20",...}
```

When a project has a `.vbw-planning/` folder, VBW reviews it before it asks
anything about it. The review happens in the interview (docs/interview.md),
right after the level question and before the other questions. VBW then tells
you what it found in plain words, recommends one of two options, and you choose.
You can pick the other option whatever it recommends.

### What the review reports

| Fact | What it means |
|---|---|
| How much was finished | plans with a SUMMARY file, out of all plans |
| How recently it was used | the date of the last git commit that touched `.vbw-planning/`; file times when the project is not a git repository |
| Whether the plans still match the code | of the files and folders the plans name, how many still exist in the project |
| Any work half done | a phase with some plans finished and some not, or an unfinished build left in `.execution-state.json` |

### The recommendation rule

The review is a fixed rule, not a judgement: the same folder always gets the
same answer. VBW recommends **start fresh** when any of these holds, and
**convert** otherwise:

- no plan in the folder could be read;
- fewer than half of the files the plans name still exist;
- the folder was last used more than a year (365 days) ago and fewer than half
  of its plans were finished.

Half-done work does not change the recommendation. VBW lists it, so you decide
with it in view. The recommended option comes first, with its reasons.

### What each choice does

| Choice | What happens |
|---|---|
| Convert it | `vbw legacy choose convert` records it, then `/vbw:convert` runs (the Q&A above) |
| Start fresh | `vbw legacy choose fresh` records it. Nothing is converted and VBW stops offering the conversion |

Either way `.vbw-planning/` stays untouched. VBW only removes it if you ask
(`vbw legacy remove`, after converting).

### Safe by design

- The review only reads. It looks at file names, file times, git history and the
  top of each plan. It never runs a command it finds in the old folder.
- A folder it cannot read does not stop it. A file that could not be read is
  not counted and appears under the review's `notes`. If no plan could be read,
  the recommendation is start fresh, because there is nothing safe to convert.
- The choice is asked once per project. It is stored in `project.legacy` in
  `.vbw/record.json` (docs/record.md).
- You can run the review again any time: `vbw legacy review`, or ask during
  `/vbw:convert`. A project without `.vbw-planning/` gets `{"legacy": false}`.

Finished VBW 1 work is not re-proved: VBW 1 had no runnable proofs. It is
history, and the user can turn any of it into a requirement with a check.

Starting fresh carries nothing over (see the choice above).

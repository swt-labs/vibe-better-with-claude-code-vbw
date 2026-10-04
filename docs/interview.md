# The interview: how VBW talks to you

VBW asks three questions once per project, then writes at your level.
`/vbw:vibe` asks them at the first spec step; the answers shape every agent's
wording from then on.

```text
$ vbw interview
kept: private
level: professionally
depth: plain with technical terms explained
involvement: I make the calls
```

`vbw status` shows the same answers on its `interview` line. `vbw interview
--json` returns `{kept, interviewed, level, depth, involvement, pending}`;
`pending` names the first unanswered question, or is `null`.

## The three answers

| Key | Question | Allowed values |
|---|---|---|
| `level` | How much have you built before? | `never`; `small scripts or no-code`; `professionally`; `senior engineer` |
| `depth` | How should VBW explain? | `plain words`; `plain with technical terms explained`; `technical and brief` |
| `involvement` | How much do you decide? | `decide and tell me`; `options with a recommendation`; `I make the calls` |

The table is `plugin/lib/interview.json`; any other value is refused with the
list above. What you are building and for whom is not stored here: it belongs
to the spec, and `vbw interview set` refuses any other key.

Until a project has answers, VBW uses the middle choice of each question
(`small scripts or no-code`, `plain with technical terms explained`, `options
with a recommendation`).

## Commands

| Command | Effect |
|---|---|
| `vbw interview [--json]` | show the answers and where they are kept |
| `vbw interview set level\|depth\|involvement VALUE` | set one answer, leave the others |
| `vbw interview keep private\|project` | choose where the complete set lives |

`keep` needs all three answers and moves them: the old location is cleared.
`/vbw:profile` shows the answers and changes one at a time.

## Private or shared

| Kept | Stored in | Who sees it |
|---|---|---|
| `private` | `$(git rev-parse --git-common-dir)/vbw/profile.json` | you only: it is never committed |
| `project` | `project.interview` in `.vbw/record.json` | everyone who clones the repository |

Choose `private` for your own preferences, `project` when the team agrees on
one style. A complete private set wins over the project's, so a teammate can
keep their own level on a shared project.

Linked git worktrees share the git common directory, so the private answers
apply in every worktree of the clone. A new clone starts without them.

## Asked once

`vbw next --json` returns `profile.ask: true` only at the spec step while no
complete set of answers exists. Once answered, it never asks again: not in a
new session, a new milestone or another worktree.

A project started before this version has milestones and no answers. It is
asked once, at its next milestone's spec step, never in the middle of a run or
phase.

## Changing an answer

Run `/vbw:profile`, or `vbw interview set KEY VALUE`. The change goes to
wherever the answers are kept (a `project` set also updates `project.interview.at`).
To move them, run `vbw interview keep private` or `vbw interview keep project`.

See docs/record.md for the stored field and docs/next.md for the lifecycle.

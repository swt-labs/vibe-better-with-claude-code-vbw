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
| `level` | "Hello, Human! Welcome to VBW. Let me interview you real quick to better adapt to you. What is your level of proficiency?" | `never`; `small scripts or no-code`; `professionally`; `senior engineer` |
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

## The flow

`/vbw:vibe` runs the `interview` skill when `vbw next --json` says
`profile.ask` is true. For existing code it runs after mapping, so VBW starts
from `.vbw/map.md` and asks you to correct it. VBW asks one question at a time:

1. The three fixed questions above, with exactly their options. Each answer is
   recorded at once with `vbw interview set`. An answer that fits no option
   (free text, "Other") is never recorded: VBW asks the same question again.
   If the project has an old VBW 1 folder (`.vbw-planning/`) and no choice
   about it yet, one extra step comes right after the level answer: VBW reviews
   the folder, recommends converting or starting fresh, and you choose (asked
   once; see docs/convert.md).
2. What you are building and for whom. VBW writes the answer under `## Goals`
   in `.vbw/spec.md`.
3. At most three follow-up questions that VBW writes for your level and this
   project. If your answer to step 2 doesn't say what the thing does and for
   whom, VBW asks rather than deciding that for you. Zero follow-ups only when
   it already does. Their answers go into the spec, not into the interview
   answers.
4. Where to keep the three answers: "private on this machine" (recommended) or
   "saved in the project". This runs `vbw interview keep private|project`.

## Asked once

`vbw next --json` returns `profile.ask: true` only at the spec step while no
complete set of answers exists. Once answered, it never asks again: not in a
new session, a new milestone or another worktree.

The interview is complete only after the last question. If you stop earlier,
the answers given so far stay, `profile.pending` names the first unanswered
question (`level`, `depth`, `involvement`, then `keep`), and the next session
resumes there.

A project started before this version has milestones and no answers. It is
asked once, at its next milestone's spec step, never in the middle of a run or
phase.

## Suggestions

```text
$ vbw suggest decline "Should visitors be able to search the page?"
declined: Should visitors be able to search the page?
$ vbw suggest list
Should visitors be able to search the page?
```

VBW may offer you ideas, but only at two moments: when it proposes
requirements (the spec step) and when it presents the plan for approval. It
never asks mid-run, mid-build or while a step is working. The `suggest` skill
(`/vbw:vibe` follows it at those two moments) offers at most three, each a yes
or no. Zero is valid: when nothing is worth raising, VBW says nothing about
suggestions.

The wording follows your `level` and `depth`: a first-time builder gets plain
outcomes ("Should visitors be able to find the page by searching?"), a senior
engineer gets terse technical ones (rate limiting, migrations, observability).
VBW never offers a duplicate of an existing requirement or decision.

| Your answer | What VBW does |
|---|---|
| yes, a testable outcome | adds a requirement: `vbw spec add auto\|human "statement"` |
| yes, a choice or constraint | records a decision: `vbw decide "what" "why: accepted on suggestion"` |
| no | `vbw suggest decline "exact text"`: stored in `project.declined`, never offered again in this project, reworded or not |

Matching ignores case and spacing, so declining the same text twice stores it
once. The declined list belongs to the project, so it holds across sessions and
milestones. `vbw suggest list` prints it (`none declined` when empty);
`vbw next --json` returns the same texts as `declined` (docs/next.md).

## What the answers change

The answers change wording, and who makes a decision. Agents that write for you
(mapping, planning, building, fixing, verifying, investigating, researching)
get your level, depth and involvement (docs/workflows.md) and write at that
level.

`involvement` decides what VBW does at `needs_decisions`, when the Architect
finds a choice that is yours (cost, data, security, user experience, hard to
undo):

| Involvement | What VBW does |
|---|---|
| `decide and tell me` | picks the recommended option, records it with `vbw decide` as "chosen by VBW" and its trade-off, and lists each decision at the next stop so you can change it |
| `options with a recommendation` | asks you each decision with its options, trade-offs and a marked recommendation |
| `I make the calls` | asks you every decision, with no default; nothing proceeds on an unanswered one |

Autonomy `hands-off` takes the recommended option whatever the involvement.

## What never changes

The answers never change:

- rigor: the tier of each phase and its checks come from the requirements and
  the code (docs/rigor.md), not from your level;
- autonomy: how much VBW does alone is `vbw config set autonomy`;
- proof: approved checks run the same for everyone (docs/proof.md);
- machine-read output: `vbw next --json` is the same for every level except its
  `profile` field, and agent result schemas keep their fields and values;
- the record: its fields, and what `vbw` writes to it;
- commit messages and provenance trailers: `{type}({scope}): ...` and
  `VBW-Plan`, `VBW-Req`, as written for every user.

A beginner and a senior engineer get the same checks and the same gates
(docs/next.md); they read different words.

## Changing an answer

Run `/vbw:profile`, or `vbw interview set KEY VALUE`. The change goes to
wherever the answers are kept (a `project` set also updates `project.interview.at`).
To move them, run `vbw interview keep private` or `vbw interview keep project`.

See docs/record.md for the stored field and docs/next.md for the lifecycle.

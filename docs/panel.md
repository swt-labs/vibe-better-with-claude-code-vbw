# The VBW panel

The panel is VBW inside Claude Code's own screen. It has two parts:

- **The band** above the prompt: the agents at work while a VBW workflow runs,
  or a card with buttons when VBW needs you (see [The band](#the-band)).
- **Mission Control**, a pane beside the conversation: where your project
  stands, in plain words, and seven tabs for the detail (see
  [Mission Control](#mission-control)). It opens by itself when a session
  starts in a VBW project.

VBW also adds a few short lines to places Claude Code already draws (see
[One-line notes](#one-line-notes)) and three instant commands (see
[Instant commands](#instant-commands)).

Mission Control's **Now** tab starts with these sentences:

```
Working on M1: First milestone.
milestone

5 of 12 requirements done.
requirements

VBW is building: P1.2, P2.1 (4 min so far).
build

About 10 min left in this step.
estimate, approximate

About 40 min left in the milestone.
estimate, approximate

This session has cost $1.42 so far.
session cost

Please approve the plan before VBW builds it.
your turn
```

Each sentence has a short technical term under it (`milestone`, `requirements`,
`build`, `session cost`, `your turn`), so you can learn the words VBW uses.
The panel shows these things, top to bottom:

1. **The milestone** you are working on.
2. **Progress:** how many of the milestone's requirements are done (proven by
   their checks, or accepted by you), counted as the status line counts them.
3. **What VBW is doing now:** planning, building (and which parts), checking
   the results, fixing what the checks found, mapping the project, or idle.
4. **Time left**, when VBW can estimate it: for the current step and for the
   milestone (see [Time left](#time-left)).
5. **What this session has cost** so far (see [Cost](#cost)).
6. **Whether it needs you, and for what:** approving the plan, checking a
   result by hand, giving the go-ahead to ship, saying what to build,
   deciding on a stuck fix, or answering a question. The line turns yellow
   when it needs you.

The panel updates by itself, within a few seconds of a change. You do not
refresh it.

## Reading the panel at a glance

Read the panel from the top. The first two sentences say where you are. The
third says what VBW is doing. The estimate and cost lines say how long and how
much. The last sentence is the one that matters most: if it is yellow, VBW is
waiting for you; if it says "Nothing is needed from you right now", you can
leave it running.

A typical panel while a plan builds, before VBW has history to estimate from:

```
Working on M1: First milestone.
milestone

5 of 12 requirements done.
requirements

VBW is building: P1.2 (4 min so far).
build

No estimate yet: there are not enough finished steps to go on.
estimate, no basis

This session has cost $1.42 so far.
session cost

Nothing is needed from you right now.
your turn
```

## The band

The band is the strip directly above the prompt. VBW uses it only when there is
something to watch or something to decide; otherwise it is empty. A survey from
Claude Code always takes it first.

**While a VBW workflow runs**, the band shows the crew, one row per agent:

```
VBW ▸ planning · Plan · 10m04s · ≈$3.20 this run                 [p] Mission Control
● architect  scope   ⠹ reading spec.md                              2m10s   41k
● lead       P53     ⠼ "Splitting R69 into two plans: the runner…"  0m48s   18k
✓ scout      linux   done · 4 findings                              1m02s   12k
```

- Each row has the role in its colour (architect magenta, lead blue, dev green,
  QA yellow, scout cyan, debugger red, docs pink), the agent's label, what it
  is doing now (the tool it calls, or the end of what it is writing), its time
  and its context size.
- A finished agent shows ✓ and its one-line result for a minute, then joins a
  "done" count. A failed agent shows ✗, its reason and a **details** button.
- An agent with no new step for 45 seconds is marked **quiet**, so a hang looks
  different from slow work.
- The cost is the session cost added since the run started, so it is "about".
- With little room the rows shrink, down to one summary line.

VBW reads this from the files Claude Code writes for each workflow run in this
session's own folder (`<Claude config folder>/projects/<project>/<session>/`):
which agents started, their type, their transcripts and the run's end. It finds
the run from the moment `/vbw:vibe` launches it, and again after a reload while
the run goes on. These files are Claude Code's own and undocumented: if they
change, the band shows less, never an error.

**When VBW needs you**, the band shows a card instead:

```
⚑ VBW needs you · the plan is ready: review it, then approve it to build
[1: Review plan]   [2: Approve…]   [3: Discuss]   [4: Later]
```

- Press a digit from an empty prompt, or click.
- **Review plan** (or Review proof, Review fixes) opens Mission Control on that
  tab.
- **Approve…**, **Verify…**, **Discuss** and the like put the command in your
  prompt (`/vbw:approve`, …). **You press Enter.** No button ever sends a
  command or answers for you.
- **Later** hides the card until VBW needs something else; the hint line under
  the prompt still says what is waiting.
- When the plan is ready, `/vbw:approve` is also offered as the prompt's
  suggestion (press Tab to take it).
- Before a run, the card adds a warning when your weekly limit is past 80%, and
  a **/compact first** button when the context is 85% full or more. The button
  only fills `/compact` in.

## Mission Control

Mission Control is the pane. Its tabs run across the top, after the VBW
portrait (a picture on terminals that draw images, such as kitty and Ghostty;
the word `VBW` elsewhere); press one to switch:

```
Now │ Plan │ Proof │ Timeline │ Decisions │ Team │ Costs
```

- **Now:** the sentences above, the sound switch, then the running workflow as
  columns of agent cards by phase. Press a card for that agent's model, time,
  current step and result.
- **Plan:** one button per phase; each shows its goal, its plans with their
  files, and its checks with their commands.
- **Proof:** one square per approved check (green passed, red failing, grey not
  run). Press a check for its last output.
- **Timeline:** one lane per agent against the run's clock, the three slowest
  marked, and past steps of the same kind against their usual time.
- **Decisions:** the milestone's decisions, newest first.
- **Team:** which model each role uses, the profile, autonomy and rigor, with
  buttons that fill `/vbw:config` and `/vbw:profile`.
- **Costs:** each VBW run of this session with its cost (the session cost added
  while the run was open, so "about"), by kind, and the session total. The list
  starts with the session: a new session starts again from zero.

When a milestone ships, Mission Control opens on **VBW Wrapped**: the
requirements proven, the checks passing, the agents and fix rounds, the time
the milestone's steps took, its cost and its fastest and slowest steps. The
agents and the cost count only the runs this session saw; what VBW cannot know
says "unknown" or is left out. Press any tab to leave it.

## One-line notes

VBW adds a few words to places Claude Code already draws. Each one keeps
Claude Code's own drawing whenever VBW has nothing to say.

| Where | What VBW adds |
|---|---|
| The spinner while a turn runs | ` · VBW building P53.2 (2/5)…` while a VBW run works |
| The hint line under the prompt | `VBW: planning 10m`, `VBW needs you: /vbw:approve` or `VBW next: /vbw:vibe` |
| The footer's mode labels | `VBW auto ⟳ 3/10` during an autonomous run, else the profile (`VBW careful`, `VBW standard`, `VBW fast`) |
| The notes under the logo, once | `VBW M11 · 1/15 · next: /vbw:vibe` |
| A question VBW asks | `VBW · a decision for M11` above the question |
| The line that closes a turn | `VBW · plan approved · 3s` after a turn that moved VBW on |
| The Workflow row | `VBW planning · started 16:33 · [p] watch live` |
| A `vbw` command's row | what it did: `VBW · recorded P53.1 done` (its output stays below) |
| The "workflow finished" row | `✓ VBW planning finished · 3 phases · 9 plans · 21 checks · 14m · ≈$4.10`; the full row shows in the expanded transcript (ctrl+o) |

The transcript Claude Code stores is never changed: these are drawings only.

## Instant commands

These answer at once, even while Claude is busy, and cost no model turn:

| Command | What it does |
|---|---|
| `/vbw-status` | Where the project stands: milestone, progress, what VBW is doing, what comes next |
| `/vbw-why` | Who holds the VBW run and since when, and what is blocked |
| `/vbw-todo [idea]` | Parks an idea for later. With no text it takes the text you selected. VBW's own `vbw todo add` writes it |
| `/vbw-panel` | Opens Mission Control |
| `/vbw-sound` | Turns the "needs you" sound on or off |

## Cost

The cost is **one line** that shows what the **current Claude Code session**
has cost so far, in dollars. It is not a project total and not a history: a new
session starts again from zero. There is no breakdown by tokens, cache or
model.

The number comes from Claude Code and follows it within a few seconds. When
Claude Code gives no cost, the line says so instead of showing a number:

```
The cost so far is not available.
cost, not available
```

The panel never guesses a cost.

## Time left

The panel estimates the time left for **this step** (the planning, building or
checking that is running now) and for **the milestone** (all the phases not yet
passed). When nothing is running, it estimates only the milestone. When no
phase is left, it shows no milestone estimate.

- **It is approximate.** The text says "About 10 min left in this step", in
  whole minutes, never an exact figure. It counts down as the step runs.
- **It needs history.** VBW estimates only after **at least 3 finished steps
  of the same kind** (for example 3 builds). The usual time of a kind is the
  median of its latest 10 finished steps. The milestone estimate also needs
  3 finished builds and 3 finished checks. Before that, the panel says "No
  estimate yet: there are not enough finished steps to go on."
- **It comes from this clone's own history.** When a run ends, VBW adds one
  finished step (its kind, start, end and seconds) to `steps.json` in your
  clone's git directory (`.git/vbw/steps.json`), keeping the latest 50. The
  file is private to your machine: it is not committed and not part of
  `.vbw/record.json`. Delete it and the estimates start again from none.
  The panel only reads it.
- **It never shows a negative time.** When a step runs past its usual time, the
  panel says "This step is taking longer than usual." and shows no number.

## Open and close it

In a wide window the panel opens by itself when a session starts in a VBW
project. In a narrow window Claude Code does not open a pane unasked, so run
`/vbw-panel`: it opens the panel at any width.

The panel asks for a quarter of the terminal's width (never under 40
columns). It asks once per session, after its first drawing, and never takes
the keyboard. `/vbw-panel` opens at a quarter of the width of the terminal you
typed it in. A width you set by dragging the pane's edge always wins: Claude
Code keeps it, VBW never asks again, and VBW never stores a width as your
choice. Drawn on the main screen (not as a side pane), or where the width is
not reported, the panel asks for nothing.

If you close the panel yourself, it stays closed, in later sessions too, until
you open it again with `/vbw-panel`. VBW keeps this choice in Claude Code's
per-user store, never in your project, and opening or closing changes no file
of the project.

`/vbw:panel` checks your Claude Code version and tells you whether the panel
and its sound are available.

## The sound

VBW plays a short sound when it needs you: an approval, a question, or a
result to check. It plays once per request, not again while the same request
stands, and not for a request already waiting when the session starts. Each
time it picks one at random from the sounds shipped with VBW, in
`plugin/assets/audio/<character>/` (mp3 files).

The sound is **on by default**. To turn it off or on:

- click the **Turn off** / **Turn on** button in the panel, or
- run `/vbw-sound` (it switches; `/vbw-sound off` and `/vbw-sound on` set it).

The choice is remembered. It is yours alone: it is kept in Claude Code's
per-user store on your own machine, never committed, never in the project and
never in `.vbw/record.json`. The sound needs the panel, so it needs Claude Code
2.1.287 or newer.

## Motion

How much the panel animates is a project setting, shared through git:

```bash
vbw config set motion full     # crew sprites and celebrations
vbw config set motion calm     # dots and spinners, no confetti
vbw config set motion off      # static text
vbw config set motion default  # let your interview level pick
```

What each level shows:

| | `full` | `calm` | `off` |
|---|---|---|---|
| Each agent in the band | a small figure in its role's colour, posed by what it does (reading, editing, running a command, writing, quiet, done, failed), moving about 10 times a second while the run works | a dot in its role's colour and a spinner that steps once a second | a dot and a still `·` |
| A phase passes QA | about 1.5 s of confetti in the band | nothing | nothing |
| All checks pass | one green sweep across the top of the Proof tab, and `✓ All checks pass` in the band for a minute | `✓ All checks pass` in the band for a minute | nothing |
| A milestone ships | Mission Control opens on VBW Wrapped | the same | the same |

The figures need three rows of the band for each agent; with less room the band
shows dots. They move only while a VBW run works and the band shows them, and
stop when the run ends. Figures, confetti and the sweep are drawn on the
terminal only; other surfaces show the dots. VBW Wrapped is information, not
decoration, so it opens at every level.

Unset, the panel picks `full` if you told the interview you have never coded
or write small scripts, and `calm` otherwise (also before the interview). In
test mode it is always `off`, so test runs draw the same thing every time.
`vbw config` shows the setting.

## What it needs

The panel needs **Claude Code 2.1.287 or newer** (check with
`claude --version`; update with `claude update`).

- **The band above the prompt** (the crew and the cards) needs **2.1.290 or
  newer**: earlier versions redraw a band forever when it changes height. On
  2.1.287 to 2.1.289 the pane, the one-line notes and the commands work, and the
  band stays Claude Code's own.
- **Older Claude Code:** there is no panel and no error. Everything else in
  VBW, including the status line, works as before.
- **Outside a VBW project** (no `.vbw/record.json`): there is no panel and no
  error.
- **Anything unexpected inside the panel:** it stays out of the way. An error
  in the panel never reaches your session.

## What it reads and what it costs

The panel only reads local files: `.vbw/record.json`,
`.vbw/runtime/next.json` and this session's `.vbw/runtime/auto.<session>.json`
in your project, `steps.json` in your clone's git directory, and the workflow
run files in this session's own folder under the Claude config folder (found
from `CLAUDE_CONFIG_DIR`, else `HOME`; no other environment variable is read).
It asks Claude Code for the session cost, context fill and weekly limit,
read-only. It never writes and never uses the network. The one program it runs
is VBW's own `vbw todo add`, when you type `/vbw-todo`. It reads a file again
only when that file's size or modification time has changed, and redraws only
when what it shows changes (while agents work, that is every check).

It checks every 2 seconds. Each check costs CPU time (user plus system,
not time spent waiting) as follows, measured on a developer Mac with Node 22:

| Check | Measured | Budget |
|---|---|---|
| Nothing changed | about 0.02 to 0.08 ms | 0.5 ms |
| A file changed, read and redrawn | about 0.04 to 0.2 ms | 0.5 ms |
| A need raised and the sound asked to play | measured by the same script | 0.5 ms |

The budget is about 12 times the typical cost, to leave room for a busy
machine. These numbers come from the test stand-in for Claude Code, whose own
work is counted too, so they are an upper bound.

Check it yourself from a VBW checkout (needs `node`):

```
bash tools/bench-panel.sh
```

It prints the three costs and the budget, and fails if a check is over the budget.
`VBW_PANEL_BUDGET_MS` changes the budget; `VBW_BENCH_RUNS` changes how many
checks it averages (default 200).

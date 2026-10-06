# The VBW panel

The panel is a small pane inside Claude Code that tells you, in plain words,
where your project stands and whether VBW is waiting for you. It opens by
itself when a session starts in a VBW project.

```
Working on M1: First milestone.
milestone

2 of 6 phases done.
phases

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

Each sentence has a short technical term under it (`milestone`, `phases`,
`build`, `session cost`, `your turn`), so you can learn the words VBW uses.
The panel shows these things, top to bottom:

1. **The milestone** you are working on.
2. **Progress:** how many phases have passed their checks.
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

2 of 6 phases done.
phases

VBW is building: P1.2 (4 min so far).
build

No estimate yet: there are not enough finished steps to go on.
estimate, no basis

This session has cost $1.42 so far.
session cost

Nothing is needed from you right now.
your turn
```

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

## What it needs

The panel needs **Claude Code 2.1.287 or newer** (check with
`claude --version`; update with `claude update`).

- **Older Claude Code:** there is no panel and no error. Everything else in
  VBW, including the status line, works as before.
- **Outside a VBW project** (no `.vbw/record.json`): there is no panel and no
  error.
- **Anything unexpected inside the panel:** it stays out of the way. An error
  in the panel never reaches your session.

## What it reads and what it costs

The panel only reads local files: `.vbw/record.json` and
`.vbw/runtime/next.json` in your project, and `steps.json` in your clone's git
directory. It asks Claude Code for the session cost, read-only. It never writes, never uses the network and never
runs another program. It reads a file again only when that file's size or
modification time has changed, and redraws only when the sentences change.

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

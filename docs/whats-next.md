# What's next

After you ship, and whenever you ask, VBW tells you what to work on next.

```
/vbw:vibe what's next
```

```
what's next: Refunds (small)
  Customers ask for it most.
  then: Gift cards (large)
  then: Dark mode (medium)
  written 2026-10-09
```

## What it is

A recommendation has:

- a **top pick**: what to do next, one sentence on why, and a size (`small`,
  `medium` or `large`);
- up to two **runners-up**, each with a size.

A pick that comes from your backlog names its todo (`T4`); one that comes from
the milestone names its requirement (`R7`). A pick's source, when it has one, is a `T` or `R` id and is never empty: the kernel refuses an empty source.

The Architect writes it from the record only: the open requirements, the
backlog (each todo with its sort and size) and your decisions
(`vbw show decisions`). It never picks work that is already shipped or proven,
and never a suggestion you declined (see [triage](triage.md)).

## Where it is kept

The kernel stores the recommendation in the project record
(`.vbw/record.json`, field `recommendation`) with the time it was written, and
commits the record (`chore(vbw): what's next`), so a ship leaves the project
clean; your own staged files stay staged. One is kept: a new one replaces the old one. The kernel refuses a malformed one,
or a pick whose todo or requirement is not open, and says what is wrong. A
stored recommendation raises the record schema to 3 (see
[record.md](record.md)).

`vbw status` ends with it:

| State | What `vbw status` prints |
|---|---|
| a recommendation | the lines in the example above (only the first is at the left edge) |
| nothing open at all | `what's next: the backlog is empty (written <date>)` |
| none written yet | `what's next: none yet (ask /vbw:vibe what's next)` |

`vbw status --json` has the same data as `recommendation` (`null` when none).

## When it is written

- After each ship inside `/vbw:vibe`. The ship is already done: `/vbw:vibe`
  never waits for the recommendation.
- When you ask `/vbw:vibe what's next` or `/vbw:vibe suggest next`.

Not while another run is open: VBW says so in one line and does nothing.

It costs one Architect run. When nothing is open (no open requirement, empty
backlog), no Architect runs and the recommendation says the backlog is empty.

If the Architect fails, or the kernel refuses the result, VBW says so in one
line. The earlier recommendation stays, and a ship that came first stays
shipped.

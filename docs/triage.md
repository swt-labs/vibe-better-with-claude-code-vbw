# Triage: sorting new ideas into now, next and later

```
You: /vbw:vibe also add dark mode

VBW: Dark mode -> later (small). It does not block the checkout work.
     [ later (Recommended) ]  [ now ]  [ next ]
```

Every new idea you bring to `/vbw:vibe` is sorted on one line before any
planning. You pick from a menu; you type no command.

## When it happens

- Each new idea gets a triage, before VBW writes a requirement, plans or
  changes a file.
- It happens at every autonomy setting (`guided`, `balanced` and `hands-off`).
- A request made while a run is open is sorted too. It never interrupts the
  run; a `now` idea waits until the run ends.

Not sorted:

- an answer to a question VBW asked
- `continue`, `go on` and other nudges
- an approval
- an idea VBW already has. VBW names the matching requirement or backlog item
  instead, and offers to move a backlog item to `now`.

Several ideas in one message get one line each in the same menu, up to four.
More than four are sorted four at a time.

## The three sorts

| Sort | What happens |
|---|---|
| `now` | The idea joins the active milestone as a requirement (`vbw spec add`). Planning and approval continue as usual. With no active milestone, VBW starts the next one. |
| `next` | The idea goes into the backlog (`vbw todo add`), to be picked up soon. |
| `later` | The idea goes into the backlog, to be picked up when there is room. |

Each line also gives a one-sentence reason and a size: small, medium or large.

| Size | Meaning |
|---|---|
| `small` | A short change in one place |
| `medium` | Several files or one new behavior |
| `large` | A feature that needs its own plan |

VBW's sort is the first menu option, marked `(Recommended)`.

## The backlog

`vbw todo list` shows each item's sort and size. `next` items come before
`later` ones.

```
$ vbw todo list
T3 [next, small] Refunds
T2 [later, large] Gift cards
T1 Dark mode
```

Items added before sorting existed stay unsorted and list as before.

An item already in the backlog gets its sort later, or a different one:

```
$ vbw todo sort T3 next small
T3 [next, small] Refunds
```

It replaces both values, then lists the item in its group. An unknown or
closed item, or a value other than `next`/`later` and `small`/`medium`/`large`,
is refused and nothing changes.

`vbw triage` prints what VBW looks at when it sorts: the active milestone, its
requirements not yet proven or accepted, any open run and the open backlog.
It writes nothing.

## Overruling VBW

Pick another sort in the same menu. VBW then asks one follow-up question that
says, once and plainly, what your choice displaces and the risk. For example,
`now` instead of `later` grows the milestone and may need another approval;
`later` instead of `now` delays something urgent, so a bug stays unfixed.

Your options:

- one or two ready reasons VBW suggests
- your own words
- keep VBW's sorting

VBW follows your sort and records it as a decision (`vbw decide`) with the idea,
both sorts and your reason. Keeping VBW's sorting records nothing. VBW does not
repeat the warning, argue or ask again for that idea.

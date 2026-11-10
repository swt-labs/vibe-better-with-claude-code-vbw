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
- a fix that is already fixed. Before sorting a fix (a bug, a ticket, "X is
  broken"), VBW checks the code: the code path, its tests and earlier commits
  that name it. When the evidence says the bug no longer happens, the menu
  shows that evidence and recommends **already fixed**: VBW records it with
  `vbw decide` and adds no requirement. **It still happens** asks how, and the
  answer is sorted as usual. Other work found along the way, such as an
  obsolete workaround, is a separate idea with its own line.

Several ideas in one message get one line each in the same menu, up to four.
More than four are sorted four at a time.

## The three sorts

| Sort | What happens |
|---|---|
| `now` | The idea joins the active milestone as a requirement (`vbw spec add`). VBW offers its suggestions (`vbw:suggest`) once after the ideas are added, before the first planning run. Planning and approval continue as usual. With no active milestone, VBW starts the next one. |
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

### Each change is saved in git

`vbw todo add`, `sort`, `done` and `drop` save their change at once, as a
commit of `.vbw/record.json`, so the project is left clean:

```
$ vbw todo add "Gift cards"
$ git log -1 --format=%s
chore(vbw): todo T2 added
```

The message names the item and what happened to it (`todo T3 sorted next,
small`, `todo T1 done`, `todo T2 dropped`). `vbw todo list` and a command that
changes nothing make no commit.

Only `.vbw/record.json` is in that commit. Files you staged stay staged, and
files you changed but did not stage stay changed. Neither goes into the commit.

If git cannot commit (no git identity set, or a hook that refuses), the change
is kept and the command still succeeds. It prints a warning with git's reason,
and the next `vbw next` returns the commit step (docs/next.md, The commit step):
fix what the hook flagged, allow it in the checker's settings, or commit the VBW
files yourself. VBW never skips the hook.

```
vbw: warning: could not commit VBW files (chore(vbw): todo T2 added): <git's reason>; commit them yourself
```

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

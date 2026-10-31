# The VBW status line

The status line is the user's live view of VBW. Setting up a project
(`/vbw:vibe` the first time, or `/vbw:init`) turns it on; it is a core part of
VBW, not an option. The same goes for Claude Code's Dynamic workflows, which
VBW plans and builds with: `/vbw:vibe` turns them on (`vbw workflows on`) unless
the user disabled them on purpose.

```
[VBW] expenses │ M1 First milestone │ ▓▓▓▓▓▓▓░░░ 4/6 done │ ● working: building P1.2, P2.1 · 1 of 2 · 8 min, until around 14:20 │ ⟳ auto 3/25
Agents ● dev P1.2 sonnet  ● dev P2.1 sonnet
Context ▓▓▓░░░░░░░ 31% 62K/200K │ Tokens 2 in 195 out │ Cache 93% hit 3.8K write 55.5K read │ Cost $1.42 │ +303 −12
Limits 5h ▓▓░░░░░░░░ 23% (resets 2h13m) │ 7d ▓▓▓▓░░░░░░ 41% (resets 3d)
Sonnet 5.5 │ 10m22s (API 5m55s) │ main │ VBW 2.0.6 │ CC 2.1.286
```

1. **VBW:** the project, the milestone, a progress bar of requirements proven
   or accepted, and one state, in the colours of Mission Control's Now tab:
   - `● working: building P1.2, P2.1 · 1 of 2 · 8 min, until around 14:20`
     (the panel accent, violet): a step is running, what it is doing, its parts done, how long it has
     run (from a minute on) and when it should end. A background proof reads
     `● working: proving 12 of 40 checks · 3 min, until around 14:20`, counting
     up; an end on another day reads `until around tomorrow 00:20`. A step with
     parts past its time reads `until around 14:35, later than usual`; one
     without reads `until around 14:20, 6 min late`. With fewer than 3 finished
     steps of the kind there is no end time: `● working: building P1.2, P2.1 ·
     1 of 2 · 8 min`. The status line reads the time from the running step's note
     and never works it out itself (see [Time left](panel.md#time-left)). It shows
     the step's time only; the milestone's end is Mission Control's and the chat
     message's, never the status line's. While a run is open, the cell ends with
     who holds it: `· leading` in the chat that holds the run, `· held by <name>`
     in any other chat, the name (from `/rename`) cut to 20 characters with `…`.
     With no name known the cell shows the first 8 characters of the session id,
     and with a lease that has no session there is nothing after the step.
     Escape sequences in a name are removed. Agents working with no run open read
     `● working: 2 agents`.
   - `⚑ needs you: approve · since yesterday 21:38` (amber): a step needs the
     user, and since when (the day is named when it is not today); without a
     time on the last `vbw next`, the since is left out.
   - `✓ idle: M2 shipped 15:04` (green) once the milestone has shipped, and
     `✓ idle: prove is next` (from the last `vbw next`) otherwise.

   `⟳ auto 3/25` follows while this session's autonomous run is armed (another
   session's is not shown). In a folder inside a VBW project whose own git top
   has no record: `/vbw:vibe to start` (this line, then lines 3 to 5).
2. **Agents or team** (VBW projects, Claude Code before 2.1.287 only): while agents work, each one in its role's
   colour (architect magenta, lead blue, dev green, qa yellow, scout cyan,
   debugger red, docs pink) with its label and model. Otherwise the team: each role's model from the profile and
   any per-role override (`/vbw:config`), the profile, and how much VBW does on
   its own. An agent counts as working when its transcript, next to the
   session's, changed in the last minute; its `.meta.json` names its role,
   label and model. From Claude Code 2.1.287 this line is left out, because
   Claude Code itself shows the live agents and the team there; line 1 still
   counts the agents working, so the status line is four lines everywhere. The
   version comes from Claude Code's status line input (`CC` on the last line);
   when it is missing, the line stays.
3. **Context, tokens, prompt cache and cost:** the context used, the last
   request's tokens, the prompt cache hit rate with what was written and read,
   the session cost and the lines it changed.
4. **Plan limits** (5-hour and 7-day), for Pro and Max accounts.
5. **Model, time, git branch, versions.**

## How it is installed

A plugin cannot set the main status line, so `vbw statusline on` writes the
user's `settings.json` (`$CLAUDE_CONFIG_DIR`, else `~/.config/claude-code`, else
`~/.claude`). A status line the user had before is saved next to it and
`vbw statusline off` restores it. `vbw statusline status` says which is set.

The setting also asks Claude Code to re-run the status line every 5 seconds
(`statusLine.refreshInterval: 5`), on top of its event-driven redraws, so a
run's time and its working agents stay current while nothing else happens.
A run is budgeted at 60 ms on a nominal machine (no network, no git process).
`tools/bench-hooks.sh` measures a reference workload first and prints it with
the ratio to the nominal cost: on a slower machine (ratio above 1) a run within
60 ms times the ratio is reported slow, not failed; a run above that fails.

The setting is one object for both lines, so `vbw statusline on` keeps the
`padding` and the `refreshInterval` of a status line you had before, and writes
them into it. A line without an interval gets VBW's 5 seconds. An interval you
set stays yours, which means VBW's line then refreshes at that rate too. In a
project where VBW is off, your earlier line runs with the padding you gave it and,
when you gave it an interval, at that interval; without one it runs at the
5-second refresh, as often as VBW's own line would.

`vbw statusline on`, and a session that starts in a VBW project, update a
setting made by an older VBW (or by VBW 1) in place, keeping the refresh
interval and the saved status line, and giving it the saved line's padding when
it has none. `vbw statusline
status` says when the setting is an older one, and `vbw doctor` flags it with
`vbw statusline on` as the fix.

The setting runs the newest installed VBW's `scripts/vbw-statusline.sh` from
the plugin cache, because the plugin's directory changes with every update and
settings cannot use `${CLAUDE_PLUGIN_ROOT}`.

A session started with `claude --plugin-dir ./plugin` (a working tree of VBW)
is the exception: its status line is drawn by the working tree's script and
shows the working tree's version. Any other session shows the version of the
newest installed copy. If the working tree is moved or deleted, or is no longer
a VBW plugin, the session falls back to the installed copy.

## Projects where VBW is turned off

When a project's settings turn the plugin off, the status line does not show
VBW there. It shows the status line you had before `vbw statusline on` (the
earlier status line), or nothing shows if you had none. Nothing is written in
that project.

```json
{ "enabledPlugins": { "vbw@vbw-marketplace": false } }
```

Claude Code reads these files in this order, and the first one that sets the
plugin decides: `.claude/settings.local.json`, then `.claude/settings.json`
(both in the project), then your own `settings.json` (in the folder named
above).

VBW's script only says "off" (it exits with code 3). The setting itself then
runs the earlier status line with the same input; VBW never runs it.

### Folders with no VBW project

The same hand-back happens where there is no VBW project: no `.vbw` folder at
or above the folder Claude Code reports (else the folder the script runs in).
The script prints nothing and exits 3, the setting runs the earlier status line
and prints its output unchanged, and with no earlier status line saved nothing
shows. A `.vbw-planning` folder (VBW 1) does not count as a project. Inside a
VBW project the line renders as usual, and the cost side file is written only
there. A setting written by an earlier 2.1.x needs no rewrite.

The off path is the cheapest of the status line's paths. The setting starts one
bash, which runs the installed script inside itself, and that script starts one
jq: it reads your settings file, the project's two settings files (when the
session runs in the project, which is nearly always) and Claude Code's JSON
together, and starts no other process before it says "off". On a session
that loaded a working tree (`claude --plugin-dir`) it also reads the session's
record, with no jq. `tools/bench-hooks.sh` measures VBW's own CPU on this path as
`status line (VBW off)`, and the no-project hand-back (a walk up the folders
that starts no process) as `status line (no project)`: the whole call minus one bash, one jq and one sh
startup and the earlier status line itself, which are the platform's and yours.
The limit is 10 ms (`VBW_HANDBACK_BUDGET_MS`) on a nominal machine, scaled by the
same reference ratio: within budget times ratio is reported slow, not failed.

Only a setting made by this version can hand back. If `vbw doctor` says the
status line was set by an older VBW, run `vbw statusline on` to update it.

## The cost side file

On each render in a VBW project, the status line writes the session's figures
from Claude Code to `.vbw/runtime/cost.SESSION.json`:

```json
{ "session": "s1", "usd": 1.4234, "at": "2026-10-11T21:52:15Z" }
```

`usd` is the session's total cost, `at` the time of the render. Tokens are not
stored: Claude Code's token fields are the last request's, not running totals
(docs/costs.md). The file goes to a temporary name and is
renamed, so a reader never sees half of it. A render with no cost figures leaves
the file as it was, and a folder that cannot be written is skipped quietly: the
status line still renders. It never writes `.vbw/record.json`.

`vbw run start` and `vbw run end` read it to work out what a run cost, and
`vbw show costs` reads it for the milestone totals (docs/costs.md).

## The error file

When the render fails, jq's error text is kept in `.vbw/runtime/statusline.err`
so a one-off `[VBW] status line unavailable` can be explained afterwards. The
file holds jq's error output of the last render only: it is emptied at the start
of every render, so a good render leaves it empty, and it lives inside the
project. It is written only when `.vbw/runtime` already exists; the status line
never creates the folder. `tools/bench-hooks.sh` prints the line it read and this
file's text when the running step is missing from the `status line (step
running)` case.

## Engineering

- One jq program renders all the lines from Claude Code's JSON, the record,
  and VBW's runtime state (`next.json`, and the session's own `auto.SESSION.json`).
- `next.json` is the last answer of `vbw next`. It now also holds the `qa` key: each
  phase QA checks again with its reasons, and the phases that keep their pass
  (docs/next.md). The status line reads only its `action` and `gate`, so it does not
  show the reasons; `vbw show qa` does.
- It reads `.vbw/runtime/glance.json` when that is newer than the record, and
  the record otherwise (docs/record.md). The glance holds only what the status
  line shows, so the 60 ms nominal limit holds on a record over 2 MB. Any `vbw` command
  refreshes a missing or stale glance.
- While a lease is open it also reads Claude Code's list of chats
  (`<claude-config-dir>/sessions/*.json`) in one jq pass per render, to get the
  holder's current name. It reads the list only then, never writes it, and
  skips a malformed entry. With the list missing, the line renders as with an
  empty list: the stored name from the glance, else the 8 characters of the id.
  `tools/bench-hooks.sh` measures the status line with a lease open and a list
  on disk, within the same 60 ms nominal budget (same reference, ratio and slow report).
- Started in a subfolder, it shows the project that folder is in: the nearest
  folder up that holds `.git`, the same project the kernel and the guards use.
- No network, no git process (the branch is read from
  `.git/HEAD`, also in linked worktrees). It writes the cost side
  file and the error file above, never the record.
- It reads stdin with a timeout (Claude Code may send nothing on the first
  render) and never fails: a bad render prints `[VBW] status line unavailable`.
- Exit 3 is the hand-back signal: the script prints nothing and exits 3 both
  where VBW is turned off and where there is no VBW project. `tools/bench-hooks.sh`
  measures them as `status line (VBW off)` and `status line (no project)`, each
  judged on VBW's own CPU within 10 ms (see above). The no-project line
  (`/vbw:vibe to start`) remains only for a folder inside a VBW project whose
  own git top has no record.
- The script runs on its own (`bash vbw-statusline.sh`) and inside the setting's
  bash (sourced in a subshell of it, which saves a bash start on every render).
  Its exit status is its answer in both, and it finds its own folder from
  `BASH_SOURCE`, not `$0`.
- `NO_COLOR` turns the colors off.

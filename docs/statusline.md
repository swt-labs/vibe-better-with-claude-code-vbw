# The VBW status line

The status line is the user's live view of VBW. Setting up a project
(`/vbw:vibe` the first time, or `/vbw:init`) turns it on; it is a core part of
VBW, not an option.

```
[VBW] expenses │ M1 First milestone │ 4/6 done │ ▶ build: P1.2, P2.1 │ ⟳ auto 3/25
Context ▓▓▓░░░░░░░ 31% 62K/200K │ Cost $1.42 │ +303 −12
Limits 5h ▓▓░░░░░░░░ 23% (resets 2h13m) │ 7d ▓▓▓▓░░░░░░ 41% (resets 3d)
Sonnet 5.5 │ 10m22s (API 5m55s) │ main │ VBW 2.0.0 │ CC 2.1.286
```

1. **VBW:** the project, the milestone, requirements proven or accepted, and
   what is happening: a run in progress (`▶ build: P1.2`), a step that needs the
   user (`needs you: approve`), or the next step (`next: prove`, from the last
   `vbw next`). `⟳ auto 3/25` while an autonomous run is armed. Outside a VBW
   project: `/vbw:vibe to start`.
2. **Context and cost** of the session, and the lines it changed.
3. **Plan limits** (5-hour and 7-day), for Pro and Max accounts.
4. **Model, time, git branch, versions.**

## How it is installed

A plugin cannot set the main status line, so `vbw statusline on` writes the
user's `settings.json` (`$CLAUDE_CONFIG_DIR`, else `~/.config/claude-code`, else
`~/.claude`). A status line the user had before is saved next to it and
`vbw statusline off` restores it. `vbw statusline status` says which is set.

The setting runs the newest installed VBW's `scripts/vbw-statusline.sh` from
the plugin cache, because the plugin's directory changes with every update and
settings cannot use `${CLAUDE_PLUGIN_ROOT}`. It is the same setting VBW 1 used,
so updating from VBW 1 switches the status line over with no change.

## Engineering

- One jq program renders all four lines from Claude Code's JSON, the record,
  and VBW's runtime state (`next.json`, `auto.json`).
- No network, no temporary files, no git process (the branch is read from
  `.git/HEAD`, also in linked worktrees).
- It reads stdin with a timeout (Claude Code may send nothing on the first
  render) and never fails: a bad render prints `[VBW] status line unavailable`.
- `NO_COLOR` turns the colors off.

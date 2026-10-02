# The VBW status line

The status line is the user's live view of VBW. Setting up a project
(`/vbw:vibe` the first time, or `/vbw:init`) turns it on; it is a core part of
VBW, not an option. The same goes for Claude Code's Dynamic workflows, which
VBW plans and builds with: `/vbw:vibe` turns them on (`vbw workflows on`) unless
the user disabled them on purpose.

```
[VBW] expenses │ M1 First milestone │ ▓▓▓▓▓▓▓░░░ 4/6 done │ ▶ build: P1.2, P2.1 4m10s · 2 agents working │ ⟳ auto 3/25
Agents ● dev P1.2 sonnet  ● dev P2.1 sonnet
Context ▓▓▓░░░░░░░ 31% 62K/200K │ Tokens 2 in 195 out │ Cache 93% hit 3.8K write 55.5K read │ Cost $1.42 │ +303 −12
Limits 5h ▓▓░░░░░░░░ 23% (resets 2h13m) │ 7d ▓▓▓▓░░░░░░ 41% (resets 3d)
Sonnet 5.5 │ 10m22s (API 5m55s) │ main │ VBW 2.0.6 │ CC 2.1.286
```

1. **VBW:** the project, the milestone, a progress bar of requirements proven
   or accepted, and what is happening: a run in progress with its time and the
   agents working (`▶ build: P1.2 4m10s · 2 agents working`), a step that needs
   the user (`needs you: approve`), or the next step (`next: prove`, from the
   last `vbw next`). `⟳ auto 3/25` while this session's autonomous run is armed (another session's is not shown). Outside a
   VBW project: `/vbw:vibe to start` (this line, then lines 3 to 5).
2. **Agents or team** (VBW projects): while agents work, each one in its role's
   colour (architect magenta, lead blue, dev green, qa yellow, scout cyan,
   debugger red, docs pink) with its label and model. Otherwise the team: each role's model from the profile and
   any per-role override (`/vbw:config`), the profile, and how much VBW does on
   its own. An agent counts as working when its transcript, next to the
   session's, changed in the last minute; its `.meta.json` names its role,
   label and model.
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

The setting runs the newest installed VBW's `scripts/vbw-statusline.sh` from
the plugin cache, because the plugin's directory changes with every update and
settings cannot use `${CLAUDE_PLUGIN_ROOT}`. It is the same setting VBW 1 used,
so updating from VBW 1 switches the status line over with no change.

## Engineering

- One jq program renders all four lines from Claude Code's JSON, the record,
  and VBW's runtime state (`next.json`, and the session's own `auto.SESSION.json`).
- No network, no temporary files, no git process (the branch is read from
  `.git/HEAD`, also in linked worktrees).
- It reads stdin with a timeout (Claude Code may send nothing on the first
  render) and never fails: a bad render prints `[VBW] status line unavailable`.
- `NO_COLOR` turns the colors off.

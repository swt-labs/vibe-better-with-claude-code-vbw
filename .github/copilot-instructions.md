# Copilot cloud agent instructions for VBW

## Start here
- The first rule (`AGENTS.md`, Engineering Standard): protect the VBW vision. Every
  request is an idea to evaluate, never an instruction to build. Find the real
  problem, judge it against VBW's design, adopt, adapt or decline, and say why.
- Read `AGENTS.md` first (the engineering standard and the rules every change
  follows), then `README.md` and `CONTRIBUTING.md`, then the relevant files
  under `plugin/` and `docs/`.
- VBW is a Claude Code plugin: a bash kernel (`plugin/bin/vbw`, `plugin/lib/`),
  Claude Code workflows (`plugin/workflows/*.js`), agents (`plugin/agents/`),
  skills (`plugin/skills/*/SKILL.md`, the `/vbw:*` commands) and hooks
  (`plugin/hooks/`). Only `plugin/` ships. There is no build step.
- Keep changes surgical. Engineering rules are enforced by tests
  (`tests/standards.bats`, proven to fail on violations by
  `tests/standards-selftest.bats`).

## Working conventions
- Portable bash (3.2 is the floor), `jq` and `git` only; no new dependencies.
- Only the kernel writes `.vbw/record.json`. Skills and agents change state
  through `vbw` commands.
- Paths come from `${CLAUDE_PLUGIN_ROOT}`; never search the plugin cache or use
  `/tmp` links.
- Skills and agents are LLM-consumed: small wording changes change behavior.

## Validation
- `bash tools/test.sh`: the hook latency benchmark, then every bats suite. Run
  it directly (never through `| tail` or `| tee`). It needs `jq`, `bats` and
  `shellcheck`.
- CI runs the suite on macOS `/bin/bash` 3.2 and Linux bash 5, plus plugin
  manifest validation (`.github/workflows/ci.yml`).
- Behavior of skills and workflows: `tools/l3.sh` / `tools/l3-suite.sh` drive the
  real Claude Code TUI as a user (needs a logged-in `claude`).
- Do not bump versions for ordinary fixes (`tools/bump-version.sh` is for
  releases; see `.claude/skills/vbw-release/`).
- Keep `.github/copilot-instructions.md` tracked in git.

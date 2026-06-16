# Project overview

VBW is a Claude Code plugin that provides structured development workflows: plan, execute, and verify using specialized agent teams. It is implemented as bash scripts, markdown slash commands, agent definitions, hooks, templates, and JSON configuration with no external runtime dependencies beyond jq and git.

Major directories: commands/ for slash command markdown, agents/ for VBW agent definitions, scripts/ for bash helpers and state management, hooks/ for Claude Code hook definitions and handlers, references/ for command protocol docs, templates/ for generated planning artifacts, config/ for defaults/schemas/model profiles, docs/ and README.md for user-facing docs, testing/ for contract/BATS/lint checks.

Runtime state for consumer projects lives in .vbw-planning/ and is created by /vbw:init.
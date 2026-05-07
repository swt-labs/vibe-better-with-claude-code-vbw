# Style and conventions

- Commands are kebab-case markdown files in commands/; command frontmatter names are prefixed, e.g. vbw:init.
- Agents are named vbw-{role}.md; scripts are kebab-case .sh; phase directories use {NN}-{slug}/.
- Bash scripts target bash, not POSIX sh. Critical scripts use set -euo pipefail; otherwise set -u minimum.
- Use jq for JSON parsing, never grep/sed on JSON.
- YAML frontmatter description fields must be single-line.
- Keep VBW state in .vbw-planning/ and never cross-reference GSD .planning/ state.
- Prefer deterministic bash pre-extraction over making LLMs read large runtime files.
- Standalone one-line !`command` directives and fenced !`command` blocks execute in Claude templates; embedded ! spans do not.
- Root-cause fixes only; temporary mitigations must be paired with root-cause fixes.
- Do not run python/python3 in terminal except the explicitly allowed .github/scripts/wait-github.py helper.
- Use LSP-first navigation where LSP tools are available.
- Default communication style is direct and terse, no AI fluff, no opinion-soliciting endings.
---
name: teach
description: Teach Claude and VBW's agents this project's conventions (naming, structure, testing, style); saved as Claude Code rules in .claude/rules/.
argument-hint: "[the convention]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

The user said: $ARGUMENTS

Conventions live in `.claude/rules/*.md`, which every session and VBW agent
follows. A rule for part of the code gets `paths:` frontmatter, for example:

```markdown
---
paths:
  - "src/api/**"
---
- Every handler validates its input with the schemas in src/api/schemas.
```

- **A convention given:** read the existing `.claude/rules/*.md` first. If the
  new rule contradicts or repeats one, show both and ask whether to replace,
  keep both or cancel. Otherwise add it as one checkable bullet to the rule
  file for its topic (`naming.md`, `testing.md`, `structure.md`, `style.md`,
  `tooling.md`, `patterns.md`), with `paths:` for specific files.
- **Nothing given:** list the current rules by file. If `.vbw/map.md` exists,
  offer to turn its Conventions section into rules; propose them one by one
  and save only the ones the user accepts.

Write only under `.claude/rules/`. Show what was saved.

---
name: teach
description: Teach Claude and VBW's agents this project's conventions (naming, structure, testing, style); saved as Claude Code rules in .claude/rules/.
argument-hint: "[the convention]"
---

The user said: $ARGUMENTS

Conventions live in `.claude/rules/*.md`, Claude Code's own rule files: every
session and every VBW agent follows them automatically. A rule that applies
only to part of the code gets `paths:` frontmatter (glob patterns), for example:

```markdown
---
paths:
  - "src/api/**"
---
- Every handler validates its input with the schemas in src/api/schemas.
```

- **A convention given:** read the existing `.claude/rules/*.md` first. If the
  new rule contradicts or repeats one, show both and ask whether to replace,
  keep both or cancel. Otherwise add it as one clear, checkable bullet to the
  rule file for its topic (`naming.md`, `testing.md`, `structure.md`,
  `style.md`, `tooling.md`, `patterns.md`), creating it if needed, with `paths:`
  when it is about specific files.
- **Nothing given:** list the current rules by file. If `.vbw/map.md` exists,
  offer to turn its Conventions section into rules; propose them one by one
  and save only the ones the user accepts.

Write only under `.claude/rules/`. Show what was saved.

---
name: compress
description: Compress a long instruction file (CLAUDE.md, rules, docs for Claude) into terse caveman style to save tokens, keeping every fact, code block and path.
argument-hint: "path/to/file.md"
---

The file: $ARGUMENTS

If no file was given, ask for one. Only text files (`.md`, `.txt`, or no
extension). Copy the original next to it first (`<name>.original.md`), then
rewrite the file in place:

- **Remove:** articles (a, an, the), filler (just, really, basically,
  actually), pleasantries, hedging ("you might consider"), connective fluff
  (however, furthermore, additionally), and redundant phrasing ("in order to"
  becomes "to").
- **Keep exactly, byte for byte:** code blocks and inline code, URLs, file
  paths, commands, version numbers, environment variables, proper nouns.
- **Keep the structure:** every heading's text, list nesting, tables, and every
  rule and fact. Fragments are fine; meaning must not change.

Then report the size before and after (`wc -w`) and say that the original is
kept as `<name>.original.md`.

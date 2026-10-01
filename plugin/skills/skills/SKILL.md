---
name: skills
description: Find community skills (skills.sh) that fit this project's stack and install the ones the user picks.
argument-hint: "[what to search for]"
---

The user said: $ARGUMENTS

1. Work out the stack: from `.vbw/map.md` if it exists, otherwise from the
   project's manifest files (package.json, pyproject.toml, Cargo.toml, go.mod
   and so on). Name the main language, frameworks and test tools.
2. Search the skills registry for each (or for what the user asked):
   `npx skills find "<query>"`. If `npx` is missing, say that the skills CLI
   needs Node.js and stop.
3. Show at most 8 relevant results with what each does, skipping skills you
   already have (they are in your list of available skills).
4. Ask which to install and where (this project, or all projects). Install each
   chosen one with `npx skills add <skill> -y` (add `-g` for all projects).
   Nothing is installed without the user's choice. Skills work right away.

---
name: vbw:skills
category: supporting
disable-model-invocation: true
description: Browse and install community skills from skills.sh based on your project's tech stack.
argument-hint: [--search <query>] [--list] [--refresh]
allowed-tools: Read, Bash, Glob, Grep, WebFetch
---

# VBW Skills $ARGUMENTS

## Context

Working directory: `!`pwd``
Stack detection:
```
!`bash ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}/scripts/detect-stack.sh "$(pwd)" 2>/dev/null || echo '{"error":"detect-stack.sh failed"}'`
```

## Guard

1. **Script failure:** Context contains `"error"` → STOP: "Stack detection failed. Make sure jq is installed."

## Steps

### Step 1: Parse arguments

- **No args**: full flow (detect, show installed, suggest, offer install)
- **--search \<query\>**: skip curated, search registry for \<query\>
- **--list**: list installed only, no suggestions
- **--refresh**: force re-run stack detection

### Step 2: Display current state

From Context JSON: display installed skills (`installed.global[]` + `installed.project[]`) in single-line box. Display detected stack. If `--list`: STOP here.

### Step 3: Curated suggestions

From `suggestions[]` in Context JSON (recommended but not installed). Display in single-line box with `(curated)` tag.
- suggestions non-empty: show them
- empty + stack detected: "✓ All recommended skills already installed."
- no stack + no suggestions + find-skills available: suggest example searches
- no stack + find-skills unavailable: "○ No stack detected. Use --search <query>."

### Step 4: Dynamic registry search

**4a.** If `find_skills_available` is false: AskUserQuestion to install find-skills (`npx skills add vercel-labs/skills --skill find-skills -g -y`). Declined → skip to Step 5.

**4b.** Search when: --search passed (search for query) | no --search but unmapped stack items (auto-search each) | all mapped → skip.
Run `npx skills find "<query>"`. Display results with `(registry)` tag. If npx unavailable: "⚠ skills CLI not found."

### Step 5: Offer installation

Combine curated + registry, deduplicate, rank (curated first). AskUserQuestion multiSelect, max 4 options + "Skip". If >4: show top 4, suggest --search for more.

### Step 5b: Choose installation scope

AskUserQuestion (single select) — "Where should these skills be installed?":
- **Project (Recommended)** — "Installed to `./.claude/skills/`, scoped to this project only."
- **Global** — "Installed to `~/.agents/skills/`, available in all projects."

Store the choice as SCOPE. If "Skip" was selected in Step 5: skip this step.

### Step 6: Install selected

`npx skills add <skill> -y` (project scope) or `npx skills add <skill> -g -y` (global scope) per selection, based on SCOPE from Step 5b. Display ✓ or ✗ per skill. "➜ Skills take effect immediately — no restart needed."

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — single-line box, ✓ installed, ○ suggested, ✗ failed, ⚠ warning, no ANSI.

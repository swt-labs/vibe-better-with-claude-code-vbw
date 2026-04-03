---
name: vbw:profile
category: supporting
disable-model-invocation: true
description: Switch between work profiles or create custom ones. Profiles change effort, autonomy, and verification in one go.
argument-hint: "[profile-name | save | delete <name>]"
allowed-tools: Read, Write, Edit, AskUserQuestion
---

# VBW Profile $ARGUMENTS

## Context

Config:
```
!`cat .vbw-planning/config.json 2>/dev/null || echo "No config found -- run /vbw:init first"`
```

## Guard

If no .vbw-planning/ dir: STOP "Run /vbw:init first." (check `.vbw-planning/config.json`)

## Built-in Profiles

| Profile | Effort | Autonomy | Verification | Discovery | Use case |
|---------|--------|----------|--------------|-----------|----------|
| default | balanced | standard | standard | 3-5 questions | Fresh install baseline |
| prototype | fast | confident | quick | 1-2 quick | Rapid iteration |
| production | thorough | cautious | deep | 5-8 thorough | Production code |
| yolo | turbo | pure-vibe | skip | skip | No guardrails |

## Behavior

### No arguments: List and switch

1. Read config.json for `active_profile` (default: "default") + `custom_profiles`. Display table with * on active. If active_profile is "custom": show "Active: custom (modified from {last_profile})".
2. AskUserQuestion: "Which profile?" Options: all profiles + "Create new profile". Mark current "(active)".
3. Apply: update effort/autonomy/verification_tier in config.json, set active_profile. Display changed values with ➜. If already matching: "✓ Already on {name}". If "Create new profile": go to Save flow.

### `save`: Create custom profile

**S1.** AskUserQuestion: "From current settings" (use current values) | "From scratch" (pick each)
**S2.** If "From scratch", 3 AskUserQuestions:
- Effort: thorough | balanced | fast | turbo
- Autonomy: cautious | standard | confident | pure-vibe
- Verification: quick | standard | deep | skip

**S3.** AskUserQuestion for name: suggest 2-3 contextual names + user can type own.
**S4.** Validate: no built-in clash, no spaces (suggest hyphens), 1-30 chars. Add to `custom_profiles` in config.json. Ask "Switch to {name} now?" Apply if yes.

### Direct name: `profile <name>`

If $ARGUMENTS matches a profile: apply immediately (no listing). If unknown: "⚠ Unknown profile: {name}" + list available.

### `delete <name>`

Built-in: "⚠ Cannot delete built-in profile." Not found: "⚠ Profile not found." Otherwise: remove from custom_profiles. If active, reset to "default".

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — single-line box, ✓ success, ⚠ errors, ➜ transitions, no ANSI.

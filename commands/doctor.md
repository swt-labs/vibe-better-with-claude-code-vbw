---
name: vbw:doctor
category: supporting
disable-model-invocation: true
description: Run health checks on VBW installation and project setup.
allowed-tools: Read, Bash, Glob, Grep, LSP
---

# VBW Doctor

## Context

Working directory:
```
!`pwd`
```
Version: `!`cat VERSION 2>/dev/null || echo "none"``

## Checks

Run ALL checks below. For each, report PASS or FAIL with a one-line detail.

### 1. jq installed
`jq --version 2>/dev/null || echo "MISSING"`
FAIL if missing: "Install jq: brew install jq (macOS) or apt install jq (Linux)"

### 2. VERSION file exists
Check `VERSION` in repo root. FAIL if missing.

### 3. Version sync
`bash scripts/bump-version.sh --verify 2>&1`
FAIL if mismatch detected.

### 4. Plugin cache present
Check `${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/cache/vbw-marketplace/vbw/` exists and has at least one version directory. FAIL if empty or missing.

### 5. hooks.json valid
Parse `hooks/hooks.json` with `jq empty`. FAIL if parse error.

### 6. Agent files present
Glob `agents/vbw-*.md`. Expect 7 files (lead, dev, qa, scout, debugger, architect, docs). FAIL if any missing.

### 7. Config valid (project only)
If `.vbw-planning/config.json` exists, parse with `jq empty`. FAIL if parse error. SKIP if no project initialized.

### 8. Scripts executable
Check all `scripts/*.sh` files. WARN if any lack execute permission.

### 9. gh CLI available
`gh --version 2>/dev/null || echo "MISSING"`
WARN if missing: "Install gh for GitHub CLI integration (used by maintainer release tooling)."

### 10. sort -V support
`echo -e "1.0.2\n1.0.10" | sort -V 2>/dev/null | tail -1`
PASS if result is "1.0.10". WARN if sort -V unavailable (fallback will be used).

### Runtime Health

### 11. Stale teams
Run `bash scripts/doctor-cleanup.sh scan 2>/dev/null` and count lines starting with `stale_team|`.
PASS if 0. WARN if any, show count.

### 12. Orphaned processes
Count lines starting with `orphan_process|` from the scan output.
PASS if 0. WARN if any, show count.

### 13. Dangling PIDs
Count lines starting with `dangling_pid|` from the scan output.
PASS if 0. WARN if any, show count.

### 14. Stale markers
Count lines starting with `stale_marker|` from the scan output.
PASS if 0. WARN if any, list which markers.

### 15. Watchdog status
If $TMUX is set, check if .vbw-planning/.watchdog-pid exists and process is alive via kill -0.
PASS if alive or not in tmux. WARN if dead watchdog in tmux.

### 16. CLAUDE.md sections
If `.vbw-planning/` exists (project initialized):
- Run `bash scripts/check-claude-md-staleness.sh --json 2>/dev/null`
- Parse JSON output: `stale`, `missing_sections`, `version_mismatch`, `installed_version`, `marker_version`
- PASS if `stale` is false
- WARN if `stale` is true — show missing sections and/or version mismatch detail
- SKIP if no `.vbw-planning/` directory (not bootstrapped)

If user invoked with `--cleanup`: run `bash scripts/check-claude-md-staleness.sh --fix 2>&1` and report result. The fix must refresh only VBW-owned sections in place, preserve all other `CLAUDE.md` content verbatim, and add `## Code Intelligence` only when no Code Intelligence heading/guidance already exists.

## Output Format

```
VBW Doctor v{version}

  1. jq installed          {PASS|FAIL} {detail}
  2. VERSION file          {PASS|FAIL}
  3. Version sync          {PASS|FAIL} {detail}
  4. Plugin cache          {PASS|FAIL} {detail}
  5. hooks.json valid      {PASS|FAIL}
  6. Agent files           {PASS|FAIL} {count}/7
  7. Config valid          {PASS|FAIL|SKIP}
  8. Scripts executable    {PASS|WARN} {detail}
  9. gh CLI                {PASS|WARN}
 10. sort -V support       {PASS|WARN}
 11. Stale teams          {PASS|WARN} {count}
 12. Orphaned processes   {PASS|WARN} {count}
 13. Dangling PIDs        {PASS|WARN} {count}
 14. Stale markers        {PASS|WARN} {markers}
 15. Watchdog status      {PASS|WARN}
 16. CLAUDE.md sections   {PASS|WARN|SKIP}

Result: {N}/16 passed, {W} warnings, {F} failures
```

Use checkmark for PASS, warning triangle for WARN, X for FAIL.

### Cleanup

If any WARN from checks 11-14 or 16:
- Show cleanup preview listing all findings
- Display: "Run `/vbw:doctor --cleanup` to apply cleanup"

If user invoked with `--cleanup` (check for this in the command arguments):
- Run `bash scripts/doctor-cleanup.sh cleanup 2>&1` for runtime findings
- Run `bash scripts/check-claude-md-staleness.sh --fix 2>&1` for stale CLAUDE.md (non-destructive in-place refresh of VBW-owned sections only)
- Report what was cleaned
- Show updated counts

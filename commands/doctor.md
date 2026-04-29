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
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; SESSION_LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ] && [ -f "${SESSION_LINK}/scripts/hook-wrapper.sh" ]; then R="${SESSION_LINK}"; fi; if [ -z "$R" ]; then ANY_LINK=$(command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r link; do if [ -f "$link/scripts/hook-wrapper.sh" ]; then printf '%s\n' "$link"; break; fi; done || true); [ -n "$ANY_LINK" ] && R="$ANY_LINK"; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; LINK="${SESSION_LINK}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$LINK" "$REAL_R" >/dev/null 2>&1 || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```
Version:
```text
!`cat "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/VERSION" 2>/dev/null || echo "none"`
```

## Checks

Run ALL checks below. For each, report PASS or FAIL with a one-line detail. Replace `{plugin-root}` with the literal Plugin root value from Context.

### 1. jq installed
`jq --version 2>/dev/null || echo "MISSING"`
FAIL if missing: "Install jq: brew install jq (macOS) or apt install jq (Linux)"

### 2. VERSION file exists
Check `{plugin-root}/VERSION`. FAIL if missing.

### 3. Version sync
`bash "{plugin-root}/scripts/bump-version.sh" --verify 2>&1`
FAIL if mismatch detected.

### 4. Plugin cache present
Check `${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/cache/vbw-marketplace/vbw/` exists and has at least one version directory. FAIL if empty or missing.

### 5. hooks.json valid
Parse `{plugin-root}/hooks/hooks.json` with `jq empty`. FAIL if parse error.

### 6. Agent files present
Glob `{plugin-root}/agents/vbw-*.md`. Expect 7 files (lead, dev, qa, scout, debugger, architect, docs). FAIL if any missing.

### 7. Config valid (project only)
If `.vbw-planning/config.json` exists, parse with `jq empty`. FAIL if parse error. SKIP if no project initialized.

### 8. Scripts executable
Check all `{plugin-root}/scripts/*.sh` files. WARN if any lack execute permission.

### 9. gh CLI available
`gh --version 2>/dev/null || echo "MISSING"`
WARN if missing: "Install gh for GitHub CLI integration (used by maintainer release tooling)."

### 10. sort -V support
`echo -e "1.0.2\n1.0.10" | sort -V 2>/dev/null | tail -1`
PASS if result is "1.0.10". WARN if sort -V unavailable (fallback will be used).

### Runtime Health

### 11. Stale teams
Run `bash "{plugin-root}/scripts/doctor-cleanup.sh" scan 2>/dev/null` and count lines starting with `stale_team|`.
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
- Run `bash "{plugin-root}/scripts/check-claude-md-staleness.sh" --json 2>/dev/null`
- Parse JSON output: `stale`, `missing_sections`, `version_mismatch`, `installed_version`, `marker_version`
- PASS if `stale` is false
- WARN if `stale` is true — show missing sections and/or version mismatch detail
- SKIP if no `.vbw-planning/` directory (not bootstrapped)

If user invoked with `--cleanup`: run `bash "{plugin-root}/scripts/check-claude-md-staleness.sh" --fix 2>&1` and report result. The fix must refresh only VBW-owned sections in place, preserve all other `CLAUDE.md` content verbatim, and add `## Code Intelligence` only when no Code Intelligence heading/guidance already exists.

### 17. State consistency
If `.vbw-planning/` exists:
- Run `bash "{plugin-root}/scripts/verify-state-consistency.sh" .vbw-planning --mode advisory 2>/dev/null`
- Parse JSON output with jq: `.verdict`
- PASS if verdict is `"pass"`
- WARN if verdict is `"fail"` — show `.failed_checks` array
- SKIP if no `.vbw-planning/` directory (not bootstrapped)

### 18. RTK integration
Run `bash "{plugin-root}/scripts/rtk-manager.sh" doctor-json 2>/dev/null`.
- Parse JSON output: `doctor_status`, `doctor_detail`, `compatibility`, `compatibility_basis`, `updated_input_risk`, `proof_source`, `diagnostic_caveat`, `upstream_issue`
- SKIP only when RTK is absent and helper JSON reports no local/global RTK artifacts, no VBW RTK receipt, and no partial install evidence
- WARN when binary-only, hook-active-unverified, artifact-only, missing/error config, settings are unreadable, or a cached explicit update check says RTK is outdated
- PASS when `compatibility` is `"verified"` with a concrete `proof_source`, even if `updated_input_risk=true`; the runtime proof verifies this local RTK/VBW hook setup
- In normal output, do not warn solely because anthropics/claude-code#15897 still exists after proof. When invoked with `--verbose`, include `diagnostic_caveat`/`upstream_issue` as detail so the upstream caveat remains visible without downgrading health.
- Doctor must not query the network, run RTK history/stats, or run runtime smoke; runtime smoke requires explicit Claude Code Bash-tool orchestration and belongs in `/vbw:rtk verify`. Update availability may only come from cached explicit `/vbw:rtk status --check-updates` or `/vbw:rtk update` data.

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
 17. State consistency    {PASS|WARN|SKIP}
 18. RTK integration      {PASS|WARN|SKIP} {detail}

Result: {N}/18 passed, {W} warnings, {F} failures
```

Use checkmark for PASS, warning triangle for WARN, X for FAIL.

### Cleanup

If any WARN from checks 11-14, 16, or 17:
- Show cleanup preview listing all findings
- Display: "Run `/vbw:doctor --cleanup` to apply cleanup"

If user invoked with `--cleanup` (check for this in the command arguments):
- Run `bash "{plugin-root}/scripts/doctor-cleanup.sh" cleanup 2>&1` for runtime findings
- Run `bash "{plugin-root}/scripts/check-claude-md-staleness.sh" --fix 2>&1` for stale CLAUDE.md (non-destructive in-place refresh of VBW-owned sections only)
- Report what was cleaned
- Show updated counts

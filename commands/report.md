---
name: vbw:report
category: supporting
disable-model-invocation: true
description: Collect diagnostic context and file a GitHub issue.
argument-hint: "[problem description]"
allowed-tools: Read, Bash, Glob, Grep, mcp__github__issue_write
---

# VBW Report

## Context
Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}" && break; done; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$LINK" "$REAL_R" >/dev/null 2>&1 || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```
VBW version:
```
!`cat VERSION 2>/dev/null || echo "unknown"`
```

## Parse Arguments

Extract from `$ARGUMENTS`:
- Everything is the **problem description** (optional). No arguments is valid — the command still collects diagnostics and files with default placeholder text.

## Scope

This command collects diagnostics and files a GitHub issue — nothing else.

- Do not write files, save memories, create todos, update STATE.md, modify CLAUDE.md, or take any action beyond collecting diagnostics and filing the issue.
- The `Bash` tool is for running `collect-diagnostics.sh` and the `gh` issue-filing flow (including temp file scaffolding) described in this protocol. Do not use it for any other purpose.

## Steps

1. **Collect diagnostics.** Run the diagnostic collection script from the resolved plugin root. Pass the plugin root path as the first argument and the working directory as the second:
    ```bash
    bash <plugin-root>/scripts/collect-diagnostics.sh "<plugin-root>" "$(pwd)"
    ```
    Capture the full output.

2. **Display the report.** Show the diagnostic output verbatim inside a fenced code block. Do not paraphrase or reformat — the section headers and structure are designed for maintainer readability. If a problem description was provided, prepend it above the diagnostics:

    ```
    ## Problem Description
    {user's problem description from $ARGUMENTS}

    ## Diagnostic Report
    ```
    Then the fenced code block with the script output.

3. **Compose and file the issue.**

    a. Compose the issue content:
    - **Title**: Use the problem description, or `"Bug report from /vbw:report"` if none given.
    - **Body**: Format using the bug report template structure:
      - `**Command**`: The `/vbw:*` command that triggered the issue (ask the user if not in the problem description, or put "Not specified")
      - `**What happened**`: The problem description from `$ARGUMENTS`, or "Not provided — please edit"
      - `**What you expected**`: "Not provided — please edit this section"
      - `**Steps to reproduce**`: "Not provided — please edit this section"
      - `**Environment**`: Extract from the diagnostic output (VBW version, OS, Claude Code version, install method)
      - `**Additional context**`: The full diagnostic report output (the fenced block from step 2)

    b. Show the composed title and body as a brief preview so the user can see what will be filed.

    c. File the issue immediately using this fallback chain. Stop at the first method that succeeds:

    **Method 1 — `gh` CLI (if installed and authenticated):**

    Check: `gh auth status 2>/dev/null`

    If `gh` is installed and authenticated, file via temp files for safe quoting:
    ```bash
    ISSUE_BODY_FILE=$(mktemp /tmp/vbw-issue-body.XXXXXX.md)
    ISSUE_TITLE_FILE=$(mktemp /tmp/vbw-issue-title.XXXXXX.txt)
    trap 'rm -f "$ISSUE_BODY_FILE" "$ISSUE_TITLE_FILE"' EXIT

    cat > "$ISSUE_TITLE_FILE" << 'ISSUE_TITLE_EOF'
    <composed title>
    ISSUE_TITLE_EOF

    cat > "$ISSUE_BODY_FILE" << 'ISSUE_BODY_EOF'
    <composed body content>
    ISSUE_BODY_EOF

    gh issue create --repo swt-labs/vibe-better-with-claude-code-vbw \
      --title "$(cat "$ISSUE_TITLE_FILE")" \
      --label bug \
      --body-file "$ISSUE_BODY_FILE"
    ```

    **Method 2 — GitHub MCP server (if available):**

    If `gh` is not installed or not authenticated, check if `mcp__github__issue_write` is available in your tool list. If it is, call it with:
    - `method`: `create`
    - `owner`: `swt-labs`
    - `repo`: `vibe-better-with-claude-code-vbw`
    - `title`: The composed title
    - `body`: The composed body
    - `labels`: `["bug"]`
    - `assignees`: `["dpearson2699"]`

    **Method 3 — Install `gh` CLI, authenticate, then file:**

    If neither method 1 nor method 2 is available, install and set up `gh`:

    a. Detect the platform and install `gh`:
       - macOS: `brew install gh`
       - Debian/Ubuntu: `sudo apt install gh` (or the official install script)
       - Other: Direct the user to https://cli.github.com/ and skip to Method 4.

    b. After installation, authenticate:
       ```bash
       gh auth login --web
       ```
       Walk the user through the browser-based auth flow. Wait for authentication to complete successfully (`gh auth status` returns 0).

    c. Once authenticated, file the issue using the same `gh issue create` command from Method 1.

    **Method 4 — Manual fallback (last resort):**

    If all of the above fail (install refused, auth failed, network error, etc.), display:
    ```
    ⚠ Could not file issue automatically.
    File manually: https://github.com/swt-labs/vibe-better-with-claude-code-vbw/issues/new?template=bug_report.md

    Copy the diagnostic report above and paste it into the issue body.
    ```

    Stop here. Do not take any further action.

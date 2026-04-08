---
name: vbw:report
category: supporting
disable-model-invocation: true
description: Collect diagnostic context, classify bug or feature, and file a GitHub issue.
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
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then f=$( (unsetopt nomatch 2>/dev/null || true; ls -d /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh 2>/dev/null) | head -1); [ -n "$f" ] && [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}"; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$LINK" "$REAL_R" >/dev/null 2>&1 || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```
VBW version:
```
!`cat VERSION 2>/dev/null || echo "unknown"`
```

## Parse Arguments

`$ARGUMENTS` is the **problem description**.

- Everything in `$ARGUMENTS` is the description text.
- The description is optional. If it is empty, still collect diagnostics and file the issue using default placeholder text.
- If no description is provided, classify the issue as `bug` by default.

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

3. **Classify the issue.** Read the problem description and classify it as `bug` or `feature`:

    - **Bug**: the description reports something broken, an error, unexpected behavior, a crash, a regression, or a mismatch between expected and actual behavior.
    - **Feature**: the description requests something missing, a workflow improvement, a new capability, or a change to existing behavior that is not broken.
    - When the description is ambiguous or empty, classify as `bug`.

4. **Compose and file the issue.**

    a. Derive a concise issue title from the problem description — summarize to ~10 words. Do not use the raw description verbatim as the title. If no description is provided, use `"Bug report from /vbw:report"` for bugs or `"Feature request from /vbw:report"` for features.

    b. Compose the body using the template that matches the classification. Each section header must be bold on its own line, with content on the next line and a blank line between sections.

    <examples>
    <example>
    **Classification: bug** — use this body structure (matches `.github/ISSUE_TEMPLATE/bug_report.md`):

    ```
    **Command**
    {the /vbw:* command from the description, or "Not specified"}

    **What happened**
    {problem description from $ARGUMENTS, or "Not provided — please edit this section"}

    **What you expected**
    {inferred from description, or "Not provided — please edit this section"}

    **Steps to reproduce**
    {inferred from description, or "Not provided — please edit this section"}

    **Environment**
    - Claude Code version: {from diagnostics}
    - OS: {from diagnostics}
    - Plugin install method: {from diagnostics}
    - Model: Not specified

    **Additional context**
    {full diagnostic report output in a fenced code block}
    ```
    </example>

    <example>
    **Classification: feature** — use this body structure (matches `.github/ISSUE_TEMPLATE/feature_request.md`):

    ```
    **Problem**
    {problem description from $ARGUMENTS, or "Not provided — please edit this section"}

    **Proposed solution**
    {inferred from description, or "Not provided — please edit this section"}

    **Alternatives considered**
    Not provided — please edit this section

    **Additional context**
    {full diagnostic report output in a fenced code block}
    ```
    </example>
    </examples>

    c. Show the composed title and body as a brief preview so the user can see what will be filed.

    d. File the issue immediately using this fallback chain. Stop at the first method that succeeds:

    Set the label based on classification: `bug` for bugs, `enhancement` for features.

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
      --label <bug or enhancement> \
      --body-file "$ISSUE_BODY_FILE"
    ```

    **Method 2 — GitHub MCP server (if available):**

    If `gh` is not installed or not authenticated, check if `mcp__github__issue_write` is available in your tool list. If it is, call it with:
    - `method`: `create`
    - `owner`: `swt-labs`
    - `repo`: `vibe-better-with-claude-code-vbw`
    - `title`: The composed title
    - `body`: The composed body
    - `labels`: `["bug"]` or `["enhancement"]` based on classification
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

    If all of the above fail (install refused, auth failed, network error, etc.), display the composed issue title, body, and a link:
    ```
    ⚠ Could not file issue automatically.
    File manually: https://github.com/swt-labs/vibe-better-with-claude-code-vbw/issues/new?template=<bug_report.md or feature_request.md>

    Copy the composed issue body above and paste it into the issue form.
    ```
    Use `?template=bug_report.md` for bugs or `?template=feature_request.md` for features.

    Stop here. Do not take any further action.

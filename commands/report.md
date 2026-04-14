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
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; SESSION_LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ] && [ -f "${SESSION_LINK}/scripts/hook-wrapper.sh" ]; then R="${SESSION_LINK}"; fi; if [ -z "$R" ]; then ANY_LINK=$(command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r link; do if [ -f "$link/scripts/hook-wrapper.sh" ]; then printf '%s\n' "$link"; break; fi; done || true); [ -n "$ANY_LINK" ] && R="$ANY_LINK"; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; LINK="${SESSION_LINK}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$LINK" "$REAL_R" >/dev/null 2>&1 || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
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

1. **Collect diagnostics and persist to temp file.** Run the diagnostic collection script from the resolved plugin root. Pass the plugin root path as the first argument and the working directory as the second. Persist the output to a temp file so it can be embedded verbatim in the issue body later, even if context compaction occurs between this step and the filing step:
    ```bash
    DIAG_FILE="/tmp/vbw-diag-report-${CLAUDE_SESSION_ID:-default}.txt"
    bash <plugin-root>/scripts/collect-diagnostics.sh "<plugin-root>" "$(pwd)" | tee "$DIAG_FILE"
    echo "DIAG_FILE=$DIAG_FILE"
    ```
    The diagnostic output appears in this tool result for display (step 2) and classification (step 3). The temp file path is session-scoped via `CLAUDE_SESSION_ID` (set by VBW hooks) — deterministic across separate Bash invocations within a session and unique across concurrent sessions. When `CLAUDE_SESSION_ID` is unset, the literal `default` fallback keeps the path deterministic but shared across concurrent sessions (acceptable since this only applies when VBW hooks are inactive). Note the `DIAG_FILE=...` path printed at the end for use in step 4.

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

    The **Additional context** section contains the full diagnostic report collected in step 1. This diagnostic content is appended from the temp file (`$DIAG_FILE`) created in step 1 — do not reproduce the diagnostic output from memory. Write only the `**Additional context**` header in the body; the bash script handles appending the diagnostic content from the temp file.

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
    {diagnostic report — appended from temp file in the filing step, not written here}
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
    {diagnostic report — appended from temp file in the filing step, not written here}
    ```
    </example>
    </examples>

    c. Show the composed title and body as a brief preview so the user can see what will be filed.

    d. File the issue immediately using this fallback chain. Stop at the first method that succeeds:

    Set the label based on classification: `bug` for bugs, `enhancement` for features.

    **Method 1 — `gh` CLI (if installed and authenticated):**

    Check: `gh auth status 2>/dev/null`

    If `gh` is installed and authenticated, file via temp files for safe quoting. The body heredoc contains everything except the diagnostic report. The diagnostic content is appended from the temp file created in step 1:
    ```bash
    DIAG_FILE="/tmp/vbw-diag-report-${CLAUDE_SESSION_ID:-default}.txt"
    ISSUE_BODY_FILE=$(mktemp /tmp/vbw-issue-body.XXXXXX.md)
    ISSUE_TITLE_FILE=$(mktemp /tmp/vbw-issue-title.XXXXXX.txt)
    trap 'rm -f "$ISSUE_BODY_FILE" "$ISSUE_TITLE_FILE"' EXIT

    cat > "$ISSUE_TITLE_FILE" << 'ISSUE_TITLE_EOF'
    <composed title>
    ISSUE_TITLE_EOF

    cat > "$ISSUE_BODY_FILE" << 'ISSUE_BODY_EOF'
    <composed body sections WITHOUT the diagnostic report>

    **Additional context**
    ISSUE_BODY_EOF

    # Append the full diagnostic report from the temp file
    printf '```\n' >> "$ISSUE_BODY_FILE"
    cat "$DIAG_FILE" >> "$ISSUE_BODY_FILE"
    printf '```\n' >> "$ISSUE_BODY_FILE"

    if gh issue create --repo swt-labs/vibe-better-with-claude-code-vbw \
      --title "$(cat "$ISSUE_TITLE_FILE")" \
      --label <bug or enhancement> \
      --body-file "$ISSUE_BODY_FILE"; then
      rm -f "$DIAG_FILE"
    fi
    ```

    **Method 2 — GitHub MCP server (if available):**

    If `gh` is not installed or not authenticated, check if `mcp__github__issue_write` is available in your tool list. If it is, first read the diagnostic report from the temp file (`cat "$DIAG_FILE"`). Compose the full body by combining the non-diagnostic sections with the diagnostic output in a code fence under `**Additional context**`. Call the tool with:
    - `method`: `create`
    - `owner`: `swt-labs`
    - `repo`: `vibe-better-with-claude-code-vbw`
    - `title`: The composed title
    - `body`: The composed body (with full diagnostic report from the temp file)
    - `labels`: `["bug"]` or `["enhancement"]` based on classification
    - `assignees`: `["dpearson2699"]`

    After the MCP call succeeds, clean up the temp file: `rm -f "$DIAG_FILE"`.

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

    If all of the above fail (install refused, auth failed, network error, etc.), read the diagnostic report from the temp file (`cat "$DIAG_FILE"`), clean it up (`rm -f "$DIAG_FILE"`), and display the composed issue title, body (with full diagnostics), and a link:
    ```
    ⚠ Could not file issue automatically.
    File manually: https://github.com/swt-labs/vibe-better-with-claude-code-vbw/issues/new?template=<bug_report.md or feature_request.md>

    Copy the composed issue body above and paste it into the issue form.
    ```
    Use `?template=bug_report.md` for bugs or `?template=feature_request.md` for features.

    Stop here. Do not take any further action.

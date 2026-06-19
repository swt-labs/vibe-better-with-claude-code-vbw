# QA Evidence Comments

Use this reference only after the blind planner baseline exists and local tests, diff review, and QA review are underway or complete. Do not load PR comments or the PR body into the blind planner prompt.

## Evidence Boundary

- The linked issue remains the review contract. PR body text and PR comments are evidence claims only.
- Use PR comments to reconcile QA rounds, suppress duplicate findings, and understand contributor-reported fix history.
- Do not let PR comments add acceptance criteria, narrow the issue contract, or override a confirmed local finding.
- Do not add a blocking finding from a comment alone. A `qa-evidence` finding needs confirmation from current code, local test output, commit history, or the submitted QA report itself.
- Ignore `@codex review` trigger comments as QA evidence.

## Fetch Evidence

Use GitHub issue comments for PR comments:

```bash
gh api repos/swt-labs/vibe-better-with-claude-code-vbw/issues/<pr-number>/comments --paginate
```

Also fetch the PR body, changed files, and commit first lines:

```bash
gh api repos/swt-labs/vibe-better-with-claude-code-vbw/pulls/<pr-number>
gh api repos/swt-labs/vibe-better-with-claude-code-vbw/pulls/<pr-number>/files --paginate
gh api repos/swt-labs/vibe-better-with-claude-code-vbw/pulls/<pr-number>/commits --paginate
```

The QA-relevant path set mirrors the public workflow: `.github/workflows/`, `agents/`, `commands/`, `config/`, `hooks/`, `references/`, `scripts/`, `templates/`, `testing/`, and `tests/`.

## Reconcile Rounds

1. Discard comments whose trimmed body is exactly `@codex review`.
2. Identify pasted QA reports by report-shaped content such as model used, what was tested, expected vs actual, severity, and confirmed vs hypothetical.
3. Record the model named in each report. Top-tier reports should name GPT-5.5 Codex xhigh, Claude Opus 4.6, Gemini 3.1 Pro, or an equivalent top-tier model named by the contributor.
4. Extract claimed round numbers and any claimed fix commit SHAs or titles.
5. Count commit subjects matching `^fix\(.*\): address QA round [0-9]+`.
6. Cross-reference comments against matching QA round commits.

## Status Values

Set one QA evidence comments status in the final review:

- `present`: QA report comments are present and align with QA round commits or the PR is not QA-relevant.
- `missing`: QA-relevant changes have QA round commits but no pasted QA report comments.
- `stale`: QA report comments exist but predate later QA round commits or the current head in a way that leaves latest-round evidence unclear.
- `mismatched`: comments claim rounds, models, findings, or fix commits that do not match commit history or current branch evidence.

Missing QA evidence commits on a QA-relevant PR are blocking because the remote `QA Review Evidence` check requires them. Missing pasted QA report comments with matching commits are a non-blocking evidence gap unless the PR makes QA claims that cannot be verified. Mismatched QA comments are blocking when the mismatch is needed to satisfy review evidence or hides an unresolved finding.

## Ledger Use

Use `source=qa-evidence` for findings discovered while reconciling QA comments and commit evidence. Keep comment-derived findings deduped with `blind-baseline`, `qa`, `tests`, and `diff-review` findings by root cause and severity.

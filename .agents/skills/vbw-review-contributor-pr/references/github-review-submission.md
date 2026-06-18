# GitHub Review Submission

Use this reference only at the final review-emission phase. The goal is a normal GitHub pull request review, not a standalone PR comment and not a summary-only requested-changes body when line-specific findings exist.

## Submission contract

Build a `review_finding_ledger` before posting:

| field | meaning |
| --- | --- |
| `id` | Stable finding id such as `VBW-PR-001`; include it in inline and summary text. |
| `severity` | `blocker`, `non_blocking`, or `info`. |
| `source` | `blind-baseline`, `qa`, `tests`, `diff-review`, or combined source list. |
| `path` | Repository-relative changed file path, or empty when unanchorable. |
| `line` | Blob line number in the PR diff. |
| `side` | `RIGHT` for additions/context, `LEFT` for deletions. |
| `anchor_status` | `valid`, `unanchorable`, `duplicate`, or `over_cap`. |
| `inline_body` | Short review comment body for the code line. |
| `summary_body` | Review body text when the finding is not inline or needs extra context. |

For `REQUEST_CHANGES`, every unique blocking finding with `anchor_status=valid` must become an inline review comment unless the 12-comment cap is reached. Deduplicate by root cause and severity before applying the cap.

Use `line` + `side` for line comments. Avoid `position`; GitHub treats it as legacy and it is easier to miscompute. Use `start_line` / `start_side` only when a multi-line range materially improves the comment.

## Tool preference

Prefer the GitHub app tool when it is available:

```text
_add_review_to_pr(
  repo_full_name="swt-labs/vibe-better-with-claude-code-vbw",
  pr_number=<number>,
  action="REQUEST_CHANGES" | "APPROVE" | "COMMENT",
  commit_id=<head_sha>,
  review=<body>,
  file_comments=[
    {
      "path": "scripts/example.sh",
      "line": 42,
      "side": "RIGHT",
      "body": "VBW-PR-001: explain the blocker here."
    }
  ]
)
```

If the GitHub app tool is unavailable, use `gh api` with the same shape:

```bash
gh api \
  repos/swt-labs/vibe-better-with-claude-code-vbw/pulls/<pr-number>/reviews \
  --method POST \
  --input <json-file>
```

The JSON file must contain `event`, `body`, `commit_id`, and `comments`. The `comments` entries use `path`, `line`, `side`, and `body`.

Do not use `gh pr review` when inline comments are expected. It is acceptable only for zero-anchor reviews because it cannot submit the required inline comment payload.

## Review body

The review body should summarize the verdict and preserve audit evidence without duplicating every inline comment. Include these sections when relevant:

```markdown
Verdict: REQUEST_CHANGES

Blocking findings are inline where GitHub could anchor them.

Unanchored blockers:
- VBW-PR-003: <summary>. Reason: <not in changed diff | duplicate | over cap | stale line>.

Evidence:
- Linked issue: #<issue>.
- Tests: <result>.
- Blind baseline: <status>.
- QA: <status>.
```

For `APPROVE`, keep the body short and still include the issue, tests, planner baseline, and QA status. For `COMMENT`, explain why the review is informational or blocked.

## Verification gate

After posting, verify against GitHub before reporting success:

1. Fetch PR reviews and identify the latest review by the actor.
2. Confirm its state matches the intended action: `APPROVED`, `CHANGES_REQUESTED`, or `COMMENTED`.
3. Confirm its `commit_id` matches the PR head SHA used for submission.
4. Confirm its body contains the expected finding ids or review marker.
5. Fetch inline review threads or review comments and confirm every expected inline finding id appears on the expected `path`, `line`, and `side`.
6. Record the review URL, state, inline comment count, and unanchored finding ids for the final user response.

If any verification step fails, do not claim success. Report the failed gate and the current GitHub state observed.

## Failure handling

- Invalid or stale anchor before submission: mark the finding `unanchorable` and move it to `Unanchored blockers`, or abort before posting if too many blockers lose anchors to preserve review quality.
- GitHub 422 on submission: re-check that each inline comment targets a changed file and line in the current PR diff, then retry once with invalid anchors demoted to summary. Do not keep retrying unchanged payloads.
- Auth or permission failure: stop and report the exact failure. Do not fall back to a plain PR comment for the official verdict unless the user explicitly authorizes that degraded path.
- Partial uncertainty after posting: fetch reviews and review threads again. If the system of record still does not match the intended review, report degraded status rather than asserting completion.

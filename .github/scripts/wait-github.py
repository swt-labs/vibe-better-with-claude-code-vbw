#!/usr/bin/env python3
"""ETag-based polling for GitHub PR events.

Subcommands:
    wait-review  Wait for a fresh Copilot PR review.
    wait-ci      Wait for CI check runs to complete on a commit.

Both use ETag conditional requests (HTTP 304s are free against GitHub rate
limits) for efficient polling without burning through API quota.

Usage:
    python3 wait-github.py wait-review --pr 123 --repo owner/repo --push-ts 2025-01-01T00:00:00Z --head-sha abc123
    python3 wait-github.py wait-ci --repo owner/repo --sha abc123
"""

import argparse
import json
import subprocess
import sys
import time
from typing import Any, cast

# ---------------------------------------------------------------------------
# Shared utilities
# ---------------------------------------------------------------------------

def gh_api(
    endpoint: str,
    *,
    include_headers: bool = False,
    extra_args: list[str] | None = None,
) -> tuple[int | None, dict[str, str], str]:
    """Call gh api and return (status_code, headers_dict, body_string).

    When include_headers=False, status_code is None and headers is empty.
    """
    cmd = ["gh", "api", endpoint]
    if include_headers:
        cmd.append("-i")
    if extra_args:
        cmd.extend(extra_args)

    result = subprocess.run(cmd, capture_output=True, text=True)
    raw = result.stdout

    if not include_headers:
        return None, {}, raw

    # gh api -i returns: HTTP status line, headers, blank line, body
    lines = raw.split("\n")
    status_code = None
    headers: dict[str, str] = {}
    body_start = 0

    # Parse status line
    if lines and lines[0].startswith("HTTP/"):
        parts = lines[0].split(None, 2)
        if len(parts) >= 2:
            try:
                status_code = int(parts[1])
            except ValueError:
                pass
        body_start = 1

    # Parse headers until blank line
    for i in range(body_start, len(lines)):
        line = lines[i].strip("\r")
        if not line:
            body_start = i + 1
            break
        if ":" in line:
            key, _, value = line.partition(":")
            headers[key.strip().lower()] = value.strip()

    body = "\n".join(lines[body_start:])
    return status_code, headers, body


# ---------------------------------------------------------------------------
# wait-review subcommand
# ---------------------------------------------------------------------------

REVIEWER_LOGINS = frozenset([
    "copilot-pull-request-reviewer[bot]",
    "copilot-pull-request-reviewer",
])

Review = dict[str, Any]


def normalize_sha(value: str | None) -> str:
    """Normalize a commit SHA or prefix for comparison."""
    return (value or "").strip().lower()


def commit_matches(review_commit_id: str | None, head_sha: str | None) -> bool:
    """Return True when a review commit matches the requested SHA.

    The workflow intends to pass the full 40-character HEAD SHA, but the wait
    script is intentionally tolerant of a short SHA prefix because ad-hoc
    callers (or model-generated repair commands) may reuse a 7+ character
    `git log --oneline` style SHA. The review commit returned by GitHub is
    always the full SHA.
    """
    review_commit = normalize_sha(review_commit_id)
    requested = normalize_sha(head_sha)

    if not review_commit or not requested:
        return False

    return review_commit == requested or (
        len(requested) >= 7 and review_commit.startswith(requested)
    )


def parse_review_list(body: str) -> list[Review]:
    """Parse a GitHub reviews payload into a flat list of review dicts.

    `gh api --paginate --slurp` returns a JSON array of pages, where each page
    is itself a JSON array. A non-paginated call returns a single JSON array.
    """
    try:
        payload = json.loads(body)
    except (json.JSONDecodeError, TypeError):
        return []

    if not isinstance(payload, list):
        return []

    payload_list = cast(list[Any], payload)
    reviews: list[Review] = []
    if payload_list and all(isinstance(page, list) for page in payload_list):
        paged_payload = cast(list[list[Any]], payload_list)
        for page in paged_payload:
            for review in page:
                if isinstance(review, dict):
                    reviews.append(cast(Review, review))
        return reviews

    for review in payload_list:
        if isinstance(review, dict):
            reviews.append(cast(Review, review))

    return reviews


def find_fresh_review(
    reviews: list[Review],
    push_ts: str,
    head_sha: str,
) -> tuple[str | None, Review | None]:
    """Find the latest Copilot review for the current pushed commit.

    Returns (state, review_json) or (None, None).
    """
    fresh: Review | None = None
    for review in reviews:
        user = review.get("user")
        if isinstance(user, dict):
            user_dict = cast(dict[str, Any], user)
            login_raw = user_dict.get("login")
            login = login_raw if isinstance(login_raw, str) else ""
        else:
            login = ""
        submitted_raw = review.get("submitted_at")
        submitted = submitted_raw if isinstance(submitted_raw, str) else ""
        commit_raw = review.get("commit_id")
        commit_id = commit_raw if isinstance(commit_raw, str) else ""
        if (
            login in REVIEWER_LOGINS
            and submitted >= push_ts
            and commit_matches(commit_id, head_sha)
        ):
            fresh = review  # keep scanning — we want the last match

    if fresh:
        state_raw = fresh.get("state")
        state = state_raw if isinstance(state_raw, str) else None
        return state, fresh
    return None, None


def fetch_all_reviews(repo: str, pr: int) -> list[Review]:
    """Fetch all review pages for a PR and return a flat list of reviews."""
    endpoint = f"repos/{repo}/pulls/{pr}/reviews?per_page=100"
    _, _, body = gh_api(endpoint, extra_args=["--paginate", "--slurp"])
    return parse_review_list(body)


def cmd_wait_review(args: argparse.Namespace) -> None:
    """Wait for a fresh Copilot review on a PR."""
    poll_endpoint = f"repos/{args.repo}/pulls/{args.pr}"
    start = time.monotonic()

    # Phase 1: Immediate check — a fresh review may already exist.
    reviews = fetch_all_reviews(args.repo, args.pr)
    status, headers, body = gh_api(poll_endpoint, include_headers=True)
    etag = headers.get("etag", "")
    print(
        f"[debug] ETag={etag or '(none)'}, reviews={len(reviews)}, "
        f"pr_body={len(body)} chars"
    )

    state, review = find_fresh_review(reviews, args.push_ts, args.head_sha)
    if state:
        print(f"REVIEW_READY|state={state}")
        print(json.dumps(review, indent=2))
        return

    # Phase 2: ETag polling loop — 304s are free against GitHub rate limit.
    # Poll the PR resource, not the reviews list, because the reviews list is
    # paginated oldest-first and page 1 can become permanently stale.
    print(f"Polling every {args.poll_interval}s with ETag conditional requests...")
    while True:
        elapsed = time.monotonic() - start
        if elapsed >= args.timeout:
            print(f"TIMEOUT after {args.timeout}s — no fresh review detected")
            sys.exit(1)

        time.sleep(args.poll_interval)

        extra = []
        if etag:
            extra = ["-H", f"If-None-Match: {etag}"]
        status, new_headers, body = gh_api(
            poll_endpoint, include_headers=True, extra_args=extra,
        )

        if status == 304:
            continue  # No change — free request

        # 200 = PR changed — update ETag and re-read the full review history.
        if new_headers.get("etag"):
            etag = new_headers["etag"]

        reviews = fetch_all_reviews(args.repo, args.pr)
        state, review = find_fresh_review(reviews, args.push_ts, args.head_sha)
        if state:
            print(f"REVIEW_READY|state={state}")
            print(json.dumps(review, indent=2))
            return


# ---------------------------------------------------------------------------
# wait-ci subcommand
# ---------------------------------------------------------------------------

def cmd_wait_ci(args: argparse.Namespace) -> None:
    """Wait for CI check runs to complete on a commit."""
    endpoint = f"repos/{args.repo}/commits/{args.sha}/check-runs"
    start = time.monotonic()

    # Initial fetch with ETag capture.
    status, headers, body = gh_api(endpoint, include_headers=True)
    etag = headers.get("etag", "")
    print(f"[debug] ETag={etag or '(none)'}, body={len(body)} chars")

    while True:
        result = _evaluate_check_runs(body, args.sha)
        if result:
            print(result)
            if result.startswith("CI_FAILURE"):
                sys.exit(2)
            return

        elapsed = time.monotonic() - start
        if elapsed >= args.timeout:
            pending_names = _pending_check_names(body)
            print(f"TIMEOUT after {args.timeout}s — checks still pending")
            for name in pending_names:
                print(f"PENDING: {name}")
            sys.exit(1)

        time.sleep(args.poll_interval)

        extra = []
        if etag:
            extra = ["-H", f"If-None-Match: {etag}"]
        status, new_headers, body = gh_api(
            endpoint, include_headers=True, extra_args=extra,
        )

        if status == 304:
            continue  # No change — free request

        if new_headers.get("etag"):
            etag = new_headers["etag"]


def _evaluate_check_runs(body: str, sha: str) -> str | None:
    """Evaluate check-run JSON. Returns a result string or None if still pending."""
    try:
        data = json.loads(body)
    except (json.JSONDecodeError, TypeError):
        return None

    check_runs = data.get("check_runs", [])
    total = data.get("total_count", 0)

    if total == 0:
        return f"NO_CHECKS — no check runs found on {sha}"

    failed = [cr for cr in check_runs if cr.get("conclusion") == "failure"]
    pending = [cr for cr in check_runs if cr.get("status") != "completed"]

    if failed:
        lines = ["CI_FAILURE"]
        for cr in failed:
            lines.append(f"FAILED: {cr.get('name', '(unknown)')}")
        return "\n".join(lines)

    if not pending:
        lines = [f"CI_GREEN — all {total} checks passed"]
        for cr in check_runs:
            lines.append(f"{cr.get('name', '(unknown)')}: {cr.get('conclusion', '?')}")
        return "\n".join(lines)

    return None  # Still pending


def _pending_check_names(body: str) -> list[str]:
    """Extract names of pending check runs from JSON body."""
    try:
        data = json.loads(body)
    except (json.JSONDecodeError, TypeError):
        return []
    return [
        f"{cr.get('name', '(unknown)')} ({cr.get('status', '?')})"
        for cr in data.get("check_runs", [])
        if cr.get("status") != "completed"
    ]


# ---------------------------------------------------------------------------
# CLI entrypoint
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="ETag-based polling for GitHub PR events",
    )
    subparsers = parser.add_subparsers(dest="command")

    # wait-review
    review_parser = subparsers.add_parser(
        "wait-review",
        help="Wait for a fresh Copilot PR review",
    )
    review_parser.add_argument("--pr", required=True, type=int, help="PR number")
    review_parser.add_argument("--repo", required=True, help="owner/repo")
    review_parser.add_argument("--push-ts", required=True, help="ISO8601 timestamp captured immediately before the triggering push")
    review_parser.add_argument("--head-sha", required=True, help="Exact commit SHA or unique prefix that the review must target")
    review_parser.add_argument("--timeout", type=int, default=600, help="Max seconds to wait (default: 600)")
    review_parser.add_argument("--poll-interval", type=int, default=5, help="Seconds between polls (default: 5)")

    # wait-ci
    ci_parser = subparsers.add_parser(
        "wait-ci",
        help="Wait for CI check runs to complete on a commit",
    )
    ci_parser.add_argument("--repo", required=True, help="owner/repo")
    ci_parser.add_argument("--sha", required=True, help="Commit SHA to check")
    ci_parser.add_argument("--timeout", type=int, default=900, help="Max seconds to wait (default: 900)")
    ci_parser.add_argument("--poll-interval", type=int, default=10, help="Seconds between polls (default: 10)")

    args = parser.parse_args()

    if args.command == "wait-review":
        cmd_wait_review(args)
    elif args.command == "wait-ci":
        cmd_wait_ci(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()

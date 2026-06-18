#!/usr/bin/env python3
"""ETag-based polling for GitHub PR events.

Subcommands:
    wait-ci      Wait for CI check runs to complete on a commit.

Both use ETag conditional requests (HTTP 304s are free against GitHub rate
limits) for efficient polling without burning through API quota.

Usage:
    python3 wait-github.py wait-ci --repo owner/repo --sha abc123
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from typing import Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Shared utilities
# ---------------------------------------------------------------------------


class GhApiError(RuntimeError):
    """Raised when `gh api` exits non-zero."""

    def __init__(self, endpoint: str, returncode: int, stderr: str):
        self.endpoint = endpoint
        self.returncode = returncode
        self.stderr = stderr
        super().__init__(
            f"gh api failed for {endpoint} with exit code {returncode}: {stderr}"
        )

def gh_api(
    endpoint: str,
    *,
    include_headers: bool = False,
    extra_args: Optional[List[str]] = None,
) -> Tuple[Optional[int], Dict[str, str], str]:
    """Call gh api and return (status_code, headers_dict, body_string).

    When include_headers=False, status_code is None and headers is empty.
    """
    cmd = ["gh", "api", endpoint]
    if include_headers:
        cmd.append("-i")
    if extra_args:
        cmd.extend(extra_args)

    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
    except OSError as exc:
        raise GhApiError(
            endpoint,
            127,
            f"failed to execute gh api: {exc}. Ensure GitHub CLI (`gh`) is installed and available on PATH.",
        ) from exc
    if result.returncode != 0:
        # gh api exits non-zero for HTTP 304 (Not Modified) when using
        # conditional requests (If-None-Match).  When include_headers is
        # True the caller expects to inspect the status code, so parse the
        # output first and only raise if it's not a 304.
        if include_headers and "HTTP/" in (result.stdout or ""):
            first_line = result.stdout.split("\n", 1)[0]
            parts = first_line.split(None, 2)
            if len(parts) >= 2 and parts[1] == "304":
                # Fall through to normal header/body parsing below.
                pass
            else:
                stderr = result.stderr.strip() or result.stdout.strip() or "unknown gh api error"
                raise GhApiError(endpoint, result.returncode, stderr)
        else:
            stderr = result.stderr.strip() or result.stdout.strip() or "unknown gh api error"
            raise GhApiError(endpoint, result.returncode, stderr)

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
# wait-ci subcommand
# ---------------------------------------------------------------------------

def cmd_wait_ci(args: argparse.Namespace) -> None:
    """Wait for CI check runs to complete on a commit."""
    # Request the maximum page size so a commit with many check runs does
    # not silently pass because only the first page (default 30) looks
    # green. `_evaluate_check_runs` also detects truncation and keeps
    # polling when total_count > returned items, so this is defensive.
    endpoint = f"repos/{args.repo}/commits/{args.sha}/check-runs?per_page=100"
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
            if result.startswith("CI_ERROR"):
                sys.exit(1)
            # NO_CHECKS is not a terminal success — CI may not have registered yet.
            # Keep polling until checks appear, CI_GREEN, CI_FAILURE, CI_ERROR,
            # or timeout.
            if not result.startswith("NO_CHECKS"):
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
        status, new_headers, new_body = gh_api(
            endpoint, include_headers=True, extra_args=extra,
        )

        if status == 304:
            continue  # No change — free request, preserve previous body

        # 200 = content changed — update body and ETag.
        body = new_body
        if new_headers.get("etag"):
            etag = new_headers["etag"]


def _evaluate_check_runs(body: str, sha: str) -> Optional[str]:
    """Evaluate check-run JSON. Returns a result string or None if still pending."""
    try:
        data = json.loads(body)
    except (json.JSONDecodeError, TypeError):
        return None

    check_runs = data.get("check_runs", [])
    total = data.get("total_count", 0)

    if total == 0:
        return f"NO_CHECKS — no check runs found on {sha}"

    # If the API says there are more check runs than we received, we're
    # looking at a truncated page. per_page=100 is the max for this endpoint,
    # so if total_count exceeds 100 continued polling will never produce a
    # complete single-page result. Treat as a terminal error.
    if len(check_runs) < total:
        message = (
            f"CI_ERROR — check-runs response truncated for {sha}: got "
            f"{len(check_runs)} of {total}. This endpoint requires pagination "
            f"to evaluate all check runs; update the caller to paginate and "
            f"aggregate results instead of polling a single page."
        )
        print(f"[error] {message}", file=sys.stderr)
        return message

    allowed_completed_conclusions = {"success", "neutral", "skipped"}
    failed = [
        cr
        for cr in check_runs
        if cr.get("status") == "completed"
        and cr.get("conclusion") not in allowed_completed_conclusions
    ]
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


def _pending_check_names(body: str) -> List[str]:
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
    try:
        parser = argparse.ArgumentParser(
            description="ETag-based polling for GitHub PR events",
        )
        subparsers = parser.add_subparsers(dest="command")

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

        if args.command == "wait-ci":
            cmd_wait_ci(args)
        else:
            parser.print_help()
            sys.exit(1)
    except GhApiError as exc:
        print(
            f"GH_API_ERROR endpoint={exc.endpoint} exit_code={exc.returncode}",
            file=sys.stderr,
        )
        print(exc.stderr, file=sys.stderr)
        sys.exit(3)


if __name__ == "__main__":
    main()

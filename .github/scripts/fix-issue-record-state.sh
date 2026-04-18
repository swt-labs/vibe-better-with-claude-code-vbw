#!/usr/bin/env bash
# Record fix-issue state for the Stop hook's Tier 1 targeting path.
#
# Usage: fix-issue-record-state.sh <pr_number> <branch> <worktree_path> <issue_number>
#
# Discovers the current VS Code Copilot session_id by finding the most
# recently modified transcript JSONL under the Copilot workspace storage
# (mtime within 120 seconds) and writes
# /tmp/fix-issue-vbw-state-<session_id>.json containing:
#   { session_id, pr_number, branch, worktree_path, issue_number, updated_at }
#
# The Stop hook (.github/hooks/fix-issue-stop-guard.sh) reads this file to
# validate only the thread's own PR. The file is deleted by the Stop hook
# on a clean pass, or can be removed manually.
#
# Exit codes:
#   0 on success (state file written)
#   1 on bad args
#   2 when session_id cannot be discovered (still prints a warning; caller
#     should proceed — Stop hook falls back to transcript inference).

set -euo pipefail

if [ "$#" -ne 4 ]; then
  printf 'usage: %s <pr_number> <branch> <worktree_path> <issue_number>\n' "$0" >&2
  exit 1
fi

pr_number="$1"
branch="$2"
worktree_path="$3"
issue_number="$4"

require_non_negative_integer() {
  local field_name="$1"
  local value="$2"

  case "$value" in
    ''|*[!0-9]*)
      printf 'fix-issue-record-state: %s must be a non-negative integer (got %s)\n' "$field_name" "$value" >&2
      exit 1
      ;;
  esac
}

require_non_negative_integer "pr_number" "$pr_number"
require_non_negative_integer "issue_number" "$issue_number"

case "$(uname -s)" in
  Darwin) storage_root="$HOME/Library/Application Support/Code - Insiders/User/workspaceStorage" ;;
  Linux)  storage_root="$HOME/.config/Code - Insiders/User/workspaceStorage" ;;
  *)      storage_root="" ;;
esac

# Also try stable (non-Insiders) paths as a fallback.
candidate_roots=("$storage_root")
case "$(uname -s)" in
  Darwin) candidate_roots+=("$HOME/Library/Application Support/Code/User/workspaceStorage") ;;
  Linux)  candidate_roots+=("$HOME/.config/Code/User/workspaceStorage") ;;
esac

transcript=""
now=$(date +%s)
best_mtime=0
for root in "${candidate_roots[@]}"; do
  [ -n "$root" ] && [ -d "$root" ] || continue
  while IFS= read -r -d '' f; do
    if command -v gstat >/dev/null 2>&1; then
      m=$(gstat -c '%Y' "$f" 2>/dev/null || echo 0)
    else
      m=$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null || echo 0)
    fi
    age=$(( now - m ))
    if [ "$age" -le 120 ] && [ "$m" -gt "$best_mtime" ]; then
      best_mtime="$m"
      transcript="$f"
    fi
  done < <(find "$root" -type f -path '*/GitHub.copilot-chat/transcripts/*.jsonl' -print0 2>/dev/null)
done

if [ -z "$transcript" ]; then
  printf 'fix-issue-record-state: could not find an active Copilot transcript (mtime within 120s). Stop hook will fall back to transcript inference.\n' >&2
  exit 2
fi

session_id=$(basename "$transcript" .jsonl)
if [ -z "$session_id" ]; then
  printf 'fix-issue-record-state: empty session_id derived from transcript %s\n' "$transcript" >&2
  exit 2
fi

state_file="/tmp/fix-issue-vbw-state-${session_id}.json"
updated_at=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

# Write the state file privately. The file contains session id / branch /
# worktree / issue metadata — on multi-user systems a permissive umask
# could leave it world-readable, so lock it down before and after write.
(
  umask 077
  jq -n \
    --arg session_id "$session_id" \
    --argjson pr_number "$pr_number" \
    --arg branch "$branch" \
    --arg worktree_path "$worktree_path" \
    --argjson issue_number "$issue_number" \
    --arg updated_at "$updated_at" \
    '{
      session_id: $session_id,
      pr_number: $pr_number,
      branch: $branch,
      worktree_path: $worktree_path,
      issue_number: $issue_number,
      updated_at: $updated_at
    }' > "$state_file"
)
chmod 600 "$state_file" 2>/dev/null || true

printf 'fix-issue-record-state: wrote %s\n' "$state_file"

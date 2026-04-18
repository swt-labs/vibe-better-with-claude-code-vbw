#!/usr/bin/env bash
# Stop hook for the fix-issue-vbw agent.
# Blocks the agent from declaring completion when:
#   1. PR is still in draft
#   2. PR is out of date with main or has merge conflicts
#   3. Required GitHub Actions CI checks are not all green
#   4. No fresh Copilot review exists after the latest push
#   5. The PR still has an active CHANGES_REQUESTED review decision
#   6. The PR still has unresolved review threads
#
# Agent-scoped: only runs when fix-issue-vbw is the active agent.
# Requires: git, gh, jq

set -euo pipefail

OWNER="swt-labs"
REPO="vibe-better-with-claude-code-vbw"

# Capture hook stdin JSON for best-effort worktree/branch targeting.
INPUT=$(cat)

# --- Diagnostic capture (step 1 of per-thread targeting rollout) ---
# Dump stdin + env for one-shot analysis of what VS Code GitHub Copilot
# actually passes to Stop hooks. Used to pick a stable thread identifier
# before we build per-thread state wiring. Keeps only the last 10 dumps to
# avoid filling /tmp. Remove or gate behind FIX_ISSUE_HOOK_DEBUG after
# the identifier source is confirmed.
{
  debug_dir="/tmp/fix-issue-stop-hook-debug"
  mkdir -p "$debug_dir" 2>/dev/null || true
  debug_file="$debug_dir/$(date +%s%N).json"
  {
    printf '{\n'
    printf '  "pid": %s,\n' "$$"
    printf '  "ppid": %s,\n' "${PPID:-0}"
    printf '  "cwd": %s,\n' "$(pwd -P | jq -R .)"
    printf '  "stdin": %s,\n' "$(printf '%s' "$INPUT" | jq -Rs . 2>/dev/null || printf '""')"
    printf '  "env": '
    env | awk -F= '
      {
        key=$1
        val=substr($0, length(key)+2)
        if (key ~ /(TOKEN|SECRET|PASSWORD|CREDENTIAL|_KEY$|_PAT$|_AUTH$|API_KEY|ACCESS_KEY)/ ) {
          val="[REDACTED]"
        }
        print key "=" val
      }
    ' | jq -Rs 'split("\n") | map(select(length > 0))' 2>/dev/null || printf '[]'
    printf '\n}\n'
  } > "$debug_file" 2>/dev/null || true
  # Prune: keep last 10
  ls -1t "$debug_dir"/*.json 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
} 2>/dev/null || true

# --- Helpers ---
# block() emits structured data so the agent can recover without re-deriving
# the SHA or worktree path. Fields: commit_sha (full 40-char), worktree_path,
# pr_number, and an optional recovery_command when a deterministic re-check
# command is useful (for example pending CI on a specific SHA).
block() {
  local reason="$1"
  local recovery="${2:-}"
  local sha="${_block_sha:-}"
  local wt="${_block_worktree:-}"
  local pr="${_block_pr:-}"

  jq -n \
    --arg reason "$reason" \
    --arg sha "$sha" \
    --arg wt "$wt" \
    --arg pr "$pr" \
    --arg recovery "$recovery" \
    '{
      hookSpecificOutput: {
        hookEventName: "Stop",
        decision: "block",
        reason: $reason,
        commit_sha: $sha,
        worktree_path: $wt,
        pr_number: ($pr | if . == "" then null else tonumber end),
        recovery_command: $recovery
      }
    }'
  exit 0
}

allow() {
  echo '{}'
  exit 0
}

canonicalize_dir() {
  local path="$1"
  [ -n "$path" ] || return 1
  [ -d "$path" ] || return 1
  (cd "$path" 2>/dev/null && pwd -P)
}

# --- validate_pr: run all readiness gates against one PR. On any failure
# calls block() (which exits 0 with decision:block). Returns 0 if all gates
# pass.
validate_pr() {
  local pr_number="$1"
  local worktree_dir="$2"
  local branch="$3"
  local pr_is_draft="$4"

  _block_pr="$pr_number"
  _block_worktree="$worktree_dir"

  local cd_target="$worktree_dir"
  if [ ! -d "$cd_target" ]; then
    cd_target="."
  fi

  local head_sha=""
  if pushd "$cd_target" >/dev/null 2>&1; then
    head_sha=$(git rev-parse HEAD 2>/dev/null || true)
    popd >/dev/null 2>&1 || true
  fi
  _block_sha="$head_sha"

  # Gate 1: draft
  if [ "$pr_is_draft" = "true" ]; then
    block "PR #${pr_number} is still a draft. Mark it as ready for review (step 25) before completing."
  fi

  # Gate 2: merge state + review decision + unresolved threads
  local pr_state_raw pr_state_json merge_state review_decision
  local unresolved_threads_json unresolved_thread_count unresolved_examples unresolved_suffix
  pr_state_raw=$(gh api graphql -f query='
    { repository(owner:"'"${OWNER}"'",name:"'"${REPO}"'") {
        pullRequest(number:'"${pr_number}"') {
          mergeStateStatus
          reviewDecision
          reviewThreads(first:100) {
            nodes { id isResolved isOutdated path line }
          }
        }
      }
    }' 2>/dev/null || true)
  pr_state_json=$(printf '%s' "$pr_state_raw" | jq '.data.repository.pullRequest // empty' 2>/dev/null || true)
  if [ -z "$pr_state_json" ] || [ "$pr_state_json" = "null" ]; then
    block "Could not query PR #${pr_number} review state from GitHub. Retry once GitHub API access is healthy before completing."
  fi

  merge_state=$(printf '%s' "$pr_state_json" | jq -r '.mergeStateStatus // empty')
  review_decision=$(printf '%s' "$pr_state_json" | jq -r '.reviewDecision // empty')
  unresolved_threads_json=$(printf '%s' "$pr_state_json" | jq '[.reviewThreads.nodes[]? | select((.isResolved // false) == false)]')
  unresolved_thread_count=$(printf '%s' "$unresolved_threads_json" | jq 'length')

  case "$merge_state" in
    BEHIND)
      block "PR #${pr_number} is out of date with main (merge state: behind). Merge origin/main into ${branch} or update the branch on GitHub before completing."
      ;;
    DIRTY)
      block "PR #${pr_number} has merge conflicts with main (merge state: dirty). Merge origin/main and resolve the conflicts before completing."
      ;;
  esac

  if [ "$review_decision" = "CHANGES_REQUESTED" ]; then
    block "PR #${pr_number} still has an active CHANGES_REQUESTED review decision. Address the requested changes and obtain an updated review before completing."
  fi

  if [ "$unresolved_thread_count" -gt 0 ]; then
    unresolved_examples=$(printf '%s' "$unresolved_threads_json" | jq -r '
      [ .[]
        | ((.path // "(unknown path)")
           + (if .line == null then "" else ":" + (.line | tostring) end))
      ]
      | unique
      | .[:3]
      | join(", ")')
    unresolved_suffix=""
    [ -n "$unresolved_examples" ] && unresolved_suffix=" Examples: ${unresolved_examples}."
    block "PR #${pr_number} still has ${unresolved_thread_count} unresolved review thread(s). Resolve the outstanding review threads before completing.${unresolved_suffix}"
  fi

  # Gate 3: remote CI
  if [ -n "$head_sha" ]; then
    local check_runs_json total_checks failed pending failed_names pending_names
    check_runs_json=$(gh api "repos/${OWNER}/${REPO}/commits/${head_sha}/check-runs" --jq '.check_runs' 2>/dev/null || echo '[]')
    total_checks=$(printf '%s' "$check_runs_json" | jq 'length')
    if [ "$total_checks" -gt 0 ]; then
      failed=$(printf '%s' "$check_runs_json" | jq '[.[] | select(.conclusion != null and .conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral")] | length')
      pending=$(printf '%s' "$check_runs_json" | jq '[.[] | select(.status == "queued" or .status == "in_progress")] | length')
      if [ "$failed" -gt 0 ]; then
        failed_names=$(printf '%s' "$check_runs_json" | jq -r '[.[] | select(.conclusion != null and .conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral")] | map(.name + " (" + .conclusion + ")") | join(", ")')
        block "Remote CI failed on commit ${head_sha}. Failing checks: ${failed_names}. Diagnose and fix the CI failures before completing." "cd ${worktree_dir} && gh api repos/${OWNER}/${REPO}/commits/${head_sha}/check-runs --jq '.check_runs[] | .name + \": \" + .status + \" / \" + (.conclusion // \"pending\")'"
      fi
      if [ "$pending" -gt 0 ]; then
        pending_names=$(printf '%s' "$check_runs_json" | jq -r '[.[] | select(.status == "queued" or .status == "in_progress")] | map(.name + " (" + .status + ")") | join(", ")')
        block "Remote CI still running on commit ${head_sha}. Pending checks: ${pending_names}. Wait for CI to complete before finishing." "cd ${worktree_dir} && gh api repos/${OWNER}/${REPO}/commits/${head_sha}/check-runs --jq '.check_runs[] | .name + \": \" + .status + \" / \" + (.conclusion // \"pending\")'"
      fi
    fi
  fi

  # Gate 4: fresh Copilot review after latest push
  if [ -n "$head_sha" ]; then
    local latest_push_at reviews_json latest_copilot_review copilot_review_at
    local review_epoch push_epoch date_cmd
    latest_push_at=$(gh api "repos/${OWNER}/${REPO}/events" --jq '[.[] | select(.type == "PushEvent" and .payload.ref == "refs/heads/'"${branch}"'")] | first | .created_at // empty' 2>/dev/null || true)
    [ -z "$latest_push_at" ] && latest_push_at=$(gh api "repos/${OWNER}/${REPO}/commits/${head_sha}" --jq '.commit.committer.date // empty' 2>/dev/null || true)
    if [ -n "$latest_push_at" ]; then
      reviews_json=$(gh api graphql -f query='
        { repository(owner:"'"${OWNER}"'",name:"'"${REPO}"'") {
            pullRequest(number:'"${pr_number}"') {
              reviews(last:10) { nodes { author { login } state submittedAt } }
            }
          }
        }' 2>/dev/null | jq '.data.repository.pullRequest.reviews.nodes // []' || echo '[]')
      latest_copilot_review=$(printf '%s' "$reviews_json" | jq -r '[.[] | select((.author.login // "") | startswith("copilot-pull-request-reviewer"))] | sort_by(.submittedAt) | last // empty')
      if [ -z "$latest_copilot_review" ] || [ "$latest_copilot_review" = "null" ]; then
        block "No Copilot review found on PR #${pr_number}. Request a Copilot review (step 25/30) and wait for it to complete before finishing."
      fi
      copilot_review_at=$(printf '%s' "$latest_copilot_review" | jq -r '.submittedAt // empty')
      if [ -n "$copilot_review_at" ]; then
        if command -v gdate >/dev/null 2>&1; then date_cmd="gdate"; else date_cmd="date"; fi
        review_epoch=$($date_cmd -d "$copilot_review_at" +%s 2>/dev/null || $date_cmd -j -f "%Y-%m-%dT%H:%M:%SZ" "$copilot_review_at" +%s 2>/dev/null || echo 0)
        push_epoch=$($date_cmd -d "$latest_push_at" +%s 2>/dev/null || $date_cmd -j -f "%Y-%m-%dT%H:%M:%SZ" "$latest_push_at" +%s 2>/dev/null || echo 0)
        if [ "$review_epoch" -lt "$push_epoch" ]; then
          block "Copilot review on PR #${pr_number} is stale (submitted before the latest push). Request a fresh Copilot review and wait for it to arrive before completing."
        fi
      fi
    fi
  fi

  return 0
}

# --- Enumerate every local open-PR worktree.
# Emits one "pr|branch|worktree|draft" line per candidate. Skips main and
# worktrees whose branches have no open PR.
enumerate_open_pr_worktrees() {
  local wt_path="" wt_branch="" wt_pr_json wt_pr wt_draft wt_canon
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      worktree\ *) wt_path="${line#worktree }" ;;
      branch\ refs/heads/*)
        wt_branch="${line#branch refs/heads/}"
        if [ -z "$wt_path" ] || [ -z "$wt_branch" ] || [ "$wt_branch" = "main" ]; then
          continue
        fi
        wt_pr_json=$(gh pr list --repo "${OWNER}/${REPO}" --head "$wt_branch" --state open --json number,isDraft --limit 1 2>/dev/null || echo '[]')
        wt_pr=$(printf '%s' "$wt_pr_json" | jq -r '.[0].number // empty')
        [ -z "$wt_pr" ] && continue
        wt_draft=$(printf '%s' "$wt_pr_json" | jq -r '.[0].isDraft // false')
        wt_canon="$(canonicalize_dir "$wt_path" 2>/dev/null || true)"
        [ -z "$wt_canon" ] && continue
        printf '%s|%s|%s|%s\n' "$wt_pr" "$wt_branch" "$wt_canon" "$wt_draft"
        ;;
      '') wt_path=""; wt_branch="" ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null || true)
}

# --- Infer the active worktree from the thread's transcript.
# Reads the JSONL transcript, extracts every absolute path that looks like
# one of our worktrees, and matches them against the open-PR candidate list.
# Prints the chosen candidate line ("pr|branch|worktree|draft") if exactly
# one worktree was referenced, else nothing.
infer_from_transcript() {
  local transcript="$1"
  local candidates_blob="$2"
  [ -n "$transcript" ] && [ -f "$transcript" ] || return 1
  [ -n "$candidates_blob" ] || return 1

  # All canonical candidate worktree paths.
  local candidate_paths
  candidate_paths=$(printf '%s\n' "$candidates_blob" | awk -F'|' 'NF>=4 {print $3}' | sort -u)
  [ -n "$candidate_paths" ] || return 1

  # Extract every candidate path that appears anywhere in the transcript.
  local referenced
  referenced=$(
    while IFS= read -r cand; do
      [ -n "$cand" ] || continue
      if grep -Fq -- "$cand" "$transcript" 2>/dev/null; then
        printf '%s\n' "$cand"
      fi
    done <<< "$candidate_paths"
  )

  local ref_count
  ref_count=$(printf '%s\n' "$referenced" | awk 'NF' | wc -l | tr -d ' ')
  if [ "$ref_count" != "1" ]; then
    return 1
  fi

  local chosen_path
  chosen_path=$(printf '%s\n' "$referenced" | awk 'NF' | head -n1)
  printf '%s\n' "$candidates_blob" | awk -F'|' -v p="$chosen_path" '$3 == p { print; exit }'
}

# --- Extract session context from stdin ---
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)

# --- Main cascade ---

# Tier 1: explicit state file written by the fix-issue agent after worktree+PR creation.
if [ -n "$SESSION_ID" ]; then
  STATE_FILE="/tmp/fix-issue-vbw-state-${SESSION_ID}.json"
  if [ -f "$STATE_FILE" ]; then
    s_pr=$(jq -r '.pr_number // empty' "$STATE_FILE" 2>/dev/null || true)
    s_branch=$(jq -r '.branch // empty' "$STATE_FILE" 2>/dev/null || true)
    s_worktree=$(jq -r '.worktree_path // empty' "$STATE_FILE" 2>/dev/null || true)
    if [ -n "$s_pr" ] && [ -n "$s_branch" ] && [ -n "$s_worktree" ]; then
      s_draft=$(gh pr view "$s_pr" --repo "${OWNER}/${REPO}" --json isDraft --jq '.isDraft' 2>/dev/null || echo "false")
      validate_pr "$s_pr" "$s_worktree" "$s_branch" "$s_draft"
      # All gates passed → remove state file and allow.
      rm -f "$STATE_FILE" 2>/dev/null || true
      allow
    fi
  fi
fi

# Enumerate open-PR worktrees once for tiers 2-4.
CANDIDATES=$(enumerate_open_pr_worktrees)
CANDIDATE_COUNT=$(printf '%s\n' "$CANDIDATES" | awk 'NF' | wc -l | tr -d ' ')

# No open-PR worktrees at all → nothing to gate. Let through.
if [ "$CANDIDATE_COUNT" = "0" ]; then
  allow
fi

# Tier 2: infer from transcript.
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  inferred=$(infer_from_transcript "$TRANSCRIPT_PATH" "$CANDIDATES" 2>/dev/null || true)
  if [ -n "$inferred" ]; then
    i_pr=$(printf '%s' "$inferred" | awk -F'|' '{print $1}')
    i_branch=$(printf '%s' "$inferred" | awk -F'|' '{print $2}')
    i_worktree=$(printf '%s' "$inferred" | awk -F'|' '{print $3}')
    i_draft=$(printf '%s' "$inferred" | awk -F'|' '{print $4}')
    validate_pr "$i_pr" "$i_worktree" "$i_branch" "$i_draft"
    allow
  fi
fi

# Tier 3: single candidate worktree locally.
if [ "$CANDIDATE_COUNT" = "1" ]; then
  c_pr=$(printf '%s\n' "$CANDIDATES" | awk 'NF' | head -n1 | awk -F'|' '{print $1}')
  c_branch=$(printf '%s\n' "$CANDIDATES" | awk 'NF' | head -n1 | awk -F'|' '{print $2}')
  c_worktree=$(printf '%s\n' "$CANDIDATES" | awk 'NF' | head -n1 | awk -F'|' '{print $3}')
  c_draft=$(printf '%s\n' "$CANDIDATES" | awk 'NF' | head -n1 | awk -F'|' '{print $4}')
  validate_pr "$c_pr" "$c_worktree" "$c_branch" "$c_draft"
  allow
fi

# Tier 4: strict fallback — validate every open-PR worktree. Block on first failure.
# Reached when multiple open-PR worktrees exist AND the transcript did not
# uniquely identify one AND no state file was found. Blocks so no thread can
# complete while any local PR is unready; the block message makes it explicit
# that the hook could not target a specific PR.
while IFS='|' read -r s_pr s_branch s_worktree s_draft; do
  [ -z "$s_pr" ] && continue
  validate_pr "$s_pr" "$s_worktree" "$s_branch" "$s_draft"
done <<< "$CANDIDATES"

allow

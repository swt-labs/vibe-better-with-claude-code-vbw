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

# --- Diagnostic capture ---
# Opt-in only: local debug snapshots can include stdin and partially-redacted
# environment data, so only emit them when FIX_ISSUE_HOOK_DEBUG=1.
if [ "${FIX_ISSUE_HOOK_DEBUG:-}" = "1" ]; then
  {
    umask 077
    debug_dir="/tmp/fix-issue-stop-hook-debug"
    mkdir -p "$debug_dir" 2>/dev/null || true
    chmod 700 "$debug_dir" 2>/dev/null || true
    # Use mktemp for portable uniqueness. `date +%s%N` prints a literal "N" on
    # macOS/BSD `date` (no nanosecond support), which collapses concurrent Stop
    # events fired in the same second onto the same filename and overwrites
    # earlier debug snapshots.
    debug_file=$(mktemp "$debug_dir/debug.XXXXXX.json" 2>/dev/null) || \
      debug_file="$debug_dir/debug.$(date +%s).$$.$RANDOM.json"
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
    chmod 600 "$debug_file" 2>/dev/null || true
    # Prune: keep last 10
    ls -1t "$debug_dir"/*.json 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
  } 2>/dev/null || true
fi

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

latest_branch_push_at() {
  local branch="$1"
  local head_sha="$2"
  local ref_owner="${3:-$OWNER}"
  local ref_repo="${4:-$REPO}"
  local branch_ref_json branch_head_oid branch_pushed_at

  branch_ref_json=$(gh api graphql \
    -f query='\
      query($owner: String!, $repo: String!, $ref: String!) {\
        repository(owner: $owner, name: $repo) {\
          ref(qualifiedName: $ref) {\
            target {\
              __typename\
              ... on Commit {\
                oid\
                pushedDate\
              }\
            }\
          }\
        }\
      }' \
    -f owner="$ref_owner" \
    -f repo="$ref_repo" \
    -f ref="refs/heads/${branch}" 2>/dev/null || true)

  branch_head_oid=$(printf '%s' "$branch_ref_json" | jq -r '.data.repository.ref.target.oid // empty' 2>/dev/null || true)
  branch_pushed_at=$(printf '%s' "$branch_ref_json" | jq -r '.data.repository.ref.target.pushedDate // empty' 2>/dev/null || true)

  if [ -n "$branch_pushed_at" ] && [ "$branch_head_oid" = "$head_sha" ]; then
    printf '%s\n' "$branch_pushed_at"
    return 0
  fi

  gh api "repos/${ref_owner}/${ref_repo}/events" --jq '[.[] | select(.type == "PushEvent" and .payload.ref == "refs/heads/'"${branch}"'")] | first | .created_at // empty' 2>/dev/null || true
}

latest_matching_copilot_review() {
  local pr_number="$1"
  local head_sha="$2"
  local reviews_json

  # Paginate: the REST reviews API is oldest-first and capped at 100 per
  # page, so on PRs with >100 reviews the newest Copilot review would be
  # missed without --paginate. jq -s flattens the per-page arrays into a
  # single list before filtering for the matching fresh review.
  reviews_json=$(gh api --paginate "repos/${OWNER}/${REPO}/pulls/${pr_number}/reviews?per_page=100" 2>/dev/null | jq -s 'add // []' 2>/dev/null || echo '[]')
  printf '%s' "$reviews_json" | jq -c --arg head_sha "$head_sha" '
    [ .[]
      | select((.user.login // "") | startswith("copilot-pull-request-reviewer"))
      | select((.commit_id // "") == $head_sha)
    ]
    | sort_by(.submitted_at)
    | last // empty
  ' 2>/dev/null || true
}

# --- validate_pr: run all readiness gates against one PR. On any failure
# calls block() (which exits 0 with decision:block). Returns 0 if all gates
# pass.
validate_pr() {
  local pr_number="$1"
  local worktree_dir="$2"
  local branch="$3"
  local pr_is_draft="$4"
  local head_owner="${5:-$OWNER}"
  local head_repo="${6:-$REPO}"
  local head_ref_name="${7:-$branch}"

  _block_pr="$pr_number"
  _block_worktree="$worktree_dir"

  # Fail closed when the recorded worktree is missing or unreadable. The previous
  # fallback to "." silently validated against whatever directory the hook was
  # launched from (typically an unrelated repo), which could let completion pass
  # with CI/review state from the wrong codebase.
  if [ ! -d "$worktree_dir" ]; then
    block "Worktree directory '${worktree_dir}' does not exist. Recreate or reselect the fix-issue worktree, then retry completion."
  fi
  if [ ! -r "$worktree_dir" ] || [ ! -x "$worktree_dir" ]; then
    block "Worktree directory '${worktree_dir}' is not accessible (needs read+execute). Fix its permissions or reselect the fix-issue worktree, then retry completion."
  fi

  local head_sha=""
  if pushd "$worktree_dir" >/dev/null 2>&1; then
    head_sha=$(git rev-parse HEAD 2>/dev/null || true)
    popd >/dev/null 2>&1 || true
  else
    block "Unable to enter worktree directory '${worktree_dir}' to validate PR #${pr_number}. Recreate or reselect the fix-issue worktree, then retry completion."
  fi
  _block_sha="$head_sha"
  if [ -z "$head_sha" ]; then
    block "Unable to resolve HEAD in worktree '${worktree_dir}' for PR #${pr_number}. Ensure this fix-issue worktree is a valid git checkout (with a readable .git directory and commit history), or recreate/reselect the worktree, then retry completion."
  fi

  # Gate 1: draft
  if [ "$pr_is_draft" = "true" ]; then
    block "PR #${pr_number} (worktree: ${worktree_dir}) is still a draft. Mark it as ready for review (step 25) before completing."
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
    block "Could not query PR #${pr_number} (worktree: ${worktree_dir}) review state from GitHub. Retry once GitHub API access is healthy before completing."
  fi

  merge_state=$(printf '%s' "$pr_state_json" | jq -r '.mergeStateStatus // empty')
  review_decision=$(printf '%s' "$pr_state_json" | jq -r '.reviewDecision // empty')
  unresolved_threads_json=$(printf '%s' "$pr_state_json" | jq '[.reviewThreads.nodes[]? | select((.isResolved // false) == false)]')
  unresolved_thread_count=$(printf '%s' "$unresolved_threads_json" | jq 'length')

  case "$merge_state" in
    BEHIND)
      block "PR #${pr_number} (worktree: ${worktree_dir}) is out of date with main (merge state: behind). Merge origin/main into ${branch} or update the branch on GitHub before completing."
      ;;
    DIRTY)
      block "PR #${pr_number} (worktree: ${worktree_dir}) has merge conflicts with main (merge state: dirty). Merge origin/main and resolve the conflicts before completing."
      ;;
  esac

  if [ "$review_decision" = "CHANGES_REQUESTED" ]; then
    block "PR #${pr_number} (worktree: ${worktree_dir}) still has an active CHANGES_REQUESTED review decision. Address the requested changes and obtain an updated review before completing."
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
    block "PR #${pr_number} (worktree: ${worktree_dir}) still has ${unresolved_thread_count} unresolved review thread(s). Resolve the outstanding review threads before completing.${unresolved_suffix}"
  fi

  # Gate 3: remote CI
  if [ -n "$head_sha" ]; then
    local check_runs_json total_checks failed pending failed_names pending_names
    # Paginate so repos with >30 check runs don't appear green due to
    # truncation. `--paginate` emits one JSON object per page; flatten
    # with jq -s and pull every .check_runs[] into a single array.
    # Fail closed: a transient gh/jq/network error must block completion
    # ("unknown CI state") rather than be silently coerced to `[]`, which
    # previously let the gate pass on a zero-check count.
    if check_runs_json=$(gh api --paginate "repos/${OWNER}/${REPO}/commits/${head_sha}/check-runs?per_page=100" 2>/dev/null | jq -s '[.[].check_runs[]?]' 2>/dev/null); then
      :
    else
      block "Could not query remote check-runs for PR #${pr_number} (worktree: ${worktree_dir}) at commit ${head_sha}. Remote CI status is unknown, so completion is blocked until check-runs can be fetched successfully." "cd ${worktree_dir} && gh api --paginate 'repos/${OWNER}/${REPO}/commits/${head_sha}/check-runs?per_page=100' | jq -s '[.[].check_runs[]?] | .[] | .name + \": \" + .status + \" / \" + (.conclusion // \"pending\")'"
    fi
    total_checks=$(printf '%s' "$check_runs_json" | jq 'length')
    if [ "$total_checks" -gt 0 ]; then
      failed=$(printf '%s' "$check_runs_json" | jq '[.[] | select(.conclusion != null and .conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral")] | length')
      pending=$(printf '%s' "$check_runs_json" | jq '[.[] | select(.status == "queued" or .status == "in_progress")] | length')
      if [ "$failed" -gt 0 ]; then
        failed_names=$(printf '%s' "$check_runs_json" | jq -r '[.[] | select(.conclusion != null and .conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral")] | map(.name + " (" + .conclusion + ")") | join(", ")')
        block "Remote CI failed on PR #${pr_number} (worktree: ${worktree_dir}) at commit ${head_sha}. Failing checks: ${failed_names}. Diagnose and fix the CI failures before completing." "cd ${worktree_dir} && gh api --paginate 'repos/${OWNER}/${REPO}/commits/${head_sha}/check-runs?per_page=100' | jq -s '[.[].check_runs[]?] | .[] | .name + \": \" + .status + \" / \" + (.conclusion // \"pending\")'"
      fi
      if [ "$pending" -gt 0 ]; then
        pending_names=$(printf '%s' "$check_runs_json" | jq -r '[.[] | select(.status == "queued" or .status == "in_progress")] | map(.name + " (" + .status + ")") | join(", ")')
        block "Remote CI still running on PR #${pr_number} (worktree: ${worktree_dir}) at commit ${head_sha}. Pending checks: ${pending_names}. Wait for CI to complete before finishing." "cd ${worktree_dir} && gh api --paginate 'repos/${OWNER}/${REPO}/commits/${head_sha}/check-runs?per_page=100' | jq -s '[.[].check_runs[]?] | .[] | .name + \": \" + .status + \" / \" + (.conclusion // \"pending\")'"
      fi
    fi
  fi

  # Gate 4: fresh Copilot review after latest push
  if [ -n "$head_sha" ]; then
    local latest_push_at reviews_json latest_copilot_review copilot_review_at
    local review_epoch push_epoch date_cmd
    latest_push_at=$(latest_branch_push_at "$head_ref_name" "$head_sha" "$head_owner" "$head_repo")
    if [ -z "$latest_push_at" ]; then
      block "Unable to determine the latest push timestamp for branch ${branch} (worktree: ${worktree_dir}) at head commit ${head_sha}. Fix GitHub CLI/API access and retry so the hook can verify that a fresh Copilot review exists after the latest push."
    fi
    if [ -n "$latest_push_at" ]; then
      latest_copilot_review=$(latest_matching_copilot_review "$pr_number" "$head_sha")
      if [ -z "$latest_copilot_review" ] || [ "$latest_copilot_review" = "null" ]; then
        block "No Copilot review found on PR #${pr_number} (worktree: ${worktree_dir}) for current head commit ${head_sha}. Request a Copilot review (step 25/30) and wait for it to complete before finishing."
      fi
      copilot_review_at=$(printf '%s' "$latest_copilot_review" | jq -r '.submitted_at // empty')
      if [ -n "$copilot_review_at" ]; then
        if command -v gdate >/dev/null 2>&1; then date_cmd="gdate"; else date_cmd="date"; fi
        review_epoch=$($date_cmd -d "$copilot_review_at" +%s 2>/dev/null || $date_cmd -j -f "%Y-%m-%dT%H:%M:%SZ" "$copilot_review_at" +%s 2>/dev/null || echo 0)
        push_epoch=$($date_cmd -d "$latest_push_at" +%s 2>/dev/null || $date_cmd -j -f "%Y-%m-%dT%H:%M:%SZ" "$latest_push_at" +%s 2>/dev/null || echo 0)
        if [ "$review_epoch" -lt "$push_epoch" ]; then
          block "Copilot review on PR #${pr_number} (worktree: ${worktree_dir}) is stale (submitted before the latest push). Request a fresh Copilot review and wait for it to arrive before completing."
        fi
      fi
    fi
  fi

  return 0
}

# --- Enumerate every local open-PR worktree.
# Emits one "pr|branch|worktree|draft|head_owner|head_repo|head_ref_name" line per candidate. Skips main and
# worktrees whose branches have no open PR.
enumerate_open_pr_worktrees() {
  local wt_path="" wt_branch="" wt_pr_json wt_pr wt_draft wt_canon wt_head_owner wt_head_repo wt_head_ref
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      worktree\ *) wt_path="${line#worktree }" ;;
      branch\ refs/heads/*)
        wt_branch="${line#branch refs/heads/}"
        if [ -z "$wt_path" ] || [ -z "$wt_branch" ] || [ "$wt_branch" = "main" ]; then
          continue
        fi
        if ! wt_pr_json=$(gh pr list --repo "${OWNER}/${REPO}" --head "$wt_branch" --state open --json number,isDraft,headRepository,headRepositoryOwner,headRefName --limit 1 2>/dev/null); then
          printf 'BLOCK: unable to query open PRs for branch "%s" in %s/%s; fix gh authentication/configuration and retry.\n' "$wt_branch" "$OWNER" "$REPO" >&2
          return 1
        fi
        wt_pr=$(printf '%s' "$wt_pr_json" | jq -r '.[0].number // empty')
        [ -z "$wt_pr" ] && continue
        wt_draft=$(printf '%s' "$wt_pr_json" | jq -r '.[0].isDraft // false')
        wt_head_owner=$(printf '%s' "$wt_pr_json" | jq -r '.[0].headRepositoryOwner.login // empty')
        wt_head_repo=$(printf '%s' "$wt_pr_json" | jq -r '.[0].headRepository.name // empty')
        wt_head_ref=$(printf '%s' "$wt_pr_json" | jq -r '.[0].headRefName // empty')
        wt_canon="$(canonicalize_dir "$wt_path" 2>/dev/null || true)"
        [ -z "$wt_canon" ] && continue
        printf '%s|%s|%s|%s|%s|%s|%s\n' "$wt_pr" "$wt_branch" "$wt_canon" "$wt_draft" "$wt_head_owner" "$wt_head_repo" "$wt_head_ref"
        ;;
      '') wt_path=""; wt_branch="" ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null)
  # If git worktree list failed (e.g. not in a git repo), the subshell
  # exit code is lost by the process substitution.  Validate we got
  # at least the bare worktree (always present in a valid repo).
  if ! git worktree list --porcelain >/dev/null 2>&1; then
    printf 'BLOCK: git worktree list failed; cannot enumerate worktrees.\n' >&2
    return 1
  fi
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
    s_head_owner=$(jq -r '.fork_owner // empty' "$STATE_FILE" 2>/dev/null || true)
    s_head_repo=$(jq -r '.fork_repo // empty' "$STATE_FILE" 2>/dev/null || true)
    s_head_ref=$(jq -r '.head_ref_name // empty' "$STATE_FILE" 2>/dev/null || true)
    if [ -n "$s_pr" ] && [ -n "$s_branch" ] && [ -n "$s_worktree" ]; then
      s_draft=$(gh pr view "$s_pr" --repo "${OWNER}/${REPO}" --json isDraft --jq '.isDraft' 2>/dev/null || echo "false")
      validate_pr "$s_pr" "$s_worktree" "$s_branch" "$s_draft" "$s_head_owner" "$s_head_repo" "$s_head_ref"
      # All gates passed → remove state file and allow.
      rm -f "$STATE_FILE" 2>/dev/null || true
      allow
    fi
  fi
fi

# Enumerate open-PR worktrees once for tiers 2-4.
if CANDIDATES=$(enumerate_open_pr_worktrees); then
  CANDIDATE_COUNT=$(printf '%s\n' "$CANDIDATES" | awk 'NF' | wc -l | tr -d ' ')
else
  block "Unable to enumerate open PR worktrees; cannot safely validate fix-issue completion."
fi

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
    i_head_owner=$(printf '%s' "$inferred" | awk -F'|' '{print $5}')
    i_head_repo=$(printf '%s' "$inferred" | awk -F'|' '{print $6}')
    i_head_ref=$(printf '%s' "$inferred" | awk -F'|' '{print $7}')
    validate_pr "$i_pr" "$i_worktree" "$i_branch" "$i_draft" "$i_head_owner" "$i_head_repo" "$i_head_ref"
    allow
  fi
fi

# Tier 3: single candidate worktree locally.
if [ "$CANDIDATE_COUNT" = "1" ]; then
  c_pr=$(printf '%s\n' "$CANDIDATES" | awk 'NF' | head -n1 | awk -F'|' '{print $1}')
  c_branch=$(printf '%s\n' "$CANDIDATES" | awk 'NF' | head -n1 | awk -F'|' '{print $2}')
  c_worktree=$(printf '%s\n' "$CANDIDATES" | awk 'NF' | head -n1 | awk -F'|' '{print $3}')
  c_draft=$(printf '%s\n' "$CANDIDATES" | awk 'NF' | head -n1 | awk -F'|' '{print $4}')
  c_head_owner=$(printf '%s\n' "$CANDIDATES" | awk 'NF' | head -n1 | awk -F'|' '{print $5}')
  c_head_repo=$(printf '%s\n' "$CANDIDATES" | awk 'NF' | head -n1 | awk -F'|' '{print $6}')
  c_head_ref=$(printf '%s\n' "$CANDIDATES" | awk 'NF' | head -n1 | awk -F'|' '{print $7}')
  validate_pr "$c_pr" "$c_worktree" "$c_branch" "$c_draft" "$c_head_owner" "$c_head_repo" "$c_head_ref"
  allow
fi

# Tier 4: strict fallback — validate every open-PR worktree. Block on first failure.
# Reached when multiple open-PR worktrees exist AND the transcript did not
# uniquely identify one AND no state file was found. Blocks so no thread can
# complete while any local PR is unready; the block message makes it explicit
# that the hook could not target a specific PR.
while IFS='|' read -r s_pr s_branch s_worktree s_draft s_head_owner s_head_repo s_head_ref; do
  [ -z "$s_pr" ] && continue
  validate_pr "$s_pr" "$s_worktree" "$s_branch" "$s_draft" "$s_head_owner" "$s_head_repo" "$s_head_ref"
done <<< "$CANDIDATES"

allow

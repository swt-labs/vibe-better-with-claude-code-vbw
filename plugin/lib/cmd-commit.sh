#!/usr/bin/env bash
# vbw commit PLAN MESSAGE: commit the plan's declared files that changed, with
# VBW-Plan/VBW-Req trailers. Nothing else in the working tree or the index is
# touched: the user's own staged work stays staged. Commits are serialized with
# the project lock, so parallel Devs never collide on git's index lock.

VBW_COMMIT_RE='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)\([^)]+\)!?: .+'

cmd_commit() {
  [ $# -eq 2 ] || vbw_usage_error "usage: vbw commit PLAN MESSAGE"
  local plan="$1" msg="$2"
  printf '%s' "$msg" | grep -Eq "$VBW_COMMIT_RE" \
    || vbw_usage_error "commit message must be 'type(scope): description' (types: feat fix docs style refactor perf test build ci chore revert)"
  vbw_require_project
  local record reqs
  record=$(record_read)
  printf '%s' "$record" | jq -e --arg p "$plan" 'any(.plans[]; .id == $p)' > /dev/null \
    || vbw_die "unknown plan $plan"
  reqs=$(printf '%s' "$record" | jq -r --arg p "$plan" '.plans[] | select(.id == $p) | .reqs | join(", ")')

  local files=() f
  while IFS= read -r -d '' f; do files+=("$f"); done \
    < <(printf '%s' "$record" | jq -j --arg p "$plan" '.plans[] | select(.id == $p) | .files[] | . + "\u0000"')
  [ ${#files[@]} -gt 0 ] || vbw_die "plan $plan declares no files"

  cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
  record_lock

  # Changed = differs from HEAD (tracked, staged or not, incl. deletions) or new
  # and not ignored. NUL-separated throughout: names may hold spaces or UTF-8.
  local changed=() untracked=()
  while IFS= read -r -d '' f; do changed+=("$f"); done \
    < <(git diff --name-only -z HEAD -- "${files[@]}")
  while IFS= read -r -d '' f; do untracked+=("$f"); changed+=("$f"); done \
    < <(git ls-files -z --others --exclude-standard -- "${files[@]}")
  [ ${#changed[@]} -gt 0 ] || vbw_die "nothing to commit for $plan"

  [ ${#untracked[@]} -eq 0 ] || git add -- "${untracked[@]}"
  git commit --quiet --only -m "$msg" -m "VBW-Plan: $plan
VBW-Req: $reqs" -- "${changed[@]}" || vbw_die "git commit failed"

  record_unlock
  commit_escalate "$plan" "${#files[@]}" "${changed[@]}"
  printf 'committed %s for %s (%d file%s)\n' "$(git rev-parse --short HEAD)" "$plan" \
    "${#changed[@]}" "$([ ${#changed[@]} -eq 1 ] || printf s)"
}

# commit_escalate PLAN PLANNED_FILES CHANGED...: a changed file on a risk path
# raises the plan's phase to deep; a commit of more than twice the planned
# files (and at least 4) raises it one step. Runs with the lock released.
commit_escalate() {
  local plan="$1" planned="$2" changed n hit phase
  shift 2
  n=$#
  changed=$(printf '%s\0' "$@" | jq -Rsc 'split("\u0000")[:-1]')
  hit=$(printf '%s' "$changed" | jq -r "$VBW_JQ_DEFS"'[.[] | . as $f | ($f | risk_name) as $c | select($c != null) | "\($c) (\($f))"] | .[0] // empty')
  # shellcheck source=rigor.sh
  . "$VBW_LIB/rigor.sh"
  phase=$(jq -r --arg p "$plan" '.plans[] | select(.id == $p) | .phase' "$VBW_RECORD")
  [ -z "$hit" ] || rigor_escalate "$phase" "touches a risk path: $hit" deep
  if [ "$n" -ge 4 ] && [ "$n" -gt $((planned * 2)) ]; then
    rigor_escalate "$phase" "grew beyond its plan: $n files for $planned planned"
  fi
}

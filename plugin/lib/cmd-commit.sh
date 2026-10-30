#!/usr/bin/env bash
# vbw commit PLAN MESSAGE [FILE...]: commit the plan's declared files that
# changed (or only the named FILEs, each covered by the plan: one commit per
# task), with VBW-Plan/VBW-Req trailers. Nothing else in the working tree or the index is
# touched: the user's own staged work stays staged. A file inside a submodule is
# committed in the submodule (one commit per repository; the submodule's pointer in
# the project is never moved: docs/workflows.md, "Submodules"). vbw commit --fix FIX MESSAGE
# FILE...: an open project-command fix commits the named changed files (VBW-Fix);
# an open requirement fix, whatever opened it, commits the changed check files of
# its requirement (VBW-Fix, VBW-Req). Commits are serialized with
# the project lock, so parallel Devs never collide on git's index lock.

VBW_COMMIT_RE='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)\([^)]+\)!?: .+'

cmd_commit() {
  [ "${1:-}" != --fix ] || { shift; cmd_commit_fix "$@"; return; }
  [ $# -ge 2 ] || vbw_usage_error "usage: vbw commit PLAN MESSAGE [FILE...]"
  local plan="$1" msg="$2"
  shift 2
  printf '%s' "$msg" | grep -E "$VBW_COMMIT_RE" > /dev/null \
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

  local planned=${#files[@]}
  if [ $# -gt 0 ]; then
    local named=() e covered
    for f in "$@"; do
      f="${f#./}"
      covered=0
      for e in "${files[@]}"; do
        e="${e%/}"
        if [ "$f" = "$e" ] || { [ "${f#"$e"/}" != "$f" ] && [[ "/$f/" != *"/../"* ]]; }; then covered=1; break; fi
      done
      if [ "$covered" -eq 0 ]; then
        # A check file the plan may strengthen after a survivor (strengthen_files, R210).
        printf '%s' "$record" | jq -e --arg p "$plan" --arg f "$f" "$VBW_JQ_DEFS"'strengthen_files($p) | index($f) != null' > /dev/null \
          || vbw_die "$f is not covered by plan $plan: name only files the plan declares, or, after a survivor of vbw mutate $plan, a check file of a check of the plan's own rules (a file only other requirements' or other plans' checks name is never the plan's to commit)
Next: commit only the plan's files, or run vbw mutate $plan on a rule and strengthen a check file that one of its own rules' checks names"
      fi
      named+=("$f")
    done
    files=("${named[@]}")
  fi

  cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
  record_lock

  # Changed = differs from HEAD (tracked, staged or not, incl. deletions) or new
  # and not ignored, each in the repository that tracks it (a submodule's files
  # in the submodule): one commit per repository, no submodule pointer moved.
  vbw_commit_paths "$msg" "VBW-Plan: $plan
VBW-Req: $reqs" "${files[@]}" || vbw_die "nothing to commit for $plan"

  record_unlock
  commit_escalate "$plan" "$planned" "${VBW_COMMITTED[@]}"
  vbw_commits_say "$plan"
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

# cmd_commit_fix FIX MESSAGE FILE...: an open fix for a project command (any
# changed file), or an open requirement fix of any source (QA or a failing
# proof): then only changed check files of its requirement, with VBW-Fix and
# VBW-Req. FILEs must have changed and may not be under .vbw/.
cmd_commit_fix() {
  [ $# -ge 3 ] || vbw_usage_error "usage: vbw commit --fix FIX MESSAGE FILE..."
  local fix="$1" msg="$2" f req=""
  shift 2
  printf '%s' "$msg" | grep -E "$VBW_COMMIT_RE" > /dev/null || vbw_usage_error "commit message must be 'type(scope): description'"
  vbw_require_project
  local record
  record=$(record_read)
  printf '%s' "$record" | jq -e --arg f "$fix" 'any(.fixes[]?; .id == $f)' > /dev/null || vbw_die "unknown fix $fix"
  printf '%s' "$record" | jq -e --arg f "$fix" 'any(.fixes[]?; .id == $f and .status == "open")' > /dev/null \
    || vbw_die "$fix is not open: only an open fix commits"
  req=$(printf '%s' "$record" | jq -r --arg f "$fix" '[.fixes[] | select(.id == $f)][0] | if (.command // "") != "" then "" else (.req // "") end')
  [ -n "$req" ] || printf '%s' "$record" | jq -e --arg f "$fix" 'any(.fixes[]; .id == $f and (.command // "") != "")' > /dev/null \
    || vbw_die "$fix is not an open project-command or requirement fix"
  for f in "$@"; do
    f="${f#./}"
    case "/$f/" in /.vbw/* | */../*) vbw_die "$f: .vbw/ and paths outside the project cannot be committed by a fix" ;; esac
    [ -z "$req" ] && continue
    printf '%s' "$record" | jq -e --arg q "$req" --arg p "$f" 'any(.checks[]; .req == $q and any(.files[]?; . == $p))' > /dev/null && continue
    local other
    other=$(printf '%s' "$record" | jq -r --arg q "$req" --arg p "$f" '[.checks[] | select(.req != $q and any(.files[]?; . == $p)) | .req] | unique | join(", ")')
    if [ -n "$other" ]; then
      vbw_die "$f is a check file of $other, not of $req, the requirement $fix is about: it is not this fix's to commit"
    fi
    vbw_die "$f is not a check file of $req, the requirement $fix is about (a requirement with no check file has none to commit): commit code through its plan (vbw commit PLAN MESSAGE), new test files through vbw fix check first"
  done
  cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
  record_lock
  vbw_commit_paths "$msg" "VBW-Fix: $fix${req:+
VBW-Req: $req}" "$@" || vbw_die "nothing to commit for $fix: none of the named files changed"
  record_unlock
  vbw_commits_say "$fix"
}

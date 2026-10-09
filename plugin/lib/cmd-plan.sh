#!/usr/bin/env bash
# vbw plan done|block|reset ID: a plan's outcome (docs/workflows.md). "done" is
# verified, not claimed: the plan has a commit carrying its VBW-Plan trailer (or
# all its files are committed in HEAD and a check of its requirements passes),
# none of its files has uncommitted changes, and the checks of every requirement
# it completes (no other open plan serves it) pass. "block" refuses a done plan.

cmd_plan() {
  local sub="${1:-}" id="${2:-}"
  case "$sub" in
    done|reset) [ $# -eq 2 ] || vbw_usage_error "usage: vbw plan $sub ID" ;;
    block) [ $# -eq 3 ] && [ -n "$3" ] || vbw_usage_error "usage: vbw plan block ID REASON" ;;
    *) vbw_usage_error "usage: vbw plan done ID | block ID REASON | reset ID" ;;
  esac
  vbw_require_project
  local record
  record=$(record_read)
  printf '%s' "$record" | jq -e --arg p "$id" 'any(.plans[]; .id == $p)' > /dev/null || vbw_die "unknown plan $id"
  case "$sub" in
    done)
      local files=() completes=() f dirty trailer=0
      while IFS= read -r -d '' f; do files+=("$f"); done \
        < <(printf '%s' "$record" | jq -j --arg p "$id" '.plans[] | select(.id == $p) | .files[] | . + "\u0000"')
      dirty=$(vbw_dirty_files "${files[@]}")
      [ -z "$dirty" ] || vbw_die "$id has uncommitted changes in: $dirty"
      if plan_has_commit "$id"; then trailer=1; else
        # Work committed some other way (the approval commit, a plain commit):
        # every file must be tracked in HEAD, and a check must prove it below.
        [ ${#files[@]} -gt 0 ] || vbw_die "$id has no commit yet: commit its work with vbw commit $id \"type(scope): ...\""
        for f in "${files[@]}"; do
          [ -n "$(git -C "$VBW_ROOT" ls-tree -r --name-only -z HEAD -- "$f" 2> /dev/null | tr -d '\0')" ] \
            || vbw_die "$id has no commit yet: $f is not committed (commit it with vbw commit $id \"type(scope): ...\")"
        done
      fi
      # The checks of every requirement this plan completes (no other open
      # plan serves it) must pass now.
      while IFS= read -r f; do [ -n "$f" ] && completes+=("$f"); done < <(printf '%s' "$record" | jq -r --arg p "$id" '
        . as $r | (.plans[] | select(.id == $p)) as $pl
        | $pl.reqs[] as $q
        | select(all($r.plans[]; .id == $p or .status == "done" or (any(.reqs[]; . == $q) | not)))
        | $r.checks[] | select(.req == $q) | .id')
      # shellcheck source=checks.sh
      . "$VBW_LIB/checks.sh"
      if [ "$trailer" -eq 0 ]; then
        # Without a trailer, the plan's own requirements need a passing check.
        local own=()
        while IFS= read -r f; do [ -n "$f" ] && own+=("$f"); done < <(printf '%s' "$record" | jq -r --arg p "$id" '
          . as $r | (.plans[] | select(.id == $p)) as $pl | $r.checks[] | select(.req as $q | $pl.reqs | any(. == $q)) | .id')
        [ ${#own[@]} -gt 0 ] || vbw_die "$id has no commit with its trailer and no check of its requirements to prove its committed files"
        checks_must_pass "$record" "$id is committed but its checks do not pass" "${own[@]}"
      fi
      checks_must_pass "$record" "$id completes requirements whose checks do not pass" ${completes[@]+"${completes[@]}"}
      record_update '(.plans[] | select(.id == $p)) |= (.status = "done" | del(.note))' --arg p "$id"
      printf '%s done\n' "$id"
      ;;
    block)
      printf '%s' "$record" | jq -e --arg p "$id" 'any(.plans[]; .id == $p and .status == "done") | not' > /dev/null \
        || vbw_die "$id is already done: a finished plan cannot be blocked (vbw plan reset $id first if it must be built again)"
      # A blocked Dev raises the plan's phase one step, in the same update.
      record_update "$VBW_JQ_DEFS"'(.plans[] | select(.id == $p)) as $pl
        | (.plans[] | select(.id == $p)) |= (.status = "blocked" | .note = $why)
        | escalate_phases([$pl.phase]; null; "Dev blocked \($p): \($why)"; $at)' \
        --arg p "$id" --arg why "$3" --arg at "$(vbw_now)"
      printf '%s blocked: %s\n' "$id" "$3"
      ;;
    reset)
      record_update '(.plans[] | select(.id == $p)) |= (.status = "planned" | del(.note))' --arg p "$id"
      printf '%s planned\n' "$id"
      ;;
  esac
}

# True when some commit carries "VBW-Plan: ID" (an exact token).
plan_has_commit() {
  local line
  while IFS= read -r line; do
    [ "$line" = "$1" ] && return 0
  done < <(git -C "$VBW_ROOT" log --format='%(trailers:key=VBW-Plan,valueonly)' 2> /dev/null)
  return 1
}

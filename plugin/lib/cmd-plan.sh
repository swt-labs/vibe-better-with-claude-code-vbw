#!/usr/bin/env bash
# vbw plan done|block|reset ID: a plan's outcome (docs/workflows.md). "done" is
# verified, not claimed: the plan has a commit carrying its VBW-Plan trailer,
# none of its files has uncommitted changes, and the checks of every requirement
# it completes (no other open plan serves it) pass.

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
      plan_has_commit "$id" || vbw_die "$id has no commit yet: commit its work with vbw commit $id \"type(scope): ...\""
      local dirty completes=() c results
      dirty=$(plan_dirty_files "$record" "$id")
      [ -z "$dirty" ] || vbw_die "$id has uncommitted changes in: $dirty"
      # The checks of every requirement this plan completes (no other open
      # plan serves it) must pass now.
      while IFS= read -r c; do [ -n "$c" ] && completes+=("$c"); done < <(printf '%s' "$record" | jq -r --arg p "$id" '
        . as $r | (.plans[] | select(.id == $p)) as $pl
        | $pl.reqs[] as $q
        | select(all($r.plans[]; .id == $p or .status == "done" or (any(.reqs[]; . == $q) | not)))
        | $r.checks[] | select(.req == $q) | .id')
      if [ ${#completes[@]} -gt 0 ]; then
        cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
        # shellcheck source=checks.sh
        . "$VBW_LIB/checks.sh"
        checks_begin "$record"
        results=$(checks_run_all "$record" "${completes[@]}")
        checks_end
        printf '%s' "$results" | jq -e 'all(.[]; .status == "pass")' > /dev/null \
          || vbw_die "$id completes requirements whose checks do not pass: $(printf '%s' "$results" \
               | jq -r '[to_entries[] | select(.value.status != "pass") | "\(.key) \(.value.status)"] | join(", ")')"
      fi
      record_update '(.plans[] | select(.id == $p)) |= (.status = "done" | del(.note))' --arg p "$id"
      printf '%s done\n' "$id"
      ;;
    block)
      record_update '(.plans[] | select(.id == $p)) |= (.status = "blocked" | .note = $why)' --arg p "$id" --arg why "$3"
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

# The plan's files that differ from HEAD or are new, comma-separated.
plan_dirty_files() {
  local files=() f out=""
  while IFS= read -r -d '' f; do files+=("$f"); done \
    < <(printf '%s' "$1" | jq -j --arg p "$2" '.plans[] | select(.id == $p) | .files[] | . + "\u0000"')
  [ ${#files[@]} -gt 0 ] || return 0
  while IFS= read -r -d '' f; do out="$out${out:+, }$f"; done \
    < <(cd "$VBW_ROOT" && { git diff --name-only -z HEAD -- "${files[@]}"; git ls-files -z --others --exclude-standard -- "${files[@]}"; })
  printf '%s' "$out"
}

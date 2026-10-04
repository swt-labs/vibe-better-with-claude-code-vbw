#!/usr/bin/env bash
# vbw fix done ID [ID...] | retry ID (docs/proof.md). "done" is verified, not claimed:
# for a requirement's fix, none of the files it may touch has uncommitted
# changes, and the checks of every finished requirement served by those files
# pass now (one that already passed on the same committed files under the same
# approved contract is not rerun), so a fix cannot quietly break other work. Then, for a requirement
# proved by checks, or a project command, it awaits proof: the next vbw prove
# closes it or counts a failed attempt. For a [human] requirement no check can
# decide, so the fix closes and the requirement returns to the user for
# acceptance. `retry` reopens an escalated fix for one more attempt (the user's
# decision at the cap; a further failure escalates again). Several fixes close in
# one command: the checks they serve run once (their union), a failing check
# fails only the fixes it serves, and a fix that cannot close is named while the
# others still close; the exit code is non-zero when any could not.

# cmd_fix_files RECORD ID: the files the fix's requirement may touch, NUL-separated.
cmd_fix_files() {
  printf '%s' "$1" | jq -j --arg f "$2" '
    [.fixes[] | select(.id == $f)][0].req as $q
    | select($q != null) | [.plans[] | select(any(.reqs[]; . == $q)) | .files[]] | unique[] | . + "\u0000"'
}

# cmd_fix_checks RECORD ID: the checks of the finished requirements the fix's files serve.
cmd_fix_checks() {
  local files=() f
  while IFS= read -r -d '' f; do files+=("$f"); done < <(cmd_fix_files "$1" "$2")
  printf '%s' "$1" | jq -r --argjson files \
    "$(printf '%s\n' ${files[@]+"${files[@]}"} | jq -R . | jq -sc 'map(select(length > 0))')" '
    . as $r
    | [.requirements[] | .id as $q | [$r.plans[] | select(any(.reqs[]; . == $q))] as $ps
       | select(($ps | length) > 0 and all($ps[]; .status == "done")
                and any($ps[].files[]; . as $x | any($files[]; . == $x))) | $q] as $reqs
    | .checks[] | select(.req as $q | any($reqs[]; . == $q)) | .id'
}

cmd_fix() {
  local mode="${1:-}"
  { [ "$mode" = "done" ] && [ $# -ge 2 ]; } || { [ "$mode" = retry ] && [ $# -eq 2 ]; } \
    || vbw_usage_error "usage: vbw fix done ID [ID...] | fix retry ID"
  shift
  vbw_require_project
  local record id
  record=$(record_read)
  if [ "$mode" = retry ]; then
    id="$1"
    printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f)' > /dev/null || vbw_die "unknown fix $id"
    # The user decides to try again after the cap: one more attempt.
    printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f and .status == "escalated")' > /dev/null \
      || vbw_die "$id is not escalated"
    record_update '(.fixes[] | select(.id == $f)).status = "open"' --arg f "$id"
    printf '%s reopened for one more attempt\n' "$id"
    return 0
  fi

  # Each named fix is judged alone: unknown, not open and dirty fixes are named
  # and left out; the rest are candidates.
  local ids=() bad=0 dirty f seen=" "
  local fl=()
  for id in "$@"; do
    case "$seen" in *" $id "*) continue ;; esac
    seen="$seen$id "
    if ! printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f)' > /dev/null; then
      printf 'vbw: unknown fix %s\n' "$id" >&2
      bad=1
      continue
    fi
    if ! printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f and .status == "open")' > /dev/null; then
      printf 'vbw: %s is not open\n' "$id" >&2
      bad=1
      continue
    fi
    fl=()
    while IFS= read -r -d '' f; do fl+=("$f"); done < <(cmd_fix_files "$record" "$id")
    dirty=$(vbw_dirty_files ${fl[@]+"${fl[@]}"})
    if [ -n "$dirty" ]; then
      printf 'vbw: %s has uncommitted changes in: %s (commit them with vbw commit PLAN "fix(scope): ...")\n' "$id" "$dirty" >&2
      bad=1
      continue
    fi
    ids+=("$id")
  done

  # The union of the served checks runs once; a pass on unchanged files is reused.
  # shellcheck source=checks.sh
  . "$VBW_LIB/checks.sh"
  local union=() todo=() c at results='{}'
  for id in ${ids[@]+"${ids[@]}"}; do
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      case " ${union[*]-} " in *" $c "*) ;; *) union+=("$c") ;; esac
    done < <(cmd_fix_checks "$record" "$id")
  done
  for c in ${union[@]+"${union[@]}"}; do
    if at=$(checks_unchanged "$record" "$c"); then
      printf '%s unchanged since its pass (%s)\n' "$c" "$at"
    else
      todo+=("$c")
    fi
  done
  if [ ${#todo[@]} -gt 0 ]; then
    cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
    checks_begin "$record"
    results=$(checks_run_all "$record" "${todo[@]}")
    checks_end
    checks_record_passes "$record" "$results" "$CHECK_HASH"
  fi

  # Each fix ends as it would alone; a failing check fails only the fixes it serves.
  local closed=() mine failed human fixed='[]' humans='[]'
  for id in ${ids[@]+"${ids[@]}"}; do
    mine=$(cmd_fix_checks "$record" "$id" | jq -R . | jq -sc 'map(select(length > 0))')
    failed=$(printf '%s' "$results" | jq -r --argjson mine "$mine" \
      '[to_entries[] | select(.value.status != "pass" and (.key as $k | $mine | index($k))) | "\(.key) \(.value.status)"] | join(", ")')
    if [ -n "$failed" ]; then
      printf 'vbw: %s broke finished work: these checks of requirements its files serve do not pass: %s\n' "$id" "$failed" >&2
      bad=1
      continue
    fi
    human=$(printf '%s' "$record" | jq -r --arg f "$id" '. as $r | [.fixes[] | select(.id == $f)][0] as $x
      | any($r.requirements[]; .id == $x.req and .proof == "human")')
    if [ "$human" = true ]; then
      humans=$(printf '%s' "$humans" | jq -c --arg f "$id" '. + [$f]')
    else
      fixed=$(printf '%s' "$fixed" | jq -c --arg f "$id" '. + [$f]')
    fi
    closed+=("$id")
  done
  if [ ${#closed[@]} -gt 0 ]; then
    record_update '. as $r | (.fixes[] | select(.id as $i | $fixed | index($i))).status = "fixed"
      | (.fixes[] | select(.id as $i | $humans | index($i))).status = "closed"
      | (.requirements[] | select(.id as $q | any($r.fixes[]; (.id as $i | $humans | index($i)) and .req == $q))).status = "open"' \
      --argjson fixed "$fixed" --argjson humans "$humans"
    for id in "${closed[@]}"; do
      if printf '%s' "$humans" | jq -e --arg f "$id" 'index($f)' > /dev/null; then
        printf '%s closed: its requirement goes back to the user for acceptance\n' "$id"
      else
        printf '%s fixed: vbw prove decides\n' "$id"
      fi
    done
  fi
  return "$bad"
}

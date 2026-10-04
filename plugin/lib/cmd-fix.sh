#!/usr/bin/env bash
# vbw fix done ID | retry ID (docs/proof.md). "done" is verified, not claimed:
# for a requirement's fix, none of the files it may touch has uncommitted
# changes, and the checks of every finished requirement served by those files
# pass now (one that already passed on the same committed files under the same
# approved contract is not rerun), so a fix cannot quietly break other work. Then, for a requirement
# proved by checks, or a project command, it awaits proof: the next vbw prove
# closes it or counts a failed attempt. For a [human] requirement no check can
# decide, so the fix closes and the requirement returns to the user for
# acceptance. `retry` reopens an escalated fix for one more attempt (the user's
# decision at the cap; a further failure escalates again).

cmd_fix() {
  [ $# -eq 2 ] && { [ "$1" = "done" ] || [ "$1" = retry ]; } || vbw_usage_error "usage: vbw fix done ID | fix retry ID"
  local id="$2" record human
  vbw_require_project
  record=$(record_read)
  printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f)' > /dev/null || vbw_die "unknown fix $id"
  if [ "$1" = retry ]; then
    # The user decides to try again after the cap: one more attempt.
    printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f and .status == "escalated")' > /dev/null \
      || vbw_die "$id is not escalated"
    record_update '(.fixes[] | select(.id == $f)).status = "open"' --arg f "$id"
    printf '%s reopened for one more attempt\n' "$id"
    return 0
  fi
  printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f and .status == "open")' > /dev/null \
    || vbw_die "$id is not open"

  local files=() checks=() f dirty
  while IFS= read -r -d '' f; do files+=("$f"); done < <(printf '%s' "$record" | jq -j --arg f "$id" '
    [.fixes[] | select(.id == $f)][0].req as $q
    | select($q != null) | [.plans[] | select(any(.reqs[]; . == $q)) | .files[]] | unique[] | . + "\u0000"')
  dirty=$(vbw_dirty_files ${files[@]+"${files[@]}"})
  [ -z "$dirty" ] || vbw_die "$id has uncommitted changes in: $dirty (commit them with vbw commit PLAN \"fix(scope): ...\")"
  while IFS= read -r f; do [ -n "$f" ] && checks+=("$f"); done < <(printf '%s' "$record" | jq -r --argjson files \
    "$(printf '%s\n' ${files[@]+"${files[@]}"} | jq -R . | jq -sc 'map(select(length > 0))')" '
    . as $r
    | [.requirements[] | .id as $q | [$r.plans[] | select(any(.reqs[]; . == $q))] as $ps
       | select(($ps | length) > 0 and all($ps[]; .status == "done")
                and any($ps[].files[]; . as $x | any($files[]; . == $x))) | $q] as $reqs
    | .checks[] | select(.req as $q | any($reqs[]; . == $q)) | .id')
  # shellcheck source=checks.sh
  . "$VBW_LIB/checks.sh"
  local todo=() at
  for f in ${checks[@]+"${checks[@]}"}; do
    if at=$(checks_unchanged "$record" "$f"); then
      printf '%s unchanged since its pass (%s)\n' "$f" "$at"
    else
      todo+=("$f")
    fi
  done
  checks_must_pass "$record" "$id broke finished work: these checks of requirements its files serve do not pass" \
    ${todo[@]+"${todo[@]}"}

  human=$(printf '%s' "$record" | jq -r --arg f "$id" '. as $r | [.fixes[] | select(.id == $f)][0] as $x
    | any($r.requirements[]; .id == $x.req and .proof == "human")')
  if [ "$human" = true ]; then
    record_update '[.fixes[] | select(.id == $f)][0].req as $q
      | (.fixes[] | select(.id == $f)).status = "closed"
      | (.requirements[] | select(.id == $q)).status = "open"' --arg f "$id"
    printf '%s closed: its requirement goes back to the user for acceptance\n' "$id"
  else
    record_update '(.fixes[] | select(.id == $f)).status = "fixed"' --arg f "$id"
    printf '%s fixed: vbw prove decides\n' "$id"
  fi
}
